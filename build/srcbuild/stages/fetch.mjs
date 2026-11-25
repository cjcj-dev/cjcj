// Port of cangjie-build/src/cangjie_build/stages/fetch.py.

import fs from 'node:fs';
import path from 'node:path';
import {saveSourceSelection} from '../../lib/config.mjs';
import {BuildError} from '../../lib/errors.mjs';
import {shallowClone, assertSourceIdentity} from '../../lib/git.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {applyTextPatch, ensureDir, requireFile} from './common.mjs';

const logger = getLogger('cangjie_build.stages.fetch');
// CMake >= 4.0 leaves CMAKE_OSX_SYSROOT empty on macOS unless it is set. The
// pinned debugserver (eb7ad012 lldb/tools/debugserver/source/CMakeLists.txt:184-187)
// passes it unquoted to mig, so an empty value makes mig take dbgnub-mig.defs as
// the -isysroot argument, read stdin and generate nothing (run 45420757561,
// macos-15, CMake 4.5.0: [979/1022] mach_excServer.c not found). Resolve the SDK
// for mig alone, from xcrun when unset, and fail configure when it cannot; the
// compile lines of every other LLDB object stay as they are.
export const DARWIN_DEBUGSERVER_MIG_SYSROOT = Object.freeze({
  before: 'add_custom_command(OUTPUT ${generated_mach_interfaces}\n' +
    '  VERBATIM COMMAND mig ${MIG_ARCH_FLAGS_SEPARTED} -isysroot ${CMAKE_OSX_SYSROOT} ${CMAKE_CURRENT_SOURCE_DIR}/MacOSX/dbgnub-mig.defs\n',
  after: [
    'if("${CMAKE_OSX_SYSROOT}" STREQUAL "")',
    '  execute_process(COMMAND xcrun --sdk macosx --show-sdk-path',
    '    RESULT_VARIABLE _lldb_mig_sdk_rc',
    '    OUTPUT_VARIABLE _lldb_mig_sysroot',
    '    ERROR_VARIABLE _lldb_mig_sdk_err',
    '    OUTPUT_STRIP_TRAILING_WHITESPACE)',
    '  if(NOT _lldb_mig_sdk_rc EQUAL 0 OR "${_lldb_mig_sysroot}" STREQUAL "")',
    '    message(FATAL_ERROR "debugserver: CMAKE_OSX_SYSROOT is empty and \'xcrun --sdk macosx --show-sdk-path\' gave no SDK for mig (rc=${_lldb_mig_sdk_rc}): ${_lldb_mig_sdk_err}")',
    '  endif()',
    'else()',
    '  set(_lldb_mig_sysroot "${CMAKE_OSX_SYSROOT}")',
    'endif()',
    'add_custom_command(OUTPUT ${generated_mach_interfaces}',
    '  VERBATIM COMMAND mig ${MIG_ARCH_FLAGS_SEPARTED} -isysroot "${_lldb_mig_sysroot}" ${CMAKE_CURRENT_SOURCE_DIR}/MacOSX/dbgnub-mig.defs',
    ''].join('\n'),
});

// Clang 23 diagnoses a new virtual member on a final class. Keep the
// out-of-line key functions and the same virtual slots in producers and users.
export function prepareWindowsLlvmSource(llvm) {
  for (const [folder, members] of [
    ['IR/ConstantFolder', ''],
    ['IR/NoFolder', ''],
    ['Analysis/InstSimplifyFolder', '  TargetFolder ConstFolder;\n  SimplifyQuery SQ;\n\n'],
  ]) {
    const name = path.basename(folder);
    const file = path.join(llvm, 'llvm/include/llvm', folder + '.h');
    const before = `class ${name} final : public IRBuilderFolder {`;
    const after = `class ${name} : public IRBuilderFolder {`;
    const stage = 'prepare.windows.llvm-folder';
    requireFile(file, {stage});
    const source = fs.readFileSync(file, 'utf8').replaceAll('\r\n', '\n');
    const declarations = source.split(before).length - 1 + (source.split(after).length - 1);
    const expected = source.includes(before) ? before : after;
    if (declarations !== 1 || !source.includes(`\n${expected}\n${members}  virtual void anchor();\n`))
      throw new BuildError(stage, `patch shape drift: expected one ${name} declaration with its anchor in ${file}`);
    applyTextPatch(file, [[before, after]], {stage, marker: after});
  }

  // Clang 23 + libc++ also exposes three source-shape failures in the pinned
  // LLVM/LLDB tree.  Check the complete old/new shape before calling
  // applyTextPatch: its marker fast-path is intentionally idempotent, but a
  // mixed tree (one edit applied and another missing) must fail closed.
  const patchWindowsFile = (relative, edits, stage, description) => {
    const file = path.join(llvm, relative);
    requireFile(file, {stage});
    const source = fs.readFileSync(file, 'latin1').replaceAll('\r\n', '\n');
    const count = text => source.split(text).length - 1;
    const states = edits.map(([oldText, newText]) => [count(oldText), count(newText)]);
    const unpatched = states.every(([oldCount, newCount]) => oldCount === 1 && newCount === 0);
    const patched = states.every(([oldCount, newCount]) => oldCount === 0 && newCount === 1);
    if (patched) return;
    if (!unpatched) {
      throw new BuildError(stage,
        `patch shape drift: expected one complete unpatched or patched ${description} form in ${file}`);
    }
    applyTextPatch(file, edits, {stage, marker: edits.map(([, newText]) => newText).join('\n')});
  };

  patchWindowsFile(
    'llvm/include/llvm/Demangle/ItaniumDemangle.h',
    [['#include <limits>\n#include <utility>', '#include <limits>\n#include <type_traits>\n#include <utility>']],
    'prepare.windows.llvm-demangle',
    'ItaniumDemangle include block',
  );
  patchWindowsFile(
    'llvm/tools/sancov/sancov.cpp',
    [
      ['SpecialCaseList::createOrDie({{ClBlacklist}},', 'SpecialCaseList::createOrDie({ClBlacklist.getValue()},'],
      ['SpecialCaseList::createOrDie({{ClIgnorelist}},', 'SpecialCaseList::createOrDie({ClIgnorelist.getValue()},'],
    ],
    'prepare.windows.llvm-sancov',
    'sancov blacklist call',
  );
  patchWindowsFile(
    'lldb/source/Plugins/Process/gdb-remote/GDBRemoteCommunicationServerLLGS.cpp',
    [["std::basic_string<uint8_t> zeros(reg_info.byte_size, '\\0');",
      "std::vector<uint8_t> zeros(reg_info.byte_size, '\\0');"]],
    'prepare.windows.lldb-gdb-remote',
    'LLGS zero buffer declaration',
  );
}

// Applied to prepare-native's private LLVM checkout. The parent toolchain
// stages boundscheck under aarch64; standalone CMake reports arm64 on macOS.
export function prepareDarwinLldbSource(llvm) {
  const base = path.join(llvm, 'lldb/source');
  for (const plugin of ['ExpressionParser/Cangjie', 'Platform/OHOS']) {
    const file = path.join(base, 'Plugins', plugin, 'CMakeLists.txt');
    const anchor = 'string(REPLACE "AMD64" "x86_64" ARCH_NAME "${CMAKE_SYSTEM_PROCESSOR}")';
    const normalize = 'string(REPLACE "arm64" "aarch64" ARCH_NAME "${ARCH_NAME}")';
    applyTextPatch(file, [[anchor, anchor + '\n' + normalize]], {stage:'prepare.darwin.bounds', marker:normalize});
  }
  const file = path.join(base, 'API/CMakeLists.txt');
  const before = 'target_link_options(liblldb PUBLIC "-Wl,-rpath,${CMAKE_SOURCE_DIR}/../utils/boundscheck/lib/${CMAKE_SYSTEM_PROCESSOR}")';
  const after = 'target_link_options(liblldb PRIVATE "-Wl,-rpath,@loader_path")';
  applyTextPatch(file, [[before, after]], {stage:'prepare.darwin.rpath', marker:after});
  const debugserver = path.join(llvm, 'lldb/tools/debugserver/source/CMakeLists.txt');
  const mig = DARWIN_DEBUGSERVER_MIG_SYSROOT;
  applyTextPatch(debugserver, [[mig.before, mig.after]], {stage:'prepare.darwin.debugserver-mig-sysroot', marker:mig.after});
}

// Applied to prepare-native's private LLVM checkout on Darwin. The pinned
// compiler-rt (eb7ad012 compiler-rt/lib/builtins/assembly.h:257-265) opens the
// CFI frame of every outline-atomic helper (aarch64/lse.S) before its global
// label; Xcode 16.4's assembler rejects a non-private label between
// .cfi_startproc and .cfi_endproc. Place the label first, as upstream LLVM
// e34b743e6c24 (llvm/llvm-project#73526) does.
const macroLine = text => text.padEnd(79) + '\\';
export const DARWIN_COMPILER_RT_OUTLINE_CFI = Object.freeze({
  before: [macroLine('  DECLARE_SYMBOL_VISIBILITY_UNMANGLED(name) SEPARATOR'), macroLine('  CFI_START SEPARATOR'),
    macroLine('  DECLARE_FUNC_ENCODING'), '  name: SEPARATOR BTI_C'].join('\n'),
  after: [macroLine('  DECLARE_SYMBOL_VISIBILITY_UNMANGLED(name) SEPARATOR'), macroLine('  DECLARE_FUNC_ENCODING'),
    macroLine('  name: SEPARATOR'), '  CFI_START SEPARATOR BTI_C'].join('\n'),
});
export function prepareDarwinCompilerRtSource(llvm) {
  const file = path.join(llvm, 'compiler-rt/lib/builtins/assembly.h');
  const {before, after} = DARWIN_COMPILER_RT_OUTLINE_CFI;
  applyTextPatch(file, [[before, after]], {stage:'prepare.darwin.compiler-rt-cfi', marker:after});
  // xray_trampoline_x86_64.S (built for x86_64/x86_64h osx) spells its branch
  // targets .Lxxx, which Mach-O does not treat as assembler-local: each becomes a
  // symbol that splits the function into atoms, and Xcode 16.4 then rejects the
  // following .cfi_adjust_cfa_offset ("invalid CFI advance_loc expression", run
  // 45385716455 step 5510/6066). assembly.h's LOCAL_LABEL is L_ on Apple and
  // .L_ on ELF, as current upstream LLVM uses in this file.
  const xray = path.join(llvm, 'compiler-rt/lib/xray/xray_trampoline_x86_64.S');
  applyTextPatch(xray, DARWIN_XRAY_X86_64_LOCAL_LABELS.flatMap(name => [[`.L${name}`, `LOCAL_LABEL(${name})`], [`.L${name}`, `LOCAL_LABEL(${name})`]]),
    {stage:'prepare.darwin.compiler-rt-xray-labels', marker:'LOCAL_LABEL(typedEventCleanup):'});
}
export const DARWIN_XRAY_X86_64_LOCAL_LABELS = Object.freeze(['tmp0', 'tmp2', 'tmp4', 'arg1entryLog', 'arg1entryFail', 'customEventCleanup', 'typedEventCleanup']);

// Applied to prepare-native's private LLVM checkout on every host. The pinned
// lldb/bindings/python/python-typemaps.swig still spells Python 2 PyInt_* calls
// that only resolved through SWIG's own pyhead.swg compatibility macros
// (PyInt_Check/PyInt_AsLong/PyInt_FromLong -> PyLong_*). SWIG 4.5 removed those
// macros, so LLDBWrapPython.cpp fails to compile (run 45410608964, macos-15,
// Homebrew SWIG 4.5.1, [942/1022]). Spell the Python 3 API directly, as current
// upstream LLDB does; SetNumberFromPyObject keeps only its PyLongAsT<T> branch so
// unsigned/64-bit numbers are not narrowed through PyLong_AsLong.
export const LLDB_SWIG_PYTHON3_TYPEMAPS = Object.freeze([
  ['  if (!PyInt_Check($input)) {', '  if (!PyLong_Check($input)) {'],
  ['  $2 = PyInt_AsLong($input);\n  if ($2 <= 0) {', '  $2 = PyLong_AsLong($input);\n  if ($2 <= 0) {'],
  ['  if (!PyInt_Check($input)) {', '  if (!PyLong_Check($input)) {'],
  ['  $2 = PyInt_AsLong($input);\n  if ($2 <= 0) {', '  $2 = PyLong_AsLong($input);\n  if ($2 <= 0) {'],
  ['  if (PyInt_Check($input)) {\n    $2 = PyInt_AsLong($input);\n  } else if (PyLong_Check($input)) {\n',
    '  if (PyLong_Check($input)) {\n'],
  ['  if (PyInt_Check(obj))\n    number = static_cast<T>(PyInt_AsLong(obj));\n  else if (PyLong_Check(obj))\n',
    '  if (PyLong_Check(obj))\n'],
  ['    PyObject *item = PyInt_FromLong($1[j]);', '    PyObject *item = PyLong_FromLong($1[j]);'],
].map(edit => Object.freeze(edit)));
export const LLDB_SWIG_PYTHON3_MARKER = 'bool SetNumberFromPyObject(T &number, PyObject *obj) {\n  if (PyLong_Check(obj))\n    number = PyLongAsT<T>(obj);';
export function prepareLldbSwigPython3Source(llvm) {
  const file = path.join(llvm, 'lldb/bindings/python/python-typemaps.swig');
  const stage = 'prepare.lldb.swig-python3';
  applyTextPatch(file, LLDB_SWIG_PYTHON3_TYPEMAPS, {stage, marker:LLDB_SWIG_PYTHON3_MARKER});
  const text = fs.readFileSync(file, 'utf8').replaceAll('\r\n', '\n');
  if (!text.includes(LLDB_SWIG_PYTHON3_MARKER) || /\bPy(Int|String|File)_/.test(text))
    throw new BuildError(stage, `Python 2 API remains in ${file}`);
}

export async function fetchRepos(config,names) {
  for (const name of names) {
    const repo=config.repo(name);
    const target = path.join(config.workspace, repo.dirName);
    if (fs.existsSync(target)) {
      logger.info('Checking existing repo %s at %s', repo.name, target);
    } else {
      await shallowClone(repo.url, target, {tag: repo.tag});
    }
    await assertSourceIdentity(repo, target);
  }
}

export async function run(config) {
  ensureDir(config.workspace);
  await stage('fetch', async () => {
    await fetchRepos(config,Object.keys(config.repos));
    const windows = config.target.spec.nodePlatform === 'win32';
    if (windows) prepareWindowsLlvmSource(config.repoPath('llvm'));
    saveSourceSelection(config);
  });
}
