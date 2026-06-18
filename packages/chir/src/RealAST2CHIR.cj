package cangjie_compiler::chir

import std.collection.*
import std.convert.*
import cangjie_compiler::ast.Package as AstPackage
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.MainDecl as AstMainDecl
import cangjie_compiler::ast.FuncBody as AstFuncBody
import cangjie_compiler::ast.Type as AstType
import cangjie_compiler::ast.LitConstExpr as AstLitConstExpr
import cangjie_compiler::ast.LitConstKind as AstLitConstKind
import cangjie_compiler::ast.Node as AstNode
import cangjie_compiler::ast.ReturnExpr as AstReturnExpr
import cangjie_compiler::ast.VarDecl as AstVarDecl
import cangjie_compiler::ast.AssignExpr as AstAssignExpr
import cangjie_compiler::ast.RefExpr as AstRefExpr
import cangjie_compiler::ast.BinaryExpr as AstBinaryExpr
import cangjie_compiler::ast.UnaryExpr as AstUnaryExpr
import cangjie_compiler::ast.ParenExpr as AstParenExpr
import cangjie_compiler::ast.CallExpr as AstCallExpr
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.Block as AstBlock
import cangjie_compiler::ast.IfExpr as AstIfExpr
import cangjie_compiler::ast.WhileExpr as AstWhileExpr
import cangjie_compiler::ast.JumpExpr as AstJumpExpr
import cangjie_compiler::ast.TokenKind as AstTokenKind

private let REAL_AST_RETURN_NONE: Int64 = 0
private let REAL_AST_RETURN_INT: Int64 = 1
private let REAL_AST_RETURN_BOOL: Int64 = 2
private let REAL_AST_RETURN_UNIT: Int64 = 3
private let REAL_AST_RETURN_STRING: Int64 = 4

private class RealASTFunctionInfo {
    let paramKinds: ArrayList<Int64> = ArrayList<Int64>()
    let returnKind: Int64

    init(returnKind: Int64) {
        this.returnKind = returnKind
    }
}

private class RealASTPackageLoweringScope {
    let functions = HashMap<String, RealASTFunctionInfo>()

    func AddFunction(name: String, info: RealASTFunctionInfo): Bool {
        if (name.isEmpty() || functions.contains(name)) {
            return false
        }
        functions[name] = info
        return true
    }

    func GetFunction(name: String): Option<RealASTFunctionInfo> {
        return functions.get(name)
    }
}

private class RealASTBodyLowering {
    let ok: Bool
    let stmts: ArrayList<AST2CHIRStmtSpec>
    let returnKind: Int64

    init(ok: Bool, stmts: ArrayList<AST2CHIRStmtSpec>, returnKind: Int64) {
        this.ok = ok
        this.stmts = stmts
        this.returnKind = returnKind
    }
}

private class RealASTParamLowering {
    let types: ArrayList<Type> = ArrayList<Type>()
    let names: ArrayList<String> = ArrayList<String>()
}

private class RealASTStmtLowering {
    let stmt: AST2CHIRStmtSpec
    let returnKind: Int64

    init(stmt: AST2CHIRStmtSpec, returnKind: Int64) {
        this.stmt = stmt
        this.returnKind = returnKind
    }
}

private class RealASTScopeSnapshot {
    let locals = HashMap<String, Bool>()
    let localKinds = HashMap<String, Int64>()
    let loopDepth: Int64

    init(scope: RealASTLoweringScope) {
        for ((name, mutable) in scope.locals) {
            locals[name] = mutable
        }
        for ((name, kind) in scope.localKinds) {
            localKinds[name] = kind
        }
        loopDepth = scope.loopDepth
    }
}

private class RealASTLoweringScope {
    let locals = HashMap<String, Bool>()
    let localKinds = HashMap<String, Int64>()
    var loopDepth: Int64 = 0

    init(body: AstFuncBody) {
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                let name = param.identifier.Val()
                if (!name.isEmpty()) {
                    locals[name] = false
                    if (let Some(typeNode) <- param.typeNode) {
                        if (let Some(kind) <- RealASTValueTypeKind(typeNode)) {
                            localKinds[name] = kind
                        }
                    }
                }
            }
        }
    }

    func Contains(name: String): Bool {
        return locals.contains(name)
    }

    func Add(name: String, mutable: Bool, kind: Int64): Bool {
        if (locals.contains(name)) {
            return false
        }
        locals[name] = mutable
        localKinds[name] = kind
        return true
    }

    func CanAssign(name: String): Bool {
        return locals.get(name) ?? false
    }

    func Kind(name: String): Option<Int64> {
        return localKinds.get(name)
    }

    func Save(): RealASTScopeSnapshot {
        return RealASTScopeSnapshot(this)
    }

    func Restore(snapshot: RealASTScopeSnapshot): Unit {
        locals.clear()
        localKinds.clear()
        for ((name, mutable) in snapshot.locals) {
            locals[name] = mutable
        }
        for ((name, kind) in snapshot.localKinds) {
            localKinds[name] = kind
        }
        loopDepth = snapshot.loopDepth
    }

    func EnterLoop(): Unit {
        loopDepth++
    }

    func ExitLoop(): Unit {
        if (loopDepth > 0) {
            loopDepth--
        }
    }

    func InLoop(): Bool {
        return loopDepth > 0
    }
}

public func DescribeRealASTFunctionLowering(pkg: AstPackage): ArrayList<String> {
    let out = ArrayList<String>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            if ((decl as AstMainDecl).isSome() || (decl as AstFuncDecl).isSome()) {
                out.add(RealASTDisplayName(decl))
            }
        }
    }
    return out
}

public func TryLowerRealASTPackage(pkg: AstPackage, builder: CHIRBuilder): Option<Package> {
    if (pkg.files.isEmpty()) {
        return None
    }
    if (let Some(spec) <- BuildRealASTPackageSpec(pkg, builder.context)) {
        return Some(AST2CHIR(builder).LowerPackage(spec).pkg)
    }
    return None
}

private func BuildRealASTPackageSpec(pkg: AstPackage, context: CHIRContext): Option<AST2CHIRPackageSpec> {
    let packageScope = match (BuildRealASTPackageLoweringScope(pkg)) {
        case Some(value) => value
        case None => return None
    }
    let spec = AST2CHIRPackageSpec(pkg.fullPackageName)
    spec.SetAccessLevel(AccessLevel.PUBLIC)
    var funcCount: Int64 = 0
    for (file in pkg.files) {
        if (!file.imports.isEmpty()) {
            return None
        }
        let fileName = if (file.filePath.isEmpty()) { file.fileName } else { file.filePath }
        spec.RegisterSourceFile(UInt32(file.begin.fileID), fileName)
        for (decl in file.decls) {
            if (let Some(fnSpec) <- BuildRealASTFunctionSpec(pkg.fullPackageName, decl, context, fileName,
                packageScope)) {
                spec.AddFunction(fnSpec)
                funcCount++
            } else {
                return None
            }
        }
    }
    if (funcCount == 0) {
        return None
    }
    return Some(spec)
}

private func BuildRealASTPackageLoweringScope(pkg: AstPackage): Option<RealASTPackageLoweringScope> {
    let scope = RealASTPackageLoweringScope()
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
                let name = funcDecl.identifier.Val()
                let body = match (funcDecl.funcBody) {
                    case Some(value) => value
                    case None => return None
                }
                let info = match (BuildRealASTFunctionInfo(body)) {
                    case Some(value) => value
                    case None => return None
                }
                if (!scope.AddFunction(name, info)) {
                    return None
                }
            }
        }
    }
    return Some(scope)
}

private func BuildRealASTFunctionInfo(body: AstFuncBody): Option<RealASTFunctionInfo> {
    if (body.generic.isSome() || body.paramLists.size != 1) {
        return None
    }
    let returnKind = match (RealASTFunctionReturnKind(body)) {
        case Some(value) => value
        case None => return None
    }
    let info = RealASTFunctionInfo(returnKind)
    let paramList = body.paramLists[0]
    if (paramList.hasVariableLenArg) {
        return None
    }
    for (param in paramList.params) {
        if (param.assignment.isSome()) {
            return None
        }
        let typeNode = match (param.typeNode) {
            case Some(value) => value
            case None => return None
        }
        let paramKind = match (RealASTValueTypeKind(typeNode)) {
            case Some(value) => value
            case None => return None
        }
        info.paramKinds.add(paramKind)
    }
    return Some(info)
}

private func RealASTFunctionReturnKind(body: AstFuncBody): Option<Int64> {
    if (let Some(retType) <- body.retType) {
        if (IsRealASTInt64Type(retType)) {
            return Some(REAL_AST_RETURN_INT)
        }
        if (IsRealASTBoolType(retType)) {
            return Some(REAL_AST_RETURN_BOOL)
        }
        if (IsRealASTUnitType(retType)) {
            return Some(REAL_AST_RETURN_UNIT)
        }
        return None
    }
    if (RealASTBodyHasValueReturn(body)) {
        return None
    }
    return Some(REAL_AST_RETURN_UNIT)
}

private func RealASTBodyHasValueReturn(body: AstFuncBody): Bool {
    if (let Some(block) <- body.body) {
        return RealASTBlockHasValueReturn(block)
    }
    return false
}

private func RealASTBlockHasValueReturn(block: AstBlock): Bool {
    for (node in block.body) {
        if (RealASTNodeHasValueReturn(node)) {
            return true
        }
    }
    return false
}

private func RealASTNodeHasValueReturn(node: AstNode): Bool {
    if (let Some(ret) <- (node as AstReturnExpr)) {
        return ret.expr.isSome()
    }
    if (let Some(ifExpr) <- (node as AstIfExpr)) {
        if (let Some(thenBlock) <- ifExpr.thenBody) {
            if (RealASTBlockHasValueReturn(thenBlock)) {
                return true
            }
        }
        if (let Some(elseExpr) <- ifExpr.elseBody) {
            if (let Some(elseBlock) <- (elseExpr as AstBlock)) {
                return RealASTBlockHasValueReturn(elseBlock)
            }
            if (RealASTNodeHasValueReturn(elseExpr)) {
                return true
            }
        }
    }
    if (let Some(whileExpr) <- (node as AstWhileExpr)) {
        if (let Some(bodyBlock) <- whileExpr.body) {
            return RealASTBlockHasValueReturn(bodyBlock)
        }
    }
    return false
}

private func BuildRealASTFunctionSpec(
    packageName: String,
    decl: AstDecl,
    context: CHIRContext,
    sourceFileKey: String,
    packageScope: RealASTPackageLoweringScope
): Option<AST2CHIRFunctionSpec> {
    let isMain = (decl as AstMainDecl).isSome()
    if (!isMain && (decl as AstFuncDecl).isNone()) {
        return None
    }
    let body = match (GetRealASTFuncBody(decl)) {
        case Some(value) => value
        case None => return None
    }
    let params = match (BuildRealASTParamLowering(context, body, allowParams: !isMain)) {
        case Some(value) => value
        case None => return None
    }
    let lowered = LowerRealASTBody(body, packageScope)
    if (!lowered.ok) {
        return None
    }
    let returnTy = match (RealASTReturnType(context, body, lowered)) {
        case Some(value) => value
        case None => return None
    }
    let fnName = if (isMain) { "user.main" } else { RealASTStableMangledName(packageName, decl) }
    let srcName = if (decl.identifier.Empty()) {
        if (isMain) { "main" } else { fnName }
    } else {
        decl.identifier.Val()
    }
    let kind = if (isMain) { FuncKind.MAIN_ENTRY } else { FuncKind.DEFAULT }
    let fnSpec = AST2CHIRFunctionSpec(fnName, params.types, returnTy, srcCodeIdentifier: srcName,
        rawMangledName: fnName, packageName: packageName, funcKind: kind, emitBody: true)
    fnSpec.EnableRealBody()
    for (name in params.names) {
        fnSpec.AddParamName(name)
    }
    for (stmt in lowered.stmts) {
        fnSpec.AddBodyStatement(stmt)
    }
    if (decl.IsExportedDecl()) {
        fnSpec.AddAttribute(Attribute.PUBLIC)
    } else {
        fnSpec.AddAttribute(Attribute.PRIVATE)
    }
    if (!sourceFileKey.isEmpty()) {
        fnSpec.SetSourceFileKey(sourceFileKey)
    }
    return Some(fnSpec)
}

private func GetRealASTFuncBody(decl: AstDecl): Option<AstFuncBody> {
    if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
        return funcDecl.funcBody
    }
    if (let Some(mainDecl) <- (decl as AstMainDecl)) {
        return mainDecl.funcBody
    }
    return None
}

private func BuildRealASTParamLowering(
    context: CHIRContext,
    body: AstFuncBody,
    allowParams!: Bool = true
): Option<RealASTParamLowering> {
    if (body.generic.isSome()) {
        return None
    }
    if (body.paramLists.size != 1) {
        return None
    }
    let paramList = body.paramLists[0]
    if (paramList.hasVariableLenArg) {
        return None
    }
    if (!allowParams && !paramList.params.isEmpty()) {
        return None
    }
    let out = RealASTParamLowering()
    for (param in paramList.params) {
        if (param.assignment.isSome()) {
            return None
        }
        let paramTy = match (param.typeNode) {
            case Some(typeNode) =>
                match (RealASTParamType(context, typeNode)) {
                    case Some(value) => value
                    case None => return None
                }
            case None => return None
        }
        out.types.add(paramTy)
        out.names.add(param.identifier.Val())
    }
    return Some(out)
}

private func LowerRealASTBody(body: AstFuncBody, packageScope: RealASTPackageLoweringScope): RealASTBodyLowering {
    let empty = ArrayList<AST2CHIRStmtSpec>()
    let block = match (body.body) {
        case Some(value) => value
        case None => return RealASTBodyLowering(false, empty, REAL_AST_RETURN_NONE)
    }
    let stmts = ArrayList<AST2CHIRStmtSpec>()
    if (block.body.isEmpty()) {
        return RealASTBodyLowering(true, stmts, REAL_AST_RETURN_NONE)
    }
    let scope = RealASTLoweringScope(body)
    let lowered = match (LowerRealASTBlock(block, scope, packageScope, scoped: false)) {
        case Some(value) => value
        case None => return RealASTBodyLowering(false, empty, REAL_AST_RETURN_NONE)
    }
    return lowered
}

private func LowerRealASTBlock(
    block: AstBlock,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope,
    scoped!: Bool = true
): Option<RealASTBodyLowering> {
    let snapshot: Option<RealASTScopeSnapshot> = if (scoped) { Some(scope.Save()) } else { None }
    let stmts = ArrayList<AST2CHIRStmtSpec>()
    var returnKind = REAL_AST_RETURN_NONE
    for (node in block.body) {
        let lowered = match (LowerRealASTBodyNode(node, scope, packageScope)) {
            case Some(value) => value
            case None =>
                if (let Some(value) <- snapshot) {
                    scope.Restore(value)
                }
                return None
        }
        stmts.add(lowered.stmt)
        if (lowered.returnKind != REAL_AST_RETURN_NONE) {
            returnKind = lowered.returnKind
        }
    }
    if (let Some(value) <- snapshot) {
        scope.Restore(value)
    }
    return Some(RealASTBodyLowering(true, stmts, returnKind))
}

private func LowerRealASTBodyNode(
    node: AstNode,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    if (let Some(varDecl) <- (node as AstVarDecl)) {
        return LowerRealASTVarDecl(varDecl, scope, packageScope)
    }
    if (let Some(assign) <- (node as AstAssignExpr)) {
        return LowerRealASTAssign(assign, scope, packageScope)
    }
    if (let Some(ret) <- (node as AstReturnExpr)) {
        return LowerRealASTReturn(ret, scope, packageScope)
    }
    if (let Some(ifExpr) <- (node as AstIfExpr)) {
        return LowerRealASTIf(ifExpr, scope, packageScope)
    }
    if (let Some(whileExpr) <- (node as AstWhileExpr)) {
        return LowerRealASTWhile(whileExpr, scope, packageScope)
    }
    if (let Some(jumpExpr) <- (node as AstJumpExpr)) {
        return LowerRealASTJump(jumpExpr, scope)
    }
    if (let Some(call) <- (node as AstCallExpr)) {
        return LowerRealASTPrint(call, scope, packageScope)
    }
    return None
}

private func RealASTStmtAndKind(stmt: AST2CHIRStmtSpec, kind: Int64): RealASTStmtLowering {
    return RealASTStmtLowering(stmt, kind)
}

private func LowerRealASTVarDecl(
    varDecl: AstVarDecl,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    if (varDecl.isConst) {
        return None
    }
    var declaredKind: Option<Int64> = None
    if (let Some(typeNode) <- varDecl.typeNode) {
        declaredKind = match (RealASTLocalTypeKind(typeNode)) {
            case Some(kind) => Some(kind)
            case None => return None
        }
    }
    let name = varDecl.identifier.Val()
    if (name.isEmpty() || scope.Contains(name)) {
        return None
    }
    let initExpr = match (varDecl.initializer) {
        case Some(value) => value
        case None => return None
    }
    let initKind = match (RealASTExprValueKind(initExpr, scope, packageScope)) {
        case Some(kind) => kind
        case None => return None
    }
    if (let Some(targetKind) <- declaredKind) {
        if (targetKind != initKind) {
            return None
        }
    }
    let exprSpec = match (LowerRealASTExpr(initExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (!scope.Add(name, varDecl.isVar, initKind)) {
        return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Let(name, exprSpec, isVar: varDecl.isVar),
        REAL_AST_RETURN_NONE))
}

private func LowerRealASTAssign(
    assign: AstAssignExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    if (assign.op != AstTokenKind.ASSIGN) {
        return None
    }
    let left = match (assign.leftValue) {
        case Some(value) => value
        case None => return None
    }
    let ref = match (left as AstRefExpr) {
        case Some(value) => value
        case None => return None
    }
    let name = ref.ref.identifier.Val()
    if (name.isEmpty() || !scope.Contains(name) || !scope.CanAssign(name)) {
        return None
    }
    let right = match (assign.rightExpr) {
        case Some(value) => value
        case None => return None
    }
    let rightKind = match (RealASTExprValueKind(right, scope, packageScope)) {
        case Some(kind) => kind
        case None => return None
    }
    if (let Some(localKind) <- scope.Kind(name)) {
        if (localKind != rightKind) {
            return None
        }
    }
    let exprSpec = match (LowerRealASTExpr(right, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Assign(name, exprSpec), REAL_AST_RETURN_NONE))
}

private func LowerRealASTReturn(
    ret: AstReturnExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    if (let Some(expr) <- ret.expr) {
        if (let Some(lit) <- (expr as AstLitConstExpr)) {
            if (let Some(value) <- ParseRealASTIntLiteral(lit)) {
                return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Return(AST2CHIRExprSpec.Literal(value)),
                    REAL_AST_RETURN_INT))
            }
            if (let Some(value) <- ParseRealASTBoolLiteral(lit)) {
                return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Return(AST2CHIRExprSpec.BoolLit(value)),
                    REAL_AST_RETURN_BOOL))
            }
            if (lit.kind == AstLitConstKind.UNIT) {
                return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.ReturnNone(), REAL_AST_RETURN_UNIT))
            }
        }
        let exprKind = match (RealASTExprValueKind(expr, scope, packageScope)) {
            case Some(kind) => kind
            case None => return None
        }
        if (exprKind == REAL_AST_RETURN_STRING) {
            return None
        }
        let exprSpec = match (LowerRealASTExpr(expr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Return(exprSpec), exprKind))
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.ReturnNone(), REAL_AST_RETURN_UNIT))
}

private func LowerRealASTIf(
    ifExpr: AstIfExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    let condExpr = match (ifExpr.condExpr) {
        case Some(value) => value
        case None => return None
    }
    let condKind = match (RealASTExprValueKind(condExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (condKind != REAL_AST_RETURN_BOOL) {
        return None
    }
    let condSpec = match (LowerRealASTExpr(condExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let thenBlock = match (ifExpr.thenBody) {
        case Some(value) => value
        case None => return None
    }
    let thenLowering = match (LowerRealASTBlock(thenBlock, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let elseStmts = ArrayList<AST2CHIRStmtSpec>()
    var elseKind = REAL_AST_RETURN_NONE
    if (let Some(elseExpr) <- ifExpr.elseBody) {
        if (let Some(elseBlock) <- (elseExpr as AstBlock)) {
            let elseLowering = match (LowerRealASTBlock(elseBlock, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            for (stmt in elseLowering.stmts) {
                elseStmts.add(stmt)
            }
            elseKind = elseLowering.returnKind
        } else if (let Some(elseIf) <- (elseExpr as AstIfExpr)) {
            let elseIfLowering = match (LowerRealASTIf(elseIf, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            elseStmts.add(elseIfLowering.stmt)
            elseKind = elseIfLowering.returnKind
        } else {
            return None
        }
    }
    let returnKind = if (elseKind != REAL_AST_RETURN_NONE) {
        elseKind
    } else {
        thenLowering.returnKind
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.If(condSpec, thenLowering.stmts, elseStmts), returnKind))
}

private func LowerRealASTWhile(
    whileExpr: AstWhileExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    let condExpr = match (whileExpr.condExpr) {
        case Some(value) => value
        case None => return None
    }
    let condKind = match (RealASTExprValueKind(condExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (condKind != REAL_AST_RETURN_BOOL) {
        return None
    }
    let condSpec = match (LowerRealASTExpr(condExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let bodyBlock = match (whileExpr.body) {
        case Some(value) => value
        case None => return None
    }
    scope.EnterLoop()
    let bodyLowering = match (LowerRealASTBlock(bodyBlock, scope, packageScope)) {
        case Some(value) => value
        case None =>
            scope.ExitLoop()
            return None
    }
    scope.ExitLoop()
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.While(condSpec, bodyLowering.stmts),
        bodyLowering.returnKind))
}

private func LowerRealASTJump(jumpExpr: AstJumpExpr, scope: RealASTLoweringScope): Option<RealASTStmtLowering> {
    if (!scope.InLoop()) {
        return None
    }
    let stmt = if (jumpExpr.isBreak) {
        AST2CHIRStmtSpec.Break()
    } else {
        AST2CHIRStmtSpec.Continue()
    }
    return Some(RealASTStmtAndKind(stmt, REAL_AST_RETURN_NONE))
}

private func LowerRealASTPrint(
    call: AstCallExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    let base = match (call.baseFunc) {
        case Some(value) => value
        case None => return None
    }
    let calleeRef = match (base as AstRefExpr) {
        case Some(value) => value
        case None => return None
    }
    if (!calleeRef.typeArguments.isEmpty()) {
        return None
    }
    let calleeName = calleeRef.ref.identifier.Val()
    if (calleeName != "println" && calleeName != "print") {
        return None
    }
    if (scope.Contains(calleeName) || call.args.size != 1) {
        return None
    }
    let arg = call.args[0]
    if (!arg.name.Empty() || arg.withInout) {
        return None
    }
    let argExpr = match (arg.expr) {
        case Some(value) => value
        case None => return None
    }
    let newline = calleeName == "println"
    if (let Some(text) <- PlainRealASTStringLiteralValue(argExpr)) {
        return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.PrintStr(text, newline: newline),
            REAL_AST_RETURN_NONE))
    }
    let kind = match (RealASTExprValueKind(argExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (kind != REAL_AST_RETURN_INT && kind != REAL_AST_RETURN_BOOL && kind != REAL_AST_RETURN_STRING) {
        return None
    }
    let exprSpec = match (LowerRealASTExpr(argExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Print(exprSpec, newline: newline), REAL_AST_RETURN_NONE))
}

private func LowerRealASTExpr(
    expr: AstExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<AST2CHIRExprSpec> {
    if (let Some(parenExpr) <- (expr as AstParenExpr)) {
        if (let Some(inner) <- parenExpr.expr) {
            return LowerRealASTExpr(inner, scope, packageScope)
        }
        return None
    }
    if (let Some(lit) <- (expr as AstLitConstExpr)) {
        if (let Some(value) <- ParseRealASTIntLiteral(lit)) {
            return Some(AST2CHIRExprSpec.Literal(value))
        }
        if (let Some(value) <- ParseRealASTBoolLiteral(lit)) {
            return Some(AST2CHIRExprSpec.BoolLit(value))
        }
        if (let Some(text) <- PlainRealASTStringLiteralValue(lit)) {
            return Some(AST2CHIRExprSpec.StrLit(text))
        }
        return None
    }
    if (let Some(refExpr) <- (expr as AstRefExpr)) {
        let name = refExpr.ref.identifier.Val()
        if (name.isEmpty() || !scope.Contains(name)) {
            return None
        }
        return Some(AST2CHIRExprSpec.Ref(name))
    }
    if (let Some(binary) <- (expr as AstBinaryExpr)) {
        if (RealASTExprValueKind(binary, scope, packageScope).isNone()) {
            return None
        }
        let op = match (RealASTBinaryOp(binary.op)) {
            case Some(value) => value
            case None => return None
        }
        let lhs = match (binary.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let rhs = match (binary.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let lhsSpec = match (LowerRealASTExpr(lhs, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let rhsSpec = match (LowerRealASTExpr(rhs, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(AST2CHIRExprSpec.Binary(op, lhsSpec, rhsSpec))
    }
    if (let Some(unary) <- (expr as AstUnaryExpr)) {
        let op = match (RealASTUnaryOp(unary.op)) {
            case Some(value) => value
            case None => return None
        }
        let operand = match (unary.expr) {
            case Some(value) => value
            case None => return None
        }
        let operandSpec = match (LowerRealASTExpr(operand, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(AST2CHIRExprSpec.Unary(op, operandSpec))
    }
    if (let Some(call) <- (expr as AstCallExpr)) {
        return LowerRealASTCall(call, scope, packageScope)
    }
    return None
}

private func LowerRealASTCall(
    call: AstCallExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<AST2CHIRExprSpec> {
    let base = match (call.baseFunc) {
        case Some(value) => value
        case None => return None
    }
    let calleeRef = match (base as AstRefExpr) {
        case Some(value) => value
        case None => return None
    }
    if (!calleeRef.typeArguments.isEmpty()) {
        return None
    }
    let calleeName = calleeRef.ref.identifier.Val()
    if (calleeName.isEmpty() || scope.Contains(calleeName)) {
        return None
    }
    let info = match (packageScope.GetFunction(calleeName)) {
        case Some(value) => value
        case None => return None
    }
    if (info.returnKind != REAL_AST_RETURN_INT && info.returnKind != REAL_AST_RETURN_BOOL) {
        return None
    }
    if (call.args.size != info.paramKinds.size) {
        return None
    }
    let argSpecs = ArrayList<AST2CHIRExprSpec>()
    var idx: Int64 = 0
    while (idx < call.args.size) {
        let arg = call.args[idx]
        if (!arg.name.Empty() || arg.withInout) {
            return None
        }
        let argExpr = match (arg.expr) {
            case Some(value) => value
            case None => return None
        }
        let argKind = match (RealASTExprValueKind(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (argKind != info.paramKinds[idx]) {
            return None
        }
        let argSpec = match (LowerRealASTExpr(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        argSpecs.add(argSpec)
        idx++
    }
    return Some(AST2CHIRExprSpec.Call(calleeName, argSpecs))
}

private func RealASTExprValueKind(
    expr: AstExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<Int64> {
    if (let Some(parenExpr) <- (expr as AstParenExpr)) {
        if (let Some(inner) <- parenExpr.expr) {
            return RealASTExprValueKind(inner, scope, packageScope)
        }
        return None
    }
    if (let Some(lit) <- (expr as AstLitConstExpr)) {
        if (ParseRealASTIntLiteral(lit).isSome()) {
            return Some(REAL_AST_RETURN_INT)
        }
        if (ParseRealASTBoolLiteral(lit).isSome()) {
            return Some(REAL_AST_RETURN_BOOL)
        }
        if (PlainRealASTStringLiteralValue(expr).isSome()) {
            return Some(REAL_AST_RETURN_STRING)
        }
        if (lit.kind == AstLitConstKind.UNIT) {
            return Some(REAL_AST_RETURN_UNIT)
        }
        return None
    }
    if (let Some(refExpr) <- (expr as AstRefExpr)) {
        return scope.Kind(refExpr.ref.identifier.Val())
    }
    if (let Some(unary) <- (expr as AstUnaryExpr)) {
        let operand = match (unary.expr) {
            case Some(value) => value
            case None => return None
        }
        let operandKind = match (RealASTExprValueKind(operand, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (unary.op == AstTokenKind.SUB && operandKind == REAL_AST_RETURN_INT) {
            return Some(REAL_AST_RETURN_INT)
        }
        if (unary.op == AstTokenKind.NOT && operandKind == REAL_AST_RETURN_BOOL) {
            return Some(REAL_AST_RETURN_BOOL)
        }
        return None
    }
    if (let Some(binary) <- (expr as AstBinaryExpr)) {
        let lhs = match (binary.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let rhs = match (binary.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let lhsKind = match (RealASTExprValueKind(lhs, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let rhsKind = match (RealASTExprValueKind(rhs, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (lhsKind == REAL_AST_RETURN_STRING || rhsKind == REAL_AST_RETURN_STRING) {
            return None
        }
        if (RealASTIsArithmeticOp(binary.op)) {
            return if (lhsKind == REAL_AST_RETURN_INT && rhsKind == REAL_AST_RETURN_INT) {
                Some(REAL_AST_RETURN_INT)
            } else {
                None
            }
        }
        if (RealASTIsOrderingOp(binary.op)) {
            return if (lhsKind == REAL_AST_RETURN_INT && rhsKind == REAL_AST_RETURN_INT) {
                Some(REAL_AST_RETURN_BOOL)
            } else {
                None
            }
        }
        if (binary.op == AstTokenKind.EQUAL || binary.op == AstTokenKind.NOTEQ) {
            let comparable = (lhsKind == REAL_AST_RETURN_INT && rhsKind == REAL_AST_RETURN_INT) ||
                (lhsKind == REAL_AST_RETURN_BOOL && rhsKind == REAL_AST_RETURN_BOOL)
            return if (comparable) { Some(REAL_AST_RETURN_BOOL) } else { None }
        }
        if (binary.op == AstTokenKind.AND || binary.op == AstTokenKind.OR) {
            return if (lhsKind == REAL_AST_RETURN_BOOL && rhsKind == REAL_AST_RETURN_BOOL) {
                Some(REAL_AST_RETURN_BOOL)
            } else {
                None
            }
        }
        return None
    }
    if (let Some(call) <- (expr as AstCallExpr)) {
        let base = match (call.baseFunc) {
            case Some(value) => value
            case None => return None
        }
        let calleeRef = match (base as AstRefExpr) {
            case Some(value) => value
            case None => return None
        }
        if (!calleeRef.typeArguments.isEmpty()) {
            return None
        }
        let calleeName = calleeRef.ref.identifier.Val()
        if (calleeName.isEmpty() || scope.Contains(calleeName)) {
            return None
        }
        let info = match (packageScope.GetFunction(calleeName)) {
            case Some(value) => value
            case None => return None
        }
        if (call.args.size != info.paramKinds.size) {
            return None
        }
        var idx: Int64 = 0
        while (idx < call.args.size) {
            let arg = call.args[idx]
            if (!arg.name.Empty() || arg.withInout) {
                return None
            }
            let argExpr = match (arg.expr) {
                case Some(value) => value
                case None => return None
            }
            let argKind = match (RealASTExprValueKind(argExpr, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            if (argKind != info.paramKinds[idx]) {
                return None
            }
            idx++
        }
        return if (info.returnKind == REAL_AST_RETURN_INT || info.returnKind == REAL_AST_RETURN_BOOL) {
            Some(info.returnKind)
        } else {
            None
        }
    }
    return None
}

private func RealASTIsArithmeticOp(op: AstTokenKind): Bool {
    return op == AstTokenKind.ADD || op == AstTokenKind.SUB || op == AstTokenKind.MUL ||
        op == AstTokenKind.DIV || op == AstTokenKind.MOD
}

private func RealASTIsOrderingOp(op: AstTokenKind): Bool {
    return op == AstTokenKind.LT || op == AstTokenKind.LE || op == AstTokenKind.GT || op == AstTokenKind.GE
}

private func RealASTBinaryOp(op: AstTokenKind): Option<ExprKind> {
    return match (op) {
        case AstTokenKind.ADD => Some(ExprKind.ADD)
        case AstTokenKind.SUB => Some(ExprKind.SUB)
        case AstTokenKind.MUL => Some(ExprKind.MUL)
        case AstTokenKind.DIV => Some(ExprKind.DIV)
        case AstTokenKind.MOD => Some(ExprKind.MOD)
        case AstTokenKind.LT => Some(ExprKind.LT)
        case AstTokenKind.LE => Some(ExprKind.LE)
        case AstTokenKind.GT => Some(ExprKind.GT)
        case AstTokenKind.GE => Some(ExprKind.GE)
        case AstTokenKind.EQUAL => Some(ExprKind.EQUAL)
        case AstTokenKind.NOTEQ => Some(ExprKind.NOTEQUAL)
        case AstTokenKind.AND => Some(ExprKind.AND)
        case AstTokenKind.OR => Some(ExprKind.OR)
        case _ => None
    }
}

private func RealASTUnaryOp(op: AstTokenKind): Option<ExprKind> {
    return match (op) {
        case AstTokenKind.SUB => Some(ExprKind.NEG)
        case AstTokenKind.NOT => Some(ExprKind.NOT)
        case _ => None
    }
}

private func RealASTReturnType(
    context: CHIRContext,
    body: AstFuncBody,
    lowered: RealASTBodyLowering
): Option<Type> {
    if (let Some(retType) <- body.retType) {
        if (IsRealASTInt64Type(retType)) {
            return Some(context.GetInt64Ty())
        }
        if (IsRealASTBoolType(retType)) {
            return Some(context.GetBoolTy())
        }
        if (IsRealASTUnitType(retType)) {
            return Some(context.GetUnitTy())
        }
        return None
    }
    if (lowered.returnKind == REAL_AST_RETURN_INT || lowered.returnKind == REAL_AST_RETURN_BOOL) {
        return None
    }
    return Some(context.GetUnitTy())
}

private func RealASTParamType(context: CHIRContext, ty: AstType): Option<Type> {
    if (IsRealASTInt64Type(ty)) {
        return Some(context.GetInt64Ty())
    }
    if (IsRealASTBoolType(ty)) {
        return Some(context.GetBoolTy())
    }
    return None
}

private func RealASTValueTypeKind(ty: AstType): Option<Int64> {
    if (IsRealASTInt64Type(ty)) {
        return Some(REAL_AST_RETURN_INT)
    }
    if (IsRealASTBoolType(ty)) {
        return Some(REAL_AST_RETURN_BOOL)
    }
    return None
}

private func RealASTLocalTypeKind(ty: AstType): Option<Int64> {
    if (let Some(kind) <- RealASTValueTypeKind(ty)) {
        return Some(kind)
    }
    if (IsRealASTStringType(ty)) {
        return Some(REAL_AST_RETURN_STRING)
    }
    return None
}

private func IsRealASTInt64Type(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "Int64" || name == "Int"
}

private func IsRealASTBoolType(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "Bool"
}

private func IsRealASTUnitType(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "Unit" || name == "()"
}

private func IsRealASTStringType(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "String" || name == "CString"
}

private func ParseRealASTIntLiteral(lit: AstLitConstExpr): Option<Int64> {
    if (lit.kind != AstLitConstKind.INTEGER) {
        return None
    }
    let text = StripIntegerSuffix(lit.stringValue.replace("_", ""))
    try {
        return Some(Int64.parse(text))
    } catch (e: Exception) {
        return None
    }
}

private func ParseRealASTBoolLiteral(lit: AstLitConstExpr): Option<Bool> {
    if (lit.kind != AstLitConstKind.BOOL) {
        return None
    }
    let text = lit.stringValue.trimAscii()
    if (text == "true") {
        return Some(true)
    }
    if (text == "false") {
        return Some(false)
    }
    return None
}

private func PlainRealASTStringLiteralValue(expr: AstExpr): Option<String> {
    if (let Some(lit) <- (expr as AstLitConstExpr)) {
        if (lit.kind != AstLitConstKind.STRING || lit.siExpr.isSome()) {
            return None
        }
        let text = lit.stringValue
        var idx: Int64 = 0
        while (idx < text.size) {
            if (text[idx] == b'\\') {
                return None
            }
            idx++
        }
        return Some(text)
    }
    return None
}

private func StripIntegerSuffix(value: String): String {
    if (value.endsWith("i64") || value.endsWith("u64") ||
        value.endsWith("i32") || value.endsWith("u32") ||
        value.endsWith("i16") || value.endsWith("u16")) {
        return value[0..value.size - 3]
    }
    if (value.endsWith("i8") || value.endsWith("u8")) {
        return value[0..value.size - 2]
    }
    return value
}

private func RealASTDisplayName(decl: AstDecl): String {
    if ((decl as AstMainDecl).isSome()) {
        return "main"
    }
    if (!decl.identifier.Empty()) {
        return decl.identifier.Val()
    }
    return RealASTStableMangledName("", decl)
}

private func RealASTStableMangledName(packageName: String, decl: AstDecl): String {
    if (!decl.mangledName.isEmpty()) {
        return decl.mangledName
    }
    let identifier = if (decl.identifier.Empty()) {
        "decl_" + decl.begin.line.toString() + "_" + decl.begin.column.toString()
    } else {
        decl.identifier.Val()
    }
    return "_C" + (packageName + "." + identifier).replace(".", "_").replace("::", "_")
}
