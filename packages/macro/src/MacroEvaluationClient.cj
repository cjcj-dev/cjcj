package cjcj::macro_pkg

import cjcj::basic.{DiagSeverityIndex, Errorln}
import std.collection.*

private func IsResultForMacCall(id: String, pos: Position, mi: MacroInvocation): Bool {
    if (id != mi.macroCallDiagInfo.identifier) {
        return false
    }
    if (pos != mi.macroCallDiagInfo.identifierPos) {
        return false
    }
    if (pos.fileID != mi.macroCallDiagInfo.identifierPos.fileID) {
        return false
    }
    return true
}

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
    let resBuf = ArrayList<ArrayList<UInt8>>()
    if (!MacroProcMsger.GetInstance().ReadAllMsgFromSrv(resBuf)) {
        call.status = MacroEvalStatus.FAIL
        return
    }
    if (resBuf.size != 1) {
        call.status = MacroEvalStatus.FAIL
        return
    }
    let result = resBuf[0]
    let invocation = call.RequireInvocation()
    let id = Box<String>("")
    let pos = Box<Position>(INVALID_POSITION)
    MacroEvalMsgSerializer.DeSerializeIdInfoFromResult(id, pos, result)
    if (!IsResultForMacCall(id.value, pos.value, invocation)) {
        call.status = MacroEvalStatus.FAIL
        return
    }
    MacroEvalMsgSerializer.DeSerializeTksFromResult(invocation.newTokens, result)
    call.status = MacroEvalMsgSerializer.DeSerializeStatusFromResult(result)
    MacroEvalMsgSerializer.DeSerializeItemsFromResult(call.items, result)
    MacroEvalMsgSerializer.DeSerializeAssertParentsFromResult(call.assertParents, result)
    let diags = ArrayList<Diagnostic>()
    MacroEvalMsgSerializer.DeSerializeDiagsFromResult(diags, result)
    for (diag in diags) {
        call.DiagReport(DiagSeverityIndex(diag.diagSeverity), MakeRange(diag.start, diag.end),
            diag.errorMessage, diag.mainHint.str)
    }
    call.isDataReady = true
    for (parentName in call.assertParents) {
        call.ci.getOrThrow().GetDiag().Diagnose(call.GetBeginPos(), DiagKind.macro_assert_parent_context_failed,
            args: [DiagArgument(call.GetFullName()), DiagArgument(parentName)]).Emit()
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
        var foundEvalmc = false
        for (call in calls) {
            if (!call.isDataReady) {
                foundEvalmc = true
                break
            }
        }
        if (!foundEvalmc) {
            return true
        }
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
            var findFlag = false
            for (call in calls) {
                let invocation = call.RequireInvocation()
                if (!IsResultForMacCall(id.value, pos.value, invocation)) {
                    continue
                }
                findFlag = true
                MacroEvalMsgSerializer.DeSerializeTksFromResult(invocation.newTokens, msg)
                call.status = MacroEvalMsgSerializer.DeSerializeStatusFromResult(msg)
                MacroEvalMsgSerializer.DeSerializeItemsFromResult(call.items, msg)
                MacroEvalMsgSerializer.DeSerializeAssertParentsFromResult(call.assertParents, msg)
                let diags = ArrayList<Diagnostic>()
                MacroEvalMsgSerializer.DeSerializeDiagsFromResult(diags, msg)
                for (diag in diags) {
                    call.DiagReport(DiagSeverityIndex(diag.diagSeverity), MakeRange(diag.start, diag.end),
                        diag.errorMessage, diag.mainHint.str)
                }
                call.isDataReady = true
                for (parentName in call.assertParents) {
                    ci.GetDiag().Diagnose(call.GetBeginPos(), DiagKind.macro_assert_parent_context_failed,
                        args: [DiagArgument(call.GetFullName()), DiagArgument(parentName)]).Emit()
                }
                break
            }
            if (!findFlag) {
                Errorln("DeserializeMacroCallsResult not find macCall for result " + id.value + pos.value.ToString())
            }
        }
    }
}
