package cjcj::cjc

import std.env.*
import std.collection.*
import cjcj::driver.RunDriverMain
import cjcj::utils.StringifyArgumentVector

@When[os == "Windows"]
private func GetArgumentVector(): Array<String> {
    // Windows std.env obtains this vector from GetCommandLineW/CommandLineToArgvW.
    // getCommand() is the real process image, which differs from the public
    // SDK argv[0] when the launcher retains the compiler under libexec.
    return getCommandLine()
}

@When[os != "Windows"]
private func GetArgumentVector(): Array<String> {
    let command = getCommand()
    let commandLine = getCommandLine()
    if (!commandLine.isEmpty() && commandLine[0] == command) {
        return commandLine
    }
    let args = ArrayList<String>()
    args.add(command)
    for (arg in commandLine) {
        args.add(arg)
    }
    return args.toArray()
}

main(): Int64 {
    return RunDriverMain(StringifyArgumentVector(GetArgumentVector()))
}
