#!/usr/bin/env python3
"""Parser controls only: these do not count as product R1/R2/R3 evidence."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

CHECKER = pathlib.Path(__file__).with_name('check_ir.py')
IR = '''declare void @llvm.cj.gcwrite.ref(i8 addrspace(1)*, i8 addrspace(1)*, i8 addrspace(1)* addrspace(1)*, ...)
define void @ordinary() {
  call void (i8 addrspace(1)*, i8 addrspace(1)*, i8 addrspace(1)* addrspace(1)*, ...) @llvm.cj.gcwrite.ref(i8 addrspace(1)* null, i8 addrspace(1)* %base, i8 addrspace(1)* addrspace(1)* %field, i32 1)
  ret void
}
define void @weak() {
  call void (i8 addrspace(1)*, i8 addrspace(1)*, i8 addrspace(1)* addrspace(1)*, ...) @llvm.cj.gcwrite.ref(i8 addrspace(1)* null, i8 addrspace(1)* %base, i8 addrspace(1)* addrspace(1)* %field, i32 2)
  ret void
}
'''


class CheckerControls(unittest.TestCase):
    def run_checker(self, text, *extra):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'input.ll'
            path.write_text(text)
            return subprocess.run([sys.executable, str(CHECKER), str(path),
                                   '--expect', 'ordinary=1', '--expect', 'weak=2', *extra],
                                  text=True, capture_output=True)

    def test_explicit_strengths(self):
        result = self.run_checker(IR)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('three_operand=0 invalid=0 writes=2', result.stdout)

    def test_single_missing_operand(self):
        result = self.run_checker(IR.replace(', i32 2)', ')'))
        self.assertEqual(result.returncode, 1)
        self.assertIn('three_operand=1 invalid=1 writes=2', result.stdout)
        self.assertIn('strength.ordinary=PASS', result.stdout)
        self.assertIn('strength.weak=FAIL', result.stdout)

    def test_filtered_target_runs(self):
        result = self.run_checker(IR.replace('i32 2)', 'i32 1)'), '--filter', 'strength.weak')
        self.assertEqual(result.returncode, 1)
        self.assertIn('strength.weak=FAIL', result.stdout)
        self.assertIn('checks=1 failures=1', result.stdout)

    def test_missing_input_cannot_pass_filtered_strength(self):
        result = self.run_checker('', '--filter', 'strength.weak')
        self.assertEqual(result.returncode, 1)
        self.assertIn('strength.weak=FAIL', result.stdout)

    def test_declaration_is_not_a_write(self):
        result = self.run_checker(IR.split('define', 1)[0])
        self.assertEqual(result.returncode, 1)
        self.assertIn('input.writes=FAIL writes=0', result.stdout)


if __name__ == '__main__':
    unittest.main()
