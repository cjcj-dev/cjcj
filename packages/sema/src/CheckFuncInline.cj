package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::option.MockMode

private let MAX_INLINE_NODE_NUMBER: Int64 = 32
private let MAIN_INVOKE_NAME: String = "$mainInvoke"
private let TEST_ENTRY_NAME: String = "$test.entry"
private let CPOINTER_NAME: String = "CPointer"

private class InlineDecision {
    public var result: Bool = true
    public var nodeNum: Int64 = 0
    public init() {}
}

private func CanExportForInline(fd: FuncDecl): Bool {
    var outerExported = true
    if (let Some(outer) <- fd.outerDecl) {
        if (!outer.IsExportedDecl()) {
            outerExported = false
        }
    }
    var checkFd = fd
    if (let Some(owner) <- fd.ownerFunc) {
        checkFd = owner
    }
    return checkFd.IsExportedDecl() && outerExported
}

private func CanCountedRefExprOrMemberExpr(expr: Expr): Bool {
    if (let Some(target) <- expr.GetTarget()) {
        if (target.astKind == ASTKind.VAR_DECL) {
            if (target.TestAttr(Attribute.GLOBAL) && !target.IsExportedDecl()) {
                return false
            }
            if (target.TestAttr(Attribute.STATIC)) {
                if (let Some(outer) <- target.outerDecl) {
                    if (outer.IsNominalDecl() && (!outer.IsExportedDecl() || !target.IsExportedDecl())) {
                        return false
                    }
                }
            }
        } else if (target.astKind == ASTKind.FUNC_DECL) {
            if (let Some(funcDecl) <- (target as FuncDecl)) {
                if (funcDecl.TestAttr(Attribute.INTRINSIC)) {
                    return true
                }
                if (funcDecl.TestAnyAttr(Attribute.FOREIGN, Attribute.C) || !CanExportForInline(funcDecl)) {
                    return false
                }
            }
        }
    }
    return true
}

private func DeclOfTy(ty: Ty): Option<Decl> {
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(decl) <- classTy.declPtr) {
            return decl
        }
    }
    if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(decl) <- interfaceTy.declPtr) {
            return decl
        }
    }
    if (let Some(structTy) <- (ty as StructTy)) {
        if (let Some(decl) <- structTy.declPtr) {
            return decl
        }
    }
    if (let Some(enumTy) <- (ty as EnumTy)) {
        if (let Some(decl) <- enumTy.declPtr) {
            return decl
        }
    }
    if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
        if (let Some(decl) <- aliasTy.declPtr) {
            return decl
        }
    }
    return None
}

private func ContainsInternalType(ty: Option<Ty>): Bool {
    if (let Some(value) <- ty) {
        if (!Ty.IsTyCorrect(value)) {
            return true
        }
        if (let Some(decl) <- DeclOfTy(value)) {
            if (!decl.IsExportedDecl() && !decl.TestAttr(Attribute.GENERIC)) {
                return true
            }
        }
        for (arg in value.typeArgs) {
            if (ContainsInternalType(arg)) {
                return true
            }
        }
        return false
    }
    return true
}

private func CountNodeNumber(expr: Expr, state: InlineDecision): VisitAction {
    if (state.nodeNum >= MAX_INLINE_NODE_NUMBER) {
        state.result = false
        return VisitAction.STOP_NOW
    }
    if (let Some(_) <- expr.desugarExpr) {
        return VisitAction.WALK_CHILDREN
    }
    if (ContainsInternalType(expr.GetTy())) {
        state.result = false
        return VisitAction.STOP_NOW
    }
    if (expr.astKind == ASTKind.BLOCK) {
        return VisitAction.WALK_CHILDREN
    }
    if (expr.astKind == ASTKind.LAMBDA_EXPR) {
        state.result = false
        return VisitAction.STOP_NOW
    }
    if (expr.astKind == ASTKind.REF_EXPR || expr.astKind == ASTKind.MEMBER_ACCESS) {
        if (!CanCountedRefExprOrMemberExpr(expr)) {
            state.result = false
            return VisitAction.STOP_NOW
        }
        state.nodeNum++
        return VisitAction.WALK_CHILDREN
    }
    state.nodeNum++
    return VisitAction.WALK_CHILDREN
}

public func IsInlineFunction(fd: FuncDecl): Bool {
    if (!CanExportForInline(fd)) {
        return false
    }
    if (fd.TestAnyAttr(Attribute.ENUM_CONSTRUCTOR, Attribute.CONSTRUCTOR)) {
        return false
    }
    if (let Some(propDecl) <- fd.propDecl) {
        if (!propDecl.HasAnno(AstAnnotationKind.FROZEN) && !propDecl.isConst) {
            return false
        }
    } else if (let Some(owner) <- fd.ownerFunc) {
        if (!owner.HasAnno(AstAnnotationKind.FROZEN) && !owner.isConst) {
            return false
        }
    } else if (!fd.isFrozen && !fd.isConst) {
        return false
    }
    if (let Some(ownerFunc) <- fd.ownerFunc) {
        if (ownerFunc.TestAttr(Attribute.CONSTRUCTOR)) {
            return false
        }
    }
    if (fd.TestAnyAttr(Attribute.C, Attribute.FOREIGN)) {
        return false
    }
    if (fd.TestAttr(Attribute.OPEN) || fd.TestAttr(Attribute.INTRINSIC)) {
        return false
    }
    if (fd.TestAttr(Attribute.ABSTRACT) && (fd.isGetter || fd.isSetter)) {
        return false
    }
    if (fd.TestAttr(Attribute.MAIN_ENTRY) || fd.identifier == MAIN_INVOKE_NAME || fd.identifier == TEST_ENTRY_NAME) {
        return false
    }
    if (let Some(outer) <- fd.outerDecl) {
        if (outer.identifier == CPOINTER_NAME) {
            return false
        }
    }
    if (let Some(body) <- fd.funcBody) {
        let state = InlineDecision()
        let walker = Walker(body, visitPre: { curNode: Node =>
            if (let Some(arg) <- (curNode as FuncArg)) {
                if (arg.TestAttr(Attribute.HAS_INITIAL)) {
                    return VisitAction.SKIP_CHILDREN
                }
            }
            if (let Some(expr) <- (curNode as Expr)) {
                return CountNodeNumber(expr, state)
            }
            if (curNode.astKind == ASTKind.FUNC_DECL && !curNode.TestAttr(Attribute.HAS_INITIAL)) {
                state.result = false
                return VisitAction.STOP_NOW
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        return state.result
    }
    return false
}

private func CheckDefaultParameterFunctionIsInline(fd: FuncDecl): Unit {
    if (let Some(body) <- fd.funcBody) {
        if (body.paramLists.isEmpty()) {
            return
        }
        for (param in body.paramLists[0].params) {
            if (let Some(desugarDecl) <- param.desugarDecl) {
                if (let Some(owner) <- desugarDecl.ownerFunc) {
                    desugarDecl.isInline = owner.isInline
                } else {
                    desugarDecl.isInline = fd.isInline
                }
            }
        }
    }
}

public func ProcessFuncDeclWithInline(fd: FuncDecl): Unit {
    if (fd.TestAttr(Attribute.GENERIC) || fd.TestAttr(Attribute.MACRO_FUNC)) {
        return
    }
    fd.isInline = IsInlineFunction(fd)
    if (CanExportForInline(fd) && !fd.TestAttr(Attribute.GENERIC) && !fd.TestAttr(Attribute.COMPILER_ADD)) {
        CheckDefaultParameterFunctionIsInline(fd)
    }
}

public func CheckFuncDeclIsInline(pkg: Package): Unit {
    let walker = Walker(pkg, visitPre: { curNode: Node =>
        if (let Some(funcDecl) <- (curNode as FuncDecl)) {
            ProcessFuncDeclWithInline(funcDecl)
            return VisitAction.SKIP_CHILDREN
        }
        if (curNode.astKind == ASTKind.VAR_DECL || curNode.astKind == ASTKind.INTERFACE_DECL) {
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func RemoveImportedInlineFunctionDecls(pkgs: ArrayList<Package>): ArrayList<FuncDecl> {
    let out = ArrayList<FuncDecl>()
    for (pkg in pkgs) {
        var idx: Int64 = 0
        while (idx < pkg.srcImportedNonGenericDecls.size) {
            if (let Some(funcDecl) <- (pkg.srcImportedNonGenericDecls[idx] as FuncDecl)) {
                out.add(funcDecl)
                pkg.srcImportedNonGenericDecls.remove(at: idx)
                continue
            }
            idx++
        }
    }
    return out
}

private func ComesAfter(left: FuncDecl, right: FuncDecl): Bool {
    if (right.begin < left.begin) {
        return true
    }
    if (left.begin == right.begin && right.end < left.end) {
        return true
    }
    return left.begin == right.begin && left.end == right.end && left.identifier.Val() > right.identifier.Val()
}

private func SortInlineFuncDecls(values: ArrayList<FuncDecl>): Unit {
    var idx: Int64 = 1
    while (idx < values.size) {
        let current = values[idx]
        var prev = idx - 1
        while (prev >= 0 && ComesAfter(values[prev], current)) {
            values[prev + 1] = values[prev]
            prev--
        }
        values[prev + 1] = current
        idx++
    }
}

public func CheckInlineFunctionsForPackages(pkgs: ArrayList<Package>, opts: OptionGlobalOptions): Unit {
    let importedInlineFunctions = RemoveImportedInlineFunctionDecls(pkgs)
    if (!opts.chirLLVM || opts.enableCompileTest || opts.enableHotReload || opts.mock == MockMode.ON) {
        return
    }
    for (pkg in pkgs) {
        if (!pkg.TestAttr(Attribute.IMPORTED) && !pkg.isMacroPackage) {
            CheckFuncDeclIsInline(pkg)
        }
    }
    for (pkg in pkgs) {
        SortInlineFuncDecls(pkg.inlineFuncDecls)
        if (!pkg.TestAttr(Attribute.IMPORTED)) {
            for (funcDecl in importedInlineFunctions) {
                pkg.inlineFuncDecls.add(funcDecl)
            }
            for (funcDecl in pkg.inlineFuncDecls) {
                if (funcDecl.TestAttr(Attribute.IMPORTED)) {
                    pkg.srcImportedNonGenericDecls.add(funcDecl)
                }
            }
        }
    }
}
