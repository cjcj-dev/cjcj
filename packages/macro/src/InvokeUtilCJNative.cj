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
                let method = GetMethodPointer(handle, methodName)
                if (!method.isNull()) {
                    invokeFuncName = methodName
                    invokeFunc = method
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
        let method = GetMethodPointer(handle, methodName)
        if (!method.isNull()) {
            SetOpenedLibHandles(handle)
            invokeFuncName = methodName
            invokeFunc = method
            return true
        }
        return false
    }
}
