package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine

public enum SynPos {
    | NONE
    | EXPR_ARG
    | IMPLICIT_RETURN
    | LEFT_VALUE
    | UNUSED
}

private func SynPosIndex(value: SynPos): Int64 {
    return match (value) {
        case SynPos.NONE => 0
        case SynPos.EXPR_ARG => 1
        case SynPos.IMPLICIT_RETURN => 2
        case SynPos.LEFT_VALUE => 3
        case SynPos.UNUSED => 4
    }
}

extend SynPos <: Equatable<SynPos> {
    public operator func ==(right: SynPos): Bool {
        return SynPosIndex(this) == SynPosIndex(right)
    }

    public operator func !=(right: SynPos): Bool {
        return !(this == right)
    }
}

public class CheckerContext {
    private var astContext: ASTContext
    private var synthesizePos: SynPos

    public init(ctx: ASTContext, synthesizePos: SynPos) {
        astContext = ctx
        this.synthesizePos = synthesizePos
    }

    public func Ctx(): ASTContext {
        return astContext
    }

    public func SynthPos(): SynPos {
        return synthesizePos
    }

    public func With(newPos: SynPos): CheckerContext {
        return CheckerContext(astContext, newPos)
    }
}

public class CollectDeclsInfo {
    public let funcDecls: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let initFuncDecls: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let nonFuncDecls: ArrayList<Decl> = ArrayList<Decl>()
    public let staticFuncDecls: ArrayList<Decl> = ArrayList<Decl>()
    public let annotations: ArrayList<ArrayLit> = ArrayList<ArrayLit>()

    public init() {}
}

public class TypeCheckerImpl {
    public var typeManager: TypeManager
    public var diag: Option<BasicDiagnosticEngine> = None

    public init(typeManager!: TypeManager = TypeManager(), diag!: Option<BasicDiagnosticEngine> = None) {
        this.typeManager = typeManager
        this.diag = diag
    }

    public func WarmupCache(ctx: ASTContext): Unit {
        let _ = ctx.searcher.GetScopeNamesByPrefix(ctx, TOPLEVEL_SCOPE_NAME)
    }

    public func GetToplevelDecls(ctx: ASTContext): ArrayList<Symbol> {
        return GetToplevelDeclSymbols(ctx)
    }

    public func GetAllDecls(ctx: ASTContext): ArrayList<Symbol> {
        return GetAllDeclSymbols(ctx)
    }

    public func GetGenericCandidates(ctx: ASTContext): ArrayList<Symbol> {
        return GetGenericCandidateSymbols(ctx)
    }

    public func GetAllStructDecls(ctx: ASTContext): ArrayList<Symbol> {
        return GetAllStructDeclSymbols(ctx)
    }

    public func GetSymsByASTKind(ctx: ASTContext, astKind: ASTKind,
        order!: SearchOrder = SearchOrder.POS_ASC): ArrayList<Symbol> {
        return GetSymbolsByASTKind(ctx, astKind, order: order)
    }

    public func Lookup(ctx: ASTContext, name: String, scopeName: String, node: Node,
        isSetter!: Bool = false): ArrayList<Decl> {
        return Lookup(typeManager, ctx, name, scopeName, node, isSetter: isSetter)
    }

    public func LookupTopLevel(ctx: ASTContext, name: String, scopeName: String, node: Node,
        isSetter!: Bool = false): ArrayList<Decl> {
        return LookupTopLevel(typeManager, ctx, name, scopeName, node, isSetter: isSetter)
    }

    public func FieldLookup(ctx: ASTContext, decl: Option<Decl>, fieldName: String,
        info!: LookupInfo = LookupInfo()): ArrayList<Decl> {
        let _ = ctx
        return FieldLookup(typeManager, decl, fieldName, info: info)
    }

    public func ExtendFieldLookup(ctx: ASTContext, file: File, ty: Option<Ty>, fieldName: String): ArrayList<Decl> {
        let _ = ctx
        return ExtendFieldLookup(typeManager, file, ty, fieldName)
    }

    public func SynReferenceSeparately(ctx: ASTContext, scopeName: String, expr: Expr,
        hasLocalDecl: Bool): Candidate {
        let candidate = Candidate()
        if (let Some(ty) <- expr.GetTy()) {
            if (Ty.IsTyCorrect(ty)) {
                candidate.tys.add(ty)
                candidate.hasDecl = false
                return candidate
            }
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            let lookupScope = if (hasLocalDecl) { scopeName } else { GetParentScopeName(scopeName) }
            let decls = Lookup(ctx, refExpr.ref.identifier.Val(), lookupScope, refExpr)
            for (decl in decls) {
                candidate.decls.add(decl)
            }
            candidate.hasDecl = !candidate.decls.isEmpty()
        } else if (let Some(memberAccess) <- (expr as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                if (let Some(baseTy) <- baseExpr.GetTy()) {
                    let decls = FieldLookup(ctx, Ty.GetDeclPtrOfTy(baseTy), memberAccess.field.Val(),
                        info: LookupInfo(baseTy: baseTy, file: memberAccess.curFile))
                    for (decl in decls) {
                        candidate.decls.add(decl)
                    }
                    candidate.hasDecl = !candidate.decls.isEmpty()
                }
            }
        }
        return candidate
    }

    public func RemoveTargetNotMeetExtendConstraint(baseTy: Option<Ty>, targets: ArrayList<Decl>): Unit {
        if (let Some(value) <- baseTy) {
            RemoveTargetNotMeetExtendConstraint(value, targets)
        }
    }

    public func RemoveTargetNotMeetExtendConstraint(baseTy: Ty, targets: ArrayList<Decl>): Unit {
        var idx: Int64 = 0
        while (idx < targets.size) {
            if (let Some(parentDecl) <- targets[idx].outerDecl) {
                if (let Some(extendDecl) <- (parentDecl as ExtendDecl)) {
                    if (!typeManager.CheckExtendWithConstraint(baseTy, extendDecl)) {
                        targets.remove(at: idx)
                        continue
                    }
                }
            }
            idx++
        }
    }
}

public func SelfhostPortStatus_TypeCheckerImpl(): Bool {
    return true
}
