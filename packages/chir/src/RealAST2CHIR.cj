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
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.TokenKind as AstTokenKind

private let REAL_AST_RETURN_NONE: Int64 = 0
private let REAL_AST_RETURN_INT: Int64 = 1
private let REAL_AST_RETURN_BOOL: Int64 = 2
private let REAL_AST_RETURN_UNIT: Int64 = 3

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

private class RealASTLoweringScope {
    let locals = HashMap<String, Bool>()

    init(body: AstFuncBody) {
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                let name = param.identifier.Val()
                if (!name.isEmpty()) {
                    locals[name] = false
                }
            }
        }
    }

    func Contains(name: String): Bool {
        return locals.contains(name)
    }

    func Add(name: String, mutable: Bool): Bool {
        if (locals.contains(name)) {
            return false
        }
        locals[name] = mutable
        return true
    }

    func CanAssign(name: String): Bool {
        return locals.get(name) ?? false
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
            if (let Some(fnSpec) <- BuildRealASTFunctionSpec(pkg.fullPackageName, decl, context, fileName)) {
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

private func BuildRealASTFunctionSpec(
    packageName: String,
    decl: AstDecl,
    context: CHIRContext,
    sourceFileKey: String
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
    let lowered = LowerRealASTBody(body)
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

private func LowerRealASTBody(body: AstFuncBody): RealASTBodyLowering {
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
    var returnKind = REAL_AST_RETURN_NONE
    for (node in block.body) {
        let lowered = match (LowerRealASTBodyNode(node, scope)) {
            case Some(value) => value
            case None => return RealASTBodyLowering(false, empty, REAL_AST_RETURN_NONE)
        }
        stmts.add(lowered.stmt)
        if (lowered.returnKind != REAL_AST_RETURN_NONE) {
            returnKind = lowered.returnKind
        }
    }
    return RealASTBodyLowering(true, stmts, returnKind)
}

private func LowerRealASTBodyNode(node: AstNode, scope: RealASTLoweringScope): Option<RealASTStmtLowering> {
    if (let Some(varDecl) <- (node as AstVarDecl)) {
        return LowerRealASTVarDecl(varDecl, scope)
    }
    if (let Some(assign) <- (node as AstAssignExpr)) {
        return LowerRealASTAssign(assign, scope)
    }
    if (let Some(ret) <- (node as AstReturnExpr)) {
        return LowerRealASTReturn(ret, scope)
    }
    return None
}

private func RealASTStmtAndKind(stmt: AST2CHIRStmtSpec, kind: Int64): RealASTStmtLowering {
    return RealASTStmtLowering(stmt, kind)
}

private func LowerRealASTVarDecl(varDecl: AstVarDecl, scope: RealASTLoweringScope): Option<RealASTStmtLowering> {
    if (varDecl.isConst) {
        return None
    }
    if (let Some(typeNode) <- varDecl.typeNode) {
        if (!IsRealASTInt64Type(typeNode) && !IsRealASTBoolType(typeNode)) {
            return None
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
    let exprSpec = match (LowerRealASTExpr(initExpr, scope)) {
        case Some(value) => value
        case None => return None
    }
    if (!scope.Add(name, varDecl.isVar)) {
        return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Let(name, exprSpec, isVar: varDecl.isVar),
        REAL_AST_RETURN_NONE))
}

private func LowerRealASTAssign(assign: AstAssignExpr, scope: RealASTLoweringScope): Option<RealASTStmtLowering> {
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
    let exprSpec = match (LowerRealASTExpr(right, scope)) {
        case Some(value) => value
        case None => return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Assign(name, exprSpec), REAL_AST_RETURN_NONE))
}

private func LowerRealASTReturn(ret: AstReturnExpr, scope: RealASTLoweringScope): Option<RealASTStmtLowering> {
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
        let exprSpec = match (LowerRealASTExpr(expr, scope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Return(exprSpec), REAL_AST_RETURN_INT))
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.ReturnNone(), REAL_AST_RETURN_UNIT))
}

private func LowerRealASTExpr(expr: AstExpr, scope: RealASTLoweringScope): Option<AST2CHIRExprSpec> {
    if (let Some(parenExpr) <- (expr as AstParenExpr)) {
        if (let Some(inner) <- parenExpr.expr) {
            return LowerRealASTExpr(inner, scope)
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
        let lhsSpec = match (LowerRealASTExpr(lhs, scope)) {
            case Some(value) => value
            case None => return None
        }
        let rhsSpec = match (LowerRealASTExpr(rhs, scope)) {
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
        let operandSpec = match (LowerRealASTExpr(operand, scope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(AST2CHIRExprSpec.Unary(op, operandSpec))
    }
    return None
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
