package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

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

private func FindPackageDecl(pkg: Package, fullPackageName: String, name: String): Option<Decl> {
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

private func MatchFuncBySingleParamTy(candidates: ArrayList<Decl>, paramTy: Ty): Option<Decl> {
    for (candidate in candidates) {
        if (let Some(candidateTy) <- candidate.GetTy()) {
            if (let Some(funcTy) <- (candidateTy as FuncTy)) {
                if (funcTy.paramTys.size == 1 && SameTy(funcTy.paramTys[0], paramTy)) {
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

private func MatchToStringImpl(typeManager: TypeManager, pkg: Package, file: File, ty: Ty): ArrayList<Decl> {
    let found = if (ty.IsBuiltin()) {
        ExtendFieldLookup(typeManager, file, Some(ty), TO_STRING_NAME)
    } else {
        FieldLookup(typeManager, Ty.GetDeclPtrOfTy(Some(ty)), TO_STRING_NAME, info: LookupInfo(file: file))
    }
    let out = ArrayList<Decl>()
    let stringTy: Option<Ty> = if (let Some(stringDecl) <- FindPackageDecl(pkg, CORE_PACKAGE_NAME, STRING_NAME)) {
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
    partExpr: Expr, appendDecls: ArrayList<Decl>, sbItem: VarDecl): Option<CallExpr> {
    var appendDecl: Option<Decl> = None
    let appendArgs = ArrayList<FuncArg>()
    if (let Some(interpolation) <- (partExpr as InterpolationExpr)) {
        if (let Some(block) <- interpolation.block) {
            if (let Some(blockTy) <- block.GetTy()) {
                appendDecl = MatchFuncBySingleParamTy(appendDecls, blockTy)
                if (let Some(_) <- appendDecl) {
                    appendArgs.add(CreateFuncArg(block))
                } else {
                    if (let Some(file) <- partExpr.curFile) {
                        var found = MatchToStringImpl(typeManager, pkg, file, blockTy)
                        if (found.isEmpty()) {
                            if (let Some(toStringInterface) <- FindPackageDecl(pkg, CORE_PACKAGE_NAME,
                                TO_STRING_INTERFACE_NAME)) {
                                found = FieldLookup(typeManager, Some(toStringInterface), TO_STRING_NAME,
                                    info: LookupInfo(file: partExpr.curFile))
                            }
                        }
                        if (found.size == 1) {
                            let toStringDecl = found[0]
                            let toStringFunc = CreateMemberAccess(block, toStringDecl)
                            CopyBasicInfo(block, toStringFunc)
                            let toStringCall = CreateCallExpr(toStringFunc, ArrayList<FuncArg>(),
                                AsFuncDecl(Some(toStringDecl)), FuncRetTy(toStringDecl), CallKind.CALL_DECLARED_FUNCTION)
                            if (let Some(retTy) <- FuncRetTy(toStringDecl)) {
                                toStringCall.SetTy(retTy)
                                appendDecl = MatchFuncBySingleParamTy(appendDecls, retTy)
                            }
                            appendArgs.add(CreateFuncArg(toStringCall))
                        }
                    }
                }
            }
        }
    } else if (let Some(lit) <- (partExpr as LitConstExpr)) {
        if (lit.rawString.isEmpty()) {
            return None
        }
        if (let Some(litTy) <- lit.GetTy()) {
            appendDecl = MatchFuncBySingleParamTy(appendDecls, litTy)
        }
        if (let Some(cloned) <- CloneExpr(lit)) {
            appendArgs.add(CreateFuncArg(cloned))
        }
    }
    if (let Some(realAppendDecl) <- appendDecl) {
        let appendFunc = CreateMemberAccess(CreateRefExpr(sbItem, partExpr), realAppendDecl)
        CopyBasicInfo(partExpr, appendFunc)
        let appendCall = CreateCallExpr(appendFunc, appendArgs, AsFuncDecl(Some(realAppendDecl)),
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)), CallKind.CALL_DECLARED_FUNCTION)
        appendCall.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        AddCurFile(appendCall, file: litConstExpr.curFile)
        return appendCall
    }
    return None
}

public func DesugarStrInterpolationExpr(typeManager: TypeManager, pkg: Package, litConstExpr: LitConstExpr): Unit {
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
    if (let None <- FindPackageDecl(pkg, CORE_PACKAGE_NAME, STRING_BUILDER_NAME)) {
        return
    }
    let sbDecl = FindPackageDecl(pkg, CORE_PACKAGE_NAME, STRING_BUILDER_NAME).getOrThrow()
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
    let sbCtorCall = CreateCallExpr(CreateRefExpr(sbDecl), args)
    if (let Some(sbTy) <- sbDecl.GetTy()) {
        sbCtorCall.SetTy(sbTy)
    }
    CopyBasicInfo(siExpr, sbCtorCall)
    let sbItem = CreateTmpVarDecl(None, sbCtorCall)
    CopyNodeScopeInfo(sbItem, siExpr)
    sbItem.EnableAttr(Attribute.NO_MANGLE)
    if (let Some(sbTy2) <- sbDecl.GetTy()) {
        sbItem.SetTy(sbTy2)
    }
    block.body.add(sbItem)

    let appendDecls = FieldLookup(typeManager, Some(sbDecl), APPEND_NAME,
        info: LookupInfo(file: litConstExpr.curFile, lookupExtend: false))
    for (partExpr in siExpr.strPartExprs) {
        if (let Some(appendCall) <- CreateAppendCall(typeManager, pkg, litConstExpr, partExpr, appendDecls, sbItem)) {
            block.body.add(appendCall)
        }
    }

    let toStringDecls = if (let Some(file) <- litConstExpr.curFile) {
        MatchToStringImpl(typeManager, pkg, file, sbDecl.GetTy().getOrThrow())
    } else {
        ArrayList<Decl>()
    }
    if (toStringDecls.size == 1) {
        let toStringDecl = toStringDecls[0]
        let toStringFunc = CreateMemberAccess(CreateRefExpr(sbItem, litConstExpr), toStringDecl)
        CopyBasicInfo(sbCtorCall, toStringFunc)
        let toStringCall = CreateCallExpr(toStringFunc, ArrayList<FuncArg>(), AsFuncDecl(Some(toStringDecl)),
            FuncRetTy(toStringDecl), CallKind.CALL_DECLARED_FUNCTION)
        if (let Some(litTy) <- litConstExpr.GetTy()) {
            toStringCall.SetTy(litTy)
        }
        CopyBasicInfo(sbCtorCall, toStringCall)
        block.body.add(toStringCall)
        AddCurFile(block, file: litConstExpr.curFile)
        litConstExpr.desugarExpr = block
    }
}

public func SelfhostPortStatus_Desugar_AfterTypeCheck_StrInterpolationExpr(): Bool {
    return true
}
