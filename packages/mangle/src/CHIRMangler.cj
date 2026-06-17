package cangjie_compiler::mangle

import cangjie_compiler::ast.FuncTy

public class CHIRMangler <: BaseMangler {
    private var enableCompileTest: Bool

    public init(compileTest: Bool) {
        super()
        enableCompileTest = compileTest
    }

    public init(delimiter: String, compileTest: Bool) {
        super(delimiter)
        enableCompileTest = compileTest
    }

    public override func MangleEntryFunction(funcDecl: MangleDecl): Option<String> {
        if (enableCompileTest && funcDecl.identifier == TEST_ENTRY_NAME) {
            return USER_MAIN_MANGLED_NAME
        }
        if (!enableCompileTest && funcDecl.identifier == MAIN_INVOKE && funcDecl.IsStaticOrGlobal()) {
            return USER_MAIN_MANGLED_NAME
        }
        return None
    }

    public func MangleCFuncSignature(cFuncTy: MangleType): String {
        var mangled = if (let Some(ret) <- cFuncTy.retTy) { MangleSemaType(ret) } else { MANGLE_VOID_TY_SUFFIX }
        for (paramTy in cFuncTy.paramTys) {
            mangled += MangleSemaType(paramTy)
        }
        return mangled
    }

    public func MangleCFuncSignature(cFuncTy: FuncTy): String {
        var mangled = MangleAstSemanticType(cFuncTy.retTy)
        for (paramTy in cFuncTy.paramTys) {
            mangled += MangleAstSemanticType(paramTy)
        }
        return mangled
    }
}
