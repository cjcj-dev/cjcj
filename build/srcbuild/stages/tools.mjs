// Port of cangjie-build/src/cangjie_build/stages/tools.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import {applyTextPatch, baseEnv, requireFile, runBuildPy} from './common.mjs';

// cjcov and cjtrace-recover are Cangjie-written SDK tools that upstream
// cangjie-build does not drive, so shipping the base SDK's copies would leave
// them compiled by a foreign toolchain. Both expose the same clean/build/install
// verbs as the four ported tools.
const TOOL_PATHS = [
  ['cjpm', path.join('cjpm', 'build')],
  ['cjfmt', path.join('cjfmt', 'build')],
  ['hle', path.join('hyperlangExtension', 'build')],
  ['lsp', path.join('cangjie-language-server', 'build')],
  ['cjcov', path.join('cjcov', 'build')],
  ['cjtrace-recover', path.join('cjtrace-recover', 'build')],
];
// cjcov's cross build reaches an unreviewed link-flag branch, and
// cjtrace-recover's build.py exits when --target arrives without a sysroot. The
// source-build matrix has no Windows cell, so keep both native for now.
export const NATIVE_ONLY_TOOLS = Object.freeze(['cjcov', 'cjtrace-recover']);
// cjtrace-recover is a CMake project: an install without --prefix resolves to
// CMAKE_INSTALL_PREFIX (/usr/local by default), so it must be pointed at a
// directory inside the repo, mirroring the dist/ the other tools produce.
const CJTRACE_DIST = path.join('cjtrace-recover', 'dist');
const CJPM_NEEDLE = '/opt/buildtools/llvm-mingw-w64';
const CJPM_PIN_FILE = new URL('../../../ci/cjpm_pin.env', import.meta.url);
const CJPM_EDITS = [[
  '-L /opt/buildtools/llvm-mingw-w64/x86_64-w64-mingw32/lib',
  "-L {os.path.join(os.environ['MINGW_PATH'], 'x86_64-w64-mingw32', 'lib')}",
]];

function readCjpmPin() {
  const pins = Object.fromEntries(fs.readFileSync(CJPM_PIN_FILE, 'utf8').split(/\r?\n/)
    .filter(Boolean)
    .map(line => {
      const separator = line.indexOf('=');
      if (separator < 1) throw new BuildError('tools.cjpm.pin', `invalid pin line: ${line}`);
      return [line.slice(0, separator), line.slice(separator + 1)];
    }));
  if (!/^https:\/\//.test(pins.CJPM_FORK_URL || '')) {
    throw new BuildError('tools.cjpm.pin', `invalid CJPM_FORK_URL: ${pins.CJPM_FORK_URL || '<missing>'}`);
  }
  if (!/^[0-9a-f]{40}$/.test(pins.CJPM_FORK_REF || '')) {
    throw new BuildError('tools.cjpm.pin', `invalid CJPM_FORK_REF: ${pins.CJPM_FORK_REF || '<missing>'}`);
  }
  return {url: pins.CJPM_FORK_URL, ref: pins.CJPM_FORK_REF};
}

async function checkoutPinnedCjpm(toolsRoot) {
  const {url, ref} = readCjpmPin();
  await runCommand(['git', 'fetch', '--depth', '1', url, ref], {cwd: toolsRoot, stage: 'tools.cjpm.fetch'});
  const fetched = await runCommand(['git', 'rev-parse', 'FETCH_HEAD'], {
    cwd: toolsRoot, stage: 'tools.cjpm.pin', capture: true, logOutput: false,
  });
  if (process.env.CANGJIE_BUILD_DRY_RUN !== '1' && fetched.stdout.trim() !== ref) {
    throw new BuildError('tools.cjpm.pin', `fetched ${fetched.stdout.trim() || '<empty>'}, expected ${ref}`);
  }
  await runCommand(['git', 'checkout', ref, '--', 'cjpm'], {cwd: toolsRoot, stage: 'tools.cjpm.checkout'});
}

function buildArgsFor(name, config) {
  if (config.target.spec.crossCompile) {
    return ['build', '-t', config.crossBuildType, '--target', 'windows-x86_64'];
  }
  const toolsBuildType = config.buildType === 'relwithdebinfo' ? 'release' : config.buildType;
  const args = ['build', '-t', toolsBuildType];
  if (name === 'cjpm') {
    args.push(
      '--set-rpath',
      `${config.target.spec.rpathOrigin}/../../runtime/lib/${config.target.runtimeLibSubdir(config.buildType)}`,
    );
  }
  return args;
}

function installArgsFor(name, toolsRoot) {
  if (name !== 'cjtrace-recover') return ['install'];
  return ['install', '--prefix', path.join(toolsRoot, CJTRACE_DIST)];
}

export function toolsFor(config) {
  if (!config.target.spec.crossCompile) return TOOL_PATHS;
  return TOOL_PATHS.filter(([name]) => !NATIVE_ONLY_TOOLS.includes(name));
}

export function targetToolsEnv(config) {
  const env = baseEnv(config);
  const targetHome = path.join(config.repoPath('compiler'), 'output');
  const targetPaths = [path.join(targetHome, 'bin'), path.join(targetHome, 'tools', 'bin')];
  const remainingPaths = String(env.PATH || '').split(path.delimiter)
    .filter(entry => entry && !targetPaths.includes(entry));
  // Driver.cpp:49-52 derives the link SDK from the resolved cjc executable.
  // Keep baseEnv's plain-host loader, but select the target SDK's cjc so its
  // products use the target cjstart.o, built-in libraries, and runtime.
  env.PATH = [...targetPaths, ...remainingPaths].join(path.delimiter);
  return env;
}

export async function run(config) {
  const toolsRoot = config.repoPath('tools');
  const suffix = config.target.spec.exeSuffix;
  await stage('tools', async () => {
    await checkoutPinnedCjpm(toolsRoot);
    const cjpmBuildPy = path.join(toolsRoot, 'cjpm', 'build', 'build.py');
    if (fs.readFileSync(cjpmBuildPy, 'utf8').includes(CJPM_NEEDLE)) {
      applyTextPatch(cjpmBuildPy, CJPM_EDITS, {stage: 'tools.cjpm.patch'});
    }
    const toolEnv = targetToolsEnv(config);
    for (const [name, subpath] of toolsFor(config)) {
      const cwd = path.join(toolsRoot, subpath);
      await runBuildPy(config, cwd, ['clean'], {stageName: `tools.${name}.clean`, extraEnv: toolEnv});
      await runBuildPy(config, cwd, buildArgsFor(name, config), {stageName: `tools.${name}.build`, extraEnv: toolEnv});
      await runBuildPy(config, cwd, installArgsFor(name, toolsRoot), {
        stageName: `tools.${name}.install`, extraEnv: toolEnv,
      });
    }
    requireFile(path.join(toolsRoot, 'cjpm', 'dist', `cjpm${suffix}`), {stage: 'tools.cjpm.verify'});
  });
}
