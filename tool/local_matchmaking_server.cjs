// Full pinned server in a disposable copy. Never modifies the source checkout.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawn, execFileSync} = require('node:child_process');
const revision = 'b354a81f11003a03f0dcd1dafd4edc641e6763bd';
const source = path.resolve(process.env.SHOWDOWN_PATH || '');
if (!process.env.SHOWDOWN_PATH || execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim() !== revision) {
  throw new Error(`SHOWDOWN_PATH must be a checkout at ${revision}`);
}
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'showdown-matchmaking-'));
// Export tracked files from the pinned commit, excluding local configs/data/dist.
execFileSync('tar', ['-xf', '-', '-C', root], {
  input: execFileSync('git', ['-C', source, 'archive', revision], {maxBuffer: 64 * 1024 * 1024}),
});
fs.symlinkSync(path.join(source, 'node_modules'), path.join(root, 'node_modules'), 'dir');
fs.mkdirSync(path.join(root, 'logs'), {recursive: true});
// Local ladder, no credentials and no upstream login/registration traffic.
fs.writeFileSync(path.join(root, 'config/config.js'), `
exports.port = 8001;
exports.bindaddress = '127.0.0.1';
exports.noguestsecurity = true;
exports.noipchecks = true;
exports.nothrottle = true;
exports.remoteladder = false;
exports.loginserver = 'http://127.0.0.1:1/';
exports.forceregisterelo = 0;
exports.subprocesses = {network: 1, simulator: 1, validator: 1, verifier: 0};
exports.repl = false;
exports.startuphook = () => {
  // Synthetic registered identity for the same-account merge scenario only.
  // Does not test the public login service or signature verification.
  const validateToken = Users.User.prototype.validateToken;
  Users.User.prototype.validateToken = function(token, name, id, connection) {
    if (!token && id.startsWith('shared')) return Promise.resolve('2');
    return validateToken.call(this, token, name, id, connection);
  };
  // Delay only explicitly named test users, around the real preparation method.
  const original = Ladders.Ladder.prototype.prepBattle;
  Ladders.Ladder.prototype.prepBattle = async function(connection, ...args) {
    if (connection.user.id.startsWith('delay')) await new Promise(r => setTimeout(r, 1200));
    return original.call(this, connection, ...args);
  };
};
`);
try {
  execFileSync(process.execPath, ['build'], {cwd: root, stdio: 'inherit'});
} catch (error) {
  fs.rmSync(root, {recursive: true, force: true});
  throw error;
}
console.log(`Disposable full server: ${root}; ws://127.0.0.1:8001/showdown/websocket`);
const child = spawn(process.execPath, ['pokemon-showdown', 'start', '--skip-build'], {cwd: root, stdio: 'inherit', detached: true});
let stopped = false;
function stop() {
  if (stopped) return;
  stopped = true;
  try { process.kill(-child.pid, 'SIGTERM'); } catch {}
}
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
child.on('exit', code => {
  stop();
  fs.rmSync(root, {recursive: true, force: true});
  process.exitCode = code || 0;
});
