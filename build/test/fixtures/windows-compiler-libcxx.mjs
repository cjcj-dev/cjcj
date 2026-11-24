#!/usr/bin/env zx
// Independent expectations for the source seen by fetch and the native configure command.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const fixture = fileURLToPath(new URL('./compiler-41b223-windows/', import.meta.url));
export const libcxxEdits = [
  ['src/AST/Searcher.cpp', '#include <memory>', '#include <iterator>\n#include <memory>'],
  ['src/Basic/Display.cpp', '#include <cassert>', '#include <cassert>\n#include <locale>'],
  ['src/Frontend/CompilerInstance.cpp', '#include <fstream>', '#include <fstream>\n#include <iterator>'],
  ['include/cangjie/Modules/ModulesUtils.h', '#include "cangjie/AST/Node.h"', '#include <iterator>\n\n#include "cangjie/AST/Node.h"'],
  ['src/Parse/Parser.cpp', '#include "ParserImpl.h"', '#include "ParserImpl.h"\n\n#include <iterator>'],
  ['src/Sema/InheritanceChecker/StructInheritanceChecker.cpp', '#include <map>', '#include <iterator>\n#include <map>'],
  ['src/Sema/LegalityOfUsage/LegalityOfUsage.cpp', '#include "Diags.h"', '#include <iterator>\n\n#include "Diags.h"'],
  ['src/Driver/Driver.cpp', '    future.get();', '    res = future.get() && res;'],
];
export function assertCompilerLibcxxEdits(root, eol) {
  for (const [file, old, updated] of libcxxEdits) {
    const bytes = fs.readFileSync(path.join(fixture, file), 'utf8');
    const original = bytes.replaceAll('\r\n', '\n');
    assert.ok(original.includes(old), 'missing upstream fixture anchor: ' + file);
    const expected = original.replace(old, updated).replaceAll('\n', eol ?? (bytes.includes('\r\n') ? '\r\n' : '\n'));
    assert.equal(fs.readFileSync(path.join(root, file), 'utf8'), expected, 'compiler libc++ patch: ' + file);
  }
}
