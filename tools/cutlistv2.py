#!/usr/bin/env python3
"""Build CUTLIST_0712.md from scan-v2 flow rows and portdiff missing rows."""
import csv
import argparse
from pathlib import Path

ROOT = Path('/root/cj_build/reports')
EXCLUDE = {'infermemfull', 'aliastype', 'fbmangle', 'capord'}

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--flow', type=Path, default=ROOT/'FLOWDIFF_0712.tsv')
    ap.add_argument('--port-missing', type=Path, default=ROOT/'PORTDIFF_MISSING_0712.tsv')
    ap.add_argument('-o', '--output', type=Path, default=ROOT/'CUTLIST_0712.md')
    a = ap.parse_args()
    flow = list(csv.DictReader(a.flow.open(), delimiter='\t'))
    miss = list(csv.DictReader(a.port_missing.open(), delimiter='\t'))
    # Bare-name aggregation makes ubiquitous framework verbs (Visit/Run/Clone,
    # etc.) non-actionable.  Keep only one-to-few definition candidates; this
    # is a cut list, not a claim that the aggregate itself is a C++ entity.
    noise = {'Visit', 'Run', 'Walk', 'Clone', 'Check', 'Verify', 'Serialize', 'Deserialize', 'Dispatch', 'ToString'}
    rows = [r for r in flow if r['symbol'] not in noise and int(r['score']) <= 500
            and not any(x in (r['cpp_anchor']+' '+r['cj_anchor']).lower() for x in EXCLUDE)]
    rows.sort(key=lambda r: (-int(r['score']), r['symbol']))
    out = a.output
    with out.open('w') as f:
        f.write('# CUTLIST 0712 (scan-v2 new baseline)\n\n')
        f.write('Numbers are scan-v2 scores and are not comparable to 0711. In-flight roots infermemfull/aliastype/fbmangle/capord are excluded.\n\n')
        f.write('| rank | root | C++ anchor | selfhost anchor | estimated impact | evidence |\n|---:|---|---|---|---:|---|\n')
        for i,r in enumerate(rows[:30],1):
            impact = int(r['score']) + int(r['cpp_branches']) + len(r['cpp_calls_absent_from_cj'].split(';'))
            f.write(f"| {i} | `{r['symbol']}` | `{r['cpp_anchor']}` | `{r['cj_anchor']}` | {impact} | flow score={r['score']}; missing calls={r['cpp_calls_absent_from_cj'] or '-'} |\n")
        f.write(f'\nPortdiff context: MISSING={len(miss)}; use `PORTDIFF_MISSING_0712.tsv` for the full C++ symbol anchors. CALLDIFF_0712 was retained as a supporting input; v2 does not rewrite its historical score.\n')
    print(f'CUTLIST_V2 TOP={min(30,len(rows))} OUTPUT={out}')
if __name__ == '__main__': main()
