package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.{DiagMismatchedTypesWithFoundTy, GenerateTypeMapping, TypeManager}

// Resolve modes after overload and lambda selection, before AST rewrites lose lexical owners.
class LocalModeAnalysis {
    private let diag: BasicDiagnosticEngine
    private let scopes = ArrayList<FuncBody>()
    private let owners = HashMap<Decl, FuncBody>()
    private let declaredIn = HashMap<Decl, Node>()
    private let parents = ArrayList<Node>()

    private let typeManager: TypeManager

    init(diag: BasicDiagnosticEngine, typeManager: TypeManager) { this.diag = diag; this.typeManager = typeManager }

    func Resolve(pkg: Package): Unit {
        Walker(pkg, localVisits: true, visitPre: { node: Node =>
            parents.add(node)
            if (let Some(body) <- (node as FuncBody)) {
                scopes.add(body)
                BindSlots(body)
            }
            if ((let Some(decl) <- (node as VarDecl)) && !scopes.isEmpty()) {
                owners[decl] = scopes[scopes.size - 1]
                if (let Some(region) <- ExclaveOwner()) { declaredIn[decl] = region }
            }
            VisitAction.WALK_CHILDREN
        }, visitPost: { node: Node =>
            ResolveValue(node)
            if (let Some(body) <- (node as FuncBody)) {
                if ((let Some(block) <- body.body) && (let Some(ft) <- Signature(body))) {
                    if ((let Some(last) <- block.GetLastExprOrDecl()) && (let Some(expr) <- (last as Expr)) &&
                        expr.astKind != ASTKind.RETURN_EXPR && !(expr is ExclaveExpr) && !ft.retTy.IsUnit()) { CheckReturn(expr, ft.retMode) }
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

    private func CopyType(ty: Ty): Bool { return typeManager.IsModalCopyType(ty) }

    private func CopyNode(node: Node): Bool { return node.GetTy().map({ ty => CopyType(ty) }) ?? false }

    private func CheckSlot(node: Node, ty: Ty, mode: ASTMode): Unit {
        if (mode != ASTMode.NOT && (!Ty.IsTyCorrect(ty) || ty.HasQuestTy() || ty.HasIdealTy())) {
            DiagMismatchedTypesWithFoundTy(diag, node, "a resolved local-mode slot", ty.String())
        }
        if (let Some(ft) <- (ty as FuncTy)) {
            for (i in 0..ft.paramTys.size) { CheckSlot(node, ft.paramTys[i], ft.ParamMode(i)) }
            CheckSlot(node, ft.retTy, ft.retMode)
        }
    }

    // The owner stops at a function boundary: a nested lambda starts its own region.
    private func ExclaveOwner(): Option<Node> {
        var i = parents.size
        while (i > 0) {
            i--
            if (parents[i] is ExclaveExpr) { return parents[i] }
            if (let Some(body) <- (parents[i] as FuncBody)) {
                if ((let Some(fd) <- body.funcDecl) && HasLocalModifier(fd, TokenKind.EXCLAVE)) { return fd }
                return None
            }
        }
        return None
    }

    private func AllowsExclave(body: FuncBody, ft: FuncTy): Bool {
        if (let Some(fd) <- body.funcDecl) {
            if (fd.IsFinalizer() || fd.TestAttr(Attribute.MAIN_ENTRY) ||
                (fd.TestAttr(Attribute.STATIC) && fd.TestAttr(Attribute.CONSTRUCTOR))) { return false }
            let mode = GetReceiverMode(fd)
            if (fd.TestAttr(Attribute.CONSTRUCTOR) && mode != ASTMode.NOT) { return true }
            if (mode == ASTMode.FULL && (let Some(owner) <- fd.outerDecl) && !CopyNode(owner)) { return true }
        }
        if (ft.retMode != ASTMode.NOT && !CopyType(ft.retTy)) { return true }
        for (i in 0..ft.paramTys.size) {
            if (ft.ParamMode(i) == ASTMode.FULL && !CopyType(ft.paramTys[i])) { return true }
        }
        return false
    }

    private func CheckExclave(ex: ExclaveExpr): Unit {
        var valid = false
        if (!scopes.isEmpty()) {
            let body = scopes[scopes.size - 1]
            if ((let Some(ft) <- Signature(body)) && AllowsExclave(body, ft)) {
                var j = parents.size - 1
                while (j > 0) {
                    j--
                    if (parents[j] is ExclaveExpr || parents[j] is TryExpr || parents[j] is SpawnExpr) { break }
                    if (let Some(b) <- body.body) { if (refEq(parents[j], b)) { valid = true } }
                    if (refEq(parents[j], body)) { break }
                }
                if ((let Some(fd) <- body.funcDecl) && HasLocalModifier(fd, TokenKind.EXCLAVE)) { valid = false }
            }
            if ((let Some(block) <- ex.body) && (let Some(ft) <- Signature(body)) && !ft.retTy.IsUnit()) {
                if ((let Some(last) <- block.GetLastExprOrDecl()) && (let Some(value) <- (last as Expr))) {
                    if (!(value is ReturnExpr) && !(value.GetTy().map({ t => t.IsNothing() }) ?? false)) {
                        Check(value, ft.retMode)
                    }
                }
            }
        }
        if (!valid) { DiagMismatchedTypesWithFoundTy(diag, ex, "a local function body permitting exclave", "exclave") }
    }

    private func BindSlots(body: FuncBody): Unit {
        let ft = Signature(body) ?? return;
        if (body.paramLists.isEmpty()) { return }
        if (let Some(fd) <- body.funcDecl) {
            let whole = HasLocalModifier(fd, TokenKind.EXCLAVE)
            if (whole && (!AllowsExclave(body, ft) || fd.TestAttr(Attribute.ABSTRACT))) {
                DiagMismatchedTypesWithFoundTy(diag, fd, "a concrete local function signature", "exclave")
            }
            if (!whole && fd.TestAttr(Attribute.CONSTRUCTOR) && GetReceiverMode(fd) != ASTMode.NOT &&
                (let Some(block) <- body.body) && (block.body.size != 1 || !(block.body[0] is ExclaveExpr))) {
                DiagMismatchedTypesWithFoundTy(diag, fd, "constructor body enclosed in exclave", fd.identifier.Val())
            }
        }
        if (let Some(receiver) <- body.paramLists[0].receiverModal) {
            if ((body.funcDecl.map({ fd => IsInstanceMember(fd) && !fd.TestAttr(Attribute.STATIC) }) ?? false) == false) {
                DiagMismatchedTypesWithFoundTy(diag, body, "an instance receiver", receiver.local.Suffix())
            }
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
        if (CopyType(ty)) { return }
        DiagMismatchedTypesWithFoundTy(diag, value, ty.String() + expected.Suffix(), ty.String() + mode.Suffix())
    }

    // The result of a conditional never comes from its condition, selector, or finally block.
    private func ResultBranches(value: Expr): ArrayList<Expr> {
        let out = ArrayList<Expr>()
        if (let Some(paren) <- (value as ParenExpr)) {
            if (let Some(inner) <- paren.expr) { out.add(inner) }
        } else if (let Some(block) <- (value as Block)) {
            if ((let Some(last) <- block.GetLastExprOrDecl()) && (let Some(e) <- (last as Expr))) { out.add(e) }
        } else if (let Some(ie) <- (value as IfExpr)) {
            if (let Some(b) <- ie.thenBody) { out.add(b) }
            if (let Some(b) <- ie.elseBody) { out.add(b) }
        } else if (let Some(me) <- (value as MatchExpr)) {
            for (c in me.matchCases) { if (let Some(b) <- c.exprOrDecls) { out.add(b) } }
            for (c in me.matchCaseOthers) { if (let Some(b) <- c.exprOrDecls) { out.add(b) } }
        } else if (let Some(te) <- (value as TryExpr)) {
            if (let Some(b) <- te.tryBlock) { out.add(b) }
            for (b in te.catchBlocks) { out.add(b) }
        }
        return out
    }

    private func MergeBranchModes(value: Expr): Unit {
        if (value.TyKind() == TypeKind.TYPE_UNIT || CopyNode(value)) { return }
        var result: Option<ASTMode> = None
        for (branch in ResultBranches(value)) {
            if (branch.GetTy().map({ t => t.IsNothing() }) ?? false) { continue }
            if ((let Some(prior) <- result) && prior != branch.resolvedMode) {
                result = Some(ASTMode.HALF)
            } else { result = Some(branch.resolvedMode) }
        }
        value.resolvedMode = result ?? ASTMode.NOT
    }

    private func IsBranchChild(parent: Node, child: Node): Bool {
        if (let Some(c) <- (parent as MatchCase)) { return c.exprOrDecls.map({ b => refEq(b, child) }) ?? false }
        if (let Some(c) <- (parent as MatchCaseOther)) { return c.exprOrDecls.map({ b => refEq(b, child) }) ?? false }
        if (let Some(e) <- (parent as Expr)) {
            for (result in ResultBranches(e)) { if (refEq(result, child)) { return true } }
        }
        return false
    }

    private func External(value: Expr): Bool {
        // Entering an exclave ends this frame's region. Permitted operands now live in
        // the caller's region. Return validation handles values leaving that region.
        if (ExclaveOwner().isSome()) { return false }
        for (branch in ResultBranches(value)) { if (External(branch)) { return true } }
        if (let Some(index) <- (value as SubscriptExpr)) {
            if (index.isTupleAccess || (index.baseExpr.map({ e => e.TyKind() == TypeKind.TYPE_VARRAY }) ?? false)) {
                return index.baseExpr.map({ b => External(b) }) ?? false
            }
        }
        if (let Some(paren) <- (value as ParenExpr)) {
            return if (let Some(inner) <- paren.expr) { External(inner) } else { false }
        }
        if (let Some(ma) <- (value as MemberAccess)) {
            return ma.baseExpr.map({ base => External(base) }) ?? false
        }
        if (let Some(ref) <- (value as RefExpr)) {
            if (ref.isThis || ref.isSuper) { return true }
            if ((let Some(d) <- ref.GetTarget()) && (d.IsMemberDecl() || d.TestAttr(Attribute.GLOBAL) ||
                d.TestAttr(Attribute.STATIC))) { return true }
        }
        if ((let Some(ref) <- (value as RefExpr)) && (let Some(target) <- ref.GetTarget()) &&
            (let Some(param) <- (target as FuncParam))) {
            if (scopes.isEmpty()) { return false }
            if (let Some(owner) <- owners.get(param)) { return refEq(owner, scopes[scopes.size - 1]) }
        }
        return false
    }

    private func CheckReturn(value: Expr, expected: ASTMode): Unit {
        let parts = ResultBranches(value)
        if (!parts.isEmpty()) {
            for (part in parts) {
                if (!(part.GetTy().map({ t => t.IsNothing() }) ?? false)) { CheckReturn(part, expected) }
            }
            return
        }
        Check(value, expected)
        if (expected != ASTMode.NOT && value.resolvedMode != ASTMode.NOT &&
            !CopyNode(value) && ExclaveOwner().isNone() && !External(value)) {
            DiagMismatchedTypesWithFoundTy(diag, value, "an external local return value", "an internal local value")
        }
    }

    private func CheckStore(left: Expr, right: Expr): Unit {
        Check(right, left.resolvedMode)
        if (CopyNode(left) || left.resolvedMode == ASTMode.NOT) { return }
        if (let Some(paren) <- (left as ParenExpr)) {
            if (let Some(inner) <- paren.expr) { CheckStore(inner, right) }
            return
        }
        if (left.resolvedMode == ASTMode.HALF && right.resolvedMode != ASTMode.NOT &&
            (left.GetTarget().map({ target => target.IsMemberDecl() }) ?? false)) {
            let fd: Option<FuncDecl> = if (scopes.isEmpty()) { None } else { scopes[scopes.size - 1].funcDecl }
            let allowed = fd.map({ f => f.IsFinalizer() || (f.TestAttr(Attribute.CONSTRUCTOR) &&
                GetReceiverMode(f) == ASTMode.HALF) }) ?? false
            let own = if (let Some(ma) <- (left as MemberAccess)) {
                if ((let Some(base) <- ma.baseExpr) && (let Some(r) <- (base as RefExpr))) { r.isThis || r.isSuper } else { false }
            } else { left is RefExpr }
            if (!allowed || !own) { DiagMismatchedTypesWithFoundTy(diag, right, "a field in the destination region", "local? field") }
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

    private func IsCallTarget(expr: Expr): Bool {
        if (parents.size < 2) { return false }
        let call = (parents[parents.size - 2] as CallExpr) ?? return false;
        return call.baseFunc.map({ base => refEq(base, expr) }) ?? false
    }

    private func ResolveRef(ref: RefExpr): Unit {
        if ((ref.isThis || ref.isSuper) && !scopes.isEmpty()) {
            for (i in 0..scopes.size) {
                if (let Some(fd) <- scopes[scopes.size - 1 - i].funcDecl) {
                    ref.resolvedMode = GetReceiverMode(fd)
                    if (i > 0 && ref.resolvedMode != ASTMode.NOT) { Check(ref, ASTMode.NOT) }
                    return
                }
            }
        }
        let decl = ref.GetTarget() ?? return;
        ref.resolvedMode = decl.resolvedMode
        if (decl is FuncDecl && IsInstanceMember(decl) && !IsCallTarget(ref) && !scopes.isEmpty() &&
            (let Some(owner) <- scopes[scopes.size - 1].funcDecl) && GetReceiverMode(owner) != ASTMode.NOT) {
            DiagMismatchedTypesWithFoundTy(diag, ref, "an unbound method or non-local receiver", "bound local receiver")
        }
        if (let Some(pd) <- (decl as PropDecl)) {
            ref.resolvedMode = PropertyMode(pd)
        } else if (decl is VarDecl && IsInstanceMember(decl) && !HasLocalModifier(decl, TokenKind.DEMODE)) {
            for (i in 0..scopes.size) {
                if (let Some(fd) <- scopes[scopes.size - 1 - i].funcDecl) {
                    ref.resolvedMode = GetReceiverMode(fd)
                    if (i > 0) { Check(ref, ASTMode.NOT) }
                    break
                }
            }
        }
        if ((let Some(region) <- ExclaveOwner()) && !(decl is FuncParam) && !decl.IsMemberDecl() &&
            owners.contains(decl) && !CopyNode(decl) && ref.resolvedMode != ASTMode.NOT &&
            !(declaredIn.get(decl).map({ owner => refEq(owner, region) }) ?? false)) {
            DiagMismatchedTypesWithFoundTy(diag, ref, "a value live in the exclave", decl.identifier.Val())
        }
        if (decl.resolvedMode == ASTMode.NOT || scopes.isEmpty() ||
            CopyNode(decl)) { return }
        let owner = owners.get(decl) ?? return;
        let body = scopes[scopes.size - 1]
        if (refEq(body, owner)) { return }
        // LambdaExpr.cpp:633-694. FULL is never capturable; HALF requires a HALF
        // closure. Only a synthesized lambda may infer that mode from a capture.
        if (decl.resolvedMode == ASTMode.FULL || body.funcDecl.isSome()) {
            Check(ref, ASTMode.NOT)
        } else {
            for (i in 0..scopes.size) {
                let captureBody = scopes[scopes.size - 1 - i]
                if (refEq(captureBody, owner)) { break }
                if (captureBody.funcDecl.isSome()) { Check(ref, ASTMode.NOT); break }
                captureBody.resolvedMode = ASTMode.HALF
            }
        }
    }

    private func ResolveCall(call: CallExpr): Unit {
        let base = call.baseFunc ?? return;
        if ((let Some(lowered) <- call.desugarExpr) && (let Some(array) <- (lowered as ArrayExpr)) && !array.isValueArray) {
            call.resolvedMode = array.resolvedMode
            for (arg in array.args) {
                if (let Some(value) <- arg.expr) { Check(value, ASTMode.NOT) }
            }
            return
        }
        var decl = call.resolvedFunction
        if (decl.isNone() && (let Some(target) <- base.GetTarget())) { decl = target as FuncDecl }
        let ctor = call.callKind == CallKind.CALL_OBJECT_CREATION || call.callKind == CallKind.CALL_STRUCT_CREATION
        let enumCtor = decl.map({ fd => fd.TestAttr(Attribute.ENUM_CONSTRUCTOR) }) ?? false
        var createdMode = if (ctor) { decl.map({ fd => GetReceiverMode(fd) }) ?? ASTMode.NOT } else { ASTMode.NOT }
        if (let Some(postfix) <- call.modal) {
            if ((!ctor && !enumCtor) || (ctor && createdMode != postfix.local)) {
                DiagMismatchedTypesWithFoundTy(diag, call, "a matching constructor receiver", postfix.local.Suffix())
                return
            }
            createdMode = postfix.local
        }
        if (!ctor && !enumCtor && (let Some(fd) <- decl) && IsInstanceMember(fd)) {
            let mode = GetReceiverMode(fd)
            if ((let Some(ma) <- (base as MemberAccess)) && (let Some(receiver) <- ma.baseExpr)) {
                Check(receiver, mode)
                if (mode == ASTMode.FULL && receiver.resolvedMode == ASTMode.FULL && !CopyNode(receiver) &&
                    ExclaveOwner().isNone() && External(receiver)) {
                    DiagMismatchedTypesWithFoundTy(diag, receiver, "an internal local receiver", "an external local value")
                }
            } else if (!scopes.isEmpty() && (let Some(owner) <- scopes[scopes.size - 1].funcDecl)) {
                let actual = GetReceiverMode(owner)
                if (!actual.IsSubMode(mode) || (mode == ASTMode.FULL && ExclaveOwner().isNone())) {
                    DiagMismatchedTypesWithFoundTy(diag, call, "receiver" + mode.Suffix(), "this" + actual.Suffix())
                }
            }
        }
        if (ctor || enumCtor) { call.resolvedMode = createdMode }
        var sig = Signature(base)
        if (sig.isNone() && (let Some(fd) <- call.resolvedFunction)) { sig = Signature(fd) }
        if (sig.isNone()) {
            for (arg in call.args) {
                if (let Some(value) <- arg.expr) { Check(value, ASTMode.NOT) }
            }
            return
        }
        let ft = sig.getOrThrow()
        if (!ctor && !enumCtor) { call.resolvedMode = ft.retMode }
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
                !CopyNode(value) && ExclaveOwner().isNone() && External(value)) {
                DiagMismatchedTypesWithFoundTy(diag, value, "an internal local argument", "an external local value")
            }
        }
    }

    private func CopyMarkerIn(ty: Ty): Bool {
        if (typeManager.IsCopyInterface(ty)) { return true }
        if (let Some(ft) <- (ty as FuncTy)) {
            for (arg in ft.paramTys) { if (CopyMarkerIn(arg)) { return true } }
            return CopyMarkerIn(ft.retTy)
        }
        for (arg in ty.typeArgs) { if (CopyMarkerIn(arg)) { return true } }
        return false
    }

    private func CheckCopyMarker(t: Type): Unit {
        let ty = t.GetTy() ?? return;
        if (!Ty.IsTyCorrect(ty) || !CopyMarkerIn(ty)) { return }
        if (typeManager.IsCopyInterface(ty) && parents.size > 1) {
            let parent = parents[parents.size - 2]
            if (let Some(gc) <- (parent as GenericConstraint)) {
                for (upper in gc.upperBounds) { if (refEq(upper, t)) { return } }
            }
            if (let Some(id) <- (parent as InheritableDecl)) {
                for (superType in id.inheritedTypes) {
                    if (refEq(superType, t)) {
                        if (id is StructDecl) { return }
                        if ((let Some(ed) <- (id as ExtendDecl)) &&
                            (ed.extendedType.flatMap({ n => n.GetTy() }).map({ v => v.IsStruct() }) ?? false)) { return }
                        break
                    }
                }
            }
        }
        DiagMismatchedTypesWithFoundTy(diag, t, "a data type, or Copyable as a struct conformance or bound", ty.String())
    }

    private func CheckCopyFields(id: InheritableDecl): Unit {
        var copy = false
        for (superType in id.inheritedTypes) {
            if (superType.GetTy().map({ t => typeManager.IsCopyInterface(t) }) ?? false) { copy = true; break }
        }
        if (!copy) { return }
        let ty = if (let Some(ed) <- (id as ExtendDecl)) { ed.extendedType.flatMap({ t => t.GetTy() }) }
            else { id.GetTy() }
        let data = ty ?? return;
        if (!data.IsStruct()) { return }
        let decl = Ty.GetDeclPtrOfTy(ty) ?? return;
        let mapping = GenerateTypeMapping(decl, data.typeArgs)
        for (member in decl.GetMemberDecls()) {
            if (member is VarDecl && !(member is PropDecl) && !member.TestAttr(Attribute.STATIC) &&
                (let Some(ft) <- member.GetTy()) && Ty.IsTyCorrect(ft) &&
                !CopyType(typeManager.GetInstantiatedTy(ft, mapping))) {
                DiagMismatchedTypesWithFoundTy(diag, member, "a copyable stored field", ft.String())
            }
        }
    }

    private func ResolveValue(node: Node): Unit {
        if (let Some(id) <- (node as InheritableDecl)) {
            CheckCopyFields(id)
        } else if (let Some(typeNode) <- (node as Type)) {
            CheckCopyMarker(typeNode)
            if (let Some(ft) <- Signature(typeNode)) { CheckSlot(typeNode, ft, ASTMode.NOT) }
        } else if (let Some(ref) <- (node as RefExpr)) {
            ResolveRef(ref)
        } else if (let Some(ex) <- (node as ExclaveExpr)) {
            CheckExclave(ex)
        } else if (let Some(ma) <- (node as MemberAccess)) {
            if ((let Some(base) <- ma.baseExpr) && ma.GetTarget().isNone()) { Check(base, ASTMode.NOT) }
            if ((let Some(base) <- ma.baseExpr) && (let Some(target) <- ma.GetTarget())) {
                if (let Some(pd) <- (target as PropDecl)) {
                    ma.resolvedMode = PropertyMode(pd)
                    if (IsInstanceMember(pd)) { Check(base, PropertyMode(pd)) }
                } else if (target is VarDecl && IsInstanceMember(target)) {
                    ma.resolvedMode = if (HasLocalModifier(target, TokenKind.DEMODE)) { ASTMode.NOT } else { base.resolvedMode }
                } else if (!(target is FuncDecl && IsCallTarget(ma))) {
                    Check(base, ASTMode.NOT)
                }
            }
        } else if (let Some(call) <- (node as CallExpr)) {
            ResolveCall(call)
        } else if (let Some(tuple) <- (node as TupleLit)) {
            var joined: Option<ASTMode> = None
            for (value in tuple.children) {
                if (CopyNode(value)) { continue }
                joined = if ((let Some(mode) <- joined) && mode != value.resolvedMode) {
                    Some(ASTMode.HALF)
                } else { Some(value.resolvedMode) }
            }
            tuple.resolvedMode = joined ?? ASTMode.NOT
            if (tuple.resolvedMode == ASTMode.FULL) {
                for (value in tuple.children) {
                    if (!CopyNode(value) && External(value)) {
                        DiagMismatchedTypesWithFoundTy(diag, value, "a value in the tuple's region", "an external local element")
                    }
                }
            }
        } else if (let Some(index) <- (node as SubscriptExpr)) {
            if (index.isTupleAccess || index.IsVArrayAccess()) {
                if (let Some(base) <- index.baseExpr) { index.resolvedMode = base.resolvedMode }
            } else if (let Some(call) <- index.desugarExpr) {
                index.resolvedMode = call.resolvedMode
            }
        } else if (let Some(paren) <- (node as ParenExpr)) {
            if (let Some(inner) <- paren.expr) { node.resolvedMode = inner.resolvedMode }
        } else if (let Some(arg) <- (node as FuncArg)) {
            if (let Some(value) <- arg.expr) { arg.resolvedMode = value.resolvedMode }
        } else if (node is IfExpr || node is MatchExpr || node is TryExpr) {
            MergeBranchModes((node as Expr).getOrThrow())
        } else if (let Some(block) <- (node as Block)) {
            if ((let Some(last) <- block.GetLastExprOrDecl()) && last.IsExpr() &&
                block.TyKind() != TypeKind.TYPE_UNIT) { node.resolvedMode = last.resolvedMode }
        } else if (let Some(decl) <- (node as VarDeclAbstract)) {
            if (!(decl is FuncParam) && !(decl is PropDecl) && (decl.IsMemberDecl() ||
                decl.TestAttr(Attribute.GLOBAL) || decl.TestAttr(Attribute.STATIC)) &&
                (let Some(t) <- decl.typeNode) && t.resolvedMode != ASTMode.NOT) {
                DiagMismatchedTypesWithFoundTy(diag, t, "a non-local stored declaration", t.resolvedMode.Suffix())
            }
            if ((let Some(p) <- (decl as FuncParam)) && (let Some(defaultValue) <- p.assignment)) {
                Check(defaultValue, p.resolvedMode)
            }
            if ((let Some(initExpr) <- decl.initializer) && decl.astKind != ASTKind.FUNC_PARAM) {
                if (!scopes.isEmpty() && decl.astKind == ASTKind.VAR_DECL &&
                    !decl.IsMemberDecl() && !decl.TestAttr(Attribute.GLOBAL)) {
                    decl.resolvedMode = decl.typeNode.map({ t => t.resolvedMode }) ?? initExpr.resolvedMode
                    Check(initExpr, decl.resolvedMode)
                    if (decl.resolvedMode == ASTMode.FULL && !CopyNode(decl) && External(initExpr)) {
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
        if (IsBranchChild(parent, node) || parent is TupleLit) { return }
        if (let Some(index) <- (parent as SubscriptExpr)) {
            if (index.baseExpr.map({ b => refEq(b, node) }) ?? false) { return }
            if (index.desugarExpr.map({ e => refEq(e, node) }) ?? false) { return }
        }
        if (!(parent is VarDeclAbstract || parent is Block || parent is FuncBody || parent is FuncArg ||
            parent is MemberAccess || parent is ExclaveExpr || parent is CallExpr || parent is ParenExpr || parent is AssignExpr || parent is ReturnExpr)) {
            Check(node, ASTMode.NOT)
        }
    }
}
