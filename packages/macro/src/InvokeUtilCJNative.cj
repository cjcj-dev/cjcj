package cangjie_compiler::macro_pkg

extend MacroCall {
    public func FindMacroDefMethod(): Bool {
        if (IsBuiltInMacro(GetFullName())) {
            return true
        }
        if (methodName.isEmpty()) {
            return false
        }
        if (libPath.isEmpty()) {
            for (handle in GetOpenedLibHandles()) {
                if (GetMethod(handle, methodName).isSome()) {
                    invokeFuncName = methodName
                    return true
                }
            }
            return false
        }
        let handle = OpenSymbolTable(libPath)
        if (!handle.opened) {
            status = MacroEvalStatus.FAIL
            return false
        }
        if (GetMethod(handle, methodName).isSome()) {
            SetOpenedLibHandles(handle)
            invokeFuncName = methodName
            return true
        }
        return false
    }
}
