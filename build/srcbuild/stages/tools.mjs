// Port of cangjie-build/src/cangjie_build/stages/tools.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import {applyTextPatch, requireFile, runBuildPy} from './common.mjs';

const TOOL_PATHS = [
  ['cjpm', path.join('cjpm', 'build')],
  ['cjfmt', path.join('cjfmt', 'build')],
  ['hle', path.join('hyperlangExtension', 'build')],
  ['lsp', path.join('cangjie-language-server', 'build')],
];
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
    args.push('--set-rpath', `$ORIGIN/../../runtime/lib/${config.target.runtimeLibSubdir(config.buildType)}`);
  }
  return args;
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
    for (const [name, subpath] of TOOL_PATHS) {
      const cwd = path.join(toolsRoot, subpath);
      await runBuildPy(config, cwd, ['clean'], {stageName: `tools.${name}.clean`});
      await runBuildPy(config, cwd, buildArgsFor(name, config), {stageName: `tools.${name}.build`});
      await runBuildPy(config, cwd, ['install'], {stageName: `tools.${name}.install`});
    }
    requireFile(path.join(toolsRoot, 'cjpm', 'dist', `cjpm${suffix}`), {stage: 'tools.cjpm.verify'});
  });
}
