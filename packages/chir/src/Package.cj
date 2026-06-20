package cangjie_compiler::chir

import std.collection.*

public class Package {
    private let name: String
    private var pkgAccessLevel: AccessLevel = AccessLevel.INVALID
    private let importedStructs: ArrayList<StructDef> = ArrayList<StructDef>()
    private let importedClasses: ArrayList<ClassDef> = ArrayList<ClassDef>()
    private let importedEnums: ArrayList<EnumDef> = ArrayList<EnumDef>()
    private let importedExtends: ArrayList<ExtendDef> = ArrayList<ExtendDef>()
    private let globalVars: ArrayList<GlobalVar> = ArrayList<GlobalVar>()
    private let globalFuncs: ArrayList<Function> = ArrayList<Function>()
    private let structs: ArrayList<StructDef> = ArrayList<StructDef>()
    private let classes: ArrayList<ClassDef> = ArrayList<ClassDef>()
    private let enums: ArrayList<EnumDef> = ArrayList<EnumDef>()
    private let extends: ArrayList<ExtendDef> = ArrayList<ExtendDef>()
    private var packageInitFunc: Option<Function> = None
    private var packageLiteralInitFunc: Option<Function> = None

    public init(name: String) {
        this.name = name
    }

    public func Dump(): Unit {
        println(ToString())
    }

    public func ToString(): String {
        var out = "package " + name
        if (!globalVars.isEmpty()) {
            out += "\n  globals:"
            for (item in globalVars) {
                out += "\n" + item.ToString(4)
            }
        }
        if (!globalFuncs.isEmpty()) {
            out += "\n  functions:"
            for (item in globalFuncs) {
                out += "\n" + item.ToString(4)
            }
        }
        if (!structs.isEmpty()) {
            out += "\n  structs:"
            for (item in structs) {
                out += "\n" + item.ToString(4)
            }
        }
        if (!classes.isEmpty()) {
            out += "\n  classes:"
            for (item in classes) {
                out += "\n" + item.ToString(4)
            }
        }
        if (!enums.isEmpty()) {
            out += "\n  enums:"
            for (item in enums) {
                out += "\n" + item.ToString(4)
            }
        }
        if (!extends.isEmpty()) {
            out += "\n  extends:"
            for (item in extends) {
                out += "\n" + item.ToString(4)
            }
        }
        return out
    }

    public func GetName(): String { return name }
    public func GetPackageAccessLevel(): AccessLevel { return pkgAccessLevel }
    public func SetPackageAccessLevel(level: AccessLevel): Unit { pkgAccessLevel = level }

    public func AddGlobalVar(item: GlobalVar): Unit { globalVars.add(item) }

    public func TryGetGlobalVar(identifier: String): Option<GlobalVar> {
        for (item in globalVars) {
            if (item.GetIdentifier() == identifier) {
                return item
            }
        }
        return None
    }

    public func GetGlobalVarsWithoutInit(): ArrayList<GlobalVar> {
        let out = ArrayList<GlobalVar>()
        for (item in globalVars) {
            if (item.GetInitializerValue().isNone() && item.GetInitFunc().isNone() && !item.IsSrcCodeImported()) {
                out.add(item)
            }
        }
        return out
    }

    public func GetGlobalVarsWithInit(includeSrcCodeImported!: Bool = true): ArrayList<GlobalVar> {
        let out = ArrayList<GlobalVar>()
        for (item in globalVars) {
            if ((item.GetInitializerValue().isSome() || item.GetInitFunc().isSome()) &&
                (includeSrcCodeImported || !item.IsSrcCodeImported())) {
                out.add(item)
            }
        }
        return out
    }

    public func GetGlobalVars(): ArrayList<GlobalVar> { return CopyGlobalVarList(globalVars) }
    public func GetGlobalVarsRef(): ArrayList<GlobalVar> { return globalVars }

    public func SetAllGlobalVars(vars: ArrayList<GlobalVar>): Unit {
        globalVars.clear()
        for (item in vars) {
            globalVars.add(item)
        }
    }

    public func AddGlobalFunc(item: Function): Unit { globalFuncs.add(item) }

    public func TryGetGlobalFunc(identifier: String): Option<Function> {
        for (item in globalFuncs) {
            if (item.GetIdentifier() == identifier) {
                return item
            }
        }
        return None
    }

    public func GetGlobalFuncsWithoutBody(includePureAbstract!: Bool = false): ArrayList<Function> {
        let out = ArrayList<Function>()
        for (item in globalFuncs) {
            if (item.GetBody().isNone() && (!item.TestAttr(Attribute.SRC_CODE_IMPORTED))) {
                if (includePureAbstract || !item.TestAttr(Attribute.ABSTRACT)) {
                    out.add(item)
                }
            }
        }
        return out
    }

    public func GetGlobalFuncsWithBody(includeSrcCodeImported!: Bool = true): ArrayList<Function> {
        let out = ArrayList<Function>()
        for (item in globalFuncs) {
            if (item.GetBody().isSome() && (includeSrcCodeImported || !item.IsSrcCodeImported())) {
                out.add(item)
            }
        }
        return out
    }

    public func GetGlobalFunctions(includePureAbstract!: Bool = false): ArrayList<Function> {
        let out = ArrayList<Function>()
        for (item in globalFuncs) {
            if (includePureAbstract || !item.TestAttr(Attribute.ABSTRACT)) {
                out.add(item)
            }
        }
        return out
    }

    public func GetGlobalFunctionsRef(): ArrayList<Function> { return globalFuncs }

    public func SetAllGlobalFuncs(funcs: ArrayList<Function>): Unit {
        globalFuncs.clear()
        for (item in funcs) {
            globalFuncs.add(item)
        }
    }

    public func GetPackageInitFunc(): Option<Function> { return packageInitFunc }
    public func SetPackageInitFunc(fn: Function): Unit { packageInitFunc = fn }
    public func SetPackageLiteralInitFunc(fn: Function): Unit { packageLiteralInitFunc = fn }
    public func GetPackageLiteralInitFunc(): Option<Function> { return packageLiteralInitFunc }

    public func AddStruct(item: StructDef): Unit { structs.add(item) }
    public func GetStructs(): ArrayList<StructDef> { return CopyStructList(structs) }
    public func SetStructs(items: ArrayList<StructDef>): Unit { ReplaceStructList(structs, items) }
    public func AddImportedStruct(item: StructDef): Unit { importedStructs.add(item) }
    public func GetImportedStructs(): ArrayList<StructDef> { return CopyStructList(importedStructs) }
    public func GetImportedStructsRef(): ArrayList<StructDef> { return importedStructs }
    public func SetImportedStructs(items: ArrayList<StructDef>): Unit { ReplaceStructList(importedStructs, items) }

    public func AddClass(item: ClassDef): Unit { classes.add(item) }
    public func GetClasses(): ArrayList<ClassDef> { return CopyClassList(classes) }
    public func SetClasses(items: ArrayList<ClassDef>): Unit { ReplaceClassList(classes, items) }
    public func AddImportedClass(item: ClassDef): Unit { importedClasses.add(item) }
    public func GetImportedClasses(): ArrayList<ClassDef> { return CopyClassList(importedClasses) }
    public func GetImportedClassesRef(): ArrayList<ClassDef> { return importedClasses }
    public func SetImportedClasses(items: ArrayList<ClassDef>): Unit { ReplaceClassList(importedClasses, items) }

    public func AddEnum(item: EnumDef): Unit { enums.add(item) }
    public func GetEnums(): ArrayList<EnumDef> { return CopyEnumList(enums) }
    public func SetEnums(items: ArrayList<EnumDef>): Unit { ReplaceEnumList(enums, items) }
    public func AddImportedEnum(item: EnumDef): Unit { importedEnums.add(item) }
    public func GetImportedEnums(): ArrayList<EnumDef> { return CopyEnumList(importedEnums) }
    public func GetImportedEnumsRef(): ArrayList<EnumDef> { return importedEnums }
    public func SetImportedEnums(items: ArrayList<EnumDef>): Unit { ReplaceEnumList(importedEnums, items) }

    public func AddExtend(item: ExtendDef): Unit { extends.add(item) }
    public func GetExtends(): ArrayList<ExtendDef> { return CopyExtendList(extends) }
    public func SetExtends(items: ArrayList<ExtendDef>): Unit { ReplaceExtendList(extends, items) }
    public func AddImportedExtend(item: ExtendDef): Unit { importedExtends.add(item) }
    public func GetImportedExtends(): ArrayList<ExtendDef> { return CopyExtendList(importedExtends) }
    public func GetImportedExtendsRef(): ArrayList<ExtendDef> { return importedExtends }
    public func SetImportedExtends(items: ArrayList<ExtendDef>): Unit { ReplaceExtendList(importedExtends, items) }

    public func GetAllStructDef(): ArrayList<StructDef> {
        let out = CopyStructList(structs)
        for (item in importedStructs) { out.add(item) }
        return out
    }

    public func TryGetStructDef(identifier: String): Option<StructDef> {
        for (item in GetAllStructDef()) {
            if (item.GetIdentifier() == identifier) { return item }
        }
        return None
    }

    public func GetAllClassDef(): ArrayList<ClassDef> {
        let out = CopyClassList(classes)
        for (item in importedClasses) { out.add(item) }
        return out
    }

    public func TryGetClassDef(identifier: String): Option<ClassDef> {
        for (item in GetAllClassDef()) {
            if (item.GetIdentifier() == identifier) { return item }
        }
        return None
    }

    public func GetAllEnumDef(): ArrayList<EnumDef> {
        let out = CopyEnumList(enums)
        for (item in importedEnums) { out.add(item) }
        return out
    }

    public func TryGetEnumDef(identifier: String): Option<EnumDef> {
        for (item in GetAllEnumDef()) {
            if (item.GetIdentifier() == identifier) { return item }
        }
        return None
    }

    public func GetAllExtendDef(): ArrayList<ExtendDef> {
        let out = CopyExtendList(extends)
        for (item in importedExtends) { out.add(item) }
        return out
    }

    public func TryGetExtendDef(identifier: String): Option<ExtendDef> {
        for (item in GetAllExtendDef()) {
            if (item.GetIdentifier() == identifier) { return item }
        }
        return None
    }

    public func GetAllCustomTypeDef(): ArrayList<CustomTypeDef> {
        let out = GetCurPkgCustomTypeDef()
        for (item in GetAllImportedCustomTypeDef()) {
            out.add(item)
        }
        return out
    }

    public func GetCurPkgCustomTypeDef(): ArrayList<CustomTypeDef> {
        let out = ArrayList<CustomTypeDef>()
        for (item in structs) { out.add(item) }
        for (item in classes) { out.add(item) }
        for (item in enums) { out.add(item) }
        for (item in extends) { out.add(item) }
        return out
    }

    public func GetAllImportedCustomTypeDef(): ArrayList<CustomTypeDef> {
        let out = ArrayList<CustomTypeDef>()
        for (item in importedStructs) { out.add(item) }
        for (item in importedClasses) { out.add(item) }
        for (item in importedEnums) { out.add(item) }
        for (item in importedExtends) { out.add(item) }
        return out
    }
}

private func CopyGlobalVarList(values: ArrayList<GlobalVar>): ArrayList<GlobalVar> {
    let out = ArrayList<GlobalVar>()
    for (item in values) { out.add(item) }
    return out
}

private func CopyStructList(values: ArrayList<StructDef>): ArrayList<StructDef> {
    let out = ArrayList<StructDef>()
    for (item in values) { out.add(item) }
    return out
}

private func ReplaceStructList(target: ArrayList<StructDef>, values: ArrayList<StructDef>): Unit {
    target.clear()
    for (item in values) { target.add(item) }
}

private func CopyClassList(values: ArrayList<ClassDef>): ArrayList<ClassDef> {
    let out = ArrayList<ClassDef>()
    for (item in values) { out.add(item) }
    return out
}

private func ReplaceClassList(target: ArrayList<ClassDef>, values: ArrayList<ClassDef>): Unit {
    target.clear()
    for (item in values) { target.add(item) }
}

private func CopyEnumList(values: ArrayList<EnumDef>): ArrayList<EnumDef> {
    let out = ArrayList<EnumDef>()
    for (item in values) { out.add(item) }
    return out
}

private func ReplaceEnumList(target: ArrayList<EnumDef>, values: ArrayList<EnumDef>): Unit {
    target.clear()
    for (item in values) { target.add(item) }
}

private func CopyExtendList(values: ArrayList<ExtendDef>): ArrayList<ExtendDef> {
    let out = ArrayList<ExtendDef>()
    for (item in values) { out.add(item) }
    return out
}

private func ReplaceExtendList(target: ArrayList<ExtendDef>, values: ArrayList<ExtendDef>): Unit {
    target.clear()
    for (item in values) { target.add(item) }
}
