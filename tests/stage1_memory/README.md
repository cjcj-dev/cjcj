# Stage1 lifetime assertions

`python3 check.py <result.json> --kind ast|chir` checks completed compilations,
positive controls and GC-completed observations before evaluating every target.
Exit 0 means all selected lifetime assertions passed, 1 means a target failed,
and 2 means the measurement was not qualified. It does not infer release from
missing observations or from an unexecuted compiler.

The result comes from the real stage1 package compilation, with its compiler
ELF hash, loaded SO hashes, command, CPU domain and uptime recorded beside the
observations. Measurement-only source copies attach weak references to acyclic
leaf sentinels owned by AST/CHIR objects; references to cyclic AST nodes are not
a valid observer on the host runtime. These diagnostic copies force GC, so their
RSS must not be compared with an uninstrumented compiler's RSS. No diagnostic
fields or hooks are added to the shipped compiler.

AST targets cover package, file and top-level declaration retirement at
`chir_optimized` and `chir_end`. The CHIR target covers context retirement at
`process_end`; its positive control is `chir_optimized`. Report the corresponding
upstream ownership boundary, the diagnostic patch, artifact identities and a
real product cut/restoration for each claimed causal result. A passing JSON
check alone does not establish artifact identity or complete branch coverage.

The #614 measurement recipes, diagnostic patches and immutable outputs are
indexed by REPORT-sym_cjcj_614_implement_r5876319779.md. Container capacity and
annotation-map storage are not observed by these tests.
