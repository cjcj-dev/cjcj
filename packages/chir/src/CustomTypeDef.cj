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
            let paramTyInMethod = ReplaceRawGenericArgType(paramTysInMethod[paramIdx], replaceTable, builder)
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
            let declaredInstType = ReplaceRawGenericArgType(genericParamTys[paramIdx], localReplaceTable, builder)
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
        if ((this as ExtendDef).isSome()) {
            for (param in genericTypeParams) {
                out.add(param)
            }
            return out
        }
        if (TestAttr(Attribute.GENERIC)) {
            let customTy = (GetType().getOrThrow() as CustomType).getOrThrow()
            for (arg in customTy.GetGenericArgs()) {
                out.add((arg as GenericType).getOrThrow())
            }
        }
        return out
    }

    public func GetGenericTypeParamsRef(): ArrayList<GenericType> {
        return genericTypeParams
    }

    public func IsGenericDef(): Bool {
        return !GetGenericTypeParams().isEmpty()
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

    public func GetSuperTypesRecusively(builder: CHIRBuilder): ArrayList<ClassType> {
        let inheritanceList = ArrayList<ClassType>()
        for (interfaceTy in GetImplementedInterfaceTys()) {
            GetAllInstantiatedParentType(interfaceTy, builder, inheritanceList)
        }
        if (IsClassLike()) {
            let classDef = (this as ClassDef).getOrThrow()
            if (let Some(superClass) <- classDef.GetSuperClassTy()) {
                GetAllInstantiatedParentType(superClass, builder, inheritanceList)
            }
        }
        return inheritanceList
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

    public func GetExpectedFunc(funcName: String, funcType: FuncType, isStatic: Bool,
        replaceTable: HashMap<Int64, Type>, funcInstTypeArgs: ArrayList<Type>, builder: CHIRBuilder,
        checkAbstractMethod: Bool): Option<Function> {
        CJC_ASSERT(!funcName.isEmpty())
        let instParamTys = funcType.GetParamTypes()
        if (!isStatic) {
            CJC_ASSERT(!instParamTys.isEmpty())
            instParamTys.remove(at: 0)
        }
        var foundFunc: Option<Function> = None
        for (method in methods) {
            if (isStatic != method.TestAttr(Attribute.STATIC)) {
                continue
            }
            var methodName = method.GetSrcCodeIdentifier()
            if (let Some(rawMethod) <- method.GetWrappedRawMethod()) {
                methodName = rawMethod.GetSrcCodeIdentifier()
            }
            if (methodName != funcName) {
                continue
            }
            let originalFuncParamTys = method.GetFuncType().getOrThrow().GetParamTypes()
            if (!method.TestAttr(Attribute.STATIC)) {
                CJC_ASSERT(!originalFuncParamTys.isEmpty())
                originalFuncParamTys.remove(at: 0)
            }
            if (originalFuncParamTys.size != instParamTys.size) {
                continue
            }
            let genericTypeParams = method.GetGenericTypeParams()
            if (genericTypeParams.size != funcInstTypeArgs.size) {
                continue
            }
            let localReplaceTable = HashMap<Int64, Type>()
            for ((key, value) in replaceTable) {
                localReplaceTable[key] = value
            }
            var genericIdx: Int64 = 0
            while (genericIdx < genericTypeParams.size) {
                localReplaceTable[genericTypeParams[genericIdx].objectId] = funcInstTypeArgs[genericIdx]
                genericIdx++
            }
            var matched = true
            var paramIdx: Int64 = 0
            while (paramIdx < originalFuncParamTys.size) {
                let instType = ReplaceRawGenericArgType(originalFuncParamTys[paramIdx], localReplaceTable, builder)
                if (!instParamTys[paramIdx].IsGeneric() && !instType.IsEqual(instParamTys[paramIdx])) {
                    matched = false
                    break
                }
                paramIdx++
            }
            if (matched) {
                if (let Some(rawFunc) <- method.GetWrappedRawMethod()) {
                    if (let Some(rawParent) <- rawFunc.GetParentCustomTypeDef()) {
                        if (rawParent.nodeId == nodeId) {
                            foundFunc = rawFunc
                        } else {
                            foundFunc = method
                        }
                    } else {
                        foundFunc = method
                    }
                } else {
                    foundFunc = method
                }
                break
            }
        }
        let result = foundFunc ?? return None
        if (!checkAbstractMethod && result.TestAttr(Attribute.ABSTRACT)) {
            return None
        }
        let _ = builder
        return result
    }

    public func GetFuncIndexInVTable(funcCallType: FuncCallType, replaceTable: HashMap<Int64, Type>,
        builder: CHIRBuilder): ArrayList<VTableSearchRes> {
        let res = ArrayList<VTableSearchRes>()
        let candidateTypes = ArrayList<FuncType>()
        for (vtableIt in vtable.GetTypeVTables()) {
            var methodIdx: Int64 = 0
            while (methodIdx < vtableIt.GetMethodNum()) {
                let funcInfo = vtableIt.GetVirtualMethods()[methodIdx]
                if (funcInfo.FuncSigIsMatched(funcCallType, replaceTable, builder)) {
                    let originalParentType = vtableIt.GetSrcParentType().getOrThrow()
                    let instSrcParentTy = ReplaceRawGenericArgType(originalParentType, replaceTable, builder)
                    let item = VTableSearchRes()
                    item.instSrcParentType = (instSrcParentTy as ClassType).getOrThrow()
                    item.halfInstSrcParentType = originalParentType
                    item.originalFuncType = funcInfo.GetOriginalFuncType()
                    item.instance = funcInfo.GetVirtualMethod()
                    item.originalDef = this
                    for (genericParam in funcInfo.GetGenericTypeParams()) {
                        item.genericTypeParams.add(genericParam)
                    }
                    item.attr = funcInfo.GetAttributeInfo()
                    item.offset = UInt64(methodIdx)
                    res.add(item)
                    let instTy = ReplaceRawGenericArgType(funcInfo.GetCondition().funcType, replaceTable, builder)
                    candidateTypes.add((instTy as FuncType).getOrThrow())
                }
                methodIdx++
            }
        }
        return GetWellMatchingResults(res, candidateTypes, builder)
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

private func GetWellMatchingResults(candidateRes: ArrayList<VTableSearchRes>, candidateTypes: ArrayList<FuncType>,
    builder: CHIRBuilder): ArrayList<VTableSearchRes> {
    if (candidateRes.size <= 1) {
        return candidateRes.clone()
    }
    CJC_ASSERT(candidateRes.size == candidateTypes.size)
    let candidateNum = candidateTypes.size
    let targetMark = ArrayList<Bool>()
    var markIdx: Int64 = 0
    while (markIdx < candidateNum) {
        targetMark.add(true)
        markIdx++
    }
    var idx: Int64 = 0
    while (idx < candidateNum) {
        if (!targetMark[idx]) {
            idx++
            continue
        }
        var nextIdx = idx + 1
        while (nextIdx < candidateNum) {
            if (!targetMark[nextIdx]) {
                nextIdx++
                continue
            }
            let iToJ = candidateTypes[idx].IsEqualOrInstantiatedTypeOf(candidateTypes[nextIdx], builder)
            let jToI = candidateTypes[nextIdx].IsEqualOrInstantiatedTypeOf(candidateTypes[idx], builder)
            if (iToJ && !jToI) {
                targetMark[nextIdx] = false
            } else if (!iToJ && jToI) {
                targetMark[idx] = false
                break
            }
            nextIdx++
        }
        idx++
    }
    let result = ArrayList<VTableSearchRes>()
    let instances = HashSet<Int64>()
    var resIdx: Int64 = 0
    while (resIdx < candidateNum) {
        if (targetMark[resIdx]) {
            result.add(candidateRes[resIdx])
            if (let Some(fn) <- candidateRes[resIdx].instance) {
                instances.add(fn.nodeId)
            } else {
                instances.add(0)
            }
        }
        resIdx++
    }
    CJC_ASSERT(!result.isEmpty())
    CJC_ASSERT(instances.size == 1)
    return result
}

private func CollectGenericReplaceTable(mayBeGeneric: Type, instType: Type,
    replaceTable: HashMap<Int64, Type>): Unit {
    if (let Some(genericType) <- (mayBeGeneric as GenericType)) {
        if (!replaceTable.contains(genericType.objectId)) {
            replaceTable[genericType.objectId] = instType
        }
    } else {
        let genericTypeArgs = mayBeGeneric.GetTypeArgs()
        let instTypeArgs = instType.GetTypeArgs()
        if (genericTypeArgs.size != instTypeArgs.size) {
            return
        }
        var typeIdx: Int64 = 0
        while (typeIdx < genericTypeArgs.size) {
            CollectGenericReplaceTable(genericTypeArgs[typeIdx], instTypeArgs[typeIdx], replaceTable)
            typeIdx++
        }
    }
}

public func GetFuncIndexInVTable(root: Type, funcCallType: FuncCallType,
    builder: CHIRBuilder): ArrayList<VTableSearchRes> {
    var result = ArrayList<VTableSearchRes>()
    if (let Some(genericTy) <- (root as GenericType)) {
        let upperBounds = genericTy.GetUpperBounds()
        CJC_ASSERT(!upperBounds.isEmpty())
        for (upperBound in upperBounds) {
            let upperClassType = ((upperBound as RefType).getOrThrow().GetBaseType() as ClassType).getOrThrow()
            result = GetFuncIndexInVTable(upperClassType, funcCallType, builder)
            if (!result.isEmpty()) {
                break
            }
        }
    } else if (let Some(customTy) <- (root as CustomType)) {
        let replaceTable = HashMap<Int64, Type>()
        let classInstArgs = customTy.GetTypeArgs()
        let classGenericArgs = customTy.GetCustomTypeDef().GetGenericTypeParams()
        if (!classGenericArgs.isEmpty()) {
            CJC_ASSERT(classInstArgs.size == classGenericArgs.size)
        }
        var genericIdx: Int64 = 0
        while (genericIdx < classGenericArgs.size) {
            replaceTable[classGenericArgs[genericIdx].objectId] = classInstArgs[genericIdx]
            genericIdx++
        }
        result = customTy.GetCustomTypeDef().GetFuncIndexInVTable(funcCallType, replaceTable, builder)
        if (!result.isEmpty()) {
            return result
        }
        for (extendDef in customTy.GetCustomTypeDef().GetExtends()) {
            replaceTable.clear()
            let extendedTyGenericArgs = extendDef.GetExtendedType().getOrThrow().GetTypeArgs()
            CJC_ASSERT(classInstArgs.size == extendedTyGenericArgs.size)
            var typeIdx: Int64 = 0
            while (typeIdx < classInstArgs.size) {
                CollectGenericReplaceTable(extendedTyGenericArgs[typeIdx], classInstArgs[typeIdx], replaceTable)
                typeIdx++
            }
            result = extendDef.GetFuncIndexInVTable(funcCallType, replaceTable, builder)
            if (!result.isEmpty()) {
                return result
            }
        }
    } else {
        let empty = HashMap<Int64, Type>()
        let extendDefs = root.GetExtends(builder)
        CJC_ASSERT(!extendDefs.isEmpty())
        for (extendDef in extendDefs) {
            result = extendDef.GetFuncIndexInVTable(funcCallType, empty, builder)
            if (!result.isEmpty()) {
                break
            }
        }
    }
    return result
}

public func TypeIsMatched(type1: Type, type2: Type): Bool {
    if (type1.GetTypeKind() != type2.GetTypeKind()) {
        return false
    }
    let typeArgs1 = type1.GetTypeArgs()
    let typeArgs2 = type2.GetTypeArgs()
    if (typeArgs1.size != typeArgs2.size) {
        return false
    }
    var typeIdx: Int64 = 0
    while (typeIdx < typeArgs1.size) {
        if (!TypeIsMatched(typeArgs1[typeIdx], typeArgs2[typeIdx])) {
            return false
        }
        typeIdx++
    }
    return true
}

public func VirMethodTypeIsMatched(type1: FuncType, type2: FuncType): Bool {
    let type1ParamTypes = type1.GetParamTypes()
    let type2ParamTypes = type2.GetParamTypes()
    if (type1ParamTypes.size != type2ParamTypes.size) {
        return false
    }
    var paramIdx: Int64 = 0
    while (paramIdx < type1ParamTypes.size) {
        if (!VirMethodParamTypeIsMatched(type1ParamTypes[paramIdx], type2ParamTypes[paramIdx])) {
            return false
        }
        paramIdx++
    }
    return VirMethodReturnTypeIsMatched(type1.GetReturnType(), type2.GetReturnType())
}

public func VirMethodParamTypeIsMatched(type1: Type, type2: Type): Bool {
    if ((type1.IsGeneric() || type1.IsRef() || type1.IsCJFunc()) &&
        (type2.IsGeneric() || type2.IsRef() || type2.IsCJFunc())) {
        return true
    }
    return TypeIsMatched(type1, type2)
}

public func VirMethodReturnTypeIsMatched(type1: Type, type2: Type): Bool {
    if (type1.IsGeneric() && type2.IsGeneric()) {
        return true
    }
    if ((type1.IsRef() || type1.IsCJFunc()) && (type2.IsRef() || type2.IsCJFunc())) {
        return true
    }
    return TypeIsMatched(type1, type2)
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
    if (paramType.IsEqual(argType)) {
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
    return (boxType as BoxType).getOrThrow().GetBaseType().IsEqual(baseType)
}

private func MeetAutoEnvBase(subType: Type, superType: Type): Bool {
    if (!IsAutoEnvInstBase(subType) || !IsAutoEnvGenericBase(superType)) {
        return false
    }
    let subClassTy = (subType as ClassType) ?? return false
    let superClassTy = (superType as ClassType) ?? return false
    let subSuperTy = subClassTy.GetClassDef().GetSuperClassTy() ?? return false
    return subSuperTy.IsEqual(superClassTy)
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
