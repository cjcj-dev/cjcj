// Port of cangjie-build/src/cangjie_build/stages/tools.py.

import fs from 'node:fs';
import path from 'node:path';
import {stage} from '../../lib/logging.mjs';
import {applyTextPatch, requireFile, runBuildPy} from './common.mjs';

const TOOL_PATHS = [
  ['cjpm', path.join('cjpm', 'build')],
  ['cjfmt', path.join('cjfmt', 'build')],
  ['hle', path.join('hyperlangExtension', 'build')],
  ['lsp', path.join('cangjie-language-server', 'build')],
];
const CJPM_NEEDLE = '/opt/buildtools/llvm-mingw-w64';
const CJPM_EDITS = [[
  '-L /opt/buildtools/llvm-mingw-w64/x86_64-w64-mingw32/lib',
  "-L {os.path.join(os.environ['MINGW_PATH'], 'x86_64-w64-mingw32', 'lib')}",
]];

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
