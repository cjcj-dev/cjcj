package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine

private func TypeCheckDeclEmitDiag(
    diag: BasicDiagnosticEngine,
    node: Node,
    kind: BasicDiagKind,
    args!: Array<BasicDiagArgument> = Array<BasicDiagArgument>()
): Unit {
    let builder = diag.Diagnose(node.begin, node.end, kind, args: args)
    builder.Emit()
}

private func TypeCheckDeclAddUniqueDecl(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func TypeCheckDeclCopyTypeArgs(args: ArrayList<Ty>): Array<Ty> {
    let out = ArrayList<Ty>()
    for (arg in args) {
        out.add(arg)
    }
    return out.toArray()
}

public func TypeCheckDeclInsertEnumConstructors(
    ctx: ASTContext,
    ed: EnumDecl,
    enableMacroInLsp!: Bool = false
): Unit {
    if (ed.IsCommonMatchedWithSpecific()) {
        return
    }
    for (ctor in ed.constructors) {
        if (ctor.astKind == ASTKind.VAR_DECL) {
            ctx.InsertEnumConstructor(ctor.identifier.Val(), 0u64, ctor, enableMacroInLsp: enableMacroInLsp)
        } else if (let Some(funcDecl) <- (ctor as FuncDecl)) {
            var arity: UInt64 = 0u64
            if (let Some(body) <- funcDecl.funcBody) {
                if (!body.paramLists.isEmpty()) {
                    arity = UInt64(body.paramLists[0].params.size)
                }
            }
            ctx.InsertEnumConstructor(funcDecl.identifier.Val(), arity, funcDecl, enableMacroInLsp: enableMacroInLsp)
        }
    }
}

public func TypeCheckDeclBuildEnumConstructorMap(
    ctx: ASTContext,
    enableMacroInLsp!: Bool = false
): Unit {
    if (let Some(pkg) <- ctx.curPackage) {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(enumDecl) <- (decl as EnumDecl)) {
                    TypeCheckDeclInsertEnumConstructors(ctx, enumDecl, enableMacroInLsp: enableMacroInLsp)
                }
            }
        }
    }
}

public func TypeCheckDeclCheckEntryFunc(diag: BasicDiagnosticEngine, fd: FuncDecl): Bool {
    if (!fd.TestAttr(Attribute.GLOBAL)) {
        return true
    }
    if (let Some(file) <- fd.curFile) {
        if (file.isCommon) {
            let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_common_package_has_main,
                MakeRange(fd.begin, fd.end))
            builder.Emit()
        }
    } else {
        return true
    }

    if (let Some(body) <- fd.funcBody) {
        if (let Some(retType) <- body.retType) {
            if (let Some(retTy) <- retType.GetTy()) {
                if (Ty.IsTyCorrect(retTy) && !(retTy.IsInteger() || retTy.IsUnit())) {
                    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_unexpected_return_type_for_entry)
                    return false
                }
            }
        }
        if (body.paramLists.isEmpty()) {
            return true
        }
        let params = body.paramLists[0].params
        if (params.size > 1) {
            TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_unexpected_param_for_entry)
            return false
        }
        if (params.size == 1) {
            if (let Some(paramTy) <- params[0].GetTy()) {
                let isArrayTy = paramTy.IsStructArray() && paramTy.typeArgs.size == 1
                let isArrayStringTy = isArrayTy && paramTy.typeArgs[0].IsString()
                if (!isArrayStringTy) {
                    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_unexpected_param_for_entry)
                    return false
                }
            } else {
                TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_unexpected_param_for_entry)
                return false
            }
        }
    }
    return true
}

public func TypeCheckDeclIsUnaryOverloadOperator(op: TokenKind): Bool {
    return op == TokenKind.NOT || op == TokenKind.SUB
}

public func TypeCheckDeclIsBinaryOverloadOperator(op: TokenKind): Bool {
    return op == TokenKind.ADD || op == TokenKind.BITAND || op == TokenKind.BITOR ||
        op == TokenKind.BITXOR || op == TokenKind.DIV || op == TokenKind.EQUAL ||
        op == TokenKind.EXP || op == TokenKind.GE || op == TokenKind.GT ||
        op == TokenKind.LE || op == TokenKind.LSHIFT || op == TokenKind.LT ||
        op == TokenKind.MOD || op == TokenKind.MUL || op == TokenKind.NOTEQ ||
        op == TokenKind.RSHIFT || op == TokenKind.SUB
}

public func TypeCheckDeclCheckOperatorOverloadFunc(diag: BasicDiagnosticEngine, fd: FuncDecl): Bool {
    if (fd.op == TokenKind.ILLEGAL || fd.op == TokenKind.LPAREN) {
        return true
    }
    if (let Some(rawTy) <- fd.GetTy()) {
        if (let Some(funcTy) <- (rawTy as FuncTy)) {
            if (!Ty.IsTyCorrect(funcTy)) {
                return true
            }
            if (fd.op == TokenKind.LSQUARE) {
                return TypeCheckDeclCheckIndexOperatorOverload(diag, fd, funcTy)
            }
            if (funcTy.paramTys.size == 0) {
                if (!TypeCheckDeclIsUnaryOverloadOperator(fd.op)) {
                    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
                        args: [BasicDiagArgument(fd.identifier.Val())])
                    return false
                }
                return true
            }
            if (funcTy.paramTys.size == 1) {
                if (!TypeCheckDeclIsBinaryOverloadOperator(fd.op)) {
                    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
                        args: [BasicDiagArgument(fd.identifier.Val())])
                    return false
                }
                return true
            }
        } else {
            return true
        }
    } else {
        return true
    }
    TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
        args: [BasicDiagArgument(fd.identifier.Val())])
    return false
}

public func TypeCheckDeclCheckIndexOperatorOverload(
    diag: BasicDiagnosticEngine,
    fd: FuncDecl,
    funcTy: FuncTy
): Bool {
    let _ = funcTy
    if (let None <- fd.funcBody) {
        return true
    }
    let body = fd.funcBody.getOrThrow()
    if (body.paramLists.isEmpty()) {
        TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
            args: [BasicDiagArgument(fd.identifier.Val())])
        return false
    }
    let params = body.paramLists[0].params
    if (params.isEmpty()) {
        TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
            args: [BasicDiagArgument(fd.identifier.Val())])
        return false
    }
    if (!params[params.size - 1].isNamedParam) {
        return true
    }
    var valid = true
    for (param in params) {
        if (param.isNamedParam && param.identifier.Val() != "value") {
            valid = false
        }
    }
    if (params.size <= 1) {
        valid = false
    }
    if (valid && Ty.IsTyCorrect(fd.GetTy())) {
        if (let Some(realFuncTy) <- (fd.GetTy().getOrThrow() as FuncTy)) {
            if (!realFuncTy.retTy.IsUnit()) {
                valid = false
            }
        }
    }
    if (!valid) {
        TypeCheckDeclEmitDiag(diag, fd, BasicDiagKind.sema_operator_overload_invalid_num_parameter,
            args: [BasicDiagArgument(fd.identifier.Val())])
    }
    return valid
}

public func TypeCheckDeclSynchronizeTypeAndInitializer(tm: TypeManager, vd: VarDeclAbstract): Ty {
    if (let Some(typeNode) <- vd.typeNode) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            vd.SetTy(typeTy)
            if (let Some(initializer) <- vd.initializer) {
                if (typeTy.IsRune() && IsSingleRuneStringLiteral(initializer)) {
                    initializer.SetTy(typeTy)
                } else if (typeTy.kind == TypeKind.TYPE_UINT8 && IsSingleByteStringLiteral(initializer)) {
                    initializer.SetTy(typeTy)
                }
            }
            return typeTy
        }
        vd.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    if (let Some(initializer) <- vd.initializer) {
        if (let Some(initTy) <- initializer.GetTy()) {
            if (let Some(thisTy) <- (initTy as ClassThisTy)) {
                if (let Some(decl) <- thisTy.declPtr) {
                    let classTy = tm.GetClassTy(decl, TypeCheckDeclCopyTypeArgs(thisTy.typeArgs))
                    vd.SetTy(classTy)
                    return classTy
                }
            }
            if (let Some(funcTy) <- (initTy as FuncTy)) {
                if (funcTy.isC && funcTy.hasVariableLenArg) {
                    vd.SetTy(TypeManager.GetInvalidTy())
                    return TypeManager.GetInvalidTy()
                }
            }
            vd.SetTy(initTy)
            return initTy
        }
    }
    return TypeManager.GetInvalidTy()
}

public func TypeCheckDeclSetEnumElementTy(tm: TypeManager, constructor: Decl): Ty {
    if (!constructor.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        return constructor.GetTy() ?? TypeManager.GetInvalidTy()
    }
    if (Ty.IsTyCorrect(constructor.GetTy())) {
        return constructor.GetTy().getOrThrow()
    }
    if (constructor.astKind == ASTKind.VAR_DECL) {
        if (let Some(outer) <- constructor.outerDecl) {
            if (let Some(outerTy) <- outer.GetTy()) {
                constructor.SetTy(outerTy)
                return outerTy
            }
        }
        constructor.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    if (let Some(funcDecl) <- (constructor as FuncDecl)) {
        return TypeCheckDeclSetEnumElementTyForFunc(tm, funcDecl)
    }
    constructor.SetTy(TypeManager.GetInvalidTy())
    return TypeManager.GetInvalidTy()
}

public func TypeCheckDeclSetEnumElementTyForFunc(tm: TypeManager, funcDecl: FuncDecl): Ty {
    if (let None <- funcDecl.outerDecl) {
        funcDecl.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    if (let None <- funcDecl.funcBody) {
        funcDecl.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    let body = funcDecl.funcBody.getOrThrow()
    if (body.paramLists.isEmpty()) {
        funcDecl.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    let paramTys = ArrayList<Ty>()
    for (param in body.paramLists[0].params) {
        if (let Some(typeNode) <- param.typeNode) {
            if (let Some(paramTy) <- typeNode.GetTy()) {
                param.SetTy(paramTy)
                paramTys.add(paramTy)
            } else {
                paramTys.add(TypeManager.GetInvalidTy())
            }
        } else if (let Some(paramTy) <- param.GetTy()) {
            paramTys.add(paramTy)
        } else {
            paramTys.add(TypeManager.GetInvalidTy())
        }
    }
    let retTy = funcDecl.outerDecl.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy()
    let ctorTy = tm.GetFunctionTy(paramTys.toArray(), retTy)
    body.SetTy(ctorTy)
    funcDecl.SetTy(ctorTy)
    return ctorTy
}

public func TypeCheckDeclGetUnusedTysInTypeAlias(tad: TypeAliasDecl): ArrayList<Ty> {
    let unused = ArrayList<Ty>()
    if (let None <- tad.generic) {
        return unused
    }
    if (let None <- tad.typeNode) {
        return unused
    }
    let typeNode = tad.typeNode.getOrThrow()
    if (Ty.IsInitialTy(typeNode.GetTy())) {
        return unused
    }
    let used = TypeCheckDeclCollectTyArgsRecursive(typeNode.GetTy() ?? TypeManager.GetInvalidTy())
    for (param in tad.generic.getOrThrow().typeParameters) {
        if (let Some(paramTy) <- param.GetTy()) {
            var found = false
            for (candidate in used) {
                if (SameTy(candidate, paramTy)) {
                    found = true
                    break
                }
            }
            if (!found) {
                unused.add(paramTy)
            }
        }
    }
    return unused
}

private func TypeCheckDeclCollectTyArgsRecursive(ty: Ty): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    TypeCheckDeclCollectTyArgsInto(ty, out)
    return out
}

private func TypeCheckDeclCollectTyArgsInto(ty: Ty, out: ArrayList<Ty>): Unit {
    if (!Ty.IsTyCorrect(ty)) {
        return
    }
    for (arg in ty.typeArgs) {
        var exists = false
        for (value in out) {
            if (SameTy(value, arg)) {
                exists = true
                break
            }
        }
        if (!exists) {
            out.add(arg)
        }
        TypeCheckDeclCollectTyArgsInto(arg, out)
    }
}

public func TypeCheckDeclCollectNominalMembers(decl: Decl): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (member in decl.GetMemberDecls()) {
        TypeCheckDeclAddUniqueDecl(out, member)
    }
    return out
}

public func SelfhostPortStatus_TypeCheckDecl(): Bool {
    return true
}
