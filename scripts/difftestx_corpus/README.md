# difftestx structural corpus

This corpus extends the flat single-file difftest with package-shaped cases.
Run it after building the self-host compiler:

```bash
JOBS=4 CJC_JOBS=1 bash scripts/difftestx_corpus/run.sh
```

The manifest binds each case to its upstream HLT origin and coverage. The 18
cases comprise 12 import-path/multi-package cases, three macro-package
import/invocation cases, and three incremental two-pass rebuild cases.
