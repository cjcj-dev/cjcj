#!/usr/bin/env zx
// Only the mutable execution harnesses are private; test cases stay in the
// selected worktree. No source corpus export or file-inventory authentication.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
async function replaceOnce(file, before, after) {
  const text = await fs.readFile(file, 'utf8');
  if (text.split(before).length !== 2) throw Error('upstream scheduling anchor mismatch: ' + file);
  await fs.writeFile(file, text.replace(before, after));
}
export async function prepare(inputs, output) {
  const test = await fs.realpath(path.join(inputs, 'cangjie_test'));
  const sourceFramework = await fs.realpath(path.join(inputs, 'cangjie_test_framework'));
  const destination = path.join(output, 'execution-harnesses');
  await fs.mkdir(destination);
  const harness = path.join(destination, 'conformance');
  const framework = path.join(destination, 'framework');
  const options = {recursive: true, filter: file => !['.git', '__pycache__'].includes(path.basename(file))};
  await fs.cp(path.join(test, 'Conformance/Compiler/harness'), harness, options);
  await fs.mkdir(framework);
  await fs.copyFile(path.join(sourceFramework, 'main.py'), path.join(framework, 'main.py'));
  await fs.cp(path.join(sourceFramework, 'maple_test'), path.join(framework, 'maple_test'), options);
  for (const root of [framework, harness]) await fs.copyFile(path.join(here, 'admission.py'), path.join(root, 'admission.py'));
  await replaceOnce(path.join(framework, 'maple_test/run.py'), '    remain_time = timeout\n',
    '    from admission import wait_for_load\n    wait_for_load(case_path)\n    remain_time = timeout\n');
  for (const phase of ['compile', 'execute']) {
    const anchor = `    '''Choose ${phase === 'compile' ? 'compilation' : 'execution'} driver for tests'''\n`;
    await replaceOnce(path.join(harness, 'core/driver_manager.py'), anchor,
      anchor + '    from admission import wait_for_load\n    wait_for_load(test.test_path)\n');
  }
  await replaceOnce(path.join(harness, 'core/task_manager.py'), '        self.reporter.write_test_result(test)\n',
    '        self.reporter.write_test_result(test)\n        from admission import cleanup_executable\n        cleanup_executable(test, self.cfg)\n');
  // Maple already copies each case's declared dependencies into its work dir.
  // Configure that private LSP dependency instead of writing the source tree.
  await replaceOnce(path.join(framework, 'maple_test/task.py'), '                shutil.copy(str(file), str(dest))\n',
    '                shutil.copy(str(file), str(dest))\n' +
    '                if os.environ.get("CANGJIE_TEST_LSP_TOOLS") and file.resolve() == (Path(os.environ["CANGJIE_TEST"]) / "testsuites/HLT/Tools/cjlsp/lsp_config.txt").resolve():\n' +
    '                    target = dest / file.name\n' +
    '                    text = target.read_text()\n' +
    '                    if text.count("${linux_lsp_server_path}") != 1:\n' +
    '                        raise ValueError("upstream LSP configuration anchor mismatch")\n' +
    '                    target.write_text(text.replace("${linux_lsp_server_path}", os.environ["CANGJIE_TEST_LSP_TOOLS"]))\n');
  return {test, framework, harness};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length !== 4) throw Error('Usage: zx ci/cangjie-test/adapt.mjs WORKTREES NEW_OUTPUT');
    console.log(JSON.stringify(await prepare(path.resolve(process.argv[2]), path.resolve(process.argv[3]))));
  } catch (error) {
    console.error('CANGJIE_TEST_ADAPTER: ' + error.message);
    process.exitCode = 2;
  }
}
