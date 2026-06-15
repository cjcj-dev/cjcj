package cangjie_compiler::chir

import std.collection.*

public class MemberVarInfo {
    public var name: String
    public var ty: Type
    public var isStatic: Bool
    public var isReadOnly: Bool

    public init(name: String, ty: Type, isStatic!: Bool = false, isReadOnly!: Bool = false) {
        this.name = name
        this.ty = ty
        this.isStatic = isStatic
        this.isReadOnly = isReadOnly
    }
}

public class FuncSigInfo {
    public var funcType: FuncType
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()

    public init(funcType: FuncType) {
        this.funcType = funcType
    }
}

public open class CustomTypeDef <: Base {
    public let packageName: String
    public let identifier: String
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    private let instanceVars: ArrayList<MemberVarInfo> = ArrayList<MemberVarInfo>()
    private let methods: ArrayList<Function> = ArrayList<Function>()
    private let extends: ArrayList<ExtendDef> = ArrayList<ExtendDef>()

    public init(packageName: String, identifier: String) {
        super()
        this.packageName = packageName
        this.identifier = identifier
    }

    public func GetIdentifier(): String {
        return identifier
    }

    public func GetPackageName(): String {
        return packageName
    }

    public func GetFullName(): String {
        if (packageName.isEmpty()) {
            return identifier
        }
        return packageName + "." + identifier
    }

    public func AddGenericTypeParam(param: GenericType): Unit {
        genericTypeParams.add(param)
    }

    public func AddInstanceVar(info: MemberVarInfo): Unit {
        instanceVars.add(info)
    }

    public func GetInstanceVars(): ArrayList<MemberVarInfo> {
        let out = ArrayList<MemberVarInfo>()
        for (info in instanceVars) {
            out.add(info)
        }
        return out
    }

    public func AddMethod(method: Function): Unit {
        if (!ContainsFunction(methods, method)) {
            methods.add(method)
            method.SetOuterDeclaredOrExtendedDef(this)
        }
    }

    public func GetMethods(): ArrayList<Function> {
        return CopyFunctionList(methods)
    }

    public func AddExtend(extendDef: ExtendDef): Unit {
        extends.add(extendDef)
    }

    public func GetExtends(): ArrayList<ExtendDef> {
        let out = ArrayList<ExtendDef>()
        for (extendDef in extends) {
            out.add(extendDef)
        }
        return out
    }

    public open func ToString(indent: Int64): String {
        return IndentToString(indent) + GetFullName()
    }

    public func ToString(): String {
        return ToString(0)
    }
}

private func ContainsFunction(values: ArrayList<Function>, method: Function): Bool {
    for (value in values) {
        if (value.nodeId == method.nodeId) {
            return true
        }
    }
    return false
}

public class StructDef <: CustomTypeDef {
    public init(packageName: String, identifier: String) {
        super(packageName, identifier)
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "struct " + GetFullName()
    }
}

public class ClassDef <: CustomTypeDef {
    private var superClassDef: Option<ClassDef> = None
    private let implementedInterfaceDefs: ArrayList<ClassDef> = ArrayList<ClassDef>()

    public init(packageName: String, identifier: String) {
        super(packageName, identifier)
    }

    public func SetSuperClassDef(def: ClassDef): Unit {
        superClassDef = def
    }

    public func GetSuperClassDef(): Option<ClassDef> {
        return superClassDef
    }

    public func AddImplementedInterfaceDef(def: ClassDef): Unit {
        implementedInterfaceDefs.add(def)
    }

    public func GetImplementedInterfaceDefs(): ArrayList<ClassDef> {
        let out = ArrayList<ClassDef>()
        for (def in implementedInterfaceDefs) {
            out.add(def)
        }
        return out
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "class " + GetFullName()
    }
}

public class EnumCtorInfo {
    public let name: String
    public let payloadTypes: ArrayList<Type> = ArrayList<Type>()

    public init(name: String, payloadTypes: ArrayList<Type>) {
        this.name = name
        for (ty in payloadTypes) {
            this.payloadTypes.add(ty)
        }
    }
}

public class EnumDef <: CustomTypeDef {
    private let ctors: ArrayList<EnumCtorInfo> = ArrayList<EnumCtorInfo>()

    public init(packageName: String, identifier: String) {
        super(packageName, identifier)
    }

    public func AddCtor(info: EnumCtorInfo): Unit {
        ctors.add(info)
    }

    public func GetCtors(): ArrayList<EnumCtorInfo> {
        let out = ArrayList<EnumCtorInfo>()
        for (ctor in ctors) {
            out.add(ctor)
        }
        return out
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "enum " + GetFullName()
    }
}

public class ExtendDef <: CustomTypeDef {
    public var extendedType: Option<Type> = None

    public init(packageName: String, identifier: String) {
        super(packageName, identifier)
    }

    public init(packageName: String, identifier: String, extendedType: Type) {
        super(packageName, identifier)
        this.extendedType = extendedType
    }

    public override func ToString(indent: Int64): String {
        let target = if (let Some(ty) <- extendedType) { ty.ToString() } else { "<unknown>" }
        return IndentToString(indent) + "extend " + target
    }
}
