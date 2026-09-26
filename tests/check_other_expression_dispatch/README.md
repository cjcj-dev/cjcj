# CheckOtherExpression dispatch witnesses

Build release CHIR archives, then run:

```sh
python3 tests/check_other_expression_dispatch/run.py --build-tree TREE --sdk SDK --out OUT
```

The runner links existing product archives and calls the public
`CHIRChecker.CheckPackage([CHECK_FUNC_BODY])` entry. It runs 29 independent
processes: one real subclass for each of the 27 upstream table entries,
an unknown-kind warning case, and a valid constant control. Assertions consume
the returned Bool and diagnostic text; every run prints a TARGET result.
No checker implementation or test hook is compiled into the fixture.

Upstream: `src/CHIR/Checker/CHIRChecker.cpp:3374-3441`.
The two cast cases deliberately have no operands: upstream `CheckTypeCast`
at line 3751 is empty, so the dispatcher must not add its own operand check.
Other malformed cases exercise the corresponding checker-owned diagnostic.

In isolated source copies, removing only the CONSTANT callback or forcing only
CONSTANT lookup to miss must fail only the malformed constant case. Removing the
OTHERS invocation in CheckExpression must fail the other-expression negative
witnesses and warning witness while the cast and valid-constant controls pass.
Also run `tests/check_expression_dispatch` and `tests/instantiate_value` to
retain cross-major-kind and instantiated-value controls.

The runner records archive, SDK and ELF identities, return codes, wall time,
affinity and uptime. Cases run concurrently in separate processes.
