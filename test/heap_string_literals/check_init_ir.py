#!/usr/bin/env python3
"""Check initialization order and the frozen cache ABI in real compiler IR."""
from pathlib import Path
import re,sys
files=sorted(Path(sys.argv[1]).glob('*.ll'))
assert files
checks=failures=0
def check(name, ok):
    global checks,failures
    checks+=1; failures+=not ok
    print(f'ASSERT {name} {"PASS" if ok else "FAIL"}')
units=0; entries=0
for file in files:
    text=file.read_text()
    for declaration in re.findall(r'^declare[^\n]*CJ_MCC_PackageInit[^\n]*',text,re.M):
        check(file.name+'.default_c_abi', not re.search(r'\b(?:fastcc|cc \d+)\b',declaration))
    for match in re.finditer(r'^(define[^\n]*?@([^ (]+)[^\n]*\{)\n(.*?)^}',text,re.M|re.S):
        header,name,body=match.groups(); name=name.strip('"')
        if '.cjstring.materialize.' in name:
            units+=1
            check(name+'.begin.identity.phase', bool(re.search(r'call i32 @CJ_MCC_PackageInitBegin\(i8\* bitcast \(void \(\)\* @_CGP\w+iiHv to i8\*\), i8\* bitcast \(void \(\)\* @'+re.escape(name)+r' to i8\*\), i32 0, i8\*\*',body)))
            check(name+'.execute_or_ready', 'icmp eq i32 %cache.begin, 0' in body and 'icmp eq i32 %cache.begin, 1' in body)
            check(name+'.complete', 'call void @CJ_MCC_PackageInitComplete(' in body)
            allocating='@llvm.cj.malloc.array' in body
            check(name+'.failure_cleanup', not allocating or bool(re.search(r'landingpad token\s+cleanup',body)) and bool(re.search(r'call void @CJ_MCC_PackageInitFail\(i8\* [^,]+, i32 1\)',body)) and 'resume token' in body)
            check(name+'.reject', 'call void @CJ_MCC_PackageInitAbort(' in body and 'unreachable' in body)
        elif re.match(r'_CGP.*i[iurl]Hv$',name):
            calls=[m.start() for m in re.finditer(r'call void @[^ (]+\.cjstring\.materialize\.\d+\(',body)]
            if not calls: continue
            entries+=1
            first_consumer=re.search(r'\bload i1\b|call void @_CGP\w+i[fv]Hv\(',body)
            check(name+'.ensure_before_old_flag', first_consumer is None or max(calls)<first_consumer.start())
check('cache_unit_input',units>0)
check('initializer_input',entries>0)
print(f'INIT_IR_RESULT checks={checks} failures={failures} units={units} entries={entries}')
raise SystemExit(bool(failures))
