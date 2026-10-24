// Validate existing flow and command records; these are provenance, not authority.
import fs from 'node:fs/promises';
import path from 'node:path';
export function flag(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : argv.find(v => v.startsWith(name + '='))?.slice(name.length + 1);
}
const sameCommand = (a, b) => a.cwd === b.cwd && JSON.stringify(a.argv) === JSON.stringify(b.argv);
const nativeStd = row => Array.isArray(row.argv) && path.basename(row.argv[1] || '') === 'sdk-native-stage.mjs'
  && flag(row.argv, '--kind') === 'std';
export async function acceptInstalledStd({file, source, output, commit, sdk, runtime, link, platform,
  compilerRuntime, heap, previous, expected}) {
  if (!file) throw new Error('STD_RESUME_RECORD missing');
  if (!previous || !expected) throw new Error('WORK_INPUTS_MISSING');
  if (compilerRuntime !== 'target') throw new Error('STD_RESUME_RECORD compiler-runtime');
  let text;
  try { text = await fs.readFile(file, 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') throw new Error('STD_RESUME_RECORD missing'); throw error; }
  const rows = text.split('\n').filter(l => l.startsWith('{')).flatMap(l => {
    try { return [JSON.parse(l)]; } catch { return []; }
  });
  // Only the last attempt touching this source or output can qualify. A later
  // failed/incomplete attempt invalidates an earlier successful installation.
  const attempts = rows.map((row, index) => ({row, index})).filter(({row}) => row.event === 'target-command'
    && nativeStd(row) && (flag(row.argv, '--source') === source || flag(row.argv, '--output') === output));
  const attempt = attempts.at(-1);
  const identity = attempt?.row;
  const required = {source, output, commit, sdk, runtime, platform, 'compiler-runtime': compilerRuntime};
  if (!identity || !sameCommand(identity, expected)
      || Object.entries(required).some(([k,v]) => flag(identity.argv, '--'+k) !== v)
      || flag(identity.argv, '--heap') !== heap
      || identity.argv.includes('--resume-installed')) throw new Error('STD_RESUME_RECORD identity');
  const last = previous.commands?.filter(row => nativeStd(row)
    && (flag(row.argv, '--source') === source || flag(row.argv, '--output') === output)).at(-1);
  const old = last?.argv.includes('--resume-installed') ? last.resumeOf : last;
  const after = rows.slice(attempt.index + 1);
  const end = after.findIndex(row => row.event === 'target-result' && sameCommand(row, identity));
  const terminal = after[end];
  // The flow's own last result binds the selected log to this work/configuration
  // and attempt (including its measured wall/exit), not just identical argv.
  if (!old || !terminal || !sameCommand(old, identity)
      || ['rc','signal','error','cancelled','wall'].some(k => old[k] !== terminal[k]))
    throw new Error('STD_RESUME_RECORD attempt');
  const stdlib = path.join(source, 'stdlib');
  const actions = after.slice(0, end).filter(row => row.cwd === stdlib && Array.isArray(row.argv)
    && row.argv.includes('build.py'));
  const buildArgv = ['python3','-I','build.py','build','-t','relwithdebinfo','--jobs'];
  const buildCommand = actions[0], build = actions[1], installCommand = actions[2], install = actions[3];
  const successful = (command, result) => command?.event === 'target-command'
    && result?.event === 'target-result' && sameCommand(command, result)
    && result.rc === 0 && !result.signal && !result.error && !result.cancelled;
  if (!successful(buildCommand, build) || build.argv.length !== 9
      || buildArgv.some((v,i) => build.argv[i] !== v) || !/^[1-9][0-9]*$/.test(build.argv[7])
      || build.argv[8] !== '--target-lib='+link) throw new Error('STD_RESUME_RECORD build');
  if (!successful(installCommand, install) || JSON.stringify(install.argv) !== JSON.stringify(
    ['python3','-I','build.py','install','--prefix',output])) throw new Error('STD_RESUME_RECORD install');
  if (actions.length !== 4 || after.slice(end + 1).some(row => row.cwd === stdlib
      && Array.isArray(row.argv) && row.argv.includes('build.py')))
    throw new Error('STD_RESUME_RECORD sequence');
  return {build, install, identity, terminal};
}
