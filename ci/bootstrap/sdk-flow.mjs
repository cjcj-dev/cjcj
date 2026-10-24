#!/usr/bin/env zx
// Native targets own compilation and installation. This file only orders them,
// copies explicitly selected outputs, tests that installation, and archives it.
import fs from 'node:fs/promises';
import {fstatSync} from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn, execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {AsyncLocalStorage} from 'node:async_hooks';
import {supervisedCommand} from './sdk-command-lifetime.mjs';
import {acceptInstalledStd, flag} from './sdk-std-resume.mjs';
import {installEntries} from './sdk-install-entries.mjs';
import {effectiveSourceRoot, bindNativeSource, nativeSourceOptions} from './sdk-source.mjs';
const cancellation = new AsyncLocalStorage();
const supervisionWork = new AsyncLocalStorage();
export async function withProcessCancellation(run) {
  const controller = new AbortController();
  const handlers = Object.fromEntries(['SIGTERM','SIGINT'].map(name => [name, () => {
    if (!controller.signal.aborted) controller.abort(Object.assign(new Error('SDK_CANCELLED'),
      {cancellationSignal:name, rc:name === 'SIGINT' ? 130 : 143}));
  }]));
  for (const [name,handler] of Object.entries(handlers)) process.on(name,handler);
  try {
    const result = await cancellation.run(controller.signal, () => run(controller.signal));
    controller.signal.throwIfAborted();
    return result;
  } finally { for (const [name,handler] of Object.entries(handlers)) process.removeListener(name,handler); }
}


export const fileDigest = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
export const readJson = async file => JSON.parse(await fs.readFile(file, 'utf8'));
const capture = promisify(execFile);
export const atomicJson = async (file, value) => {
  await fs.mkdir(path.dirname(file), {recursive: true});
  const tmp = `${file}.${process.pid}.tmp`;
  await fs.writeFile(tmp, JSON.stringify(value, null, 2)+'\n');
  await fs.rename(tmp, file);
};
export function relative(value) {
  if (typeof value !== 'string' || path.isAbsolute(value) || value.includes('\\')
    || value.split('/').some(p => p === '..' || p === '.') || value.includes('\0'))
    throw new Error(`INSTALL_PATH ${value}`);
  return value;
}
export async function privateRoot(root) {
  root = path.resolve(root);
  if (root === path.parse(root).root || ['/root/sdks', '/root/.cjv'].some(p => root === p || root.startsWith(p+'/')))
    throw new Error(`SHARED_INSTALL ${root}`);
  // Check each existing ancestor, including symlinks to the shared SDKs.
  let parent = root;
  while (true) {
    try {
      if (await fs.realpath(parent) !== parent) throw new Error(`INSTALL_LINK ${parent}`);
      break;
    } catch (e) { if (e.code !== 'ENOENT') throw e; parent = path.dirname(parent); }
  }
  return root;
}
// GNU make pipe authentication names inherited descriptors, not paths. Preserve
// only the advertised pair at every SDK command hop (including nativeStage).
function commandStdio(env) {
  const stdio = ['inherit', 'inherit', 'inherit'];
  if (process.platform !== 'linux') return stdio;
  for (const key of ['CARGO_MAKEFLAGS', 'MAKEFLAGS', 'MFLAGS']) {
    const matches = [...(env[key] || '').matchAll(/(?:^|\s)--jobserver-(?:auth|fds)=([^\s]+)/g)];
    if (!matches.length) continue;
    const auth = matches.at(-1)[1];
    if (auth.startsWith('fifo:')) return stdio;
    // Keep this authentication in the environment: a downstream budget build
    // must use its implicit slot only, rather than creating an independent pool.
    if (/^-?\d+,-?\d+$/.test(auth) && auth.split(',').some(fd => Number(fd) < 0)) return stdio;
    if (!/^\d+,\d+$/.test(auth)) throw new Error('JOBSERVER_INVALID_AUTH');
    for (const fd of auth.split(',').map(Number)) {
      if (!Number.isSafeInteger(fd) || fd < 3 || fd > 1023 || !fstatSync(fd).isFIFO())
        throw new Error('JOBSERVER_INVALID_FD');
      while (stdio.length <= fd) stdio.push('ignore');
      stdio[fd] = fd;
    }
    return stdio;
  }
  return stdio;
}
export async function command(argv, {cwd, env = {}, records, resumeOf, signal = cancellation.getStore()} = {}) {
  signal?.throwIfAborted();
  const start = performance.now(), environment = {...process.env, ...env};
  console.log(JSON.stringify({event:'target-command',argv,cwd}));
  let result;
  if (process.platform === 'linux') {
    const supervision = await supervisedCommand(argv,{cwd,env:environment,signal,workRoot:supervisionWork.getStore()||environment.CJCJ_SUPERVISOR_WORK});
    result = {rc:supervision.childRc === null || supervision.childRc < 0 ? null : supervision.childRc,
      signal:supervision.childSignal || null, ...(supervision.cancelled ? {cancelled:true,cancellationSignal:supervision.cancellationSignal} : {}),
      ...(supervision.error ? {error:supervision.error} : {}), supervision};
  } else {
    // Preserve non-Linux signal/rc forwarding without claiming Linux subtree
    // ownership or adding a Python requirement on another platform.
    let child,cancelled,timer;
    const cancel=name=>{if(cancelled)return;cancelled=name;child?.kill(name);if(child)timer=setTimeout(()=>child.kill('SIGKILL'),1500);};
    const abort=()=>cancel(signal?.reason?.cancellationSignal||'SIGTERM');
    const handlers=new Map(['SIGINT','SIGTERM'].map(name=>[name,()=>cancel(name)]));
    for(const [name,fn]of handlers)process.on(name,fn);
    signal?.addEventListener('abort',abort,{once:true});
    try {
      if(signal?.aborted)abort();
      result=await new Promise(resolve=>{
        child=spawn(argv[0],argv.slice(1),{cwd,env:environment,stdio:commandStdio(environment)});
        child.once('error',error=>resolve({rc:null,signal:null,error:error.message}));
        child.once('exit',(rc,childSignal)=>resolve({rc,signal:childSignal}));
        if(cancelled){child.kill(cancelled);timer=setTimeout(()=>child.kill('SIGKILL'),1500);}
      });
      if(cancelled)result={...result,cancelled:true,cancellationSignal:cancelled};
    } finally {
      clearTimeout(timer);signal?.removeEventListener('abort',abort);
      for(const [name,fn]of handlers)process.removeListener(name,fn);
    }
  }
  const row={argv,cwd,...result,...(resumeOf?{resumeOf}:{}),wall:(performance.now()-start)/1000};
  records?.push(row);console.log(JSON.stringify({event:'target-result',...row}));
  const finalRc=result.supervision?.rc ?? (result.cancelled ? (result.cancellationSignal==='SIGINT'?130:143) : result.rc);
  if(finalRc!==0 || result.signal || result.error || result.cancelled)
    throw Object.assign(new Error(`TARGET_FAILED rc=${result.rc} signal=${result.signal} cancelled=${!!result.cancelled} ${argv[0]}`),result,{rc:finalRc||1});
  return row;
}
export async function copyOutputs(root, copies, owners = {}) {
  root = await privateRoot(root);
  await fs.mkdir(root, {recursive: true});
  for (const spec of copies) {
    const excluded = (spec.exclude || []).map(relative);
    async function copy(source, rel, inputRel) {
      relative(rel);
      if (excluded.some(p => inputRel === p || inputRel.startsWith(p+'/'))) return;
      const dest = path.join(root, rel), stat = await fs.lstat(source);
      await privateRoot(path.dirname(dest));
      if (stat.isDirectory()) {
        await fs.mkdir(dest, {recursive: true});
        for (const name of (await fs.readdir(source)).sort())
          await copy(path.join(source, name), rel ? rel+'/'+name : name, inputRel ? inputRel+'/'+name : name);
        return;
      }
      let previous;
      try { previous = await fs.lstat(dest); } catch (e) { if (e.code !== 'ENOENT') throw e; }
      if (previous) throw new Error(`INSTALL_CONFLICT ${rel} ${owners[rel]} ${spec.owner}`);
      await fs.mkdir(path.dirname(dest), {recursive: true});
      if (stat.isSymbolicLink()) {
        const link = await fs.readlink(source), target = path.resolve(path.dirname(dest), link);
        if (path.isAbsolute(link) || !(target === root || target.startsWith(root+path.sep)))
          throw new Error(`INSTALL_LINK_ESCAPE ${rel} ${link}`);
        await fs.symlink(link, dest);
      } else if (stat.isFile()) {
        await fs.copyFile(source, dest, fs.constants.COPYFILE_EXCL);
        await fs.chmod(dest, stat.mode & 0o777);
      } else throw new Error(`INSTALL_FILE_TYPE ${source}`);
      owners[rel] = spec.owner;
    }
    await copy(spec.from, relative(spec.to || ''), '');
  }
  return owners;
}
// Assembled SDKs are complete trees, not overlays over a prior installation.
// Publish only after copying, entry production and metadata are complete; retain
// old and interrupted trees instead of weakening copyOutputs' conflict checks.
export async function assembleDirectory(root, produce, signal = cancellation.getStore()) {
  root = await privateRoot(root);
  signal?.throwIfAborted();
  await fs.mkdir(path.dirname(root), {recursive:true});
  const pending = await fs.mkdtemp(root+'.pending-');
  const value = await produce(pending);
  signal?.throwIfAborted();
  const exists = await fs.lstat(root).then(() => true, error => {if(error.code === 'ENOENT')return false;throw error;});
  const previous = exists ? root+'.previous-'+path.basename(pending) : null;
  if (previous) await fs.rename(root, previous);
  try {
    signal?.throwIfAborted();
    await fs.rename(pending, root);
  } catch (error) {
    // In particular, a failed second rename must not strand the old install.
    if (previous) {
      try { await fs.rename(previous, root); }
      catch (restore) { throw new AggregateError([error,restore], `INSTALL_RESTORE ${root} previous=${previous} pending=${pending}`); }
    }
    throw error;
  }
  console.log('SDK_DIRECTORY_PUBLISHED '+JSON.stringify({root,previous}));
  return value;
}
// Both the bootstrap graph and install-only consume these existing recipes.
// Tests observe the pending tree, including its real launcher, before publish.
export async function installRecipe({root, recipe, build, tools, platform, test, vars = {}, records = [], consume}) {
  return assembleDirectory(root, async pending => {
    const owners = await copyOutputs(pending, recipe.copies || []);
    if (recipe.entries?.length) await installEntries({root:pending,build,groups:recipe.entries,tools,records,platform});
    await installLinks(pending,recipe.links);
    if (recipe.metadata) {
      const metadata={...recipe.metadata};
      if(metadata.compilerFile) {
        metadata.compilerSha256=await fileDigest(path.join(pending,relative(metadata.compilerFile)));
        metadata.compilerEntrySha256=await fileDigest(path.join(pending,'bin/cjcj-stage1'+(platform?.startsWith('windows_')?'.exe':'')));
      }
      await atomicJson(path.join(pending,'STAGE-INPUTS.json'),metadata);
    }
    if (test) await testInstall(pending,test,{...vars,output:pending,install:pending},records);
    if (consume) await consume(pending,records);
    return owners;
  });
}
export async function installLinks(root, links = {}) {
  for (const [rel, target] of Object.entries(links)) {
    relative(rel);
    const destination = path.join(root, rel), resolved = path.resolve(path.dirname(destination), target);
    if (path.isAbsolute(target) || !resolved.startsWith(root+path.sep)) throw new Error(`INSTALL_LINK_ESCAPE ${rel}`);
    await fs.stat(resolved); // No dangling compiler aliases or fabricated modules.
    await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.symlink(target, destination);
  }
}
// Native component producers use this to describe their own source payloads.
// SDK installation and packaging do not inventory or authenticate directories.
export async function inventory(root) {
  const files = {};
  async function walk(dir, prefix = '') {
    for (const name of (await fs.readdir(dir)).sort()) {
      const rel = prefix+name, file = path.join(dir, name), stat = await fs.lstat(file);
      if (stat.isSymbolicLink()) {
        const target = await fs.readlink(file);
        const resolved = path.resolve(path.dirname(file), target);
        if (path.isAbsolute(target) || !(resolved === root || resolved.startsWith(root+path.sep)))
          throw new Error(`INSTALL_LINK_ESCAPE ${rel} ${target}`);
        const followed = await fs.stat(file);
        if (followed.isDirectory()) files[rel] = {type:'symlink', target, kind:'directory'};
        else if (followed.isFile()) files[rel] = {type:'symlink', target, sha256:await fileDigest(file)};
        else throw new Error(`INSTALL_FILE_TYPE ${file}`);
      } else if (stat.isDirectory()) await walk(file, rel+'/');
      else if (stat.isFile()) files[rel] = {type:'file', sha256:await fileDigest(file), mode:stat.mode & 0o777};
      else throw new Error(`INSTALL_FILE_TYPE ${file}`);
    }
  }
  await walk(root); return files;
}
// Archive extraction uses root; git sources execute from their private checkout.
// Resolve this before materialization as well as during preparation.
export async function prepareSources(repos, records) {
  for (const [id, repo] of Object.entries(repos)) {
    if (!/^[0-9a-f]{40}$/.test(repo.commit) || !/^[0-9a-f]{40}$/.test(repo.tree)) throw new Error(`SOURCE_COMMIT ${id}`);
    if (repo.archive) {
      await privateRoot(repo.root);
      if(!(await fs.stat(repo.root).catch(error=>{if(error.code==='ENOENT')return null;throw error;}))) {
        if(await fileDigest(repo.archive.file)!==repo.archive.sha256)throw new Error(`SOURCE_ARCHIVE ${id}`);
        await fs.mkdir(path.dirname(repo.root),{recursive:true});
        const temporary=await fs.mkdtemp(path.join(path.dirname(repo.root),'.'+path.basename(repo.root)+'-'));
        await command(['tar','-xf',repo.archive.file,'-C',temporary],{records});
        await fs.rename(temporary,repo.root);
      }
      // Existing private sources belong to the normal native build. Re-entry
      // neither replaces generated files nor certifies their inventory.
    } else {
      await command(['git', '-C', repo.root, 'rev-parse', '--verify', repo.commit+'^{commit}'], {records});
      // A writable source domain is always private; caller supplies the object
      // repository and a distinct destination instead of resetting a shared tree.
      if (repo.checkout && !(await fs.stat(repo.checkout).catch(()=>null))) {
        await privateRoot(repo.checkout);
        await command(['git', 'clone', '--no-checkout', repo.root, repo.checkout], {records});
        await command(['git', '-C', repo.checkout, 'checkout', '--detach', repo.commit], {records});
      }
      repo.root=effectiveSourceRoot(repo);
      const git = async (...args) => (await capture('git', ['-C', repo.root, ...args])).stdout.trim();
      if (await git('rev-parse', 'HEAD') !== repo.commit) throw new Error(`SOURCE_CHECKOUT ${id}`);
    }
  }
}
const expand = (value, vars) => typeof value === 'string' ? value.replace(/\$\{([^}]+)\}/g, (_, key) => {
  if (!(key in vars)) throw new Error(`CONFIG_VARIABLE ${key}`); return vars[key];
}) : value;
export function targetOrder(stages, through) {
  const rows = new Map(stages.map(stage => [stage.id, stage]));
  if (rows.size !== stages.length) throw new Error('TARGET_DUPLICATE');
  const ordered = [], active = new Set(), done = new Set();
  function visit(id) {
    if (done.has(id)) return;
    const stage = rows.get(id);
    if (!stage || active.has(id)) throw new Error(`TARGET_DEPENDENCY ${id}`);
    active.add(id); (stage.depends || []).forEach(visit); active.delete(id); done.add(id); ordered.push(stage);
  }
  (through ? [through] : stages.map(s => s.id)).forEach(visit); return ordered;
}
export async function testInstall(root, test, vars = {}, records = []) {
  const values = {...vars, install: root};
  for (const check of test.required || []) {
    const file = path.join(root, relative(check));
    if (!(await fs.stat(file)).isFile()) throw new Error(`INSTALL_REQUIRED ${check}`);
  }
  for (const step of test.commands || []) await command(step.argv.map(v => expand(v, values)), {
    cwd: expand(step.cwd || root, values), env: Object.fromEntries(Object.entries(step.env || {}).map(([k,v]) => [k,expand(v,values)])), records,
  });
}
export async function archiveInstall({install, archive, format = 'tar.gz', test, vars, records=[]}) {
  install = path.resolve(install);
  archive = path.resolve(archive);
  if (archive === install || archive.startsWith(install+path.sep)) throw new Error('ARCHIVE_INSIDE_INSTALL');
  await privateRoot(archive);
  if (!['tar.gz','zip'].includes(format)) throw new Error(`ARCHIVE_FORMAT ${format}`);
  await fs.mkdir(path.dirname(archive),{recursive:true});
  const pending = path.join(path.dirname(archive),'.'+path.basename(archive)+'.pending-'+crypto.randomUUID()+'.'+format);
  const firstCommand=records.length, commandsFile=pending+'.commands.json';
  const result={install,archive,pending,status:'WIP',commands:[]};
  try {
  if (format === 'tar.gz') await command(['tar', '-czf', pending, '-C', path.dirname(install), path.basename(install)], {records});
  else if (format === 'zip') await command(process.platform==='win32'
    ? ['tar','-a','-cf',pending,path.basename(install)]
    : ['zip','-qyr',pending,path.basename(install)], {cwd:path.dirname(install),records});
  const extracted = pending+'.unpacked'; await fs.mkdir(extracted);
  if (format === 'tar.gz') await command(['tar', '-xzf', pending, '-C', extracted], {records});
  else await command(process.platform==='win32'?['tar','-xf',pending,'-C',extracted]:['unzip','-q',pending,'-d',extracted],{records});
  // Exercise relocation with the old private installation path unavailable.
  // Keep the original bytes and restore them even when the consumer rejects.
  const parked=install+'.archive-original-'+crypto.randomUUID();
  await fs.rename(install,parked);
  try {
    if(test) await testInstall(path.join(extracted, path.basename(install)), test, {...vars,work:path.join(extracted,'validation')}, records);
  } finally { await fs.rename(parked,install); }
  const sha256 = await fileDigest(pending);
  await fs.writeFile(pending+'.sha256', sha256+'  '+path.basename(archive)+'\n');
  await publishPaths(['', '.sha256', '.unpacked'].map(suffix=>({pending:pending+suffix,destination:archive+suffix})));
  result.status='COMPLETE';return {archive,sha256,commandsFile};
  } catch(error) {result.status='FAILED';result.error=error.message;result.rc=error.rc??null;throw error;}
  finally {result.commands=records.slice(firstCommand);await atomicJson(commandsFile,result);}
}
// An exact, small write set (package files or component directory boundaries).
// Prepare everything first; retain old members and roll back every moved member
// if any rename fails. This never backs up an SDK tree or certifies its contents.
export async function publishPaths(paths) {
  const moved=[],published=[],suffix='.previous-'+crypto.randomUUID();
  try {
    for(const {pending,destination} of paths) {
      await privateRoot(pending);await privateRoot(destination);
      cancellation.getStore()?.throwIfAborted();
      await fs.mkdir(path.dirname(destination),{recursive:true});
      try { await fs.rename(destination,destination+suffix);moved.push(destination); }
      catch(error) { if(error.code!=='ENOENT')throw error; }
      await fs.rename(pending,destination);published.push({pending,destination});
    }
  } catch(error) {
    const errors=[error];
    for(const {pending,destination}of published.reverse())try{await fs.rename(destination,pending);}catch(e){errors.push(e);}
    for(const destination of moved.reverse())try{await fs.rename(destination+suffix,destination);}catch(e){errors.push(e);}
    if(errors.length>1)throw new AggregateError(errors,'INSTALL_PARTS_RESTORE '+suffix);
    throw error;
  }
}
export async function buildFlow(config, options = {}) {
  return supervisionWork.run(path.resolve(config.work), () => buildFlowInWork(config, options));
}
async function buildFlowInWork(config, {through, from, packageOutput = true, resumeInstalled, acceptRecords} = {}) {
  // The entry recipes name the target platform, which is a property of the flow,
  // not of the machine producing it. Carry it in one place so both preparation
  // and final installation read the same value.
  const metadataPlatform = (metadata, flow) => flow.platform || metadata?.platform;
  const work = await privateRoot(config.work), install = await privateRoot(config.install);
  if(config.bootstrapInputs || config.stages.some(s=>s.id==='stage0')) {
    const {validateBootstrapTargets}=await import('./sdk-targets.mjs');
    validateBootstrapTargets(config);
    const {validateSourceInputs}=await import('./sdk-inputs.mjs');
    await validateSourceInputs(config.bootstrapInputs);
  }
  // A single original build result records what this work directory produced.
  // It is not an install authority: native and installed-language checks still run.
  const configuration=crypto.createHash('sha256').update(JSON.stringify(config)).digest('hex');
  const previous=await readJson(path.join(work,'build-result.json')).catch(error=>{
    if(error.code==='ENOENT')return null;throw error;
  });
  if(previous && previous.configuration!==configuration)throw new Error('WORK_INPUT_MISMATCH');
  if(!previous && (from || resumeInstalled))throw new Error('WORK_INPUTS_MISSING');
  if (acceptRecords && !resumeInstalled) throw new Error('STD_RESUME_ARGUMENTS');
  if (resumeInstalled && from && from !== resumeInstalled) throw new Error('STD_RESUME_STAGE from');
  const ordered = targetOrder(config.stages, through);
  const effectiveFrom = from || resumeInstalled;
  const start = effectiveFrom ? ordered.findIndex(stage => stage.id === effectiveFrom) : 0;
  if (start < 0) throw new Error(resumeInstalled ? 'STD_RESUME_STAGE '+resumeInstalled : 'TARGET_FROM '+from);
  const preVars = {work, install, ...config.variables};
  for (const [id, repo] of Object.entries(config.repos || {})) preVars['repo.'+id] = effectiveSourceRoot(repo);
  for (const stage of ordered) preVars['output.'+stage.id] = stage.output
    ? expand(stage.output, preVars) : path.join(work,'targets',stage.id);
  let resumedProduction;
  if (resumeInstalled) {
    const stage = ordered[start];
    if (stage.id !== resumeInstalled || stage.reuse || stage.commands?.length !== 1
        || stage.prepare?.length || stage.copies?.length || stage.entries || stage.links)
      throw new Error('STD_RESUME_STAGE '+resumeInstalled);
    const build = path.join(work,'build',stage.id), output = preVars['output.'+stage.id];
    const local = {...preVars, build, output};
    const step = stage.commands[0], argv = bindNativeSource(step.argv.map(v => expand(v,local)),config.repos);
    if (path.basename(argv[1] || '') !== 'sdk-native-stage.mjs' || flag(argv,'--kind') !== 'std')
      throw new Error('STD_RESUME_STAGE '+resumeInstalled);
    const expected = {argv, cwd:expand(step.cwd || build,local)};
    resumedProduction = await acceptInstalledStd({file:acceptRecords, previous, expected,
      ...Object.fromEntries(['source','output','commit','sdk','runtime','platform','heap'].map(k => [k,flag(argv,'--'+k)])),
      compilerRuntime:flag(argv,'--compiler-runtime'), link:flag(argv,'--output')+'.runtime-input'});
  }
  // Reject missing/mislocated predecessors before fetching sources or writing work.
  for (const stage of ordered.slice(0,start)) {
    const output = preVars['output.'+stage.id];
    const built = previous?.stages.find(row => row.id === stage.id);
    if (!built || built.output !== output) throw new Error('TARGET_PREBUILT_INPUT '+stage.id);
    await privateRoot(output);
    if (!(await fs.stat(output)).isDirectory()) throw new Error('TARGET_PREBUILT_MISSING '+stage.id);
  }
  // Source preparation may fail before the loop can revalidate skipped stages.
  // Keep their original production facts so a repaired source can re-enter.
  // Every skipped stage is still checked again below; this is not acceptance.
  const predecessorIds = new Set(ordered.slice(0,start).map(stage => stage.id));
  const records = [], outputs = {}, result = {configuration,status: 'WIP',
    stages: (previous?.stages || []).filter(stage => predecessorIds.has(stage.id)), commands: records};
  await fs.mkdir(work, {recursive: true});
  if(previous?.status==='COMPLETE')await fs.rename(path.join(work,'build-result.json'),path.join(work,'build-result.json.previous-'+crypto.randomUUID()));
  try {
    let resumeRan = false;
    const needed=new Set();
    for(const stage of ordered.slice(start))for(const match of JSON.stringify(stage).matchAll(/\$\{repo\.([^}]+)\}/g))needed.add(match[1]);
    // Literal native source paths consume the same configured repositories as
    // ${repo.id}. Resolve them before preparation, including custom configs.
    for (const stage of ordered.slice(start)) for (const step of stage.commands || []) {
      const local={...preVars,build:path.join(work,'build',stage.id),output:preVars['output.'+stage.id]};
      const argv=bindNativeSource(step.argv.map(value=>expand(value,local)),config.repos);
      if(path.basename(argv[1]||'')!=='sdk-native-stage.mjs')continue;
      const source=nativeSourceOptions(argv).source;
      for(const [id,repo]of Object.entries(config.repos||{}))
        if(source&&path.resolve(source)===path.resolve(effectiveSourceRoot(repo)))needed.add(id);
    }
    await prepareSources(Object.fromEntries(Object.entries(config.repos||{}).filter(([id])=>needed.has(id))),records);
    const vars = {work, install, ...config.variables};
    for (const [id, repo] of Object.entries(config.repos || {})) vars['repo.'+id] = effectiveSourceRoot(repo);
    for (const [index,stage] of ordered.entries()) {
      const build = path.join(work, 'build', stage.id);
      await fs.mkdir(build, {recursive: true});
      const output = stage.output ? expand(stage.output, vars) : path.join(work, 'targets', stage.id);
      const local = {...vars, build, output};
      if(index<start){
        if (resumeInstalled && stage.id === resumeInstalled) throw new Error('STD_RESUME_STAGE skipped '+stage.id);
        const built=previous?.stages.find(row=>row.id===stage.id);
        if(!built || built.output!==output)throw new Error('TARGET_PREBUILT_INPUT '+stage.id);
        await privateRoot(output);
        if(!(await fs.stat(output)).isDirectory())throw new Error('TARGET_PREBUILT_MISSING '+stage.id);
        // --from skips production, not input validation. The same configured
        // native N/R checks must observe the current installed entities before
        // any dependent consumer, even when the work/configuration is unchanged.
        if (stage.test) await testInstall(output, stage.test, local, records);
        outputs[stage.id]=output;vars['output.'+stage.id]=output;
        result.stages = result.stages.filter(row => row.id !== stage.id);
        result.stages.push({id:stage.id,output,owners:built.owners||{},
          reuse:{source:output,reason:'explicit --from dependency'}});continue;
      }
      vars['output.'+stage.id]=output; // Commands may install directly to their declared target prefix.
      for (const preparation of stage.prepare || []) {
        const root=expand(preparation.to,local);
        await assembleDirectory(root, async destination => {
        await copyOutputs(destination,preparation.copies.map(c=>({...c,from:expand(c.from,local)})));
        if(preparation.entries){
          await installEntries({root:destination,build:path.join(build,'input-entries'),groups:preparation.entries,tools:config.tools,records,
            platform:metadataPlatform(preparation.metadata,config)});}
        await installLinks(destination,preparation.links);
        if(preparation.metadata){const metadata=Object.fromEntries(Object.entries(preparation.metadata).map(([k,v])=>[k,expand(v,local)]));
          if(metadata.compilerFile){metadata.compilerSha256=await fileDigest(path.join(destination,relative(metadata.compilerFile)));
            metadata.compilerEntrySha256=await fileDigest(path.join(destination,'bin/cjcj-stage1'+(metadata.platform?.startsWith('windows_')?'.exe':'')));}
          await atomicJson(path.join(destination,'STAGE-INPUTS.json'),metadata);}
        });
      }
      if (resumeInstalled && stage.id === resumeInstalled && (stage.reuse || !(stage.commands || []).length))
        throw new Error('STD_RESUME_STAGE '+stage.id);
      if (!stage.reuse) for (const step of stage.commands || []) {
        let argv = bindNativeSource(step.argv.map(v => expand(v, local)),config.repos);
        if (resumeInstalled && stage.id === resumeInstalled) {
          resumeRan = true;
          argv = argv.concat(['--resume-installed', '--accept-records', acceptRecords, '--resume-state', path.join(work,'build-result.json'), '--resume-stage', stage.id]);
        }
        await command(argv, {
        resumeOf: resumeInstalled === stage.id ? resumedProduction.terminal : undefined,
        cwd: expand(step.cwd || build, local), env: Object.fromEntries(Object.entries({...config.env, ...step.env}).map(([k,v]) => [k,expand(v,local)])), records,
      });
      }
      const finalTest=stage.id===config.finalStage?config.test:undefined;
      const test={required:[...(stage.test?.required||[]),...(finalTest?.required||[])],
        commands:[...(stage.test?.commands||[]),...(finalTest?.commands||[])]};
      const recipe={...stage,copies:(stage.copies||[]).map(c=>({...c,from:expand(c.from,local),owner:c.owner||stage.id})),
        ...(stage.metadata?{metadata:JSON.parse(JSON.stringify(stage.metadata),(_key,value)=>expand(value,local))}:{})};
      let owners={};
      if(stage.copies?.length || stage.entries || stage.links) {
        owners=await installRecipe({root:output,recipe,build:path.join(build,'entries'),tools:config.tools,
          platform:metadataPlatform(stage.metadata,config),test,vars:local,records});
      } else {
        // Native producer outputs stay native; they are not advertised as a
        // transactionally installed SDK. Their consumer still blocks the flow.
        await testInstall(output,test,local,records);
      }
      outputs[stage.id] = output; vars['output.'+stage.id] = output;
      result.stages.push({id: stage.id, output, reuse: stage.reuse || null, owners});
      await atomicJson(path.join(work,'build-result.json'),result);
    }
    if (resumeInstalled && !resumeRan) throw new Error('STD_RESUME_STAGE '+resumeInstalled);
    if (!through || through === config.finalStage) {
      const final = outputs[config.finalStage];
      if (final !== install) throw new Error('FINAL_INSTALL_TARGET');
      if (packageOutput && config.archive) result.package = await archiveInstall({install, archive: config.archive,
        format: config.archiveFormat, test: config.test, vars, records});
    }
    // COMPLETE describes this requested target traversal, never full SDK
    // qualification (tools/stdx/platform gates belong to their native flow).
    result.completedThrough = through || config.finalStage;
    result.scope = through && through !== config.finalStage ? 'PARTIAL_TARGET_FLOW' : 'FINAL_TARGET_FLOW';
    result.fullSdkQualification = 'NOT_GRANTED';
    cancellation.getStore()?.throwIfAborted();
    result.status = 'COMPLETE'; return result;
  } catch (error) {
    result.status = 'FAILED'; result.error = error.message; result.rc = error.rc ?? 1; result.signal = error.signal ?? null;
    throw error;
  } finally { await atomicJson(path.join(work, 'build-result.json'), result); }
}
export async function main(args = process.argv.slice(2)) {
  const {values} = parseArgs({args, options: {config: {type: 'string'}, 'install-inputs':{type:'string'},'build-only':{type:'boolean'},'dry-run':{type:'boolean'}, through: {type: 'string'}, from: {type:'string'}, 'no-package': {type: 'boolean'}, 'resume-installed': {type: 'string'}, 'accept-records': {type: 'string'}}});
  if(values['install-inputs']) {
    if(values.config||values.from||values.through||values['resume-installed'])throw Error('INSTALL_ARGUMENT_CONFLICT');
    return withProcessCancellation(()=>installProducts(readJson(values['install-inputs']),{buildOnly:values['build-only'],dryRun:values['dry-run'],packageOutput:!values['no-package']}));
  }
  if(values['build-only']||values['dry-run'])throw Error('INSTALL_INPUTS_REQUIRED');
  if (!values.config) throw new Error('usage: sdk-flow.mjs --config TARGETS.json [--through STAGE] [--from STAGE] [--resume-installed STAGE --accept-records FILE] [--no-package]');
  const config = await readJson(values.config);
  return withProcessCancellation(() => buildFlow(config, {through: values.through, from:values.from, packageOutput: !values['no-package'], resumeInstalled: values['resume-installed'], acceptRecords: values['accept-records']}));
}
export async function installProducts(descriptor,{buildOnly=false,dryRun=false,packageOutput=true,consume}={}) {
  const {prepareInstallInputs}=await import('./sdk-inputs.mjs');
  const {installationRecipe}=await import('./sdk-targets.mjs');
  const input=await prepareInstallInputs(await descriptor),{work,install,platform,selection}=input;
  const recipe=installationRecipe(selection,{layout:input.layout});
  const test=input.test??{commands:[{argv:[process.execPath,fileURLToPath(new URL('./compiler_identity.mjs',import.meta.url)),'${install}']},
    {argv:[process.execPath,fileURLToPath(new URL('./sdk-hello.mjs',import.meta.url)),
    '--sdk','${install}','--work','${work}/hello','--platform',platform,'--compiler-only',
    '--source',fileURLToPath(new URL('../smoke/01_hello.cj',import.meta.url)),'--expected','hello from cjcj']}]};
  if(buildOnly||dryRun) {
    const result={status:'NOT_INSTALLED',selection,recipe,reason:dryRun?'DRY_RUN':'BUILD_ONLY'};
    console.log(JSON.stringify(result));return result;
  }
  const records=[],result={status:'WIP',selection,commands:records,fullSdkQualification:'NOT_GRANTED',
    consumption:input.cross?{status:'NOT_RUN',reason:'HOST_CROSS_EXEC'}:{status:'WIP'}};
  await fs.mkdir(work,{recursive:true});
  const oldResult=path.join(work,'install-result.json');
  if((await readJson(oldResult).catch(error=>{if(error.code==='ENOENT')return null;throw error;}))?.status==='COMPLETE')
    await fs.rename(oldResult,oldResult+'.previous-'+crypto.randomUUID());
  return supervisionWork.run(work,async()=>{
    try {
      recipe.metadata={platform,phase:selection.compilerExecution.stage,compilerFile:'libexec/compiler/cjcj-stage1'+sdkExe(platform),
        compilerCommit:selection.targetComponents.compiler.commit,runtimeCommit:selection.targetComponents.runtime.commit,selection,
        sources:Object.fromEntries(Object.entries(selection.targetComponents).map(([name,row])=>[name,{repository:row.repository,commit:row.commit,producer:row.producer}])),
        configuration:{layout:input.layout??'components',platform},production:input.production};
      await installRecipe({root:install,recipe,platform,build:path.join(work,'entries'),tools:input.tools,records,
        vars:{work},test:input.cross?undefined:test,consume});
      if(!input.cross)result.consumption={status:'EXECUTED'};
      if(packageOutput&&input.archive)result.package=await archiveInstall({install,archive:input.archive,format:input.archiveFormat,
        test:input.cross?undefined:test,vars:{work},records});
      result.status='COMPLETE';return result;
    } catch(error) { result.status='FAILED';result.error=error.message;result.rc=error.rc??1;throw error; }
    finally {await atomicJson(path.join(work,'install-result.json'),result);}
  });
}
function sdkExe(platform) { return platform.startsWith('windows_')?'.exe':''; }
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await main(); } catch (error) { console.error(error.stack); process.exitCode = error.rc || 1; }
}
