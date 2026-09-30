package cjcj::mangle

import cjcj::ast.{FuncTy, FuncDecl}

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

    public override func MangleEntryFunction(funcDecl: FuncDecl): Option<String> {
        if (enableCompileTest && funcDecl.identifier.Val() == TEST_ENTRY_NAME) {
            return USER_MAIN_MANGLED_NAME
        }
        if (!enableCompileTest && funcDecl.identifier.Val() == MAIN_INVOKE && funcDecl.IsStaticOrGlobal()) {
            return USER_MAIN_MANGLED_NAME
        }
        return None
    }

    public func MangleCFuncSignature(cFuncTy: FuncTy): String {
        var mangled = MangleSemaType(cFuncTy.retTy)
        for (paramTy in cFuncTy.paramTys) {
            mangled += MangleSemaType(paramTy)
        }
        return mangled
    }
}
