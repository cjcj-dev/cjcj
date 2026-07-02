package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::basic.Linkage as BasicLinkage
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
        let typeParamText = TypeVecToString("<", genericTypeParams, ">", delimiter: ",")
        let paramText = TypeVecToString("", funcType.GetParamTypes(), "", delimiter: ",")
        return funcName + typeParamText + "(" + paramText + ") -> " + funcType.GetReturnType().ToString()
    }

    public func Dump(): Unit {
        println(ToString())
    }
}

public class FuncCallType {
    public var funcName: String
    public var funcType: FuncType
    public let genericTypeArgs: ArrayList<Type> = ArrayList<Type>()

    public init(funcType: FuncType, funcName!: String = "",
        genericTypeArgs!: ArrayList<Type> = ArrayList<Type>()) {
        this.funcName = funcName
        this.funcType = funcType
        for (arg in genericTypeArgs) {
            this.genericTypeArgs.add(arg)
        }
    }

}

public class VirtualMethodInfo {
    private var condition: FuncSigInfo
    private var instance: Option<Function>
    private let attr: AttributeInfo = AttributeInfo()
    private var originalType: FuncType
    private var parentType: Type
    private var returnType: Type

    public init(condition: FuncSigInfo, method: Function, attr: AttributeInfo, originalType: FuncType,
        parentType: Type, returnType: Type) {
        this(condition, Some(method), attr, originalType, parentType, returnType)
    }

    public init(condition: FuncSigInfo, method: Option<Function>, attr: AttributeInfo, originalType: FuncType,
        parentType: Type, returnType: Type) {
        this.condition = condition
        instance = method
        this.attr.CopyFrom(attr)
        this.originalType = originalType
        this.parentType = parentType
        this.returnType = returnType
    }

    public func GetAttributeInfo(): AttributeInfo {
        let out = AttributeInfo()
        out.CopyFrom(attr)
        return out
    }

    public func GetCondition(): FuncSigInfo {
        return condition
    }

    public func GetGenericTypeParams(): ArrayList<GenericType> {
        return condition.GetGenericTypeParams()
    }

    public func GetInstParentType(): Type {
        return parentType
    }

    public func GetMethodInstRetType(): Type {
        return returnType
    }

    public func GetMethodName(): String {
        return condition.funcName
    }

    public func GetMethodSigType(): FuncType {
        return condition.funcType
    }

    public func GetOriginalFuncType(): FuncType {
        return originalType
    }

    public func GetVirtualMethod(): Option<Function> {
        return instance
    }

    public func SetFuncName(newName: String): Unit {
        condition.funcName = newName
    }

    public func SetInstParentType(newParentTy: Type): Unit {
        parentType = newParentTy
    }

    public func SetOriginalFuncType(newFuncType: FuncType): Unit {
        originalType = newFuncType
    }

    public func SetVirtualMethod(newFunc: Option<Function>): Unit {
        instance = newFunc
    }

    public func UpdateMethodInfo(newInfo: VirtualMethodInfo): Unit {
        instance = newInfo.instance
        attr.CopyFrom(newInfo.attr)
        originalType = newInfo.originalType
        parentType = newInfo.parentType
        returnType = newInfo.returnType
    }

    public func ConvertPrivateType(convertFuncParamsAndRetType: (FuncType) -> FuncType,
        convertType: (Type) -> Type): Unit {
        condition.funcType = convertFuncParamsAndRetType(condition.funcType)
        if (let Some(fn) <- instance) {
            fn.SetType(convertFuncParamsAndRetType(fn.GetFuncType().getOrThrow()))
        }
        originalType = convertFuncParamsAndRetType(originalType)
        parentType = convertType(parentType)
        returnType = convertType(returnType)
    }

    public func FuncSigIsMatched(other: FuncSigInfo, builder: CHIRBuilder): Bool {
        let _ = builder
        if (condition.funcName != other.funcName) {
            return false
        }
        let paramTysInMethod = other.funcType.GetParamTypes()
        let paramTysInVtable = condition.funcType.GetParamTypes()
        if (paramTysInVtable.size != paramTysInMethod.size) {
            return false
        }
        if (other.genericTypeParams.size != condition.genericTypeParams.size) {
            return false
        }
        let replaceTable = HashMap<Int64, Type>()
        var idx: Int64 = 0
        while (idx < condition.genericTypeParams.size) {
            replaceTable[other.genericTypeParams[idx].objectId] = condition.genericTypeParams[idx]
            idx++
        }
        var paramIdx: Int64 = 0
        while (paramIdx < paramTysInMethod.size) {
            let paramTyInMethod = ReplaceRawGenericArgType(paramTysInMethod[paramIdx], replaceTable)
            if (!ParamTypeIsEquivalent(paramTyInMethod, paramTysInVtable[paramIdx])) {
                return false
            }
            paramIdx++
        }
        return true
    }

    public func FuncSigIsMatched(other: FuncCallType, replaceTable: HashMap<Int64, Type>,
        builder: CHIRBuilder): Bool {
        let _ = builder
        if (condition.funcName != other.funcName) {
            return false
        }
        let genericParamTys = condition.funcType.GetParamTypes()
        let instArgTys = other.funcType.GetParamTypes()
        if (genericParamTys.size != instArgTys.size) {
            return false
        }
        let genericTypeParams = condition.GetGenericTypeParams()
        let funcInstTypeArgs = other.genericTypeArgs
        if (genericTypeParams.size != funcInstTypeArgs.size) {
            return false
        }
        let localReplaceTable = HashMap<Int64, Type>()
        for ((key, value) in replaceTable) {
            localReplaceTable[key] = value
        }
        var idx: Int64 = 0
        while (idx < genericTypeParams.size) {
            localReplaceTable[genericTypeParams[idx].objectId] = funcInstTypeArgs[idx]
            idx++
        }
        var paramIdx: Int64 = 0
        while (paramIdx < genericParamTys.size) {
            let declaredInstType = ReplaceRawGenericArgType(genericParamTys[paramIdx], localReplaceTable)
            if (!ParamTypeIsEquivalent(declaredInstType, instArgTys[paramIdx])) {
                return false
            }
            paramIdx++
        }
        return true
    }

    public func TestAttr(attr: Attribute): Bool {
        return this.attr.Test(attr)
    }
}

public class VTableInType {
    private var srcParentType: Option<ClassType> = None
    private let genericConstraints: HashMap<Int64, HashSet<Int64>> = HashMap<Int64, HashSet<Int64>>()
    private let virtualMethods: ArrayList<VirtualMethodInfo> = ArrayList<VirtualMethodInfo>()

    public init() {}

    public init(parentType: ClassType) {
        srcParentType = parentType
    }

    public init(parentType: ClassType, methods: ArrayList<VirtualMethodInfo>) {
        srcParentType = parentType
        for (method in methods) {
            virtualMethods.add(method)
        }
    }

    public func GetMethodNum(): Int64 {
        return virtualMethods.size
    }

    public func GetModifiableVirtualMethods(): ArrayList<VirtualMethodInfo> {
        return virtualMethods
    }

    public func GetSrcParentType(): Option<ClassType> {
        return srcParentType
    }

    public func GetVirtualMethods(): ArrayList<VirtualMethodInfo> {
        let out = ArrayList<VirtualMethodInfo>()
        for (method in virtualMethods) {
            out.add(method)
        }
        return out
    }

    public func AppendNewMethod(newMethod: VirtualMethodInfo): Unit {
        virtualMethods.add(newMethod)
    }

    public func ConvertPrivateType(convertFuncParamsAndRetType: (FuncType) -> FuncType,
        convertType: (Type) -> Type): Unit {
        if (let Some(parentTy) <- srcParentType) {
            srcParentType = (convertType(parentTy) as ClassType).getOrThrow()
        }
        for (method in virtualMethods) {
            method.ConvertPrivateType(convertFuncParamsAndRetType, convertType)
        }
    }

    public func IsEmpty(): Bool {
        return srcParentType.isNone()
    }
}

public class VTableInDef {
    private var srcParentIndex: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let vtables: ArrayList<VTableInType> = ArrayList<VTableInType>()
    private let empty: VTableInType = VTableInType()

    public init() {}

    public func GetExpectedTypeVTable(srcParentType: ClassType): VTableInType {
        if (let Some(index) <- srcParentIndex.get(srcParentType.objectId)) {
            return vtables[index]
        }
        return empty
    }

    public func GetModifiableTypeVTables(): ArrayList<VTableInType> {
        return vtables
    }

    public func GetTypeVTables(): ArrayList<VTableInType> {
        let out = ArrayList<VTableInType>()
        for (vtable in vtables) {
            out.add(vtable)
        }
        return out
    }

    public func AddNewItemToTypeVTable(srcParent: ClassType, funcInfo: VirtualMethodInfo): Unit {
        if (let Some(index) <- srcParentIndex.get(srcParent.objectId)) {
            vtables[index].AppendNewMethod(funcInfo)
        } else {
            vtables.add(VTableInType(srcParent))
            srcParentIndex[srcParent.objectId] = vtables.size - 1
            vtables[vtables.size - 1].AppendNewMethod(funcInfo)
        }
    }

    public func AddNewItemToTypeVTable(srcParent: ClassType, funcInfos: ArrayList<VirtualMethodInfo>): Unit {
        CJC_ASSERT(!srcParentIndex.contains(srcParent.objectId))
        vtables.add(VTableInType(srcParent, funcInfos))
        srcParentIndex[srcParent.objectId] = vtables.size - 1
    }

    public func UpdateItemInTypeVTable(srcClassTy: ClassType, index: Int64, newFunc: Option<Function>,
        newParentTy: Option<Type>, newName: String): Unit {
        for (vtableIt in vtables) {
            let srcParentType = vtableIt.GetSrcParentType() ?? continue
            if (srcParentType.objectId != srcClassTy.objectId) {
                continue
            }
            let methodInfo = vtableIt.GetModifiableVirtualMethods()[index]
            methodInfo.SetVirtualMethod(newFunc)
            if (let Some(fn) <- newFunc) {
                methodInfo.SetOriginalFuncType(fn.GetFuncType().getOrThrow())
            }
            if (let Some(parentTy) <- newParentTy) {
                methodInfo.SetInstParentType(parentTy)
            }
            if (!newName.isEmpty()) {
                methodInfo.SetFuncName(newName)
            }
        }
    }

    public func ConvertPrivateType(convertFuncParamsAndRetType: (FuncType) -> FuncType,
        convertType: (Type) -> Type): Unit {
        for (vtable in vtables) {
            vtable.ConvertPrivateType(convertFuncParamsAndRetType, convertType)
        }
        let newTypeMap = HashMap<Int64, Int64>()
        for ((_, value) in srcParentIndex) {
            let srcParentType = vtables[value].GetSrcParentType().getOrThrow()
            newTypeMap[srcParentType.objectId] = value
        }
        srcParentIndex = newTypeMap
    }
}

public class VTableSearchRes {
    public var instSrcParentType: Option<ClassType> = None
    public var halfInstSrcParentType: Option<ClassType> = None
    public var originalFuncType: Option<FuncType> = None
    public var instance: Option<Function> = None
    public var originalDef: Option<CustomTypeDef> = None
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    public var attr: AttributeInfo = AttributeInfo()
    public var offset: UInt64 = 0u64

    public init() {}
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
    private var vtable: VTableInDef = VTableInDef()
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
        return methods.clone()
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

    public func GetDefVTable(): VTableInDef {
        return vtable
    }

    public func GetModifiableDefVTable(): VTableInDef {
        return vtable
    }

    public func SetVTable(table: VTableInDef): Unit {
        vtable = table
    }

    public func UpdateVtableItem(srcClassTy: ClassType, index: Int64, newFunc: Option<Function>,
        newParentTy: Option<Type>, newName: String): Unit {
        vtable.UpdateItemInTypeVTable(srcClassTy, index, newFunc, newParentTy, newName)
    }

    public func AddVtableItem(srcClassTy: ClassType, info: VirtualMethodInfo): Unit {
        for (vtableIt in vtable.GetModifiableTypeVTables()) {
            let srcParentType = vtableIt.GetSrcParentType() ?? continue
            if (srcParentType.objectId == srcClassTy.objectId) {
                vtableIt.AppendNewMethod(info)
            }
        }
    }

    public func GetGenericDecl(): Option<CustomTypeDef> {
        return genericDecl
    }

    public func SetGenericDecl(decl: CustomTypeDef): Unit {
        genericDecl = decl
    }

    public func SetLinkTypeInfo(linkType: BasicLinkage): Unit {
        SetAnnotation("LinkTypeInfo", LinkTypeInfoToString(linkType))
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

    public func VTableToString(indent: Int64): String {
        let vtables = vtable.GetTypeVTables()
        if (vtables.isEmpty()) {
            return ""
        }
        var curIndent = indent
        var out = IndentToString(curIndent) + "vtable {\n"
        curIndent++
        for (vtableInType in vtables) {
            let srcParentType = vtableInType.GetSrcParentType() ?? continue
            out += IndentToString(curIndent) + srcParentType.ToString() + " {\n"
            curIndent++
            for (funcInfo in vtableInType.GetVirtualMethods()) {
                out += IndentToString(curIndent) + "@" + funcInfo.GetMethodName()
                out += ": " + funcInfo.GetOriginalFuncType().ToString()
                if (let Some(fn) <- funcInfo.GetVirtualMethod()) {
                    out += "=> " + fn.GetIdentifier()
                }
                out += "\n"
            }
            curIndent--
            out += IndentToString(curIndent) + "}\n"
        }
        curIndent--
        out += IndentToString(curIndent) + "}"
        return out
    }

    public open func ToString(indent: Int64): String {
        let vtableText = VTableToString(indent + 1)
        if (vtableText.isEmpty()) {
            return IndentToString(indent) + GetFullName()
        }
        return IndentToString(indent) + GetFullName() + "\n" + vtableText
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

private func LinkTypeInfoToString(linkType: BasicLinkage): String {
    let linkToString = match (linkType) {
        case BasicLinkage.EXTERNAL => "external"
        case BasicLinkage.WEAK_ODR => "weak_odr"
        case BasicLinkage.INTERNAL => "internal"
        case BasicLinkage.LINKONCE_ODR => "linkonce_odr"
        case BasicLinkage.EXTERNAL_WEAK => "external_weak"
    }
    return "linkType: " + linkToString
}

private func ParamTypeIsEquivalent(paramType: Type, argType: Type): Bool {
    if (paramType.objectId == argType.objectId) {
        return true
    }
    if (argType.IsNothing()) {
        return true
    }
    if (IsBoxRefTypeOf(argType, paramType) || IsBoxRefTypeOf(paramType, argType)) {
        return true
    }
    return MeetAutoEnvBase(argType.StripAllRefs(), paramType.StripAllRefs())
}

private func IsBoxRefTypeOf(ty: Type, baseType: Type): Bool {
    if (!ty.IsRef()) {
        return false
    }
    let refTy = (ty as RefType).getOrThrow()
    let boxType = refTy.GetBaseType()
    if (!boxType.IsBox()) {
        return false
    }
    return (boxType as BoxType).getOrThrow().GetBaseType().objectId == baseType.objectId
}

private func MeetAutoEnvBase(subType: Type, superType: Type): Bool {
    if (!IsAutoEnvInstBase(subType) || !IsAutoEnvGenericBase(superType)) {
        return false
    }
    let subClassTy = (subType as ClassType) ?? return false
    let superClassTy = (superType as ClassType) ?? return false
    let subSuperTy = subClassTy.GetClassDef().GetSuperClassTy() ?? return false
    return subSuperTy.objectId == superClassTy.objectId
}

private func IsAutoEnvInstBase(ty: Type): Bool {
    if (let Some(customTy) <- (ty as CustomType)) {
        let def = customTy.GetCustomTypeDef()
        return def.GetAnnotation("IsAutoEnvClass").isSome() && def.TestAttr(Attribute.ABSTRACT) &&
            customTy.GetGenericArgs().isEmpty()
    }
    return false
}

private func IsAutoEnvGenericBase(ty: Type): Bool {
    if (let Some(customTy) <- (ty as CustomType)) {
        let def = customTy.GetCustomTypeDef()
        return def.GetAnnotation("IsAutoEnvClass").isSome() && def.TestAttr(Attribute.ABSTRACT) &&
            !customTy.GetGenericArgs().isEmpty()
    }
    return false
}
