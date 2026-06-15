package cangjie_compiler::macro_pkg

import std.collection.*

public enum MacroSrvTaskType {
    | FIND_MACRO_DEFLIB
    | EVAL_MACRO_CALL
    | EXIT_MACRO_SRV
    | EXIT_MACRO_STG
}

public func GetMacroTaskType(msg: ArrayList<UInt8>): MacroSrvTaskType {
    let content = MacroEvalMsgSerializer.GetMacroMsgContenType(msg)
    if (content == MacroMsgContent.DEF_LIB) {
        return MacroSrvTaskType.FIND_MACRO_DEFLIB
    }
    if (content == MacroMsgContent.MULTI_CALLS) {
        return MacroSrvTaskType.EVAL_MACRO_CALL
    }
    if (content == MacroMsgContent.EXIT_TASK) {
        return MacroSrvTaskType.EXIT_MACRO_STG
    }
    return MacroSrvTaskType.EXIT_MACRO_SRV
}

extend MacroEvaluation {
    public func RunMacroSrv(): Unit {
        ExecuteEvalSrvTask()
        RuntimeInit.GetInstance().CloseRuntime()
    }

    public func ExecMacroSrv(pid: Int64): Unit {
        let _ = pid
        RunMacroSrv()
    }

    public func FindDef(msg: ArrayList<UInt8>): Bool {
        let macroLibs = ArrayList<String>()
        MacroEvalMsgSerializer.DeSerializeDeflibMsg(macroLibs, msg)
        for (lib in macroLibs) {
            let handle = OpenSymbolTable(lib)
            if (!handle.opened) {
                let res = ArrayList<UInt8>()
                for (byte in ("RespondFindDef " + lib).toArray()) {
                    res.add(byte)
                }
                let _ = MacroProcMsger.GetInstance().SendMsgToClient(res)
                return false
            }
        }
        let ok = ArrayList<UInt8>()
        for (byte in "RespondFindDef ".toArray()) {
            ok.add(byte)
        }
        return MacroProcMsger.GetInstance().SendMsgToClient(ok)
    }

    public func SerializeAndNotifyResult(macCall: MacroCall): Bool {
        if (MacroExpandFailed(macCall.RequireInvocation().newTokens)) {
            macCall.status = MacroEvalStatus.FAIL
        }
        let result = ArrayList<UInt8>()
        if (!MacroEvalMsgSerializer().SerializeMacroCallResultMsg(macCall, result)) {
            return false
        }
        return MacroProcMsger.GetInstance().SendMsgToClient(result)
    }

    public func EvalMacroCallsAndWaitResult(): Bool {
        return true
    }

    public func CreateMacroExpandFromMessage(text: String): MacroExpandDecl {
        let decl = MacroExpandDecl()
        let id = Box<String>("")
        let pos = Box<Position>(INVALID_POSITION)
        MacroEvalMsgSerializer.DeSerializeIdInfoFromCall(id, pos, text)
        decl.identifier = id.value
        decl.invocation.macroCallDiagInfo.identifier = id.value
        decl.invocation.macroCallDiagInfo.fullName = id.value
        decl.invocation.macroCallDiagInfo.identifierPos = pos.value
        MacroEvalMsgSerializer.DeSerializeArgsFromCall(decl.invocation.args, text)
        MacroEvalMsgSerializer.DeSerializeAttrsFromCall(decl.invocation.attrs, text)
        return decl
    }

    public func DeSerializeMacroCall(text: String): MacroCall {
        let decl = CreateMacroExpandFromMessage(text)
        let call = MacroCall(decl)
        MacroEvalMsgSerializer.DeSerializeParentNamesFromCall(call.parentNames, text)
        call.ci = Some(CompilerInstance())
        return call
    }

    public func EvalMacroCall(msg: ArrayList<UInt8>): Bool {
        let _ = msg
        return false
    }

    public func ResetForNextEval(): Unit {
        RuntimeInit.GetInstance().CloseRuntime()
    }
}
