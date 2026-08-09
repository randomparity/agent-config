'use strict';

const assert = require('assert').strict;
const crypto = require('crypto');
const fs = require('fs');
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
