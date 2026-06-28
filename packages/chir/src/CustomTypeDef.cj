package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::utils.CJC_ASSERT

public class MemberVarInfo {
    public var name: String
    public var rawMangledName: String
    public var ty: Type
    public var attributeInfo: AttributeInfo = AttributeInfo()
    public var loc: DebugLocation = DebugLocation()
    public var annoInfo: AnnoInfo = AnnoInfo()
    public var initializerFunc: Option<Function> = None
    public var outerDef: Option<CustomTypeDef> = None
    public var isStatic: Bool
    public var isReadOnly: Bool

    public init(name: String, ty: Type, isStatic!: Bool = false, isReadOnly!: Bool = false,
        rawMangledName!: String = "") {
        this.name = name
        this.rawMangledName = rawMangledName
        this.ty = ty
        this.isStatic = isStatic
        this.isReadOnly = isReadOnly
        if (isStatic) {
            attributeInfo.Enable(Attribute.STATIC)
        }
        if (isReadOnly) {
            attributeInfo.Enable(Attribute.READONLY)
        }
    }

    public func TestAttr(attr: Attribute): Bool {
        return attributeInfo.Test(attr)
    }

    public func IsImmutable(): Bool {
        return isReadOnly || attributeInfo.Test(Attribute.READONLY) || attributeInfo.Test(Attribute.CONST)
    }
}

public class FuncSigInfo {
    public var funcName: String
    public var funcType: FuncType
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()

    public init(funcType: FuncType, funcName!: String = "",
        genericTypeParams!: ArrayList<GenericType> = ArrayList<GenericType>()) {
        this.funcName = funcName
        this.funcType = funcType
        for (param in genericTypeParams) {
            this.genericTypeParams.add(param)
        }
    }

    public func GetGenericTypeParams(): ArrayList<GenericType> {
        let out = ArrayList<GenericType>()
        for (param in genericTypeParams) {
            out.add(param)
        }
        return out
    }

    public func ToString(): String {
        let typeParamText = GenericTypeParamsToString(genericTypeParams)
        let paramText = TypeListKey(funcType.GetParamTypes())
        return funcName + typeParamText + "(" + paramText + ") -> " + funcType.GetReturnType().ToString()
    }

    public func Dump(): Unit {
        println(ToString())
    }
}

public open class CustomTypeDef <: Base {
    private let customKind: CustomDefKind
    public let packageName: String
    public let identifier: String
    private var srcCodeIdentifier: String
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    private var customType: Option<CustomType> = None
    private var genericDecl: Option<CustomTypeDef> = None
    private let instanceVars: ArrayList<MemberVarInfo> = ArrayList<MemberVarInfo>()
    private let staticVars: ArrayList<GlobalVar> = ArrayList<GlobalVar>()
    private let methods: ArrayList<Function> = ArrayList<Function>()
    protected let implementedInterfaceTys: ArrayList<ClassType> = ArrayList<ClassType>()
    private let extends: ArrayList<ExtendDef> = ArrayList<ExtendDef>()
    private var varInitializationFunc: Option<Function> = None
    private var annoInfo: AnnoInfo = AnnoInfo()

    public init(packageName: String, identifier: String) {
        this(packageName, identifier, identifier, CustomDefKind.TYPE_STRUCT)
    }

    public init(packageName: String, identifier: String, srcCodeIdentifier: String, kind: CustomDefKind) {
        super()
        this.customKind = kind
        this.packageName = packageName
        this.identifier = identifier
        this.srcCodeIdentifier = srcCodeIdentifier
    }

    public func GetCustomKind(): CustomDefKind {
        return customKind
    }

    public func GetIdentifier(): String {
        return identifier
    }

    public func GetIdentifierWithoutPrefix(): String {
        if (identifier.size > 0 && identifier[0] == b'_') {
            return identifier[1..]
        }
        return identifier
    }

    public func GetSrcCodeIdentifier(): String {
        return srcCodeIdentifier
    }

    public func SetSrcCodeIdentifier(name: String): Unit {
        srcCodeIdentifier = name
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

    public open func GetType(): Option<Type> {
        if (let Some(ty) <- customType) {
            return ty
        }
        return None
    }

    public open func SetType(ty: CustomType): Unit {
        customType = ty
    }

    public open func GetGenericTypeParams(): ArrayList<GenericType> {
        let out = ArrayList<GenericType>()
        for (param in genericTypeParams) {
            out.add(param)
        }
        return out
    }

    public func GetGenericTypeParamsRef(): ArrayList<GenericType> {
        return genericTypeParams
    }

    public func IsGenericDef(): Bool {
        return !genericTypeParams.isEmpty()
    }

    public open func IsClass(): Bool {
        if (!IsClassLike()) {
            return false
        }
        if (let Some(classDef) <- (this as ClassDef)) {
            return classDef.IsClass()
        }
        return false
    }

    public func IsClassLike(): Bool {
        return customKind == CustomDefKind.TYPE_CLASS
    }

    public func IsEnum(): Bool {
        return customKind == CustomDefKind.TYPE_ENUM
    }

    public func IsExtend(): Bool {
        return customKind == CustomDefKind.TYPE_EXTEND
    }

    public open func IsInterface(): Bool {
        if (!IsClassLike()) {
            return false
        }
        if (let Some(classDef) <- (this as ClassDef)) {
            return classDef.IsInterface()
        }
        return false
    }

    public func IsStruct(): Bool {
        return customKind == CustomDefKind.TYPE_STRUCT
    }

    public func AddImplementedInterfaceTy(interfaceTy: ClassType): Unit {
        let interfaceDef = interfaceTy.GetClassDef()
        CJC_ASSERT(interfaceDef.IsInterface())
        implementedInterfaceTys.add(interfaceTy)
    }

    public open func GetImplementedInterfaceDefs(): ArrayList<ClassDef> {
        let out = ArrayList<ClassDef>()
        for (interfaceTy in implementedInterfaceTys) {
            let interfaceDef = interfaceTy.GetClassDef()
            if (!ContainsClassDef(out, interfaceDef)) {
                out.add(interfaceDef)
            }
        }
        return out
    }

    public func GetImplementedInterfaceTys(): ArrayList<ClassType> {
        let out = ArrayList<ClassType>()
        for (interfaceTy in implementedInterfaceTys) {
            out.add(interfaceTy)
        }
        return out
    }

    public func GetImplementedInterfacesNum(): Int64 {
        return implementedInterfaceTys.size
    }

    public func GetSuperTypesInCurDef(): ArrayList<ClassType> {
        let out = ArrayList<ClassType>()
        if (let Some(classDef) <- (this as ClassDef)) {
            if (let Some(superClassTy) <- classDef.GetSuperClassTy()) {
                out.add(superClassTy)
            }
        }
        for (interfaceTy in implementedInterfaceTys) {
            out.add(interfaceTy)
        }
        return out
    }

    public func AddInstanceVar(info: MemberVarInfo): Unit {
        info.outerDef = this
        instanceVars.add(info)
    }

    public func GetInstanceVars(): ArrayList<MemberVarInfo> {
        return GetAllInstanceVars()
    }

    public func GetAllInstanceVars(): ArrayList<MemberVarInfo> {
        let out = ArrayList<MemberVarInfo>()
        if (let Some(classDef) <- (this as ClassDef)) {
            if (let Some(superDef) <- classDef.GetSuperClassDef()) {
                for (info in superDef.GetAllInstanceVars()) {
                    out.add(info)
                }
            }
        }
        for (info in instanceVars) {
            out.add(info)
        }
        return out
    }

    public func GetAllInstanceVarNum(): Int64 {
        return GetAllInstanceVars().size
    }

    public func GetInstanceVar(index: Int64): MemberVarInfo {
        return GetAllInstanceVars()[index]
    }

    public func GetDirectInstanceVarNum(): Int64 {
        return instanceVars.size
    }

    public func GetDirectInstanceVar(index: Int64): MemberVarInfo {
        return instanceVars[index]
    }

    public func GetDirectInstanceVars(): ArrayList<MemberVarInfo> {
        let out = ArrayList<MemberVarInfo>()
        for (info in instanceVars) {
            out.add(info)
        }
        return out
    }

    public func SetDirectInstanceVars(vars: ArrayList<MemberVarInfo>): Unit {
        instanceVars.clear()
        for (info in vars) {
            AddInstanceVar(info)
        }
    }

    public func AddStaticMemberVar(variable: GlobalVar): Unit {
        staticVars.add(variable)
        variable.SetOuterDeclaredOrExtendedDef(this)
    }

    public func GetStaticMemberVars(): ArrayList<GlobalVar> {
        let out = ArrayList<GlobalVar>()
        for (variable in staticVars) {
            out.add(variable)
        }
        return out
    }

    public func SetStaticMemberVars(vars: ArrayList<GlobalVar>): Unit {
        staticVars.clear()
        for (variable in vars) {
            AddStaticMemberVar(variable)
        }
    }

    public func GetVarInitializationFunc(): Option<Function> {
        return varInitializationFunc
    }

    public func SetVarInitializationFunc(fn: Function): Unit {
        varInitializationFunc = fn
    }

    public func AddMethod(method: Function): Unit {
        methods.add(method)
        method.SetOuterDeclaredOrExtendedDef(this)
    }

    public func GetMethods(): ArrayList<Function> {
        return CopyFunctionList(methods)
    }

    public func SetMethods(items: ArrayList<Function>): Unit {
        methods.clear()
        for (item in items) {
            AddMethod(item)
        }
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

    public func GetGenericDecl(): Option<CustomTypeDef> {
        return genericDecl
    }

    public func SetGenericDecl(decl: CustomTypeDef): Unit {
        genericDecl = decl
    }

    public func CanBeInherited(): Bool {
        return IsInterface() || TestAttr(Attribute.VIRTUAL) || TestAttr(Attribute.ABSTRACT)
    }

    public func GetAnnoInfo(): AnnoInfo {
        return annoInfo
    }

    public func SetAnnoInfo(info: AnnoInfo): Unit {
        annoInfo = info
    }

    protected open func AddExtraComment(): String {
        return ""
    }

    public open func ToString(indent: Int64): String {
        return IndentToString(indent) + GetFullName()
    }

    public func ToString(): String {
        return ToString(0)
    }
}

private func ContainsClassDef(values: ArrayList<ClassDef>, classDef: ClassDef): Bool {
    for (value in values) {
        if (value.nodeId == classDef.nodeId) {
            return true
        }
    }
    return false
}
