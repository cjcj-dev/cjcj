# TODO: replace handwritten CJO reads with official generated accessors

This slice only adds the parallel `fullPkgName` and dependency-package-name
read path. It deliberately leaves every existing `CjoFlatBuffer` consumer in
place.

## Remaining access-site inventory

There are **524 handwritten reader access sites** still to migrate in
`FrontendModel.cj`:

| Category | Sites | Included handwritten operations |
| --- | ---: | --- |
| Strings | 26 | `StringField` (17), `StringAt` (9) |
| Vectors | 278 | `VectorField` (98), `VectorLength` (111), `VectorU32` (65), `VectorU64` (2), `VectorBool` (2) |
| Scalars | 101 | `U8Field` (61), `U16Field` (8), `U32Field` (20), `I32Field` (1), `I64Field` (2), `U64At` (5), `U32At` (2), `I32At` (2) |
| Nested tables | 119 | `RootTable` (10), `OffsetField` (68), `VectorOffsetElement` (41) |

The inventory counts source-level calls after the `CjoFlatBuffer` class in the
pre-slice `FrontendModel.cj`; it excludes the reader's own method definitions
and the new comparison/probe entry. `RootTable` is classified with nested-table
navigation, and `VectorOffsetElement` is classified there rather than counted a
second time as a vector access.

## Replacement checklist

- [x] Add an official generated-accessor view with explicit ownership and
  length-bearing string returns.
- [x] Add parallel reads for `Package.fullPkgName` and the filtered
  `Package.imports` dependency-name table.
- [ ] Replace the 26 string access sites, preserving embedded NUL bytes.
- [ ] Replace the 278 vector access sites, preserving order, duplicates, and
  absent-versus-empty behavior.
- [ ] Replace the 101 scalar access sites, preserving schema defaults and enum
  validation.
- [ ] Replace the 119 nested-table navigation sites, preserving optional-table
  behavior and union discrimination.
- [ ] Remove `CjoFlatBuffer` only after all migrated fields have direct
  positive/negative acceptance coverage.
