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

private func MarkImportedDeclUsed(decl: Decl): Unit {
    if (!decl.TestAttr(Attribute.IMPORTED)) {
        return
    }
    if (decl.isUsedImports) {
        return
    }
    decl.isUsedImports = true
    if (let Some(propDecl) <- (decl as PropDecl)) {
        for (getter in propDecl.getters) {
            MarkImportedDeclUsed(getter)
        }
        for (setter in propDecl.setters) {
            MarkImportedDeclUsed(setter)
        }
    }
    if (let Some(outer) <- decl.outerDecl) {
        MarkImportedDeclUsed(outer)
    }
}

private func AddSyntheticImportedTarget(source: Node, decl: Decl): Unit {
    if (!decl.TestAttr(Attribute.IMPORTED)) {
        return
    }
    MarkImportedDeclUsed(decl)
    if (let Some(file) <- source.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            AddImportedDeclIfMissing(pkg.srcImportedNonGenericDecls, decl)
        }
    }
}

private func AddSyntheticImportedTy(source: Node, ty: Ty): Unit {
    if (let Some(structTy) <- (ty as StructTy)) {
        if (let Some(decl) <- structTy.decl) {
            AddSyntheticImportedDeclAndDependencies(source, decl)
        }
    } else if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(decl) <- classTy.decl) {
            AddSyntheticImportedDeclAndDependencies(source, decl)
        }
    } else if (let Some(enumTy) <- (ty as EnumTy)) {
        if (let Some(decl) <- enumTy.decl) {
            AddSyntheticImportedDeclAndDependencies(source, decl)
        }
    } else if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(decl) <- interfaceTy.decl) {
            AddSyntheticImportedDeclAndDependencies(source, decl)
        }
    } else if (let Some(funcTy) <- (ty as FuncTy)) {
        for (paramTy in funcTy.paramTys) {
            AddSyntheticImportedTy(source, paramTy)
        }
        AddSyntheticImportedTy(source, funcTy.retTy)
    }
    for (arg in ty.typeArgs) {
        AddSyntheticImportedTy(source, arg)
    }
}

private func AddSyntheticImportedNominalMemberDependencies(source: Node, decl: Decl): Unit {
    if (!decl.IsNominalDecl()) {
        return
    }
    if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
        for (inheritedType in inheritableDecl.inheritedTypes) {
            if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                AddSyntheticImportedTy(source, inheritedTy)
            }
            if (let Some(target) <- inheritedType.GetTarget()) {
                AddSyntheticImportedDeclAndDependencies(source, target)
            }
        }
    }
    for (member in decl.GetMemberDecls()) {
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (let Some(funcTy) <- funcDecl.GetTy()) {
                AddSyntheticImportedTy(source, funcTy)
            }
        } else if (let Some(propDecl) <- (member as PropDecl)) {
            if (let Some(propTy) <- propDecl.GetTy()) {
                AddSyntheticImportedTy(source, propTy)
            }
            for (getter in propDecl.getters) {
                if (let Some(getterTy) <- getter.GetTy()) {
                    AddSyntheticImportedTy(source, getterTy)
                }
            }
            for (setter in propDecl.setters) {
                if (let Some(setterTy) <- setter.GetTy()) {
                    AddSyntheticImportedTy(source, setterTy)
                }
            }
        } else if (let Some(varDecl) <- (member as VarDecl)) {
            if (let Some(varTy) <- varDecl.GetTy()) {
                AddSyntheticImportedTy(source, varTy)
            }
        }
    }
}

private func AddSyntheticImportedDeclAndDependencies(source: Node, decl: Decl): Unit {
    let wasUsed = decl.isUsedImports
    AddSyntheticImportedTarget(source, decl)
    if (!wasUsed && decl.TestAttr(Attribute.GENERIC)) {
        AddSyntheticImportedNominalMemberDependencies(source, decl)
    }
    if (let Some(outer) <- decl.outerDecl) {
        let outerWasUsed = outer.isUsedImports
        AddSyntheticImportedTarget(source, outer)
        if (!outerWasUsed && outer.TestAttr(Attribute.GENERIC)) {
            AddSyntheticImportedNominalMemberDependencies(source, outer)
        }
    }
    if (!decl.IsNominalDecl()) {
        if (let Some(ty) <- decl.GetTy()) {
            AddSyntheticImportedTy(source, ty)
        }
    }
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

private func IsSameAppendParamTy(left: Ty, right: Ty): Bool {
    return SameTy(left, right) || (left.IsString() && right.IsString())
}

private func MatchFuncBySingleParamTy(candidates: ArrayList<Decl>, paramTy: Ty): Option<Decl> {
    for (candidate in candidates) {
        if (let Some(candidateTy) <- candidate.GetTy()) {
            if (let Some(funcTy) <- (candidateTy as FuncTy)) {
                if (funcTy.paramTys.size == 1 && IsSameAppendParamTy(funcTy.paramTys[0], paramTy)) {
                    return candidate
                }
                if (funcTy.paramTys.size == 2 && IsSameAppendParamTy(funcTy.paramTys[1], paramTy)) {
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
        if (let Some(block) <- interpolation.block) {
            if (let Some(blockTy) <- block.GetTy()) {
                appendDecl = MatchFuncBySingleParamTy(appendDecls, blockTy)
                if (let Some(_) <- appendDecl) {
                    appendArgs.add(CreateFuncArg(block))
                } else {
                    if (let Some(file) <- partExpr.curFile) {
                        var found = MatchToStringImpl(typeManager, pkg, file, blockTy, context: context)
                        if (found.isEmpty()) {
                            if (let Some(toStringInterface) <- FindPackageDecl(pkg, CORE_PACKAGE_NAME,
                                TO_STRING_INTERFACE_NAME, context: context)) {
                                found = FieldLookup(typeManager, Some(toStringInterface), TO_STRING_NAME,
                                    info: LookupInfo(file: partExpr.curFile))
                            }
                        }
                        if (found.size == 1) {
                            let toStringDecl = found[0]
                            AddSyntheticImportedDeclAndDependencies(partExpr, toStringDecl)
                            let toStringFunc = CreateMemberAccess(block, toStringDecl)
                            toStringFunc.target = toStringDecl
                            toStringFunc.targets.add(toStringDecl)
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
        if (lit.stringValue.isEmpty()) {
            return None
        }
        var litTyOpt = lit.GetTy()
        if (let None <- litTyOpt) {
            litTyOpt = litConstExpr.GetTy()
        } else if (let Some(litTy) <- litTyOpt) {
            if (!Ty.IsTyCorrect(litTy)) {
                litTyOpt = litConstExpr.GetTy()
            }
        }
        if (let Some(litTy) <- litTyOpt) {
            appendDecl = MatchFuncBySingleParamTy(appendDecls, litTy)
        }
        if (let Some(cloned) <- CloneExpr(lit)) {
            if (let Some(litTy) <- litTyOpt) {
                cloned.SetTy(litTy)
            }
            appendArgs.add(CreateFuncArg(cloned))
        }
    }
    if (let Some(realAppendDecl) <- appendDecl) {
        AddSyntheticImportedDeclAndDependencies(partExpr, realAppendDecl)
        let appendFunc = CreateMemberAccess(CreateRefExpr(sbItem, partExpr), realAppendDecl)
        appendFunc.target = realAppendDecl
        appendFunc.targets.add(realAppendDecl)
        CopyBasicInfo(partExpr, appendFunc)
        let appendCall = CreateCallExpr(appendFunc, appendArgs, AsFuncDecl(Some(realAppendDecl)),
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)), CallKind.CALL_DECLARED_FUNCTION)
        appendCall.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        AddCurFile(appendCall, file: litConstExpr.curFile)
        return appendCall
    }
    return None
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
    AddSyntheticImportedDeclAndDependencies(litConstExpr, sbDecl)
    AddSyntheticImportedNominalMemberDependencies(litConstExpr, sbDecl)

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
    AddSyntheticImportedDeclAndDependencies(litConstExpr, sbCtorDecl)
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
        AddSyntheticImportedDeclAndDependencies(litConstExpr, toStringDecl)
        let toStringFunc = CreateMemberAccess(CreateRefExpr(sbItem, litConstExpr), toStringDecl)
        toStringFunc.target = toStringDecl
        toStringFunc.targets.add(toStringDecl)
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

public func SelfhostPortStatus_Desugar_AfterTypeCheck_StrInterpolationExpr(): Bool {
    return true
}
