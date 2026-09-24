#!/usr/bin/env python3
"""Exercise the actual resource selector against this host's physical memory."""
from pathlib import Path
import subprocess
import unittest

script = Path(__file__).with_name('build_resources.sh')
mem_kb = int(next(line.split()[1] for line in Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemTotal:')))
budget_mb = mem_kb * 3 // 4 // 1024


def select(request):
    result = subprocess.run(['bash', script, request], capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(result.stderr)
    print(result.stderr.strip())
    values = dict(line.split('=') for line in result.stdout.splitlines())
    return int(values['STD_BUILD_HEAP'].removesuffix('MB')), int(values['STD_BUILD_JOBS'])


class Resources(unittest.TestCase):
    def test_small_request(self):
        heap, jobs = select('4MB')
        self.assertEqual(heap, 4)
        self.assertGreaterEqual(jobs, 1)
        print('ASSERT bounded small request retained')

    def test_above_physical_memory(self):
        heap, jobs = select(f'{mem_kb * 2 // 1024}MB')
        self.assertEqual(heap, budget_mb, 'compiler heap must be capped before host runtime parses it')
        self.assertEqual(jobs, int(subprocess.check_output(['getconf', '_NPROCESSORS_ONLN'])) if budget_mb >= 96 * 1024 else 1)
        print('ASSERT oversized request capped to measured physical-memory budget')


unittest.main(verbosity=2)
