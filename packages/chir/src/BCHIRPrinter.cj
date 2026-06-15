package cangjie_compiler::chir

import std.collection.*

public class BCHIRPrinter {
    private let bchir: BCHIR

    public init(bchir: BCHIR) {
        this.bchir = bchir
    }

    public func Print(header!: String = ""): String {
        var out = ""
        if (!header.isEmpty()) {
            out += header + "\n"
        }
        out += "package: " + bchir.packageName + "\n"
        out += "linked:\n"
        out += DefinitionToString(bchir.GetLinkedByteCode(), "  ")
        let functions = bchir.GetFunctions()
        if (!functions.isEmpty()) {
            out += "functions:\n"
            for (entry in functions) {
                out += "  " + entry.name + ":\n"
                out += DefinitionToString(entry.definition, "    ")
            }
        }
        let globals = bchir.GetGlobalVars()
        if (!globals.isEmpty()) {
            out += "globals:\n"
            for (entry in globals) {
                out += "  " + entry.name + ":\n"
                out += DefinitionToString(entry.definition, "    ")
            }
        }
        return out
    }

    public func PrintAll(header!: String = ""): String {
        var out = Print(header: header)
        let strings = bchir.GetStrings()
        if (!strings.isEmpty()) {
            out += "strings:\n"
            var idx: Int64 = 0
            while (idx < strings.size) {
                out += "  #${idx}: \"" + strings[idx] + "\"\n"
                idx++
            }
        }
        let files = bchir.GetFileNames()
        if (!files.isEmpty()) {
            out += "files:\n"
            var idx: Int64 = 0
            while (idx < files.size) {
                out += "  #${idx}: " + files[idx] + "\n"
                idx++
            }
        }
        let types = bchir.GetTypes()
        if (!types.isEmpty()) {
            out += "types:\n"
            var idx: Int64 = 0
            while (idx < types.size) {
                out += "  #${idx}: " + types[idx].ToString() + "\n"
                idx++
            }
        }
        let classTable = bchir.GetSClassTable()
        if (!classTable.isEmpty()) {
            out += "classes:\n"
            for (name in classTable.keys()) {
                out += "  " + name + "\n"
            }
        }
        return out
    }

    private func DefinitionToString(definition: BCHIRDefinition, indent: String): String {
        let code = definition.GetByteCodeRef()
        var out = ""
        var index: Int64 = 0
        while (index < code.size) {
            let opCode = OpCodeFromIndex(code[index])
            out += indent + "${index}: " + GetOpCodeLabel(opCode)
            let size = GetOpCodeArgSize(opCode)
            var argIndex: Int64 = 0
            while (argIndex < size && index + 1 + argIndex < code.size) {
                if (argIndex == 0) {
                    out += " "
                } else {
                    out += ", "
                }
                out += "${code[index + 1 + argIndex]}"
                argIndex++
            }
            let mangled = definition.GetMangledNameAnnotation(index)
            if (!mangled.isEmpty()) {
                out += " ; " + mangled
            }
            if (let Some(position) <- definition.GetCodePositionAnnotation(index)) {
                out += " @" + position.ToString()
            }
            out += "\n"
            index += 1 + size
        }
        return out
    }
}
