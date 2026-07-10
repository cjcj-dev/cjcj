package cjcj::chir

import std.collection.*

import cjcj::ast.ASTKind as AstASTKind
import cjcj::ast.Attribute as AstAttribute
import cjcj::ast.ArrayTy as AstArrayTy
import cjcj::ast.ClassDecl as AstClassDecl
import cjcj::ast.ClassLikeDecl as AstClassLikeDecl
import cjcj::ast.ClassTy as AstClassTy
import cjcj::ast.Decl as AstDecl
import cjcj::ast.EnumDecl as AstEnumDecl
import cjcj::ast.EnumTy as AstEnumTy
import cjcj::ast.FuncDecl as AstFuncDecl
import cjcj::ast.InterfaceTy as AstInterfaceTy
import cjcj::ast.InheritableDecl as AstInheritableDecl
import cjcj::ast.IsStaticInitializer as AstIsStaticInitializer
import cjcj::ast.Node as AstNode
import cjcj::ast.PropDecl as AstPropDecl
import cjcj::ast.RefEnumTy as AstRefEnumTy
import cjcj::ast.StructDecl as AstStructDecl
import cjcj::ast.StructTy as AstStructTy
import cjcj::ast.Ty as AstTy
import cjcj::ast.TypeKind as AstTypeKind
import cjcj::ast.VArrayTy as AstVArrayTy
import cjcj::ast.VarDecl as AstVarDecl
import cjcj::utils.InternalError

private func Errorln(info: String): Unit {
    eprintln("ast2chir checker error: " + info)
}

private func CheckPrimitiveType(astTy: AstTy, chirTy: Type): Bool {
    let astKind = match (chirTy.GetTypeKind()) {
        case TypeKind.TYPE_INT8 => AstTypeKind.TYPE_INT8
        case TypeKind.TYPE_INT16 => AstTypeKind.TYPE_INT16
        case TypeKind.TYPE_INT32 => AstTypeKind.TYPE_INT32
        case TypeKind.TYPE_INT64 => AstTypeKind.TYPE_INT64
        case TypeKind.TYPE_INT_NATIVE => AstTypeKind.TYPE_INT_NATIVE
        case TypeKind.TYPE_UINT8 => AstTypeKind.TYPE_UINT8
        case TypeKind.TYPE_UINT16 => AstTypeKind.TYPE_UINT16
        case TypeKind.TYPE_UINT32 => AstTypeKind.TYPE_UINT32
        case TypeKind.TYPE_UINT64 => AstTypeKind.TYPE_UINT64
        case TypeKind.TYPE_UINT_NATIVE => AstTypeKind.TYPE_UINT_NATIVE
        case TypeKind.TYPE_FLOAT16 => AstTypeKind.TYPE_FLOAT16
        case TypeKind.TYPE_FLOAT32 => AstTypeKind.TYPE_FLOAT32
        case TypeKind.TYPE_FLOAT64 => AstTypeKind.TYPE_FLOAT64
        case TypeKind.TYPE_RUNE => AstTypeKind.TYPE_RUNE
        case TypeKind.TYPE_BOOLEAN => AstTypeKind.TYPE_BOOLEAN
        case TypeKind.TYPE_UNIT => AstTypeKind.TYPE_UNIT
        case TypeKind.TYPE_NOTHING => AstTypeKind.TYPE_NOTHING
        case _ =>
            InternalError("unsupported type kind")
            AstTypeKind.TYPE_INVALID
    }
    return astKind == astTy.kind
}

private func CheckTypeArgs(astTy: AstTy, chirTy: Type): Bool {
    let astTyArgs = astTy.typeArgs
    let chirTyArgs = chirTy.GetTypeArgs()
    if (astTyArgs.size != chirTyArgs.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < astTyArgs.size) {
        if (!CheckType(astTyArgs[idx], chirTyArgs[idx])) {
            return false
        }
        idx++
    }
    return true
}

private func CheckTupleType(astTy: AstTy, chirTy: Type): Bool {
    let astTyArgs = astTy.typeArgs
    let chirTyArgs = chirTy.GetTypeArgs()
    if (astTyArgs.size != chirTyArgs.size) {
        return false
    }
    var loop: Int64 = 0
    while (loop < astTyArgs.size) {
        if (!CheckType(astTyArgs[loop], chirTyArgs[loop])) {
            return false
        }
        loop++
    }
    return true
}

private func CheckFuncType(astTy: AstTy, chirTy: Type): Bool {
    let astTyArgs = astTy.typeArgs
    let chirTyArgs = chirTy.GetTypeArgs()
    if (astTyArgs.size != chirTyArgs.size) {
        return false
    }
    var loop: Int64 = 0
    while (loop < astTyArgs.size) {
        if (!CheckType(astTyArgs[loop], chirTyArgs[loop])) {
            return false
        }
        loop++
    }
    return true
}

private func CheckMethodType(astTy: AstTy, chirTy: Type): Bool {
    let astTyArgs = astTy.typeArgs
    let chirTyArgs = chirTy.GetTypeArgs()
    if (astTyArgs.size + 1 != chirTyArgs.size) {
        return false
    }
    var loop: Int64 = 0
    while (loop < astTyArgs.size) {
        if (!CheckType(astTyArgs[loop], chirTyArgs[loop + 1])) {
            return false
        }
        loop++
    }
    return true
}

private func CheckStructType(astTy: AstTy, chirTy: Type): Bool {
    if (!astTy.IsStruct()) {
        return false
    }
    let astStruct = (astTy as AstStructTy).getOrThrow().declPtr.getOrThrow()
    let chirStruct = (chirTy as StructType).getOrThrow().GetStructDef()
    if (astStruct.mangledName != chirStruct.GetIdentifierWithoutPrefix()) {
        return false
    }
    return CheckTypeArgs(astTy, chirTy)
}

private func CheckClassType(astTy: AstTy, chirTy: Type): Bool {
    if (!astTy.IsClass()) {
        return false
    }
    let astClass = (astTy as AstClassTy).getOrThrow().declPtr.getOrThrow()
    let chirClass = (chirTy as ClassType).getOrThrow().GetClassDef()
    if (astClass.mangledName != chirClass.GetIdentifierWithoutPrefix()) {
        return false
    }
    return CheckTypeArgs(astTy, chirTy)
}

private func CheckInterfaceType(astTy: AstTy, chirTy: Type): Bool {
    if (!astTy.IsInterface()) {
        return false
    }
    let astClass = (astTy as AstInterfaceTy).getOrThrow().declPtr.getOrThrow()
    let chirClass = (chirTy as ClassType).getOrThrow().GetClassDef()
    if (astClass.mangledName != chirClass.GetIdentifierWithoutPrefix()) {
        return false
    }
    return CheckTypeArgs(astTy, chirTy)
}

private func CheckEnumType(astTy: AstTy, chirTy: Type): Bool {
    if (!astTy.IsEnum()) {
        return false
    }
    let astEnum = (astTy as AstEnumTy).getOrThrow().declPtr.getOrThrow()
    let chirEnum = (chirTy as EnumType).getOrThrow().GetEnumDef()
    if (astEnum.mangledName != chirEnum.GetIdentifierWithoutPrefix()) {
        return false
    }
    return CheckTypeArgs(astTy, chirTy)
}

private func CheckRawArrayType(astTy: AstTy, chirTy: Type): Bool {
    if (!astTy.IsArray()) {
        return false
    }
    let astArray = (astTy as AstArrayTy).getOrThrow()
    let chirArray = (chirTy as RawArrayType).getOrThrow()
    return astArray.dims == chirArray.GetDims() && CheckType(astTy.typeArgs[0], chirTy.GetTypeArgs()[0])
}

private func CheckVArrayType(astTy: AstTy, chirTy: Type): Bool {
    if (astTy.kind != AstTypeKind.TYPE_VARRAY) {
        return false
    }
    let astArray = (astTy as AstVArrayTy).getOrThrow()
    let chirArray = (chirTy as VArrayType).getOrThrow()
    return UInt64(astArray.size) == chirArray.GetSize() && CheckType(astTy.typeArgs[0], chirTy.GetTypeArgs()[0])
}

private func CheckCPointerType(astTy: AstTy, chirTy: Type): Bool {
    if (!astTy.IsPointer()) {
        return false
    }
    return CheckType(astTy.typeArgs[0], chirTy.GetTypeArgs()[0])
}

private func CheckType(astTy: AstTy, chirTy: Type): Bool {
    if (chirTy.IsPrimitive()) {
        return CheckPrimitiveType(astTy, chirTy)
    } else if (chirTy.IsTuple()) {
        return CheckTupleType(astTy, chirTy)
    } else if (chirTy.IsFunc()) {
        return CheckFuncType(astTy, chirTy)
    } else if (chirTy.IsStruct()) {
        return CheckStructType(astTy, chirTy)
    } else if (chirTy.IsClass()) {
        if ((chirTy as ClassType).getOrThrow().GetClassDef().IsClass()) {
            return CheckClassType(astTy, chirTy)
        } else {
            return CheckInterfaceType(astTy, chirTy)
        }
    } else if (chirTy.IsEnum()) {
        return CheckEnumType(astTy, chirTy)
    } else if (chirTy.IsRawArray()) {
        return CheckRawArrayType(astTy, chirTy)
    } else if (chirTy.IsVArray()) {
        return CheckVArrayType(astTy, chirTy)
    } else if (chirTy.IsCPointer()) {
        return CheckCPointerType(astTy, chirTy)
    } else if (chirTy.IsCString()) {
        return astTy.IsCString()
    } else if (chirTy.IsRef()) {
        return CheckType(astTy, chirTy.GetTypeArgs()[0])
    }
    return true
}

private func CheckClass(decl: AstClassDecl, classDef: ClassDef): Bool {
    if (!classDef.IsClass()) {
        Errorln(classDef.GetIdentifier() + " is expected to be a classDef.")
        return false
    }
    var astSupClsTy: Option<AstClassTy> = None
    for (superNode in decl.inheritedTypes) {
        if (let Some(superTy) <- superNode.GetTy()) {
            if (superTy.kind == AstTypeKind.TYPE_CLASS) {
                astSupClsTy = superTy as AstClassTy
            }
        }
    }
    let chirSupClsTy = classDef.GetSuperClassTy()
    if (let Some(astClassTy) <- astSupClsTy) {
        if (let Some(chirClassTy) <- chirSupClsTy) {
            if (!CheckType(astClassTy, chirClassTy)) {
                Errorln(classDef.GetIdentifier() + " set wrong super class.")
                return false
            }
        } else {
            Errorln(classDef.GetIdentifier() + " not set super class.")
            return false
        }
    } else if (chirSupClsTy.isSome()) {
        Errorln(classDef.GetIdentifier() + " set redundant super class.")
        return false
    }
    return true
}

private func CheckInterface(chirNode: ClassDef): Bool {
    if (!chirNode.IsInterface()) {
        Errorln(chirNode.GetIdentifier() + " is expected to be a interfaceDef.")
        return false
    }
    return true
}

private func GetParentCustomTypeDef(value: Value): Option<CustomTypeDef> {
    if (let Some(funcValue) <- (value as Function)) {
        return funcValue.GetParentCustomTypeDef()
    } else if (let Some(varValue) <- (value as GlobalVar)) {
        return varValue.GetParentCustomTypeDef()
    }
    return None
}

private func CheckInheritDeclGlobalMember(decl: AstDecl, chirNode: CustomTypeDef,
    globalCache: FaithfulAST2CHIRNodeMap): Bool {
    let chirCache = globalCache.TryGet(decl)
    if (chirCache.isNone() && decl.TestAttr(AstAttribute.COMMON)) {
        return true
    }
    if (chirCache.isNone()) {
        Errorln("not find " + decl.mangledName + " translator in " + chirNode.GetIdentifier() + ".")
        return false
    }
    let cacheValue = chirCache.getOrThrow()
    if (decl.IsConst() && decl.TestAttr(AstAttribute.IMPORTED)) {
        return true
    }
    let funcDecl = decl as AstFuncDecl
    if (funcDecl.isNone() || !AstIsStaticInitializer(funcDecl.getOrThrow())) {
        if (let Some(def) <- GetParentCustomTypeDef(cacheValue)) {
            if (def.nodeId != chirNode.nodeId) {
                Errorln("not find " + cacheValue.GetIdentifier() + " in " + chirNode.GetIdentifier() + ".")
                return false
            }
        } else {
            Errorln("not find " + cacheValue.GetIdentifier() + " in " + chirNode.GetIdentifier() + ".")
            return false
        }
    }
    if (decl.astKind == AstASTKind.FUNC_DECL) {
        let checkedFuncDecl = (decl as AstFuncDecl).getOrThrow()
        if (checkedFuncDecl.TestAttr(AstAttribute.CONSTRUCTOR) || checkedFuncDecl.IsFinalizer()) {
            return true
        }
        let chirType = cacheValue.GetType().getOrThrow()
        if (!decl.TestAttr(AstAttribute.STATIC) && !CheckMethodType(decl.GetTy().getOrThrow(), chirType)) {
            Errorln(cacheValue.GetIdentifier() + " is expected to be promoted " + decl.GetTy().getOrThrow().String() +
                ".")
            return false
        }
        if (decl.TestAttr(AstAttribute.STATIC) && !CheckFuncType(decl.GetTy().getOrThrow(), chirType)) {
            Errorln(cacheValue.GetIdentifier() + " is expected to be promoted " + decl.GetTy().getOrThrow().String() +
                ".")
            return false
        }
    }
    return true
}

private func CheckLocalVar(decl: AstDecl, chirNode: CustomTypeDef): Bool {
    let localVars = if (chirNode.GetCustomKind() == CustomDefKind.TYPE_CLASS) {
        (chirNode as ClassDef).getOrThrow().GetDirectInstanceVars()
    } else {
        chirNode.GetAllInstanceVars()
    }
    for (item in localVars) {
        if (item.name != decl.identifier.Val()) {
            continue
        }
        let declTy = decl.GetTy().getOrThrow()
        if ((declTy as AstRefEnumTy).isNone() && !CheckType(declTy, item.ty)) {
            Errorln(item.name + " is expected to be " + declTy.String() + " in " + chirNode.GetIdentifier() + ".")
            return false
        }
        return true
    }
    Errorln("not find local var " + decl.mangledName + " in " + chirNode.GetIdentifier() + ".")
    return false
}

private func CheckInheritDeclMembers(decl: AstInheritableDecl, chirNode: CustomTypeDef,
    globalCache: FaithfulAST2CHIRNodeMap): Bool {
    var ret = true
    for (memberDecl in decl.GetMemberDecls()) {
        if (memberDecl.TestAttr(AstAttribute.GENERIC)) {
            continue
        }
        if (memberDecl.astKind == AstASTKind.VAR_DECL && !memberDecl.TestAttr(AstAttribute.STATIC)) {
            ret = CheckLocalVar(memberDecl, chirNode) && ret
            continue
        }
        if (memberDecl.astKind == AstASTKind.PRIMARY_CTOR_DECL) {
            continue
        }
        if (memberDecl.astKind == AstASTKind.PROP_DECL) {
            let propDecl = (memberDecl as AstPropDecl).getOrThrow()
            for (getter in propDecl.getters) {
                ret = CheckInheritDeclGlobalMember(getter, chirNode, globalCache) && ret
            }
            for (setter in propDecl.setters) {
                ret = CheckInheritDeclGlobalMember(setter, chirNode, globalCache) && ret
            }
            continue
        }
        ret = CheckInheritDeclGlobalMember(memberDecl, chirNode, globalCache) && ret
    }
    return ret
}

private func CheckClassLike(decl: AstClassLikeDecl, chirNode: CustomTypeDef,
    globalCache: FaithfulAST2CHIRNodeMap): Bool {
    if (chirNode.GetCustomKind() != CustomDefKind.TYPE_CLASS) {
        Errorln(chirNode.GetIdentifier() + " is expected to be a classDef/interfaceDef.")
        return false
    }
    var ret = true
    let classDef = (chirNode as ClassDef).getOrThrow()
    let astSupInter = decl.GetSuperInterfaceTys()
    let chirSupClsInter = classDef.GetImplementedInterfaceDefs()
    if (astSupInter.size != chirSupClsInter.size) {
        Errorln(chirNode.GetIdentifier() + " set wrong super interfaces.")
        ret = false
    }
    if (decl.astKind == AstASTKind.CLASS_DECL) {
        ret = CheckClass((decl as AstClassDecl).getOrThrow(), classDef) && ret
    } else {
        ret = CheckInterface(classDef) && ret
    }
    return CheckInheritDeclMembers(decl, chirNode, globalCache) && ret
}

private func CheckEnum(decl: AstEnumDecl, chirNode: CustomTypeDef,
    globalCache: FaithfulAST2CHIRNodeMap): Bool {
    if (chirNode.GetCustomKind() != CustomDefKind.TYPE_ENUM) {
        Errorln(chirNode.GetIdentifier() + " is expected to be a enumDef.")
        return false
    }
    return CheckInheritDeclMembers(decl, chirNode, globalCache)
}

private func CheckStruct(decl: AstStructDecl, chirNode: CustomTypeDef,
    globalCache: FaithfulAST2CHIRNodeMap): Bool {
    if (chirNode.GetCustomKind() != CustomDefKind.TYPE_STRUCT) {
        Errorln(chirNode.GetIdentifier() + " is expected to be a structDef.")
        return false
    }
    return CheckInheritDeclMembers(decl, chirNode, globalCache)
}

private func CheckFunc(decl: AstFuncDecl, chirNode: Value): Bool {
    if ((chirNode as Function).isNone()) {
        Errorln(chirNode.GetIdentifier() + " is expected to be a func.")
        return false
    }
    if (decl.outerDecl.isSome()) {
        return true
    }
    let astTy = decl.GetTy().getOrThrow()
    let chirTy = chirNode.GetType().getOrThrow()
    if (!CheckType(astTy, chirTy)) {
        var report = true
        if (decl.TestAttr(AstAttribute.SPECIFIC) && chirNode.TestAttr(Attribute.DESERIALIZED)) {
            report = false
        }
        if (report) {
            Errorln(chirNode.GetIdentifier() + " is expected to be " + astTy.String() + ".")
            return false
        }
    }
    return true
}

private func CheckVar(decl: AstVarDecl, chirNode: Value): Bool {
    if ((chirNode as GlobalVar).isNone()) {
        Errorln(chirNode.GetIdentifier() + " is expected to be a globalVar.")
        return false
    }
    let astTy = decl.GetTy().getOrThrow()
    let chirTy = chirNode.GetType().getOrThrow()
    if (!CheckType(astTy, chirTy)) {
        Errorln(chirNode.GetIdentifier() + " is expected to be " + astTy.String() + ".")
        return false
    }
    return true
}

public func AST2CHIRCheckCustomTypeDef(astNode: AstNode, chirNode: CustomTypeDef,
    globalCache: FaithfulAST2CHIRNodeMap): Bool {
    if (!astNode.IsNominalDecl()) {
        InternalError("unsupported decl")
        return false
    }
    var ret = true
    let decl = (astNode as AstDecl).getOrThrow()
    if (decl.identifier != chirNode.GetSrcCodeIdentifier()) {
        Errorln(chirNode.GetIdentifier() + "'srcIdentifier is expected to be " + decl.identifier.Val() + ".")
        ret = false
    }
    if (decl.mangledName != chirNode.GetIdentifierWithoutPrefix()) {
        Errorln(chirNode.GetIdentifier() + "'identifier is expected to be " + decl.mangledName + ".")
        ret = false
    }
    if (astNode.astKind == AstASTKind.CLASS_DECL || astNode.astKind == AstASTKind.INTERFACE_DECL) {
        return CheckClassLike((decl as AstClassLikeDecl).getOrThrow(), chirNode, globalCache) && ret
    } else if (astNode.astKind == AstASTKind.ENUM_DECL) {
        return CheckEnum((decl as AstEnumDecl).getOrThrow(), chirNode, globalCache) && ret
    } else if (astNode.astKind == AstASTKind.STRUCT_DECL) {
        return CheckStruct((decl as AstStructDecl).getOrThrow(), chirNode, globalCache) && ret
    }
    return ret
}

public func AST2CHIRCheckValue(astNode: AstNode, chirNode: Value): Bool {
    if (!astNode.IsDecl()) {
        return true
    }
    let decl = (astNode as AstDecl).getOrThrow()
    if (astNode.astKind == AstASTKind.VAR_DECL) {
        return CheckVar((decl as AstVarDecl).getOrThrow(), chirNode)
    } else if (astNode.astKind == AstASTKind.FUNC_DECL) {
        return CheckFunc((decl as AstFuncDecl).getOrThrow(), chirNode)
    }
    return true
}
