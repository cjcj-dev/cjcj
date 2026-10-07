#!/usr/bin/env zx
// Real fetch_sources -> build_tuple chain. Observe first CMake argv, then stop.
import {fs, path, assert, repo, requireArgument, run, capture} from './entry-common.mjs';
const requiredArguments = {"0": [7, "new work directory"], "1": [8, "actual runtime Git transport mirror"], "2": [9, "other-source Git transport fixture"]};
const required = index => requireArgument(index, ...requiredArguments[index]);
const work = path.resolve(required(0, 'new work directory'));
const runtimeArgument = required(1), otherArgument = required(2);
await run(['mkdir', work]);
const runtimeMirror = fs.realpathSync(runtimeArgument);
const otherMirror = fs.realpathSync(otherArgument);
const otherSha = (await capture(['git', '-C', otherMirror, 'rev-parse', 'HEAD'])).stdout.trim();
const runtimeSha = '4909b2dec1af7f522133c6401e2ce960b0ef511d';
const runtimeUrl = 'https://github.com/cjcj-dev/cangjie-runtime.git';
delete process.env.RUNTIME_REF; delete process.env.RUNTIME_SRC_URL;
Object.assign(process.env, {
  CJCJ_LLVM_RUNTIME_MODE: 'private', CJCJ_LLVM_RUNTIME_URL: runtimeUrl, CJCJ_LLVM_RUNTIME_SHA: runtimeSha,
  CJCJ_SRCBUILD_SOURCE_MIRRORS: `${runtimeUrl}=file://${runtimeMirror};file://${otherMirror}=file://${otherMirror}`,
  CJCJ_SRCBUILD_REQUIRE_MIRRORS: '1', TUPLE_ROOT: path.join(work, 'tuple'), TUPLE_PLATFORM: 'linux_x86_64', LLVM_TARGETS: 'X86',
  LLVM_URL: `file://${otherMirror}`, LLVM_SHA: otherSha,
  CANGJIE_COMPILER_URL: `file://${otherMirror}`, CANGJIE_COMPILER_SHA: otherSha,
  FLATBUFFERS_URL: `file://${otherMirror}`, FLATBUFFERS_SHA: otherSha, GIT_TRACE: path.join(work, 'fetch.trace'),
});
console.log(`CHAIN_INPUT runtime=${runtimeSha} other=${otherSha} runtime_mirror=${runtimeMirror}`);
await run(['bash', path.join(repo, 'ci/platform_tuples/fetch_sources.sh')], {log: path.join(work, 'fetch.log')});
const selected = path.join(process.env.TUPLE_ROOT, 'paired-runtime');
const head = (await capture(['git', '-C', selected, 'rev-parse', 'HEAD'])).stdout.trim();
console.log(`CHAIN_ASSERT_REACHED runtime_head actual=${head} expected=${runtimeSha}`);
assert.equal(head, runtimeSha); console.log('CHAIN_ASSERT_PASS runtime_head');
fs.mkdirSync(path.join(work, 'bin'));
process.env.LLVM_RUNTIME_CMAKE_CAPTURE = path.join(work, 'cmake.json');
fs.writeFileSync(path.join(work, 'bin/cmake'), "#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ['LLVM_RUNTIME_CMAKE_CAPTURE'], 'w') as out:\n    json.dump(sys.argv[1:], out)\nsys.exit(86)\n", {mode: 0o755});
process.env.PATH = `${path.join(work, 'bin')}:${process.env.PATH}`;
const build = await run(['bash', path.join(repo, 'ci/platform_tuples/build_tuple.sh')], {log: path.join(work, 'build.log'), check: false});
fs.writeFileSync(path.join(work, 'build.rc'), `${build.exitCode}\n`);
console.log(`CHAIN_ASSERT_REACHED first_cmake_boundary actual=${build.exitCode} expected=86`);
assert.equal(build.exitCode, 86); console.log('CHAIN_ASSERT_PASS first_cmake_boundary');
await run(['python3', '-', path.join(work, 'cmake.json'), selected, runtimeSha], {input: String.raw`import json,subprocess,sys
from pathlib import Path
command=json.loads(Path(sys.argv[1]).read_text())
actual=[x for x in command if x.startswith('-DCANGJIE_RUNTIME_SOURCE_DIR=')]
expected=['-DCANGJIE_RUNTIME_SOURCE_DIR='+str(Path(sys.argv[2]).resolve())]
print(f'CHAIN_ASSERT_REACHED cmake_runtime_source actual={actual!r} expected={expected!r}', flush=True)
assert actual==expected, 'cmake_runtime_source'
selected=actual[0].split('=',1)[1]
head=subprocess.check_output(['git','-C',selected,'rev-parse','HEAD'],text=True).strip()
print(f'CHAIN_ASSERT_REACHED consumed_head actual={head} expected={sys.argv[3]}',flush=True)
assert head==sys.argv[3], 'consumed_head'
assert not subprocess.check_output(['git','-C',selected,'status','--porcelain']).strip()
print('CHAIN_ASSERT_PASS cmake_runtime_source consumed_head clean')`});
