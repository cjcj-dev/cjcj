#!/usr/bin/env python3
"""Exercise the classifier CLI, including a one-case B-only positive control."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from classify import CATEGORIES, SUITES

HERE = Path(__file__).resolve().parent


def fixture(root, statuses):
    root.mkdir()
    identity = dict.fromkeys(('pins', 'jobs', 'compiler_jobs', 'recipe_sha256', 'source_manifest_sha256',
                             'adapter_hashes', 'adapter_source_sha256', 'compiler_sha256', 'runtime_sha256'), 'fixture')
    (root / 'identity.json').write_text(json.dumps(identity))
    (root / 'environment.json').write_text(json.dumps({'tools': {'cjdb': {'ready': False, 'reason': 'missing loader'}}}))
    for suite in SUITES:
        path = root / suite
        path.mkdir()
        rows = []
        for name in ('b', 'o', 'common', 'timeout', 'noise', 'environment', 'Tools/cjdb/tool', 'pass', 'unresolved'):
            category = statuses.get(name, 'pass') if suite == 'HLT' else 'pass'
            row = dict(name='testsuites/' + suite + '/' + name, suite=suite,
                       status={'pass': 'PASS', 'fail': 'FAIL', 'not_run': 'UNRESOLVED'}[category],
                       category=category, timeout_failure=name == 'timeout' and category == 'fail',
                       environment_hints=['No space left on device'] if name == 'environment' and category == 'fail' else [],
                       error_summary='')
            rows.append(row)
        (path / 'summary.json').write_text(json.dumps({'status': 'ran', 'counts': {}}))
        (path / 'cases.json').write_text(json.dumps(rows))


class ClassifyTest(unittest.TestCase):
    def invoke(self, official, output, *arguments):
        process = subprocess.run([sys.executable, str(HERE / 'classify.py'), str(official), str(output), *map(str, arguments)],
                                 capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        return json.loads(output.read_text())

    def test_seven_categories_and_exact_delta(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            o, b, b2 = (root / name for name in ('O', 'B', 'B2'))
            common = {'common': 'fail', 'timeout': 'fail', 'environment': 'fail',
                      'Tools/cjdb/tool': 'fail', 'unresolved': 'not_run'}
            fixture(o, dict(common, o='fail'))
            fixture(b, dict(common, b='fail', noise='fail'))
            fixture(b2, dict(common, b='fail'))
            result = self.invoke(o, root / 'classified.json', '--bootstrap', b, '--repeat-bootstrap', b2)
            print('CLASSIFY_SEVEN_TARGET', result['counts'])
            self.assertEqual(result['counts'], dict.fromkeys(CATEGORIES, 1))
            self.assertEqual([r['name'] for r in result['categories']['B_only']], ['testsuites/HLT/b'])
            before = result['counts']
            cases = b / 'HLT/cases.json'
            rows = json.loads(cases.read_text())
            for row in rows:
                if row['name'] == 'testsuites/HLT/b':
                    row.update(category='pass', status='PASS')
            for arm in (b, b2):
                armrows = json.loads((arm / 'HLT/cases.json').read_text())
                for row in armrows:
                    if row['name'] == 'testsuites/HLT/b':
                        row.update(category='pass', status='PASS')
                (arm / 'HLT/cases.json').write_text(json.dumps(armrows))
            restored = self.invoke(o, root / 'restored.json', '--bootstrap', b, '--repeat-bootstrap', b2)
            self.assertEqual(restored['counts'], dict(before, B_only=0))
            print('CLASSIFY_EXACT_DELTA B_only=1->0 others=unchanged')

    def test_official_alone_does_not_invent_comparison(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            o = root / 'O'
            fixture(o, {'b': 'fail'})
            result = self.invoke(o, root / 'classified.json')
            self.assertFalse(result['comparison_available'])
            self.assertEqual(result['counts']['O_only'], 0)
            self.assertEqual(len(result['unpaired_failures']), 1)
            print('CLASSIFY_UNPAIRED_TARGET 1')

    def test_missing_case_is_not_a_pass(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            o, b = root / 'O', root / 'B'
            fixture(o, {})
            fixture(b, {'b': 'fail'})
            path = o / 'HLT/cases.json'
            path.write_text(json.dumps([r for r in json.loads(path.read_text()) if r['name'] != 'testsuites/HLT/b']))
            result = self.invoke(o, root / 'classified.json', '--bootstrap', b)
            self.assertEqual(result['counts']['B_only'], 0)
            self.assertEqual(len(result['unpaired_failures']), 1)
            self.assertEqual(len(result['case_set_differences']), 1)
            print('CLASSIFY_MISSING_CASE_TARGET 1')


if __name__ == '__main__':
    unittest.main(verbosity=2)
