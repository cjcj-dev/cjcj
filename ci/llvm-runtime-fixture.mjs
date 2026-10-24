import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {sourceFetchArguments} from '../build/lib/git.mjs';
export const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const base = '3b1fe439310269257a43685407df523f55a47cf6';
export function command(argv, options = {}) {
  const result = spawnSync(argv[0], argv.slice(1), {encoding: 'utf8', ...options});
  if (result.error || result.signal) throw result.error ?? new Error(result.signal);
  return {rc: result.status, stdout: result.stdout, stderr: result.stderr};
}
const sourcePath = 'ci/fetch-llvm-runtime.sh';
const sourceBlob = '52e9de86a83eeeabe5545041b653f80eb11b9f69';
export function prepareOriginalSource(checkout = repo) {
  const identity = () => command(['git', '-C', checkout, 'rev-parse', '--verify', `${base}:${sourcePath}`]);
  if (identity().rc !== 0) {
    const fetched = command(['git', '-C', checkout, ...sourceFetchArguments('https://github.com/cjcj-dev/cjcj.git', base, {noTags: true})]);
    if (fetched.rc !== 0) throw new Error(`LLVM_RUNTIME_HISTORY_FETCH_FAILED: ${fetched.stderr}`);
  }
  const result = identity();
  if (result.rc !== 0 || result.stdout.trim() !== sourceBlob)
    throw new Error(`LLVM_RUNTIME_HISTORY_IDENTITY: ${result.stderr || result.stdout}`);
  const content = command(['git', '-C', checkout, 'cat-file', '-e', `${sourceBlob}^{blob}`]);
  if (content.rc !== 0) throw new Error(`LLVM_RUNTIME_HISTORY_BLOB: ${content.stderr}`);
  console.log(`LLVM_RUNTIME_HISTORY_VERIFIED commit=${base} blob=${sourceBlob}`);
}
export function originalSource(checkout = repo) {
  const result = command(['git', '-C', checkout, 'show', `${base}:${sourcePath}`]);
  if (result.rc !== 0) throw new Error(`LLVM_RUNTIME_HISTORY_MISSING: ${result.stderr}`);
  return result.stdout;
}
export const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
export function fixture(root, table, {baseline = false} = {}) {
  fs.mkdirSync(root, {recursive: true});
  const git = (...args) => {
    const result = command(['git', ...args], {env: {...process.env, GIT_AUTHOR_DATE: '2000-01-01T00:00:00Z', GIT_COMMITTER_DATE: '2000-01-01T00:00:00Z'}});
    if (result.rc !== 0) throw new Error(result.stderr);
    return result.stdout.trim();
  };
  const origin = path.join(root, 'origin');
  git('init', '-q', origin);
  fs.writeFileSync(path.join(origin, 'tracked'), 'clean\n');
  git('-C', origin, 'add', '.');
  git('-C', origin, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'runtime transport fixture');
  const sha = git('-C', origin, 'rev-parse', 'HEAD');
  git('-C', origin, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
    'commit', '--allow-empty', '-qm', 'alternate HEAD for checkout guard');
  const alternate = git('-C', origin, 'rev-parse', 'HEAD');
  git('-C', origin, 'reset', '--hard', sha);
  const copy = path.join(root, 'entry');
  fs.mkdirSync(path.join(copy, 'ci'), {recursive: true});
  fs.mkdirSync(path.join(copy, 'build/lib'), {recursive: true});
  const entry = path.join(copy, 'ci', baseline ? 'original.bash' : 'fetch-llvm-runtime.mjs');
  if (baseline) fs.writeFileSync(entry, originalSource());
  else fs.copyFileSync(path.join(repo, 'ci/fetch-llvm-runtime.mjs'), entry);
  fs.copyFileSync(path.join(repo, 'build/lib/srcbuild_git.sh'), path.join(copy, 'build/lib/srcbuild_git.sh'));
  // Only the adjacent data pin changes: both unchanged product entries use the
  // same real Git fixture. No network runtime revision or native claim is made.
  fs.writeFileSync(path.join(copy, 'ci/runtime_pin.env'), `RUNTIME_REF=${sha}\nRUNTIME_SRC_URL=${table.privateEnv[table.urlVariable]}\n`);
  const cleanEnv = {...process.env, LC_ALL: 'C', GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null'};
  for (const key of new Set([...Object.keys(table.privateEnv), 'RUNTIME_REF', 'RUNTIME_SRC_URL', 'GIT_TRACE',
    'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'CJCJ_SRCBUILD_SOURCE_MIRRORS', 'CJCJ_SRCBUILD_REQUIRE_MIRRORS'])) delete cleanEnv[key];
  cleanEnv.CJCJ_SRCBUILD_SOURCE_MIRRORS = `${table.privateEnv[table.urlVariable]}=file://${origin}`;
  cleanEnv.CJCJ_SRCBUILD_REQUIRE_MIRRORS = '1';
  const execute = (input, index) => {
    let dest = path.join(root, `dest-${index}`);
    if (input.fixture === 'root-trailing-space') dest += ' ';
    if (input.fixture === 'root-trailing-tab') dest += '\t';
    if (input.fixture !== 'absent') {
      if (input.fixture === 'destination-file') fs.writeFileSync(dest, 'not a directory\n');
      else if (input.fixture === 'unborn' || input.fixture === 'checkout-conflict') {
        git('init', '-q', dest);
        if (input.fixture === 'checkout-conflict') fs.writeFileSync(path.join(dest, 'tracked'), 'local contents\n');
      }
      else if (input.fixture === 'nongit') fs.mkdirSync(dest);
      else {
        git('clone', '-q', '--no-hardlinks', origin, dest);
        if (input.fixture === 'subdirectory') { dest = path.join(dest, 'nested'); fs.mkdirSync(dest); }
        else if (input.fixture === 'tracked-dirty') fs.writeFileSync(path.join(dest, 'tracked'), 'changed\n');
        else if (input.fixture === 'untracked-dirty') fs.writeFileSync(path.join(dest, 'untracked'), 'changed\n');
        else if (input.fixture === 'corrupt-index') fs.writeFileSync(path.join(dest, '.git/index'), 'invalid index\n');
        else if (input.fixture.startsWith('checkout-head-')) {
          // A real post-checkout hook changes real Git state after a successful
          // checkout. Neither Git nor the product entry is mocked/replaced.
          git('-C', dest, 'fetch', '-q', origin, alternate);
          const action = input.fixture === 'checkout-head-drift'
            ? ['update-ref', 'HEAD', alternate] : ['update-ref', '-d', 'HEAD'];
          fs.writeFileSync(path.join(dest, '.git/hooks/post-checkout'),
            `#!/usr/bin/env node\nimport('node:child_process').then(({spawnSync}) => {\nconst result = spawnSync('git', ${JSON.stringify(['-C', dest, ...action])}, {stdio: 'inherit'});\nprocess.exit(result.status);\n});\n`, {mode: 0o755});
        }
        else if (!['clean', 'root-trailing-space', 'root-trailing-tab'].includes(input.fixture)) throw new Error(`unknown fixture ${input.fixture}`);
      }
    }
    const env = {...cleanEnv};
    for (const [key, value] of Object.entries(input.env)) {
      if (value === undefined) delete env[key];
      else env[key] = value === table.privateEnv[table.shaVariable] ? sha : value;
    }
    const args = input.args.map(arg => arg === '$DEST' ? dest : arg);
    const result = command([...(baseline ? ['bash'] : ['npx', '--yes', 'zx@8']), entry, ...args], {env, cwd: root});
    // Git emits directory names on init/fetch and the identity line emits the
    // canonical path. This is the only normalization; complete streams remain.
    const normalize = text => text.replaceAll(root, '$ROOT').replaceAll(sha, '$SHA');
    return {input, argv: args, entrySha256: digest(entry), ...result,
      normalized: {rc: result.rc, stdout: normalize(result.stdout), stderr: normalize(result.stderr)}};
  };
  return {entry, sha, execute};
}
