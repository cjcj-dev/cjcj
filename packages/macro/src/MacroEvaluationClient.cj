package cjcj::macro_pkg

import cjcj::basic.{DiagSeverityIndex, Errorln}
import cjcj::utils.FileUtil
import std.collection.*

private let MACRO_SRV_NAME: String = "LSPMacroServer"

@When[os != "Windows"]
private let SIGABRT: Int32 = 6
@When[os != "Windows"]
private let SIGINT: Int32 = 2
@When[os != "Windows"]
private let SIGTERM: Int32 = 15
@When[os != "Windows"]
private let SIGSEGV: Int32 = 11
@When[os == "Linux"]
private let SIGHUP: Int32 = 1
@When[os == "Linux"]
private let PR_SET_PDEATHSIG: Int32 = 1

@When[os != "Windows"]
foreign {
    func signal(sig: Int32, handler: CFunc<(Int32) -> Unit>): CFunc<(Int32) -> Unit>
    func _exit(status: Int32): Unit
    func waitpid(pid: Int32, status: CPointer<Int32>, options: Int32): Int32
    func dup2(oldfd: Int32, newfd: Int32): Int32
    func execv(path: CString, argv: CPointer<CString>): Int32
    func pipe(pipefd: CPointer<Int32>): Int32
    func fork(): Int32
    func getpid(): Int32
}

@When[os == "Linux"]
foreign {
    func prctl(option: Int32, ...): Int32
}

@When[os == "Windows"]
@C
struct SecurityAttributes {
    var nLength: UInt32
    var securityDescriptor: CPointer<Unit>
    var inheritHandle: Int32

    init() {
        nLength = UInt32(sizeOf<SecurityAttributes>())
        securityDescriptor = CPointer<Unit>()
        inheritHandle = 1
    }
}

@When[os == "Windows"]
@C
struct StartupInfo {
    var cb: UInt32
    var reserved: CString
    var desktop: CString
    var title: CString
    var x: UInt32
    var y: UInt32
    var xSize: UInt32
    var ySize: UInt32
    var xCountChars: UInt32
    var yCountChars: UInt32
    var fillAttribute: UInt32
    var flags: UInt32
    var showWindow: UInt16
    var reserved2Size: UInt16
    var reserved2: CPointer<UInt8>
    var stdInput: CPointer<Unit>
    var stdOutput: CPointer<Unit>
    var stdError: CPointer<Unit>

    init() {
        cb = UInt32(sizeOf<StartupInfo>())
        reserved = CString(CPointer<UInt8>())
        desktop = CString(CPointer<UInt8>())
        title = CString(CPointer<UInt8>())
        x = 0u32
        y = 0u32
        xSize = 0u32
        ySize = 0u32
        xCountChars = 0u32
        yCountChars = 0u32
        fillAttribute = 0u32
        flags = 0u32
        showWindow = 0u16
        reserved2Size = 0u16
        reserved2 = CPointer<UInt8>()
        stdInput = CPointer<Unit>()
        stdOutput = CPointer<Unit>()
        stdError = CPointer<Unit>()
    }
}

@When[os == "Windows"]
@C
struct ProcessInformation {
    var process: CPointer<Unit>
    var thread: CPointer<Unit>
    var processId: UInt32
    var threadId: UInt32

    init() {
        process = CPointer<Unit>()
        thread = CPointer<Unit>()
        processId = 0u32
        threadId = 0u32
    }
}

@When[os == "Windows"]
@C
struct JobObjectBasicLimitInformation {
    var perProcessUserTimeLimit: Int64
    var perJobUserTimeLimit: Int64
    var limitFlags: UInt32
    var minimumWorkingSetSize: UIntNative
    var maximumWorkingSetSize: UIntNative
    var activeProcessLimit: UInt32
    var affinity: UIntNative
    var priorityClass: UInt32
    var schedulingClass: UInt32

    init() {
        perProcessUserTimeLimit = 0
        perJobUserTimeLimit = 0
        limitFlags = 0u32
        minimumWorkingSetSize = UIntNative(0)
        maximumWorkingSetSize = UIntNative(0)
        activeProcessLimit = 0u32
        affinity = UIntNative(0)
        priorityClass = 0u32
        schedulingClass = 0u32
    }
}

@When[os == "Windows"]
@C
struct IoCounters {
    var readOperationCount: UInt64
    var writeOperationCount: UInt64
    var otherOperationCount: UInt64
    var readTransferCount: UInt64
    var writeTransferCount: UInt64
    var otherTransferCount: UInt64

    init() {
        readOperationCount = 0u64
        writeOperationCount = 0u64
        otherOperationCount = 0u64
        readTransferCount = 0u64
        writeTransferCount = 0u64
        otherTransferCount = 0u64
    }
}

@When[os == "Windows"]
@C
struct JobObjectExtendedLimitInformation {
    var basicLimitInformation: JobObjectBasicLimitInformation
    var ioInfo: IoCounters
    var processMemoryLimit: UIntNative
    var jobMemoryLimit: UIntNative
    var peakProcessMemoryUsed: UIntNative
    var peakJobMemoryUsed: UIntNative

    init() {
        basicLimitInformation = JobObjectBasicLimitInformation()
        ioInfo = IoCounters()
        processMemoryLimit = UIntNative(0)
        jobMemoryLimit = UIntNative(0)
        peakProcessMemoryUsed = UIntNative(0)
        peakJobMemoryUsed = UIntNative(0)
    }
}

@When[os == "Windows"]
foreign {
    func WaitForSingleObject(handle: CPointer<Unit>, milliseconds: UInt32): UInt32
    func CreateJobObjectA(attributes: CPointer<SecurityAttributes>, name: CString): CPointer<Unit>
    func SetInformationJobObject(job: CPointer<Unit>, informationClass: Int32,
        information: CPointer<JobObjectExtendedLimitInformation>, informationLength: UInt32): Int32
    func AssignProcessToJobObject(job: CPointer<Unit>, process: CPointer<Unit>): Int32
    func GetStdHandle(stdHandle: UInt32): CPointer<Unit>
    func CloseHandle(handle: CPointer<Unit>): Int32
    func CreatePipe(readPipe: CPointer<CPointer<Unit>>, writePipe: CPointer<CPointer<Unit>>,
        attributes: CPointer<SecurityAttributes>, size: UInt32): Int32
    func CreateProcessA(applicationName: CString, commandLine: CString,
        processAttributes: CPointer<SecurityAttributes>, threadAttributes: CPointer<SecurityAttributes>,
        inheritHandles: Int32, creationFlags: UInt32, environment: CPointer<Unit>, currentDirectory: CString,
        startupInfo: CPointer<StartupInfo>, processInformation: CPointer<ProcessInformation>): Int32
    func GetLastError(): UInt32
}

@When[os != "Windows"]
private func SignalHandler(_: Int32): Unit {
    MacroProcMsger.GetInstance().CloseMacroSrv()
    unsafe { _exit(1) }
}

@When[os != "Windows"]
private func SetExitSignal(): Unit {
    unsafe {
        let _ = signal(SIGABRT, { value: Int32 => SignalHandler(value) })
        let _ = signal(SIGINT, { value: Int32 => SignalHandler(value) })
        let _ = signal(SIGTERM, { value: Int32 => SignalHandler(value) })
        let _ = signal(SIGSEGV, { value: Int32 => SignalHandler(value) })
    }
}

@When[os != "Windows"]
private func WaitProcessExit(pid: Int32): Unit {
    try (status = LibC.malloc<Int32>().asResource()) {
        let ret = unsafe { waitpid(pid, status.value, 0) }
        MacroProcMsger.GetInstance().macroSrvRun.store(false)
        if (ret == -1) {
            Errorln("Error waiting for macro srv process")
        }
    }
}

@When[os != "Windows"]
private func CloseBothEndsOfPipe(pipefd: CPointer<Int32>): Unit {
    unsafe {
        let _ = close(pipefd.read())
        let _ = close((pipefd + 1).read())
        pipefd.write(-1)
        (pipefd + 1).write(-1)
    }
}

@When[os != "Windows"]
private func RedirectStdOutTOStdErr(): Unit {
    if (unsafe { dup2(2, 1) } == -1) {
        try (message = unsafe {
            LibC.mallocCString("macro srv dup2 from STDOUT_FILENO to STDERR_FILENO fail")
        }.asResource()) {
            unsafe { perror(message.value) }
        }
    }
}

@When[os == "Windows"]
private func WaitProcessExit(pi: ProcessInformation): Unit {
    if (unsafe { WaitForSingleObject(pi.process, UInt32.Max) } == UInt32.Max) {
        Errorln("Getting child process exit code: " + unsafe { GetLastError() }.toString())
    }
    MacroProcMsger.GetInstance().macroSrvRun.store(false)
}

@When[os == "Windows"]
private func CreateJobObjectForMacroSrv(): Unit {
    let job = unsafe { CreateJobObjectA(CPointer<SecurityAttributes>(), CString(CPointer<UInt8>())) }
    if (job.isNull()) {
        Errorln("Create job object for macro srv fail!")
        return
    }
    try (information = LibC.malloc<JobObjectExtendedLimitInformation>().asResource()) {
        var value = JobObjectExtendedLimitInformation()
        value.basicLimitInformation.limitFlags = 0x00002000u32
        unsafe { information.value.write(value) }
        if (unsafe { SetInformationJobObject(job, 9, information.value,
            UInt32(sizeOf<JobObjectExtendedLimitInformation>())) } == 0) {
            Errorln("Could not SetInformationJobObject for macro srv")
            return
        }
    }
    if (unsafe { AssignProcessToJobObject(job, MacroProcMsger.GetInstance().hProcess) } == 0) {
        Errorln("Assign process to JobObject fail!")
    }
}

@When[os == "Windows"]
private func RedirectStdOutForMarcoSrv(si: CPointer<StartupInfo>): Unit {
    let parentErr = unsafe { GetStdHandle(0xfffffff4u32) }
    unsafe {
        var value = si.read()
        value.stdOutput = parentErr
        value.stdError = parentErr
        value.flags = 0x00000100u32
        si.write(value)
    }
}

@When[os == "Windows"]
private func CloseSrvPipe(): Unit {
    let msger = MacroProcMsger.GetInstance()
    if (!msger.hChildWrite.isNull()) {
        if (unsafe { CloseHandle(msger.hChildWrite) } != 0) {
            msger.hChildWrite = CPointer<Unit>()
        } else {
            Errorln("CloseHandle hParentRead error")
        }
    }
    if (!msger.hChildRead.isNull()) {
        if (unsafe { CloseHandle(msger.hChildRead) } != 0) {
            msger.hChildRead = CPointer<Unit>()
        } else {
            Errorln("CloseHandle hParentWrite error")
        }
    }
}

@When[os == "Windows"]
private func CreateMacroMsgPipe(): Bool {
    let msger = MacroProcMsger.GetInstance()
    try (attributes = LibC.malloc<SecurityAttributes>().asResource(),
        parentRead = LibC.malloc<CPointer<Unit>>().asResource(),
        childWrite = LibC.malloc<CPointer<Unit>>().asResource(),
        childRead = LibC.malloc<CPointer<Unit>>().asResource(),
        parentWrite = LibC.malloc<CPointer<Unit>>().asResource()) {
        unsafe { attributes.value.write(SecurityAttributes()) }
        if (unsafe { CreatePipe(parentRead.value, childWrite.value, attributes.value, 0u32) } == 0) {
            Errorln("Create macro srv pipe fail!")
            return false
        }
        msger.hParentRead = unsafe { parentRead.value.read() }
        msger.hChildWrite = unsafe { childWrite.value.read() }
        if (unsafe { CreatePipe(childRead.value, parentWrite.value, attributes.value, 0u32) } == 0) {
            CloseSrvPipe()
            msger.CloseClientResource()
            Errorln("Create macro srv pipe fail!")
            return false
        }
        msger.hChildRead = unsafe { childRead.value.read() }
        msger.hParentWrite = unsafe { parentWrite.value.read() }
    }
    return true
}

@When[os == "Windows"]
private func GetMacroSrvCmd(enableParallelMacro: Bool, cjcPath: String): String {
    var cmd = FileUtil.JoinPath(FileUtil.GetDirPath(cjcPath), "..\\tools\\bin\\" + MACRO_SRV_NAME + ".exe")
    cmd += " " + Int32(UIntNative(MacroProcMsger.GetInstance().hChildRead)).toString()
    cmd += " " + Int32(UIntNative(MacroProcMsger.GetInstance().hChildWrite)).toString()
    cmd += if (enableParallelMacro) { " 1" } else { " 0" }
    cmd += " \"" + cjcPath + "\""
    return cmd
}

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
    @When[os != "Windows"]
    public func ExecMacroSrv(pid: Int32): Unit {
        let macSrvPath = FileUtil.JoinPath(FileUtil.GetDirPath(ci.GetGlobalOptions().executablePath),
            "../tools/bin/" + MACRO_SRV_NAME)
        let msger = MacroProcMsger.GetInstance()
        let hRead = unsafe { msger.pipefdP2C.read() }.toString()
        let hWrite = unsafe { (msger.pipefdC2P + 1).read() }.toString()
        let enPara = if (enableParallelMacro) { "1" } else { "0" }
        let pidStr = pid.toString()
        let arguments = [macSrvPath, hRead, hWrite, enPara, ci.GetGlobalOptions().executablePath, pidStr]
        let nativeArguments = ArrayList<CString>()
        try (argv = LibC.malloc<CString>(count: arguments.size + 1).asResource()) {
            var idx: Int64 = 0
            while (idx < arguments.size) {
                let value = unsafe { LibC.mallocCString(arguments[idx]) }
                nativeArguments.add(value)
                unsafe { (argv.value + idx).write(value) }
                idx++
            }
            unsafe {
                (argv.value + arguments.size).write(CString(CPointer<UInt8>()))
                let _ = execv(nativeArguments[0], argv.value)
            }
        }
        for (value in nativeArguments) {
            unsafe { LibC.free(value) }
        }
    }
}

@When[os == "Linux"]
func CreateMacroSrvProcess(evaluation: MacroEvaluation): Unit {
        synchronized(MacroProcMsger.GetInstance().mutex) {
            let msger = MacroProcMsger.GetInstance()
            if (msger.macroSrvRun.load()) {
                return
            }
            msger.CloseClientResource()
            if (unsafe { pipe(msger.pipefdP2C) } == -1) {
                try (message = unsafe { LibC.mallocCString("Create P2C pipe fail: ") }.asResource()) {
                    unsafe { perror(message.value) }
                }
                return
            }
            if (unsafe { pipe(msger.pipefdC2P) } == -1) {
                CloseBothEndsOfPipe(msger.pipefdP2C)
                try (message = unsafe { LibC.mallocCString("Create C2P pipe fail: ") }.asResource()) {
                    unsafe { perror(message.value) }
                }
                return
            }
            msger.pipeError.store(false)
            let ppid = unsafe { getpid() }
            let pid = unsafe { fork() }
            if (pid < 0) {
                CloseBothEndsOfPipe(msger.pipefdP2C)
                CloseBothEndsOfPipe(msger.pipefdC2P)
                return
            }
            msger.macroSrvRun.store(true)
            if (pid == 0) {
                if (unsafe { prctl(PR_SET_PDEATHSIG, SIGHUP) } == -1) {
                    try (message = unsafe { LibC.mallocCString("PR_SET_PDEATHSIG: ") }.asResource()) {
                        unsafe { perror(message.value) }
                    }
                }
                RedirectStdOutTOStdErr()
                evaluation.ExecMacroSrv(ppid)
                try (message = unsafe {
                    LibC.mallocCString("run macro srv in fork, due to exec fail")
                }.asResource()) {
                    unsafe { perror(message.value) }
                }
                evaluation.RunMacroSrv()
            } else {
                SetExitSignal()
                let _ = spawn { WaitProcessExit(pid) }
                unsafe {
                    let _ = close(msger.pipefdP2C.read())
                    let _ = close((msger.pipefdC2P + 1).read())
                }
            }
        }
    }

@When[os == "macOS"]
func CreateMacroSrvProcess(evaluation: MacroEvaluation): Unit {
        synchronized(MacroProcMsger.GetInstance().mutex) {
            let msger = MacroProcMsger.GetInstance()
            if (msger.macroSrvRun.load()) {
                return
            }
            msger.CloseClientResource()
            if (unsafe { pipe(msger.pipefdP2C) } == -1) {
                try (message = unsafe { LibC.mallocCString("Create P2C pipe fail: ") }.asResource()) {
                    unsafe { perror(message.value) }
                }
                return
            }
            if (unsafe { pipe(msger.pipefdC2P) } == -1) {
                CloseBothEndsOfPipe(msger.pipefdP2C)
                try (message = unsafe { LibC.mallocCString("Create C2P pipe fail: ") }.asResource()) {
                    unsafe { perror(message.value) }
                }
                return
            }
            msger.pipeError.store(false)
            let ppid = unsafe { getpid() }
            let pid = unsafe { fork() }
            if (pid < 0) {
                CloseBothEndsOfPipe(msger.pipefdP2C)
                CloseBothEndsOfPipe(msger.pipefdC2P)
                return
            }
            msger.macroSrvRun.store(true)
            if (pid == 0) {
                RedirectStdOutTOStdErr()
                evaluation.ExecMacroSrv(ppid)
                try (message = unsafe {
                    LibC.mallocCString("run macro srv in fork, due to exec fail")
                }.asResource()) {
                    unsafe { perror(message.value) }
                }
                evaluation.RunMacroSrv()
            } else {
                SetExitSignal()
                let _ = spawn { WaitProcessExit(pid) }
                unsafe {
                    let _ = close(msger.pipefdP2C.read())
                    let _ = close((msger.pipefdC2P + 1).read())
                }
            }
        }
    }

@When[os == "Windows"]
func CreateMacroSrvProcess(evaluation: MacroEvaluation): Unit {
        synchronized(MacroProcMsger.GetInstance().mutex) {
            let msger = MacroProcMsger.GetInstance()
            if (msger.macroSrvRun.load()) {
                return
            }
            msger.CloseClientResource()
            if (!CreateMacroMsgPipe()) {
                return
            }
            msger.pipeError.store(false)
            try (startupInfo = LibC.malloc<StartupInfo>().asResource(),
                processInformation = LibC.malloc<ProcessInformation>().asResource()) {
                unsafe {
                    startupInfo.value.write(StartupInfo())
                    processInformation.value.write(ProcessInformation())
                }
                RedirectStdOutForMarcoSrv(startupInfo.value)
                let command = GetMacroSrvCmd(evaluation.enableParallelMacro,
                    evaluation.ci.GetGlobalOptions().executablePath)
                try (commandLine = unsafe { LibC.mallocCString(command) }.asResource()) {
                    if (unsafe { CreateProcessA(CString(CPointer<UInt8>()), commandLine.value,
                        CPointer<SecurityAttributes>(), CPointer<SecurityAttributes>(), 1, 0u32, CPointer<Unit>(),
                        CString(CPointer<UInt8>()), startupInfo.value, processInformation.value) } == 0) {
                        CloseSrvPipe()
                        msger.CloseClientResource()
                        Errorln("Create " + MACRO_SRV_NAME + " fail!")
                        return
                    }
                }
                msger.macroSrvRun.store(true)
                let pi = unsafe { processInformation.value.read() }
                let _ = spawn { WaitProcessExit(pi) }
                msger.hProcess = pi.process
                msger.hThread = pi.thread
                CreateJobObjectForMacroSrv()
                CloseSrvPipe()
            }
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
