#!/usr/bin/env python3
"""Fixed #666 single-package experiment; sequential arms avoid mutual load.

No retries or tolerances. The allocated value is a GC summary sample, not live
bytes or an observed physical peak. Keep every failed/timeout artifact.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import time

EVENT = re.compile(r'(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+) (\d+) I GC for ([^:]+): (sync|async): collected objects: (\d+)->.*utilization \((\d+)->[^/]+/(\d+)->.*total GC time: (\d+)->')


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()


def events(path):
    rows=[]
    for n,line in enumerate(path.read_text(errors='replace').splitlines(),1):
        m=EVENT.search(line)
        if m:
            stamp,tid,reason,mode,collected,allocated,used,ns=m.groups()
            rows.append(dict(line=n,timestamp=stamp,reason=reason,mode=mode,allocated=int(allocated)))
    raw=subprocess.run(['/usr/bin/grep','-c','-F','GC for oom: sync:',str(path)],text=True,capture_output=True)
    count=sum(e['reason']=='oom' and e['mode']=='sync' for e in rows)
    if raw.returncode not in (0,1) or count!=int(raw.stdout):
        raise ValueError('GC log parser does not cover printed OOM events')
    return rows,count


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True)
    p.add_argument('--baseline',type=Path,required=True)
    p.add_argument('--candidate',type=Path,required=True)
    a=p.parse_args();r=a.root;k=r/'keep/gc';sdk=r/'gc-sdk'
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    samples=[('noise-1',a.baseline),('noise-2',a.baseline)]+[(f'base-{i}',a.baseline) for i in range(1,4)]+[(f'cand-{i}',a.candidate) for i in range(1,4)]
    plan=dict(samples=[dict(tag=t,compiler=str(c),sha256=sha(c)) for t,c in samples],heap='5376MB',jobs='default',timeout=900,
              comparison='candidate maximum <= baseline maximum independently for OOM completed events and allocated samples',
              serial_reason='concurrent arms alter shared CPU and memory contention')
    (k/'preregistered.json').write_text(json.dumps(plan,indent=2)+'\n')
    positive,positive_count=events(k/'parser-positive.log')
    if not positive or positive_count==0: raise ValueError('missing positive OOM log control')
    (k/'parser-positive.json').write_text(json.dumps(dict(events=positive,oom=positive_count),indent=2)+'\n')
    inputs={}
    for line in (k/'original-inputs.sha256').read_text().splitlines():
        expected,name=line.split(None,1)
        path=r/(name.replace('sdk/','gc-sdk/',1) if name.startswith('sdk/') else name)
        actual=sha(path)
        inputs[name]=dict(expected=expected,actual=actual)
        if actual!=expected: raise ValueError('input mismatch: '+name)
    (k/'inputs-check.json').write_text(json.dumps(inputs,indent=2)+'\n')
    env=dict(os.environ,CANGJIE_HOME=str(sdk),cjHeapSize='5376MB',MRT_LOG_LEVEL='i')
    env['PATH']=f'{sdk}/bin:{sdk}/tools/bin:{sdk}/third_party/llvm/bin:/usr/bin:/bin'
    env['LD_LIBRARY_PATH']=f'{sdk}/runtime/lib/linux_x86_64_cjnative:{sdk}/tools/lib:{sdk}/third_party/llvm/lib'
    env['CANGJIE_PATH']=f'{r}/modules/linux_x86_64_cjnative:{sdk}/third_party/flatbuffers/modules'
    results=[]
    for tag,compiler in samples:
        shutil.copy2(compiler,sdk/'bin/cjcj-stage1')
        out=r/('gc-'+tag);out.mkdir()
        env['TMPDIR']=str(out)
        cmd=[str(sdk/'bin/cjc'),'-g','--apc=1','--output-type=staticlib','-p',str(r/'ast'),'--lto=full','--profile-compile-time','--output',str(out/'libstd.ast.bc'),'-O2']
        objects=[sdk/'bin/cjcj-stage1',sdk/'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',sdk/'runtime/lib/linux_x86_64_cjnative/libboundscheck.so',sdk/'third_party/llvm/lib/libLLVM-15.so']
        ident=dict(command=cmd,hashes={str(x):sha(x) for x in objects},affinity=sorted(os.sched_getaffinity(0)),uptime_before=subprocess.check_output(['uptime'],text=True),start_epoch=time.time(),environment=env)
        # Only retain recipe variables, not unrelated environment values.
        ident['environment']={key:env[key] for key in ('CANGJIE_HOME','PATH','LD_LIBRARY_PATH','CANGJIE_PATH','cjHeapSize','MRT_LOG_LEVEL','TMPDIR')}
        (k/(tag+'-identity.json')).write_text(json.dumps(ident,indent=2)+'\n')
        start=time.monotonic()
        with (k/(tag+'.log')).open('w') as log:
            rc=subprocess.run(['/usr/bin/time','-v','-o',str(k/(tag+'-time.txt')),'timeout','900']+cmd,env=env,cwd=out,stdout=log,stderr=subprocess.STDOUT).returncode
        ev,count=events(k/(tag+'.log'))
        result=dict(tag=tag,rc=rc,wall=time.monotonic()-start,uptime_after=subprocess.check_output(['uptime'],text=True),end_epoch=time.time(),events=ev,oom=count,allocated_max=max((e['allocated'] for e in ev),default=None),bc_sha256=sha(out/'libstd.ast.bc') if (out/'libstd.ast.bc').is_file() else None)
        result['qualified']=rc==0 and result['bc_sha256'] is not None and bool(ev)
        for prof in out.glob('*.prof'): shutil.copy2(prof,k/(tag+'-'+prof.name))
        (k/(tag+'-result.json')).write_text(json.dumps(result,indent=2)+'\n');results.append(result)
        print(json.dumps({key:result[key] for key in ('tag','rc','wall','qualified','oom','allocated_max')}),flush=True)
        if result['qualified']: shutil.rmtree(out)
    base=results[2:5];cand=results[5:]
    valid=all(x['qualified'] for x in results)
    comparison={key:valid and max(x[key] for x in cand)<=max(x[key] for x in base) for key in ('oom','allocated_max')}
    summary=dict(results=results,comparison=comparison,noise={key:[x[key] for x in results[:2]] for key in ('oom','allocated_max')})
    (k/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    return int(not all(comparison.values()))


if __name__=='__main__': raise SystemExit(main())
