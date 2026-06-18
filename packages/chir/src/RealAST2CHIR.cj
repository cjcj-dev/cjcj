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

private class RealASTBodyLowering {
    let ok: Bool
    let stmt: Option<AST2CHIRStmtSpec>
    let returnsValue: Bool

    init(ok: Bool, stmt: Option<AST2CHIRStmtSpec>, returnsValue: Bool) {
        this.ok = ok
        this.stmt = stmt
        this.returnsValue = returnsValue
    }
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
    if (!HasNoParams(body)) {
        return None
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
    let paramTypes = ArrayList<Type>()
    let kind = if (isMain) { FuncKind.MAIN_ENTRY } else { FuncKind.DEFAULT }
    let fnSpec = AST2CHIRFunctionSpec(fnName, paramTypes, returnTy, srcCodeIdentifier: srcName,
        rawMangledName: fnName, packageName: packageName, funcKind: kind, emitBody: true)
    fnSpec.EnableRealBody()
    if (let Some(stmt) <- lowered.stmt) {
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

private func HasNoParams(body: AstFuncBody): Bool {
    if (body.generic.isSome()) {
        return false
    }
    if (body.paramLists.size != 1) {
        return false
    }
    return body.paramLists[0].params.isEmpty()
}

private func LowerRealASTBody(body: AstFuncBody): RealASTBodyLowering {
    let block = match (body.body) {
        case Some(value) => value
        case None => return RealASTBodyLowering(false, None, false)
    }
    if (block.body.isEmpty()) {
        return RealASTBodyLowering(true, None, false)
    }
    if (block.body.size != 1) {
        return RealASTBodyLowering(false, None, false)
    }
    return LowerRealASTSingleBodyNode(block.body[0])
}

private func LowerRealASTSingleBodyNode(node: AstNode): RealASTBodyLowering {
    let ret = match (node as AstReturnExpr) {
        case Some(value) => value
        case None => return RealASTBodyLowering(false, None, false)
    }
    if (let Some(expr) <- ret.expr) {
        if (let Some(lit) <- (expr as AstLitConstExpr)) {
            if (let Some(value) <- ParseRealASTIntLiteral(lit)) {
                return RealASTBodyLowering(true, Some(AST2CHIRStmtSpec.Return(AST2CHIRExprSpec.Literal(value))), true)
            }
        }
        return RealASTBodyLowering(false, None, false)
    }
    return RealASTBodyLowering(true, Some(AST2CHIRStmtSpec.ReturnNone()), false)
}

private func RealASTReturnType(
    context: CHIRContext,
    body: AstFuncBody,
    lowered: RealASTBodyLowering
): Option<Type> {
    if (lowered.returnsValue) {
        if (let Some(retType) <- body.retType) {
            if (IsRealASTInt64Type(retType)) {
                return Some(context.GetInt64Ty())
            }
        }
        return None
    }
    if (let Some(retType) <- body.retType) {
        if (IsRealASTUnitType(retType)) {
            return Some(context.GetUnitTy())
        }
        return None
    }
    return Some(context.GetUnitTy())
}

private func IsRealASTInt64Type(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "Int64" || name == "Int"
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
