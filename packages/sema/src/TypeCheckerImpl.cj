package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::option.GetHardwareConcurrency
import cangjie_compiler::utils.ProfileRecorder

private let CORES_REQUIRED_WARMUP: UInt64 = 8u64

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
        try (recorder = ProfileRecorder("PrepareTypeCheck", "WarmupCache")) {
            let numProcessors = GetHardwareConcurrency()
            if (numProcessors < CORES_REQUIRED_WARMUP) {
                return
            }
            let scopeNames = ctx.searcher.GetScopeNamesByPrefix(ctx, TOPLEVEL_SCOPE_NAME)
            let numScopeNames = UInt64(scopeNames.size)
            if (numProcessors < numScopeNames) {
                return
            }
            let cache = HashMap<String, ArrayList<Symbol>>()
            let threads = ArrayList<Option<Future<Unit>>>()
            let searchers = ArrayList<Searcher>()
            for (_ in 0..scopeNames.size) {
                threads.add(None)
                searchers.add(Searcher())
            }
            var idx: Int64 = 0
            while (idx < scopeNames.size) {
                let scopeName = scopeNames[idx]
                let searcher = searchers[idx]
                threads[idx] = spawn {
                    let query = CompoundQuery(QueryKind.NOT)
                    let scopeAndDecl = CompoundQuery(QueryKind.AND)
                    scopeAndDecl.children.add(ScopeQuery(scopeName))
                    let declOrFuncParam = CompoundQuery(QueryKind.OR)
                    declOrFuncParam.children.add(ASTKindQuery("decl", matchKind: MatchKind.SUFFIX))
                    declOrFuncParam.children.add(ASTKindQuery("func_param"))
                    scopeAndDecl.children.add(declOrFuncParam)
                    query.children.add(scopeAndDecl)
                    query.children.add(ASTKindQuery("extend_decl"))
                    let _ = searcher.Search(ctx, query)
                }
                idx++
            }
            for (thread in threads) {
                if (let Some(value) <- thread) {
                    value.get()
                }
            }
            for (searcher in searchers) {
                for ((key, value) in searcher.GetCache()) {
                    cache[key] = value
                }
            }
            ctx.searcher.SetCache(cache)
        }
    }

    public func GetToplevelDecls(ctx: ASTContext): ArrayList<Symbol> {
        let query = CompoundQuery(QueryKind.AND)
        query.children.add(ScopeLevelQuery(0u32))
        query.children.add(ASTKindQuery("decl", matchKind: MatchKind.SUFFIX))
        return ctx.searcher.Search(ctx, query, order: SearchOrder.POS_ASC)
    }

    public func GetAllDecls(ctx: ASTContext): ArrayList<Symbol> {
        return ctx.searcher.Search(ctx, ASTKindQuery("decl", matchKind: MatchKind.SUFFIX),
            order: SearchOrder.POS_ASC)
    }

    public func GetGenericCandidates(ctx: ASTContext): ArrayList<Symbol> {
        return ctx.searcher.Search(ctx,
            "ast_kind : class_decl || ast_kind : interface_decl || ast_kind : struct_decl || ast_kind : enum_decl || " +
            "ast_kind : func_decl || ast_kind : extend_decl || ast_kind : builtin_decl", order: SearchOrder.POS_ASC)
    }

    public func GetAllStructDecls(ctx: ASTContext): ArrayList<Symbol> {
        return ctx.searcher.Search(ctx,
            "ast_kind : class_decl || ast_kind : interface_decl || ast_kind : struct_decl || ast_kind : enum_decl || " +
            "ast_kind : extend_decl", order: SearchOrder.POS_ASC)
    }

    public func GetSymsByASTKind(ctx: ASTContext, astKind: ASTKind,
        order!: SearchOrder = SearchOrder.POS_DESC): ArrayList<Symbol> {
        return ctx.searcher.Search(ctx, ASTKindQuery(astKind), order: order)
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
        TypeCheckReferenceRemoveTargetNotMeetExtendConstraint(typeManager, baseTy, targets)
    }

    public func RemoveTargetNotMeetExtendConstraint(baseTy: Ty, targets: ArrayList<Decl>): Unit {
        TypeCheckReferenceRemoveTargetNotMeetExtendConstraint(typeManager, Some(baseTy), targets)
    }

    public func GetTyFromASTType(ctx: ASTContext, node: Option<Node>): Ty {
        return GetTyFromASTNode(typeManager, ctx, node)
    }

    public func GetTyFromASTType(ctx: ASTContext, node: Node): Ty {
        return GetTyFromASTNode(typeManager, ctx, node)
    }

    public func GetTyFromASTDecl(decl: Decl, typeArgs: ArrayList<Ty>): Ty {
        return GetTyFromASTDecl(typeManager, decl, typeArgs)
    }

    public func SetDeclTy(decl: Decl): Unit {
        SetDeclTy(typeManager, decl)
    }

    public func SetTypeAliasDeclTy(ctx: ASTContext, tad: TypeAliasDecl): Unit {
        SetTypeAliasDeclTy(typeManager, ctx, tad)
    }

    public func ResolveOneDecl(ctx: ASTContext, decl: Decl): Unit {
        ResolveOneDecl(typeManager, ctx, decl)
    }

    public func ResolveDecls(ctx: ASTContext): Unit {
        ResolveDecls(typeManager, ctx)
    }

    public func ResolveTypeAlias(ctx: ASTContext): Unit {
        ResolveTypeAlias(typeManager, ctx)
    }

    public func SetTypeTy(ctx: ASTContext, typeNode: Type): Unit {
        SetTypeTy(typeManager, ctx, typeNode)
    }

    public func SubstituteTypeAliasForAlias(tad: TypeAliasDecl): Unit {
        SubstituteTypeAliasForAlias(typeManager, tad)
    }

    public func ResolveNames(ctx: ASTContext): Unit {
        ResolveNames(typeManager, ctx)
    }

    public func PreSetDeclType(ctx: ASTContext): Unit {
        PreSetDeclType(typeManager, ctx)
    }
}
