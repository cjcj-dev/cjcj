package cjcj::codegen

import std.collection.*
import cjcj::chir.Attribute
import cjcj::chir.CheckCustomTypeDefIsExpected
import cjcj::chir.CHIRBuilder
import cjcj::chir.ClassDef
import cjcj::chir.ClassType
import cjcj::chir.Constant
import cjcj::chir.CustomType
import cjcj::chir.EnumType
import cjcj::chir.ExtendDef
import cjcj::chir.ExprKind
import cjcj::chir.Expression
import cjcj::chir.Function
import cjcj::chir.FuncType
import cjcj::chir.GenericType
import cjcj::chir.GetElementRef
import cjcj::chir.GetFieldOfType
import cjcj::chir.IntType
import cjcj::chir.LocalVar
import cjcj::chir.Parameter
import cjcj::chir.RawArrayLiteralInit
import cjcj::chir.ReplaceRawGenericArgType
import cjcj::chir.RefType
import cjcj::chir.Tuple
import cjcj::chir.Type
import cjcj::chir.TypeKind
import cjcj::chir.`VArray` as CHIRVArray
import cjcj::chir.Value
import cjcj::mangle.MANGLE_NESTED_PREFIX
import cjcj::mangle.MANGLE_SUFFIX
import cjcj::option.OSType
import cjcj::utils.CJC_ABORT
import cjcj::utils.{CJC_ASSERT, CORE_PACKAGE_NAME, HashString64, REF_PACKAGE_NAME, STD_LIB_FUTURE,
    STD_LIB_MONITOR, STD_LIB_MUTEX, STD_LIB_WAIT_QUEUE, STD_LIB_WEAK_REF, SYNC_PACKAGE_NAME}

public func GetCodeGenGlobalName(value: Value): String {
    return value.GetIdentifierWithoutPrefix()
}

public func GetInstAbstractMethodTypes(interfaceTy: ClassType,
    builder: CHIRBuilder): ArrayList<(Function, FuncType)> {
    let result = ArrayList<(Function, FuncType)>()
    let typeArgs = interfaceTy.GetGenericArgs()
    let paramArgs = interfaceTy.GetClassDef().GetGenericTypeParams()
    let instMap = HashMap<GenericType, Type>()
    CJC_ASSERT(typeArgs.size == paramArgs.size)
    var idx: Int64 = 0
    while (idx < typeArgs.size) {
        instMap[paramArgs[idx]] = typeArgs[idx]
        idx++
    }
    for (method in interfaceTy.GetClassDef().GetMethods()) {
        let instFuncType = (ReplaceRawGenericArgType(method.GetType().getOrThrow(), instMap, builder) as FuncType).
            getOrThrow()
        result.add((method, instFuncType))
    }
    return result
}

public func GenNameForBB(name: String, extraInfo!: UInt64 = 0u64): String {
    if (extraInfo != 0u64) {
        return name
    }
    return name
}

public func IsFPType(ty: LLVMTypeRef): Bool {
    let kind = unsafe { LLVMGetTypeKind(ty) }
    return kind == 1 || kind == 2 || kind == 3 || kind == 4 || kind == 5 || kind == 6
}

public func UnwindGenericRelateType(llvmCtx: LLVMContextHandle, ty: Type): ArrayList<LLVMMetadataRef> {
    let tyArgMeta = ArrayList<LLVMMetadataRef>()
    if (ty.IsGeneric()) {
        return tyArgMeta
    }
    let typeArgs = ty.GetTypeArgs()
    if (!typeArgs.isEmpty()) {
        tyArgMeta.add(LLVMCreateMDString(llvmCtx, CGType.GetNameOfTypeTemplateGV(ty)))
        let tyArg = typeArgs[0]
        if (tyArg.IsValueType()) {
            tyArgMeta.add(LLVMCreateMDString(llvmCtx, CGType.GetNameOfTypeInfoGV(tyArg)))
        } else {
            let nestedTyArgMeta = UnwindGenericRelateType(llvmCtx, tyArg.StripAllRefs())
            if (!nestedTyArgMeta.isEmpty()) {
                tyArgMeta.add(LLVMCreateMDTuple(llvmCtx, nestedTyArgMeta))
            }
        }
    }
    return tyArgMeta
}

public func GetClassObjLayoutName(className: String): String {
    return "ObjLayout." + className
}

public func IsExternalDefinedType(chirTy: Type): Bool {
    if (!chirTy.IsNominal()) {
        return true
    }
    return (chirTy as CustomType).getOrThrow().GetCustomTypeDef().TestAttr(Attribute.IMPORTED)
}

public func GetOrCreateNamedStructType(context: LLVMContextHandle, name: String): LLVMTypeRef {
    var result = LLVMNullType()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetTypeByName2(context.raw, nameCString.value) }
        if (result.isNull()) {
            result = unsafe { LLVMStructCreateNamed(context.raw, nameCString.value) }
        }
    }
    return result
}

public func GetLLVMStructType(cgMod: CGModule, elementTypes: ArrayList<Type>, name: String): LLVMTypeRef {
    let cgCtx = cgMod.GetCGContext()
    let llvmCtx = cgMod.GetLLVMContext()
    var layoutType = LLVMNullType()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        layoutType = unsafe { LLVMGetTypeByName2(llvmCtx.raw, nameCString.value) }
    }
    if (!layoutType.isNull() && cgCtx.IsGeneratedStructType(name)) {
        return layoutType
    }
    if (layoutType.isNull()) {
        layoutType = GetOrCreateNamedStructType(llvmCtx, name)
    }
    cgCtx.AddGeneratedStructType(name)
    let elemTypes = ArrayList<LLVMTypeRef>()
    for (elemType in elementTypes) {
        elemTypes.add(CGType.GetOrCreate(cgMod, elemType).GetLLVMType())
    }
    SetStructTypeBody(layoutType, elemTypes)
    return layoutType
}

public func SetStructTypeBody(structType: LLVMTypeRef, body: ArrayList<LLVMTypeRef>): Unit {
    if (structType.isNull()) {
        return
    }
    if (body.isEmpty()) {
        unsafe { LLVMStructSetBody(structType, CPointer<LLVMTypeRef>(), 0u32, 0) }
        return
    }
    try (bodyPtr = LibC.malloc<LLVMTypeRef>(count: body.size).asResource()) {
        var idx: Int64 = 0
        while (idx < body.size) {
            unsafe { (bodyPtr.value + idx).write(body[idx]) }
            idx++
        }
        unsafe { LLVMStructSetBody(structType, bodyPtr.value, UInt32(body.size), 0) }
    }
}

public func GetPointerElementType(llvmType: LLVMTypeRef): LLVMTypeRef {
    return unsafe { LLVMGetElementType(llvmType) }
}

public func IsStructPtrType(llvmType: LLVMTypeRef): Bool {
    if (llvmType.isNull() || unsafe { LLVMGetTypeKind(llvmType) } != 12) {
        return false
    }
    let elementType = GetPointerElementType(llvmType)
    return !elementType.isNull() && unsafe { LLVMGetTypeKind(elementType) } == 10
}

public func IsLitStructPtrType(llvmType: LLVMTypeRef): Bool {
    if (llvmType.isNull() || unsafe { LLVMGetTypeKind(llvmType) } != 12) {
        return false
    }
    let elementType = GetPointerElementType(llvmType)
    return !elementType.isNull() && unsafe { LLVMGetTypeKind(elementType) } == 10 &&
        unsafe { LLVMIsLiteralStruct(elementType) } != 0
}

public func IsCommonStruct(chirTy: Type): Bool {
    return chirTy.IsStruct() && !chirTy.IsCPointer() && !chirTy.IsCString()
}

public func IsStructOrExtendMethod(value: Value): Bool {
    let functionValue = (value as Function) ?? return false
    let declaredParent = functionValue.GetParentCustomTypeDef() ?? return false
    if (declaredParent.IsStruct()) {
        return true
    } else if (let Some(extendDef) <- (declaredParent as ExtendDef)) {
        if (let Some(extendedTy) <- extendDef.GetExtendedType()) {
            return extendedTy.IsStruct()
        }
    }
    return false
}

public func AlignedUpTo(offset: UInt64, align: UInt64): UInt64 {
    CJC_ASSERT(align != 0u64)
    return ((offset + align - 1u64) / align) * align
}

public func AlignedUpTo(cgMod: CGModule, offset: UInt64, llvmType: LLVMTypeRef): UInt64 {
    return AlignedUpTo(offset, UInt64(cgMod.GetABITypeAlignment(llvmType)))
}

public func GetTypeSize(cgMod: CGModule, llvmType: LLVMTypeRef): UInt64 {
    return cgMod.GetTypeSize(llvmType)
}

public func GetTypeSize(cgMod: CGModule, chirTy: Type): UInt64 {
    if (chirTy.IsUnit() || chirTy.IsNothing()) {
        return 0u64
    }
    return GetTypeSize(cgMod, CGType.GetOrCreate(cgMod, chirTy).GetLLVMType())
}

public func GetTypeAlignment(cgMod: CGModule, llvmType: LLVMTypeRef): UInt64 {
    return UInt64(cgMod.GetABITypeAlignment(llvmType))
}

public func GetTypeAlignment(cgMod: CGModule, chirTy: Type): UInt64 {
    if (chirTy.IsUnit() || chirTy.IsNothing()) {
        return 1u64
    }
    return GetTypeAlignment(cgMod, CGType.GetOrCreate(cgMod, chirTy).GetLLVMType())
}

public func IsZeroSizedTypeInC(cgMod: CGModule, chirTy: Type): Bool {
    if (chirTy.IsRef()) {
        let typeArgs = chirTy.GetTypeArgs()
        if (!typeArgs.isEmpty()) {
            return IsZeroSizedTypeInC(cgMod, typeArgs[0])
        }
    }
    return chirTy.IsUnit() || chirTy.IsNothing() ||
        (cgMod.GetCGContext().GetCompileOptions().target.os != OSType.WINDOWS &&
            GetTypeSize(cgMod, chirTy) == 0u64)
}

public func FixedCGTypeOfFuncArg(cgMod: CGModule, chirFuncArg: Value, llvmValue: LLVMValueRef): CGType {
    let chirFuncArgType = chirFuncArg.GetType().getOrThrow()
    var cgType = CGType.GetOrCreate(cgMod, chirFuncArgType)
    let byRef = chirFuncArgType.IsStruct() || chirFuncArgType.IsTuple() || chirFuncArgType.IsVArray() ||
        chirFuncArgType.IsUnit() || chirFuncArgType.IsNothing() ||
        (chirFuncArgType.IsEnum() && (CGType.GetOrCreate(cgMod, chirFuncArgType) as CGEnumType).getOrThrow().PassByReference())
    if (byRef) {
        let rawType = unsafe { LLVMTypeOf(llvmValue) }
        let addrspace = if (!rawType.isNull() && unsafe { LLVMGetTypeKind(rawType) } == 12) {
            unsafe { LLVMGetPointerAddressSpace(rawType) }
        } else {
            0u32
        }
        let refType = cgMod.GetCGContext().GetCHIRBuilder().context.GetRefTy(chirFuncArgType)
        cgType = CGType.GetOrCreate(cgMod, refType, extraInfo: TypeExtraInfo(addrspace))
    }
    cgMod.SetOrUpdateMappedCGValue(chirFuncArg, CGValue(llvmValue, cgType))
    return cgType
}

public func MangleName(value: String): String {
    return value.size.toString() + value
}

public func GetMangledNameOfCompilerAddedClass(className: String): String {
    return MANGLE_NESTED_PREFIX + MangleName(className) + MANGLE_SUFFIX
}

public func GetCjStringDataLiteralName(cjStr: String): String {
    return CJSTRING_DATA_PREFIX + HashString64(cjStr)
}

public func GetCjStringLiteralName(cjStr: String): String {
    return CJSTRING_LITERAL_PREFIX + HashString64(cjStr)
}

public func GetConstantTupleName(value: String): String {
    return CONST_TUPLE_PREFIX + HashString64(value)
}

public func GetConstantArrayName(value: String): String {
    return CONST_ARRAY_PREFIX + HashString64(value)
}

public class ArrayCopyToInfo {
    public let srcBP: LLVMValueRef
    public let dstBP: LLVMValueRef
    public let srcArrPtr: LLVMValueRef
    public let dstArrPtr: LLVMValueRef
    public let dataSize: LLVMValueRef
    public let srcIndex: LLVMValueRef
    public let dstIndex: LLVMValueRef
    public let elemType: CGType
    public let elemCnt: LLVMValueRef

    public init(srcBP: LLVMValueRef, dstBP: LLVMValueRef, srcArrPtr: LLVMValueRef, dstArrPtr: LLVMValueRef,
        dataSize: LLVMValueRef, srcIndex: LLVMValueRef, dstIndex: LLVMValueRef, elemType: CGType,
        elemCnt: LLVMValueRef) {
        this.srcBP = srcBP
        this.dstBP = dstBP
        this.srcArrPtr = srcArrPtr
        this.dstArrPtr = dstArrPtr
        this.dataSize = dataSize
        this.srcIndex = srcIndex
        this.dstIndex = dstIndex
        this.elemType = elemType
        this.elemCnt = elemCnt
    }
}

public func ConstantValueToString(expr: Constant): String {
    if (expr.IsBoolLit()) {
        return if (expr.GetBoolLitVal()) { "1" } else { "0" }
    } else if (expr.IsFloatLit()) {
        return expr.GetFloatLitVal().toString()
    } else if (expr.IsSignedIntLit()) {
        return expr.GetSignedIntLitVal().toString()
    } else if (expr.IsUnSignedIntLit()) {
        return expr.GetUnsignedIntLitVal().toString()
    } else if (expr.IsRuneLit()) {
        return UInt32(expr.GetRuneLitVal()).toString()
    } else {
        CJC_ABORT()
        return ""
    }
}

private func IsAllConstantNode(args: ArrayList<Value>): (Bool, String) {
    if (args.isEmpty()) {
        return (false, "")
    }
    var isAllConstantNode = true
    var serialized = ""
    for (node in args) {
        if (!node.IsLocalVar()) {
            isAllConstantNode = false
            break
        }
        let localVar = (node as LocalVar).getOrThrow()
        let maybeExpr = localVar.GetExpr()
        if (let Some(localExpr) <- maybeExpr) {
            if (let Some(constant) <- (localExpr as Constant)) {
                if (constant.IsBoolLit() || constant.IsIntLit() || constant.IsFloatLit() || constant.IsRuneLit()) {
                    serialized += "{" + ConstantValueToString(constant) +
                        localVar.GetType().getOrThrow().ToString() + "}"
                    continue
                }
            }
        }
        let localExpr = maybeExpr.getOrThrow()
        var isEleConstant = false
        var serializedEle = ""
        if (localExpr.GetExprKind() == ExprKind.TUPLE && localVar.GetType().getOrThrow().IsTuple()) {
            let result = IsConstantTuple((localExpr as Tuple).getOrThrow())
            isEleConstant = result[0]
            serializedEle = result[1] + "Tuple"
        } else if (localExpr.GetExprKind() == ExprKind.VARRAY) {
            let result = IsConstantVArray((localExpr as CHIRVArray).getOrThrow())
            isEleConstant = result[0]
            serializedEle = result[1] + "VArray"
        } else {
            isAllConstantNode = false
            break
        }
        if (isEleConstant) {
            serialized += "{" + serializedEle + "}"
            continue
        } else {
            isAllConstantNode = false
            break
        }
    }
    if (!isAllConstantNode) {
        serialized = ""
    }
    return (isAllConstantNode, serialized)
}

public func IsConstantArray(arrayLiteralInit: RawArrayLiteralInit): (Bool, String) {
    return IsAllConstantNode(arrayLiteralInit.GetElements())
}

public func IsConstantVArray(varray: CHIRVArray): (Bool, String) {
    return IsAllConstantNode(varray.GetOperands())
}

public func IsConstantTuple(tuple: Tuple): (Bool, String) {
    return IsAllConstantNode(tuple.GetOperands())
}

public func IsAllConstantValue(args: ArrayList<CGValue>): Bool {
    if (args.isEmpty()) {
        return false
    }
    for (arg in args) {
        if (unsafe { LLVMSelfhostIsConstant(arg.GetRawValue()) } == 0) {
            return false
        }
    }
    return true
}

public func DeRef(chirTy: Type): Type {
    return chirTy.StripAllRefs()
}

public func GetIntMaxOrMin(irBuilder: IRBuilder2, ty: IntType, isMax: Bool): Int64 {
    let minMax = match (irBuilder.GetTypeKindFromType(ty)) {
        case TypeKind.TYPE_INT8 => (Int64(Int8.Min), Int64(Int8.Max))
        case TypeKind.TYPE_INT16 => (Int64(Int16.Min), Int64(Int16.Max))
        case TypeKind.TYPE_INT32 => (Int64(Int32.Min), Int64(Int32.Max))
        case TypeKind.TYPE_INT64 => (Int64.Min, Int64.Max)
        case _ => throw IllegalArgumentException("not a signed integer type")
    }
    return if (isMax) { minMax[1] } else { minMax[0] }
}

public func GetUIntMax(irBuilder: IRBuilder2, ty: IntType): UInt64 {
    return match (irBuilder.GetTypeKindFromType(ty)) {
        case TypeKind.TYPE_UINT8 => UInt64(UInt8.Max)
        case TypeKind.TYPE_UINT16 => UInt64(UInt16.Max)
        case TypeKind.TYPE_UINT32 => UInt64(UInt32.Max)
        case TypeKind.TYPE_UINT64 => UInt64.Max
        case _ => throw IllegalArgumentException("not an unsigned integer type")
    }
}

public func IsGetElementRefOfClass(expr: Expression, builder: CHIRBuilder): Bool {
    if (expr.GetExprKind() != ExprKind.GET_ELEMENT_REF) {
        return false
    }
    let getElementRef = (expr as GetElementRef).getOrThrow()
    var baseType = getElementRef.GetLocation().GetType().getOrThrow().GetTypeArgs()[0]
    let path = getElementRef.GetPath()
    CJC_ASSERT(!path.isEmpty())
    var index: Int64 = 0
    while (index < path.size - 1) {
        baseType = GetFieldOfType(baseType, path[index], builder).getOrThrow()
        index++
    }
    return baseType.IsClass()
}

private func GetGenericArgsFromCHIRTypeHelper(chirTy: Type, path: ArrayList<Int64>,
    result: ArrayList<GenericTypeAndPath>): Unit {
    let baseType = DeRef(chirTy)
    if (let Some(genericType) <- (baseType as GenericType)) {
        result.add(GenericTypeAndPath(genericType, path))
    }
    let args = baseType.GetTypeArgs()
    var index: Int64 = 0
    while (index < args.size) {
        let newPath = path.clone()
        newPath.add(index)
        GetGenericArgsFromCHIRTypeHelper(args[index], newPath, result)
        index++
    }
}

public func GetGenericArgsFromCHIRType(chirTy: Type): ArrayList<GenericTypeAndPath> {
    let result = ArrayList<GenericTypeAndPath>()
    GetGenericArgsFromCHIRTypeHelper(chirTy, ArrayList<Int64>(), result)
    return result
}

public func GetTypeInnerType(chirTy: Type, gtAndPath: GenericTypeAndPath): Type {
    var result = DeRef(chirTy)
    for (path in gtAndPath.GetPath()) {
        result = DeRef(result.GetTypeArgs()[path])
    }
    return result
}

public func IsThisArgOfStructMethod(chirValue: Value): Bool {
    if (!chirValue.IsParameter()) {
        return false
    }
    let chirParam = (chirValue as Parameter) ?? return false
    let chirFunc = chirParam.GetTopLevelFunc() ?? return false
    if (chirFunc.GetNumOfParams() == 0 || chirFunc.GetParam(0) != chirParam) {
        return false
    }
    if (chirFunc.TestAttr(Attribute.STATIC) || !chirFunc.IsStructMethod()) {
        return false
    }
    return true
}

// Type.cpp:66 IsAutoEnv = kind == CLASS && IsClosureConversionEnvClass(classDef).
public func IsAutoEnvType(chirTy: Type): Bool {
    return chirTy.StripAllRefs().IsAutoEnv()
}

// Type.cpp:71 IsAutoEnvBase = IsClosureConversionEnvClass(classDef) && classDef->TestAttr(ABSTRACT).
public func IsAutoEnvBaseType(chirTy: Type): Bool {
    return chirTy.StripAllRefs().IsAutoEnvBase()
}

// Type.cpp:80 IsAutoEnvInstBase = IsAutoEnvBase && argTys.empty().
public func IsAutoEnvInstBaseType(chirTy: Type): Bool {
    return chirTy.StripAllRefs().IsAutoEnvInstBase()
}

public func IsGenericRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsGeneric()
}

public func IsTrivialEnum(chirTy: Type): Bool {
    if (let Some(enumTy) <- (chirTy as EnumType)) {
        return enumTy.GetEnumDef().IsAllCtorsTrivial()
    }
    return false
}

public func IsStructRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsStruct()
}

public func IsStaticStruct(chirTy: Type): Bool {
    return chirTy.IsStruct() && CGType.GetCGGenericKind(chirTy) == CGGenericKind.STATIC_GI
}

public func IsDynamicStruct(chirTy: Type): Bool {
    return chirTy.IsStruct() && CGType.GetCGGenericKind(chirTy) == CGGenericKind.DYNAMIC_GI
}

public func IsDynamicStructRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    if (!chirTy.IsRef() || typeArgs.isEmpty()) {
        return false
    }
    let baseTy = typeArgs[0]
    return baseTy.IsStruct() && CGType.GetCGGenericKind(baseTy) == CGGenericKind.DYNAMIC_GI
}

public func IsClassRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsClass()
}

public func IsStaticClass(chirTy: Type): Bool {
    return chirTy.IsClass() && CGType.GetCGGenericKind(chirTy) == CGGenericKind.STATIC_GI
}

public func IsDynamicClass(chirTy: Type): Bool {
    return chirTy.IsClass() && CGType.GetCGGenericKind(chirTy) == CGGenericKind.DYNAMIC_GI
}

public func IsDynamicClassRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    if (!chirTy.IsRef() || typeArgs.isEmpty()) {
        return false
    }
    let baseTy = typeArgs[0]
    return baseTy.IsClass() && CGType.GetCGGenericKind(baseTy) == CGGenericKind.DYNAMIC_GI
}

public func IsModifiableClass(chirTy: Type): Bool {
    if (!chirTy.IsClass()) {
        return false
    }
    let classDef = (chirTy as ClassType).getOrThrow().GetClassDef()
    return classDef.IsClass() && !classDef.TestAttr(Attribute.COMPILER_ADD) && !classDef.TestAttr(Attribute.VIRTUAL)
}

public func IsCoreFutureClass(classDef: ClassDef): Bool {
    return CheckCustomTypeDefIsExpected(classDef, CORE_PACKAGE_NAME, STD_LIB_FUTURE)
}

public func IsSyncRelatedClass(classDef: ClassDef): Bool {
    return CheckCustomTypeDefIsExpected(classDef, SYNC_PACKAGE_NAME, STD_LIB_MONITOR) ||
        CheckCustomTypeDefIsExpected(classDef, SYNC_PACKAGE_NAME, STD_LIB_MUTEX) ||
        CheckCustomTypeDefIsExpected(classDef, SYNC_PACKAGE_NAME, STD_LIB_WAIT_QUEUE)
}

public func IsWeakRefClass(classDef: ClassDef): Bool {
    return CheckCustomTypeDefIsExpected(classDef, REF_PACKAGE_NAME, STD_LIB_WEAK_REF)
}

public func IsSizeTrustedInCompileUnit(cgMod: CGModule, chirTy: Type): Bool {
    if (!IsModifiableClass(chirTy)) {
        return false
    }
    if (CGType.GetOrCreate(cgMod, chirTy).GetSize().isNone()) {
        return false
    }
    let classDef = (chirTy as ClassType).getOrThrow().GetClassDef()
    let typePackageName = classDef.GetPackageName()
    let compileUnitPkgName = cgMod.GetCGContext().GetCHIRPackage().GetName()
    CJC_ASSERT(!typePackageName.isEmpty() && !compileUnitPkgName.isEmpty())
    var pos: Int64 = 0
    var ch = typePackageName[pos]
    while (ch == compileUnitPkgName[pos]) {
        if (ch == b'.') {
            return true
        }
        pos++
        if (pos == typePackageName.size || pos == compileUnitPkgName.size) {
            return true
        }
        ch = typePackageName[pos]
    }
    return false
}

public func IsVArrayRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsVArray()
}

public func IsUnitOrNothing(chirTy: Type): Bool {
    return chirTy.IsUnit() || chirTy.IsNothing()
}

public func IsReferenceType(ty: Type, cgMod: CGModule): Bool {
    if (let Some(refTy) <- (ty as RefType)) {
        return IsReferenceType(refTy.GetBaseType(), cgMod)
    }
    if (let Some(enumTy) <- (ty as EnumType)) {
        let enumCGType = (CGType.GetOrCreate(cgMod, enumTy) as CGEnumType).getOrThrow()
        return enumCGType.IsCommonEnum() || enumCGType.IsOptionLikeRef() || enumCGType.IsOptionLikeT()
    }
    return ty.IsClass() || ty.IsBox() || ty.IsRawArray()
}
