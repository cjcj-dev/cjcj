package cjcj::sema.Desugar.AfterTypeCheck

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*
import cjcj::utils.CJC_ASSERT

private let CORE_PACKAGE_NAME: String = "std.core"
private let STRING_BUILDER_NAME: String = "StringBuilder"
private let STRING_NAME: String = "String"
private let TO_STRING_INTERFACE_NAME: String = "ToString"
private let APPEND_NAME: String = "append"
private let TO_STRING_NAME: String = "toString"

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

private func IsNamedDecl(decl: Decl, fullPackageName: String, name: String): Bool {
    if (decl.identifier.Val() != name) {
        return false
    }
    return fullPackageName.isEmpty() || decl.fullPackageName == fullPackageName
}

private func SameImportedAwareDecl(left: Decl, right: Decl): Bool {
    if (left.TestAttr(Attribute.IMPORTED) && right.TestAttr(Attribute.IMPORTED)) {
        if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
            return left.rawMangleName == right.rawMangleName
        }
        if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
            return left.mangledName == right.mangledName
        }
    }
    return SameDecl(left, right)
}

private func AddImportedDeclIfMissing(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (SameImportedAwareDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func FindPackageDecl(pkg: Package, fullPackageName: String, name: String,
    context!: Option<ASTContext> = None): Option<Decl> {
    for (decl in pkg.srcImportedNonGenericDecls) {
        if (IsNamedDecl(decl, fullPackageName, name)) {
            return decl
        }
    }
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (IsNamedDecl(decl, fullPackageName, name)) {
                return decl
            }
        }
    }
    if (let Some(ctx) <- context) {
        if (let Some(packageMap) <- ctx.resolvedPackageMemberDeclsMap.get(fullPackageName)) {
            if (let Some(decls) <- packageMap.get(name)) {
                for (decl in decls) {
                    if (IsNamedDecl(decl, fullPackageName, name)) {
                        return decl
                    }
                }
            }
        }
        for (packageDecl in ctx.packageDecls) {
            if (packageDecl.fullPackageName == fullPackageName) {
                for (file in packageDecl.srcPackage.files) {
                    for (decl in file.decls) {
                        if (IsNamedDecl(decl, fullPackageName, name)) {
                            return decl
                        }
                    }
                }
            }
        }
    }
    return None
}

private func EstimateStringLength(siExpr: StrInterpolationExpr): Int64 {
    var size: Int64 = 0
    for (expr in siExpr.strPartExprs) {
        if (let Some(interpolation) <- (expr as InterpolationExpr)) {
            if (let Some(block) <- interpolation.block) {
                if (let Some(blockTy) <- block.GetTy()) {
                    size += if (blockTy.IsPrimitive()) { 10 } else { 32 }
                } else {
                    size += 32
                }
            } else {
                size += 32
            }
        } else if (let Some(lit) <- (expr as LitConstExpr)) {
            size += lit.stringValue.size
        }
    }
    return size
}

private func MatchAppendFuncByParamTy(candidates: ArrayList<Decl>, paramTy: Ty): Option<Decl> {
    for (candidate in candidates) {
        if (let Some(candidateTy) <- candidate.GetTy()) {
            if (let Some(funcTy) <- (candidateTy as FuncTy)) {
                if (funcTy.paramTys.size == 1 && refEq(funcTy.paramTys[0], paramTy)) {
                    return candidate
                }
            }
        }
    }
    return None
}

private func FuncRetTy(decl: Decl): Option<Ty> {
    if (let Some(declTy) <- decl.GetTy()) {
        if (let Some(funcTy) <- (declTy as FuncTy)) {
            return funcTy.retTy
        }
    }
    return None
}

private func AsFuncDecl(decl: Option<Decl>): Option<FuncDecl> {
    if (let Some(value) <- decl) {
        return value as FuncDecl
    }
    return None
}

private func MatchConstructorBySingleParamTy(decl: Decl, paramTy: Ty): Option<FuncDecl> {
    for (member in decl.GetMemberDecls()) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (IsInstanceConstructor(funcDecl) && funcDecl.identifier.Val() == "init") {
                if (let Some(declTy) <- funcDecl.GetTy()) {
                    if (let Some(funcTy) <- (declTy as FuncTy)) {
                        if (funcTy.paramTys.size == 1 && SameTy(funcTy.paramTys[0], paramTy)) {
                            return funcDecl
                        }
                    }
                }
            }
        }
    }
    return None
}

private func AddMemberDeclsByName(out: ArrayList<Decl>, owner: Decl, name: String): Unit {
    for (member in owner.GetMemberDecls()) {
        if (member.identifier.Val() == name) {
            AddImportedDeclIfMissing(out, member)
        }
    }
}

private func MatchToStringImpl(typeManager: TypeManager, pkg: Package, file: File, ty: Ty,
    context!: Option<ASTContext> = None): ArrayList<Decl> {
    let found = if (ty.IsBuiltin()) {
        ExtendFieldLookup(typeManager, file, Some(ty), TO_STRING_NAME)
    } else {
        FieldLookup(typeManager, Ty.GetDeclPtrOfTy(Some(ty)), TO_STRING_NAME, info: LookupInfo(file: file))
    }
    let out = ArrayList<Decl>()
    let stringTy: Option<Ty> = if (let Some(stringDecl) <- FindPackageDecl(pkg, CORE_PACKAGE_NAME, STRING_NAME,
        context: context)) {
        stringDecl.GetTy()
    } else {
        None
    }
    for (decl in found) {
        if (let Some(declTy) <- decl.GetTy()) {
            if (let Some(funcTy) <- (declTy as FuncTy)) {
                if (funcTy.paramTys.isEmpty()) {
                    if (let Some(coreStringTy) <- stringTy) {
                        if (SameTy(funcTy.retTy, coreStringTy)) {
                            out.add(decl)
                        }
                    } else if (funcTy.retTy.name == STRING_NAME) {
                        out.add(decl)
                    }
                }
            }
        }
    }
    return out
}

private func CreateAppendCall(typeManager: TypeManager, pkg: Package, litConstExpr: LitConstExpr,
    partExpr: Expr, appendDecls: ArrayList<Decl>, sbItem: VarDecl, context!: Option<ASTContext> = None):
    Option<CallExpr> {
    var appendDecl: Option<Decl> = None
    let appendArgs = ArrayList<FuncArg>()
    if (let Some(interpolation) <- (partExpr as InterpolationExpr)) {
        CJC_ASSERT(interpolation.block.isSome())
        let block = interpolation.block.getOrThrow()
        CJC_ASSERT(Ty.IsTyCorrect(block.GetTy()))
        let blockTy = block.GetTy().getOrThrow()
        appendDecl = MatchAppendFuncByParamTy(appendDecls, blockTy)
        if (let Some(_) <- appendDecl) {
            appendArgs.add(CreateFuncArg(block))
            interpolation.block = None
        } else {
            CJC_ASSERT(partExpr.curFile.isSome())
            let file = partExpr.curFile.getOrThrow()
            var found = MatchToStringImpl(typeManager, pkg, file, blockTy, context: context)
            if (found.isEmpty()) {
                let toStringInterface = FindPackageDecl(pkg, CORE_PACKAGE_NAME,
                    TO_STRING_INTERFACE_NAME, context: context)
                CJC_ASSERT(toStringInterface.isSome())
                found = FieldLookup(typeManager, Some(toStringInterface.getOrThrow()), TO_STRING_NAME,
                    info: LookupInfo(file: partExpr.curFile))
            }
            CJC_ASSERT(found.size == 1)
            let toStringDecl = found[0]
            let toStringFunc = CreateMemberAccess(block, toStringDecl)
            interpolation.block = None
            toStringFunc.target = toStringDecl
            toStringFunc.targets.add(Some((toStringDecl as FuncDecl).getOrThrow()))
            CopyBasicInfo(block, toStringFunc)
            let toStringCall = CreateCallExpr(toStringFunc, ArrayList<FuncArg>(),
                AsFuncDecl(Some(toStringDecl)), FuncRetTy(toStringDecl), CallKind.CALL_DECLARED_FUNCTION)
            let retTy = FuncRetTy(toStringDecl).getOrThrow()
            toStringCall.SetTy(retTy)
            appendDecl = MatchAppendFuncByParamTy(appendDecls, retTy)
            appendArgs.add(CreateFuncArg(toStringCall))
        }
    } else if (let Some(lit) <- (partExpr as LitConstExpr)) {
        if (lit.rawString.isEmpty()) {
            return None
        }
        let litTy = lit.GetTy().getOrThrow()
        appendDecl = MatchAppendFuncByParamTy(appendDecls, litTy)
        if (let Some(cloned) <- CloneExpr(lit)) {
            cloned.SetTy(litTy)
            appendArgs.add(CreateFuncArg(cloned))
        }
    }
    CJC_ASSERT(appendDecl.isSome())
    let realAppendDecl = appendDecl.getOrThrow()
    let appendFunc = CreateMemberAccess(CreateRefExpr(sbItem, partExpr), realAppendDecl)
    appendFunc.target = realAppendDecl
    appendFunc.targets.add(Some((realAppendDecl as FuncDecl).getOrThrow()))
    CopyBasicInfo(partExpr, appendFunc)
    let appendCall = CreateCallExpr(appendFunc, appendArgs, AsFuncDecl(Some(realAppendDecl)),
        Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)), CallKind.CALL_DECLARED_FUNCTION)
    appendCall.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
    AddCurFile(appendCall, file: litConstExpr.curFile)
    return appendCall
}

public func DesugarStrInterpolationExpr(typeManager: TypeManager, pkg: Package, litConstExpr: LitConstExpr,
    context!: Option<ASTContext> = None): Unit {
    if (let Some(_) <- litConstExpr.desugarExpr) {
        return
    }
    if (let None <- litConstExpr.siExpr) {
        return
    }
    let siExpr = litConstExpr.siExpr.getOrThrow()
    if (let None <- litConstExpr.curFile) {
        return
    }
    if (let None <- FindPackageDecl(pkg, CORE_PACKAGE_NAME, STRING_BUILDER_NAME, context: context)) {
        return
    }
    let sbDecl = FindPackageDecl(pkg, CORE_PACKAGE_NAME, STRING_BUILDER_NAME, context: context).getOrThrow()
    if (let None <- sbDecl.GetTy()) {
        return
    }

    let block = Block()
    CopyBasicInfo(siExpr, block)
    block.EnableAttr(Attribute.COMPILER_ADD)
    if (let Some(siTy) <- siExpr.GetTy()) {
        block.SetTy(siTy)
    }

    let args = ArrayList<FuncArg>()
    let capacity = CreateLitConstExpr(LitConstKind.INTEGER, "${EstimateStringLength(siExpr)}",
        TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
    args.add(CreateFuncArg(capacity))
    let sbTy = sbDecl.GetTy().getOrThrow()
    let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    if (let None <- MatchConstructorBySingleParamTy(sbDecl, int64Ty)) {
        return
    }
    let sbCtorDecl = MatchConstructorBySingleParamTy(sbDecl, int64Ty).getOrThrow()
    let sbCtorRef = CreateRefExpr(sbCtorDecl, siExpr)
    let sbCtorCall = CreateCallExpr(sbCtorRef, args, Some(sbCtorDecl), Some(sbTy), CallKind.CALL_OBJECT_CREATION)
    CopyBasicInfo(siExpr, sbCtorCall)
    sbCtorCall.SetTy(sbTy)
    let sbItem = CreateTmpVarDecl(None, sbCtorCall)
    CopyNodeScopeInfo(sbItem, siExpr)
    sbItem.EnableAttr(Attribute.NO_MANGLE)
    sbItem.SetTy(sbTy)
    block.body.add(sbItem)

    let appendDecls = FieldLookup(typeManager, Some(sbDecl), APPEND_NAME,
        info: LookupInfo(file: litConstExpr.curFile, lookupExtend: false))
    AddMemberDeclsByName(appendDecls, sbDecl, APPEND_NAME)
    for (partExpr in siExpr.strPartExprs) {
        if (let Some(appendCall) <- CreateAppendCall(typeManager, pkg, litConstExpr, partExpr, appendDecls, sbItem,
            context: context)) {
            block.body.add(appendCall)
        }
    }

    let toStringDecls = if (let Some(file) <- litConstExpr.curFile) {
        MatchToStringImpl(typeManager, pkg, file, sbTy, context: context)
    } else {
        ArrayList<Decl>()
    }
    if (toStringDecls.size == 1) {
        let toStringDecl = toStringDecls[0]
        let toStringFunc = CreateMemberAccess(CreateRefExpr(sbItem, litConstExpr), toStringDecl)
        toStringFunc.target = toStringDecl
        toStringFunc.targets.add(Some((toStringDecl as FuncDecl).getOrThrow()))
        CopyBasicInfo(sbCtorCall, toStringFunc)
        let toStringCall = CreateCallExpr(toStringFunc, ArrayList<FuncArg>(), AsFuncDecl(Some(toStringDecl)),
            FuncRetTy(toStringDecl), CallKind.CALL_DECLARED_FUNCTION)
        CopyBasicInfo(sbCtorCall, toStringCall)
        if (let Some(litTy) <- litConstExpr.GetTy()) {
            toStringCall.SetTy(litTy)
        }
        block.body.add(toStringCall)
        AddCurFile(block, file: litConstExpr.curFile)
        litConstExpr.desugarExpr = block
    }
}
