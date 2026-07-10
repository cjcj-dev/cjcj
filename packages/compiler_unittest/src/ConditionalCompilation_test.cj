package cjcj::compiler_unittest

import cjcj::frontend.*
import std.unittest.*
import std.unittest.testmacro.*

private let CONDITIONAL_COMPILATION_PROJECT_PATH: String = "/root/cj_build/cangjie_compiler"

@When[os == "Windows"]
private let CONDITIONAL_COMPILATION_SRC_PATH: String =
    CONDITIONAL_COMPILATION_PROJECT_PATH + "\\unittests\\ConditionalCompilation\\srcFiles\\"

@When[os != "Windows"]
private let CONDITIONAL_COMPILATION_SRC_PATH: String =
    CONDITIONAL_COMPILATION_PROJECT_PATH + "/unittests/ConditionalCompilation/srcFiles/"

@When[os == "Windows"]
@Test
class ConditionalCompilationTest {
    @TestCase
    func for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
    }

    @TestCase
    func passedCondition_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.passedWhenKeyValue.add("test1", "abc")
        invocation.globalOptions.passedWhenKeyValue.add("test2", "aaa")
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
    }

    @TestCase
    func passedCondition_cfgFile_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.passedWhenCfgPaths.add(CONDITIONAL_COMPILATION_SRC_PATH)
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
    }

    @TestCase
    func packagePaths_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.packagePaths.add(CONDITIONAL_COMPILATION_SRC_PATH)
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
    }

    @TestCase
    func invalid_condition_value_after_short_circuit(): Unit {
        let result = CompileSource(##"@When[debug || os == "${x}"]
func foo() {}
"##, stage: CompileStage.PARSE)
        result.instance.invocation.globalOptions.enableCompileDebug = true
        let _ = result.instance.PerformConditionCompile()
        @Expect(result.diag.GetErrorCount(), 1u64)
    }
}

@When[os != "Windows"]
@Test
class ConditionalCompilationTest {
    @TestCase
    func for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
    }

    @TestCase
    func passedCondition_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.passedWhenKeyValue.add("test1", "abc")
        invocation.globalOptions.passedWhenKeyValue.add("test2", "aaa")
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
    }

    @TestCase
    func passedCondition_cfgFile_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.passedWhenCfgPaths.add(CONDITIONAL_COMPILATION_SRC_PATH)
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
    }

    @TestCase
    func packagePaths_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.packagePaths.add(CONDITIONAL_COMPILATION_SRC_PATH)
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
    }

    @TestCase
    func invalid_condition_value_after_short_circuit(): Unit {
        let result = CompileSource(##"@When[debug || os == "${x}"]
func foo() {}
"##, stage: CompileStage.PARSE)
        result.instance.invocation.globalOptions.enableCompileDebug = true
        let _ = result.instance.PerformConditionCompile()
        @Expect(result.diag.GetErrorCount(), 1u64)
    }

    @TestCase
    func cfgPaths_no_file_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.passedWhenCfgPaths.add("srcPath")
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
        @Expect(diag.GetWarningCount(), 1u64)
    }

    @TestCase
    func same_with_builtin_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.passedWhenCfgPaths.add("srcPath")
        invocation.globalOptions.passedWhenKeyValue.add("os", "aaa")
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
        @Expect(diag.GetErrorCount(), 1u64)
    }

    @TestCase
    func cfg_path_ignored_for_lsp(): Unit {
        let src = CONDITIONAL_COMPILATION_SRC_PATH + "os.cj"
        let diag = DiagnosticEngine()
        let invocation = CompilerInvocation()
        let instance = CompilerInstance(invocation, diag)
        instance.compileOnePackageFromSrcFiles = true
        invocation.globalOptions.enableMacroInLSP = true
        invocation.globalOptions.passedWhenCfgPaths.add("srcPath")
        invocation.globalOptions.passedWhenKeyValue.add("test1", "abc")
        invocation.globalOptions.passedWhenKeyValue.add("test2", "aaa")
        instance.srcFilePaths.add(src)
        let _ = instance.Compile(stage: CompileStage.PARSE)
        let _ = instance.PerformConditionCompile()
        @Expect(diag.GetWarningCount(), 1u64)
    }
}
