#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {buildConfig, saveSourceSelection} from '../../lib/config.mjs';

export const tuple = 'linux_x86_64_cjnative';
export const cli = path.resolve(import.meta.dirname, '../../cli.mjs');
export function write(file, text, mode = 0o644) {
  fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text, {mode});
}
export function run(cmd, args, options = {}) {
  const r = spawnSync(cmd, args, {encoding: 'utf8', ...options});
  assert.equal(r.status, 0, r.stdout + '\n' + r.stderr); return r;
}
export function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'stdx-facts-'));
  const evidence = process.env.STDX_FACTS_EVIDENCE
    ? path.join(process.env.STDX_FACTS_EVIDENCE, path.basename(root)) : null;
  if (evidence) fs.mkdirSync(evidence, {recursive: true});
  t.after(() => {
    if (evidence) { fs.writeFileSync(path.join(evidence, 'retained-root.txt'), root+'\n'); return; }
    fs.rmSync(root, {recursive: true, force: true});
  });
  const sdk = path.join(root, 'sdk'), host = path.join(root, 'host'), stdx = path.join(root, 'cangjie_stdx');
  for (const [base, source] of [[host, 'int plain;'], [sdk, 'long g_cjLoadBadMask;']]) {
    const file = path.join(base, 'runtime/lib', tuple, 'libcangjie-runtime.so');
    fs.mkdirSync(path.dirname(file), {recursive: true});
    run('cc', ['-shared', '-fPIC', '-x', 'c', '-', '-o', file], {input: source});
  }
  // Only the Cangjie boundary is controlled; native CMake libraries remain real.
  write(path.join(sdk, 'bin/cjc'), "#!/bin/sh\nif [ \"$1\" != \"\" ]; then\n  while [ \"$#\" -gt 0 ]; do\n    if [ \"$1\" = \"-o\" ]; then shift; printf '#!/bin/sh\\nexit \"${FIXTURE_FAIL_CONSUMER:-0}\"\\n' > \"$1\"; chmod +x \"$1\"; exit 0; fi\n    shift\n  done\nfi\nprintf \"%s\" \"$CANGJIE_STDX_PATH\"\n", 0o755);
  write(path.join(stdx, '.gitignore'), 'build_temp/\ntarget/\n');
  write(path.join(stdx, 'unit.c'), 'int stdx_fixture_value(void) { return 42; }\n');
  write(path.join(stdx, 'input.cj'), '// controlled custom-command source dependency\n');
  write(path.join(stdx, 'CMakeLists.txt'), String.raw`
cmake_minimum_required(VERSION 3.20)
project(stdx_facts_fixture C)
set(CANGJIE_INCLUDE "" CACHE PATH "compiler include")
set(CANGJIE_TARGET_LIB "" CACHE PATH "target library")
set(CANGJIE_TARGET_TOOLCHAIN "" CACHE PATH "target toolchain")
set(CANGJIE_TARGET_SYSROOT "" CACHE PATH "sysroot")
set(CANGJIE_BUILD_ARGS "" CACHE STRING "args")
option(CANGJIE_BUILD_STDLIB_WITH_COVERAGE "coverage" OFF)
foreach(feature CHIR SYNTAX EFFECT_HANDLERS PLUGIN ASPECT_CJ)
  option(CANGJIE_BUILD_WITHOUT_@{feature} "native stdx branch" OFF)
endforeach()
set(modules base)
if(NOT CANGJIE_BUILD_WITHOUT_CHIR)
  list(APPEND modules chir)
  if(NOT CANGJIE_BUILD_WITHOUT_PLUGIN)
    list(APPEND modules plugin)
  endif()
  if(NOT CANGJIE_BUILD_WITHOUT_ASPECT_CJ)
    list(APPEND modules aspect)
  endif()
endif()
if(NOT CANGJIE_BUILD_WITHOUT_SYNTAX)
  list(APPEND modules syntax)
endif()
if(NOT CANGJIE_BUILD_WITHOUT_EFFECT_HANDLERS)
  list(APPEND modules effects)
endif()
foreach(module IN LISTS modules)
  add_library(@{module}_static STATIC unit.c)
  add_library(@{module}_shared SHARED unit.c)
  install(TARGETS @{module}_static ARCHIVE DESTINATION linux_x86_64_cjnative/static/stdx)
  install(TARGETS @{module}_shared LIBRARY DESTINATION linux_x86_64_cjnative/dynamic/stdx)
  file(WRITE "@{CMAKE_CURRENT_BINARY_DIR}/stdx.@{module}.cjo" "from native install")
  foreach(kind static dynamic)
    install(FILES "@{CMAKE_CURRENT_BINARY_DIR}/stdx.@{module}.cjo" DESTINATION linux_x86_64_cjnative/@{kind}/stdx)
  endforeach()
endforeach()
add_custom_target(cj_entry ALL COMMAND @{CMAKE_COMMAND} -E env "LD_LIBRARY_PATH=$ENV{LD_LIBRARY_PATH}" cjc file.cj VERBATIM)
add_custom_command(OUTPUT "@{CMAKE_CURRENT_BINARY_DIR}/custom.cjo"
  COMMAND @{CMAKE_COMMAND} -E copy "@{CMAKE_CURRENT_SOURCE_DIR}/input.cj" "@{CMAKE_CURRENT_BINARY_DIR}/custom.cjo"
  DEPENDS input.cj)
add_custom_target(custom_cj ALL DEPENDS "@{CMAKE_CURRENT_BINARY_DIR}/custom.cjo")
`.replaceAll('@{', '${'));
  write(path.join(stdx, 'build.py'), String.raw`import sys,os,pathlib,json,subprocess,shutil
root=pathlib.Path(os.environ['FIXTURE_ROOT'])
build=pathlib.Path('build_temp/build')
if sys.argv[1]=='clean':
 for p in ['build_temp','target']: shutil.rmtree(p,ignore_errors=True)
if sys.argv[1]=='build':
 if os.environ.get('FIXTURE_FAIL_BUILD'): sys.exit(23)
 selected=subprocess.check_output(['cjc'],text=True)
 with (root/'consumer.jsonl').open('a') as f: f.write(json.dumps(selected)+'\n')
 args=['cmake','-S','.', '-B',str(build),'-G','Ninja','-DCMAKE_BUILD_TYPE='+sys.argv[sys.argv.index('-t')+1],'-DCMAKE_INSTALL_PREFIX='+str(pathlib.Path('target').resolve())]
 for flag,key in [('--skip-chir','CHIR'),('--skip-syntax','SYNTAX'),('--without-effect-handlers','EFFECT_HANDLERS')]:
  args+=['-DCANGJIE_BUILD_WITHOUT_'+key+'='+('ON' if flag in sys.argv else 'OFF')]
 args+=['-DCANGJIE_INCLUDE='+next(a.split('=',1)[1] for a in sys.argv if a.startswith('--include=')),'-DCANGJIE_TARGET_LIB='+next((a.split('=',1)[1] for a in sys.argv if a.startswith('--target-lib=')),'')]
 if not build.exists():
  if os.environ.get('FIXTURE_FAIL_CONFIGURE'): sys.exit(25)
  subprocess.run(args,check=True)
 subprocess.run(['cmake','--build',str(build),'--parallel','2'],check=True)
if sys.argv[1]=='install':
 args=['cmake','--install',str(build)]
 if '--prefix' in sys.argv: args+=['--prefix',sys.argv[sys.argv.index('--prefix')+1]]
 subprocess.run(args,check=True)
 if os.environ.get('FIXTURE_FAIL_INSTALL'): sys.exit(24)
`);
  run('git', ['init', '-q', stdx]);
  run('git', ['-C', stdx, 'remote', 'add', 'origin', 'https://gitcode.com/Cangjie/cangjie_stdx.git']);
  run('git', ['-C', stdx, 'add', '.']);
  run('git', ['-C', stdx, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'Native stdx facts fixture']);
  let commit = run('git', ['-C', stdx, 'rev-parse', 'HEAD']).stdout.trim();
  saveSourceSelection(buildConfig({workspace:root,repoOverrides:{stdx:{url:'https://gitcode.com/Cangjie/cangjie_stdx.git',tag:commit}}}));
  const env = {...process.env, CC: process.env.CC || '/usr/lib/llvm-15/bin/clang',
    CXX: process.env.CXX || '/usr/lib/llvm-15/bin/clang++',
    FIXTURE_ROOT: root, CJCJ_SRCBUILD_HOST_SDK: host, CJCJ_SRCBUILD_CONSUMER_SDK: sdk};
  delete env.CANGJIE_BUILD_DRY_RUN; delete env.CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE;
  env.CANGJIE_STDX_PATH = path.join(root, 'unrelated-host-stdx');
  const args = [cli, '--workspace', root, '--build-root', path.join(root, 'buildtools'), '--host-profile', 'kkk2'];
  let invocation = 0;
  const build = (options = [], overrides = {}) => {
    const argv = [...args, ...options, 'build', 'stdx'], start = new Date().toISOString();
    const result = spawnSync(process.execPath, argv,
      {encoding: 'utf8', env: {...env, ...overrides}, timeout: 45000, maxBuffer: 4 * 1024 ** 2});
    if (evidence) {
      const prefix = path.join(evidence, 'invocation-' + ++invocation);
      fs.writeFileSync(prefix + '.stdout', result.stdout || ''); fs.writeFileSync(prefix + '.stderr', result.stderr || '');
      fs.writeFileSync(prefix + '.json', JSON.stringify({argv, start, end: new Date().toISOString(),
        rc: result.status, signal: result.signal, error: result.error?.message, sourceCommit: commit}, null, 2) + '\n');
    }
    return result;
  };
  const freezeSource = () => {
    run('git', ['-C',stdx,'add','.']);
    run('git', ['-C',stdx,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Freeze controlled stdx producer variant']);
    commit=run('git',['-C',stdx,'rev-parse','HEAD']).stdout.trim();
    saveSourceSelection(buildConfig({workspace:root,repoOverrides:{stdx:{url:'https://gitcode.com/Cangjie/cangjie_stdx.git',tag:commit}}}));
    return commit;
  };
  return {root, sdk, host, stdx, commit, env, args, build, freezeSource};
}
