# Option test input

`main.cj` is the repository-owned source input for the Option tests. The test
setup resolves it from `PROJECT_SOURCE_DIR`, or from the current directory when
that variable is unset. Run from the repository root:

```sh
cjpm test --member packages/option
```

When running the test executable from another directory, set
`PROJECT_SOURCE_DIR` to the absolute root of this checkout. This is the cjpm
counterpart of the upstream OptionTest setup's CMake `PROJECT_SOURCE_DIR`.
The fixture must exist: missing input should fail the three successful-input
tests, while malformed/conflicting option tests still reject their arguments.
