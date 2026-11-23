import fs from 'node:fs/promises';
import path from 'node:path';
import {fileDigest, privateRoot, publishPaths} from '../../../../../ci/bootstrap/sdk-flow.mjs';
import {verifyCompiler} from '../../../../../ci/bootstrap/compiler_identity.mjs';
import {installCrossRuntime} from '../../release/cross-runtime.mjs';
import {installedStageOutput} from './installed-stage-output.mjs';

export const tuple = 'linux_ohos_aarch64_cjnative';
const roots = ['lib', 'runtime/lib', 'modules'].map(dir => path.join(dir, tuple));
const hostRef = '9991cf4f4c9cb3465bb5aec28a5590f6c529be4e';
const compiler = 'ea6d3b5fc73b5e4cc2926535005a46a92109b2b9';
const llvm = 'f2a8e33d2dbb6797d65813cd20f529d9567843a1';
export const targetRef = '3ca5bb660b9bc628cd76d037d478aa13223e167c';
export const astFile = path.join('lib', tuple, 'libcangjie-ast-support.a');
const astSha = '4aaff79751207a54552fd8cf1a340466c59e2cd1e02681cfe2bc147f90fa4f65';
const compilerHashes = {
  stage2: 'ab8e03d32d95b8a84da42a4d11520b2644796cc339e50825426bb38bf5c33be0',
  stage3: '5190316791e889c882684361d79a8fc70f7a1f9d606316b3cde032bf0c5f6fc1',
};

export function checkPair(stage, selectedHost, selectedTarget, actual, targetTuple) {
  if (targetTuple !== tuple || selectedTarget !== targetRef || actual !== targetRef ||
      selectedHost !== hostRef || stage.platform !== 'linux_x86_64' || stage.runtimeCommit !== hostRef ||
      stage.sources?.runtime?.commit !== hostRef || stage.sources?.std?.commit !== hostRef ||
      stage.compilerCommit !== compiler || stage.sources?.compiler?.commit !== compiler ||
      stage.sources?.llvm?.commit !== llvm || (stage.llvmCommit !== undefined && stage.llvmCommit !== llvm) ||
      !Object.hasOwn(compilerHashes, stage.phase) || stage.compilerSha256 !== compilerHashes[stage.phase])
    throw Error(`OHOS split source mismatch: host=${stage.runtimeCommit} target=${actual} requested=${selectedTarget} tuple=${targetTuple} phase=${stage.phase}`);
}

export async function checkAst(file) {
  if (await fileDigest(file) !== astSha) throw Error('OHOS AST digest mismatch: ' + file);
  const {stdout} = await $({stdio:'pipe'})`readelf -hW ${file}`;
  const machines = [...stdout.matchAll(/^\s*Machine:\s*(.+)$/gm)];
  if (machines.length !== 70 || machines.some(([,name]) => name.trim() !== 'AArch64'))
    throw Error('OHOS AST requires 70 AArch64 objects: ' + file);
  console.log('OHOS_AST_OK', file, astSha, machines.length);
}

export async function checkExports(root) {
  const so = path.join(root, 'runtime/lib', tuple, 'libcangjie-runtime.so');
  const {stdout} = await $({stdio:'pipe'})`readelf --dyn-syms -W ${so}`;
  for (const symbol of ['g_cjHeapRangeStart','g_cjHeapRangeEnd','g_cjHeapRangeCount','g_cjLoadShift']) {
    const row = stdout.split('\n').find(s => {
      const [, , , type, bind, vis, ndx, name] = s.trim().split(/\s+/);
      return type === 'OBJECT' && bind === 'GLOBAL' && vis === 'DEFAULT' && /^\d+$/.test(ndx) &&
        name?.split('@')[0] === symbol;
    });
    if (!row) throw Error('OHOS local runtime missing exported object: ' + symbol);
    console.log(so, row.trim());
  }
}

export async function copyHost(parent, dest) {
  const excluded = new Set(roots.map(dir => path.join(parent, dir)));
  await fs.cp(parent, dest, {recursive:true, verbatimSymlinks:true, filter:p => !excluded.has(p)});
}

export async function installOhosStage3({parent, software, finalStd, stage2, globalExportFlag}) {
  if (globalExportFlag !== '0') throw Error('OHOS Stage3 requires verified GLOBAL_EXPORT_FLAG=0');
  const target = path.join(software, 'ohos-stage3', 'cangjie');
  await privateRoot(target);
  const input = await fs.realpath(parent);
  if (input === target || target.startsWith(input + path.sep) || input.startsWith(target + path.sep))
    throw Error('OHOS Stage3 output overlaps parent');
  const pending = await fs.mkdtemp(path.join(software, '.ohos-install-'));
  try {
    await copyHost(parent, pending);
    const {lineage} = await installedStageOutput(pending, 'stage3');
    checkPair(lineage, hostRef, targetRef, targetRef, tuple);
    await verifyCompiler(pending, compilerHashes.stage3);
    for (const rel of roots) await fs.cp(path.join(finalStd, rel), path.join(pending, rel), {recursive:true});
    await installCrossRuntime({root:path.join(finalStd, 'cross-runtime'), stage:pending, tuple, runtimeRef:targetRef});
    await checkAst(path.join(pending, astFile));
    await checkExports(pending);
    const provenance = await fs.readFile(path.join(finalStd, 'PROVENANCE.txt'), 'utf8');
    if (!provenance.split('\n').includes('STD_SOURCE_COMMIT = ' + targetRef)) throw Error('OHOS final std provenance mismatch');
    await fs.writeFile(path.join(pending, 'STD-PROVENANCE-' + tuple + '.txt'), provenance);
    await fs.writeFile(path.join(pending, 'OHOS-TARGET.json'), JSON.stringify({tuple, hostRuntimeCommit:hostRef,
      compilerCommit:compiler, llvmCommit:llvm, stage2CompilerSha256:stage2.compilerSha256,
      stage3CompilerSha256:lineage.compilerSha256, runtimeCommit:targetRef, stdCommit:targetRef,
      globalExportFlag, exportMap:'ohos_local_export.map', astSha256:astSha, fullHostToolsStdx:'NOT_INCLUDED'}, null, 2) + '\n');
    await publishPaths([{pending,destination:target}]);
  } finally { await fs.rm(pending, {recursive:true, force:true}); }
  console.log('OHOS_STAGE3_INSTALLED', target);
}
