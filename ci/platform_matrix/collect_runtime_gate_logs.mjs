import fs from 'node:fs/promises';
import path from 'node:path';

const source = path.join(process.env.RUNTIME_SOURCE || path.join(process.cwd(), 'runtime-source'), 'runtime');
const output = path.join(process.env.PLATFORM_CI_ROOT || path.join(process.cwd(), '.platform-ci'), 'logs', 'gc-unit');
const names = new Set(['gate_run.log', 'gate.status', 'gc-unit.status', 'gc_unit_gate.status', 'teardown.log', 'teardown.rc', 'teardown-artifacts.sha256', 'other_vm_exit.log']);
let count = 0;

async function collect(directory) {
  let entries;
  try {
    entries = await fs.readdir(directory, {withFileTypes: true});
  } catch (error) {
    if (error.code === 'ENOENT' && directory === source) return;
    throw error;
  }
  for (const entry of entries) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      await collect(file);
    } else if (entry.isFile() && (names.has(entry.name)||path.relative(source,file).split(path.sep).slice(0,2).join('/')==='CMakebuild/gc-unit-runs')) {
      const relative = path.relative(source, file);
      const destination = path.join(output, relative);
      await fs.mkdir(path.dirname(destination), {recursive: true});
      await fs.copyFile(file, destination);
      console.log(`RUNTIME_GATE_LOG path=${relative}`);
      count++;
    }
  }
}

await collect(source);
if (count === 0) console.log('::warning::No runtime gate diagnostics found; the build may have stopped before the gate ran.');
