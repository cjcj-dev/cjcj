import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

const run = promisify(execFile);

export async function verifyRepeatedCjo({compiler, sourceDir, importPath, outputDir, timeoutCommand = 'timeout'}) {
  // Upstream SourceManager.cpp:107-115 hashes the absolute source path.
  // Cross-directory ELF reproducibility is covered by the release trimpath checks.
  console.log('[selfdet] verify same-directory repeated CJO compilation');
  const started = process.hrtime.bigint();
  await fs.mkdir(outputDir, {recursive: true});
  const output = path.join(outputDir, 'conditional_compilation.a');
  async function compile() {
    const {stdout, stderr} = await run(timeoutCommand, ['900', compiler,
      '--emit-chir=raw', '--output-type=staticlib', '--package', sourceDir,
      '--module-name', 'cjcj', '--import-path', importPath, `--trimpath=${sourceDir}`, '-o', output],
      {maxBuffer: 16 * 1024 * 1024});
    process.stdout.write(stdout);
    process.stderr.write(stderr);
    const cjos = (await fs.readdir(outputDir)).filter(name => name.endsWith('.cjo'));
    if (cjos.length !== 1) throw new Error(`selfdet expected one CJO, found ${cjos.length}`);
    const bytes = await fs.readFile(path.join(outputDir, cjos[0]));
    if (bytes.length === 0) throw new Error('selfdet CJO is empty');
    return bytes;
  }
  const first = await compile();
  await fs.rm(outputDir, {recursive: true});
  await fs.mkdir(outputDir, {recursive: true});
  const second = await compile();
  if (!first.equals(second)) throw new Error('selfdet repeated CJO compilation differs');
  console.log(`[selfdet] PASS bytes=${first.length} wall=${(Number(process.hrtime.bigint() - started) / 1e9).toFixed(3)}s`);
}
