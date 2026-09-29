import pathlib, shutil, subprocess, concurrent.futures, time, hashlib, json, difflib
root=pathlib.Path('/root/sym_cjcj_710_implement_r5899967301')
src=root/'green'
src.mkdir(exist_ok=True)
subprocess.run(['tar','xf',str(root/'candidate.tar'),'-C',str(src)],check=True)
rel='ci/smoke/run_smoke.mjs'
original=(src/rel).read_text()
changes={
 'green':original,
 'restored':original,
 'cut-producer':original.replace("['--verbose',", "['--verbose', '-L', process.env.CJCJ_PATCHED_RUNTIME_LIB_DIR,"),
 'cut-loader':original.replace('const ran = await runCommand(exe, []);', "process.env.LD_LIBRARY_PATH = process.env.CJCJ_PATCHED_RUNTIME_LIB_DIR;\n  const ran = await runCommand(exe, []);"),
 'cut-consumer':original.replace('if (mixed) {', 'if (false && mixed) {'),
}
for arm,content in changes.items():
 d=root/arm
 if arm!='green': shutil.copytree(src,d,dirs_exist_ok=True)
 (d/rel).write_text(content)
 if arm.startswith('cut-'):
  (root/'keep'/f'{arm}.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True),content.splitlines(True),fromfile='a/'+rel,tofile='b/'+rel)))
def run(arm):
 d=root/arm; start=time.time()
 hashes={p:hashlib.sha256((d/p).read_bytes()).hexdigest() for p in [rel,'ci/smoke/smoke-runtime-isolation.test.mjs']}
 with (root/'keep'/f'{arm}.log').open('w') as log:
  p=subprocess.run(['node','--test','ci/smoke/smoke-runtime-isolation.test.mjs'],cwd=d,stdout=log,stderr=subprocess.STDOUT)
 result=dict(arm=arm,rc=p.returncode,wall=round(time.time()-start,2),hashes=hashes)
 (root/'keep'/f'{arm}.json').write_text(json.dumps(result,indent=2))
 return result
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
 for result in pool.map(run, changes): print(json.dumps(result),flush=True)
with (root/'keep'/'isolation.log').open('w') as log:
 start=time.time();p=subprocess.run(['node','--test','ci/official-runtime-isolation.test.mjs','build/test/package-provenance.test.mjs'],cwd=src,stdout=log,stderr=subprocess.STDOUT)
 print('isolation rc='+str(p.returncode)+' wall='+str(round(time.time()-start,2)),flush=True)
