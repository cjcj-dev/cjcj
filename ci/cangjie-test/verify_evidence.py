#!/usr/bin/env python3
"""Regression: diagnostic evidence survives Maple command length."""
import json
from pathlib import Path
import tempfile
import unittest
from run import dump_case_rows, summarize


class EvidenceTest(unittest.TestCase):
    def check_command(self, command):
        diagnostic = "No such directory: '-lstdx.chir'"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            raw = root / 'results.json'
            raw.write_text(json.dumps([{'total': 2, 'tests': [
                {'name': 'hit.cj', 'result': 'FAIL', 'output': [
                    {'cmd': command, 'return_code': 1, 'stderr': diagnostic}]},
                {'name': 'miss.cj', 'result': 'FAIL', 'output': [
                    {'cmd': command, 'return_code': 1,
                     'stderr': 'error: incompatible types'}]}]}]))
            rows = summarize('HLT', raw, root)
            dump_case_rows(root, rows)
            entries = json.loads((root / 'environment-failures.json').read_text())
            self.assertEqual(len(entries), 1)
            self.assertIn(diagnostic, entries[0]['error_evidence'])
            print('DIAGNOSTIC_OBSERVED command_length=%d' % len(command))

    def test_short_command(self):
        self.check_command('cjc main.cj')

    def test_long_command(self):
        self.check_command('cjc ' + '-L /some/library/path ' * 100 + 'main.cj')


if __name__ == '__main__':
    unittest.main(verbosity=2)
