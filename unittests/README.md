# Unit test fixtures

These files are copied unchanged from the matching paths in the upstream
Cangjie compiler. CheckCjd, ConditionalCompilation and Driver tests consume them.
Utils uses its directory as the IsDirTest positive input.

Run tests from the checkout root, or set `PROJECT_SOURCE_DIR` to the absolute
checkout root when invoking a test executable elsewhere. This is the cjpm
adaptation of the upstream CMake `PROJECT_SOURCE_DIR` definition, also used by
`packages/option/src/Option_test.cj`. No external reference checkout is required.
