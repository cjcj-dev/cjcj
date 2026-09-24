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
private let CHAR_PTR_TYPE: String = "char*"
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

public class TypeMapper {
    private let bridge: InteropLibBridge
    private let typeManager: TypeManager

    public init(bridge: InteropLibBridge, typeManager: TypeManager) {
        this.bridge = bridge
        this.typeManager = typeManager
    }

    public static func BuildFunctionalCType(funcType: FuncTy, argTypes: ArrayList<Ty>, resultType: Ty, isBlock: Bool,
        toString: (Ty) -> String): MappedCType {
        let typedefNamePrefix = if (isBlock) { "Block" } else { "Func" }
        let designator = if (isBlock) { "^" } else { "*" }
        let mangler = BaseMangler()
        let mangledName = typedefNamePrefix + MangleTypedefName(mangler.MangleAstSemanticType(funcType))
        var decl = TYPEDEF_PREFIX + toString(resultType) + "(" + designator + mangledName + ")(" 
        for (argType in argTypes) { decl += toString(argType) + "," }
        if (decl.endsWith(",")) { decl = decl[0..decl.size - 1] }
        decl += ")"
        return MappedCType(mangledName, decl: decl)
    }

    public func Cj2CType(cjty: Ty): Ty {
        if (IsObjCCJMapping(cjty)) {
            let result = bridge.GetRegistryIdTy()
            CJC_NULLPTR_CHECK(result)
            return result.getOrThrow()
        }
        if (IsObjCObjectType(cjty)) {
            let result = bridge.GetNativeObjCIdTy()
            CJC_NULLPTR_CHECK(result)
            return result.getOrThrow()
        }
        if (IsObjCPointer(cjty)) {
            CJC_ASSERT(cjty.typeArgs.size == 1)
            return typeManager.GetPointerTy(Cj2CType(cjty.typeArgs[0]))
        }
        if (IsObjCFunc(cjty)) {
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
        if (IsObjCBlock(cjty)) {
            let result = bridge.GetNativeObjCIdTy()
            CJC_NULLPTR_CHECK(result)
            return result.getOrThrow()
        }
        CJC_ASSERT(cjty.IsBuiltin() || Ty.IsCStructType(cjty) || cjty.IsCFunc())
        return cjty
    }

    public static func Cj2ObjCForObjC(from: Ty): MappedCType {
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
            case TypeKind.TYPE_CSTRING => return MappedCType(CHAR_PTR_TYPE)
            case TypeKind.TYPE_STRUCT =>
                if (IsObjCPointer(from)) { let result = Cj2ObjCForObjC(from.typeArgs[0]); result.usage += "*"; return result }
                if (Ty.IsCStructType(from)) { return MappedCType(STRUCT_TYPE_PREFIX + from.name) }
                if (IsObjCCJMapping(from)) { return MappedCType(from.name + "*") }
                if (IsObjCFunc(from)) {
                    let actualFuncType = from.typeArgs[0] as FuncTy
                    if (let Some(value) <- actualFuncType) { return BuildFunctionalCType(value, value.paramTys, value.retTy, false, { ty => Cj2ObjCForObjC(ty).usage }) }
                    return MappedCType(UNSUPPORTED_TYPE)
                }
                CJC_ABORT(); return MappedCType(UNSUPPORTED_TYPE)
            case TypeKind.TYPE_CLASS =>
                if (IsObjCBlock(from)) {
                    let actualFuncType = from.typeArgs[0] as FuncTy
                    if (let Some(value) <- actualFuncType) { return BuildFunctionalCType(value, value.paramTys, value.retTy, true, { ty => Cj2ObjCForObjC(ty).usage }) }
                    return MappedCType(UNSUPPORTED_TYPE)
                }
                if (IsObjCObjectType(from)) {
                    let decl = Ty.GetDeclOfTy(from)
                    CJC_NULLPTR_CHECK(decl)
                    if (let Some(userDefinedName) <- NameGenerator.GetUserDefinedObjCName(decl.getOrThrow())) {
                        return MappedCType(userDefinedName + "*")
                    }
                    return MappedCType(from.name + "*")
                }
                return MappedCType(UNSUPPORTED_TYPE)
            case TypeKind.TYPE_INTERFACE =>
                if (IsObjCId(from)) { return MappedCType("id") }
                if (IsObjCMirror(from) || IsObjCCJMappingInterface(from)) { return MappedCType("id<" + from.name + ">") }
                return MappedCType(UNSUPPORTED_TYPE)
            case TypeKind.TYPE_POINTER =>
                if (from.typeArgs[0].kind == TypeKind.TYPE_FUNC) { return Cj2ObjCForObjC(from.typeArgs[0]) }
                let result = Cj2ObjCForObjC(from.typeArgs[0]); result.usage += "*"; return result
            case TypeKind.TYPE_FUNC =>
                let actualFuncType = from as FuncTy; CJC_NULLPTR_CHECK(actualFuncType); let value = actualFuncType.getOrThrow()
                return BuildFunctionalCType(value, value.paramTys, value.retTy, false, { ty => Cj2ObjCForObjC(ty).usage })
            case TypeKind.TYPE_ENUM =>
                if (IsObjCCJMapping(from)) { return MappedCType(from.name + "*") }
                if (!from.IsCoreOptionType()) { CJC_ABORT(); return MappedCType(UNSUPPORTED_TYPE) }
                if (IsObjCObjectType(from.typeArgs[0])) { return Cj2ObjCForObjC(from.typeArgs[0]) }
                CJC_ABORT(); return MappedCType(UNSUPPORTED_TYPE)
            case _ => CJC_ABORT(); return MappedCType(UNSUPPORTED_TYPE)
        }
    }

}
