#!/usr/bin/env python3
"""Assert the actual child outcome; Abort cannot print an assertion after _Exit."""
from pathlib import Path
import re,sys
out=Path(sys.argv[1]); log=(out/'run.log').read_text(); rc=int((out/'run.rc').read_text())
checks=[('failure.control.bytes','ASSERT library.control.bytes PASS' in log),
        ('failure.original.exception','exception:std.core:OutOfMemoryError' in log and
         'ASSERT library.failure.original.returned PASS' in log),
        ('failure.no.consumer','ASSERT library.failure.no.consumer PASS' in log),
        ('failure.retry.failed.state',bool(re.search(r'package cache initialization failed:.*phase=0 result=2',log))),
        ('failure.retry.must.abort70',rc==70)]
for name,ok in checks: print('ASSERT '+name+' '+('PASS' if ok else 'FAIL'))
print(f'FAILURE_RESULT checks={len(checks)} failures={sum(not ok for _,ok in checks)} child_rc={rc}')
raise SystemExit(any(not ok for _,ok in checks))
