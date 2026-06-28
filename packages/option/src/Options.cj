package cangjie_compiler::option

private let EMPTY_VALUES: Array<OptionValue> = Array<OptionValue>()

private func value(
    name: String,
    help: String,
    backends: Array<Backend>,
    groups: Array<Group>
): OptionValue {
    return OptionValue(name, help, backends, groups)
}

private func optionValues(name: String): Array<OptionValue> {
    if (name == "backend_value") {
        return [
            value("llvm", "compile with cjnative backend (default)", [Backend.ALL], [Group.STABLE])
        ]
    }
    if (name == "warn_group") {
        return [
            value("all", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("unused", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("unused-main", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("driver-arg", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("deprecated", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("unsupport-compile-source", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("package-import", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("parser", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("semantics", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("interpreter", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE]),
            value("apilevel-check", "", [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE])
        ]
    }
    if (name == "diagnostic_value") {
        return [
            value("json", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("noColor", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("default", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE])
        ]
    }
    if (name == "emit_chir_phase") {
        return [
            value("raw", "emit CHIR before compiler optimization", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("opt", "emit CHIR after compiler optimization (default)", [Backend.ALL], [Group.STABLE, Group.VISIBLE])
        ]
    }
    if (name == "chir_mode") {
        return [
            value("standard", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("withID", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("all", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE])
        ]
    }
    if (name == "simple_on_off_mode") {
        return [
            value("on", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("off", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE])
        ]
    }
    if (name == "integer_overflow_mode") {
        return [
            value("throwing", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("wrapping", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("saturating", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE])
        ]
    }
    if (name == "sanitizer_type") {
        return [
            value("address", "enable address sanitizer", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE]),
            value("thread", "enable thread sanitizer", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE]),
            value(
                "hwaddress",
                "enable hardware-assisted address sanitizer",
                [Backend.CJNATIVE],
                [Group.STABLE, Group.VISIBLE]
            )
        ]
    }
    if (name == "stack_trace_format") {
        return [
            value("default", "", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE]),
            value("simple", "", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE]),
            value("all", "", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE])
        ]
    }
    if (name == "output_type_list") {
        return [
            value("exe", "emit executable (default)", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE]),
            value("staticlib", "emit static library", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE]),
            value("dylib", "emit dynamic library", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE]),
            value("chir", "emit partially compiled package", [Backend.CJNATIVE], [Group.VISIBLE]),
            value("obj", "emit obj", [Backend.CJNATIVE], [Group.VISIBLE])
        ]
    }
    if (name == "compile_target_list") {
        return [
            value("exe", "compile executable (default)", [Backend.CJNATIVE], [Group.VISIBLE]),
            value("staticlib", "compile static library", [Backend.CJNATIVE], [Group.VISIBLE]),
            value("dylib", "compile dynamic library", [Backend.CJNATIVE], [Group.VISIBLE])
        ]
    }
    if (name == "lto_mode") {
        return [
            value("full", "", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE]),
            value("thin", "", [Backend.CJNATIVE], [Group.STABLE, Group.VISIBLE])
        ]
    }
    if (name == "bchir_print_mode") {
        return [
            value("deserialized", "after deserialisation", [Backend.CJNATIVE], [Group.STABLE]),
            value("linked", "after linkage", [Backend.CJNATIVE], [Group.STABLE]),
            value("chir2bchir", "after chir2bchir", [Backend.CJNATIVE], [Group.STABLE]),
            value("interpreter", "interpretation trace", [Backend.CJNATIVE], [Group.STABLE]),
            value("ce-linked", "const eval after linkage", [Backend.CJNATIVE], [Group.STABLE]),
            value("ce-chir2bchir", "const eval after chir2bchir", [Backend.CJNATIVE], [Group.STABLE]),
            value("all", "all of the above", [Backend.CJNATIVE], [Group.STABLE])
        ]
    }
    if (name == "mock_mode") {
        return [
            value("on", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("off", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE]),
            value("runtime-error", "", [Backend.ALL], [Group.STABLE, Group.VISIBLE])
        ]
    }
    return EMPTY_VALUES
}

public func CreateOptionInfos(): Array<OptionInfo> {
    return [
        OptionInfo("--dump-tokens", ID.DUMP_TOKENS, Kind.FLAG, [Backend.ALL], [Group.FRONTEND, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Print all of the tokens in one compile unit"),
        OptionInfo("--dump-symbols", ID.DUMP_SYMBOLS, Kind.FLAG, [Backend.ALL], [Group.FRONTEND, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Print symbols after semantic analysis"),
        OptionInfo("--typecheck", ID.TYPE_CHECK, Kind.FLAG, [Backend.ALL], [Group.FRONTEND, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Parse and check type of input file(s)"),
        OptionInfo("-d", ID.COMPILE_CJD, Kind.FLAG, [Backend.ALL], [Group.FRONTEND, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Compile declaration file(s) (.cj.d)"),
        OptionInfo("--diagnostic-format", ID.DIAG_FORMAT, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", optionValues("diagnostic_value"), Occurrence.SINGLE_OCCURRENCE, "Diagnostic format. Candidate modes: "),
        OptionInfo("--backend", ID.BACKEND_MODE, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", optionValues("backend_value"), Occurrence.SINGLE_OCCURRENCE, "Specify backend toolchain"),
        OptionInfo("--scan-dependency", ID.DUMP_DEPENDENT_PACKAGE, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Get the package(s) which the current package depends on"),
        OptionInfo("--no-sub-pkg", ID.NO_SUB_PACKAGE, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "The package doesn't have sub-packages"),
        OptionInfo("--cfg", ID.CONDITIONAL_COMPILATION_CONFIG, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "User defined condition to compile"),
        OptionInfo("--debug-macro", ID.COMPILE_DEBUG_MACRO, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable debug macro"),
        OptionInfo("--parallel-macro-expansion", ID.PARALLEL_MACRO_EXPANSION, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable parallel macro expansion"),
        OptionInfo("-g", ID.COMPILE_DEBUG, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable compile debug version target"),
        OptionInfo("--trimpath", ID.TRIMPATH, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Remove a specified path prefix in debuginfo"),
        OptionInfo("--strip-all", ID.STRIP_ALL, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "-s", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Strip the symbol table from executable and dynamic library"),
        OptionInfo("--no-stacktrace-info", ID.NO_STACKTRACE_INFO, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Do not display the line number and file name information"),
        OptionInfo("--test", ID.COMPILE_TEST, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable compile test"),
        OptionInfo("--test-only", ID.COMPILE_TESTS_ONLY, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Compile test files only (`<filename>_test.cj`), production parts should be added as a dependency separately"),
        OptionInfo("--export-for-test", ID.EXPORT_FOR_TESTS, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Export some additional kinds of declaration specifically for using them in tests"),
        OptionInfo("--mock", ID.MOCK, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", optionValues("mock_mode"), Occurrence.SINGLE_OCCURRENCE, "Specify whether mock features are enabled, or disabled, or a runtime exception is thrown when trying to use mock features"),
        OptionInfo("--output", ID.OUTPUT_FILE, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "-o", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify product name or output directory when compiling a package"),
        OptionInfo("--output-dir", ID.OUTPUT_DIR, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify output directory (it affects '--output' option)"),
        OptionInfo("--output-javagen-dir", ID.OUTPUT_JAVA_GEN_DIR, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify output directory for javagen"),
        OptionInfo("--objc-interop-output-dir", ID.OUTPUT_OBJC_GEN_DIR, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify output directory for Objective-C generated sources"),
        OptionInfo("--no-prelude", ID.NO_PRELUDE, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Not import cangjie std.core package by default, only applicable when compiling std.core"),
        OptionInfo("--static", ID.STATIC, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Statically link cangjie library"),
        OptionInfo("--static-std", ID.STATIC_STD, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Statically link packages of the std module"),
        OptionInfo("--dy-std", ID.DY_STD, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dynamically link packages of the std module"),
        OptionInfo("--static-libs", ID.STATIC_LIBS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Statically link packages of other modules except std"),
        OptionInfo("--dy-libs", ID.DY_LIBS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dynamically link packages of other modules except std"),
        OptionInfo("--lto", ID.LTO, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", optionValues("lto_mode"), Occurrence.SINGLE_OCCURRENCE, "Enable LTO to either 'full' or 'thin' (Not available for Windows target)"),
        OptionInfo("--compile-as-exe", ID.COMPILE_AS_EXE, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Hide symbols from bitcode files in LTO mode, and only the package init symbols remain visible"),
        OptionInfo("--lto-keep-pkg-visibility", ID.LTO_KEEP_PKG_VISIBILITY, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Specify packages that remain visible in LTO mode. Use \"\" to hide all packages"),
        OptionInfo("--profile-compile-time", ID.PROFILE_COMPILE_TIME, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.VISIBLE, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Print time spent of all phases in the compilation"),
        OptionInfo("--profile-compile-memory", ID.PROFILE_COMPILE_MEMORY, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.VISIBLE, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Print memory usage of all phases in the compilation"),
        OptionInfo("--enable-eh", ID.ENABLE_EFFECTS, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enables experimental support for effect handlers"),
        OptionInfo("--dump-ast", ID.DUMP_AST, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump human readable AST when compiling for debug"),
        OptionInfo("--dump-chir", ID.DUMP_CHIR, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump human readable CHIR when compiling for debug"),
        OptionInfo("--dump-ir", ID.DUMP_IR, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump human readable IR"),
        OptionInfo("--dump-all", ID.DUMP_ALL, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump all of AST, CHIR, IR"),
        OptionInfo("--dump-to-screen", ID.DUMP_TO_SCREEN, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump to screen instead of file"),
        OptionInfo("--debug-annotations", ID.DUMP_ANNOTATIONS_DEBUG, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Debug computing annotations stage"),
        OptionInfo("--deserialize-chir-and-dump", ID.DESERIALIZE_CHIR_AND_DUMP, Kind.SEPARATED, [Backend.ALL], [Group.FRONTEND, Group.STABLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Deserialize CHIR and dump CHIL to file"),
        OptionInfo("--emit-chir", ID.EMIT_CHIR, Kind.FLAG_WITH_ARG, [Backend.ALL], [Group.GLOBAL, Group.VISIBLE, Group.STABLE], "", optionValues("emit_chir_phase"), Occurrence.SINGLE_OCCURRENCE, "emit CHIR serialization file of the specified phase. Candidate phases:"),
        OptionInfo("--chir-wfc", ID.CHIR_WFC, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", optionValues("simple_on_off_mode"), Occurrence.SINGLE_OCCURRENCE, "Well-formedness check for CHIR. Candidate modes: "),
        OptionInfo("--enable-chir-redundant-getorthrow-elimination", ID.ENABLE_CHIR_REDUNDANT_GETORTHROW_ELIMINATION, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable CHIR redundant GetOrThrow elimination."),
        OptionInfo("--disable-chir-useless-import-elimination", ID.DISABLE_CHIR_USELESS_IMPORT_ELIMINATION, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "--disable-chir-UIE", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable CHIR useless import elimination"),
        OptionInfo("--chir-ea", ID.CHIR_EA, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", optionValues("simple_on_off_mode"), Occurrence.SINGLE_OCCURRENCE, "escape analysis for CHIR. Candidate modes: "),
        OptionInfo("--fchir-constant-propagation", ID.CONST_PROPAGATION, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable constant propagation optimizaion in CHIR"),
        OptionInfo("--fno-chir-constant-propagation", ID.NO_CONST_PROPAGATION, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable constant propagation optimizaion in CHIR"),
        OptionInfo("--fchir-function-inlining", ID.FUNC_INLINING, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable function inlining optimizaion in CHIR"),
        OptionInfo("--fno-chir-function-inlining", ID.NO_FUNC_INLINING, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable function inlining optimizaion in CHIR"),
        OptionInfo("--fchir-devirtualization", ID.DEVIRTUALIZATION, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable devirtualization optimizaion in CHIR"),
        OptionInfo("--fno-chir-devirtualization", ID.NO_DEVIRTUALIZATION, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable devirtualization optimizaion in CHIR"),
        OptionInfo("--fchir-redundant-return-removal", ID.REDUANDANT_RETURN_REMOVAL, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable redundant return removal in CHIR"),
        OptionInfo("--fno-chir-redundant-return-removal", ID.NO_REDUANDANT_RETURN_REMOVAL, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable redundant return removal in CHIR"),
        OptionInfo("--fchir-redundant-future-removal", ID.REDUNDANT_FUTURE_REMOVAL, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable redundant future removal in CHIR"),
        OptionInfo("--fno-chir-redundant-future-removal", ID.NO_REDUNDANT_FUTURE_REMOVAL, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable redundant future removal in CHIR"),
        OptionInfo("--fchir-redundant-assign-removal", ID.REDUANDANT_ASSIGN_REMOVAL, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable redundant assign removal in CHIR"),
        OptionInfo("--fno-chir-redundant-assign-removal", ID.NO_REDUANDANT_ASSIGN_REMOVAL, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable redundant assign removal in CHIR"),
        OptionInfo("--fchir-loop-invariant-code-motion", ID.LOOP_INVARIANT_CODE_MOTION, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable loop invariant code motion in CHIR"),
        OptionInfo("--fno-chir-loop-invariant-code-motion", ID.NO_LOOP_INVARIANT_CODE_MOTION, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable loop invariant code motion in CHIR"),
        OptionInfo("--fchir-sroa", ID.SROA_OPT, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable scalar replacement of aggregates in CHIR"),
        OptionInfo("--fno-chir-sroa", ID.NO_SROA_OPT, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable scalar replacement of aggregates in CHIR"),
        OptionInfo("--fchir-switch-opt", ID.SWITCH_OPT, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable switch opt optimizaion in CHIR"),
        OptionInfo("--fchir-letc-folding", ID.LETC_FOLDING, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable letc folding optimizaion in CHIR"),
        OptionInfo("--fchir-ref-folding", ID.REF_FOLDING, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable ref folding optimizaion in CHIR"),
        OptionInfo("--fchir-array-lambda", ID.ARRAY_LAMBDA_OPT, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable array lambda optimizaion in CHIR"),
        OptionInfo("--sanitizer-coverage-inline-8bit-counters", ID.SANCOV_INLINE_8BIT, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable sanitizer-coverage-inline-8bit-counters in CHIR"),
        OptionInfo("--sanitizer-coverage-inline-bool-flag", ID.SANCOV_INLINE_BOOL_FLAG, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable sanitizer-coverage-inline-bool-flag in CHIR"),
        OptionInfo("--sanitizer-coverage-trace-pc-guard", ID.SANCOV_TRACE_PC_GUARD, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable sanitizer-coverage-trace-pc-guard in CHIR"),
        OptionInfo("--sanitizer-coverage-pc-table", ID.SANCOV_PC_TABLE, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable sanitizer-coverage-pc-table in CHIR"),
        OptionInfo("--sanitizer-coverage-stack-depth", ID.SANCOV_STACK_DEPTH, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable sanitizer-coverage-stack-depth in CHIR"),
        OptionInfo("--sanitizer-coverage-trace-compares", ID.SANCOV_TRACE_COMPARES, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable sanitizer-coverage-trace-compares in CHIR"),
        OptionInfo("--sanitizer-coverage-trace-memcmp", ID.SANCOV_TRACE_MEM_COMPARES, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable sanitizer-coverage-trace-memcmp in CHIR"),
        OptionInfo("--sanitizer-coverage-level=0", ID.SANCOV_LEVEL_0, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "sancov level 0"),
        OptionInfo("--sanitizer-coverage-level=1", ID.SANCOV_LEVEL_1, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "sancov level 1"),
        OptionInfo("--sanitizer-coverage-level=2", ID.SANCOV_LEVEL_2, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "sancov level 2"),
        OptionInfo("--sanitizer-coverage-level", ID.SANCOV_LEVEL_CUSTOM, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Set sanitizer-coverage level"),
        OptionInfo("--disable-sema-vic", ID.DISABLE_SEMA_VIC, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable variable initialization check in SEMA"),
        OptionInfo("--disable-chir-opt", ID.DISABLE_CHIR_OPT, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable optimizaion in CHIR"),
        OptionInfo("--disable-backend-opt", ID.DISABLE_BACKEND_OPT, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable optimizaion in Backend"),
        OptionInfo("--chir-opt-debug", ID.CHIR_OPT_DEBUG, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Debug optimizer"),
        OptionInfo("--render-chir", ID.RENDER_CHIR, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", optionValues("chir_mode"), Occurrence.SINGLE_OCCURRENCE, "Render CHIR as graph. Candidate modes: "),
        OptionInfo("--int-overflow", ID.INT_OVERFLOW_MODE, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", optionValues("integer_overflow_mode"), Occurrence.SINGLE_OCCURRENCE, "Specify default integer overflow strategy: "),
        OptionInfo("--fast-math", ID.FAST_MATH_MODE, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable fast-math mode"),
        OptionInfo("--opt-options", ID.OPT_OPTIONS, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Options directly passed to opt, put the value into \"\" when there is space in it"),
        OptionInfo("--llc-options", ID.LLC_OPTIONS, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Options directly passed to llc, put the value into \"\" when there is space in it"),
        OptionInfo("--link-option", ID.LINK_OPTION, Kind.SEPARATED, [Backend.ALL], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "An option directly passed to linker"),
        OptionInfo("--link-options", ID.LINK_OPTIONS, Kind.SEPARATED, [Backend.ALL], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Options directly passed to linker"),
        OptionInfo("--library-path", ID.LIBRARY_PATH, Kind.SEPARATED, [Backend.ALL], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "-L", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Add directory to library search path"),
        OptionInfo("--library", ID.LIBRARY, Kind.SEPARATED, [Backend.ALL], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "-l", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Link library"),
        OptionInfo("--set-runtime-rpath", ID.USE_RUNTIME_RPATH, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Add cangjie runtime directory to rpath"),
        OptionInfo("--toolchain", ID.TOOLCHAIN, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "-B", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Use toolchain binaries and object files at the given directory"),
        OptionInfo("--target", ID.TARGET, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Generate code for the given target platform"),
        OptionInfo("--target-cpu", ID.TARGET_CPU, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Generate instructions for the given target processor"),
        OptionInfo("--sysroot", ID.SYSROOT, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Set the system root directory under which bin, lib and include can be found"),
        OptionInfo("--output-type", ID.OUTPUT_TYPE, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", optionValues("output_type_list"), Occurrence.SINGLE_OCCURRENCE, "Specify output file type"),
        OptionInfo("--compile-target", ID.COMPILE_TARGET, Kind.SEPARATED, [Backend.ALL], [Group.DRIVER, Group.VISIBLE], "", optionValues("compile_target_list"), Occurrence.SINGLE_OCCURRENCE, "Specify compile target for obj"),
        OptionInfo("-O0", ID.OPTIMIZATION_0, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level 0 (default)"),
        OptionInfo("-O1", ID.OPTIMIZATION_1, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.VISIBLE, Group.STABLE], "-O", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level 1"),
        OptionInfo("-O2", ID.OPTIMIZATION_2, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level 2"),
        OptionInfo("-O3", ID.OPTIMIZATION_3, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level 3"),
        OptionInfo("-Os", ID.OPTIMIZATION_S, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level s, like -O2 with extra optimizations for size"),
        OptionInfo("-Oz", ID.OPTIMIZATION_Z, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level z, like -Os but reduces code size further"),
        OptionInfo("-O", ID.OPTIMIZATION_CUSTOM, Kind.CONTINOUS, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Set Optimization level"),
        OptionInfo("--opt-pass-options", ID.OPT_PASS_OPTIONS, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Set opt pass options"),
        OptionInfo("--module-name", ID.MODULE_NAME, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Tell compiler name of the module"),
        OptionInfo("--package", ID.PACKAGE_COMPILE, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "-p", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Specify package directory to be compiled"),
        OptionInfo("--import-path", ID.IMPORT_PATH, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Add .cjo search path"),
        OptionInfo("--plugin", ID.PLUGIN_PATH, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Specify the dynamic library path of compiler plugin"),
        OptionInfo("--common-part-cjo", ID.COMMON_PART_CJO, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Add .cjo file of package common part"),
        OptionInfo("--common-part-chir", ID.COMMON_PART_CHIR, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Add .chir file of package common part"),
        OptionInfo("--incremental-compile", ID.INCRE_COMPILE, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable incremental compilation."),
        OptionInfo("--incremental-debug", ID.INCRE_DEBUG, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Print debug message during incremental compilation."),
        OptionInfo("--save-temps", ID.SAVE_TEMPS, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Save intermediate compilation results. <value>: path to save temp files."),
        OptionInfo("--warn-off", ID.WARN_OFF, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "-Woff", optionValues("warn_group"), Occurrence.MULTIPLE_OCCURRENCE, "Suppress a specific group of warning"),
        OptionInfo("--warn-on", ID.WARN_ON, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "-Won", optionValues("warn_group"), Occurrence.MULTIPLE_OCCURRENCE, "Report a specific group of warning"),
        OptionInfo("--error-count-limit", ID.ERROR_COUNT_LIMIT, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Emit specified <number> of errors only. Available options: all, <number> (8 by default)"),
        OptionInfo("--verbose", ID.VERBOSE, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "-V", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable verbose"),
        OptionInfo("--version", ID.VERSION, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "-v", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Print compiler version information "),
        OptionInfo("--help", ID.HELP, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "-h", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Show usage"),
        OptionInfo("--compile-macro", ID.COMPILE_MACRO, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Options to compile the macro define package"),
        OptionInfo("--coverage", ID.ENABLE_COVERAGE, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable coverage"),
        OptionInfo("--experimental", ID.EXPERIMENTAL, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable experimental options"),
        OptionInfo("--debug-codegen", ID.DEBUG_CODEGEN, Kind.FLAG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Debug codeGen mode (execute the codeGen sub-tasks in series and dump debug-ir to file)"),
        OptionInfo("--jobs", ID.JOBS, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "-j", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Number of tasks to run at once"),
        OptionInfo("--aggressive-parallel-compile", ID.AGGRESSIVE_PARALLEL_COMPILE, Kind.FLAG_WITH_ARG, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "--apc", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Enable agrressive parallel compile and specify the number of tasks to run at once"),
        OptionInfo("--sanitize", ID.SANITIZE, Kind.SEPARATED, [Backend.CJNATIVE], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", optionValues("sanitizer_type"), Occurrence.SINGLE_OCCURRENCE, "Enable sanitizer: "),
        OptionInfo("--sanitize-set-rpath", ID.SANITIZE_SET_RPATH, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Add -rpath with cangjie runtime directory to linker flags for sanitizer-enabled product"),
        OptionInfo("--fobf-string", ID.OBF_STRING, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable string literal obfuscation"),
        OptionInfo("--fno-obf-string", ID.NO_OBF_STRING, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable string literal obfuscation"),
        OptionInfo("--fobf-const", ID.OBF_CONST, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable constant literal obfuscation"),
        OptionInfo("--fno-obf-const", ID.NO_OBF_CONST, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable constant literal obfuscation"),
        OptionInfo("--fobf-layout", ID.OBF_LAYOUT, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable code layout obfuscation"),
        OptionInfo("--fno-obf-layout", ID.NO_OBF_LAYOUT, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable code layout obfuscation"),
        OptionInfo("--fobf-cf-flatten", ID.OBF_CF_FLATTEN, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable control flow flatten obfuscation"),
        OptionInfo("--fno-obf-cf-flatten", ID.NO_OBF_CF_FLATTEN, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable control flow flatten obfuscation"),
        OptionInfo("--fobf-cf-bogus", ID.OBF_CF_BOGUS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable control flow bogus obfuscation"),
        OptionInfo("--fno-obf-cf-bogus", ID.NO_OBF_CF_BOGUS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable control flow bogus obfuscation"),
        OptionInfo("--fobf-all", ID.OBF_ALL, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable all obfuscations"),
        OptionInfo("--fobf-export-symbols", ID.OBF_EXPORT_SYMS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Obfuscate export symbols when layout obfuscation is enabled"),
        OptionInfo("--fno-obf-export-symbols", ID.NO_OBF_EXPORT_SYMS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Don't obfuscate export symbols when layout obfuscation is enabled"),
        OptionInfo("--obf-sym-input-mapping", ID.OBF_SYM_INPUT_MAPPING, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify the input files of symbol mapping for layout obfuscation"),
        OptionInfo("--obf-sym-output-mapping", ID.OBF_SYM_OUTPUT_MAPPING, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify the output file of symbol mapping for layout obfuscation"),
        OptionInfo("--obf-apply-mapping-file", ID.OBF_MAP_FILE, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Supply user-defined symbol mapping file for layout obfuscation"),
        OptionInfo("--obf-sym-prefix", ID.OBF_SYM_PREFIX, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify the prefix of obfuscated symbols for layout obfuscation"),
        OptionInfo("--fobf-source-path", ID.OBF_SOURCE_PATH, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Obfuscate source path of symbols when layout obfuscation is enabled"),
        OptionInfo("--fno-obf-source-path", ID.NO_OBF_SOURCE_PATH, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Don't obfuscate source path of symbols when layout obfuscation is enabled"),
        OptionInfo("--fobf-line-number", ID.OBF_LINE_NUMBER, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Obfuscate line number of symbols when layout obfuscation is enabled"),
        OptionInfo("--fno-obf-line-number", ID.NO_OBF_LINE_NUMBER, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Don't obfuscate line number of symbols when layout obfuscation is enabled"),
        OptionInfo("--obf-config", ID.OBF_CONFIG, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify obfuscation configure file"),
        OptionInfo("--obf-level", ID.OBF_LEVEL, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify obfuscation level. Available value: 1 to 9 (5 by default)"),
        OptionInfo("--obf-seed", ID.OBF_SEED, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify random seed for obfuscation algorithm. Available value: <number>"),
        OptionInfo("--interp-const-eval-debug", ID.INTERP_CONST_EVAL_DEBUG, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable debug logging in const evaluation"),
        OptionInfo("--print-bchir", ID.PRINT_BCHIR, Kind.SEPARATED, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", optionValues("bchir_print_mode"), Occurrence.MULTIPLE_OCCURRENCE, "Print BCHIR"),
        OptionInfo("--disable-codegen", ID.DISABLE_CODEGEN, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable code generation"),
        OptionInfo("--disable-reflection", ID.DISABLE_REFLECTION, Kind.FLAG, [Backend.ALL], [Group.GLOBAL, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable reflection"),
        OptionInfo("--stack-trace-format", ID.STACK_TRACE_FORMAT, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", optionValues("stack_trace_format"), Occurrence.SINGLE_OCCURRENCE, "Specify stack trace format"),
        OptionInfo("--ffunction-sections", ID.FUNC_SECTIONS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "enable function-sections"),
        OptionInfo("--fno-function-sections", ID.NO_FUNC_SECTIONS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "disable function-sections"),
        OptionInfo("--fdata-sections", ID.DATA_SECTIONS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "enable data-sections"),
        OptionInfo("--fno-data-sections", ID.NO_DATA_SECTIONS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "disable data-sections"),
        OptionInfo("--gc-sections", ID.GC_SECTIONS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "enable gc-sections"),
        OptionInfo("--no-gc-sections", ID.NO_GC_SECTIONS, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "disable gc-sections"),
        OptionInfo("--pgo-instr-gen", ID.PGO_INSTR_GEN, Kind.FLAG_WITH_ARG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "PGO instrumentation"),
        OptionInfo("--pgo-instr-use", ID.PGO_INSTR_USE, Kind.SEPARATED, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Read PGO instrumentation profile"),
        OptionInfo("--discard-eh-frame", ID.DISCARD_EH_FRAME, Kind.FLAG, [Backend.CJNATIVE], [Group.DRIVER, Group.STABLE, Group.VISIBLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Discard the eh_frame section"),
    ]
}
