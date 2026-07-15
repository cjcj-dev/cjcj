package cjcj::macro_pkg

import cjcj::basic.Errorln
import cjcj::utils.FileUtil
import std.collection.*

@When[os == "Linux"]
private let PR_SET_NAME: Int32 = 15

@When[os != "Windows"]
foreign {
    func exit(status: Int32): Unit
}

@When[os == "Linux"]
private func RenameSrvProcess(): Unit {
    var subName = "msrv" + unsafe { getpid() }.toString()
    let maxProcNameSize: Int64 = 15
    if (subName.size > maxProcNameSize) {
        subName = subName[0..maxProcNameSize]
    }
    try (name = unsafe { LibC.mallocCString(subName) }.asResource()) {
        if (unsafe { prctl(PR_SET_NAME, name.value) } == -1) {
            Errorln("Rename macro srv to " + subName + " fail")
            return
        }
    }
}

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
        if (MacroEvalMsgSerializer.GetExitFlag(msg)) {
            return MacroSrvTaskType.EXIT_MACRO_SRV
        }
        return MacroSrvTaskType.EXIT_MACRO_STG
    }
    return MacroSrvTaskType.EXIT_MACRO_SRV
}

public func ExecuteOneMacroServerTask(evaluation: MacroEvaluation): Bool {
    let msg = ArrayList<UInt8>()
    if (!MacroProcMsger.GetInstance().ReadMsgFromClient(msg)) {
        return false
    }
    let task = GetMacroTaskType(msg)
    return match (task) {
        case MacroSrvTaskType.FIND_MACRO_DEFLIB => evaluation.FindDef(msg)
        case MacroSrvTaskType.EVAL_MACRO_CALL => evaluation.EvalMacroCall(msg)
        case MacroSrvTaskType.EXIT_MACRO_STG =>
            evaluation.ResetForNextEval()
            true
        case MacroSrvTaskType.EXIT_MACRO_SRV => false
    }
}

public func ExecuteMacroServerTaskLoop(evaluation: MacroEvaluation): Unit {
    while (ExecuteOneMacroServerTask(evaluation)) {
        ()
    }
}

private func evalServerCalls(evaluation: MacroEvaluation, calls: ArrayList<MacroCall>): Bool {
    var hasRunnable = false
    for (call in calls) {
        if (call.status != MacroEvalStatus.INIT) {
            continue
        }
        call.ci = Some(evaluation.ci)
        if (!call.FindMacroDefMethod()) {
            call.status = MacroEvalStatus.FAIL
            if (!evaluation.SerializeAndNotifyResult(call)) {
                return false
            }
            continue
        }
        if (evaluation.enableParallelMacro) {
            evaluation.SaveUsedMacros(call)
        } else {
            evaluation.SaveUsedMacroPkgs(call.packageName)
        }
        hasRunnable = true
    }
    if (!hasRunnable) {
        return true
    }
    evaluation.InitGlobalVariable()
    for (call in calls) {
        if (call.status == MacroEvalStatus.FAIL) {
            continue
        }
        evaluation.EvalOneMacroCall(call)
        if (!evaluation.SerializeAndNotifyResult(call)) {
            return false
        }
    }
    return true
}

extend MacroEvaluation {
    @When[os == "Linux" && backend == "cjnative"]
    public func RunMacroSrv(): Unit {
        useChildProcess = false
        RenameSrvProcess()
        let initArgs = ArrayList<(String, String)>()
        for ((key, value) in ci.GetGlobalOptions().environment.allVariables) {
            initArgs.add((key, value))
        }
        let _ = RuntimeInit.GetInstance().InitRuntime(ci.GetRuntimeLibPath(), initArgs: initArgs)
        let msger = MacroProcMsger.GetInstance()
        unsafe {
            let _ = close((msger.pipefdP2C + 1).read())
            let _ = close(msger.pipefdC2P.read())
        }
        ExecuteEvalSrvTask()
        RuntimeInit.GetInstance().CloseRuntime()
        unsafe {
            let _ = close(msger.pipefdP2C.read())
            let _ = close((msger.pipefdC2P + 1).read())
            exit(0)
        }
    }

    @When[os == "Linux" && backend != "cjnative"]
    public func RunMacroSrv(): Unit {
        useChildProcess = false
        RenameSrvProcess()
        let msger = MacroProcMsger.GetInstance()
        unsafe {
            let _ = close((msger.pipefdP2C + 1).read())
            let _ = close(msger.pipefdC2P.read())
        }
        ExecuteEvalSrvTask()
        RuntimeInit.GetInstance().CloseRuntime()
        unsafe {
            let _ = close(msger.pipefdP2C.read())
            let _ = close((msger.pipefdC2P + 1).read())
            exit(0)
        }
    }

    @When[(os == "macOS" || os == "iOS") && backend == "cjnative"]
    public func RunMacroSrv(): Unit {
        useChildProcess = false
        let initArgs = ArrayList<(String, String)>()
        for ((key, value) in ci.GetGlobalOptions().environment.allVariables) {
            initArgs.add((key, value))
        }
        let _ = RuntimeInit.GetInstance().InitRuntime(ci.GetRuntimeLibPath(), initArgs: initArgs)
        let msger = MacroProcMsger.GetInstance()
        unsafe {
            let _ = close((msger.pipefdP2C + 1).read())
            let _ = close(msger.pipefdC2P.read())
        }
        ExecuteEvalSrvTask()
        RuntimeInit.GetInstance().CloseRuntime()
        unsafe {
            let _ = close(msger.pipefdP2C.read())
            let _ = close((msger.pipefdC2P + 1).read())
            exit(0)
        }
    }

    @When[(os == "macOS" || os == "iOS") && backend != "cjnative"]
    public func RunMacroSrv(): Unit {
        useChildProcess = false
        let msger = MacroProcMsger.GetInstance()
        unsafe {
            let _ = close((msger.pipefdP2C + 1).read())
            let _ = close(msger.pipefdC2P.read())
        }
        ExecuteEvalSrvTask()
        RuntimeInit.GetInstance().CloseRuntime()
        unsafe {
            let _ = close(msger.pipefdP2C.read())
            let _ = close((msger.pipefdC2P + 1).read())
            exit(0)
        }
    }

    public func FindDef(msg: ArrayList<UInt8>): Bool {
        let macroLibs = ArrayList<String>()
        MacroEvalMsgSerializer.DeSerializeDeflibMsg(macroLibs, msg)
        for (lib in macroLibs) {
            let dyfile = FileUtil.NormalizePath(lib)
            let handle = OpenSymbolTable(dyfile)
            if (!handle.opened) {
                let res = ArrayList<UInt8>()
                for (byte in ("RespondFindDef " + dyfile).toArray()) {
                    res.add(byte)
                }
                let _ = MacroProcMsger.GetInstance().SendMsgToClient(res)
                return false
            }
            SetOpenedLibHandles(handle)
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
        return evalServerCalls(this, macroCollector.macCalls)
    }

    public func CreateMacroExpandFromMessage(text: String): MacroExpandDecl {
        let decl = MacroExpandDecl()
        let id = Box<String>("")
        let fullName = Box<String>("")
        let pos = Box<Position>(INVALID_POSITION)
        let begin = Box<Position>(INVALID_POSITION)
        let end = Box<Position>(INVALID_POSITION)
        MacroEvalMsgSerializer.DeSerializeRangeFromCall(begin, end, text)
        MacroEvalMsgSerializer.DeSerializeIdInfoFromCall(id, pos, text)
        MacroEvalMsgSerializer.DeSerializeFullNameFromCall(fullName, text)
        decl.begin = begin.value
        decl.end = end.value
        decl.identifier = SrcIdentifier(id.value)
        decl.invocation.macroCallDiagInfo.identifier = id.value
        decl.invocation.macroCallDiagInfo.fullName = if (fullName.value.isEmpty()) { id.value } else { fullName.value }
        decl.invocation.macroCallDiagInfo.identifierPos = pos.value
        decl.invocation.hasAttr = MacroEvalMsgSerializer.DeSerializeHasAttrFromCall(text)
        MacroEvalMsgSerializer.DeSerializeArgsFromCall(decl.invocation.args, text)
        MacroEvalMsgSerializer.DeSerializeAttrsFromCall(decl.invocation.attrs, text)
        return decl
    }

    public func DeSerializeMacroCall(text: String): MacroCall {
        let decl = CreateMacroExpandFromMessage(text)
        let call = MacroCall(decl)
        MacroEvalMsgSerializer.DeSerializeParentNamesFromCall(call.parentNames, text)
        MacroEvalMsgSerializer.DeSerializeChildMsgesFromCall(call.childMessages, text)
        let methodName = Box<String>("")
        let packageName = Box<String>("")
        let libPath = Box<String>("")
        MacroEvalMsgSerializer.DeSerializeMethodInfoFromCall(methodName, packageName, libPath, text)
        call.methodName = methodName.value
        call.packageName = packageName.value
        call.libPath = libPath.value
        call.ci = Some(ci)
        return call
    }

    public func EvalMacroCall(msg: ArrayList<UInt8>): Bool {
        let messages = ArrayList<String>()
        MacroEvalMsgSerializer.DeSerializeMacroCallMessages(msg, messages)
        if (messages.isEmpty()) {
            return false
        }
        let calls = ArrayList<MacroCall>()
        for (message in messages) {
            calls.add(DeSerializeMacroCall(message))
        }
        return evalServerCalls(this, calls)
    }

    public func ResetForNextEval(): Unit {
        usedMacroPkgs.clear()
        macroCollector.clear()
        ci.GetDiag().Reset()
        RuntimeInit.GetInstance().CloseRuntime()
    }
}
