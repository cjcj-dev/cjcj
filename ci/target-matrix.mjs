import fs from 'node:fs';
import {ciBuildCells, ciProvisionCells, getTarget, platformTestCells} from '../build/lib/targets.mjs';

const mode = process.argv[2];
let outputs;
if (mode === 'ci') {
  outputs = {build: {include: ciBuildCells()}, provision: {include: ciProvisionCells()}};
} else if (mode === 'platform') {
  outputs = {matrix: {include: platformTestCells()}};
} else if (mode === 'arm-soak') {
  const {spec, sourceBuild} = getTarget('linux-aarch64');
  outputs = {
    targets: spec.key, runner: sourceBuild.runner, platform: spec.key,
    llvm_platform: spec.llvmPlatform, sdk_runtime_dir: spec.runtimeTuple,
    compiler_artifact: `final-compiler-${spec.key}`, std_artifact: `final-std-${spec.key}`,
  };
} else {
  throw new Error(`unknown target matrix: ${mode}`);
}
const text = Object.entries(outputs).map(([key, value]) => `${key}=${typeof value === 'string' ? value : JSON.stringify(value)}`).join('\n') + '\n';
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, text);
process.stdout.write(text);
