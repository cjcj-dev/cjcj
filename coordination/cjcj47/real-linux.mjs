// Run on kkk2. External build.py fixtures exercise actual stage dispatch with
// the advisor-approved real compiler, std and target runtime. This is not a
// build of the complete stdx/tools sources or a final release qualification.
import fs from 'node:fs/promises';
import path from 'node:path';
import {buildConfig} from '../../build/lib/config.mjs';
import * as tools from '../../build/srcbuild/stages/tools.mjs';
import * as stdx from '../../build/srcbuild/stages/stdx.mjs';

const root = '/root/sym_cjcj_47_implement_r5749367643/real-linux';
const sdk = path.join(root, 'sdk');
const host = '/root/sym_cjcj_48_implement_r5685150408/host';
const tuple = 'linux_x86_64_cjnative';
const trace = path.join(root, 'invocations.jsonl');
const fakeBin = path.join(root, 'external-git');
const write = async (file, contents, mode = 0o755) => {
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents, {mode});
  return file;
};
const pin = (await fs.readFile(new URL('../../ci/cjpm_pin.env', import.meta.url), 'utf8')).match(/^CJPM_FORK_REF=(.+)$/m)[1];
await write(path.join(fakeBin, 'git'), `#!/bin/sh\ncase "$1" in rev-parse) printf '%s\\n' '${pin}' ;; esac\n`);
process.env.PATH = `${fakeBin}:${process.env.PATH}`;
process.env.CJCJ_SRCBUILD_HOST_SDK = host;
process.env.GC_UNIT_CJC_RUNTIME_LIB_DIR = path.join(host, 'runtime/lib', tuple);
delete process.env.CANGJIE_BUILD_DRY_RUN;
const original = buildConfig({workspace: path.join(root, 'workspace'), buildRoot: root, consumerSdk: sdk});
const config = {...original, target: {...original.target, spec: {...original.target.spec,
  llvmBinDir: path.join(sdk, 'bin'), opensslLibDir: '/usr/lib/x86_64-linux-gnu'}}};
const sample = await write(path.join(root, 'main.cj'), 'main() { return 47 }\n');
const python = `import hashlib, json, os, pathlib, shutil, subprocess, sys, time
if sys.argv[1] == 'build':
 output = pathlib.Path.cwd()/'real-consumer'
 compiler = shutil.which('cjc')
 command = [compiler, ${JSON.stringify(sample)}, '-o', str(output)]
 started = time.monotonic()
 compiled = subprocess.run(['strace', '-f', '-e', 'trace=execve', '-o', 'compiler-execve.log', *command], text=True, capture_output=True)
 pathlib.Path('compiler.stdout').write_text(compiled.stdout)
 pathlib.Path('compiler.stderr').write_text(compiled.stderr)
 record = {'cwd': os.getcwd(), 'argv': command, 'compiler_sha256': hashlib.sha256(pathlib.Path(compiler).read_bytes()).hexdigest(), 'build_rc': compiled.returncode, 'wall': time.monotonic()-started, 'sdk': os.environ.get('CANGJIE_HOME'), 'host_loader': os.environ.get('LD_LIBRARY_PATH')}
 with open(${JSON.stringify(trace)}, 'a') as out: out.write(json.dumps(record) + '\\n')
 compiled.check_returncode()
 env = dict(os.environ)
 env['LD_LIBRARY_PATH'] = ${JSON.stringify('/root/diff_0189f2e01515/default/build/runtime-staging/lib/x86_64_Release')}
 env['LD_DEBUG'] = 'libs'
 result = subprocess.run([str(output)], env=env, text=True, capture_output=True, timeout=30)
 pathlib.Path('loader.log').write_text(result.stderr)
 record.update({'run_rc': result.returncode, 'elf_sha256': hashlib.sha256(output.read_bytes()).hexdigest()})
 with open(${JSON.stringify(trace)}, 'a') as out: out.write(json.dumps(record) + '\\n')
 assert result.returncode == 47, result.stderr
 p = pathlib.Path('build_temp/build/build.ninja')
 p.parent.mkdir(parents=True, exist_ok=True)
 p.write_text('LD_LIBRARY_PATH=' + os.environ['LD_LIBRARY_PATH'] + ' cjc main.cj\\n')
`;
await write(path.join(config.repoPath('stdx'), 'build.py'), python);
for (const [, directory] of tools.toolsFor(config)) await write(path.join(config.repoPath('tools'), directory, 'build.py'), python);
await write(path.join(config.repoPath('tools'), 'cjpm/dist/cjpm'), 'external tool fixture, not a release product');
await stdx.run(config);
await tools.run(config);
const rows = (await fs.readFile(trace, 'utf8')).trim().split('\n').map(JSON.parse).filter(row => row.run_rc !== undefined);
if (rows.length !== 7 || rows.some(row => row.build_rc !== 0 || row.run_rc !== 47 || row.sdk !== sdk)) {
  throw new Error(`real consumer outcome mismatch: ${JSON.stringify(rows)}`);
}
console.log(`REAL_LINUX_CONSUMERS_ASSERT_PASS consumers=${rows.length} each_exit=47 scope=real-compiler-in-build-fixtures`);
