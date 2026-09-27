import pathlib, subprocess, concurrent.futures, time, shutil, hashlib, json
import os
root=pathlib.Path(os.environ['RUNNER_TEMP'])/'provision-arms'
root.mkdir()
t0=time.monotonic()
base=root/'candidate'
subprocess.run(['git','clone','--local','--quiet','.',str(base)],check=True)
for arm in ['cut-clang','cut-lld','cut-consumer','restored']:
 shutil.copytree(base,root/arm)
for arm,old,new in [('cut-clang','zip unzip clang lld','zip unzip lld'),('cut-lld','zip unzip clang lld','zip unzip clang'),('cut-consumer','node ci/test-manifest.mjs list','node ci/test-manifest.mjs omitted')]:
 p=root/arm/'.github/workflows/ci.yml'; p.write_text(p.read_text().replace(old,new))
 diff=subprocess.run(['diff','-u','--label','a/.github/workflows/ci.yml','--label','b/.github/workflows/ci.yml',str(base/'.github/workflows/ci.yml'),str(p)],capture_output=True,text=True)
 (root/(arm+'.diff')).write_text(diff.stdout)
def run(arm):
 cwd=root/arm

 hashes={p:hashlib.sha256((cwd/p).read_bytes()).hexdigest() for p in ['.github/workflows/ci.yml','ci/test-manifest.test.mjs','ci/test-manifest.mjs']}
 start=time.monotonic()
 with (root/(arm+'.log')).open('w') as out:
  r=subprocess.run(['node','--test','--test-name-pattern=ci.yml provides the publisher archive tools|ci.yml runs the manifest rather', 'ci/test-manifest.test.mjs'],cwd=cwd,stdout=out,stderr=subprocess.STDOUT)
 return dict(arm=arm,rc=r.returncode,wall=time.monotonic()-start,sha256=hashes)
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool: results=list(pool.map(run,['candidate','cut-clang','cut-lld','cut-consumer','restored']))
(root/'arms.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2)); print('wall=',time.monotonic()-t0)
for arm in ['candidate','cut-clang','cut-lld','cut-consumer','restored']:
 print('ARM_LOG',arm); print((root/(arm+'.log')).read_text())
assert [x['rc'] for x in results] == [0,1,1,1,0], results
