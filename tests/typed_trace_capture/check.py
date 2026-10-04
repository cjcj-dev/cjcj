#!/usr/bin/env python3
"""Check the real saved LLVM IR from the paired compiler, without running a target."""
import argparse, json, re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('ir',type=Path);p.add_argument('--json',type=Path,required=True);a=p.parse_args()
s=a.ir.read_text()
fill=[line for line in s.splitlines() if re.search(r'\b(call|invoke)\b',line) and re.search(r'@(CJ_MCC_FillInStackTrace|llvm.cj.fill.in.stack.trace)\(',line)]
decode=[line for line in s.splitlines() if re.search(r'\b(call|invoke)\b',line) and '@CJ_MCC_DecodeStackTrace(' in line]
checks={'fill_call_reached':bool(fill),'decode_call_reached':bool(decode)}
checks['fill_four_inputs_gc_result']=bool(fill) and all(re.search(r'i8 addrspace\(1\)\* @(CJ_MCC_FillInStackTrace|llvm.cj.fill.in.stack.trace)\(i8\* [^,]+, i8\* [^,]+, i8\* [^,]+, i8 addrspace\(1\)\* [^)]+\)',line) for line in fill)
checks['decode_hidden_sret_and_three_inputs']=bool(decode) and all(re.search(r'\bvoid @CJ_MCC_DecodeStackTrace\(',line) and 'sret(' in line and re.search(r', i8 addrspace\(1\)\* [^,]+, i64 [^,]+, i8\* [^)]+\)',line) for line in decode)
checks['generated_typeinfo_present']='CFileKlass' in s and 'TraceCapture' in s and 'TraceFrame' in s
result={'checks':checks,'fill_calls':fill,'decode_calls':decode,'rc':0 if all(checks.values()) else 1}
a.json.write_text(json.dumps(result,indent=2)+'\n')
for name,ok in checks.items():print(('PASS ' if ok else 'FAIL ')+name)
raise SystemExit(result['rc'])
