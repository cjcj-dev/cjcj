package cangjie_compiler::cjc

import std.env.*
import std.collection.*
import cangjie_compiler::driver.RunDriverMain
import cangjie_compiler::utils.StringifyArgumentVector

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
