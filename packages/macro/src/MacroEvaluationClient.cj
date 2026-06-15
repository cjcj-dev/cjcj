package cangjie_compiler::macro_pkg

import std.collection.*

public func SendMacroDefTaskToServer(macroLibs: ArrayList<String>): Bool {
    let msg = ArrayList<UInt8>()
    MacroEvalMsgSerializer().SerializeDeflibMsg(macroLibs, msg)
    return MacroProcMsger.GetInstance().SendMsgToSrv(msg)
}

public func SendExitStgTaskToServer(): Unit {
    let msg = ArrayList<UInt8>()
    MacroEvalMsgSerializer().SerializeExitMsg(msg, flag: false)
    let _ = MacroProcMsger.GetInstance().SendMsgToSrv(msg)
}

public func WaitMacroDefResultFromServer(): Unit {
    let msg = ArrayList<UInt8>()
    let _ = MacroProcMsger.GetInstance().ReadMsgFromSrv(msg)
}

public func SendMacroCallTaskToServer(call: MacroCall): Bool {
    let msg = ArrayList<UInt8>()
    MacroEvalMsgSerializer().SerializeMacroCallMsg(call, msg)
    if (!MacroProcMsger.GetInstance().SendMsgToSrv(msg)) {
        call.status = MacroEvalStatus.FAIL
        return false
    }
    return true
}

public func WaitMacroCallEvalResultFromServer(call: MacroCall): Unit {
    let result = ArrayList<UInt8>()
    let invocation = call.RequireInvocation()
    if (MacroProcMsger.GetInstance().ReadMsgFromSrv(result)) {
        let id = Box<String>("")
        let pos = Box<Position>(INVALID_POSITION)
        MacroEvalMsgSerializer.DeSerializeIdInfoFromResult(id, pos, result)
        if (id.value == invocation.macroCallDiagInfo.identifier &&
            pos.value == invocation.macroCallDiagInfo.identifierPos) {
            invocation.newTokens.clear()
            MacroEvalMsgSerializer.DeSerializeTksFromResult(invocation.newTokens, result)
            call.status = MacroEvalMsgSerializer.DeSerializeStatusFromResult(result)
            MacroEvalMsgSerializer.DeSerializeItemsFromResult(call.items, result)
            MacroEvalMsgSerializer.DeSerializeAssertParentsFromResult(call.assertParents, result)
            call.isDataReady = true
            return
        }
    }
    if (!invocation.newTokens.isEmpty()) {
        call.status = MacroEvalStatus.SUCCESS
        call.isDataReady = true
    } else {
        invocation.newTokens.add(Token(TokenKind.ILLEGAL, ""))
        call.status = MacroEvalStatus.FAIL
        call.isDataReady = true
    }
}

extend MacroEvaluation {
    public func SendMacroDefTask(macroLibs: ArrayList<String>): Bool {
        return SendMacroDefTaskToServer(macroLibs)
    }

    public func SendExitStgTask(): Unit {
        SendExitStgTaskToServer()
    }

    public func WaitMacroDefResult(): Unit {
        WaitMacroDefResultFromServer()
    }

    public func SendMacroCallTask(call: MacroCall): Bool {
        return SendMacroCallTaskToServer(call)
    }

    public func WaitMacroCallEvalResult(call: MacroCall): Unit {
        WaitMacroCallEvalResultFromServer(call)
    }

    public func SendMacroCallsTask(calls: ArrayList<MacroCall>): Bool {
        let needSendCalls = ArrayList<MacroCall>()
        for (call in calls) {
            if (!call.hasSend) {
                needSendCalls.add(call)
                call.hasSend = true
            }
        }
        let msg = ArrayList<UInt8>()
        MacroEvalMsgSerializer().SerializeMultiCallsMsg(needSendCalls, msg)
        if (!MacroProcMsger.GetInstance().SendMsgToSrv(msg)) {
            for (call in calls) {
                call.status = MacroEvalStatus.FAIL
            }
            return false
        }
        return true
    }

    public func WaitMacroCallsEvalResult(calls: ArrayList<MacroCall>): Bool {
        let msgList = ArrayList<ArrayList<UInt8>>()
        if (!MacroProcMsger.GetInstance().ReadAllMsgFromSrv(msgList)) {
            for (call in calls) {
                call.status = MacroEvalStatus.FAIL
            }
            return false
        }
        DeserializeMacroCallsResult(calls, msgList)
        return true
    }

    public func DeserializeMacroCallsResult(calls: ArrayList<MacroCall>, msgList: ArrayList<ArrayList<UInt8>>): Unit {
        for (msg in msgList) {
            let id = Box<String>("")
            let pos = Box<Position>(INVALID_POSITION)
            MacroEvalMsgSerializer.DeSerializeIdInfoFromResult(id, pos, msg)
            for (call in calls) {
                let invocation = call.RequireInvocation()
                if (id.value == invocation.macroCallDiagInfo.identifier &&
                    pos.value == invocation.macroCallDiagInfo.identifierPos) {
                    invocation.newTokens.clear()
                    MacroEvalMsgSerializer.DeSerializeTksFromResult(invocation.newTokens, msg)
                    call.status = MacroEvalMsgSerializer.DeSerializeStatusFromResult(msg)
                    MacroEvalMsgSerializer.DeSerializeItemsFromResult(call.items, msg)
                    MacroEvalMsgSerializer.DeSerializeAssertParentsFromResult(call.assertParents, msg)
                    call.isDataReady = true
                    break
                }
            }
        }
    }
}
