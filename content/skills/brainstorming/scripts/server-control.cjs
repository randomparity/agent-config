'use strict';

const crypto = require('crypto');
const fs = require('fs');
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

function projectStateFor(identity, home) {
  const root = ensurePrivateStateRoot(home);
  const projectKey = crypto.createHash('sha256').update(Buffer.from(identity, 'utf8')).digest('hex');
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
    if (expectation.kind === 'stable' && record.project_key !== expectation.projectKey) {
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

module.exports = {
  CONTROL_LIMITS,
  MAX_IDENTITY_BYTES,
  MAX_METADATA_BYTES,
  ControlError,
  atomicInstallMetadata,
  createControlToken,
  ensurePrivateStateRoot,
  projectStateFor,
  projectStateFromEnvironment,
  readMetadata,
  readProjectIdentity,
  readStdinIdentity,
  removeMatchingRecord,
  validateRecord
};
