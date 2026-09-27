#!/usr/bin/env python3
"""Observe SDKROOT at the real isolated command; no compiler qualification claim."""
import concurrent.futures
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
assert os.uname().sysname == 'Darwin'
sdkroot = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
source = out / 'observe.c'
source.write_text('#include <stdio.h>\n#include <stdlib.h>\nint main(){const char*s=getenv("SDKROOT");printf("OBS_SDKROOT=%s\\n",s?s:"MISSING");printf("OBS_LEAK=%s\\n",getenv("LEAK_ME")?"LEAK":"CLEAN");return 0;}\n')
observer = out / 'observe'
subprocess.run(['cc', str(source), '-o', str(observer)], check=True)
producer = 'ci/bootstrap/host_tools.sh'
consumer = 'ci/bootstrap/bootstrap.sh'
original = {f:(root/f).read_text() for f in (producer,consumer)}
cuts = {'producer-cut':(producer, "printf 'SDKROOT=%q ' \"$sdk_root\"", "printf 'SDKROOT=%q ' /"),
        'consumer-cut':(consumer, '${native_env}${HOST_LOADER_VAR}', '${HOST_LOADER_VAR}')}
for arm in ('candidate','producer-cut','consumer-cut','restored'):
    here=out/arm
    shutil.copytree(root/'ci',here/'ci')
    for file,text in original.items():
        if arm in cuts and cuts[arm][0]==file:
            _,before,after=cuts[arm]
            # Cut only cjpm_build, keeping the independent std consumer intact.
            if file==consumer:
                pos=text.index('cjpm_build() {')
                text=text[:pos]+text[pos:].replace(before,after,1)
            else:
                assert text.count(before)==1
                text=text.replace(before,after)
            (here/'cut.diff').write_text(''.join(difflib.unified_diff(original[file].splitlines(True),text.splitlines(True),fromfile='a/'+file,tofile='b/'+file)))
        (here/file).write_text(text)
    (here/'sdk/tools/bin').mkdir(parents=True)
    shutil.copy2(observer,here/'sdk/tools/bin/cjpm')
    (here/'rt').mkdir()
    (here/'rt/libcangjie-runtime.dylib').touch()
    (here/'input/packages/cjc').mkdir(parents=True)
    shutil.copyfile(root/'packages/cjc/cjpm.toml',here/'input/packages/cjc/cjpm.toml')

def run(arm):
    here=out/arm
    env={**os.environ,'LEAK_ME':'must-not-cross'}
    env.pop('SDKROOT',None)
    script='source "$1"; STAGE=env-control; host_tuple_init; SRC="$2"; WORK="$2/work"; cjpm_build "$2/sdk" "$2/rt" "$2/input" "" 4GB'
    result=subprocess.run(['bash','-c',script,'bash',str(here/consumer),str(here)],env=env,capture_output=True,text=True)
    (here/'command.log').write_text(result.stdout+result.stderr)
    checks={'sdk-root':result.returncode==0 and f'OBS_SDKROOT={sdkroot}\n' in result.stdout,
            'isolation':result.returncode==0 and 'OBS_LEAK=CLEAN\n' in result.stdout}
    record={'rc':int(not all(checks.values())),'product_rc':result.returncode,'checks':checks,
            'product':{f:hashlib.sha256((here/f).read_bytes()).hexdigest() for f in original},
            'observer_sha256':hashlib.sha256(observer.read_bytes()).hexdigest()}
    (here/'result.json').write_text(json.dumps(record,indent=2))
    print('ASSERT native-build-env',arm,json.dumps(record),flush=True)
    return arm,record
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results=dict(pool.map(run,('candidate','producer-cut','consumer-cut','restored')))
(out/'results.json').write_text(json.dumps(results,indent=2))
for arm,r in results.items():
    assert r['product_rc']==0
    assert [k for k,v in r['checks'].items() if not v]==(['sdk-root'] if arm in cuts else [])
    assert r['rc']==(1 if arm in cuts else 0)
assert results['candidate']==results['restored']
for arm in results:
    shutil.rmtree(out/arm/'ci')
