#!/usr/bin/env python3
"""Apply #666's conservative sequential-stage bounds to retained GC results.

Completion times are observations, not allocation stacks or direct phase clocks.
Unknown profile keys, negative slack or missing output invalidate this ruler.
"""
import argparse
from datetime import datetime, timezone, timedelta
import json
from pathlib import Path

ORDER = ['Parser','ConditionalCompilation','ImportPackages','MacroExpand','AST Diff',
         'Semantic','Desugar after Sema','Generic Instantiation','Overflow Strategy',
         'Perform Mangling','Save cjo','CHIR','CodeGen','Save results','Execute opt']


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('keep',type=Path)
    k=p.parse_args().keep;rows=[]
    for result in json.loads((k/'summary.json').read_text())['results']:
        tag=result['tag'];identity=json.loads((k/(tag+'-identity.json')).read_text())
        profiles={path.name:json.loads(path.read_text()) for path in k.glob(tag+'-*.prof')}
        main=next((v.get('Main Stage') for name,v in profiles.items() if name.endswith('time.prof')),None)
        row=dict(tag=tag,basis='derived conservative bounds, not direct phase timestamps',valid=False)
        if not main or not result['qualified']:
            rows.append(row);continue
        unknown=sorted(set(main)-set(ORDER));slack=result['wall']-sum(main.values())/1000
        row.update(unknown=unknown,slack=slack,margin=1.0,stages=[],events=[])
        if unknown or slack<0:
            rows.append(row);continue
        row['valid']=True;prefix=0
        for stage in ORDER:
            if stage not in main:continue
            duration=main[stage]/1000
            row['stages'].append(dict(stage=stage,start=[prefix,prefix+slack],end=[prefix+duration,prefix+duration+slack],interior=[prefix+slack+1,prefix+duration-1]))
            prefix+=duration
        peak=max(result['events'],key=lambda e:e['allocated'])
        events=[dict(peak,kind='allocated_max')]+[dict(e,kind='oom_sync') for e in result['events'] if e['reason']=='oom' and e['mode']=='sync']
        for e in events:
            epoch=datetime.strptime(e['timestamp'],'%Y-%m-%d %H:%M:%S.%f').replace(tzinfo=timezone(timedelta(hours=8))).timestamp()
            offset=epoch-identity['start_epoch'];lower=offset-e['duration_ns']/1e9
            e.update(offset=offset,completion_phase=[s['stage'] for s in row['stages'] if s['interior'][0]<offset<s['interior'][1]],whole_reported_interval_phase=[s['stage'] for s in row['stages'] if s['interior'][0]<lower and offset<s['interior'][1]])
            row['events'].append(e)
        rows.append(row)
    (k/'phase-bounds.json').write_text(json.dumps(rows,indent=2)+'\n')
    for row in rows:
        print(row['tag'],row['valid'],[(e['kind'],e['completion_phase']) for e in row.get('events',[])])
    return int(not all(r['valid'] for r in rows))


if __name__=='__main__':raise SystemExit(main())
