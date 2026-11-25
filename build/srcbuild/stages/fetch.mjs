// Port of cangjie-build/src/cangjie_build/stages/fetch.py.

import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {saveSourceSelection} from '../../lib/config.mjs';
import {BuildError} from '../../lib/errors.mjs';
import {shallowClone, assertSourceIdentity} from '../../lib/git.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {applyTextPatch, ensureDir, requireFile} from './common.mjs';

const logger = getLogger('cangjie_build.stages.fetch');
const BOUNDSCHECK_DEPENDS = 'DEPENDS cangjie-demangler boundscheck';

// Upstream da68cc5ae3028c724da470b703eff757402cba44. Both cjnative
// source paths copy the static archive on Windows during their patch step.
// The shared-library target alone cannot order that producer before the copy.
export function applyCompilerBoundscheckDependencies(repoDir) {
  const file = path.join(repoDir, 'third_party', 'CMakeLists.txt');
  const source = fs.readFileSync(file, 'utf8');
  const oldText = `${BOUNDSCHECK_DEPENDS})`;
  const newText = `${BOUNDSCHECK_DEPENDS} boundscheck-static)`;
  const count = text => source.split(text).length - 1;
  if (count(oldText) + count(newText) !== 2) {
    throw new BuildError('fetch.patch', `patch shape drift: expected both cjnative boundscheck dependencies in ${file}`);
  }
  if (source.includes(oldText)) fs.writeFileSync(file, source.replaceAll(oldText, newText));
}

// VERSION.txt is produced by the same normal cjnative POST_BUILD step for
// Git checkouts and selected archives. Do not require a fabricated repository.
export function applyCompilerLlvmVersion(repoDir) {
  const old = 'COMMAND git log -1 --oneline --decorate > ${CMAKE_BINARY_DIR}/${THIRD_PARTY_LLVM}/VERSION.txt';
  const replacement = 'COMMAND "${CJCJ_NATIVE_NODE}" "${CMAKE_CURRENT_SOURCE_DIR}/cmake/llvm-source-version.mjs" "${SOURCE_DIR}" "${CMAKE_BINARY_DIR}/${THIRD_PARTY_LLVM}/VERSION.txt" "${CJ_LLVM_COMMIT}"';
  applyTextPatch(path.join(repoDir, 'third_party', 'CMakeLists.txt'), [[old, replacement]], {
    stage: 'fetch.patch.llvm-version', marker: replacement,
  });
  fs.copyFileSync(fileURLToPath(new URL('../patches/llvm-source-version.mjs', import.meta.url)),
    path.join(repoDir, 'third_party', 'cmake', 'llvm-source-version.mjs'));
}

// Xml2.cmake normally builds and installs the selected source before CJDB.
// Follow that producer's shared-library chain at install time; its entity
// version need not equal the source release, and the SONAME may change.
export function applyCompilerXml2Install(repoDir) {
  const file = path.join(repoDir, 'third_party', 'cmake', 'BuildCJDB.cmake');
  for (const [entry, soname, entity] of [
    ['libxml2.dylib', 'libxml2.16.dylib', 'libxml2.2.14.0.dylib'],
    ['libxml2.so', 'libxml2.so.16', 'libxml2.so.2.14.0'],
  ]) {
    const old = `    install(FILES\n        \${CMAKE_BINARY_DIR}/third_party/xml2/lib/${entry}\n        \${CMAKE_BINARY_DIR}/third_party/xml2/lib/${soname}\n        \${CMAKE_BINARY_DIR}/third_party/xml2/lib/${entity}\n        DESTINATION third_party/llvm/lib)`;
    const replacement = `    install(CODE "file(INSTALL DESTINATION \\\"\\\${CMAKE_INSTALL_PREFIX}/third_party/llvm/lib\\\"\n        TYPE SHARED_LIBRARY FOLLOW_SYMLINK_CHAIN\n        FILES \\\"\${CMAKE_BINARY_DIR}/third_party/xml2/lib/${entry}\\\")")`;
    applyTextPatch(file, [[old, replacement]], {stage:'fetch.patch.xml2-install', marker:replacement});
  }
}

const BUILDCJDB_EDITS = [
  [
    'externalproject_get_property(cjnative BINARY_DIR)\nset(LLVM_GC_BINARY_DIR "${BINARY_DIR}")\n',
    'cmake_policy(SET CMP0114 NEW)\nexternalproject_get_property(cjnative BINARY_DIR)\nset(LLVM_GC_BINARY_DIR "${BINARY_DIR}")\n',
  ],
  [
    '    USES_TERMINAL_BUILD ON\n    DEPENDS cjnative)\n',
    '    USES_TERMINAL_BUILD ON\n    DEPENDS cjnative\n    STEP_TARGETS build configure)\n',
  ],
];
const SRC_CMAKE_EDITS = [[
  'if(CANGJIE_BUILD_CJDB)\n    add_dependencies(lldb cangjie-frontend)\nendif()\n',
  'if(CANGJIE_BUILD_CJDB)\n    add_dependencies(lldb cangjie-frontend)\n    if(TARGET lldb-build)\n        add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)\n    endif()\nendif()\n',
]];
const COMPILER_CJDB_REQUIREMENTS = [
  [path.join('third_party', 'cmake', 'BuildCJDB.cmake'), [
    'cmake_policy(SET CMP0114 NEW)',
    'STEP_TARGETS build configure',
  ]],
  [path.join('src', 'CMakeLists.txt'), [
    'add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)',
  ]],
];

export function verifyCompilerCjdbPatches(repoDir) {
  for (const [relativePath, requiredTexts] of COMPILER_CJDB_REQUIREMENTS) {
    const file = path.join(repoDir, relativePath);
    const source = fs.readFileSync(file, 'utf8').replaceAll('\r\n', '\n');
    for (const requiredText of requiredTexts) {
      if (!source.includes(requiredText)) {
        throw new BuildError('fetch.patch.verify', `required compiler patch text missing from ${file}: ${requiredText}`);
      }
    }
  }
}

export function applyCompilerCjdbPatches(repoDir) {
  applyTextPatch(path.join(repoDir, 'third_party', 'cmake', 'BuildCJDB.cmake'), BUILDCJDB_EDITS, {
    stage: 'fetch.patch', marker: 'STEP_TARGETS build configure',
  });
  applyTextPatch(path.join(repoDir, 'src', 'CMakeLists.txt'), SRC_CMAKE_EDITS, {
    stage: 'fetch.patch', marker: 'add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)',
  });
  verifyCompilerCjdbPatches(repoDir);
}

export function applyNativeCjdbConfigure(repoDir) {
  // Keep the public umbrella include in the same tree CMake installs. More
  // recent explicit compiler sources may already provide their own version.
  const header = path.join(repoDir,'include/cangjie/Utils/Casting.h');
  if (!fs.existsSync(header)) {
    fs.mkdirSync(path.dirname(header),{recursive:true});
    fs.copyFileSync(new URL('../patches/Casting.h',import.meta.url),header,fs.constants.COPYFILE_EXCL);
  }
  // The pinned LLDB plugin assumes compiler/build/build/schema. Our generated
  // headers live in the outer binary directory, including on resumed builds.
  const file = path.join(repoDir, 'third_party', 'cmake', 'BuildCJDB.cmake');
  const anchor = 'if(NOT "${LLDB_CMAKE_CXX_FLAGS}" STREQUAL "")';
  const replacement = 'string(APPEND LLDB_CMAKE_CXX_FLAGS " -I\\"${CMAKE_BINARY_DIR}/schema\\"")\n' + anchor;
  applyTextPatch(file, [[anchor, replacement]], {stage:'fetch.patch.cjdb-schema',marker:replacement});
  // LLVM_BUILD_ARG is Unix-only upstream. Python and the launcher must also
  // reach the standalone LLDB configure on native Windows.
  const args = '    CMAKE_ARGS ${LLDB_CMAKE_ARGS}';
  applyTextPatch(file, [[args, args + ' ${CJCJ_LLDB_ARGS}']], {stage:'fetch.patch.cjdb-args',marker:args + ' ${CJCJ_LLDB_ARGS}'});
}

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

// The installed public compiler headers include several generated schemas.
// Install the complete output set owned by the existing flatc target, including
// libs-only builds; never synthesize headers or copy them after CMake install.
export function applyCompilerSchemaInstall(repoDir) {
  const target = 'add_custom_target(CangjieFlatbuffersHeaders DEPENDS ${FLATC_OUTPUTS} ${FLATC_LIBAST_OUTPUTS})';
  const install = 'install(FILES ${FLATC_OUTPUTS} DESTINATION include/flatbuffers)';
  applyTextPatch(path.join(repoDir, 'schema', 'CMakeLists.txt'), [[target, target + '\n' + install]], {
    stage: 'fetch.patch.schema-install', marker: install,
  });
}

// Keep the reviewed 53da076 native Windows compiler/install changes when
// consuming canonical sources. Canonical Flatbuffer.cmake already forwards
// selected compilers and separates host flatc; preserve its newer recipe.
export function applyCompilerWindowsPatches(repoDir, patch = new URL('../patches/compiler-windows-native.patch', import.meta.url)) {
  const stage = 'fetch.patch.windows';
  const root = fs.realpathSync(repoDir);
  // This patch edits or creates files in place. Match each section to the
  // working bytes, including on reverse-check of an already created file.
  const sections = fs.readFileSync(patch, 'utf8').replaceAll('\r\n', '\n').split(/^(?=diff --git )/m);
  const input = sections.map(section => {
    const header = /^diff --git a\/(.+) b\/\1\n/.exec(section);
    if (!header || header[1].split('/').some(part => !part || part === '.' || part === '..') || /[\\:]/.test(header[1]))
      throw new BuildError(stage, 'compiler Windows patch shape drift: unsupported diff path');
    const file = path.join(root, header[1]);
    const crlf = fs.existsSync(file) && fs.readFileSync(file).includes('\r\n');
    return crlf ? section.replaceAll('\n', '\r\n') : section;
  }).join('');
  // Native preparation removes .git when copying the compiler. Even when the
  // copy lives inside a checkout, Git must interpret patch paths from the copy.
  const env = {...process.env, GIT_CEILING_DIRECTORIES: path.dirname(root)};
  const apply = (...args) => spawnSync('git', [
    '-c', 'core.autocrlf=false', '-c', 'core.whitespace=cr-at-eol', '-c', 'apply.ignoreWhitespace=no', 'apply', ...args, '-',
  ], {cwd: root, input, encoding: 'utf8', env});
  const check = apply('--check');
  if (check.status === 0) {
    const result = apply();
    if (result.status !== 0) throw new BuildError(stage, result.stderr || result.error?.message || `git apply exited ${result.status}`);
  } else if (apply('--reverse', '--check').status !== 0) {
    throw new BuildError(stage, `compiler Windows patch shape drift: ${check.stderr || check.error?.message}`);
  }

  // An explicit system name makes even a Windows-hosted LLVM configure a
  // cross build. Only a real cross build needs the separate NATIVE tools.
  const thirdParty = path.join(root, 'third_party/CMakeLists.txt');
  const system = 'list(APPEND LLVM_CMAKE_ARGS -DCMAKE_SYSTEM_NAME=Windows)';
  const triple = 'list(APPEND LLVM_CMAKE_ARGS -DLLVM_HOST_TRIPLE=x86_64-w64-mingw32)';
  const native = 'set(NATIVE_LLVM_CMAKE_ARGS -Wno-dev|-Wno-deprecated)';
  const flags = 'list(APPEND LLVM_CMAKE_ARGS -DCROSS_TOOLCHAIN_FLAGS_LLVM_NATIVE=${NATIVE_LLVM_CMAKE_ARGS})';
  const block = lines => ['            list(APPEND LLVM_CMAKE_ARGS -DSANITIZER_CXX_ABI=libc++)',
    ...lines.map(line => '            ' + line), ''].join('\n');
  const before = block([system, triple, native, flags]);
  const after = block([triple, 'if(NOT CMAKE_HOST_WIN32)', '    ' + system, '    ' + native, '    ' + flags, 'endif()']);
  const source = fs.readFileSync(thirdParty, 'latin1').replaceAll('\r\n', '\n');
  if ((!source.includes(before) && !source.includes(after)) ||
      [system, triple, native, flags].some(line => source.split(line).length !== 2))
    throw new BuildError(stage, `patch shape drift: expected one MinGW cjnative argument block in ${thirdParty}`);

  // The selected toolchain installs its own runtime DLLs. Keep the legacy
  // external project only for MinGW configurations without those files.
  const legacyMingw = '\n    if(MINGW)\n        include(AddMinGWLibs)\n    endif()\n    if(OHOS)\n';
  const fallbackMingw = legacyMingw.replace('if(MINGW)', 'if(MINGW AND NOT CANGJIE_TOOLCHAIN_RUNTIME_FILES)');
  if (source.split(/AddMinGWLibs/i).length !== 2 || (!source.includes(legacyMingw) && !source.includes(fallbackMingw)))
    throw new BuildError(stage, `patch shape drift: expected one AddMinGWLibs fallback in ${thirdParty}`);
  applyTextPatch(thirdParty, [[before, after]], {stage, marker: after});
  applyTextPatch(thirdParty, [[legacyMingw, fallbackMingw]], {stage, marker: fallbackMingw});

  // Both demangler targets use std::vector with BUILD_LIB_CANGJIE_DEMANGLE set.
  const guard = '#ifndef BUILD_LIB_CANGJIE_DEMANGLE';
  const vector = '#include <vector>';
  const includes = (first, second) => [
    '#define CANGJIE_DEMANGLER_H', '', '#include <array>', first, second, '#include "Base/CString.h"', '#endif', '',
  ].join('\n');
  const fixed = includes(vector, guard);
  applyTextPatch(path.join(root, 'demangler/Demangler.h'), [[includes(guard, vector), fixed]], {stage, marker: fixed});

  // libc++ does not expose these declarations through unrelated headers.
  for (const [file, before, include, after] of [
    ['src/AST/Searcher.cpp', '#include "cangjie/AST/Searcher.h"\n\n', '#include <iterator>\n', '#include <memory>'],
    ['src/Basic/Display.cpp', '#include <codecvt>\n#include <cassert>\n', '#include <locale>\n', '\n#include "cangjie/Basic/Print.h"'],
    ['src/Frontend/CompilerInstance.cpp', '#include "cangjie/Frontend/CompilerInstance.h"\n\n#include <fstream>\n', '#include <iterator>\n', '\n#include "PrintSymbolTable.h"'],
    ['include/cangjie/Modules/ModulesUtils.h', '#define CANGJIE_MODULES_UTILS_H\n\n', '#include <iterator>\n\n', '#include "cangjie/AST/Node.h"'],
    ['src/Parse/Parser.cpp', '#include "ParserImpl.h"\n\n', '#include <iterator>\n\n', '#include "cangjie/AST/Clone.h"'],
    ['src/Sema/InheritanceChecker/StructInheritanceChecker.cpp', '#include <algorithm>\n#include <cstddef>\n', '#include <iterator>\n', '#include <map>'],
    ['src/Sema/LegalityOfUsage/LegalityOfUsage.cpp', '#include "TypeCheckerImpl.h"\n\n', '#include <iterator>\n\n', '#include "Diags.h"'],
  ]) {
    const fixedIncludes = before + include + after;
    applyTextPatch(path.join(root, file), [[before + after, fixedIncludes]], {stage, marker: fixedIncludes});
  }

  // get() also joins the cleanup task and propagates its exceptions; always call it.
  const cleanup = '    future.get();', consumed = '    res = future.get() && res;';
  const stop = '\n    Utils::ProfileRecorder::Stop("Main Stage", "DeleteInstanceLeftTime");';
  applyTextPatch(path.join(root, 'src/Driver/Driver.cpp'), [[cleanup + stop, consumed + stop]], {stage, marker: consumed + stop});

  // Keep the base patch (and its reverse-check context) stable for cached sources.
  // The first toolchain read happens before CMake identifies the compiler.
  const findLld = 'find_program(lld_path lld${CMAKE_EXECUTABLE_SUFFIX})';
  const selectLinker = [
    'string(REPLACE [[\\]] "/" _cangjie_cc "${CMAKE_C_COMPILER}")',
    'get_filename_component(_cangjie_cc_name "${_cangjie_cc}" NAME)',
    'string(TOLOWER "${_cangjie_cc_name}" _cangjie_cc_name)',
    'set(_cangjie_clang FALSE)',
    'if(_cangjie_cc_name MATCHES "(^|-)clang([+][+])?(-[0-9.]+)?([.]exe)?$" OR CMAKE_C_COMPILER_ID STREQUAL "Clang")',
    '    set(_cangjie_clang TRUE)',
    'else()',
    '    ' + findLld,
    'endif()',
    'if(_cangjie_clang)',
    '    set(OTHER_FLAGS "${OTHER_FLAGS} -fuse-ld=lld")',
    '    get_filename_component(_cangjie_cc_dir "${CMAKE_C_COMPILER}" DIRECTORY)',
    '    if(_cangjie_cc_dir)',
    '        find_program(CMAKE_AR NAMES llvm-ar llvm-ar.exe HINTS "${_cangjie_cc_dir}" NO_DEFAULT_PATH)',
    '        find_program(CMAKE_RANLIB NAMES llvm-ranlib llvm-ranlib.exe HINTS "${_cangjie_cc_dir}" NO_DEFAULT_PATH)',
    '    endif()',
    'elseif(NOT lld_path)',
  ].join('\n');
  // The unchanged archive lookups below provide fallback; find_program also
  // respects tools already supplied by the caller.
  applyTextPatch(path.join(root, 'cmake/mingw_x86_64_toolchain.cmake'),
    [[findLld + '\nif(NOT lld_path)', selectLinker]], {stage, marker: selectLinker});
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

// Fetch and the source handoff must replay the same edits in the same order.
export function patchFetchedCompiler(dir, windows) {
  applyCompilerCjdbPatches(dir);
  applyCompilerBoundscheckDependencies(dir);
  applyCompilerSchemaInstall(dir);
  if (windows) applyCompilerWindowsPatches(dir);
}

export async function run(config) {
  ensureDir(config.workspace);
  await stage('fetch', async () => {
    await fetchRepos(config,Object.keys(config.repos));
    const windows = config.target.spec.nodePlatform === 'win32';
    patchFetchedCompiler(config.repoPath('compiler'), windows);
    if (windows) prepareWindowsLlvmSource(config.repoPath('llvm'));
    saveSourceSelection(config);
  });
}
