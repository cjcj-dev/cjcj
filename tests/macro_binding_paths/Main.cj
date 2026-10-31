import cjcj::driver.{Driver, Linux_CJNATIVE, ToolBatch}
import cjcj::option.{TempFileInfo, TempFileManager, ArchType, OSType, EnvironmentType, OutputMode, OrderedInput}
import cjcj::frontend.DiagnosticEngine
import cjcj::macro_pkg.{RuntimeInit, OpenMacroLibrary, GetMethodPointer}
import std.collection.ArrayList
import std.env.getVariable

class LinuxLinkProbe <: Linux_CJNATIVE {
    init(driver: Driver, commands: ArrayList<ToolBatch>) {
        super(driver, driver.driverOptions, commands)
    }
    func Generate(): Unit {
        GenerateLinkingTool(ArrayList<TempFileInfo>(), "", ("crtbeginS.o", "crtendS.o"))
    }
}

@C
func BorrowedTask(argument: CPointer<Unit>): CPointer<Unit> {
    unsafe { CPointer<Int64>(argument).write(42) }
    return CPointer<Unit>()
}

func LinkPaths(macroOutput: Bool): Int64 {
    let sdk = getVariable("CANGJIE_HOME").getOrThrow()
    let root = getVariable("M1_WORK").getOrThrow()
    try (diag = DiagnosticEngine()) {
        let driver = Driver(["cjc"], diag, executableName: sdk + "/bin/cjc")
        driver.cangjieHome = sdk
        let opts = driver.driverOptions
        opts.host.arch = ArchType.X86_64
        opts.host.os = OSType.LINUX
        opts.host.env = EnvironmentType.GNU
        opts.target.arch = ArchType.X86_64
        opts.target.os = OSType.LINUX
        opts.target.env = EnvironmentType.GNU
        opts.compileMacroPackage = macroOutput
        opts.outputMode = OutputMode.SHARED_LIB
        opts.useRuntimeRpath = true
        opts.moduleName = "binding"
        opts.output = root + "/lib-binding.so"
        opts.inputLinkOptionsOrder.add(OrderedInput("-rpath $ORIGIN/private", 0u64))
        if (!TempFileManager.Instance().Init(opts, false)) { return 90 }
        try {
            let commands = ArrayList<ToolBatch>()
            LinuxLinkProbe(driver, commands).Generate()
            if (commands.size != 1 || commands[0].size != 1) { return 91 }
            let args = commands[0][0].GetArgs()
            let paths = ArrayList<String>()
            for (i in 0..args.size) {
                if (args[i] == "-rpath" && i + 1 < args.size) { paths.add(args[i + 1]) }
            }
            for (path in paths) { println("RPATH=" + path) }
            let runtime = if (macroOutput) { sdk + "/bin/../runtime/lib/linux_x86_64_cjnative" }
                else { sdk + "/runtime/lib/linux_x86_64_cjnative" }
            let expected = if (macroOutput) { [runtime, "$ORIGIN/private"] }
                else { ["$ORIGIN/private", runtime] }
            var matches = paths.size == expected.size
            if (matches) {
                for (i in 0..expected.size) { matches = matches && paths[i] == expected[i] }
            }
            println("LINK_PATH_ASSERT macro=${macroOutput} reached=1 matches=${matches}")
            return if (matches) { 0 } else { 2 }
        } finally { TempFileManager.Instance().DeleteTempFiles() }
    }
    return 99
}

func BorrowedBinding(): Int64 {
    let sdk = getVariable("CANGJIE_HOME").getOrThrow()
    let root = getVariable("M1_WORK").getOrThrow()
    let runtime = RuntimeInit.GetInstance()
    if (!runtime.InitRuntime(sdk + "/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so")) { return 92 }
    if (runtime.taskOnOpenedRuntime || runtime.GetHandle().isSome()) { return 93 }
    try {
        let stale = OpenMacroLibrary(root + "/old.so")
        println("BORROWED_STALE rejected=${!stale.opened}")
        if (stale.opened) { return 94 }
        let current = OpenMacroLibrary(root + "/current.so")
        println("BORROWED_BINDING_ASSERT handleNone=true opened=${current.opened}")
        if (!current.opened) { return 3 }
        let value = GetMethodPointer(current, "binding_value")
        if (value.isNull() || unsafe { CFunc<() -> Int32>(value)() } != 42) { return 95 }
    } finally { runtime.CloseRuntime() }
    let second = RuntimeInit()
    if (!second.InitRuntime(sdk + "/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so")) { return 96 }
    try {
        if (second.taskOnOpenedRuntime) { return 97 }
        try (argument = LibC.malloc<Int64>().asResource()) {
            unsafe { argument.value.write(0) }
            let future = second.SubmitTask(CPointer<Unit>(BorrowedTask), CPointer<Unit>(argument.value))
            let result = second.CompleteTask(future)
            if (!result.isNull() || unsafe { argument.value.read() } != 42) { return 98 }
        }
    } finally { second.CloseRuntime() }
    println("BORROWED_CLOSE_CONTROL task42=true hostAlive=true")
    return 0
}

main(args: Array<String>): Int64 {
    if (args.size != 2) { return 64 }
    return match (args[1]) {
        case "macro" => LinkPaths(true)
        case "ordinary" => LinkPaths(false)
        case "borrowed" => BorrowedBinding()
        case _ => 64
    }
}
