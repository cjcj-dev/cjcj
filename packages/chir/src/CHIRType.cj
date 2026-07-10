package cjcj::chir

import std.collection.*

import cjcj::ast.Ty as AstTy
import cjcj::ast.TypeKind as AstTypeKind
import cjcj::ast.TupleTy as AstTupleTy
import cjcj::ast.FuncTy as AstFuncTy
import cjcj::ast.ArrayTy as AstArrayTy
import cjcj::ast.VArrayTy as AstVArrayTy
import cjcj::ast.PointerTy as AstPointerTy
import cjcj::ast.Decl as AstDecl
import cjcj::ast.ClassDecl as AstClassDecl
import cjcj::ast.StructDecl as AstStructDecl
import cjcj::ast.InterfaceDecl as AstInterfaceDecl
import cjcj::ast.EnumDecl as AstEnumDecl
import cjcj::ast.GenericParamDecl as AstGenericParamDecl
import cjcj::ast.ClassTy as AstClassTy
import cjcj::ast.StructTy as AstStructTy
import cjcj::ast.InterfaceTy as AstInterfaceTy
import cjcj::ast.EnumTy as AstEnumTy
import cjcj::ast.GenericsTy as AstGenericsTy

public class CHIRTypeCacheEntry {
    public let astTy: AstTy
    public var chirTy: Type

    public init(astTy: AstTy, chirTy: Type) {
        this.astTy = astTy
        this.chirTy = chirTy
    }
}

public class CHIRNominalCacheEntry {
    public let decl: AstDecl
    public var def: CustomTypeDef

    public init(decl: AstDecl, def: CustomTypeDef) {
        this.decl = decl
        this.def = def
    }
}

public class CHIRTypeCache {
    public let typeMap: ArrayList<CHIRTypeCacheEntry> = ArrayList<CHIRTypeCacheEntry>()
    public let globalNominalCache: ArrayList<CHIRNominalCacheEntry> = ArrayList<CHIRNominalCacheEntry>()
    private let typeIndex: HashMap<Int64, CHIRTypeCacheEntry> = HashMap<Int64, CHIRTypeCacheEntry>()
    private let nominalIndex: HashMap<Int64, CHIRNominalCacheEntry> = HashMap<Int64, CHIRNominalCacheEntry>()

    public init() {}

    public func TryGetType(ty: AstTy): Option<Type> {
        if (let Some(entry) <- typeIndex.get(ty.objectId)) {
            return entry.chirTy
        }
        return None
    }

    public func SetType(ty: AstTy, chirTy: Type): Unit {
        if (let Some(entry) <- typeIndex.get(ty.objectId)) {
            entry.chirTy = chirTy
            return
        }
        let entry = CHIRTypeCacheEntry(ty, chirTy)
        typeIndex[ty.objectId] = entry
        typeMap.add(entry)
    }

    public func TryGetNominal(decl: AstDecl): Option<CustomTypeDef> {
        if (let Some(entry) <- nominalIndex.get(decl.objectId)) {
            return entry.def
        }
        return None
    }

    public func SetNominal(decl: AstDecl, def: CustomTypeDef): Unit {
        if (let Some(entry) <- nominalIndex.get(decl.objectId)) {
            entry.def = def
            return
        }
        let entry = CHIRNominalCacheEntry(decl, def)
        nominalIndex[decl.objectId] = entry
        globalNominalCache.add(entry)
    }
}

public class CHIRType {
    private let builder: CHIRBuilder
    private let chirTypeCache: CHIRTypeCache

    public init(builder: CHIRBuilder, typeCache: CHIRTypeCache) {
        this.builder = builder
        this.chirTypeCache = typeCache
    }

    public func FillGenericArgType(ty: AstGenericsTy): Unit {
        let cachedType = chirTypeCache.TryGetType(ty) ??
            throw IllegalStateException("generic AST type has not been translated: ${ty.String()}")
        if (let Some(genericType) <- (cachedType as GenericType)) {
            let chirUpperBounds = ArrayList<Type>()
            for (argTy in ty.upperBounds) {
                if (argTy.IsGeneric()) {
                    throw IllegalStateException("generic upper bound should have been resolved before FillGenericArgType")
                }
                chirUpperBounds.add(TranslateType(argTy))
            }
            genericType.SetUpperBounds(chirUpperBounds)
            return
        }
        throw IllegalStateException("translated generic AST type is not CHIR GenericType")
    }

    public func SetGlobalNominalCache(decl: AstDecl, def: CustomTypeDef): Unit {
        chirTypeCache.SetNominal(decl, def)
    }

    public func GetGlobalNominalCache(decl: AstDecl): CustomTypeDef {
        return chirTypeCache.TryGetNominal(decl) ??
            throw IllegalStateException("nominal declaration is not registered in CHIRType cache: ${decl.identifier.Val()}")
    }

    public func TryGetGlobalNominalCache(decl: AstDecl): Option<CustomTypeDef> {
        return chirTypeCache.TryGetNominal(decl)
    }

    public func Has(decl: AstDecl): Bool {
        return chirTypeCache.TryGetNominal(decl).isSome()
    }

    public func GetAllTypeDef(): ArrayList<CHIRNominalCacheEntry> {
        return chirTypeCache.globalNominalCache
    }

    public func GetTypeMap(): ArrayList<CHIRTypeCacheEntry> {
        return chirTypeCache.typeMap
    }

    public func GetGlobalNominalCache(): ArrayList<CHIRNominalCacheEntry> {
        return chirTypeCache.globalNominalCache
    }

    public func TranslateType(ty: AstTy): Type {
        if (let Some(cached) <- chirTypeCache.TryGetType(ty)) {
            return cached
        }

        var translatedType = match (ty.kind) {
            case AstTypeKind.TYPE_UNIT => builder.context.GetUnitTy()
            case AstTypeKind.TYPE_INT8 => builder.context.GetInt8Ty()
            case AstTypeKind.TYPE_INT16 => builder.context.GetInt16Ty()
            case AstTypeKind.TYPE_INT32 => builder.context.GetInt32Ty()
            case AstTypeKind.TYPE_INT64 => builder.context.GetInt64Ty()
            case AstTypeKind.TYPE_INT_NATIVE => builder.context.GetIntNativeTy()
            case AstTypeKind.TYPE_IDEAL_INT => builder.context.GetInt64Ty()
            case AstTypeKind.TYPE_UINT8 => builder.context.GetUInt8Ty()
            case AstTypeKind.TYPE_UINT16 => builder.context.GetUInt16Ty()
            case AstTypeKind.TYPE_UINT32 => builder.context.GetUInt32Ty()
            case AstTypeKind.TYPE_UINT64 => builder.context.GetUInt64Ty()
            case AstTypeKind.TYPE_UINT_NATIVE => builder.context.GetUIntNativeTy()
            case AstTypeKind.TYPE_FLOAT16 => builder.context.GetFloat16Ty()
            case AstTypeKind.TYPE_FLOAT32 => builder.context.GetFloat32Ty()
            case AstTypeKind.TYPE_FLOAT64 => builder.context.GetFloat64Ty()
            case AstTypeKind.TYPE_IDEAL_FLOAT => builder.context.GetFloat64Ty()
            case AstTypeKind.TYPE_RUNE => builder.context.GetRuneTy()
            case AstTypeKind.TYPE_BOOLEAN => builder.context.GetBoolTy()
            case AstTypeKind.TYPE_TUPLE => TranslateTupleType(RequireTupleTy(ty))
            case AstTypeKind.TYPE_FUNC => TranslateFuncType(RequireFuncTy(ty))
            case AstTypeKind.TYPE_ENUM => TranslateEnumType(RequireEnumTy(ty))
            case AstTypeKind.TYPE_STRUCT => TranslateStructType(RequireStructTy(ty))
            case AstTypeKind.TYPE_CLASS => TranslateClassType(RequireClassTy(ty))
            case AstTypeKind.TYPE_INTERFACE => TranslateInterfaceType(RequireInterfaceTy(ty))
            case AstTypeKind.TYPE_ARRAY => TranslateArrayType(RequireArrayTy(ty))
            case AstTypeKind.TYPE_VARRAY => TranslateVArrayType(RequireVArrayTy(ty))
            case AstTypeKind.TYPE_POINTER => TranslateCPointerType(RequirePointerTy(ty))
            case AstTypeKind.TYPE_NOTHING => builder.context.GetNothingType()
            case AstTypeKind.TYPE_CSTRING => builder.context.GetCStringTy()
            case AstTypeKind.TYPE_GENERICS => TranslateGenericType(RequireGenericsTy(ty))
            case _ => throw IllegalArgumentException("unsupported AST type kind for CHIRType.TranslateType: ${ty.String()}")
        }

        if (translatedType.IsClassOrArray() || translatedType.IsBox()) {
            translatedType = builder.context.GetRefTy(translatedType)
        }
        chirTypeCache.SetType(ty, translatedType)
        return translatedType
    }

    private func TranslateTupleType(tupleTy: AstTupleTy): Type {
        let argTys = ArrayList<Type>()
        for (argTy in tupleTy.typeArgs) {
            argTys.add(TranslateType(argTy))
        }
        return builder.context.GetTupleTy(argTys)
    }

    private func TranslateFuncType(fnTy: AstFuncTy): Type {
        let retTy = TranslateType(fnTy.retTy)
        let paramTys = ArrayList<Type>()
        for (paramTy in fnTy.paramTys) {
            var paramType = TranslateType(paramTy)
            if (fnTy.IsCFunc() && paramType.IsVArray()) {
                paramType = builder.context.GetRefTy(paramType)
            }
            paramTys.add(paramType)
        }
        return builder.context.GetFuncTy(paramTys, retTy, hasVarLenParam: fnTy.hasVariableLenArg,
            isCFunc: fnTy.IsCFunc())
    }

    private func TranslateStructType(structTy: AstStructTy): Type {
        let typeArgs = TranslateTypeArgs(structTy.typeArgs)
        let def = RequireStructDef(GetGlobalNominalCache(RequireStructDecl(structTy)))
        let structType = builder.context.GetStructTy(def, typeArgs)
        chirTypeCache.SetType(structTy, structType)
        return structType
    }

    private func TranslateClassType(classTy: AstClassTy): Type {
        let typeArgs = TranslateTypeArgs(classTy.typeArgs)
        let def = RequireClassDef(GetGlobalNominalCache(RequireClassDecl(classTy)))
        let classType = builder.context.GetClassTy(def, typeArgs)
        chirTypeCache.SetType(classTy, classType)
        return classType
    }

    private func TranslateInterfaceType(interfaceTy: AstInterfaceTy): Type {
        let typeArgs = TranslateTypeArgs(interfaceTy.typeArgs)
        let def = RequireClassDef(GetGlobalNominalCache(RequireInterfaceDecl(interfaceTy)))
        let classType = builder.context.GetClassTy(def, typeArgs)
        chirTypeCache.SetType(interfaceTy, classType)
        return classType
    }

    private func TranslateEnumType(enumTy: AstEnumTy): Type {
        let typeArgs = TranslateTypeArgs(enumTy.typeArgs)
        let def = RequireEnumDef(GetGlobalNominalCache(RequireEnumDecl(enumTy)))
        let enumType = builder.context.GetEnumTy(def, typeArgs)
        chirTypeCache.SetType(enumTy, enumType)
        return enumType
    }

    private func TranslateArrayType(arrayTy: AstArrayTy): Type {
        if (arrayTy.typeArgs.isEmpty()) {
            throw IllegalArgumentException("RawArray AST type has no element type")
        }
        let elementTy = TranslateType(arrayTy.typeArgs[0])
        return builder.context.GetRawArrayTy(elementTy, dims: arrayTy.dims)
    }

    private func TranslateVArrayType(varrayTy: AstVArrayTy): Type {
        if (varrayTy.typeArgs.isEmpty()) {
            throw IllegalArgumentException("VArray AST type has no element type")
        }
        if (varrayTy.size < 0) {
            throw IllegalArgumentException("VArray AST type has negative size")
        }
        let elementTy = TranslateType(varrayTy.typeArgs[0])
        return builder.context.GetVArrayTy(elementTy, UInt64(varrayTy.size))
    }

    private func TranslateCPointerType(pointerTy: AstPointerTy): Type {
        if (pointerTy.typeArgs.isEmpty()) {
            throw IllegalArgumentException("CPointer AST type has no element type")
        }
        let elementTy = TranslateType(pointerTy.typeArgs[0])
        return builder.context.GetCPointerTy(elementTy)
    }

    private func TranslateGenericType(genericTy: AstGenericsTy): Type {
        let genericDecl = RequireGenericDecl(genericTy)
        if (genericDecl.mangledName.isEmpty()) {
            throw IllegalStateException("generic declaration has no mangledName: ${genericTy.name}")
        }
        return builder.context.GetGenericTy(genericDecl.mangledName, genericTy.name)
    }

    private func TranslateTypeArgs(astArgs: ArrayList<AstTy>): ArrayList<Type> {
        let typeArgs = ArrayList<Type>()
        for (arg in astArgs) {
            typeArgs.add(TranslateType(arg))
        }
        return typeArgs
    }

    private func RequireTupleTy(ty: AstTy): AstTupleTy {
        if (let Some(tupleTy) <- (ty as AstTupleTy)) {
            return tupleTy
        }
        throw IllegalArgumentException("expected TupleTy, got ${ty.String()}")
    }

    private func RequireFuncTy(ty: AstTy): AstFuncTy {
        if (let Some(funcTy) <- (ty as AstFuncTy)) {
            return funcTy
        }
        throw IllegalArgumentException("expected FuncTy, got ${ty.String()}")
    }

    private func RequireArrayTy(ty: AstTy): AstArrayTy {
        if (let Some(arrayTy) <- (ty as AstArrayTy)) {
            return arrayTy
        }
        throw IllegalArgumentException("expected ArrayTy, got ${ty.String()}")
    }

    private func RequireVArrayTy(ty: AstTy): AstVArrayTy {
        if (let Some(varrayTy) <- (ty as AstVArrayTy)) {
            return varrayTy
        }
        throw IllegalArgumentException("expected VArrayTy, got ${ty.String()}")
    }

    private func RequirePointerTy(ty: AstTy): AstPointerTy {
        if (let Some(pointerTy) <- (ty as AstPointerTy)) {
            return pointerTy
        }
        throw IllegalArgumentException("expected PointerTy, got ${ty.String()}")
    }

    private func RequireClassTy(ty: AstTy): AstClassTy {
        if (let Some(classTy) <- (ty as AstClassTy)) {
            return classTy
        }
        throw IllegalArgumentException("expected ClassTy, got ${ty.String()}")
    }

    private func RequireStructTy(ty: AstTy): AstStructTy {
        if (let Some(structTy) <- (ty as AstStructTy)) {
            return structTy
        }
        throw IllegalArgumentException("expected StructTy, got ${ty.String()}")
    }

    private func RequireInterfaceTy(ty: AstTy): AstInterfaceTy {
        if (let Some(interfaceTy) <- (ty as AstInterfaceTy)) {
            return interfaceTy
        }
        throw IllegalArgumentException("expected InterfaceTy, got ${ty.String()}")
    }

    private func RequireEnumTy(ty: AstTy): AstEnumTy {
        if (let Some(enumTy) <- (ty as AstEnumTy)) {
            return enumTy
        }
        throw IllegalArgumentException("expected EnumTy, got ${ty.String()}")
    }

    private func RequireGenericsTy(ty: AstTy): AstGenericsTy {
        if (let Some(genericTy) <- (ty as AstGenericsTy)) {
            return genericTy
        }
        throw IllegalArgumentException("expected GenericsTy, got ${ty.String()}")
    }

    private func RequireClassDecl(ty: AstClassTy): AstClassDecl {
        if (let Some(decl) <- ty.declPtr) {
            return decl
        }
        throw IllegalStateException("ClassTy has no declPtr: ${ty.String()}")
    }

    private func RequireStructDecl(ty: AstStructTy): AstStructDecl {
        if (let Some(decl) <- ty.declPtr) {
            return decl
        }
        throw IllegalStateException("StructTy has no declPtr: ${ty.String()}")
    }

    private func RequireInterfaceDecl(ty: AstInterfaceTy): AstInterfaceDecl {
        if (let Some(decl) <- ty.declPtr) {
            return decl
        }
        throw IllegalStateException("InterfaceTy has no declPtr: ${ty.String()}")
    }

    private func RequireEnumDecl(ty: AstEnumTy): AstEnumDecl {
        if (let Some(decl) <- ty.declPtr) {
            return decl
        }
        throw IllegalStateException("EnumTy has no declPtr: ${ty.String()}")
    }

    private func RequireGenericDecl(ty: AstGenericsTy): AstGenericParamDecl {
        if (let Some(decl) <- ty.decl) {
            return decl
        }
        throw IllegalStateException("GenericsTy has no decl: ${ty.String()}")
    }

    private func RequireClassDef(def: CustomTypeDef): ClassDef {
        if (let Some(classDef) <- (def as ClassDef)) {
            return classDef
        }
        throw IllegalStateException("nominal cache entry is not a ClassDef")
    }

    private func RequireStructDef(def: CustomTypeDef): StructDef {
        if (let Some(structDef) <- (def as StructDef)) {
            return structDef
        }
        throw IllegalStateException("nominal cache entry is not a StructDef")
    }

    private func RequireEnumDef(def: CustomTypeDef): EnumDef {
        if (let Some(enumDef) <- (def as EnumDef)) {
            return enumDef
        }
        throw IllegalStateException("nominal cache entry is not an EnumDef")
    }
}
