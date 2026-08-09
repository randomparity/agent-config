'use strict';

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');
const { TextDecoder } = require('util');

const MAX_IDENTITY_BYTES = 4096;
const MAX_METADATA_BYTES = 16 * 1024;
const STATE_PARTS = ['.local', 'state', 'superpowers', 'brainstorm'];
const APPLICATION_PARTS = new Set(['superpowers', 'brainstorm']);
const SERVER_ID_PATTERN = /^[A-Za-z0-9_-]{32,64}$/;
const HEX_64_PATTERN = /^[0-9a-f]{64}$/;
const NOFOLLOW = fs.constants.O_NOFOLLOW || 0;

const CONTROL_LIMITS = Object.freeze({
  connectTimeoutMs: 500,
  requestDeadlineMs: 3000,
  receiveTimeoutMs: 1000,
  requestBytes: 1024,
  responseBytes: 4096
});

class ControlError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'ControlError';
    this.code = code;
  }
}

function createControlToken(randomBytes = crypto.randomBytes) {
  const bytes = randomBytes(32);
  if (!Buffer.isBuffer(bytes) || bytes.length !== 32) {
    throw new ControlError('rng_failed', 'Control token source must return exactly 32 bytes');
  }
  return bytes.toString('hex');
}

function readStdinIdentity() {
  const input = Buffer.alloc(MAX_IDENTITY_BYTES + 1);
  let offset = 0;
  while (offset < input.length) {
    const count = fs.readSync(0, input, offset, input.length - offset, null);
    if (count === 0) break;
    offset += count;
  }
  if (offset > MAX_IDENTITY_BYTES) {
    throw new ControlError(
      'identity_too_large',
      `Canonical project identity exceeds ${MAX_IDENTITY_BYTES} bytes`
    );
  }
  return input.subarray(0, offset);
}

function decodeUtf8(input, label) {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(input);
  } catch (_error) {
    throw new ControlError('invalid_utf8', `${label} must be valid UTF-8`);
  }
}

function readProjectIdentity(input) {
  if (!Buffer.isBuffer(input)) {
    throw new ControlError('invalid_identity', 'Canonical project identity must be bytes');
  }
  if (input.length > MAX_IDENTITY_BYTES) {
    throw new ControlError(
      'identity_too_large',
      `Canonical project identity exceeds ${MAX_IDENTITY_BYTES} bytes`
    );
  }
  if (input.includes(0)) {
    throw new ControlError('identity_nul', 'Canonical project identity must not contain NUL');
  }
  return decodeUtf8(input, 'Canonical project identity');
}

function effectiveUid() {
  return typeof process.geteuid === 'function' ? process.geteuid() : null;
}

function validateDirectory(directory, exactMode) {
  const stat = fs.lstatSync(directory);
  const mode = stat.mode & 0o777;
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new Error(`${directory} must be a non-symlink directory`);
  }
  const uid = effectiveUid();
  if (uid !== null && stat.uid !== uid) {
    throw new Error(`${directory} must be owned by the effective user`);
  }
  if ((mode & 0o022) !== 0) {
    throw new Error(`${directory} must not be group/world writable`);
  }
  if (exactMode !== null && mode !== exactMode) {
    throw new Error(`${directory} must have mode ${exactMode.toString(8)}`);
  }
}

function validatedHome(home) {
  if (typeof home !== 'string' || home.length === 0 || !path.isAbsolute(home)) {
    throw new ControlError('invalid_home', 'HOME must be non-empty and absolute');
  }
  return home;
}

function ensurePrivateStateRoot(home) {
  const base = validatedHome(home);
  const fixedRoot = path.join(base, ...STATE_PARTS);
  try {
    validateDirectory(base, null);
    let current = base;
    for (const part of STATE_PARTS) {
      current = path.join(current, part);
      if (!fs.existsSync(current)) fs.mkdirSync(current, { mode: 0o700 });
      validateDirectory(current, APPLICATION_PARTS.has(part) ? 0o700 : null);
    }
    fs.accessSync(fixedRoot, fs.constants.W_OK);
    return fixedRoot;
  } catch (error) {
    throw new ControlError(
      'state_unavailable',
      `Cannot create or write ${fixedRoot}; authorize or write-enable it: ${error.message}`
    );
  }
}

function projectKeyForIdentity(identity) {
  return crypto.createHash('sha256')
    .update(Buffer.from(identity, 'utf8'))
    .digest('hex');
}

function projectStateFor(identity, home) {
  const root = ensurePrivateStateRoot(home);
  const projectKey = projectKeyForIdentity(identity);
  return { projectKey, root, recordPath: path.join(root, `${projectKey}.json`) };
}

function projectStateFromEnvironment(identity) {
  return projectStateFor(identity, process.env.HOME || '');
}

function validUtf8String(value, maxBytes) {
  if (typeof value !== 'string' || Buffer.byteLength(value, 'utf8') > maxBytes) return false;
  try {
    return decodeUtf8(Buffer.from(value, 'utf8'), 'value') === value;
  } catch (_error) {
    return false;
  }
}

function validateRecord(record) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return false;
  if (record.version !== 1) return false;
  if (!Number.isInteger(record.pid) || record.pid < 1 || record.pid > 2147483647) return false;
  if (!SERVER_ID_PATTERN.test(record.server_id)) return false;
  if (!validUtf8String(record.session_dir, MAX_IDENTITY_BYTES)) return false;
  if (!path.isAbsolute(record.session_dir)) return false;
  if (record.project_key !== null && !HEX_64_PATTERN.test(record.project_key)) return false;
  if (!Number.isInteger(record.control_port)) return false;
  if (record.control_port < 1024 || record.control_port > 65535) return false;
  return HEX_64_PATTERN.test(record.control_token);
}

function metadataInvalid(reason, pid = null) {
  return { kind: 'invalid', reason, pid };
}

function readOpenedFile(descriptor, size) {
  const output = Buffer.alloc(Math.min(size + 1, MAX_METADATA_BYTES + 1));
  let offset = 0;
  while (offset < output.length) {
    const count = fs.readSync(descriptor, output, offset, output.length - offset, null);
    if (count === 0) break;
    offset += count;
  }
  return output.subarray(0, offset);
}

function readMetadata(recordPath, expectation = {}) {
  let descriptor;
  try {
    descriptor = fs.openSync(recordPath, fs.constants.O_RDONLY | NOFOLLOW);
  } catch (error) {
    if (error.code === 'ENOENT') return { kind: 'missing' };
    return metadataInvalid('unreadable');
  }

  try {
    const stat = fs.fstatSync(descriptor);
    const uid = effectiveUid();
    const mode = stat.mode & 0o777;
    if (!stat.isFile() || (uid !== null && stat.uid !== uid)) return metadataInvalid('ownership');
    if ((mode & 0o077) !== 0 || (mode & 0o400) === 0) return metadataInvalid('permissions');
    if (stat.size > MAX_METADATA_BYTES) return metadataInvalid('oversized');
    const bytes = readOpenedFile(descriptor, stat.size);
    if (bytes.length > MAX_METADATA_BYTES) return metadataInvalid('oversized');
    let record;
    try {
      record = JSON.parse(decodeUtf8(bytes, 'Metadata'));
    } catch (_error) {
      return metadataInvalid('malformed');
    }
    const pid = Number.isInteger(record && record.pid) ? record.pid : null;
    if (!validateRecord(record)) return metadataInvalid('invalid', pid);
    if (Object.prototype.hasOwnProperty.call(expectation, 'projectKey') &&
        record.project_key !== expectation.projectKey) {
      return metadataInvalid('project_mismatch', pid);
    }
    if (expectation.kind === 'session') {
      if (expectation.sessionDir && record.session_dir !== expectation.sessionDir) {
        return metadataInvalid('session_mismatch', pid);
      }
    }
    return { kind: 'valid', record };
  } finally {
    fs.closeSync(descriptor);
  }
}

function writeAll(descriptor, bytes) {
  let offset = 0;
  while (offset < bytes.length) offset += fs.writeSync(descriptor, bytes, offset);
}

function atomicInstallMetadata(recordPath, record) {
  if (!validateRecord(record)) throw new ControlError('invalid_metadata', 'Metadata is invalid');
  const bytes = Buffer.from(`${JSON.stringify(record)}\n`, 'utf8');
  if (bytes.length > MAX_METADATA_BYTES) {
    throw new ControlError('metadata_too_large', `Metadata exceeds ${MAX_METADATA_BYTES} bytes`);
  }
  const temporary = `${recordPath}.tmp-${crypto.randomBytes(12).toString('hex')}`;
  let descriptor;
  try {
    descriptor = fs.openSync(
      temporary,
      fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | NOFOLLOW,
      0o600
    );
    writeAll(descriptor, bytes);
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = undefined;
    fs.renameSync(temporary, recordPath);
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    try { fs.unlinkSync(temporary); } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
}

function removeMatchingRecord(recordPath, identity) {
  const result = readMetadata(recordPath);
  if (result.kind !== 'valid') return false;
  if (result.record.pid !== identity.pid || result.record.server_id !== identity.serverId) {
    return false;
  }
  try {
    fs.unlinkSync(recordPath);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

function secureEqual(left, right) {
  const leftBytes = Buffer.from(String(left));
  const rightBytes = Buffer.from(String(right));
  return leftBytes.length === rightBytes.length && crypto.timingSafeEqual(leftBytes, rightBytes);
}

function sendJson(response, statusCode, body) {
  const bytes = Buffer.from(`${JSON.stringify(body)}\n`);
  response.writeHead(statusCode, {
    'content-type': 'application/json',
    'content-length': bytes.length,
    'cache-control': 'no-store'
  });
  response.end(bytes);
}

function parseControlBody(bytes) {
  try {
    const value = JSON.parse(decodeUtf8(bytes, 'Control request'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    return value;
  } catch (_error) {
    return null;
  }
}

function isLoopbackRequest(request) {
  return request.socket.remoteAddress === '127.0.0.1';
}

function createControlServer({ token, pid, serverId, closeUserListener }) {
  let lifecycle = 'running';
  let terminalSent = false;
  const server = http.createServer((request, response) => {
    if (!isLoopbackRequest(request) || request.method !== 'POST' || request.url !== '/stop') {
      sendJson(response, 404, { status: 'failed', reason: 'not_found' });
      return;
    }

    let size = 0;
    const chunks = [];
    const receiveTimer = setTimeout(() => request.destroy(), CONTROL_LIMITS.receiveTimeoutMs);
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > CONTROL_LIMITS.requestBytes) {
        clearTimeout(receiveTimer);
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', async () => {
      clearTimeout(receiveTimer);
      if (size > CONTROL_LIMITS.requestBytes) return;
      const body = parseControlBody(Buffer.concat(chunks));
      const authorization = request.headers.authorization || '';
      const suppliedToken = authorization.startsWith('Bearer ')
        ? authorization.slice('Bearer '.length)
        : '';
      if (!body || !secureEqual(suppliedToken, token) || body.pid !== pid ||
          body.server_id !== serverId) {
        sendJson(response, 403, { status: 'failed', reason: 'identity_mismatch' });
        return;
      }
      if (lifecycle === 'stopping') {
        sendJson(response, 202, { status: 'stopping' });
        return;
      }
      lifecycle = 'stopping';
      let responseClosed = false;
      let terminalOutcome = null;
      const emitTerminal = () => {
        if (!terminalOutcome || terminalSent) return;
        terminalSent = true;
        server.emit('terminal', terminalOutcome);
      };
      response.once('close', () => {
        responseClosed = true;
        emitTerminal();
      });
      let statusCode;
      let responseBody;
      try {
        await closeUserListener();
        terminalOutcome = { status: 'stopped' };
        statusCode = 200;
        responseBody = { status: 'stopped' };
      } catch (error) {
        terminalOutcome = { status: 'failed', error };
        statusCode = 500;
        responseBody = { status: 'failed', reason: 'shutdown_cleanup' };
      }
      response.once('finish', emitTerminal);
      if (responseClosed) emitTerminal();
      else sendJson(response, statusCode, responseBody);
      const terminalTimer = setTimeout(emitTerminal, 50);
      terminalTimer.unref();
    });
    request.on('error', () => clearTimeout(receiveTimer));
  });
  return server;
}

function requestAuthenticatedStop(record) {
  return new Promise((resolve) => {
    let settled = false;
    let request;
    const finish = (outcome) => {
      if (settled) return;
      settled = true;
      clearTimeout(connectTimer);
      clearTimeout(deadlineTimer);
      if (request) request.destroy();
      resolve(outcome);
    };
    const deadlineTimer = setTimeout(
      () => finish({ status: 'failed', reason: 'deadline' }),
      CONTROL_LIMITS.requestDeadlineMs
    );
    const connectTimer = setTimeout(
      () => finish({ status: 'failed', reason: 'connect_timeout' }),
      CONTROL_LIMITS.connectTimeoutMs
    );
    const body = Buffer.from(JSON.stringify({ pid: record.pid, server_id: record.server_id }));
    request = http.request({
      host: '127.0.0.1',
      port: record.control_port,
      method: 'POST',
      path: '/stop',
      headers: {
        authorization: `Bearer ${record.control_token}`,
        'content-type': 'application/json',
        'content-length': body.length
      }
    }, (response) => {
      const chunks = [];
      let size = 0;
      response.on('data', (chunk) => {
        if (settled) return;
        size += chunk.length;
        if (size > CONTROL_LIMITS.responseBytes) {
          response.destroy();
          finish({ status: 'failed', reason: 'oversized_response' });
          return;
        }
        chunks.push(chunk);
      });
      response.on('end', () => {
        if (settled) return;
        try {
          const parsed = JSON.parse(decodeUtf8(Buffer.concat(chunks), 'Control response'));
          const accepted = parsed &&
            ((response.statusCode === 200 && parsed.status === 'stopped') ||
              (response.statusCode === 202 && parsed.status === 'stopping'));
          if (parsed && accepted) {
            finish({ status: parsed.status });
          } else {
            const reason = response.statusCode >= 300
              ? `http_${response.statusCode}`
              : parsed.reason || 'rejected';
            finish({ status: 'failed', reason });
          }
        } catch (_error) {
          finish({ status: 'failed', reason: 'malformed_response' });
        }
      });
    });
    request.on('socket', (socket) => {
      const connected = () => clearTimeout(connectTimer);
      if (socket.connecting) socket.once('connect', connected);
      else connected();
    });
    request.on('error', (error) => finish({
      status: 'failed',
      reason: error.code === 'ECONNREFUSED' ? 'connection_refused' : 'connection_failed'
    }));
    request.end(body);
  });
}

function activeRecordPath(sessionDir) {
  return path.join(sessionDir, 'state', 'server-control.json');
}

function publishActiveRecords({
  projectDir,
  sessionDir,
  pid,
  serverId,
  controlPort,
  controlToken
}) {
  let projectKey = null;
  let stableRecordPath = null;
  if (projectDir !== null) {
    const identity = readProjectIdentity(Buffer.from(projectDir, 'utf8'));
    const state = projectStateFromEnvironment(identity);
    projectKey = state.projectKey;
    stableRecordPath = state.recordPath;
  }
  const sessionRecordPath = activeRecordPath(sessionDir);
  const record = {
    version: 1,
    pid,
    server_id: serverId,
    session_dir: sessionDir,
    project_key: projectKey,
    control_port: controlPort,
    control_token: controlToken
  };
  if (stableRecordPath) atomicInstallMetadata(stableRecordPath, record);
  atomicInstallMetadata(sessionRecordPath, record);
  return { projectKey, stableRecordPath, sessionRecordPath };
}

function safeUnlink(filePath) {
  try {
    fs.unlinkSync(filePath);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    return false;
  }
}

function hasExactServerArgument(argumentsBuffer, serverId) {
  const expected = Buffer.from(`--brainstorm-server-id=${serverId}`);
  let start = 0;
  while (start < argumentsBuffer.length) {
    const separator = argumentsBuffer.indexOf(0, start);
    const end = separator === -1 ? argumentsBuffer.length : separator;
    if (argumentsBuffer.subarray(start, end).equals(expected)) return true;
    if (separator === -1) break;
    start = separator + 1;
  }
  return false;
}

function pidEvidence(pid, serverId) {
  try {
    process.kill(pid, 0);
  } catch (error) {
    if (error.code === 'ESRCH') return 'absent';
    if (error.code !== 'EPERM') return 'indeterminate';
  }
  if (process.platform !== 'linux') return 'live';
  try {
    const argumentsBuffer = fs.readFileSync(`/proc/${pid}/cmdline`);
    return hasExactServerArgument(argumentsBuffer, serverId)
      ? 'live'
      : 'proven_unrelated';
  } catch (_error) {
    return 'live';
  }
}

function stablePathFromKey(projectKey) {
  if (!HEX_64_PATTERN.test(projectKey)) return null;
  return path.join(ensurePrivateStateRoot(process.env.HOME || ''), `${projectKey}.json`);
}

function cleanupSessionRecords(recordPath, record) {
  safeUnlink(recordPath);
  if (record && record.project_key) {
    const stablePath = stablePathFromKey(record.project_key);
    removeMatchingRecord(stablePath, { pid: record.pid, serverId: record.server_id });
  }
}

function isEphemeralSession(sessionDir) {
  const temporaryRoot = fs.realpathSync('/tmp');
  return sessionDir.startsWith(`${temporaryRoot}${path.sep}`) &&
    path.basename(sessionDir).startsWith('brainstorm-');
}

function expectedProjectKeyForSession(sessionDir) {
  if (isEphemeralSession(sessionDir)) return null;
  const brainstormDirectory = path.dirname(sessionDir);
  const agentDirectory = path.dirname(brainstormDirectory);
  if (path.basename(brainstormDirectory) !== 'brainstorm' ||
      path.basename(agentDirectory) !== '.agent') {
    throw new ControlError(
      'invalid_session_layout',
      `Persistent brainstorm session path has an invalid layout: ${sessionDir}`
    );
  }
  const projectDirectory = path.dirname(agentDirectory);
  const identity = readProjectIdentity(Buffer.from(projectDirectory, 'utf8'));
  return projectKeyForIdentity(identity);
}

function failureForStop(recordPath, pid) {
  const suffix = pid ? `; PID ${pid} left running` : '';
  return {
    status: 'failed',
    error: `cannot verify brainstorm server identity from ${recordPath}${suffix}; state preserved`
  };
}

async function replaceProject(identity) {
  const state = projectStateFromEnvironment(identity);
  const metadata = readMetadata(state.recordPath, {
    kind: 'stable',
    projectKey: state.projectKey
  });
  if (metadata.kind === 'valid') await requestAuthenticatedStop(metadata.record);
  safeUnlink(state.recordPath);
  return { status: metadata.kind === 'missing' ? 'not_running' : 'handled' };
}

async function stopSession(sessionDir) {
  const recordPath = activeRecordPath(sessionDir);
  const metadata = readMetadata(recordPath, {
    kind: 'session',
    sessionDir,
    projectKey: expectedProjectKeyForSession(sessionDir)
  });
  if (metadata.kind === 'missing') return { exitCode: 0, body: { status: 'not_running' } };

  if (metadata.kind !== 'valid') {
    if (metadata.pid && pidEvidence(metadata.pid, '') === 'absent') {
      safeUnlink(recordPath);
      return { exitCode: 0, body: { status: 'stale_pid' } };
    }
    return { exitCode: 1, body: failureForStop(recordPath, metadata.pid) };
  }

  const outcome = await requestAuthenticatedStop(metadata.record);
  if (outcome.status === 'stopped') {
    cleanupSessionRecords(recordPath, metadata.record);
    if (isEphemeralSession(sessionDir)) fs.rmSync(sessionDir, { recursive: true, force: true });
    return { exitCode: 0, body: { status: 'stopped' } };
  }
  if (outcome.reason === 'shutdown_cleanup') {
    return { exitCode: 1, body: failureForStop(recordPath, metadata.record.pid) };
  }
  const evidence = pidEvidence(metadata.record.pid, metadata.record.server_id);
  if (evidence === 'absent' || evidence === 'proven_unrelated') {
    cleanupSessionRecords(recordPath, metadata.record);
    return { exitCode: 0, body: { status: 'stale_pid' } };
  }
  return { exitCode: 1, body: failureForStop(recordPath, metadata.record.pid) };
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

async function runCli(command) {
  try {
    const identity = readProjectIdentity(readStdinIdentity());
    if (command === 'replace-project') {
      printJson(await replaceProject(identity));
      return 0;
    }
    if (command === 'stop-session') {
      const result = await stopSession(identity);
      printJson(result.body);
      return result.exitCode;
    }
    printJson({ status: 'failed', error: 'unknown internal server-control command' });
    return 1;
  } catch (error) {
    printJson({
      status: 'failed',
      error: error && error.message ? error.message : 'server control failed'
    });
    return 1;
  }
}

if (require.main === module) {
  runCli(process.argv[2]).then((exitCode) => { process.exitCode = exitCode; });
}

module.exports = {
  CONTROL_LIMITS,
  MAX_IDENTITY_BYTES,
  MAX_METADATA_BYTES,
  ControlError,
  atomicInstallMetadata,
  activeRecordPath,
  createControlServer,
  createControlToken,
  ensurePrivateStateRoot,
  hasExactServerArgument,
  projectStateFor,
  projectStateFromEnvironment,
  publishActiveRecords,
  readMetadata,
  readProjectIdentity,
  readStdinIdentity,
  removeMatchingRecord,
  requestAuthenticatedStop,
  runCli,
  stopSession,
  validateRecord
};
