import fs from 'node:fs';
import path from 'node:path';
const withEol = (text, eol) => text.replace(/\r?\n/g, eol);

// Declaration excerpts from llvm@eb7ad012. The Analysis folder owns data
// members before its key function; IR's two folders declare it immediately.
export function putLlvmFolders(root, eol = '\n') {
  return ['IR/ConstantFolder', 'IR/NoFolder', 'Analysis/InstSimplifyFolder'].map(rel => {
    const name = path.basename(rel), file = path.join(root, 'llvm/include/llvm', rel + '.h');
    const lines = ['namespace llvm {', `class ${name} final : public IRBuilderFolder {`];
    if (name === 'InstSimplifyFolder') lines.push('  TargetFolder ConstFolder;', '  SimplifyQuery SQ;', '');
    lines.push('  virtual void anchor();', '', 'public:', '  // unrelated final stays here', '};', '}', '');
    const original = lines.join(eol), expected = original.replace(name + ' final :', name + ' :');
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, original);
    return {file, original, expected};
  });
}

// Minimal excerpts of the three Clang 23/libc++ failures from llvm@eb7ad012.
// They keep the production path tests small while preserving each exact edit
// anchor and the source tree's selected line ending.
export function putLlvmWindowsFixes(root, eol = '\n') {
  const files = [
    ['llvm/include/llvm/Demangle/ItaniumDemangle.h',
      '#include "Utility.h"\n#include <limits>\n#include <utility>\n',
      '#include "Utility.h"\n#include <limits>\n#include <type_traits>\n#include <utility>\n'],
    ['llvm/tools/sancov/sancov.cpp',
      'return SpecialCaseList::createOrDie({{ClBlacklist}},\n'
      + '                                          *vfs::getRealFileSystem());\n'
      + 'return SpecialCaseList::createOrDie({{ClIgnorelist}},\n'
      + '                                        *vfs::getRealFileSystem());\n',
      'return SpecialCaseList::createOrDie({ClBlacklist.getValue()},\n'
      + '                                          *vfs::getRealFileSystem());\n'
      + 'return SpecialCaseList::createOrDie({ClIgnorelist.getValue()},\n'
      + '                                        *vfs::getRealFileSystem());\n'],
    ['lldb/source/Plugins/Process/gdb-remote/GDBRemoteCommunicationServerLLGS.cpp',
      "#include <limits>\n\nvoid f() { std::basic_string<uint8_t> zeros(reg_info.byte_size, '\\0'); }\n",
      "#include <limits>\n\nvoid f() { std::vector<uint8_t> zeros(reg_info.byte_size, '\\0'); }\n"],
  ];
  return files.map(([relative, original, expected]) => {
    const file = path.join(root, relative);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, withEol(original, eol));
    return {file, original: withEol(original, eol), expected: withEol(expected, eol)};
  });
}
