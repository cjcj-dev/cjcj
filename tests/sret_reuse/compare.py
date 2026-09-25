#!/usr/bin/env python3
"""Compile fixture/self-host package twice on base and once on candidate; retain full artifacts."""
import argparse
import concurrent.futures
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def compile_one(compiler, source, out, level, imports, jobs):
    out.mkdir(parents=True, exist_ok=True)
    command = [str(compiler)] + (['-p'] if source.is_dir() else []) + [str(source),
               '--output-type=staticlib', '-' + level, '--save-temps', '--dump-ir',
               '--jobs', str(jobs), '-o', str(out/'output.bc')]
    for directory in imports:
        command += ['--import-path', str(directory)]
    start = time.monotonic()
    before = subprocess.check_output(['uptime'], text=True).strip()
    with (out/'compile.log').open('w') as log:
        process = subprocess.run(command, cwd=out, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
    return {'command': command, 'rc': process.returncode, 'wall': time.monotonic()-start,
            'uptime_before': before, 'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
            'outputs': {str(p.relative_to(out)): sha(p) for p in out.rglob('*')
                        if p.is_file() and p.suffix in ('.bc','.ll','.cjo','.chir')}}


def instructions(root):
    # This ruler compares instruction forms only. Full metadata-bearing IR and
    # bitcode are preserved, hashed, and not claimed byte-identical by this ruler.
    functions = {}
    for p in root.rglob('*.ll'):
        text = p.read_text()
        attributes = dict(re.findall(r'^attributes #(\d+) = (.*)$', text, re.M))
        for m in re.finditer(r'^define [^\n]+\{\n.*?^\}', text, re.M|re.S):
            name = re.search(r'@([^ (]+)\(',m.group()).group(1)
            body = re.sub(r',? ![\w.]+ !\d+', '', m.group())
            body = re.sub(r'#(\d+)', lambda x: attributes[x.group(1)], body)
            body = re.sub(r'\s*;[^\n]*', '', body)
            functions[p.name + ':' + name] = '\n'.join(line.rstrip() for line in body.splitlines())
    return functions


def difference(left, right, out):
    a,b=instructions(left),instructions(right)
    changed=[name for name in sorted(a.keys()|b.keys()) if a.get(name)!=b.get(name)]
    out.write_text(''.join(''.join(difflib.unified_diff(a.get(k,'').splitlines(True),b.get(k,'').splitlines(True),
                              fromfile='base/'+k,tofile='other/'+k))+'\n' for k in changed))
    chir_a={p.name:p.read_bytes() for p in left.rglob('*.chir')}
    chir_b={p.name:p.read_bytes() for p in right.rglob('*.chir')}
    chir_changed=[k for k in sorted(chir_a.keys()|chir_b.keys()) if chir_a.get(k)!=chir_b.get(k)]
    return {'function_count':[len(a),len(b)],'changed_functions':changed,'chir_changed':chir_changed,
            'chir_count':[len(chir_a),len(chir_b)],'instruction_diff':str(out)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',type=Path,required=True)
    parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--import-dir',type=Path,action='append',default=[])
    parser.add_argument('--jobs',type=int,default=os.cpu_count())
    a=parser.parse_args();a.out.mkdir(parents=True,exist_ok=True)
    record={'compiler_sha256':{'base':sha(a.baseline),'candidate':sha(a.candidate)},
            'source':str(a.source),'affinity':sorted(os.sched_getaffinity(0)), 'jobs':a.jobs,'parallel_arms':4}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        pending={(level,arm):pool.submit(compile_one,compiler,a.source,a.out/level/arm,level,a.import_dir,a.jobs)
                 for level in ('O0','O1') for arm,compiler in [('base',a.baseline),('noise',a.baseline),('candidate',a.candidate)]}
        record['runs']={level:{arm:pending[level,arm].result() for arm in ('base','noise','candidate')} for level in ('O0','O1')}
    record['comparisons']={}
    for level,runs in record['runs'].items():
        if all(r['rc']==0 for r in runs.values()):
            record['comparisons'][level]={arm:difference(a.out/level/'base',a.out/level/arm,a.out/f'{level}-{arm}.diff')
                                            for arm in ('noise','candidate')}
    (a.out/'result.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({'rc':{level:{arm:r['rc'] for arm,r in runs.items()} for level,runs in record['runs'].items()},
                      'comparisons':record['comparisons']},indent=2))
    compiled = all(r['rc']==0 for runs in record['runs'].values() for r in runs.values())
    observed = len(record['comparisons']) == 2 and all(
        all(count > 0 for count in item['function_count'] + item['chir_count'])
        for comparisons in record['comparisons'].values() for item in comparisons.values())
    return 0 if compiled and observed else 1


if __name__=='__main__':
    raise SystemExit(main())
