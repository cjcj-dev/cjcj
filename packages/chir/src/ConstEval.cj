package cangjie_compiler::chir

import std.collection.*

public class ConstEvalPass {
    public init() {}

    public static func HasConstGlobalVarInitFuncs(pkg: Package): Bool {
        for (fn in pkg.GetGlobalFuncsWithBody(includeSrcCodeImported: false)) {
            if (fn.IsGVInit() && fn.IsCompileTimeValue()) {
                return true
            }
        }
        return false
    }

    public func RunOnPackage(pkg: Package): Unit {
        let initFuncsForConstVar = CollectConstGlobalVarInitFuncs(pkg)
        if (initFuncsForConstVar.isEmpty()) {
            return
        }
        RunInterpreter(pkg, initFuncsForConstVar)
    }

    private func RunInterpreter(pkg: Package, initFuncsForConstVar: ArrayList<Function>): Unit {
        let bchirPackages = ArrayList<BCHIR>()
        let packageBchir = BCHIR()
        CHIR2BCHIR.CompilePackage(pkg, packageBchir, forConstEval: true)
        for (fn in initFuncsForConstVar) {
            packageBchir.initFuncsForConsts.add(BCHIRMangledName(fn))
        }
        bchirPackages.add(packageBchir)

        let linker = BCHIRLinker()
        let globalInitValues = linker.RunForConstEval(bchirPackages)
        let linkedBchir = linker.GetLinkedBCHIR()
        let fePlayground = linkedBchir.GetLinkedByteCode().Size()
        let extraReqSpace = BCHIRInterpreter.INTERNAL_PLAYGROUND_SIZE + BCHIRInterpreter.EXTERNAL_PLAYGROUND_SIZE
        linkedBchir.Resize(fePlayground + extraReqSpace)

        let interpreter = BCHIRInterpreter(linkedBchir)
        interpreter.SetGlobalVars(globalInitValues)
        let result = interpreter.Run(baseIndex: 0, expectsReturn: false)
        if (result.kind == BCHIRResultKind.TRAP || result.kind == BCHIRResultKind.UNSUPPORTED) {
            let message = if (result.message.isEmpty()) { "no message" } else { result.message }
            throw IllegalStateException("ConstEvalPass interpreter failed: " + message)
        }
    }

    private func CollectConstGlobalVarInitFuncs(pkg: Package): ArrayList<Function> {
        let funcs = ArrayList<Function>()
        for (fn in pkg.GetGlobalFuncsWithBody(includeSrcCodeImported: false)) {
            if (fn.IsGVInit() && fn.IsCompileTimeValue()) {
                funcs.add(fn)
            }
        }
        return funcs
    }
}
