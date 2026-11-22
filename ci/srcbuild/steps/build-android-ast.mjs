#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {readSourcePins} from '../../native-llvm-inputs.mjs';
import {checkoutExactSource} from '../../../build/lib/git.mjs';
import {probeRequirement} from '../../release/platform-matrix.mjs';
import {crossBuildJobs} from '../lib/cross-build-jobs.mjs';

$.stdio = 'inherit';
const {CANGJIE_WORKSPACE:workspace, CJCJ_BOOTSTRAP_WORK:bootstrap} = process.env;
const stage = JSON.parse(await fs.readFile(path.join(bootstrap, 'sdk-stage2/STAGE-INPUTS.json')));
const pins = readSourcePins();
const root = path.join(workspace, 'android-ast');
const source = process.env.CJCJ_ANDROID_AST_SOURCE || path.join(root, 'src');
const llvm = process.env.CJCJ_ANDROID_AST_LLVM_SOURCE || path.join(root, 'llvm');
const build = process.env.CJCJ_ANDROID_AST_BUILD || path.join(root, 'build');
const install = path.join(workspace, 'software/android-ast-support');
const ast = stage.sources.ast ?? {repository:pins.source.COMPILER_SRC_URL, commit:pins.source.COMPILER_REF};
const deps = [[source,ast.repository,ast.commit], [llvm,stage.sources.llvm.repository,stage.sources.llvm.commit],
  [path.join(source,'third_party/boundscheck'),pins.source.BOUNDS_SRC_URL,pins.source.BOUNDS_REF],
  [path.join(source,'third_party/flatbuffers'),pins.llvm.FLATBUFFERS_URL,pins.llvm.FLATBUFFERS_SHA]];
// CI prepares private source trees. Managed builds supply the already prepared
// AST/LLVM paths and pinned dependency copies, because upstream patches both dependencies.
if (!process.env.CJCJ_ANDROID_AST_SOURCE && process.env.GITHUB_ACTIONS === 'true') {
  for (const [dir,url,commit] of deps) await checkoutExactSource(url, dir, commit);
}
for (const [dir,,commit] of deps.slice(0,2)) {
  if ((await $({stdio:'pipe'})`git -C ${dir} rev-parse HEAD`).stdout.trim() !== commit) throw Error('ANDROID_AST_SOURCE '+dir);
}
await fs.access(path.join(source, 'third_party/boundscheck/include/securec.h'));
const flat = path.join(source, 'third_party/flatbuffers');
await fs.access(path.join(flat,'CMakeLists.txt'));
const probe = probeRequirement('android-ndk');
if (!probe.present) throw Error(probe.detail);
const ndk = await fs.realpath(probe.detail.slice(probe.detail.indexOf('=')+1));
const jobs = crossBuildJobs();
const env = {...process.env, ANDROID_NDK_ROOT:ndk, CMAKE_BUILD_PARALLEL_LEVEL:String(jobs)};
delete env.CMAKE_TOOLCHAIN_FILE; // host flatc must use its native compiler
const cmake = $({env});
const options = ['-G','Ninja','-DCMAKE_BUILD_TYPE=Release',
  '-DCMAKE_TOOLCHAIN_FILE='+path.join(source,'cmake/android_aarch64_toolchain.cmake'),
  '-DCMAKE_ANDROID_NDK='+ndk,'-DCMAKE_ANDROID_API=23','-DCMAKE_TRY_COMPILE_PLATFORM_VARIABLES=CMAKE_ANDROID_NDK;CMAKE_ANDROID_API'];
await cmake`cmake -S ${source} -B ${build} ${options} -DCANGJIE_BUILD_CJC=OFF -DCANGJIE_BUILD_STD_SUPPORT=ON -DCANGJIE_SKIP_BUILD_CLANG_RT=ON -DCANGJIE_BUILD_TESTS=OFF -DCANGJIE_BUILD_CJDB=OFF -DCANGJIE_CJNATIVE_SOURCE_DIR=${llvm} -DCMAKE_INSTALL_PREFIX=${install}`;
// The target FlatBuffers ExternalProject forwards the toolchain but omits
// NDK/API; initialize that child cache before Ninja configures it.
await cmake`cmake -S ${flat} -B ${path.join(build,'third_party/flatbuffers-prefix/src/flatbuffers-build')} ${options} -DFLATBUFFERS_BUILD_FLATC=OFF -DFLATBUFFERS_BUILD_TESTS=OFF -DFLATBUFFERS_BUILD_FLATHASH=OFF -DCMAKE_INSTALL_PREFIX=${build}`;
await cmake`cmake --build ${build} --target cangjie-ast-support boundscheck boundscheck-static --parallel ${jobs}`;
await cmake`cmake --install ${build}`;
