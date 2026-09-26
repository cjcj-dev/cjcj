package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{DiagKindRefactor, DiagnosticEngine}
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateBoolMatch, CreateCall, CreateJavaRefCall, CreateType, GetJavaJniClassName,
    InteropLibBridge, Utils, WithinFile}
import cjcj::utils.V_COMPILER

private class PatternVar {
    public let decl: VarDecl
    public let ty: Ty

    public init(decl: VarDecl, ty: Ty) {
        this.decl = decl
        this.ty = ty
    }
}

private class DeclPair {
    public let from: Decl
    public let to: Decl

    public init(from: Decl, to: Decl) {
        this.from = from
        this.to = to
    }
}

public class DesugarTypeCheckingAndCasting {
    private let ilib: InteropLibBridge
    private let diag: DiagnosticEngine
    private let utils: Utils

    public init(ilib: InteropLibBridge, diag: DiagnosticEngine, utils: Utils) {
        this.ilib = ilib
        this.diag = diag
        this.utils = utils
    }

    private func ShouldDesugarTypecheck(typeNode: Option<Type>, expr: Option<Expr>): Bool {
        if (let None <- typeNode) {
            return false
        }
        if (let None <- expr) {
            return false
        }
        let castDecl = Ty.GetDeclOfTy(typeNode.getOrThrow().GetTy())
        let objDecl = Ty.GetDeclOfTy(expr.getOrThrow().GetTy())
        if (let None <- castDecl) {
            return false
        }
        if (let None <- objDecl) {
            return false
        }
        if ((castDecl.getOrThrow() as ClassLikeDecl).isNone() || (objDecl.getOrThrow() as ClassLikeDecl).isNone()) {
            return false
        }
        let castClass = castDecl.getOrThrow()
        return IsMirror(castClass) || IsImpl(castClass)
    }

    private func CollectTypePatterns(pat: Pattern, out: ArrayList<TypePattern>): Unit {
        Walker(pat, visitPre: { node: Node =>
            if (let Some(typePat) <- (node as TypePattern)) {
                if (let Some(typeNode) <- typePat.typeNode) {
                    if (let Some(decl) <- Ty.GetDeclOfTy(typeNode.GetTy())) {
                        if ((IsMirror(decl) || IsImpl(decl)) && !IsJObject(decl)) {
                            out.add(typePat)
                        }
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
    }

    private func CreateIsInstanceCall(jObjectVar: VarDecl, classTy: Ty, curFile: Option<File>): Option<Expr> {
        let isInstanceOfDecl = ilib.GetIsInstanceOf()
        if (let None <- isInstanceOfDecl) {
            return None
        }
        let fd = isInstanceOfDecl.getOrThrow()
        let envCall = ilib.CreateGetJniEnvCall(curFile)
        if (let None <- envCall) {
            return None
        }
        let javaRefExpr = CreateJavaRefCall(WithinFile<RefExpr>(CreateRefExpr(jObjectVar), curFile))
        let nameTy = fd.funcBody.getOrThrow().paramLists[0].params[2].GetTy().getOrThrow()
        let nameLit = CreateLitConstExpr(LitConstKind.STRING, GetJavaJniClassName(utils, classTy), nameTy)
        nameLit.curFile = curFile
        let args = ArrayList<FuncArg>()
        args.add(CreateFuncArg(envCall.getOrThrow()))
        args.add(CreateFuncArg(javaRefExpr))
        args.add(CreateFuncArg(nameLit))
        if (let Some(call) <- CreateCall(isInstanceOfDecl, curFile, args: args)) {
            return Some(call)
        }
        return None
    }

    private func CreateJObjectCast(jObjectVar: VarDecl, castDecl: ClassLikeDecl, castTy: Ty,
        curFile: Option<File>): Option<Expr> {
        let isInstanceCall = CreateIsInstanceCall(jObjectVar, castTy, curFile)
        if (let None <- isInstanceCall) {
            return None
        }
        let javarefExpr = CreateJavaRefCall(WithinFile<RefExpr>(CreateRefExpr(jObjectVar), curFile))
        let unwrapped = ilib.UnwrapJavaEntity(javarefExpr, castTy, castDecl)
        if (let None <- unwrapped) {
            return None
        }
        let trueBranch = utils.CreateOptionSomeCall(unwrapped.getOrThrow(), castTy)
        let falseBranch = utils.CreateOptionNoneRef(castTy)
        return Some(CreateBoolMatch(isInstanceCall.getOrThrow(), trueBranch, falseBranch, utils.GetOptionTy(castTy)))
    }

    private func DesugarIsExpression(ie: IsExpr): Unit {
        if (ie.desugarExpr.isSome()) {
            return
        }
        let curFile = ie.curFile
        let castTy = ie.isType.getOrThrow().GetTy().getOrThrow()
        let jObjectDecl = utils.GetJObjectDecl()
        if (let None <- jObjectDecl) {
            return
        }
        let jObject = jObjectDecl.getOrThrow()
        let jObjVarPattern = WithinFile<VarPattern>(CreateVarPattern(V_COMPILER, jObject.GetTy()), curFile)
        jObjVarPattern.varDecl.getOrThrow().curFile = curFile
        let isInstanceCall = CreateIsInstanceCall(jObjVarPattern.varDecl.getOrThrow(), castTy, curFile)
        if (let None <- isInstanceCall) {
            return
        }
        let left = ie.leftExpr.getOrThrow()
        let ctxExpr = (ASTCloner.Clone(left) as Expr).getOrThrow()
        let typePattern = CreateTypePattern(jObjVarPattern, CreateType(jObject.GetTy().getOrThrow()), ctxExpr)
        typePattern.needRuntimeTypeCheck = true
        typePattern.matchBeforeRuntime = false
        let cases = ArrayList<MatchCase>()
        cases.add(CreateMatchCase(typePattern, isInstanceCall.getOrThrow()))
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let falseLit = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy)
        falseLit.curFile = curFile
        cases.add(CreateMatchCase(WildcardPattern(), falseLit))
        ie.desugarExpr = Some(WithinFile<MatchExpr>(CreateMatchExpr(left, cases, boolTy), curFile))
    }

    private func DesugarAsExpression(ae: AsExpr): Unit {
        if (ae.desugarExpr.isSome()) {
            return
        }
        let curFile = ae.curFile
        let castTy = ae.asType.getOrThrow().GetTy().getOrThrow()
        let castDeclNode = Ty.GetDeclOfTy(Some(castTy))
        if (let None <- castDeclNode) {
            return
        }
        if (let None <- (castDeclNode.getOrThrow() as ClassLikeDecl)) {
            return
        }
        let castDecl = (castDeclNode.getOrThrow() as ClassLikeDecl).getOrThrow()
        let jObjectDecl = utils.GetJObjectDecl()
        if (let None <- jObjectDecl) {
            return
        }
        let jObject = jObjectDecl.getOrThrow()
        let jObjVarPattern = WithinFile<VarPattern>(CreateVarPattern(V_COMPILER, jObject.GetTy()), curFile)
        jObjVarPattern.varDecl.getOrThrow().curFile = curFile
        let isInstanceMatch = CreateJObjectCast(jObjVarPattern.varDecl.getOrThrow(), castDecl, castTy, curFile)
        if (let None <- isInstanceMatch) {
            return
        }
        let left = ae.leftExpr.getOrThrow()
        let ctxExpr = (ASTCloner.Clone(left) as Expr).getOrThrow()
        let typePattern = CreateTypePattern(jObjVarPattern, CreateType(jObject.GetTy().getOrThrow()), ctxExpr)
        typePattern.needRuntimeTypeCheck = true
        typePattern.matchBeforeRuntime = false
        let cases = ArrayList<MatchCase>()
        cases.add(CreateMatchCase(typePattern, isInstanceMatch.getOrThrow()))
        let noneRef = utils.CreateOptionNoneRef(castTy)
        noneRef.curFile = curFile
        cases.add(CreateMatchCase(WildcardPattern(), noneRef))
        ae.desugarExpr = Some(WithinFile<MatchExpr>(
            CreateMatchExpr(left, cases, utils.GetOptionTy(castTy)), curFile))
    }

    private func MappedDecl(mapping: ArrayList<DeclPair>, target: Decl): Option<Decl> {
        for (pair in mapping) {
            if (pair.from == target) {
                return Some(pair.to)
            }
        }
        return None
    }

    private func CastAndSubstituteVars(expr: Expr, patternVars: ArrayList<PatternVar>): Block {
        let curFile = expr.curFile
        let mapping = ArrayList<DeclPair>()
        let block = Block()
        block.curFile = curFile
        for (patternVar in patternVars) {
            let castDecl = Ty.GetDeclOfTy(Some(patternVar.ty))
            if (let Some(decl) <- castDecl) {
                if (let Some(classLike) <- (decl as ClassLikeDecl)) {
                    let javarefExpr = CreateJavaRefCall(WithinFile<RefExpr>(CreateRefExpr(patternVar.decl), curFile))
                    if (let Some(initializer) <- ilib.UnwrapJavaEntity(javarefExpr, patternVar.ty, classLike)) {
                        let castedVar = WithinFile<VarDecl>(
                            CreateTmpVarDecl(Some(CreateType(classLike.GetTy().getOrThrow())), Some(initializer)), curFile)
                        castedVar.SetTy(patternVar.ty)
                        mapping.add(DeclPair(patternVar.decl, castedVar))
                        block.body.add(castedVar)
                    }
                }
            }
        }
        Walker(expr, visitPre: { node: Node =>
            if (let Some(refExpr) <- (node as RefExpr)) {
                if (let Some(target) <- refExpr.ref.target) {
                    if (let Some(mapped) <- MappedDecl(mapping, target)) {
                        refExpr.ref.identifier = mapped.identifier
                        refExpr.ref.target = Some(mapped)
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
        return block
    }

    private func DesugarMatchCase(matchCase: MatchCase): Unit {
        let typePatterns = ArrayList<TypePattern>()
        for (pat in matchCase.patterns) {
            CollectTypePatterns(pat, typePatterns)
        }
        if (typePatterns.isEmpty()) {
            return
        }
        let jObjectDecl = utils.GetJObjectDecl()
        if (let None <- jObjectDecl) {
            return
        }
        let jObject = jObjectDecl.getOrThrow()
        let patternVars = ArrayList<PatternVar>()
        let guards = ArrayList<Expr>()
        for (pat in typePatterns) {
            if (let Some(inner) <- pat.pattern) {
                if ((inner as WildcardPattern).isSome()) {
                    if (let Some(typeNode) <- pat.typeNode) {
                        if (let Some(ty) <- typeNode.GetTy()) {
                            let varPat = CreateVarPattern(V_COMPILER, Some(ty))
                            varPat.curFile = matchCase.curFile
                            pat.pattern = Some(varPat)
                        }
                    }
                }
            }
            if (let Some(innerPat) <- pat.pattern) {
            if (let Some(varPat) <- (innerPat as VarPattern)) {
                if (let Some(originalTy) <- varPat.GetTy()) {
                    if (let Some(varDecl) <- varPat.varDecl) {
                        pat.typeNode = Some(CreateType(jObject.GetTy().getOrThrow()))
                        varPat.SetTy(jObject.GetTy().getOrThrow())
                        varDecl.SetTy(jObject.GetTy().getOrThrow())
                        patternVars.add(PatternVar(varDecl, originalTy))
                        if (let Some(check) <- CreateIsInstanceCall(varDecl, originalTy, matchCase.curFile)) {
                            guards.add(check)
                        }
                    }
                }
            }
            }
        }
        if (guards.isEmpty()) {
            return
        }
        var guard = guards[guards.size - 1]
        var idx = guards.size - 2
        while (idx >= 0) {
            guard = CreateBinaryExpr(guards[idx], guard, TokenKind.AND)
            idx = idx - 1
        }
        if (let Some(oldGuard) <- matchCase.patternGuard) {
            let intro = CastAndSubstituteVars(oldGuard, patternVars)
            intro.body.add(oldGuard)
            if (let Some(guardTy) <- oldGuard.GetTy()) {
                intro.SetTy(guardTy)
            }
            oldGuard.desugarExpr = Some(intro)
            guard = CreateBinaryExpr(guard, oldGuard, TokenKind.AND)
        }
        matchCase.patternGuard = Some(guard)
        if (let Some(body) <- matchCase.exprOrDecls) {
            let intro = CastAndSubstituteVars(body, patternVars)
            let merged = ArrayList<Node>()
            for (node in intro.body) {
                merged.add(node)
            }
            for (node in body.body) {
                merged.add(node)
            }
            body.body.clear()
            for (node in merged) {
                body.body.add(node)
            }
        }
    }

    private func DesugarLetPattern(letPat: LetPatternDestructor): Unit {
        let typePatterns = ArrayList<TypePattern>()
        for (pat in letPat.patterns) {
            CollectTypePatterns(pat, typePatterns)
        }
        for (typePat in typePatterns) {
            DiagnoseRefactor(diag, DiagKindRefactor.sema_java_interop_not_supported, typePat,
                "let type patterns with JavaImpl or JavaMirror types").Emit()
        }
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        Walker(ctx.pkg, visitPre: { node: Node =>
            if (let Some(ie) <- (node as IsExpr)) {
                if (ShouldDesugarTypecheck(ie.isType, ie.leftExpr)) {
                    DesugarIsExpression(ie)
                }
            } else if (let Some(ae) <- (node as AsExpr)) {
                if (ShouldDesugarTypecheck(ae.asType, ae.leftExpr)) {
                    DesugarAsExpression(ae)
                }
            } else if (let Some(matchCase) <- (node as MatchCase)) {
                DesugarMatchCase(matchCase)
            } else if (let Some(letPat) <- (node as LetPatternDestructor)) {
                DesugarLetPattern(letPat)
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
    }
}
