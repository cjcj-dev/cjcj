#!/usr/bin/env python3
"""Replay upstream record formats through run_suite's execution and JSON outputs.

Completion excerpts are the two saved #504 out1 records (residual-explanation.json),
not complete upstream logs. The fixture runner only writes records; run.py owns
all classification and reporting. No compiler/runtime behavior is claimed.
"""
import json
import os
from pathlib import Path
import tempfile
import unittest
from run import run_suite

HERE = Path(__file__).resolve().parent
COMPLETIONS = json.loads((HERE / 'fixtures/completion-timeout-mentions.json').read_text())

# An external runner obeys the upstream output-path convention, allowing the
# actual run_suite -> execute -> summarize -> dump_case_rows chain to run.
RUNNER = '''import json, pathlib, sys
args = sys.argv[1:]
key = '--log-file' if '--log-file' in args else '--json_output'
out = pathlib.Path(args[args.index(key) + 1])
if key == '--log-file':
    out = pathlib.Path(str(out) + '.json')
out.write_text(pathlib.Path(__file__).with_name('records.json').read_text())
print('UPSTREAM_RECORDS_EMITTED', out)
sys.exit(1)
'''


class TimeoutHintsTest(unittest.TestCase):
    def replay(self, suite, detail, timeout, hint, status='FAIL'):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            test = root / 'test'
            framework = root / 'framework'
            framework.mkdir()
            output = root / 'output'
            output.mkdir()
            if suite == 'Conformance':
                harness = test / 'Conformance/Compiler/harness'
                harness.mkdir(parents=True)
                cases = test / 'Conformance/Compiler/testsuite'
                cases.mkdir()
                (cases / 'test1.cj').write_text('')
                records = [{'test_path': 'test1.cj', 'result': status,
                            'compile_log': detail, 'execute_log': ''}]
                runner = harness / 'harness.py'
            else:
                records = [{'total': 1, 'tests': [
                    {'name': 'case.info', 'result': status, 'output': detail}]}]
                runner = framework / 'main.py'
            runner.write_text(RUNNER)
            runner.with_name('records.json').write_text(json.dumps(records))
            record, rows = run_suite(suite, test, framework, output,
                                    dict(os.environ, CANGJIE_HOME=str(root)), 2)
            out = output / suite
            written = {name: json.loads((out / (name + '.json')).read_text())
                       for name in ('cases', 'failures', 'timeout-failures', 'environment-failures')}
            self.assertEqual(record['rc'], 1)
            self.assertIn('UPSTREAM_RECORDS_EMITTED', (out / 'runner.log').read_text())
            self.assertEqual(rows, written['cases'])
            self.assertEqual(rows[0]['status'], status)
            self.assertEqual(rows[0]['category'], 'fail' if status == 'FAIL' else 'pass')
            self.assertEqual(len(written['failures']), int(status == 'FAIL'))
            self.assertEqual(rows[0]['timeout_failure'], timeout)
            self.assertEqual(len(written['timeout-failures']), int(timeout))
            # The target assertion observes the final product JSON, not a helper.
            actual = [h for entry in written['environment-failures'] for h in entry['hints']]
            print('TARGET_OBSERVED', self._testMethodName, suite, 'hints=', actual, flush=True)
            self.assertEqual(actual, [hint] if hint else [])
            if hint:
                self.assertIn(hint, written['environment-failures'][0]['error_evidence'])
                self.assertTrue(written['environment-failures'][0]['reasons'])

    def test_completion_mentions(self):
        for suite in ('HLT', 'LLT'):
            for item in COMPLETIONS:
                with self.subTest(suite=suite, case=item['name']):
                    self.replay(suite, [{'cmd': 'completion', 'return_code': 1,
                                         'stdout': item['stdout'], 'stderr': ''}], False, None)

    def test_maple_timeout(self):
        for suite in ('HLT', 'LLT'):
            for item in COMPLETIONS:
                with self.subTest(suite=suite, case=item['name']):
                    self.replay(suite, [{'cmd': 'completion', 'return_code': 3,
                                         'stdout': item['stdout'], 'stderr': 'TimeOut'}], True, 'TimeOut')

    def test_partial_timeout_signature(self):
        for code, err in ((1, 'TimeOut'), (3, 'public class TimeoutException'),
                          (3, 'timed out'), (3, 'timeout has expired')):
            with self.subTest(code=code, stderr=err):
                self.replay('HLT', [{'return_code': code, 'stderr': err}], False, None)

    def test_conformance_timeout(self):
        self.replay('Conformance', 'The 5.0-second timeout has expired', True, 'timeout has expired')

    def test_conformance_mentions(self):
        self.replay('Conformance', 'public class TimeoutException; timed out; timeout has expired', False, None)

    def test_other_environment_hint(self):
        self.replay('HLT', [{'return_code': 1, 'stderr': 'command not found'}], False, 'command not found')

    def test_pass_unchanged(self):
        self.replay('HLT', [{'return_code': 3, 'stderr': 'TimeOut'}], False, None, 'PASS')


if __name__ == '__main__':
    unittest.main(verbosity=2)
