import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {packageCompileOptions} from '../package-options.mjs';

const root = path.resolve(import.meta.dirname, '../../../../..');
const manifest = (value, extra = '') => `[package]\n  name = "p"\n  compile-option = ${value}\n${extra}`;

for (const [name, text, expected] of [
  ['missing key', '[package]\n  name = "p"\n', []],
  ['empty string', manifest('""'), []],
  ['basic string', manifest('"--cfg feature=on"'), ['--cfg', 'feature=on']],
  ['literal string', manifest("'--cfg feature=on'"), ['--cfg', 'feature=on']],
  ['TOML-escaped double-quoted argument', manifest('"--trimpath \\"/source space -g\\""'), ['--trimpath', '/source space -g']],
  ['single-quoted argument', manifest('"--trimpath \'/source space\'"'), ['--trimpath', '/source space']],
  ['JSON escape inside a quoted argument', manifest('"--trimpath \\"/a\\\\\\\\b c\\""'), ['--trimpath', '/a\\b c']],
  ['surrounding whitespace and comment', manifest('"  -O2   -g  " # debug'), ['-O2', '-g']],
  ['other tables ignored', `compile-option = "-root"\n${manifest('"-O2"')}[profile.build]\n  compile-option = "-other"\n`, ['-O2']],
  ['quoted key', '[package]\n  "compile-option" = "-O2"\n', ['-O2']],
]) {
  test(`compile-option accepted: ${name}`, () => {
    assert.deepEqual(packageCompileOptions(text), expected);
  });
}

for (const [name, text, message] of [
  ['non-string value', manifest('7'), /must be a string/],
  ['array value', manifest('["-g"]'), /must be a string/],
  ['trailing text', manifest('"-g" garbage'), /unexpected text after the string/],
  ['unterminated basic string', manifest('"-g'), /unterminated string/],
  ['unterminated literal string', manifest("'-g"), /unterminated string/],
  ['multi-line string', manifest('"""-g"""'), /multi-line string/],
  ['invalid TOML escape', manifest('"-\\q"'), /invalid escape/],
  ['repeated key', manifest('"-g"', '  compile-option = "-O2"\n'), /defined again/],
  ['dotted key', 'package.compile-option = "-g"\n', /dotted key/],
  ['unterminated quoted argument', manifest('"--trimpath \'/source space"'), /unsupported quoting/],
  ['quote inside an argument', manifest('"--trimpath=\\"/source space\\""'), /unsupported quoting/],
]) {
  test(`compile-option rejected: ${name}`, () => {
    assert.throws(() => packageCompileOptions(text, 'fixture/cjpm.toml'), error => {
      assert.match(error.message, /^fixture\/cjpm\.toml: \[package\] compile-option /);
      assert.match(error.message, message);
      return true;
    });
  });
}

test('every package manifest parses without package-specific compile options', async () => {
  const packages = (await fs.readdir(path.join(root, 'packages'), {withFileTypes: true}))
    .filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
  const declared = {};
  for (const pkg of packages) {
    const file = path.join(root, 'packages', pkg, 'cjpm.toml');
    const text = await fs.readFile(file, 'utf8').catch(error => error.code === 'ENOENT' ? null : Promise.reject(error));
    if (text === null) continue;
    const options = packageCompileOptions(text, file);
    if (options.length) declared[pkg] = options;
  }
  assert.deepEqual(declared, {});
});
