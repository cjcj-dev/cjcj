目标: IR 级 calldiff，逐 ABI-mangled 函数比较 reference/selfhost 直接 call/invoke callee 多重集。
已落 commit 清单: 待本轮提交（tools/calldiff.py、tools/README.md、reports/CALLDIFF_CODEGEN_0712.tsv）。
下一步: 以 reports/CALLDIFF_CODEGEN_0712.tsv 的 TOP-30 为候选审计队列；新基线直接重跑同命令。
