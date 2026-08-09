'use strict';

const assert = require('assert').strict;
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn, spawnSync } = require('child_process');

const CONTROL_PATH = path.join(__dirname, '..', 'server-control.cjs');
const control = require(CONTROL_PATH);

let passed = 0;
const cleanups = [];

function temporaryDirectory(prefix = 'brainstorm-control-test-') {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  cleanups.push(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

async function test(name, body) {
  try {
    await body();
    passed += 1;
    process.stdout.write(`  ok   ${name}\n`);
  } catch (error) {
    error.message = `${name}: ${error.message}`;
    throw error;
  }
}

function validRecord(overrides = {}) {
  return {
    version: 1,
    pid: process.pid,
    server_id: 'a'.repeat(32),
    session_dir: '/tmp/brainstorm-control-test',
    project_key: null,
    control_port: 49152,
    control_token: 'b'.repeat(64),
    ...overrides
  };
}

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.removeListener('error', reject);
      resolve(server.address().port);
    });
  });
}

function close(server) {
  return new Promise((resolve) => server.close(resolve));
}

function trackedServer(server) {
  cleanups.push(async () => {
    if (server.listening) await close(server);
  });
  return server;
}

function post(port, token, body) {
  return new Promise((resolve, reject) => {
    const bytes = Buffer.from(JSON.stringify(body));
    const request = http.request({
      host: '127.0.0.1',
      port,
      method: 'POST',
      path: '/stop',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
        'content-length': bytes.length
      }
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        resolve({ statusCode: response.statusCode, body: JSON.parse(Buffer.concat(chunks)) });
      });
    });
    request.on('error', reject);
    request.end(bytes);
  });
}

function writeAndWaitForClose(port, bytes, timeoutMs = 2000) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host: '127.0.0.1', port });
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error('peer close timeout'));
    }, timeoutMs);
    socket.on('connect', () => socket.write(bytes));
    socket.on('close', () => {
      clearTimeout(timer);
      resolve();
    });
    socket.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

function runControlCli(command, input, environment) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [CONTROL_PATH, command], {
      env: { ...process.env, ...environment }
    });
    const output = [];
    const errors = [];
    child.stdout.on('data', (chunk) => output.push(chunk));
    child.stderr.on('data', (chunk) => errors.push(chunk));
    child.on('error', reject);
    child.on('exit', (exitCode) => resolve({
      exitCode,
      stdout: Buffer.concat(output).toString('utf8'),
      stderr: Buffer.concat(errors).toString('utf8')
    }));
    child.stdin.end(input);
  });
}

async function main() {
  process.stdout.write('server-control.cjs\n\n');

  await test('control token uses exactly 32 cryptographic bytes', () => {
    let requested = 0;
    const token = control.createControlToken((size) => {
      requested = size;
      return Buffer.alloc(size, 0xab);
    });
    assert.equal(requested, 32);
    assert.equal(token, 'ab'.repeat(32));
  });

  await test('project identity accepts 4096 bytes and preserves trailing newline', () => {
    const identity = Buffer.concat([Buffer.alloc(4095, 0x61), Buffer.from('\n')]);
    assert.equal(Buffer.byteLength(control.readProjectIdentity(identity)), 4096);
    assert.throws(
      () => control.readProjectIdentity(Buffer.alloc(4097, 0x61)),
      /4096 bytes/
    );
  });

  await test('project identity rejects NUL and invalid UTF-8', () => {
    assert.throws(() => control.readProjectIdentity(Buffer.from('a\0b')), /NUL/);
    assert.throws(() => control.readProjectIdentity(Buffer.from([0xc3, 0x28])), /UTF-8/);
  });

  await test('project keys distinguish a trailing newline', () => {
    const home = temporaryDirectory();
    const plain = control.projectStateFor('/tmp/project', home);
    const newline = control.projectStateFor('/tmp/project\n', home);
    assert.notEqual(plain.projectKey, newline.projectKey);
    assert.equal(
      plain.projectKey,
      crypto.createHash('sha256').update('/tmp/project').digest('hex')
    );
  });

  await test('private state ignores XDG and creates exact application modes', () => {
    const home = temporaryDirectory();
    const worker = spawnSync(
      process.execPath,
      ['-e', `
        const control = require(${JSON.stringify(CONTROL_PATH)});
        process.stdout.write(JSON.stringify(control.projectStateFromEnvironment('/tmp/project')));
      `],
      {
        encoding: 'utf8',
        env: { ...process.env, HOME: home, XDG_STATE_HOME: path.join(home, 'elsewhere') }
      }
    );
    assert.equal(worker.status, 0, worker.stderr);
    const state = JSON.parse(worker.stdout);
    assert.equal(state.root, path.join(home, '.local', 'state', 'superpowers', 'brainstorm'));
    assert.equal(fs.statSync(state.root).mode & 0o777, 0o700);
    assert.equal(fs.statSync(path.dirname(state.root)).mode & 0o777, 0o700);
  });

  await test('HOME must be non-empty and absolute', () => {
    for (const home of ['', 'relative']) {
      const worker = spawnSync(
        process.execPath,
        ['-e', `
          const control = require(${JSON.stringify(CONTROL_PATH)});
          try { control.projectStateFromEnvironment('/tmp/project'); }
          catch (error) { process.stdout.write(error.message); process.exit(7); }
        `],
        { encoding: 'utf8', env: { ...process.env, HOME: home } }
      );
      assert.equal(worker.status, 7);
      assert.match(worker.stdout, /HOME.*absolute/);
    }
  });

  await test('stdin acquisition rejects overflow before state access', () => {
    const worker = spawnSync(
      process.execPath,
      ['-e', `
        const control = require(${JSON.stringify(CONTROL_PATH)});
        try { control.readStdinIdentity(); }
        catch (error) {
          process.stdout.write(JSON.stringify({ error: error.code }));
          process.exit(9);
        }
      `],
      { input: Buffer.alloc(1024 * 1024, 0x61), maxBuffer: 2 * 1024 * 1024 }
    );
    assert.equal(worker.status, 9);
    assert.deepEqual(JSON.parse(worker.stdout.toString()), { error: 'identity_too_large' });
  });

  await test('metadata installs at 0600 and validates a complete snapshot', () => {
    const directory = temporaryDirectory();
    const recordPath = path.join(directory, 'active.json');
    const record = validRecord();
    control.atomicInstallMetadata(recordPath, record);
    assert.equal(fs.statSync(recordPath).mode & 0o777, 0o600);
    assert.deepEqual(
      control.readMetadata(recordPath, {
        kind: 'session',
        sessionDir: record.session_dir
      }),
      { kind: 'valid', record }
    );
  });

  await test('metadata rejects unknown versions, loose modes, and oversized files', () => {
    const directory = temporaryDirectory();
    const recordPath = path.join(directory, 'active.json');
    fs.writeFileSync(recordPath, JSON.stringify(validRecord({ version: 2 })), { mode: 0o600 });
    assert.equal(control.readMetadata(recordPath, { kind: 'session' }).kind, 'invalid');
    fs.chmodSync(recordPath, 0o640);
    assert.equal(control.readMetadata(recordPath, { kind: 'session' }).kind, 'invalid');
    fs.chmodSync(recordPath, 0o600);
    fs.writeFileSync(recordPath, Buffer.alloc(16 * 1024 + 1, 0x61));
    assert.equal(control.readMetadata(recordPath, { kind: 'session' }).kind, 'invalid');
  });

  await test('metadata validates every numeric and credential boundary', () => {
    for (const overrides of [
      { pid: 0 },
      { pid: 2147483648 },
      { control_port: 1023 },
      { control_port: 65536 },
      { server_id: 'a'.repeat(31) },
      { server_id: 'a'.repeat(65) },
      { control_token: 'A'.repeat(64) },
      { control_token: 'b'.repeat(63) },
      { project_key: 'c'.repeat(63) },
      { session_dir: 'relative' }
    ]) {
      assert.equal(control.validateRecord(validRecord(overrides)), false);
    }
  });

  await test('private state rejects a symlinked path component', () => {
    const home = temporaryDirectory();
    const target = temporaryDirectory();
    fs.symlinkSync(target, path.join(home, '.local'));
    assert.throws(
      () => control.projectStateFor('/tmp/project', home),
      /authorize or write-enable/
    );
  });

  await test('control listener validates identity and transitions only once', async () => {
    let wrongCloseCalls = 0;
    const wrongToken = 'c'.repeat(64);
    const wrongServer = trackedServer(control.createControlServer({
      token: wrongToken,
      pid: process.pid,
      serverId: 'd'.repeat(32),
      closeUserListener: async () => { wrongCloseCalls += 1; }
    }));
    const wrongPort = await listen(wrongServer);
    const wrong = await post(wrongPort, wrongToken, {
      pid: process.pid + 1,
      server_id: 'd'.repeat(32)
    });
    const wrongCredential = await post(wrongPort, '0'.repeat(64), {
      pid: process.pid,
      server_id: 'd'.repeat(32)
    });
    const wrongId = await post(wrongPort, wrongToken, {
      pid: process.pid,
      server_id: 'x'.repeat(32)
    });
    await close(wrongServer);
    assert.equal(wrong.statusCode, 403);
    assert.equal(wrongCredential.statusCode, 403);
    assert.equal(wrongId.statusCode, 403);
    assert.equal(wrongCloseCalls, 0);

    let releaseClose;
    let closeCalls = 0;
    const closeGate = new Promise((resolve) => { releaseClose = resolve; });
    const token = 'e'.repeat(64);
    const server = trackedServer(control.createControlServer({
      token,
      pid: process.pid,
      serverId: 'f'.repeat(32),
      closeUserListener: async () => {
        closeCalls += 1;
        await closeGate;
      }
    }));
    const port = await listen(server);
    assert.equal(server.address().address, '127.0.0.1');
    const firstPromise = post(port, token, {
      pid: process.pid,
      server_id: 'f'.repeat(32)
    });
    await new Promise((resolve) => setTimeout(resolve, 20));
    const retry = await post(port, token, {
      pid: process.pid,
      server_id: 'f'.repeat(32)
    });
    assert.equal(retry.body.status, 'stopping');
    assert.equal(closeCalls, 1);
    releaseClose();
    const first = await firstPromise;
    assert.equal(first.body.status, 'stopped');
    await close(server);
  });

  await test('authenticated disconnect still reaches one terminal transition', async () => {
    let releaseClose;
    let enteredClose;
    const closeEntered = new Promise((resolve) => { enteredClose = resolve; });
    const closeGate = new Promise((resolve) => { releaseClose = resolve; });
    const token = '9'.repeat(64);
    const server = trackedServer(control.createControlServer({
      token,
      pid: process.pid,
      serverId: '8'.repeat(32),
      closeUserListener: async () => {
        enteredClose();
        await closeGate;
      }
    }));
    let terminalCount = 0;
    const terminal = new Promise((resolve) => {
      server.on('terminal', (outcome) => {
        terminalCount += 1;
        resolve(outcome);
      });
    });
    const port = await listen(server);
    const bytes = Buffer.from(JSON.stringify({
      pid: process.pid,
      server_id: '8'.repeat(32)
    }));
    const request = http.request({
      host: '127.0.0.1',
      port,
      method: 'POST',
      path: '/stop',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
        'content-length': bytes.length
      }
    });
    request.on('error', () => {});
    request.end(bytes);
    await closeEntered;
    request.destroy();
    await new Promise((resolve) => setTimeout(resolve, 20));
    releaseClose();
    const outcome = await Promise.race([
      terminal,
      new Promise((_, reject) => setTimeout(() => reject(new Error('terminal timeout')), 500))
    ]);
    assert.equal(outcome.status, 'stopped');
    assert.equal(terminalCount, 1);
    await close(server);
  });

  await test('control listener closes oversized and incomplete request bodies', async () => {
    let closeCalls = 0;
    const server = trackedServer(control.createControlServer({
      token: '7'.repeat(64),
      pid: process.pid,
      serverId: '6'.repeat(32),
      closeUserListener: async () => { closeCalls += 1; }
    }));
    const port = await listen(server);
    const oversizedHead = Buffer.from([
      'POST /stop HTTP/1.1',
      'Host: 127.0.0.1',
      `Content-Length: ${control.CONTROL_LIMITS.requestBytes + 1}`,
      '',
      ''
    ].join('\r\n'));
    await writeAndWaitForClose(port, Buffer.concat([
      oversizedHead,
      Buffer.alloc(control.CONTROL_LIMITS.requestBytes + 1, 0x61)
    ]));
    const incomplete = Buffer.from([
      'POST /stop HTTP/1.1',
      'Host: 127.0.0.1',
      'Content-Length: 2',
      '',
      '{'
    ].join('\r\n'));
    await writeAndWaitForClose(port, incomplete);
    assert.equal(closeCalls, 0);
    await close(server);
  });

  await test('bounded client authenticates against a real control listener', async () => {
    const token = 'e'.repeat(64);
    const server = trackedServer(control.createControlServer({
      token,
      pid: process.pid,
      serverId: 'f'.repeat(32),
      closeUserListener: async () => {}
    }));
    const port = await listen(server);
    const outcome = await control.requestAuthenticatedStop(validRecord({
      pid: process.pid,
      server_id: 'f'.repeat(32),
      control_port: port,
      control_token: token
    }));
    assert.deepEqual(outcome, { status: 'stopped' });
    await close(server);
  });

  await test('client rejects non-success and oversized control responses', async () => {
    assert.equal(Object.isFrozen(control.CONTROL_LIMITS), true);
    assert.equal(control.CONTROL_LIMITS.connectTimeoutMs, 500);

    const rejectedServer = trackedServer(http.createServer((_request, response) => {
      response.writeHead(500, { 'content-type': 'application/json' });
      response.end('{"status":"stopped"}\n');
    }));
    const rejectedPort = await listen(rejectedServer);
    const rejected = await control.requestAuthenticatedStop(validRecord({
      control_port: rejectedPort
    }));
    await close(rejectedServer);
    assert.deepEqual(rejected, { status: 'failed', reason: 'http_500' });

    const oversizedServer = trackedServer(http.createServer((_request, response) => {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(Buffer.alloc(control.CONTROL_LIMITS.responseBytes + 1, 0x61));
    }));
    const oversizedPort = await listen(oversizedServer);
    const oversized = await control.requestAuthenticatedStop(validRecord({
      control_port: oversizedPort
    }));
    await close(oversizedServer);
    assert.deepEqual(oversized, { status: 'failed', reason: 'oversized_response' });
  });

  await test('client enforces one non-resetting whole-request deadline', async () => {
    const stalledServer = trackedServer(http.createServer(() => {}));
    const port = await listen(stalledServer);
    const started = Date.now();
    const outcome = await control.requestAuthenticatedStop(validRecord({
      control_port: port
    }));
    const elapsed = Date.now() - started;
    assert.deepEqual(outcome, { status: 'failed', reason: 'deadline' });
    assert.ok(elapsed >= 2800, `deadline fired early after ${elapsed}ms`);
    assert.ok(elapsed < 4000, `deadline fired late after ${elapsed}ms`);
    await close(stalledServer);
  });

  await test('Linux argv matching preserves NUL boundaries with or without a final NUL', () => {
    const serverId = 'a'.repeat(32);
    const expected = `--brainstorm-server-id=${serverId}`;
    assert.equal(
      control.hasExactServerArgument(Buffer.from(`node\0${expected}\0`), serverId),
      true
    );
    assert.equal(control.hasExactServerArgument(Buffer.from(`node\0${expected}`), serverId), true);
    assert.equal(
      control.hasExactServerArgument(Buffer.from(`node\0prefix-${expected}-suffix\0`), serverId),
      false
    );
  });

  await test('publisher installs stable metadata before session recovery metadata', () => {
    const home = temporaryDirectory();
    const project = temporaryDirectory();
    const session = path.join(project, '.agent', 'brainstorm', 'session');
    fs.mkdirSync(path.join(session, 'state'), { recursive: true, mode: 0o700 });
    const previousHome = process.env.HOME;
    process.env.HOME = home;
    try {
      const published = control.publishActiveRecords({
        projectDir: project,
        sessionDir: session,
        pid: process.pid,
        serverId: '1'.repeat(32),
        controlPort: 49153,
        controlToken: '2'.repeat(64)
      });
      assert.equal(fs.existsSync(published.stableRecordPath), true);
      assert.equal(fs.existsSync(published.sessionRecordPath), true);
      assert.equal(
        control.readMetadata(published.stableRecordPath, {
          kind: 'stable',
          projectKey: published.projectKey
        }).kind,
        'valid'
      );
    } finally {
      if (previousHome === undefined) delete process.env.HOME;
      else process.env.HOME = previousHome;
    }
  });

  await test('publisher preserves stable metadata when session publication fails', () => {
    const home = temporaryDirectory();
    const project = temporaryDirectory();
    const missingSession = path.join(project, '.agent', 'brainstorm', 'missing');
    const previousHome = process.env.HOME;
    process.env.HOME = home;
    try {
      assert.throws(() => control.publishActiveRecords({
        projectDir: project,
        sessionDir: missingSession,
        pid: process.pid,
        serverId: '3'.repeat(32),
        controlPort: 49154,
        controlToken: '4'.repeat(64)
      }), /ENOENT/);
      const stable = control.projectStateFor(project, home).recordPath;
      assert.equal(control.readMetadata(stable).kind, 'valid');
      assert.deepEqual(
        fs.readdirSync(path.dirname(stable)).filter((name) => name.includes('.tmp-')),
        []
      );
    } finally {
      if (previousHome === undefined) delete process.env.HOME;
      else process.env.HOME = previousHome;
    }
  });

  await test('replacement recovers a live stable-only publication', async () => {
    const home = temporaryDirectory();
    const project = temporaryDirectory();
    const missingSession = path.join(project, '.agent', 'brainstorm', 'missing');
    let closeCalls = 0;
    const token = '1'.repeat(64);
    const serverId = '0'.repeat(32);
    const server = trackedServer(control.createControlServer({
      token,
      pid: process.pid,
      serverId,
      closeUserListener: async () => { closeCalls += 1; }
    }));
    server.on('terminal', () => server.close());
    const port = await listen(server);
    const previousHome = process.env.HOME;
    process.env.HOME = home;
    try {
      assert.throws(() => control.publishActiveRecords({
        projectDir: project,
        sessionDir: missingSession,
        pid: process.pid,
        serverId,
        controlPort: port,
        controlToken: token
      }), /ENOENT/);
      const result = await runControlCli('replace-project', project, { HOME: home });
      assert.equal(result.exitCode, 0, result.stderr);
      assert.equal(JSON.parse(result.stdout).status, 'handled');
      assert.equal(closeCalls, 1);
      assert.equal(control.readMetadata(control.projectStateFor(project, home).recordPath).kind,
        'missing');
    } finally {
      process.env.HOME = previousHome;
      if (server.listening) await close(server);
    }
  });

  await test('metadata rejects a symlink recovery copy without following it', () => {
    const directory = temporaryDirectory();
    const target = path.join(directory, 'target.json');
    const link = path.join(directory, 'server-control.json');
    fs.writeFileSync(target, JSON.stringify(validRecord()), { mode: 0o600 });
    fs.symlinkSync(target, link);
    assert.equal(control.readMetadata(link).kind, 'invalid');
  });

  await test('session project-key mismatches send no control request', async () => {
    let requestCount = 0;
    const peer = trackedServer(http.createServer((_request, response) => {
      requestCount += 1;
      response.writeHead(403, { 'content-type': 'application/json' });
      response.end('{"status":"failed","reason":"identity_mismatch"}\n');
    }));
    const port = await listen(peer);
    const home = temporaryDirectory();
    const previousHome = process.env.HOME;
    process.env.HOME = home;
    const ephemeral = fs.realpathSync(fs.mkdtempSync('/tmp/brainstorm-key-test-'));
    cleanups.push(() => fs.rmSync(ephemeral, { recursive: true, force: true }));
    const project = temporaryDirectory();
    const persistent = path.join(project, '.agent', 'brainstorm', 'session');
    try {
      for (const [session, projectKey] of [
        [ephemeral, 'a'.repeat(64)],
        [persistent, 'b'.repeat(64)]
      ]) {
        fs.mkdirSync(path.join(session, 'state'), { recursive: true, mode: 0o700 });
        control.atomicInstallMetadata(path.join(session, 'state', 'server-control.json'),
          validRecord({
            session_dir: session,
            project_key: projectKey,
            control_port: port
          }));
        await control.stopSession(session);
      }
      assert.equal(requestCount, 0);
    } finally {
      process.env.HOME = previousHome;
      await close(peer);
    }
  });

  await test('successful stop cannot remove a newer stable record', async () => {
    const home = temporaryDirectory();
    const project = temporaryDirectory();
    const session = path.join(project, '.agent', 'brainstorm', 'session');
    fs.mkdirSync(path.join(session, 'state'), { recursive: true, mode: 0o700 });
    const previousHome = process.env.HOME;
    process.env.HOME = home;
    const token = '5'.repeat(64);
    const serverId = '4'.repeat(32);
    const server = trackedServer(control.createControlServer({
      token,
      pid: process.pid,
      serverId,
      closeUserListener: async () => {}
    }));
    server.on('terminal', () => server.close());
    const port = await listen(server);
    try {
      const published = control.publishActiveRecords({
        projectDir: project,
        sessionDir: session,
        pid: process.pid,
        serverId,
        controlPort: port,
        controlToken: token
      });
      const newer = validRecord({
        pid: process.pid + 1,
        server_id: '3'.repeat(32),
        session_dir: session,
        project_key: published.projectKey,
        control_port: port,
        control_token: '2'.repeat(64)
      });
      control.atomicInstallMetadata(published.stableRecordPath, newer);
      const stopped = await control.stopSession(session);
      assert.equal(stopped.body.status, 'stopped');
      assert.deepEqual(control.readMetadata(published.stableRecordPath), {
        kind: 'valid',
        record: newer
      });
    } finally {
      process.env.HOME = previousHome;
      if (server.listening) await close(server);
    }
  });

  process.stdout.write(`\n${passed} passed, 0 failed\n`);
}

main()
  .finally(async () => {
    for (const cleanup of cleanups.reverse()) await cleanup();
  })
  .catch((error) => {
    process.stderr.write(`${error.stack}\n`);
    process.exitCode = 1;
  });
