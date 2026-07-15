package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::modules.SemaImportManager
import cjcj::option.GetHardwareConcurrency
import cjcj::utils.ProfileRecorder

private let CORES_REQUIRED_WARMUP: UInt64 = 8u64

public enum SynPos {
    | NONE
    | EXPR_ARG
    | IMPLICIT_RETURN
    | LEFT_VALUE
    | UNUSED
}

public enum MatchResult {
    | NONE
    | UNIQUE
    | AMBIGUOUS
}

// C++ src/Sema/TypeCheckerImpl.h:102-104.
public enum LambdaSource {
    | USER
    | SPAWN
    | TRY_HANDLE
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
    public var importManager: Option<SemaImportManager> = None
    public let scopeManager: ScopeManager = ScopeManager()

    public init(typeManager!: TypeManager = TypeManager(), diag!: Option<BasicDiagnosticEngine> = None,
        importManager!: Option<SemaImportManager> = None) {
        this.typeManager = typeManager
        this.diag = diag
        this.importManager = importManager
    }

    public func PickConstaintFromTys(tv: GenericsTy, tys: TySet, isUB: Bool): MatchResult {
        var result = MatchResult.NONE
        try (cs = typeManager.constraints.CommitScope()) {
            var cnt: Int64 = 0
            var target: Option<Ty> = None
            for (ty in tys.values) {
                if (if (isUB) { typeManager.IsSubtype(tv, ty) } else { typeManager.IsSubtype(ty, tv) }) {
                    cnt++
                    target = Some(ty)
                }
                typeManager.constraints.Reset()
            }
            if (cnt > 1) {
                result = MatchResult.AMBIGUOUS
            } else if (cnt == 1) {
                if (let Some(targetTy) <- target) {
                    let _ = if (isUB) {
                        typeManager.IsSubtype(tv, targetTy)
                    } else {
                        typeManager.IsSubtype(targetTy, tv)
                    }
                }
                result = MatchResult.UNIQUE
            } else {
                result = MatchResult.NONE
            }
        }
        return result
    }

    public func PickConstaintFromTys(tv1: Ty, tv2: Ty, tys: ArrayList<(Ty, Ty)>, isUB: Bool): MatchResult {
        var result = MatchResult.NONE
        try (cs = typeManager.constraints.CommitScope()) {
            var cnt: Int64 = 0
            var target1: Option<Ty> = None
            var target2: Option<Ty> = None
            for (tysEntry in tys) {
                let ty1 = tysEntry[0]
                let ty2 = tysEntry[1]
                if (if (isUB) {
                    typeManager.IsSubtype(tv1, ty1) && typeManager.IsSubtype(tv2, ty2)
                } else {
                    typeManager.IsSubtype(ty1, tv1) && typeManager.IsSubtype(ty2, tv2)
                }) {
                    cnt++
                    target1 = Some(ty1)
                    target2 = Some(ty2)
                }
                typeManager.constraints.Reset()
            }
            if (cnt > 1) {
                result = MatchResult.AMBIGUOUS
            } else if (cnt == 1) {
                if ((let Some(targetTy1) <- target1) && (let Some(targetTy2) <- target2)) {
                    let _ = if (isUB) {
                        typeManager.IsSubtype(tv1, targetTy1) && typeManager.IsSubtype(tv2, targetTy2)
                    } else {
                        typeManager.IsSubtype(targetTy1, tv1) && typeManager.IsSubtype(targetTy2, tv2)
                    }
                }
                result = MatchResult.UNIQUE
            } else {
                result = MatchResult.NONE
            }
        }
        return result
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

    // C++ src/Sema/PreCheck.cpp:1323-1330 TypeCheckerImpl::CheckDupInterfaceInStructDecl.
    public func CheckDupInterfaceInStructDecl(decl: InheritableDecl): Unit {
        if (!Ty.IsTyCorrect(decl.GetTy())) {
            return
        }
        CheckInstDupSuperInterfaces(decl, decl, TypeSubst(), checkExtend: false)
    }

    public func GetDupInterfaceRecursively(triggerNode: Node, interfaceTy: Ty, instantiateMap: TypeSubst,
        res: ArrayList<InterfaceTy>, passedClassLikeDecls: ArrayList<ClassLikeDecl>): Option<Decl> {
        let insTy = typeManager.GetInstantiatedTy(interfaceTy, instantiateMap)
        if (!Ty.IsTyCorrect(insTy) || !insTy.IsInterface()) {
            return None
        }
        let ity = (insTy as InterfaceTy).getOrThrow()
        for (value in res) {
            if (refEq(value, ity)) {
                if (let Some(interfaceDecl) <- ity.declPtr) {
                    return Some(interfaceDecl)
                }
                return None
            }
        }
        res.add(ity)
        let interfaceDecl = ity.declPtr.getOrThrow()
        let superInstantiateMap = GenerateTypeMapping(interfaceDecl, ity.typeArgs)
        if (superInstantiateMap.IsEmpty()) {
            return None
        }
        return GetDupSuperInterface(triggerNode, interfaceDecl, superInstantiateMap, passedClassLikeDecls)
    }

    public func GetExtendDupSuperInterface(triggerNode: Node, decl: InheritableDecl, instantiateMap: TypeSubst,
        res: ArrayList<InterfaceTy>, passedClassLikeDecls: ArrayList<ClassLikeDecl>): Option<Decl> {
        if (!decl.TestAttr(Attribute.GENERIC) || !Ty.IsTyCorrect(decl.GetTy())) {
            return None
        }
        let extends = typeManager.GetDeclExtends(decl)
        for (extendDecl in extends) {
            let extendInstMap = GenerateTypeMapping(extendDecl, decl.GetTy().getOrThrow().typeArgs)
            if (extendInstMap.entries.size != instantiateMap.entries.size) {
                continue
            }
            for ((tyVar, ty) in instantiateMap.entries) {
                if (!extendInstMap.Contains(tyVar.value)) {
                    extendInstMap.Put(tyVar.value, ty)
                }
            }
            for (interfaceType in extendDecl.inheritedTypes) {
                if (!Ty.IsTyCorrect(interfaceType.GetTy())) {
                    continue
                }
                let ret = GetDupInterfaceRecursively(triggerNode, interfaceType.GetTy().getOrThrow(), extendInstMap,
                    res, passedClassLikeDecls)
                if (let Some(value) <- ret) {
                    return Some(value)
                }
            }
        }
        return None
    }

    public func GetDupSuperInterface(triggerNode: Node, decl: InheritableDecl, instantiateMap: TypeSubst,
        passedClassLikeDecls: ArrayList<ClassLikeDecl>, checkExtend!: Bool = true): Option<Decl> {
        if (decl.IsClassLikeDecl()) {
            let classLikeDecl = (decl as ClassLikeDecl).getOrThrow()
            for (passedDecl in passedClassLikeDecls) {
                if (refEq(passedDecl, classLikeDecl)) {
                    return None
                }
            }
            passedClassLikeDecls.add(classLikeDecl)
        }
        let instInterfaceTys = ArrayList<InterfaceTy>()
        for (interfaceType in decl.inheritedTypes) {
            if (!Ty.IsTyCorrect(interfaceType.GetTy())) {
                continue
            }
            let ret = GetDupInterfaceRecursively(triggerNode, interfaceType.GetTy().getOrThrow(), instantiateMap,
                instInterfaceTys, passedClassLikeDecls)
            if (let Some(value) <- ret) {
                return Some(value)
            }
        }
        if (checkExtend) {
            return GetExtendDupSuperInterface(triggerNode, decl, instantiateMap, instInterfaceTys,
                passedClassLikeDecls)
        }
        return None
    }

    // C++ src/Sema/TypeChecker.cpp:2639-2651 TypeCheckerImpl::CheckInstDupSuperInterfaces.
    public func CheckInstDupSuperInterfaces(triggerNode: Node, decl: InheritableDecl, instantiateMap: TypeSubst,
        checkExtend!: Bool = true): Unit {
        let passedClassLikeDecls = ArrayList<ClassLikeDecl>()
        let interfaceDecl = GetDupSuperInterface(triggerNode, decl, instantiateMap, passedClassLikeDecls,
            checkExtend: checkExtend)
        let baseDecl = Ty.GetDeclPtrOfTy(decl.GetTy())
        let name = if (let Some(value) <- baseDecl) { value.identifier.Val() } else { Ty.ToString(decl.GetTy()) }
        if (let Some(value) <- interfaceDecl) {
            Diagnose(diag.getOrThrow(), triggerNode, BasicDiagKind.sema_inherit_duplicate_interface,
                args: [BasicDiagArgument(DeclKindToString(decl)), BasicDiagArgument(name),
                    BasicDiagArgument(value.identifier.Val())]).Emit()
        }
    }

    // C++ src/Sema/TypeChecker.cpp:2653-2670 TypeCheckerImpl::CheckInstDupSuperInterfaces(Type).
    public func CheckInstDupSuperInterfaces(typeNode: Type): VisitAction {
        if (!Ty.IsTyCorrect(typeNode.GetTy())) {
            return VisitAction.SKIP_CHILDREN
        }
        let typeTarget = GetRealTarget(typeNode.GetTarget())
        if ((let None <- typeTarget) || !typeTarget.getOrThrow().IsNominalDecl()) {
            return VisitAction.WALK_CHILDREN
        }
        let target = typeTarget.getOrThrow()
        let typeMapping = GenerateTypeMapping(target, typeNode.GetTy().getOrThrow().typeArgs)
        if (typeMapping.IsEmpty()) {
            return VisitAction.SKIP_CHILDREN
        }
        CheckInstDupSuperInterfaces(typeNode, (target as InheritableDecl).getOrThrow(), typeMapping,
            checkExtend: false)
        return VisitAction.WALK_CHILDREN
    }

    // C++ src/Sema/TypeChecker.cpp:2672-2692 TypeCheckerImpl::CheckInstDupSuperInterfaces(Expr).
    public func CheckInstDupSuperInterfaces(expr: Expr): VisitAction {
        if (!Ty.IsTyCorrect(expr.GetTy())) {
            return VisitAction.WALK_CHILDREN
        }
        var target = GetRealTarget(expr.GetTarget())
        let instTys = GetInstanationTys(expr)
        if ((let None <- target) || instTys.isEmpty()) {
            return VisitAction.WALK_CHILDREN
        }
        if (IsClassOrEnumConstructor(target.getOrThrow())) {
            target = target.getOrThrow().outerDecl
        }
        if ((let None <- target) || !target.getOrThrow().IsNominalDecl()) {
            return VisitAction.WALK_CHILDREN
        }
        let nominalTarget = target.getOrThrow()
        let instantiateMap = GenerateTypeMapping(nominalTarget, instTys)
        if (instantiateMap.IsEmpty()) {
            return VisitAction.SKIP_CHILDREN
        }
        CheckInstDupSuperInterfaces(expr, (nominalTarget as InheritableDecl).getOrThrow(), instantiateMap)
        return VisitAction.WALK_CHILDREN
    }

    // C++ src/Sema/TypeChecker.cpp:2694-2722 TypeCheckerImpl::CheckInstDupSuperInterfacesEntry.
    public func CheckInstDupSuperInterfacesEntry(node: Node): Unit {
        try (recorder = ProfileRecorder("Post TypeCheck", "CheckInstDupSuperInterfacesEntry")) {
            let visitor = Box<(Node) -> VisitAction>({ _: Node => VisitAction.WALK_CHILDREN })
            visitor.value = { current: Node =>
                if (let Some(pkg) <- (current as Package)) {
                    for (file in pkg.files) {
                        let _ = Walker(file, visitPre: visitor.value).Walk()
                    }
                    return VisitAction.STOP_NOW
                }
                if (current.astKind == ASTKind.REF_TYPE || current.astKind == ASTKind.QUALIFIED_TYPE) {
                    return CheckInstDupSuperInterfaces((current as Type).getOrThrow())
                }
                if (current.astKind == ASTKind.REF_EXPR || current.astKind == ASTKind.MEMBER_ACCESS) {
                    return CheckInstDupSuperInterfaces((current as Expr).getOrThrow())
                }
                return VisitAction.WALK_CHILDREN
            }
            let _ = Walker(node, visitPre: visitor.value).Walk()
        }
    }

    public func GetSymsByASTKind(ctx: ASTContext, astKind: ASTKind,
        order!: SearchOrder = SearchOrder.POS_DESC): ArrayList<Symbol> {
        return ctx.searcher.Search(ctx, ASTKindQuery(astKind), order: order)
    }

    public func Lookup(ctx: ASTContext, name: String, scopeName: String, node: Node,
        isSetter!: Bool = false): ArrayList<Decl> {
        return Lookup(typeManager, ctx, name, scopeName, node, isSetter: isSetter, importManager: importManager)
    }

    public func LookupTopLevel(ctx: ASTContext, name: String, scopeName: String, node: Node,
        isSetter!: Bool = false): ArrayList<Decl> {
        return LookupTopLevel(typeManager, ctx, name, scopeName, node, isSetter: isSetter, importManager: importManager)
    }

    public func FieldLookup(ctx: ASTContext, decl: Option<Decl>, fieldName: String,
        info!: LookupInfo = LookupInfo()): ArrayList<Decl> {
        let _ = ctx
        return FieldLookup(typeManager, decl, fieldName, info: info, importManager: importManager)
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
        return GetTyFromASTNode(typeManager, ctx, node, importManager: importManager, diag: diag)
    }

    public func GetTyFromASTType(ctx: ASTContext, node: Node): Ty {
        return GetTyFromASTNode(typeManager, ctx, node, importManager: importManager, diag: diag)
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
        ResolveOneDecl(typeManager, ctx, decl, importManager: importManager, diag: diag)
    }

    public func ResolveDecls(ctx: ASTContext): Unit {
        ResolveDecls(typeManager, ctx, importManager: importManager, diag: diag)
    }

    public func ResolveTypeAlias(ctx: ASTContext): Unit {
        ResolveTypeAlias(typeManager, ctx, importManager: importManager, diag: diag)
    }

    public func SetTypeTy(ctx: ASTContext, typeNode: Type): Unit {
        SetTypeTy(typeManager, ctx, typeNode, importManager: importManager, diag: diag)
    }

    public func SubstituteTypeAliasForAlias(tad: TypeAliasDecl): Unit {
        SubstituteTypeAliasForAlias(typeManager, tad)
    }

    public func ResolveNames(ctx: ASTContext): Unit {
        ResolveNames(typeManager, ctx, importManager: importManager, diag: diag)
    }

    public func PreSetDeclType(ctx: ASTContext): Unit {
        PreSetDeclType(typeManager, ctx, importManager: importManager, diag: diag)
    }
}
