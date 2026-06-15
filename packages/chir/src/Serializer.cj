package cangjie_compiler::chir

import std.collection.*
import std.convert.*

private let CHIR_TEXT_HEADER: String = "CHIR-TEXT\t1"

public class CHIRSerializer {
    public init() {}

    public func SerializePackage(pkg: Package): String {
        let lines = ArrayList<String>()
        lines.add(CHIR_TEXT_HEADER)
        lines.add("package\t" + EscapeField(pkg.GetName()))
        for (globalVar in pkg.GetGlobalVars()) {
            let typeText = if (let Some(ty) <- globalVar.GetType()) { TypeRecord(ty) } else { "Invalid" }
            lines.add("global\t" + EscapeField(globalVar.GetIdentifier()) + "\t" +
                EscapeField(globalVar.GetSrcCodeIdentifier()) + "\t" +
                EscapeField(globalVar.GetRawMangledName()) + "\t" +
                EscapeField(globalVar.GetPackageName()) + "\t" + EscapeField(typeText))
        }
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            let retTyText = if (let Some(retTy) <- fn.GetReturnType()) { TypeRecord(retTy) } else { "Invalid" }
            let paramParts = ArrayList<String>()
            if (let Some(funcTy) <- fn.GetFuncType()) {
                for (paramTy in funcTy.GetParamTypes()) {
                    paramParts.add(TypeRecord(paramTy))
                }
            }
            lines.add("function\t" + EscapeField(fn.GetIdentifier()) + "\t" +
                EscapeField(fn.GetSrcCodeIdentifier()) + "\t" +
                EscapeField(fn.GetRawMangledName()) + "\t" +
                EscapeField(fn.GetPackageName()) + "\t" + FuncKindIndex(fn.GetFuncKind()).toString() + "\t" +
                EscapeField(retTyText) + "\t" + EscapeField(JoinStrings(paramParts, ",")))
        }
        return JoinStrings(lines, "\n")
    }
}

public class CHIRDeserializer {
    public init() {}

    public func DeserializePackage(text: String, builder: CHIRBuilder): Package {
        let lines = text.split("\n")
        if (lines.isEmpty() || lines[0] != CHIR_TEXT_HEADER) {
            let name = if (text.startsWith("package ")) { text[8..].split("\n")[0] } else { "<deserialized>" }
            return builder.CreatePackage(name)
        }
        var pkg = builder.CreatePackage("<deserialized>")
        var hasPackageLine = false
        for (line in lines) {
            if (line.isEmpty() || line == CHIR_TEXT_HEADER) {
                continue
            }
            let parts = line.split("\t")
            if (parts.isEmpty()) {
                continue
            }
            if (parts[0] == "package" && parts.size >= 2) {
                pkg = builder.CreatePackage(UnescapeField(parts[1]))
                hasPackageLine = true
            } else if (parts[0] == "global" && parts.size >= 6) {
                let ownerPackage = if (parts[4].isEmpty()) { pkg.GetName() } else { UnescapeField(parts[4]) }
                let globalVar = builder.CreateGlobalVar(ParseSimpleType(UnescapeField(parts[5]), builder),
                    UnescapeField(parts[1]), srcCodeIdentifier: UnescapeField(parts[2]),
                    rawMangledName: UnescapeField(parts[3]), packageName: ownerPackage)
                pkg.AddGlobalVar(globalVar)
            } else if (parts[0] == "function" && parts.size >= 8) {
                let paramTypes = ParseTypeList(UnescapeField(parts[7]), builder)
                let returnTy = ParseSimpleType(UnescapeField(parts[6]), builder)
                let ownerPackage = if (parts[4].isEmpty()) { pkg.GetName() } else { UnescapeField(parts[4]) }
                let funcTy = builder.context.GetFuncTy(paramTypes, returnTy)
                let fn = builder.CreateFunction(funcTy, UnescapeField(parts[1]),
                    srcCodeIdentifier: UnescapeField(parts[2]), rawMangledName: UnescapeField(parts[3]),
                    packageName: ownerPackage)
                fn.SetFuncKind(FuncKindFromIndex(Int64.parse(parts[5])))
                var paramIndex: Int64 = 0
                for (paramTy in paramTypes) {
                    builder.CreateParameter(paramTy, "%arg${paramIndex}", fn)
                    paramIndex++
                }
                pkg.AddGlobalFunc(fn)
            }
        }
        if (!hasPackageLine) {
            return builder.CreatePackage("<deserialized>")
        }
        return pkg
    }
}

private func TypeRecord(ty: Type): String {
    return ty.ToSrcCodeString()
}

private func ParseTypeList(text: String, builder: CHIRBuilder): ArrayList<Type> {
    let out = ArrayList<Type>()
    if (text.isEmpty()) {
        return out
    }
    for (part in text.split(",")) {
        out.add(ParseSimpleType(part, builder))
    }
    return out
}

private func ParseSimpleType(text: String, builder: CHIRBuilder): Type {
    return match (text) {
        case "Invalid" => builder.context.GetInvalidTy()
        case "Int8" => builder.context.GetInt8Ty()
        case "Int16" => builder.context.GetInt16Ty()
        case "Int32" => builder.context.GetInt32Ty()
        case "Int64" => builder.context.GetInt64Ty()
        case "IntNative" => builder.context.GetIntNativeTy()
        case "UInt8" => builder.context.GetUInt8Ty()
        case "UInt16" => builder.context.GetUInt16Ty()
        case "UInt32" => builder.context.GetUInt32Ty()
        case "UInt64" => builder.context.GetUInt64Ty()
        case "UIntNative" => builder.context.GetUIntNativeTy()
        case "Float16" => builder.context.GetFloat16Ty()
        case "Float32" => builder.context.GetFloat32Ty()
        case "Float64" => builder.context.GetFloat64Ty()
        case "Rune" => builder.context.GetRuneTy()
        case "Bool" => builder.context.GetBoolTy()
        case "Unit" => builder.context.GetUnitTy()
        case "Nothing" => builder.context.GetNothingType()
        case "Void" => builder.context.GetVoidTy()
        case "CString" => builder.context.GetCStringTy()
        case _ => builder.context.GetInvalidTy()
    }
}

private func FuncKindFromIndex(index: Int64): FuncKind {
    return match (index) {
        case 1 => FuncKind.GETTER
        case 2 => FuncKind.SETTER
        case 3 => FuncKind.LAMBDA
        case 4 => FuncKind.CLASS_CONSTRUCTOR
        case 5 => FuncKind.PRIMAL_CLASS_CONSTRUCTOR
        case 6 => FuncKind.STRUCT_CONSTRUCTOR
        case 7 => FuncKind.PRIMAL_STRUCT_CONSTRUCTOR
        case 8 => FuncKind.GLOBALVAR_INIT
        case 9 => FuncKind.FINALIZER
        case 10 => FuncKind.MAIN_ENTRY
        case 11 => FuncKind.ANNOFACTORY_FUNC
        case 12 => FuncKind.MACRO_FUNC
        case 13 => FuncKind.DEFAULT_PARAMETER_FUNC
        case 14 => FuncKind.INSTANCEVAR_INIT
        case _ => FuncKind.DEFAULT
    }
}

private func EscapeField(text: String): String {
    return text.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")
}

private func UnescapeField(text: String): String {
    return text.replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
}
