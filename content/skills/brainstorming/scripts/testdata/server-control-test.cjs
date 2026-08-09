'use strict';

const assert = require('assert').strict;
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

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

  await test('control listener validates identity and transitions only once', async () => {
    let releaseClose;
    let closeCalls = 0;
    const closeGate = new Promise((resolve) => { releaseClose = resolve; });
    const token = 'c'.repeat(64);
    const server = control.createControlServer({
      token,
      pid: process.pid,
      serverId: 'd'.repeat(32),
      closeUserListener: async () => {
        closeCalls += 1;
        await closeGate;
      }
    });
    const port = await listen(server);
    const wrong = await post(port, token, {
      pid: process.pid + 1,
      server_id: 'd'.repeat(32)
    });
    assert.equal(wrong.statusCode, 403);
    assert.equal(closeCalls, 0);
    const firstPromise = post(port, token, {
      pid: process.pid,
      server_id: 'd'.repeat(32)
    });
    await new Promise((resolve) => setTimeout(resolve, 20));
    const retry = await post(port, token, {
      pid: process.pid,
      server_id: 'd'.repeat(32)
    });
    assert.equal(retry.body.status, 'stopping');
    assert.equal(closeCalls, 1);
    releaseClose();
    const first = await firstPromise;
    assert.equal(first.body.status, 'stopped');
    await close(server);
  });

  await test('bounded client authenticates against a real control listener', async () => {
    const token = 'e'.repeat(64);
    const server = control.createControlServer({
      token,
      pid: process.pid,
      serverId: 'f'.repeat(32),
      closeUserListener: async () => {}
    });
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

  await test('Linux argv matching preserves NUL boundaries with or without a final NUL', () => {
    const serverId = 'a'.repeat(32);
    const expected = `--brainstorm-server-id=${serverId}`;
    assert.equal(control.hasExactServerArgument(Buffer.from(`node\0${expected}\0`), serverId), true);
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

  process.stdout.write(`\n${passed} passed, 0 failed\n`);
}

main()
  .finally(() => {
    for (const cleanup of cleanups.reverse()) cleanup();
  })
  .catch((error) => {
    process.stderr.write(`${error.stack}\n`);
    process.exitCode = 1;
  });
