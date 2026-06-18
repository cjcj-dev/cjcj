package cangjie_compiler::chir

public func CHIR2BCHIRTranslateValue(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, value: Value): Unit {
    if (value.IsParameter() || value.IsLocalVar()) {
        BCHIRPushOpWithName(context.definition, OpCode.LVAR, BCHIRMangledName(value))
        context.definition.PushCell(compiler.LVarId(context, value))
    } else if (let Some(function) <- value.AsFunction()) {
        BCHIRPushOpWithName(context.definition, OpCode.FUNC, BCHIRMangledName(function))
        context.definition.PushCell(0)
    } else if (let Some(globalVar) <- value.AsGlobalVar()) {
        BCHIRPushOpWithName(context.definition, OpCode.GVAR, BCHIRMangledName(globalVar))
        context.definition.PushCell(0)
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}
