package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::mangle.BaseMangler
import cjcj::sema.TypeManager
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, OBJ_C_BLOCK_IDENT, OBJ_C_FUNC_IDENT, OBJ_C_FWD_CLASS_SUFFIX,
    OBJ_C_ID_IDENT, OBJ_C_LANG_PACKAGE_IDENT, OBJ_C_POINTER_IDENT}

private let VOID_TYPE: String = "void"
private let UNSUPPORTED_TYPE: String = "UNSUPPORTED_TYPE"
private let INT8_TYPE: String = "int8_t"
private let UINT8_TYPE: String = "uint8_t"
private let INT16_TYPE: String = "int16_t"
private let UINT16_TYPE: String = "uint16_t"
private let INT32_TYPE: String = "int32_t"
private let UINT32_TYPE: String = "uint32_t"
private let INT64_TYPE: String = "int64_t"
private let UINT64_TYPE: String = "uint64_t"
private let NATIVE_INT_TYPE: String = "ssize_t"
private let NATIVE_UINT_TYPE: String = "size_t"
private let FLOAT_TYPE: String = "float"
private let DOUBLE_TYPE: String = "double"
private let BOOL_TYPE: String = "BOOL"
private let STRUCT_TYPE_PREFIX: String = "struct "
private let TYPEDEF_PREFIX: String = "typedef "

public class MappedCType {
    public var usage: String
    public var decl: String

    public init(usage: String, decl!: String = "") {
        this.usage = usage
        this.decl = decl
    }
}

private func MangleTypedefName(name: String): String {
    return name.replace("_", "_1").replace(".", "_")
}

private func IsObjCPointerImpl(structDecl: StructDecl): Bool {
    if (structDecl.fullPackageName != OBJ_C_LANG_PACKAGE_IDENT) { return false }
    if (structDecl.identifier.Val() != OBJ_C_POINTER_IDENT) { return false }
    return true
}

private func IsObjCFuncImpl(structDecl: StructDecl): Bool {
    if (structDecl.fullPackageName != OBJ_C_LANG_PACKAGE_IDENT) { return false }
    if (structDecl.identifier.Val() != OBJ_C_FUNC_IDENT) { return false }
    return true
}

private func IsObjCBlockImpl(decl: ClassDecl): Bool {
    if (decl.fullPackageName != OBJ_C_LANG_PACKAGE_IDENT) { return false }
    if (decl.identifier.Val() != OBJ_C_BLOCK_IDENT) { return false }
    return true
}

private func SupportMembers(decl: Decl, kinds: Array<ASTKind>): Bool {
    for (kind in kinds) { if (decl.astKind == kind) { return true } }
    return false
}

private func IsOpenClassTy(ty: Ty): Bool {
    if (let Some(decl) <- Ty.GetDeclOfTy(ty)) { return decl.astKind == ASTKind.CLASS_DECL && decl.IsOpen() }
    return false
}

private func SupportMemberFunc(decl: Decl, validTy: (Ty) -> Bool): Bool {
    let fnTy = decl.GetTy() as FuncTy
    CJC_NULLPTR_CHECK(fnTy)
    let value = fnTy.getOrThrow()
    let isValid = if (decl.TestAttr(Attribute.CONSTRUCTOR)) { true } else { validTy(value.retTy) }
    if (!isValid) { return false }
    for (paramTy in value.paramTys) { if (!validTy(paramTy)) { return false } }
    return true
}

public class TypeMapper {
    private let bridge: InteropLibBridge
    private let typeManager: TypeManager
    private let mangler: BaseMangler = BaseMangler()

    public init(bridge: InteropLibBridge, typeManager: TypeManager) {
        this.bridge = bridge
        this.typeManager = typeManager
    }

    public func BuildFunctionalCType(funcType: FuncTy, argTypes: ArrayList<Ty>, resultType: Ty, isBlock: Bool,
        toString: (Ty) -> String): MappedCType {
        let typedefNamePrefix = if (isBlock) { "Block" } else { "Func" }
        let designator = if (isBlock) { "^" } else { "*" }
        let mangledName = typedefNamePrefix + MangleTypedefName(mangler.MangleAstSemanticType(funcType))
        var decl = TYPEDEF_PREFIX + toString(resultType) + "(" + designator + mangledName + ")(" 
        for (argType in argTypes) { decl += toString(argType) + "," }
        if (decl.endsWith(",")) { decl = decl[0..decl.size - 1] }
        decl += ")"
        return MappedCType(mangledName, decl: decl)
    }

    public func Cj2CType(cjty: Ty): Ty {
        if (TypeMapper.IsObjCCJMapping(cjty)) {
            let result = bridge.GetRegistryIdTy()
            CJC_NULLPTR_CHECK(result)
            return result.getOrThrow()
        }
        if (TypeMapper.IsObjCObjectType(cjty)) {
            let result = bridge.GetNativeObjCIdTy()
            CJC_NULLPTR_CHECK(result)
            return result.getOrThrow()
        }
        if (TypeMapper.IsObjCPointer(cjty)) {
            CJC_ASSERT(cjty.typeArgs.size == 1)
            return typeManager.GetPointerTy(Cj2CType(cjty.typeArgs[0]))
        }
        if (TypeMapper.IsObjCFunc(cjty)) {
            CJC_ASSERT(cjty.typeArgs.size == 1)
            let actualFuncType = cjty.typeArgs[0] as FuncTy
            CJC_NULLPTR_CHECK(actualFuncType)
            let realTypeArgs = ArrayList<Ty>()
            for (paramTy in actualFuncType.getOrThrow().paramTys) { realTypeArgs.add(Cj2CType(paramTy)) }
            let cfg = FuncTyConfig()
            cfg.isC = true
            return typeManager.GetPointerTy(typeManager.GetFunctionTy(realTypeArgs.toArray(),
                Cj2CType(actualFuncType.getOrThrow().retTy), cfg: cfg))
        }
        if (TypeMapper.IsObjCBlock(cjty)) {
            let result = bridge.GetNativeObjCIdTy()
            CJC_NULLPTR_CHECK(result)
            return result.getOrThrow()
        }
        CJC_ASSERT(cjty.IsBuiltin() || Ty.IsCStructType(cjty) || cjty.IsCFunc())
        return cjty
    }

    public func Cj2ObjCForObjC(from: Ty): MappedCType {
        match (from.kind) {
            case TypeKind.TYPE_UNIT => return MappedCType(VOID_TYPE)
            case TypeKind.TYPE_INT8 => return MappedCType(INT8_TYPE)
            case TypeKind.TYPE_INT16 => return MappedCType(INT16_TYPE)
            case TypeKind.TYPE_INT32 => return MappedCType(INT32_TYPE)
            case TypeKind.TYPE_INT64 | TypeKind.TYPE_IDEAL_INT => return MappedCType(INT64_TYPE)
            case TypeKind.TYPE_INT_NATIVE => return MappedCType(NATIVE_INT_TYPE)
            case TypeKind.TYPE_UINT8 => return MappedCType(UINT8_TYPE)
            case TypeKind.TYPE_UINT16 => return MappedCType(UINT16_TYPE)
            case TypeKind.TYPE_UINT32 => return MappedCType(UINT32_TYPE)
            case TypeKind.TYPE_UINT64 => return MappedCType(UINT64_TYPE)
            case TypeKind.TYPE_UINT_NATIVE => return MappedCType(NATIVE_UINT_TYPE)
            case TypeKind.TYPE_FLOAT32 => return MappedCType(FLOAT_TYPE)
            case TypeKind.TYPE_FLOAT64 | TypeKind.TYPE_IDEAL_FLOAT => return MappedCType(DOUBLE_TYPE)
            case TypeKind.TYPE_BOOLEAN => return MappedCType(BOOL_TYPE)
            case TypeKind.TYPE_STRUCT =>
                if (TypeMapper.IsObjCPointer(from)) { let result = Cj2ObjCForObjC(from.typeArgs[0]); result.usage += "*"; return result }
                if (Ty.IsCStructType(from)) { return MappedCType(STRUCT_TYPE_PREFIX + from.name) }
                if (TypeMapper.IsObjCCJMapping(from)) { return MappedCType(from.name + "*") }
                if (TypeMapper.IsObjCFunc(from)) {
                    let actualFuncType = from.typeArgs[0] as FuncTy
                    if (let Some(value) <- actualFuncType) { return BuildFunctionalCType(value, value.paramTys, value.retTy, false, { ty => Cj2ObjCForObjC(ty).usage }) }
                    return MappedCType(UNSUPPORTED_TYPE)
                }
                CJC_ABORT(); return MappedCType(UNSUPPORTED_TYPE)
            case TypeKind.TYPE_CLASS =>
                if (TypeMapper.IsObjCBlock(from)) {
                    let actualFuncType = from.typeArgs[0] as FuncTy
                    if (let Some(value) <- actualFuncType) { return BuildFunctionalCType(value, value.paramTys, value.retTy, true, { ty => Cj2ObjCForObjC(ty).usage }) }
                    return MappedCType(UNSUPPORTED_TYPE)
                }
                if (TypeMapper.IsObjCObjectType(from)) { return MappedCType(from.name + "*") }
                return MappedCType(UNSUPPORTED_TYPE)
            case TypeKind.TYPE_INTERFACE =>
                if (TypeMapper.IsObjCId(from)) { return MappedCType("id") }
                if (TypeMapper.IsObjCMirror(from) || TypeMapper.IsObjCCJMappingInterface(from)) { return MappedCType("id<" + from.name + ">") }
                return MappedCType(UNSUPPORTED_TYPE)
            case TypeKind.TYPE_POINTER =>
                if (from.typeArgs[0].kind == TypeKind.TYPE_FUNC) { return Cj2ObjCForObjC(from.typeArgs[0]) }
                let result = Cj2ObjCForObjC(from.typeArgs[0]); result.usage += "*"; return result
            case TypeKind.TYPE_FUNC =>
                let actualFuncType = from as FuncTy; CJC_NULLPTR_CHECK(actualFuncType); let value = actualFuncType.getOrThrow()
                return BuildFunctionalCType(value, value.paramTys, value.retTy, false, { ty => Cj2ObjCForObjC(ty).usage })
            case TypeKind.TYPE_ENUM =>
                if (TypeMapper.IsObjCCJMapping(from)) { return MappedCType(from.name + "*") }
                if (!from.IsCoreOptionType()) { CJC_ABORT(); return MappedCType(UNSUPPORTED_TYPE) }
                if (TypeMapper.IsObjCObjectType(from.typeArgs[0])) { return Cj2ObjCForObjC(from.typeArgs[0]) }
                CJC_ABORT(); return MappedCType(UNSUPPORTED_TYPE)
            case _ => CJC_ABORT(); return MappedCType(UNSUPPORTED_TYPE)
        }
    }

    public static func IsObjCCompatible(ty: Ty): Bool {
        if (IsObjCCJMapping(ty)) { return true }
        match (ty.kind) {
            case TypeKind.TYPE_UNIT | TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 |
                TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_IDEAL_INT | TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 |
                TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE | TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 | TypeKind.TYPE_IDEAL_FLOAT |
                TypeKind.TYPE_BOOLEAN => return true
            case TypeKind.TYPE_STRUCT =>
                if (IsObjCPointer(ty)) { CJC_ASSERT(ty.typeArgs.size == 1); return IsObjCCompatible(ty.typeArgs[0]) }
                if (Ty.IsCStructType(ty)) { return true }
                if (IsObjCFunc(ty)) {
                    CJC_ASSERT(ty.typeArgs.size == 1); let tyArg = ty.typeArgs[0]
                    if (!tyArg.IsFunc() || tyArg.IsCFunc()) { return false }
                    for (arg in tyArg.typeArgs) { if (!IsObjCCompatible(arg)) { return false } }
                    return true
                }
                return false
            case TypeKind.TYPE_CLASS | TypeKind.TYPE_INTERFACE =>
                if (IsValidObjCMirror(ty) || IsObjCImpl(ty)) { return true }
                if (IsObjCBlock(ty)) {
                    CJC_ASSERT(ty.typeArgs.size == 1); let tyArg = ty.typeArgs[0]
                    if (!tyArg.IsFunc() || tyArg.IsCFunc()) { return false }
                    for (arg in tyArg.typeArgs) { if (!IsObjCCompatible(arg)) { return false } }
                    return true
                }
                return false
            case TypeKind.TYPE_ENUM =>
                if (!ty.IsCoreOptionType()) { return false }
                CJC_ASSERT(ty.typeArgs.size == 1)
                if (IsValidObjCMirror(ty.typeArgs[0]) || IsObjCImpl(ty.typeArgs[0])) { return true }
            case TypeKind.TYPE_FUNC => if (ty.IsCFunc()) { return true }
            case _ => return false
        }
        return false
    }

    public static func IsObjCMirror(decl: Decl): Bool { return decl.TestAttr(Attribute.OBJ_C_MIRROR) }
    public static func IsSyntheticWrapper(decl: Decl): Bool { return decl.TestAttr(Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER) }
    public static func IsObjCMirrorSubtype(decl: Decl): Bool { let ty = decl.GetTy(); CJC_NULLPTR_CHECK(ty); return IsValidObjCMirrorSubtype(ty.getOrThrow()) }
    public static func IsObjCImpl(decl: Decl): Bool { return decl.TestAttr(Attribute.OBJ_C_MIRROR_SUBTYPE) && !decl.TestAttr(Attribute.OBJ_C_MIRROR) && decl.HasAnno(AstAnnotationKind.OBJ_C_IMPL) }

    public static func IsValidObjCMirror(ty: Ty): Bool {
        let classLikeTy = ty as ClassLikeTy
        if (let None <- classLikeTy) { return false }
        let value = classLikeTy.getOrThrow()
        if (let None <- value.commonDecl) { return false }
        if (!IsObjCMirror(value.commonDecl.getOrThrow())) { return false }
        for (parent in value.GetSuperInterfaceTys()) { if (!IsValidObjCMirror(parent)) { return false } }
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let None <- classTy.GetSuperClassTy()) { return true }
            let superTy = classTy.GetSuperClassTy().getOrThrow()
            if (superTy.IsObject()) { return true }
            return IsValidObjCMirror(superTy)
        }
        return true
    }

    public static func IsValidObjCMirrorSubtype(ty: Ty): Bool {
        let classTy = ty as ClassTy
        if (let None <- classTy) { return false }
        let value = classTy.getOrThrow(); var hasMirrorSuperInterface = false
        for (superInterfaceTy in value.GetSuperInterfaceTys()) { if (!IsValidObjCMirror(superInterfaceTy)) { return false }; hasMirrorSuperInterface = true }
        if (let None <- value.GetSuperClassTy()) { return hasMirrorSuperInterface }
        let superTy = value.GetSuperClassTy().getOrThrow()
        if (superTy.IsObject()) { return hasMirrorSuperInterface }
        return IsValidObjCMirrorSubtype(superTy) || IsValidObjCMirror(superTy)
    }

    public static func IsObjCImpl(ty: Ty): Bool { if (let Some(value) <- (ty as ClassLikeTy)) { if (let Some(decl) <- value.commonDecl) { return IsObjCImpl(decl) } }; return false }
    public static func IsObjCMirror(ty: Ty): Bool { if (let Some(value) <- (ty as ClassLikeTy)) { if (let Some(decl) <- value.commonDecl) { return IsObjCMirror(decl) } }; return false }
    public static func IsSyntheticWrapper(ty: Ty): Bool { if (let Some(value) <- (ty as ClassLikeTy)) { if (let Some(decl) <- value.commonDecl) { return IsSyntheticWrapper(decl) } }; return false }
    public static func IsObjCObjectType(ty: Ty): Bool { if (ty.IsCoreOptionType()) { CJC_ASSERT(ty.typeArgs.size == 1); return IsObjCObjectType(ty.typeArgs[0]) }; return IsObjCMirror(ty) || IsObjCImpl(ty) || IsSyntheticWrapper(ty) || IsObjCCJMapping(ty) || IsObjCCJMappingInterface(ty) }
    public static func IsObjCFwdClass(ty: Ty): Bool { if (let Some(decl) <- Ty.GetDeclOfTy(ty)) { return IsObjCFwdClass(decl) }; return false }
    public static func IsObjCFwdClass4Open(ty: Ty): Bool { if (let Some(decl) <- Ty.GetDeclOfTy(ty)) { return IsObjCFwdClass4Open(decl) }; return false }
    public static func IsObjCPointer(decl: Decl): Bool { if (let Some(value) <- (decl as StructDecl)) { return IsObjCPointerImpl(value) }; return false }
    public static func IsObjCPointer(ty: Ty): Bool { if (let Some(value) <- (ty as StructTy)) { if (let Some(decl) <- value.decl) { return IsObjCPointerImpl(decl) } }; return false }
    public static func IsObjCFunc(decl: Decl): Bool { if (let Some(value) <- (decl as StructDecl)) { return IsObjCFuncImpl(value) }; return false }
    public static func IsObjCFunc(ty: Ty): Bool { if (let Some(value) <- (ty as StructTy)) { if (let Some(decl) <- value.decl) { return IsObjCFuncImpl(decl) } }; return false }
    public static func IsObjCBlock(decl: Decl): Bool { if (let Some(value) <- (decl as ClassDecl)) { return IsObjCBlockImpl(value) }; return false }
    public static func IsObjCBlock(ty: Ty): Bool { if (let Some(value) <- (ty as ClassTy)) { if (let Some(decl) <- value.decl) { return IsObjCBlockImpl(decl) } }; return false }
    public static func IsObjCFuncOrBlock(decl: Decl): Bool { return IsObjCFunc(decl) || IsObjCBlock(decl) }
    public static func IsObjCFuncOrBlock(ty: Ty): Bool { return IsObjCFunc(ty) || IsObjCBlock(ty) }
    public static func IsObjCCJMapping(decl: Decl): Bool { return decl.TestAttr(Attribute.OBJ_C_CJ_MAPPING) && (decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.ENUM_DECL || decl.astKind == ASTKind.CLASS_DECL) }
    public static func IsObjCCJMappingInterface(decl: Decl): Bool { return decl.TestAttr(Attribute.OBJ_C_CJ_MAPPING) && decl.astKind == ASTKind.INTERFACE_DECL }
    public static func IsObjCFwdClass(decl: Decl): Bool { return decl.TestAttr(Attribute.CJ_MIRROR_OBJC_INTERFACE_FWD) }
    public static func IsObjCFwdClass4Open(decl: Decl): Bool { return decl.identifier.Val().contains(OBJ_C_FWD_CLASS_SUFFIX) }
    public static func IsObjCId(ty: Ty): Bool { if (let Some(value) <- (ty as InterfaceTy)) { if (let Some(decl) <- value.declPtr) { return IsObjCId(decl) } }; return false }
    public static func IsObjCId(decl: Decl): Bool { return decl.fullPackageName == OBJ_C_LANG_PACKAGE_IDENT && decl.identifier.Val() == OBJ_C_ID_IDENT }
    public static func IsObjCCJMapping(ty: Ty): Bool { if (let Some(decl) <- Ty.GetDeclOfTy(ty)) { return IsObjCCJMapping(decl) }; return false }
    public static func IsObjCCJMappingInterface(ty: Ty): Bool { if (let Some(decl) <- Ty.GetDeclOfTy(ty)) { return IsObjCCJMappingInterface(decl) }; return false }
    public static func IsOneWayMapping(decl: Decl): Bool { return decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.ENUM_DECL || decl.astKind == ASTKind.CLASS_DECL }

    public static func IsObjCCJMappingMember(decl: Decl): Bool {
        CJC_ASSERT(decl.IsMemberDecl()); let outerDecl = decl.outerDecl; CJC_NULLPTR_CHECK(outerDecl); let outer = outerDecl.getOrThrow(); CJC_ASSERT(IsObjCCJMapping(outer))
        if (!decl.IsOpen() && !decl.TestAttr(Attribute.PUBLIC)) { return false }
        if (decl.IsOpen() && !decl.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)) { return false }
        if (outer.astKind == ASTKind.CLASS_DECL) { if (!SupportMembers(decl, [ASTKind.FUNC_DECL])) { return false }; if (outer.IsOpen() && decl.TestAttr(Attribute.CONSTRUCTOR)) { return false } }
        if (decl.astKind == ASTKind.FUNC_DECL) {
            if (decl.IsOpen()) { return SupportMemberFunc(decl, { ty => IsPrimitiveMapping(ty) }) }
            return SupportMemberFunc(decl, { ty => IsValidCJMapping(ty) && !IsOpenClassTy(ty) })
        }
        if (decl.astKind == ASTKind.PROP_DECL || decl.astKind == ASTKind.VAR_DECL) { let ty = decl.GetTy(); CJC_NULLPTR_CHECK(ty); return IsValidCJMapping(ty.getOrThrow()) }
        return false
    }

    public static func IsOneWayMapping(ty: Ty): Bool { if (!ty.IsStruct() && !ty.IsEnum() && !ty.IsClass()) { return false }; let decl = Ty.GetDeclOfTy(ty); CJC_NULLPTR_CHECK(decl); return IsOneWayMapping(decl.getOrThrow()) }
    public static func IsValidCJMapping(ty: Ty): Bool { return IsPrimitiveMapping(ty) || IsObjCCJMapping(ty) || IsObjCCJMappingInterface(ty) }
    public static func IsPrimitiveMapping(ty: Ty): Bool { return match (ty.kind) { case TypeKind.TYPE_UNIT | TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 | TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_IDEAL_INT | TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 | TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE | TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 | TypeKind.TYPE_IDEAL_FLOAT | TypeKind.TYPE_BOOLEAN | TypeKind.TYPE_GENERICS => true; case _ => false } }
}
