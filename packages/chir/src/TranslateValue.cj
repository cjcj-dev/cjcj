package cjcj::chir

public func TranslateValue(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, value: Value): Unit {
    if (value.IsParameter()) {
        BCHIRPushOpWithName(context.definition, OpCode.LVAR, BCHIRMangledName(value))
        context.definition.PushCell(compiler.LVarId(context, value))
    } else if (value.IsLocalVar()) {
        BCHIRPushOpWithName(context.definition, OpCode.LVAR, BCHIRMangledName(value))
        context.definition.PushCell(compiler.LVarId(context, value))
    } else if (value.IsImportedFunc() && value.GetAttributeInfo().Test(Attribute.FOREIGN)) {
        context.definition.PushOp(OpCode.NULLPTR)
    } else if (value.IsFuncWithBody()) {
        BCHIRPushOpWithName(context.definition, OpCode.FUNC, BCHIRMangledName(value))
        context.definition.PushCell(0xffffffff)
    } else if (value.IsGlobalVar() || value.IsImportedFunc()) {
        let mangledName = value.GetIdentifierWithoutPrefix()
        if (mangledName == "$has_applied_pkg_init_func") {
            let opIndex = context.definition.NextIndex()
            context.definition.PushOp(OpCode.GVAR)
            context.definition.PushCell(0)
            context.definition.AddMangledNameAnnotation(opIndex, "$has_applied_pkg_init_func-" + compiler.bchir.packageName)
        } else {
            BCHIRPushOpWithName(context.definition, OpCode.GVAR, mangledName)
            context.definition.PushCell(0)
        }
    } else {
        throw IllegalStateException("CHIR2BCHIR::TranslateValue")
    }
}
