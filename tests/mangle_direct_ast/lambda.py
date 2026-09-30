#!/usr/bin/env python3
"""Observe mangled lambda identifiers in product RAW CHIR, before elimination.

Translator.cj:2156 consumes the AST result; CHIRSerializerImpl.cj:1178 writes
it to Lambda.identifier. LLVM optimizations may erase these local names.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'chir_builder'))
from decoded_compare import Package
from run import sha


def run(a,case):
    out=a.output/case.stem;out.mkdir(parents=True)
    product=out/'output.chir'
    cmd=[str(a.compiler),str(case),'--emit-chir=raw','--output-type=staticlib','-o',str(product)]
    env=dict(os.environ,CANGJIE_HOME=str(a.sdk),cjHeapSize='32GB')
    env['PATH']=':'.join(str(a.sdk/p) for p in ('bin','tools/bin','third_party/llvm/bin'))+':/usr/bin:/bin'
    env['LD_LIBRARY_PATH']=':'.join(str(a.sdk/p) for p in ('runtime/lib/linux_x86_64_cjnative','lib/linux_x86_64_cjnative','tools/lib','third_party/llvm/lib'))
    env['CANGJIE_PATH']=':'.join(str(a.sdk/p) for p in ('modules/linux_x86_64_cjnative','third_party/flatbuffers/modules'))
    ident=dict(compiler=sha(a.compiler),source=sha(case),libraries={str(p.relative_to(a.sdk)):sha(p) for p in (a.sdk/'runtime/lib/linux_x86_64_cjnative').glob('*.so')})
    before=subprocess.check_output(['uptime'],text=True);start=time.monotonic()
    with (out/'compile.log').open('w') as log:
        rc=subprocess.run(['timeout','180']+cmd,env=env,cwd=out,stdout=log,stderr=subprocess.STDOUT).returncode
    r=dict(tag=case.stem,rc=rc,wall=time.monotonic()-start,command=cmd,identity=ident,affinity=sorted(os.sched_getaffinity(0)),uptime_before=before,uptime_after=subprocess.check_output(['uptime'],text=True),assertions={})
    if rc==0 and product.exists():
        data=product.read_bytes();p=Package(data)
        # CHIRSerializerImpl.cj:1535 calls Finish without a file identifier.
        tags=p.pointer(p.root,18)
        r['lambda_names']=sorted(p.string(t,10) for i,t in enumerate(p.vector(p.root,20)) if data[tags+4+i]==16)
        tags=p.pointer(p.root,14)
        r['function_names']=sorted(p.string(p.pointer(p.pointer(t,4),4),8) for i,t in enumerate(p.vector(p.root,16)) if data[tags+4+i]==11)
        r['product_sha256']=sha(product)
        r['assertions']['functions_observed']=bool(r['function_names'])
        if case.stem in ('ordinary','control','shapes'):
            r['assertions']['lambda_observed']=bool(r['lambda_names'])
        if a.reference:
            ref=json.loads((a.reference/case.stem/'result.json').read_text())
            r['assertions']['lambda_names_equal']=r['lambda_names']==ref['lambda_names']
            r['assertions']['function_names_equal']=r['function_names']==ref['function_names']
        for key,value in r['assertions'].items():print(f'ASSERT {case.stem} {key}={value}',flush=True)
    r['passed']=rc==0 and bool(r['assertions']) and all(r['assertions'].values())
    (out/'result.json').write_text(json.dumps(r,indent=2)+'\n')
    if r['passed']:
        for path in out.iterdir():
            if path.suffix in ('.chir','.bc','.cjo','.ll','.o','.a'):path.unlink()
    return r


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('compiler','sdk','inputs','output'):p.add_argument('--'+key,type=Path,required=True)
    p.add_argument('--reference',type=Path);p.add_argument('--parallelism',type=int,choices=range(1,5),default=1)
    a=p.parse_args();resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.parallelism) as pool:results=list(pool.map(lambda case:run(a,case),sorted(a.inputs.glob('*.cj'))))
    (a.output/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
    return int(not all(r['passed'] for r in results))


if __name__=='__main__':raise SystemExit(main())
