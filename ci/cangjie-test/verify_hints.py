#!/usr/bin/env python3
"""Exercise environment-hint classification on synthetic suite records (hit and not-hit)."""
import json
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run import dump_case_rows, environment_hints, summarize  # noqa: E402

HIT_DETAIL = ("error: can not find package 'stdx.net.http'\n"
              "  ==> main.cj:3:8:\n"
              "3 | import stdx.net.http\n"
              "No such directory: '-lstdx.chir'\n")
MISS_DETAIL = ("error: incompatible types: 'Int64' and 'String'\n"
               "  ==> main.cj:5:12:\nexpected 1 argument, found 2\n")


def fake_hlt_raw(root):
    case_dir = root / 'testsuites/HLT/API/Regression'
    (case_dir / 'hit').mkdir(parents=True)
    (case_dir / 'miss').mkdir(parents=True)
    group = {'total': 3, 'tests': [
        {'name': 'API/Regression/hit/hit.cj', 'result': 'FAIL',
         'output': [{'command': 'cjc', 'return_code': 1, 'stderr': HIT_DETAIL}]},
        {'name': 'API/Regression/miss/miss.cj', 'result': 'FAIL',
         'output': [{'command': 'cjc', 'return_code': 1, 'stderr': MISS_DETAIL}]},
        {'name': 'API/Regression/ok/ok.cj', 'result': 'PASS', 'output': ''}]}
    return [group]


def main():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        raw = root / 'results.json'
        raw.write_text(json.dumps(fake_hlt_raw(root)))
        rows = summarize('HLT', raw, root)
        by_name = {row['name']: row for row in rows}
        hit = by_name['testsuites/HLT/API/Regression/hit/hit.cj']
        miss = by_name['testsuites/HLT/API/Regression/miss/miss.cj']
        assert 'can not find package' in hit['environment_hints'], hit
        assert 'No such directory:' in hit['environment_hints'], hit
        assert miss['environment_hints'] == [], miss
        out = root / 'out'
        out.mkdir()
        environmental = dump_case_rows(out, rows)
        written = json.loads((out / 'environment-failures.json').read_text())
        assert written == environmental
        names = [entry['name'] for entry in written]
        assert names == ['testsuites/HLT/API/Regression/hit/hit.cj'], written
        entry = written[0]
        assert any('CANGJIE_STDX_PATH' in reason for reason in entry['reasons']), entry
        assert "can not find package 'stdx.net.http'" in entry['error_evidence'] or \
               "No such directory: '-lstdx.chir'" in entry['error_evidence'], entry
        # Direct hit/not-hit pair on the matcher itself.
        assert environment_hints(HIT_DETAIL)[:2] == ['No such directory:', 'can not find package']
        assert environment_hints(MISS_DETAIL) == []
        print('VERIFY_HINTS_OK hit=1 not_hit=1 written=%d' % len(written))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
