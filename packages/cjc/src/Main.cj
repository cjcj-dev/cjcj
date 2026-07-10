package cjcj::cjc

import std.env.*
import std.collection.*
import cjcj::driver.RunDriverMain
import cjcj::utils.StringifyArgumentVector

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
