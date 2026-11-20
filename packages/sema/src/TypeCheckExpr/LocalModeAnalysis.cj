package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.DiagMismatchedTypesWithFoundTy

// Resolve occurrences after overload/lambda checking has selected the actual FuncTy, and
// before after-Sema rewriting. Only monomorphic class/Int64 signature slots are admitted by
// this in-memory consumer. No pending inference variable is a serializable ASTMode.
class LocalModeAnalysis {
    private let diag: BasicDiagnosticEngine
    private let scopes = ArrayList<FuncBody>()
    private let owners = HashMap<Decl, FuncBody>()
    private let parents = ArrayList<Node>()

    init(diag: BasicDiagnosticEngine) { this.diag = diag }

    func Resolve(pkg: Package): Unit {
        Walker(pkg, localVisits: true, visitPre: { node: Node =>
            parents.add(node)
            if (let Some(body) <- (node as FuncBody)) {
                scopes.add(body)
                BindSlots(body)
            }
            if ((let Some(decl) <- (node as VarDecl)) && !scopes.isEmpty()) {
                owners[decl] = scopes[scopes.size - 1]
            }
            VisitAction.WALK_CHILDREN
        }, visitPost: { node: Node =>
            ResolveValue(node)
            if (let Some(body) <- (node as FuncBody)) {
                if ((let Some(block) <- body.body) && (let Some(ft) <- Signature(body))) {
                    if ((let Some(last) <- block.GetLastExprOrDecl()) && (let Some(expr) <- (last as Expr)) &&
                        expr.astKind != ASTKind.RETURN_EXPR && !ft.retTy.IsUnit()) { CheckReturn(expr, ft.retMode) }
                }
                scopes.remove(at: scopes.size - 1)
            }
            parents.remove(at: parents.size - 1)
            VisitAction.WALK_CHILDREN
        }).Walk()
    }

    private func Signature(node: Node): Option<FuncTy> {
        let ty = node.GetTy() ?? return None
        return ty as FuncTy
    }

    private func CheckSlot(node: Node, ty: Ty, mode: ASTMode): Unit {
        if (mode != ASTMode.NOT && !(ty.kind == TypeKind.TYPE_INT64 ||
            (ty.kind == TypeKind.TYPE_CLASS && ty.typeArgs.isEmpty() && !(ty is ClassThisTy)))) {
            DiagMismatchedTypesWithFoundTy(diag, node, "a concrete class or Int64 local-mode slot", ty.String())
        }
        if (let Some(ft) <- (ty as FuncTy)) {
            for (i in 0..ft.paramTys.size) { CheckSlot(node, ft.paramTys[i], ft.ParamMode(i)) }
            CheckSlot(node, ft.retTy, ft.retMode)
        }
    }

    private func HasMode(ft: FuncTy): Bool {
        if (ft.retMode != ASTMode.NOT) { return true }
        for (i in 0..ft.paramTys.size) {
            if (ft.ParamMode(i) != ASTMode.NOT) { return true }
            if ((let Some(nested) <- (ft.paramTys[i] as FuncTy)) && HasMode(nested)) { return true }
        }
        if (let Some(nested) <- (ft.retTy as FuncTy)) { return HasMode(nested) }
        return false
    }

    private func BindSlots(body: FuncBody): Unit {
        let ft = Signature(body) ?? return;
        if (body.paramLists.isEmpty()) { return }
        if (HasMode(ft) && (body.generic.isSome() || ft.HasGeneric())) {
            DiagMismatchedTypesWithFoundTy(diag, body, "a monomorphic local-mode signature", ft.String())
        }
        let params = body.paramLists[0].params
        if (params.size != ft.paramTys.size) { return }
        for (i in 0..params.size) {
            // An unannotated lambda parameter takes its final contextual slot. Without a
            // contextual bound SynLamExpr constructs a NOT slot; generic modal slots stay closed.
            params[i].resolvedMode = ft.ParamMode(i)
            CheckSlot(params[i], ft.paramTys[i], ft.ParamMode(i))
        }
        CheckSlot(body, ft.retTy, ft.retMode)
        if (let Some(ret) <- body.retType) { ret.resolvedMode = ft.retMode }
    }

    private func Check(value: Node, expected: ASTMode): Unit {
        let mode = value.resolvedMode
        if (mode.IsSubMode(expected)) { return }
        let ty = value.GetTy() ?? return;
        if (ty.kind == TypeKind.TYPE_INT64) { return } // admitted Copyable slot
        DiagMismatchedTypesWithFoundTy(diag, value, ty.String() + expected.Suffix(), ty.String() + mode.Suffix())
    }

    private func External(value: Expr): Bool {
        if (let Some(paren) <- (value as ParenExpr)) {
            return if (let Some(inner) <- paren.expr) { External(inner) } else { false }
        }
        if ((let Some(ref) <- (value as RefExpr)) && (let Some(target) <- ref.GetTarget()) &&
            (let Some(param) <- (target as FuncParam))) {
            if (scopes.isEmpty()) { return false }
            if (let Some(owner) <- owners.get(param)) { return refEq(owner, scopes[scopes.size - 1]) }
        }
        return false
    }

    private func CheckReturn(value: Expr, expected: ASTMode): Unit {
        Check(value, expected)
        if (expected != ASTMode.NOT && value.resolvedMode != ASTMode.NOT &&
            value.TyKind() != TypeKind.TYPE_INT64 && !External(value)) {
            DiagMismatchedTypesWithFoundTy(diag, value, "an external local return value", "an internal local value")
        }
    }

    private func CheckStore(left: Expr, right: Expr): Unit {
        Check(right, left.resolvedMode)
        if (left.TyKind() == TypeKind.TYPE_INT64 || left.resolvedMode == ASTMode.NOT) { return }
        if (let Some(paren) <- (left as ParenExpr)) {
            if (let Some(inner) <- paren.expr) { CheckStore(inner, right) }
            return
        }
        if (left.resolvedMode == ASTMode.FULL && External(left) != External(right)) {
            DiagMismatchedTypesWithFoundTy(diag, right, "the region of the destination", "a different region")
        }
        if ((let Some(target) <- left.GetTarget()) && (let Some(owner) <- owners.get(target)) &&
            !scopes.isEmpty() && !refEq(owner, scopes[scopes.size - 1])) {
            // TypeCheckModal.cpp:1166-1174: a captured non-copy HALF variable only accepts NOT.
            Check(right, ASTMode.NOT)
        }
    }

    private func ResolveRef(ref: RefExpr): Unit {
        let decl = ref.GetTarget() ?? return;
        ref.resolvedMode = decl.resolvedMode
        if (decl.resolvedMode == ASTMode.NOT || scopes.isEmpty() ||
            decl.TyKind() == TypeKind.TYPE_INT64) { return }
        let owner = owners.get(decl) ?? return;
        let body = scopes[scopes.size - 1]
        if (refEq(body, owner)) { return }
        // LambdaExpr.cpp:633-694. FULL is never capturable; HALF requires a HALF
        // closure. Only a synthesized lambda may infer that mode from a capture.
        if (decl.resolvedMode == ASTMode.FULL || body.funcDecl.isSome()) {
            Check(ref, ASTMode.NOT)
        } else {
            body.resolvedMode = ASTMode.HALF
        }
    }

    private func ResolveCall(call: CallExpr): Unit {
        let base = call.baseFunc ?? return;
        var sig = Signature(base)
        if (sig.isNone() && (let Some(fd) <- call.resolvedFunction)) { sig = Signature(fd) }
        if (sig.isNone()) {
            for (arg in call.args) {
                if (let Some(value) <- arg.expr) { Check(value, ASTMode.NOT) }
            }
            return
        }
        let ft = sig.getOrThrow()
        call.resolvedMode = ft.retMode
        let ordered = call.desugarArgs
        if (let Some(args) <- ordered) {
            for (i in 0..args.size) {
                if (let Some(arg) <- args[i]) { CheckArgument(ft, i, arg) }
            }
        } else {
            for (i in 0..call.args.size) { CheckArgument(ft, i, call.args[i]) }
        }
    }

    private func CheckArgument(ft: FuncTy, i: Int64, arg: FuncArg): Unit {
        if (let Some(value) <- arg.expr) {
            let mode = if (i < ft.paramTys.size) { ft.ParamMode(i) } else { ASTMode.NOT }
            Check(value, mode)
            if (mode == ASTMode.FULL && value.resolvedMode == ASTMode.FULL &&
                value.TyKind() != TypeKind.TYPE_INT64 && External(value)) {
                DiagMismatchedTypesWithFoundTy(diag, value, "an internal local argument", "an external local value")
            }
        }
    }

    private func ResolveValue(node: Node): Unit {
        if (let Some(typeNode) <- (node as Type)) {
            if (let Some(ft) <- Signature(typeNode)) { CheckSlot(typeNode, ft, ASTMode.NOT) }
        } else if (let Some(ref) <- (node as RefExpr)) {
            ResolveRef(ref)
        } else if (let Some(call) <- (node as CallExpr)) {
            ResolveCall(call)
        } else if (let Some(paren) <- (node as ParenExpr)) {
            if (let Some(inner) <- paren.expr) { node.resolvedMode = inner.resolvedMode }
        } else if (let Some(arg) <- (node as FuncArg)) {
            if (let Some(value) <- arg.expr) { arg.resolvedMode = value.resolvedMode }
        } else if (let Some(block) <- (node as Block)) {
            if ((let Some(last) <- block.GetLastExprOrDecl()) && last.IsExpr() &&
                block.TyKind() != TypeKind.TYPE_UNIT) { node.resolvedMode = last.resolvedMode }
        } else if (let Some(decl) <- (node as VarDeclAbstract)) {
            if ((let Some(p) <- (decl as FuncParam)) && (let Some(defaultValue) <- p.assignment)) {
                Check(defaultValue, p.resolvedMode)
            }
            if ((let Some(initExpr) <- decl.initializer) && decl.astKind != ASTKind.FUNC_PARAM) {
                if (decl.typeNode.isNone() && !scopes.isEmpty() && decl.astKind == ASTKind.VAR_DECL &&
                    !decl.IsMemberDecl() && !decl.TestAttr(Attribute.GLOBAL)) {
                    decl.resolvedMode = initExpr.resolvedMode
                    if (decl.resolvedMode == ASTMode.FULL && decl.TyKind() != TypeKind.TYPE_INT64 && External(initExpr)) {
                        DiagMismatchedTypesWithFoundTy(diag, initExpr, "an internal local initializer", "an external local value")
                    }
                } else {
                    Check(initExpr, ASTMode.NOT)
                }
            }
        } else if (let Some(assign) <- (node as AssignExpr)) {
            if ((let Some(left) <- assign.leftValue) && (let Some(right) <- assign.rightExpr)) {
                CheckStore(left, right)
            }
        } else if (let Some(ret) <- (node as ReturnExpr)) {
            if (!scopes.isEmpty() && (let Some(ft) <- Signature(scopes[scopes.size - 1])) &&
                (let Some(value) <- ret.expr)) { CheckReturn(value, ft.retMode) }
        } else if (let Some(lambda) <- (node as LambdaExpr)) {
            if (let Some(body) <- lambda.funcBody) { lambda.resolvedMode = body.resolvedMode }
        }

        // Unsupported modal uses must not discard a non-Copyable mode, e.g. aggregate
        // construction or a store into a global/field. Never infer a region from spelling.
        if (node.resolvedMode == ASTMode.NOT || !(node is Expr) || parents.size < 2) { return }
        let parent = parents[parents.size - 2]
        if (!(parent is VarDeclAbstract || parent is Block || parent is FuncBody || parent is FuncArg ||
            parent is CallExpr || parent is ParenExpr || parent is AssignExpr || parent is ReturnExpr)) {
            Check(node, ASTMode.NOT)
        }
    }
}
