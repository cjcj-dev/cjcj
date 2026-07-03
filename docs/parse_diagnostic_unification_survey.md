# Parse Diagnostic Unification Survey

Stage 1 survey for removing `packages/parse/src/DiagnosticEngine.cj`.

## C++ Target API

- `include/cangjie/Basic/DiagnosticEngine.h:91-104` defines the real `DiagSeverity` and `DiagCategory`.
- `include/cangjie/Basic/DiagnosticEngine.h:163-168` defines `DiagKindRefactor` from `DiagnosticAll.def`.
- `include/cangjie/Basic/DiagnosticEngine.h:341-453` defines the real `Diagnostic` record, including `rKind`, `mainHint`, `diagSeverity`, and `diagCategory`.
- `include/cangjie/Basic/DiagnosticEngine.h:631-735` defines `DiagnosticBuilder` with `AddHint`, `AddMainHintArguments`, `AddNote`, `AddHelp`, and destructor emission.
- `include/cangjie/Basic/DiagnosticEngine.h:901-927` defines `DiagnoseRefactor(kind, Position, ...)` and `DiagnoseRefactor(kind, Range, ...)`.
- `include/cangjie/Basic/DiagnosticEngine.h:1023-1037` exposes `HandleDiagnostic`, `GetCategoryDiagnostic`, and `Reset`.
- `src/Basic/DiagnosticEngine.cpp:686-696` shows `Reset` clears counts and calls `handler->Clear()`.

## Selfhost Parallel API

`packages/parse/src/DiagnosticEngine.cj` duplicates a reduced diagnostic engine:

- `DiagSeverity.ERROR/WARNING/NOTE`.
- A local `DiagKindRefactor` subset, including non-C++ pseudo kinds such as `PARSE_ERROR`, `EXPECTED_TOKEN`, `EXPECTED_IDENTIFIER`, `UNEXPECTED_TOKEN`, `UNTERMINATED_DELIMITER`, `INVALID_MODIFIER`, `DUPLICATED_MODIFIER`, `CONFLICTING_MODIFIER`, and `INVALID_ANNOTATION`.
- A reduced `Diagnostic` with only `severity`, `kind`, `pos`, and `message`.
- A reduced `DiagnosticBuilder` with `Emit`, `AddMainHintArguments`, and `close`.
- `DiagnosticEngine.Store`, `DiagnoseRefactor`, `Warning`, `HasError`, `Diagnostics`, and `Clear`.

## Capability Diff

- Severity: covered by `basic.DiagSeverity`.
- Kind identity: covered only for real C++ names by `basic.DiagKindRefactor`; the uppercase parse-local pseudo kinds are not upstream names and must be mechanically mapped to real C++ refactor kinds in stage 3.
- Diagnostic records: covered by `basic.Diagnostic`, with strictly more C++ fields.
- Builders: covered by `basic.DiagnosticBuilder`, with strictly more C++ methods.
- Emission/storage: covered by `basic.HandleDiagnostic`, `GetCategoryDiagnostic`, `GetErrorCount`, and `Reset`.
- `Diagnostics()` over all parser-local diagnostics has no C++ counterpart; callers must use category reads/counts instead of porting this parallel API into `basic`.
- `HasError()` has no C++ `DiagnosticEngine` counterpart; callers must use `GetErrorCount() > 0`.
- `Clear()` is covered by `Reset`, whose selfhost implementation already clears the active handler as in `src/Basic/DiagnosticEngine.cpp:686-696`.

No additional `basic` API was ported in stage 1 because every C++ diagnostic capability needed for unification is already present in selfhost `basic`; the non-C++ parse-local conveniences will be removed rather than copied.
