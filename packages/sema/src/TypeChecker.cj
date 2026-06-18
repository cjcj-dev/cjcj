package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions

public class RealSemaDiagnostic {
    public let position: Position
    public let message: String

    public init(position: Position, message: String) {
        this.position = position
        this.message = message
    }
}

private class RealPipelineLocalInfo {
    let ty: Ty
    let mutable: Bool

    init(ty: Ty, mutable: Bool) {
        this.ty = ty
        this.mutable = mutable
    }
}

private class RealPipelineScope {
    private let locals: HashMap<String, RealPipelineLocalInfo> = HashMap<String, RealPipelineLocalInfo>()

    func Add(name: String, ty: Ty, mutable: Bool): Bool {
        if (locals.contains(name)) {
            return false
        }
        locals[name] = RealPipelineLocalInfo(ty, mutable)
        return true
    }

    func Get(name: String): Option<RealPipelineLocalInfo> {
        return locals.get(name)
    }

    func Contains(name: String): Bool {
        return locals.contains(name)
    }
}

public class TypeChecker {
    private var ci: Option<CompilerInstance> = None
    private var tm: TypeManager = TypeManager()
    private let realPipelineDiagnostics: ArrayList<RealSemaDiagnostic> = ArrayList<RealSemaDiagnostic>()
    private let realPipelineTypedFunctions: ArrayList<String> = ArrayList<String>()
    private let realPipelineDeclaredFunctions: HashSet<String> = HashSet<String>()
    private let realPipelineUnsupportedFunctions: HashSet<String> = HashSet<String>()
    private let realPipelineFunctionDecls: HashMap<String, FuncDecl> = HashMap<String, FuncDecl>()
    private let realPipelineFunctionTypes: HashMap<String, FuncTy> = HashMap<String, FuncTy>()
    private var realPipelineUnsupported: Bool = false

    public init(ci: Option<CompilerInstance>) {
        this.ci = ci
        if (let Some(instance) <- ci) {
            tm = instance.typeManager
        }
    }

    public func TypeCheckForPackages(pkgs: ArrayList<Package>): Unit {
        realPipelineDiagnostics.clear()
        realPipelineTypedFunctions.clear()
        realPipelineUnsupported = false
        for (pkg in pkgs) {
            preparePackageTypes(pkg)
            prepareRealPipelineFunctionTable(pkg)
            checkRealPipelinePackage(pkg)
        }
    }

    public func GetRealPipelineDiagnostics(): ArrayList<RealSemaDiagnostic> {
        let out = ArrayList<RealSemaDiagnostic>()
        for (diag in realPipelineDiagnostics) {
            out.add(diag)
        }
        return out
    }

    public func GetRealPipelineTypedFunctions(): ArrayList<String> {
        let out = ArrayList<String>()
        for (summary in realPipelineTypedFunctions) {
            out.add(summary)
        }
        return out
    }

    public func HasRealPipelineErrors(): Bool {
        return !realPipelineDiagnostics.isEmpty()
    }

    public func HasRealPipelineUnsupported(): Bool {
        return realPipelineUnsupported
    }

    public func SetOverflowStrategy(pkgs: ArrayList<Package>): Unit {
        var optionStrategy = OverflowStrategy.THROWING
        if (let Some(instance) <- ci) {
            optionStrategy = instance.globalOptions.overflowStrategy
        }
        SetIntegerOverflowStrategy(pkgs, optionStrategy)
    }

    public func CheckInlineFunctions(pkgs: ArrayList<Package>): Unit {
        if (let Some(instance) <- ci) {
            CheckInlineFunctionsForPackages(pkgs, instance.globalOptions)
        }
    }

    public func CheckUnusedImportSpec(pkg: Package): ArrayList<UnusedImportFinding> {
        return CollectUnusedImports(pkg)
    }

    public func CheckAllDeclAttributes(pkg: Package): ArrayList<DeclAttributeIssue> {
        var options = OptionGlobalOptions()
        if (let Some(instance) <- ci) {
            options = instance.globalOptions
        }
        return CheckDeclAttributesForPackage(pkg, opts: options)
    }

    public func PerformDesugarAfterInstantiation(ctx: ASTContext, pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        PerformRecursiveTypesElimination(ctx.packageDecls, tm)
        MarkExtendBox(tm, pkg)
    }

    public func PerformDesugarAfterSema(pkgs: ArrayList<Package>): Unit {
        let tyVarScope = BeginTyVarScope(tm)
        for (pkg in pkgs) {
            MarkExtendBox(tm, pkg)
        }
        EndTyVarScope(tyVarScope)
    }

    public func SynReferenceSeparately(ctx: ASTContext, scopeName: String, expr: Expr, hasLocalDecl: Bool): Candidate {
        let _ = scopeName
        let _ = hasLocalDecl
        let candidate = Candidate()
        if (let Some(ty) <- expr.GetTy()) {
            candidate.tys.add(ty)
            candidate.hasDecl = false
            return candidate
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            let names = Names(refExpr.ref.identifier.Val(), ctx.currentScopeName)
            for (decl in ctx.GetDeclsByName(names)) {
                candidate.decls.add(decl)
            }
            candidate.hasDecl = !candidate.decls.isEmpty()
        }
        return candidate
    }

    public func RemoveTargetNotMeetExtendConstraint(baseTy: Ty, targets: ArrayList<Decl>): Unit {
        var idx: Int64 = 0
        while (idx < targets.size) {
            if (let Some(parentDecl) <- targets[idx].outerDecl) {
                if (let Some(extendDecl) <- (parentDecl as ExtendDecl)) {
                    if (!tm.CheckExtendWithConstraint(baseTy, extendDecl)) {
                        targets.remove(at: idx)
                        continue
                    }
                }
            }
            idx++
        }
    }

    private func preparePackageTypes(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                synthesizeDeclType(decl)
            }
        }
    }

    private func prepareRealPipelineFunctionTable(pkg: Package): Unit {
        realPipelineDeclaredFunctions.clear()
        realPipelineUnsupportedFunctions.clear()
        realPipelineFunctionDecls.clear()
        realPipelineFunctionTypes.clear()
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    let name = funcDecl.identifier.Val()
                    if (name.isEmpty()) {
                        markRealPipelineUnsupported()
                        continue
                    }
                    if (realPipelineDeclaredFunctions.contains(name)) {
                        realPipelineUnsupportedFunctions.add(name)
                        realPipelineFunctionDecls.remove(name)
                        realPipelineFunctionTypes.remove(name)
                        markRealPipelineUnsupported()
                    } else {
                        realPipelineDeclaredFunctions.add(name)
                    }
                }
            }
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    let name = funcDecl.identifier.Val()
                    if (name.isEmpty() || realPipelineUnsupportedFunctions.contains(name)) {
                        continue
                    }
                    let body = match (funcDecl.funcBody) {
                        case Some(value) => value
                        case None =>
                            realPipelineUnsupportedFunctions.add(name)
                            markRealPipelineUnsupported()
                            continue
                    }
                    body.funcDecl = Some(funcDecl)
                    let funcTy = match (prepareRealPipelineFuncSignature(decl, body)) {
                        case Some(value) => value
                        case None =>
                            realPipelineUnsupportedFunctions.add(name)
                            markRealPipelineUnsupported()
                            continue
                    }
                    realPipelineFunctionDecls[name] = funcDecl
                    realPipelineFunctionTypes[name] = funcTy
                }
            }
        }
    }

    private func synthesizeDeclType(decl: Decl): Unit {
        if (!Ty.IsTyCorrect(decl.GetTy())) {
            if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
                if (let Some(typeNode) <- varDecl.typeNode) {
                    if (let Some(ty) <- typeNode.GetTy()) {
                        decl.SetTy(ty)
                    }
                }
            } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(body) <- funcDecl.funcBody) {
                    let params = ArrayList<Ty>()
                    if (!body.paramLists.isEmpty()) {
                        for (param in body.paramLists[0].params) {
                            if (let Some(ty) <- param.GetTy()) {
                                params.add(ty)
                            } else {
                                params.add(TypeManager.GetInvalidTy())
                            }
                        }
                    }
                    var retTy: Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    if (let Some(retType) <- body.retType) {
                        if (let Some(ty) <- retType.GetTy()) {
                            retTy = ty
                        }
                    }
                    decl.SetTy(tm.GetFunctionTy(params.toArray(), retTy))
                }
            }
        }
        for (member in decl.GetMemberDecls()) {
            synthesizeDeclType(member)
        }
    }

    private func checkRealPipelinePackage(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                checkRealPipelineDecl(decl)
            }
        }
    }

    private func checkRealPipelineDecl(decl: Decl): Unit {
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(body) <- mainDecl.funcBody) {
                checkRealPipelineFuncLike(decl, body, "main")
            } else {
                markRealPipelineUnsupported()
            }
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                body.funcDecl = Some(funcDecl)
                checkRealPipelineFuncLike(decl, body, funcDecl.identifier.Val())
            } else {
                markRealPipelineUnsupported()
            }
            return
        }
        markRealPipelineUnsupported()
        for (member in decl.GetMemberDecls()) {
            checkRealPipelineDecl(member)
        }
    }

    private func checkRealPipelineFuncLike(decl: Decl, body: FuncBody, displayName: String): Unit {
        let funcTy = match (prepareRealPipelineFuncSignature(decl, body)) {
            case Some(value) => value
            case None => return
        }
        let retTy = funcTy.retTy
        let supportedBody = checkRealPipelineBody(body, retTy)
        if (supportedBody) {
            realPipelineTypedFunctions.add(displayName + ": " + funcTy.String())
        }
    }

    private func prepareRealPipelineFuncSignature(decl: Decl, body: FuncBody): Option<FuncTy> {
        if (body.generic.isSome() || body.paramLists.size != 1) {
            markRealPipelineUnsupported()
            return None
        }
        let params = ArrayList<Ty>()
        for (param in body.paramLists[0].params) {
            if (let Some(paramType) <- param.typeNode) {
                if (let Some(paramTy) <- resolveRealPipelinePrimitiveType(paramType)) {
                    if (!isRealPipelineValueTy(paramTy)) {
                        param.SetTy(TypeManager.GetInvalidTy())
                        params.add(TypeManager.GetInvalidTy())
                        markRealPipelineUnsupported()
                        return None
                    }
                    param.SetTy(paramTy)
                    params.add(paramTy)
                } else {
                    param.SetTy(TypeManager.GetInvalidTy())
                    params.add(TypeManager.GetInvalidTy())
                    markRealPipelineUnsupported()
                    return None
                }
            } else {
                markRealPipelineUnsupported()
                return None
            }
        }
        let retTy = match (resolveRealPipelineReturnTy(body)) {
            case Some(value) => value
            case None => return None
        }
        let funcTy = tm.GetFunctionTy(params.toArray(), retTy)
        body.SetTy(funcTy)
        decl.SetTy(funcTy)
        return Some(funcTy)
    }

    private func resolveRealPipelineReturnTy(body: FuncBody): Option<Ty> {
        if (let Some(retType) <- body.retType) {
            if (let Some(retTy) <- resolveRealPipelinePrimitiveType(retType)) {
                if (!isRealPipelineReturnTy(retTy)) {
                    markRealPipelineUnsupported()
                    return None
                }
                return Some(retTy)
            }
            retType.SetTy(TypeManager.GetInvalidTy())
            markRealPipelineUnsupported()
            return None
        }
        if (realPipelineBodyHasValueReturn(body)) {
            markRealPipelineUnsupported()
            return None
        }
        return Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
    }

    private func resolveRealPipelinePrimitiveType(typeNode: Type): Option<Ty> {
        if (let Some(existing) <- typeNode.GetTy()) {
            if (!existing.HasInvalidTy() && existing.kind != TypeKind.TYPE_INITIAL) {
                return Some(existing)
            }
        }
        if (let Some(primitiveType) <- (typeNode as PrimitiveType)) {
            if (primitiveType.kind == TypeKind.TYPE_INVALID) {
                return None
            }
            let kind = if (primitiveType.kind == TypeKind.TYPE_IDEAL_INT) {
                TypeKind.TYPE_INT64
            } else {
                primitiveType.kind
            }
            let ty = TypeManager.GetPrimitiveTy(kind)
            primitiveType.SetTy(ty)
            return Some(ty)
        }
        if (let Some(parenType) <- (typeNode as ParenType)) {
            if (let Some(innerType) <- parenType.innerType) {
                if (let Some(ty) <- resolveRealPipelinePrimitiveType(innerType)) {
                    parenType.SetTy(ty)
                    return Some(ty)
                }
            }
        }
        return None
    }

    private func checkRealPipelineBody(body: FuncBody, retTy: Ty): Bool {
        let block = match (body.body) {
            case Some(value) => value
            case None =>
                markRealPipelineUnsupported()
                return false
        }
        if (block.body.isEmpty()) {
            if (retTy.kind == TypeKind.TYPE_UNIT) {
                block.SetTy(retTy)
                return true
            }
            emitRealPipelineTypeError(block.begin, "missing return value for declared return type " + retTy.String())
            block.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let scope = RealPipelineScope()
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                let paramTy = match (param.GetTy()) {
                    case Some(value) => value
                    case None =>
                        markRealPipelineUnsupported()
                        return false
                }
                if (!scope.Add(param.identifier.Val(), paramTy, false)) {
                    emitRealPipelineTypeError(param.begin, "duplicate local binding '" + param.identifier.Val() + "'")
                    param.SetTy(TypeManager.GetInvalidTy())
                    return true
                }
            }
        }
        var sawReturn = false
        for (node in block.body) {
            let stmtStatus = checkRealPipelineStmt(node, body, retTy, scope)
            if (!stmtStatus[0]) {
                markRealPipelineUnsupported()
                return false
            }
            if (stmtStatus[1]) {
                sawReturn = true
            }
        }
        if (!sawReturn && retTy.kind != TypeKind.TYPE_UNIT) {
            emitRealPipelineTypeError(block.begin, "missing return value for declared return type " + retTy.String())
            block.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        if (sawReturn) {
            block.SetTy(TypeManager.GetNothingTy())
        } else {
            block.SetTy(retTy)
        }
        return true
    }

    private func checkRealPipelineStmt(
        node: Node,
        body: FuncBody,
        retTy: Ty,
        scope: RealPipelineScope
    ): Array<Bool> {
        if (let Some(varDecl) <- (node as VarDecl)) {
            return [checkRealPipelineVarDecl(varDecl, scope), false]
        }
        if (let Some(assignExpr) <- (node as AssignExpr)) {
            return [checkRealPipelineAssign(assignExpr, scope), false]
        }
        if (let Some(ret) <- (node as ReturnExpr)) {
            ret.refFuncBody = Some(body)
            return [checkRealPipelineReturn(ret, retTy, scope), true]
        }
        if (let Some(callExpr) <- (node as CallExpr)) {
            return [checkRealPipelinePrintStmt(callExpr, scope), false]
        }
        return [false, false]
    }

    private func checkRealPipelineVarDecl(varDecl: VarDecl, scope: RealPipelineScope): Bool {
        if (varDecl.isConst) {
            return false
        }
        let name = varDecl.identifier.Val()
        if (name.isEmpty()) {
            return false
        }
        if (scope.Contains(name)) {
            emitRealPipelineTypeError(varDecl.begin, "duplicate local binding '" + name + "'")
            varDecl.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let declaredTy: Option<Ty> = match (varDecl.typeNode) {
            case Some(typeNode) =>
                match (resolveRealPipelineLocalType(typeNode)) {
                    case Some(ty) =>
                        if (!isRealPipelineLocalTy(ty)) {
                            return false
                        }
                        Some(ty)
                    case None => return false
                }
            case None => None
        }
        let initializer = match (varDecl.initializer) {
            case Some(value) => value
            case None => return false
        }
        let initTy = match (typeRealPipelineExpr(initializer, scope, declaredTy)) {
            case Some(value) => value
            case None => return false
        }
        let localTy = match (declaredTy) {
            case Some(value) => value
            case None => initTy
        }
        varDecl.SetTy(localTy)
        if (let Some(typeNode) <- varDecl.typeNode) {
            typeNode.SetTy(localTy)
        }
        if (let Some(targetTy) <- declaredTy) {
            if (!isRealPipelineAssignable(targetTy, initTy)) {
                emitRealPipelineTypeError(initializer.begin,
                    initTy.String() + " initializer is not assignable to " + targetTy.String() + " local '" + name + "'")
                varDecl.SetTy(TypeManager.GetInvalidTy())
            }
        }
        let _ = scope.Add(name, localTy, varDecl.isVar)
        return true
    }

    private func checkRealPipelinePrintStmt(callExpr: CallExpr, scope: RealPipelineScope): Bool {
        let base = match (callExpr.baseFunc) {
            case Some(value) => value
            case None => return false
        }
        let calleeRef = match (base as RefExpr) {
            case Some(value) => value
            case None => return false
        }
        if (!calleeRef.typeArguments.isEmpty()) {
            return false
        }
        let calleeName = calleeRef.ref.identifier.Val()
        if (calleeName != "println" && calleeName != "print") {
            return false
        }
        if (scope.Contains(calleeName)) {
            return false
        }
        if (callExpr.args.size != 1) {
            emitRealPipelineTypeError(callExpr.begin, calleeName + " expects exactly one argument")
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let arg = callExpr.args[0]
        if (!arg.name.Empty() || arg.withInout) {
            return false
        }
        let argExpr = match (arg.expr) {
            case Some(value) => value
            case None => return false
        }
        let argTy = match (typeRealPipelineExpr(argExpr, scope, None)) {
            case Some(value) => value
            case None => return false
        }
        if (!isRealPipelinePrintableTy(argTy)) {
            emitRealPipelineTypeError(argExpr.begin,
                calleeName + " argument must be Int64, Bool, or String, got " + argTy.String())
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        calleeRef.SetTy(unitTy)
        callExpr.SetTy(unitTy)
        return true
    }

    private func checkRealPipelineAssign(assignExpr: AssignExpr, scope: RealPipelineScope): Bool {
        if (assignExpr.op != TokenKind.ASSIGN) {
            return false
        }
        let left = match (assignExpr.leftValue) {
            case Some(value) => value
            case None => return false
        }
        let refExpr = match (left as RefExpr) {
            case Some(value) => value
            case None => return false
        }
        let name = refExpr.ref.identifier.Val()
        let local = match (scope.Get(name)) {
            case Some(value) => value
            case None =>
                emitRealPipelineTypeError(refExpr.begin, "undeclared local '" + name + "'")
                assignExpr.SetTy(TypeManager.GetInvalidTy())
                return true
        }
        if (!local.mutable) {
            emitRealPipelineTypeError(refExpr.begin, "cannot assign to immutable local '" + name + "'")
            assignExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let right = match (assignExpr.rightExpr) {
            case Some(value) => value
            case None => return false
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(local.ty))) {
            case Some(value) => value
            case None => return false
        }
        if (!isRealPipelineAssignable(local.ty, rightTy)) {
            emitRealPipelineTypeError(right.begin,
                rightTy.String() + " assignment is not assignable to " + local.ty.String() + " local '" + name + "'")
            assignExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        assignExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        return true
    }

    private func checkRealPipelineReturn(ret: ReturnExpr, retTy: Ty, scope: RealPipelineScope): Bool {
        if (let Some(expr) <- ret.expr) {
            let exprTy = match (typeRealPipelineExpr(expr, scope, Some(retTy))) {
                case Some(value) => value
                case None => return false
            }
            if (!isRealPipelineAssignable(retTy, exprTy)) {
                emitRealPipelineTypeError(expr.begin,
                    exprTy.String() + " expression is not assignable to " + retTy.String() + " return type")
                ret.SetTy(TypeManager.GetInvalidTy())
                return true
            }
            ret.SetTy(TypeManager.GetNothingTy())
            return true
        }
        if (retTy.kind != TypeKind.TYPE_UNIT) {
            emitRealPipelineTypeError(ret.begin, "return without value is not assignable to " + retTy.String())
            ret.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        ret.SetTy(TypeManager.GetNothingTy())
        return true
    }

    private func typeRealPipelineExpr(expr: Expr, scope: RealPipelineScope, targetTy: Option<Ty>): Option<Ty> {
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            let inner = match (parenExpr.expr) {
                case Some(value) => value
                case None => return None
            }
            let innerTy = match (typeRealPipelineExpr(inner, scope, targetTy)) {
                case Some(value) => value
                case None => return None
            }
            parenExpr.SetTy(innerTy)
            return Some(innerTy)
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
            return typeRealPipelineLiteralExpr(lit, targetTy)
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            let name = refExpr.ref.identifier.Val()
            let local = match (scope.Get(name)) {
                case Some(value) => value
                case None =>
                    emitRealPipelineTypeError(refExpr.begin, "undeclared local '" + name + "'")
                    refExpr.SetTy(TypeManager.GetInvalidTy())
                    return Some(TypeManager.GetInvalidTy())
            }
            refExpr.SetTy(local.ty)
            return Some(local.ty)
        }
        if (let Some(unaryExpr) <- (expr as UnaryExpr)) {
            return typeRealPipelineUnaryExpr(unaryExpr, scope)
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            return typeRealPipelineBinaryExpr(binaryExpr, scope)
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            return typeRealPipelineCallExpr(callExpr, scope)
        }
        return None
    }

    private func typeRealPipelineLiteralExpr(lit: LitConstExpr, targetTy: Option<Ty>): Option<Ty> {
        var litTy: Ty = TypeManager.GetInvalidTy()
        if (lit.kind == LitConstKind.INTEGER) {
            litTy = match (targetTy) {
                case Some(ty) =>
                    if (ty.kind == TypeKind.TYPE_INT64) { ty } else { TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64) }
                case None => TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
            }
        } else if (lit.kind == LitConstKind.BOOL) {
            litTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        } else if (lit.kind == LitConstKind.UNIT) {
            litTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        } else if (lit.kind == LitConstKind.STRING) {
            if (!isRealPipelinePlainStringLiteral(lit)) {
                return None
            }
            litTy = TypeManager.GetCStringTy()
        } else {
            return None
        }
        lit.SetTy(litTy)
        return Some(litTy)
    }

    private func typeRealPipelineUnaryExpr(unaryExpr: UnaryExpr, scope: RealPipelineScope): Option<Ty> {
        let operand = match (unaryExpr.expr) {
            case Some(value) => value
            case None => return None
        }
        if (unaryExpr.op == TokenKind.SUB) {
            let intTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
            let operandTy = match (typeRealPipelineExpr(operand, scope, Some(intTy))) {
                case Some(value) => value
                case None => return None
            }
            if (!isRealPipelineInt64Ty(operandTy)) {
                emitRealPipelineTypeError(operand.begin, "unary '-' requires Int64 operand, got " + operandTy.String())
                unaryExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
            }
            unaryExpr.SetTy(intTy)
            return Some(intTy)
        }
        if (unaryExpr.op == TokenKind.NOT) {
            let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
            let operandTy = match (typeRealPipelineExpr(operand, scope, Some(boolTy))) {
                case Some(value) => value
                case None => return None
            }
            if (!isRealPipelineBoolTy(operandTy)) {
                emitRealPipelineTypeError(operand.begin, "unary '!' requires Bool operand, got " + operandTy.String())
                unaryExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
            }
            unaryExpr.SetTy(boolTy)
            return Some(boolTy)
        }
        return None
    }

    private func typeRealPipelineBinaryExpr(binaryExpr: BinaryExpr, scope: RealPipelineScope): Option<Ty> {
        if (realPipelineBinaryWouldUseString(binaryExpr, scope)) {
            return None
        }
        if (isRealPipelineArithmeticOp(binaryExpr.op)) {
            return typeRealPipelineIntBinaryExpr(binaryExpr, scope, resultIsBool: false)
        }
        if (isRealPipelineOrderingOp(binaryExpr.op)) {
            return typeRealPipelineIntBinaryExpr(binaryExpr, scope, resultIsBool: true)
        }
        if (binaryExpr.op == TokenKind.EQUAL || binaryExpr.op == TokenKind.NOTEQ) {
            return typeRealPipelineEqualityExpr(binaryExpr, scope)
        }
        if (binaryExpr.op == TokenKind.AND || binaryExpr.op == TokenKind.OR) {
            return typeRealPipelineBoolBinaryExpr(binaryExpr, scope)
        }
        return None
    }

    private func typeRealPipelineCallExpr(callExpr: CallExpr, scope: RealPipelineScope): Option<Ty> {
        let base = match (callExpr.baseFunc) {
            case Some(value) => value
            case None => return None
        }
        let calleeRef = match (base as RefExpr) {
            case Some(value) => value
            case None => return None
        }
        if (!calleeRef.typeArguments.isEmpty()) {
            return None
        }
        let calleeName = calleeRef.ref.identifier.Val()
        if (calleeName == "println" || calleeName == "print") {
            return None
        }
        if (calleeName.isEmpty() || scope.Contains(calleeName)) {
            return None
        }
        if (!realPipelineDeclaredFunctions.contains(calleeName)) {
            emitRealPipelineTypeError(callExpr.begin, "unknown top-level function '" + calleeName + "'")
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        if (realPipelineUnsupportedFunctions.contains(calleeName)) {
            return None
        }
        let funcTy = match (realPipelineFunctionTypes.get(calleeName)) {
            case Some(value) => value
            case None => return None
        }
        if (callExpr.args.size != funcTy.paramTys.size) {
            emitRealPipelineTypeError(callExpr.begin,
                "function '" + calleeName + "' expects " + funcTy.paramTys.size.toString() +
                " argument(s), got " + callExpr.args.size.toString())
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        var idx: Int64 = 0
        while (idx < callExpr.args.size) {
            let arg = callExpr.args[idx]
            if (!arg.name.Empty() || arg.withInout) {
                return None
            }
            let argExpr = match (arg.expr) {
                case Some(value) => value
                case None => return None
            }
            let paramTy = funcTy.paramTys[idx]
            if (!isRealPipelineValueTy(paramTy)) {
                return None
            }
            let argTy = match (typeRealPipelineExpr(argExpr, scope, Some(paramTy))) {
                case Some(value) => value
                case None => return None
            }
            if (!isRealPipelineAssignable(paramTy, argTy)) {
                emitRealPipelineTypeError(argExpr.begin,
                    argTy.String() + " argument is not assignable to " + paramTy.String() +
                    " parameter " + idx.toString() + " of function '" + calleeName + "'")
                callExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
            }
            idx++
        }
        if (let Some(funcDecl) <- realPipelineFunctionDecls.get(calleeName)) {
            calleeRef.ref.target = Some(funcDecl)
            callExpr.resolvedFunction = Some(funcDecl)
            callExpr.callKind = CallKind.CALL_DECLARED_FUNCTION
        }
        calleeRef.SetTy(funcTy)
        callExpr.SetTy(funcTy.retTy)
        return Some(funcTy.retTy)
    }

    private func typeRealPipelineIntBinaryExpr(
        binaryExpr: BinaryExpr,
        scope: RealPipelineScope,
        resultIsBool!: Bool
    ): Option<Ty> {
        let intTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let leftTy = match (typeRealPipelineExpr(left, scope, Some(intTy))) {
            case Some(value) => value
            case None => return None
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(intTy))) {
            case Some(value) => value
            case None => return None
        }
        if (!isRealPipelineInt64Ty(leftTy) || !isRealPipelineInt64Ty(rightTy)) {
            emitRealPipelineTypeError(binaryExpr.begin,
                "operator '" + TokenKindText(binaryExpr.op) + "' requires Int64 operands")
            binaryExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        let resultTy = if (resultIsBool) { boolTy } else { intTy }
        binaryExpr.SetTy(resultTy)
        return Some(resultTy)
    }

    private func typeRealPipelineEqualityExpr(binaryExpr: BinaryExpr, scope: RealPipelineScope): Option<Ty> {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let leftTy = match (typeRealPipelineExpr(left, scope, None)) {
            case Some(value) => value
            case None => return None
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(leftTy))) {
            case Some(value) => value
            case None => return None
        }
        let comparable = (isRealPipelineInt64Ty(leftTy) && isRealPipelineInt64Ty(rightTy)) ||
            (isRealPipelineBoolTy(leftTy) && isRealPipelineBoolTy(rightTy))
        if (!comparable) {
            emitRealPipelineTypeError(binaryExpr.begin,
                "operator '" + TokenKindText(binaryExpr.op) + "' requires matching Int64 or Bool operands")
            binaryExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        binaryExpr.SetTy(boolTy)
        return Some(boolTy)
    }

    private func typeRealPipelineBoolBinaryExpr(binaryExpr: BinaryExpr, scope: RealPipelineScope): Option<Ty> {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let leftTy = match (typeRealPipelineExpr(left, scope, Some(boolTy))) {
            case Some(value) => value
            case None => return None
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(boolTy))) {
            case Some(value) => value
            case None => return None
        }
        if (!isRealPipelineBoolTy(leftTy) || !isRealPipelineBoolTy(rightTy)) {
            emitRealPipelineTypeError(binaryExpr.begin,
                "operator '" + TokenKindText(binaryExpr.op) + "' requires Bool operands")
            binaryExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        binaryExpr.SetTy(boolTy)
        return Some(boolTy)
    }

    private func isRealPipelineArithmeticOp(op: TokenKind): Bool {
        return op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL ||
            op == TokenKind.DIV || op == TokenKind.MOD
    }

    private func isRealPipelineOrderingOp(op: TokenKind): Bool {
        return op == TokenKind.LT || op == TokenKind.LE || op == TokenKind.GT || op == TokenKind.GE
    }

    private func isRealPipelineValueTy(ty: Ty): Bool {
        return isRealPipelineInt64Ty(ty) || isRealPipelineBoolTy(ty)
    }

    private func isRealPipelineLocalTy(ty: Ty): Bool {
        return isRealPipelineValueTy(ty) || isRealPipelineStringTy(ty)
    }

    private func isRealPipelinePrintableTy(ty: Ty): Bool {
        return isRealPipelineLocalTy(ty)
    }

    private func isRealPipelineReturnTy(ty: Ty): Bool {
        return isRealPipelineValueTy(ty) || ty.kind == TypeKind.TYPE_UNIT
    }

    private func isRealPipelineInt64Ty(ty: Ty): Bool {
        return !ty.HasInvalidTy() && ty.kind == TypeKind.TYPE_INT64
    }

    private func isRealPipelineBoolTy(ty: Ty): Bool {
        return !ty.HasInvalidTy() && ty.kind == TypeKind.TYPE_BOOLEAN
    }

    private func isRealPipelineStringTy(ty: Ty): Bool {
        return !ty.HasInvalidTy() && ty.kind == TypeKind.TYPE_CSTRING
    }

    private func isRealPipelineAssignable(targetTy: Ty, exprTy: Ty): Bool {
        if (exprTy.HasInvalidTy() || targetTy.HasInvalidTy()) {
            return false
        }
        if (targetTy.kind == exprTy.kind) {
            return true
        }
        return tm.CheckTypeCompatibility(targetTy, exprTy) != TypeCompatibility.INCOMPATIBLE
    }

    private func realPipelineBodyHasValueReturn(body: FuncBody): Bool {
        if (let Some(block) <- body.body) {
            for (node in block.body) {
                if (let Some(ret) <- (node as ReturnExpr)) {
                    return ret.expr.isSome()
                }
            }
        }
        return false
    }

    private func resolveRealPipelineLocalType(typeNode: Type): Option<Ty> {
        if (let Some(ty) <- resolveRealPipelinePrimitiveType(typeNode)) {
            return Some(ty)
        }
        let text = typeNode.ToString().trimAscii()
        if (text == "String" || text == "CString") {
            let ty = TypeManager.GetCStringTy()
            typeNode.SetTy(ty)
            return Some(ty)
        }
        return None
    }

    private func isRealPipelinePlainStringLiteral(lit: LitConstExpr): Bool {
        if (lit.kind != LitConstKind.STRING || lit.siExpr.isSome()) {
            return false
        }
        let text = lit.stringValue
        var idx: Int64 = 0
        while (idx < text.size) {
            if (text[idx] == b'\\') {
                return false
            }
            idx++
        }
        return true
    }

    private func realPipelineBinaryWouldUseString(binaryExpr: BinaryExpr, scope: RealPipelineScope): Bool {
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return false
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return false
        }
        return realPipelineExprCouldBeString(left, scope) || realPipelineExprCouldBeString(right, scope)
    }

    private func realPipelineExprCouldBeString(expr: Expr, scope: RealPipelineScope): Bool {
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            if (let Some(inner) <- parenExpr.expr) {
                return realPipelineExprCouldBeString(inner, scope)
            }
            return false
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
            return lit.kind == LitConstKind.STRING
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            if (let Some(local) <- scope.Get(refExpr.ref.identifier.Val())) {
                return isRealPipelineStringTy(local.ty)
            }
            return false
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            if (binaryExpr.op == TokenKind.ADD) {
                return realPipelineBinaryWouldUseString(binaryExpr, scope)
            }
        }
        return false
    }

    private func markRealPipelineUnsupported(): Unit {
        realPipelineUnsupported = true
    }

    private func emitRealPipelineTypeError(position: Position, message: String): Unit {
        realPipelineDiagnostics.add(RealSemaDiagnostic(position, message))
    }
}
