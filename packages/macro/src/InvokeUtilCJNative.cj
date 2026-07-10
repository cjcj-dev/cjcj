package cjcj::macro_pkg

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
            if (let Some(instance) <- ci) {
                instance.GetDiag().Diagnose(DiagKind.can_not_open_macro_library,
                    args: [DiagArgument(libPath)]).Emit()
            }
            return false
        }
        let method = GetMethodPointer(handle, methodName)
        SetOpenedLibHandles(handle)
        if (!method.isNull()) {
            invokeFuncName = methodName
            invokeFunc = method
            return true
        }
        return false
    }
}
