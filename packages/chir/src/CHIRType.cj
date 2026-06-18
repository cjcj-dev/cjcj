package cangjie_compiler::chir

import std.collection.*

import cangjie_compiler::ast.Ty as AstTy
import cangjie_compiler::ast.TypeKind as AstTypeKind
import cangjie_compiler::ast.ASTKindIndex as AstKindIndex
import cangjie_compiler::ast.TupleTy as AstTupleTy
import cangjie_compiler::ast.FuncTy as AstFuncTy
import cangjie_compiler::ast.ArrayTy as AstArrayTy
import cangjie_compiler::ast.VArrayTy as AstVArrayTy
import cangjie_compiler::ast.PointerTy as AstPointerTy
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.ClassDecl as AstClassDecl
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.InterfaceDecl as AstInterfaceDecl
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.GenericParamDecl as AstGenericParamDecl
import cangjie_compiler::ast.ClassTy as AstClassTy
import cangjie_compiler::ast.StructTy as AstStructTy
import cangjie_compiler::ast.InterfaceTy as AstInterfaceTy
import cangjie_compiler::ast.EnumTy as AstEnumTy
import cangjie_compiler::ast.GenericsTy as AstGenericsTy

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

    public init() {}

    public func TryGetType(ty: AstTy): Option<Type> {
        for (entry in typeMap) {
            if (SameAstTy(entry.astTy, ty)) {
                return entry.chirTy
            }
        }
        return None
    }

    public func SetType(ty: AstTy, chirTy: Type): Unit {
        for (entry in typeMap) {
            if (SameAstTy(entry.astTy, ty)) {
                entry.chirTy = chirTy
                return
            }
        }
        typeMap.add(CHIRTypeCacheEntry(ty, chirTy))
    }

    public func TryGetNominal(decl: AstDecl): Option<CustomTypeDef> {
        for (entry in globalNominalCache) {
            if (SameAstDecl(entry.decl, decl)) {
                return entry.def
            }
        }
        return None
    }

    public func SetNominal(decl: AstDecl, def: CustomTypeDef): Unit {
        for (entry in globalNominalCache) {
            if (SameAstDecl(entry.decl, decl)) {
                entry.def = def
                return
            }
        }
        globalNominalCache.add(CHIRNominalCacheEntry(decl, def))
    }
}

private func SameAstTy(left: AstTy, right: AstTy): Bool {
    return left.kind == right.kind && left.Hash() == right.Hash()
}

private func SameAstDecl(left: AstDecl, right: AstDecl): Bool {
    return AstKindIndex(left.astKind) == AstKindIndex(right.astKind) && left.identifier.Val() == right.identifier.Val() &&
        left.fullPackageName == right.fullPackageName && left.begin.hashCode() == right.begin.hashCode() &&
        left.end.hashCode() == right.end.hashCode()
}

public class CHIRType {
    private let builder: CHIRBuilder
    private let chirTypeCache: CHIRTypeCache

    public init(builder: CHIRBuilder, typeCache: CHIRTypeCache) {
        this.builder = builder
        this.chirTypeCache = typeCache
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
            case AstTypeKind.TYPE_UINT8 => builder.context.GetUInt8Ty()
            case AstTypeKind.TYPE_UINT16 => builder.context.GetUInt16Ty()
            case AstTypeKind.TYPE_UINT32 => builder.context.GetUInt32Ty()
            case AstTypeKind.TYPE_UINT64 => builder.context.GetUInt64Ty()
            case AstTypeKind.TYPE_UINT_NATIVE => builder.context.GetUIntNativeTy()
            case AstTypeKind.TYPE_FLOAT16 => builder.context.GetFloat16Ty()
            case AstTypeKind.TYPE_FLOAT32 => builder.context.GetFloat32Ty()
            case AstTypeKind.TYPE_FLOAT64 => builder.context.GetFloat64Ty()
            case AstTypeKind.TYPE_RUNE => builder.context.GetRuneTy()
            case AstTypeKind.TYPE_BOOLEAN => builder.context.GetBoolTy()
            case AstTypeKind.TYPE_TUPLE => TranslateTupleType(RequireTupleTy(ty))
            case AstTypeKind.TYPE_FUNC => TranslateFuncType(RequireFuncTy(ty))
            case AstTypeKind.TYPE_ARRAY => TranslateArrayType(RequireArrayTy(ty))
            case AstTypeKind.TYPE_VARRAY => TranslateVArrayType(RequireVArrayTy(ty))
            case AstTypeKind.TYPE_POINTER => TranslateCPointerType(RequirePointerTy(ty))
            case AstTypeKind.TYPE_NOTHING => builder.context.GetNothingType()
            case AstTypeKind.TYPE_CSTRING => builder.context.GetCStringTy()
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
}
