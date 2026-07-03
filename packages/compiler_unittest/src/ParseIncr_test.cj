package cangjie_compiler::compiler_unittest

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cangjie_compiler::ast.*
import cangjie_compiler::frontend.*
import cangjie_compiler::option.{ArchType, OSType, OutputMode}

private let projectPath: String = ".."
private let definePath: String = ""

private let CODE_OF_FILE1: String = #"
    package test
    public class Test1 {
    }
    "#

private let NEW_CODE_OF_FILE1: String = #"
    package test
    public class NewTest1 {
    }
    "#

private let CODE_OF_FILE2: String = #"
    package test
    public class Test2 {
    }
    "#

private type CountSymbolsFunc = (Node) -> VisitAction

private func SetUp(invocation: CompilerInvocation): Unit {
    @When[arch == "x86_64"]
    let targetArch = ArchType.X86_64
    @When[arch != "x86_64"]
    let targetArch = ArchType.AARCH64
    @When[os == "Windows"]
    let targetOS = OSType.WINDOWS
    @When[os == "Windows"]
    let executablePath = projectPath + "\\output\\bin\\"
    @When[os != "Windows"]
    let targetOS = OSType.LINUX
    @When[os != "Windows"]
    let executablePath = projectPath + "/output/bin/"
    invocation.globalOptions.target.arch = targetArch
    invocation.globalOptions.target.os = targetOS
    invocation.globalOptions.executablePath = executablePath
    invocation.globalOptions.importPaths.clear()
    invocation.globalOptions.importPaths.add(definePath)
}

private func ResetCount(
    macthTest1Count: ArrayList<Int64>,
    macthTest2Count: ArrayList<Int64>,
    macthNewTest1Count: ArrayList<Int64>
): Unit {
    macthTest1Count[0] = 0
    macthTest2Count[0] = 0
    macthNewTest1Count[0] = 0
}

private func CreateCountSymbolsLambda(
    macthTest1Count: ArrayList<Int64>,
    macthTest2Count: ArrayList<Int64>,
    macthNewTest1Count: ArrayList<Int64>
): CountSymbolsFunc {
    return { curNode: Node =>
        if (let Some(decl) <- (curNode as ClassDecl)) {
            let name = decl.identifier.Val()
            if (name == "Test1") {
                macthTest1Count[0]++
            } else if (name == "Test2") {
                macthTest2Count[0]++
            } else if (name == "NewTest1") {
                macthNewTest1Count[0]++
            }
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    }
}

private func WalkAndVerifyCounts(
    instance: CompilerInstance,
    countSymbols: CountSymbolsFunc,
    macthTest1Count: ArrayList<Int64>,
    macthTest2Count: ArrayList<Int64>,
    macthNewTest1Count: ArrayList<Int64>,
    expectedTest1: Int64,
    expectedTest2: Int64,
    expectedNewTest1: Int64
): Unit {
    Walker(instance.GetSourcePackages()[0], visitPre: countSymbols).Walk()
    @Expect(macthTest1Count[0], expectedTest1)
    @Expect(macthTest2Count[0], expectedTest2)
    @Expect(macthNewTest1Count[0], expectedNewTest1)
}

private func SetBufferCacheAndParse(
    instance: CompilerInstance,
    cache: Array<(String, SrcCodeCacheInfo)>
): Bool {
    instance.bufferCache.clear()
    for (entry in cache) {
        instance.bufferCache.add(entry[0], entry[1])
    }
    return instance.PerformParse()
}

private func TestInitialParse(
    instance: CompilerInstance,
    countSymbols: CountSymbolsFunc,
    macthTest1Count: ArrayList<Int64>,
    macthTest2Count: ArrayList<Int64>,
    macthNewTest1Count: ArrayList<Int64>
): Unit {
    let parseRes = instance.PerformParse()
    @Expect(parseRes, true)
    WalkAndVerifyCounts(instance, countSymbols, macthTest1Count, macthTest2Count, macthNewTest1Count, 1, 1, 0)
}

private func TestChangedParse(
    instance: CompilerInstance,
    newCodeOfFile1: String,
    codeOfFile2: String,
    countSymbols: CountSymbolsFunc,
    macthTest1Count: ArrayList<Int64>,
    macthTest2Count: ArrayList<Int64>,
    macthNewTest1Count: ArrayList<Int64>
): Unit {
    let parseRes = SetBufferCacheAndParse(instance, [
        ("File1.cj", SrcCodeCacheInfo(SrcCodeChangeState.CHANGED, newCodeOfFile1)),
        ("File2.cj", SrcCodeCacheInfo(SrcCodeChangeState.UNCHANGED, codeOfFile2))
    ])
    @Expect(parseRes, true)
    ResetCount(macthTest1Count, macthTest2Count, macthNewTest1Count)
    WalkAndVerifyCounts(instance, countSymbols, macthTest1Count, macthTest2Count, macthNewTest1Count, 0, 1, 1)
}

private func TestDeletedParse(
    instance: CompilerInstance,
    codeOfFile2: String,
    countSymbols: CountSymbolsFunc,
    macthTest1Count: ArrayList<Int64>,
    macthTest2Count: ArrayList<Int64>,
    macthNewTest1Count: ArrayList<Int64>
): Unit {
    let parseRes = SetBufferCacheAndParse(instance, [
        ("File1.cj", SrcCodeCacheInfo(SrcCodeChangeState.DELETED, "")),
        ("File2.cj", SrcCodeCacheInfo(SrcCodeChangeState.UNCHANGED, codeOfFile2))
    ])
    @Expect(parseRes, true)
    ResetCount(macthTest1Count, macthTest2Count, macthNewTest1Count)
    WalkAndVerifyCounts(instance, countSymbols, macthTest1Count, macthTest2Count, macthNewTest1Count, 0, 1, 0)
}

private func TestReAddedParse(
    instance: CompilerInstance,
    codeOfFile1: String,
    codeOfFile2: String,
    countSymbols: CountSymbolsFunc,
    macthTest1Count: ArrayList<Int64>,
    macthTest2Count: ArrayList<Int64>,
    macthNewTest1Count: ArrayList<Int64>
): Unit {
    let parseRes = SetBufferCacheAndParse(instance, [
        ("File1.cj", SrcCodeCacheInfo(SrcCodeChangeState.ADDED, codeOfFile1)),
        ("File2.cj", SrcCodeCacheInfo(SrcCodeChangeState.UNCHANGED, codeOfFile2))
    ])
    @Expect(parseRes, true)
    ResetCount(macthTest1Count, macthTest2Count, macthNewTest1Count)
    WalkAndVerifyCounts(instance, countSymbols, macthTest1Count, macthTest2Count, macthNewTest1Count, 1, 1, 0)
}

@Test
public class ParseIncrTest {
    @TestCase
    public func ParseIncrTest(): Unit {
        let invocation = CompilerInvocation()
        SetUp(invocation)
        let diag = DiagnosticEngine()
        let instance = CompilerInstance(invocation, diag)
        instance.bufferCache.add("File1.cj", SrcCodeCacheInfo(SrcCodeChangeState.ADDED, CODE_OF_FILE1))
        instance.bufferCache.add("File2.cj", SrcCodeCacheInfo(SrcCodeChangeState.ADDED, CODE_OF_FILE2))
        invocation.globalOptions.outputMode = OutputMode.STATIC_LIB
        instance.loadSrcFilesFromCache = true
        let macthTest1Count = ArrayList<Int64>()
        let macthTest2Count = ArrayList<Int64>()
        let macthNewTest1Count = ArrayList<Int64>()
        macthTest1Count.add(0)
        macthTest2Count.add(0)
        macthNewTest1Count.add(0)
        let countSymbols = CreateCountSymbolsLambda(macthTest1Count, macthTest2Count, macthNewTest1Count)
        TestInitialParse(instance, countSymbols, macthTest1Count, macthTest2Count, macthNewTest1Count)
        TestChangedParse(instance, NEW_CODE_OF_FILE1, CODE_OF_FILE2, countSymbols,
            macthTest1Count, macthTest2Count, macthNewTest1Count)
        TestDeletedParse(instance, CODE_OF_FILE2, countSymbols,
            macthTest1Count, macthTest2Count, macthNewTest1Count)
        TestReAddedParse(instance, CODE_OF_FILE1, CODE_OF_FILE2, countSymbols,
            macthTest1Count, macthTest2Count, macthNewTest1Count)
    }
}
