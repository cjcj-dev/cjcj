package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateZeroValue, WithinFile}
import cjcj::utils.CJC_ASSERT_WITH_MSG

// Upstream a51ced71, AfterTypeCheck/Interop/MoveImplMembersToRegCompanion.cpp:38-62.
private class ProxiedMembers {
    private let proxies = ArrayList<Decl>()
    private let byOrigin = HashMap<Decl, Decl>()

    public func Add(origin: Decl, proxy: Decl): Unit {
        byOrigin[origin] = proxy
        proxies.add(proxy)
    }

    public func Find(origin: Decl): Option<Decl> {
        return byOrigin.get(origin)
    }

    public func InDeclarationOrder(): ArrayList<Decl> {
        return proxies
    }
}

private class MoveTarget {
    public let impl: ClassDecl
    public let regCompanion: ClassDecl
    public let regCompField: VarDecl

    public init(impl: ClassDecl, regCompanion: ClassDecl, regCompField: VarDecl) {
        this.impl = impl
        this.regCompanion = regCompanion
        this.regCompField = regCompField
    }
}

private func OpenUpForRegCompanions(moved: Decl): Unit {
    moved.DisableAttr(Attribute.PRIVATE)
    moved.DisableAttr(Attribute.INTERNAL)
    moved.DisableAttr(Attribute.PUBLIC)
    moved.EnableAttr(Attribute.PROTECTED)
}

// Upstream a51ced71, MoveImplMembersToRegCompanion.cpp:82-123.
private func RewireMovedField(vd: VarDecl, target: MoveTarget, ctx: InteropContext,
    proxied: ProxiedMembers): Bool {
    if (IsObjCImplRegistryCompanionField(vd)) {
        return false
    }
    if (vd.TestAttr(Attribute.STATIC) && vd.isConst) {
        return false
    }
    let proxy = PropDecl()
    ctx.astInserter.BindTo(target.impl, proxy)
    if (vd.TestAttr(Attribute.STATIC)) {
        ctx.astTransformer.TransformToObjCImplProxyProp(proxy, vd, target.regCompanion)
    } else {
        ctx.astTransformer.TransformToObjCImplProxyProp(proxy, vd, target.regCompField)
        vd.isVar = true
        if (vd.initializer.isNone()) {
            vd.initializer = Some(CreateZeroValue(ctx.importManager, ctx.typeManager, vd.GetTy().getOrThrow()))
        }
    }
    OpenUpForRegCompanions(vd)
    proxied.Add(vd, proxy)
    return true
}

// Upstream a51ced71, MoveImplMembersToRegCompanion.cpp:125-152.
private func RewireMovedFunc(fd: FuncDecl, target: MoveTarget, ctx: InteropContext,
    proxied: ProxiedMembers): Bool {
    if (fd.IsFinalizer()) {
        return true
    }
    CJC_ASSERT_WITH_MSG(!IsStaticInitializer(fd), "@ObjCImpl static initializer is rejected by the parser")
    if (fd.TestAttr(Attribute.STATIC)) {
        let proxy = (ASTCloner.Clone(fd) as FuncDecl).getOrThrow()
        ctx.astInserter.BindTo(target.impl, proxy)
        ctx.astTransformer.TransformToObjCImplStaticProxyFunc(proxy, fd, target.regCompanion)
        OpenUpForRegCompanions(fd)
        proxied.Add(fd, proxy)
        return true
    }
    return false
}

private enum Region <: Equatable<Region> {
    | ELSEWHERE
    | IMPL
    | REG_COMPANION
    public operator func ==(other: Region): Bool {
        return match ((this, other)) {
            case (ELSEWHERE, ELSEWHERE) | (IMPL, IMPL) | (REG_COMPANION, REG_COMPANION) => true
            case _ => false
        }
    }
    public operator func !=(other: Region): Bool { return !(this == other) }
}

private func RegionOf(cd: ClassDecl): Region {
    if (IsObjCImplRegistryCompanion(cd)) {
        return Region.REG_COMPANION
    }
    return if (IsObjCImpl(cd)) { Region.IMPL } else { Region.ELSEWHERE }
}

private func IsNamedOnAnotherInstance(node: Node): Bool {
    let ma = node as MemberAccess
    if (ma.isNone()) {
        return false
    }
    let base = ma.getOrThrow().baseExpr.getOrThrow() as RefExpr
    if (let Some(ref) <- base) {
        if (ref.isThis || ref.isSuper) {
            return false
        }
        return ref.ref.target.isNone() || !(ref.ref.target.getOrThrow() is ClassDecl)
    }
    return true
}

private func RequalifyToRegCompanion(ctx: InteropContext, node: Node): Unit {
    if (let Some(ma) <- (node as MemberAccess)) {
        if (let Some(base) <- (ma.baseExpr.getOrThrow() as RefExpr)) {
            if (base.isThis || base.isSuper || base.ref.target.isNone()) {
                return
            }
            if (let Some(named) <- ctx.implToRegCompanion.get(base.ref.target.getOrThrow())) {
                ma.baseExpr = Some(WithinFile<RefExpr>(CreateRefExpr(named), node.curFile))
            }
        }
    }
}

private func GetCalleeNamedOnSelf(call: CallExpr): Option<Decl> {
    if (let Some(ref) <- (call.baseFunc.getOrThrow() as RefExpr)) {
        return ref.ref.target
    }
    if (let Some(ma) <- (call.baseFunc.getOrThrow() as MemberAccess)) {
        if (let Some(base) <- (ma.baseExpr.getOrThrow() as RefExpr)) {
            if (base.isThis || base.isSuper) {
                return ma.target
            }
        }
    }
    return None
}

private func FindImportedMovedMember(ctx: InteropContext, impl: ClassDecl, proxy: Decl): Option<Decl> {
    let regCompanion = ctx.GetRegCompanion(impl)
    if (regCompanion.isNone()) {
        return None
    }
    if (let Some(accessor) <- (proxy as FuncDecl)) {
        if (let Some(proxyProperty) <- accessor.propDecl) {
            for (member in regCompanion.getOrThrow().GetMemberDecls()) {
                if (member is VarDecl && member.identifier.Val() == proxyProperty.identifier.Val()) {
                    return Some(member)
                }
            }
            return None
        }
    }
    for (member in regCompanion.getOrThrow().GetMemberDecls()) {
        if (member is FuncDecl && member.identifier.Val() == proxy.identifier.Val() &&
            member.GetTy() == proxy.GetTy()) {
            return Some(member)
        }
    }
    return None
}

private func RetargetCallee(call: CallExpr, callee: FuncDecl): Unit {
    if (let Some(ref) <- (call.baseFunc.getOrThrow() as RefExpr)) {
        ref.ref.target = Some(callee)
    } else {
        (call.baseFunc.getOrThrow() as MemberAccess).getOrThrow().target = Some(callee)
    }
    call.resolvedFunction = Some(callee)
}

// Upstream a51ced71, MoveImplMembersToRegCompanion.cpp:302-344.
private func ResolveToImportedMovedMember(ctx: InteropContext, call: CallExpr): Unit {
    let proxy = GetCalleeNamedOnSelf(call)
    if (proxy.isNone() || !IsObjCImplMovedMemberProxy(proxy.getOrThrow())) {
        return
    }
    let impl = GetOwnerClass(proxy.getOrThrow())
    if (impl.isNone() || impl.getOrThrow().fullPackageName == ctx.pkg.fullPackageName) {
        return
    }
    let moved = FindImportedMovedMember(ctx, impl.getOrThrow(), proxy.getOrThrow())
    if (moved.isNone()) {
        return
    }
    if (let Some(fd) <- (moved.getOrThrow() as FuncDecl)) {
        RetargetCallee(call, fd)
        return
    }
    let field = WithinFile<RefExpr>(CreateRefExpr((moved.getOrThrow() as VarDecl).getOrThrow()), call.curFile)
    var access: Expr = field
    if ((proxy.getOrThrow() as FuncDecl).getOrThrow().isSetter) {
        CJC_ASSERT_WITH_MSG(!call.args.isEmpty(), "expected the value a property setter is called with")
        access = CreateAssignExpr(access, call.args[0].expr.getOrThrow(),
            Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
        access.curFile = call.curFile
    }
    access.sourceExpr = Some(call)
    call.desugarExpr = Some(access)
}

private func RewriteAsDirectFieldAccess(node: Node, userField: VarDecl, proxy: Decl): Bool {
    let isStatic = userField.TestAttr(Attribute.STATIC)
    let curFile = node.curFile
    let receiver: Expr = if (isStatic) {
        WithinFile<RefExpr>(CreateRefExpr(GetOwnerClass(userField).getOrThrow()), curFile)
    } else {
        WithinFile<RefExpr>(CreateRefExpr(GetObjCImplRegCompanionField(GetOwnerClass(proxy).getOrThrow()).getOrThrow()), curFile)
    }
    let fieldAccess = WithinFile<MemberAccess>(CreateMemberAccess(receiver, userField), curFile)
    if (let Some(ref) <- (node as RefExpr)) {
        fieldAccess.sourceExpr = Some(ref)
        ref.desugarExpr = Some(fieldAccess)
        return true
    }
    let ma = (node as MemberAccess).getOrThrow()
    let baseRef = ma.baseExpr.getOrThrow() as RefExpr
    if (isStatic || (baseRef.isSome() && baseRef.getOrThrow().isThis)) {
        fieldAccess.sourceExpr = Some(ma)
        ma.desugarExpr = Some(fieldAccess)
        return true
    }
    return false
}

// Upstream a51ced71, MoveImplMembersToRegCompanion.cpp:395-469.
private func RewriteObjCImplMembersAccess(ctx: InteropContext, proxied: ProxiedMembers): Unit {
    var region = Region.ELSEWHERE
    var hasPropsResolved = false
    let walker = Walker(ctx.pkg, visitPre: {node: Node =>
        if (!node.IsSamePackage(ctx.pkg)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(cd) <- (node as ClassDecl)) {
            region = RegionOf(cd)
        }
        if (let Some(call) <- (node as CallExpr)) {
            if (let Some(callee) <- call.resolvedFunction) {
                if (region == Region.REG_COMPANION) {
                    ResolveToImportedMovedMember(ctx, call)
                } else if (let Some(proxy) <- proxied.Find(callee)) {
                    call.resolvedFunction = proxy as FuncDecl
                }
            }
        }
        var target: Option<Decl> = None
        if (let Some(ref) <- (node as RefExpr)) {
            target = ref.ref.target
        } else if (let Some(ma) <- (node as MemberAccess)) {
            target = ma.target
        }
        if (target.isNone()) {
            return VisitAction.WALK_CHILDREN
        }
        let proxy = proxied.Find(target.getOrThrow())
        if (proxy.isNone()) {
            return VisitAction.WALK_CHILDREN
        }
        if (region == Region.REG_COMPANION && !IsNamedOnAnotherInstance(node)) {
            RequalifyToRegCompanion(ctx, node)
            return VisitAction.WALK_CHILDREN
        }
        if (region == Region.IMPL && target.getOrThrow() is VarDecl &&
            RewriteAsDirectFieldAccess(node, (target.getOrThrow() as VarDecl).getOrThrow(), proxy.getOrThrow())) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(ref) <- (node as RefExpr)) {
            ref.ref.target = proxy
        } else if (let Some(ma) <- (node as MemberAccess)) {
            ma.target = proxy
        }
        hasPropsResolved = hasPropsResolved || target.getOrThrow() is VarDecl
        return VisitAction.WALK_CHILDREN
    }, visitPost: {node: Node =>
        if (node is ClassDecl) {
            region = Region.ELSEWHERE
        }
        return VisitAction.KEEP_DECISION
    })
    let _ = walker.Walk()
    if (hasPropsResolved) {
        ctx.desugarPropRef(ctx.pkg)
    }
}

// Upstream a51ced71, MoveImplMembersToRegCompanion.cpp:473-521.
public class MoveImplMembersToRegCompanion <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        let proxied = ProxiedMembers()
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let regCompanion = ctx.implToRegCompanion.get(impl).getOrThrow()
            let field = GetObjCImplRegCompanionField(impl).getOrThrow()
            let target = MoveTarget(impl, regCompanion, field)
            let members = impl.GetMemberDecls()
            var i: Int64 = 0
            while (i < members.size) {
                let member = members[i]
                var shouldMove = false
                if (let Some(vd) <- (member as VarDecl)) {
                    shouldMove = RewireMovedField(vd, target, ctx, proxied)
                } else if (let Some(fd) <- (member as FuncDecl)) {
                    shouldMove = RewireMovedFunc(fd, target, ctx, proxied)
                }
                if (shouldMove) {
                    ctx.astInserter.InsertInto(regCompanion, member)
                    members.remove(at: i)
                } else {
                    i++
                }
            }
        }
        RewriteObjCImplMembersAccess(ctx, proxied)
        for (proxy in proxied.InDeclarationOrder()) {
            ctx.astInserter.InsertInto((proxy.outerDecl.getOrThrow() as ClassDecl).getOrThrow(), proxy)
        }
    }
}
