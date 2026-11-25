#!/usr/bin/env zx
// The full stdx and stage3 compiler installs are the tool producer's inputs.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {readJson,fileDigest,relative} from '../../../../../ci/bootstrap/sdk-flow.mjs';
import {sdkPlatform} from '../../../../../ci/bootstrap/sdk-platform.mjs';

if(process.platform!=='win32'||process.arch!=='x64')throw Error('WINDOWS_TOOLS_NATIVE_HOST_REQUIRED');
const env=process.env, sdk=await fs.realpath(path.join(env.CANGJIE_WORKSPACE, 'software', 'cangjie')),repo=await fs.realpath(env.GITHUB_WORKSPACE);
const native=sdkPlatform('windows_x86_64'), stage=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
if(stage.phase!=='stage3'||stage.platform!=='windows_x86_64'||stage.compilerCommit!==env.GITHUB_SHA)
  throw Error('WINDOWS_TOOLS_STAGE3_SOURCE');
const input=await fs.realpath(env.CJCJ_NATIVE_INPUT_ROOT),locations=await readJson(path.join(input,'locations.json'));
const jar=locations.cjprofLombok;
if(locations.platform!==stage.platform||!jar?.path||!jar.sha256)throw Error('WINDOWS_TOOLS_LOMBOK_INPUT');
const lombok=await fs.realpath(path.join(input,relative(jar.path)));
if(!lombok.startsWith(input+path.sep)||await fileDigest(lombok)!==jar.sha256)throw Error('WINDOWS_TOOLS_LOMBOK_BYTES');
const frontend=path.join(sdk,'share/cjcj/cjo'),shim=path.join(sdk,'share/cjcj/runtime_shim');
// cjpm and frontend consumers link the selected MSVCRT libc++ and unwind.
const mingw=await fs.realpath(env.CJCJ_WINDOWS_TOOLCHAIN);
const cc=await fs.realpath(path.join(mingw,'bin/clang.exe'));
const [type,version]=process.argv.slice(2);
const args=[path.join(repo,'build/cli.mjs'),'--target','windows-x64','--build-type',type,'--cangjie-version',version,
  '--tools-mangle-source',path.join(repo,'packages/mangle/src'),'--tools-frontend-source',repo,'--tools-frontend-ref',stage.compilerCommit,
  '--tools-analysis-sdk',sdk,'--tools-compiler-libs',frontend,'--tools-json-build',path.join(sdk,'stdx'),
  '--tools-runtime-config',path.join(shim,'cjc_runtime_config.o'),'--tools-llvm-shim',path.join(shim,'cjselfhost_llvmshim.o'),
  '--tools-llvm-library',path.join(sdk,'third_party/llvm',native.llvmDirectory,native.llvmLibrary),
  '--tools-runtime-header',path.join(env.CANGJIE_WORKSPACE,'native-sources/runtime/runtime/src/Cangjie.h'),
  '--tools-lombok-jar',lombok,'build','tools'];
const r=spawnSync(process.execPath,args,{stdio:'inherit',env:{...env,CC:cc,MINGW_PATH:mingw,CJFMT_FRONTEND_CJO:frontend,CJFMT_FRONTEND_LIB:frontend,
  CJFMT_FRONTEND_NATIVE:path.join(shim,'cjc_runtime_config.o'),CJFMT_FRONTEND_REF:stage.compilerCommit,CJFMT_SOURCE_REF:env.TOOLS_REF}});
if(r.error)throw r.error;
process.exitCode=r.status??1;
