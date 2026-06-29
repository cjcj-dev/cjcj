package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::sema.*

private let STATIC_INIT_VAR_NAME: String = "$init"
private let STATIC_INIT_FUNC_NAME: String = "static.init"

private func IsExplicitUnitReturn(body: FuncBody): Bool {
    if (let Some(retType) <- body.retType) {
        if (let Some(retTy) <- retType.GetTy()) {
            return retTy.IsUnit()
        }
    }
    return false
}

private func UnwrapParen(node: Node): Node {
    var current = node
    while (let Some(paren) <- (current as ParenExpr)) {
        if (let Some(expr) <- paren.expr) {
            current = expr
        } else {
            break
        }
    }
    return current
}

private func ShouldInsertReturnUnit(body: FuncBody): Bool {
    if (let None <- body.body) {
        return false
    }
    let block = body.body.getOrThrow()
    if (block.body.isEmpty()) {
        return true
    }
    let last = block.body[block.body.size - 1]
    if (last.IsDecl()) {
        return true
    }
    if (let Some(funcDecl) <- body.funcDecl) {
        if (funcDecl.TestAnyAttr(Attribute.PRIMARY_CONSTRUCTOR, Attribute.CONSTRUCTOR)) {
            return true
        }
    }
    if (IsExplicitUnitReturn(body)) {
        let unwrapped = UnwrapParen(last)
        if (unwrapped.astKind == ASTKind.RETURN_EXPR) {
            return false
        }
        if (let Some(lit) <- (unwrapped as LitConstExpr)) {
            if (lit.kind == LitConstKind.UNIT) {
                return false
            }
        }
        return true
    }
    return false
}

private func InsertUnitForFuncBody(body: FuncBody, enableCoverage: Bool): Unit {
    if (let None <- body.body) {
        return
    }
    let block = body.body.getOrThrow()
    let unitExpr = CreateUnitExpr(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
    unitExpr.curFile = body.curFile
    let ret = CreateReturnExpr(unitExpr, body)
    ret.curFile = body.curFile
    ret.SetTy(TypeManager.GetNothingTy())
    let notHaveRightCurlPos = if (let Some(_) <- body.funcDecl) { block.rightCurlPos.IsZero() } else { false }
    if (enableCoverage) {
        if (let Some(funcDecl) <- body.funcDecl) {
            ret.begin = funcDecl.begin
        } else {
            ret.begin = block.leftCurlPos
        }
    } else if (notHaveRightCurlPos) {
        if (let Some(funcDecl) <- body.funcDecl) {
            ret.begin = funcDecl.end
        } else {
            ret.begin = block.rightCurlPos
        }
    } else {
        ret.begin = block.rightCurlPos
    }
    block.body.add(ret)
}

private func MakeLastNodeReturn(funcBody: FuncBody): Unit {
    if (let None <- funcBody.body) {
        return
    }
    let block = funcBody.body.getOrThrow()
    if (block.body.isEmpty()) {
        return
    }
    let lastIndex = block.body.size - 1
    let lastNode = block.body[lastIndex]
    if (lastNode.astKind == ASTKind.RETURN_EXPR) {
        return
    }
    if (let Some(lastExpr) <- (lastNode as Expr)) {
        let ret = CreateReturnExpr(lastExpr, funcBody)
        CopyBasicInfo(lastExpr, ret)
        ret.SetTy(TypeManager.GetNothingTy())
        block.SetTy(TypeManager.GetNothingTy())
        AddCurFile(ret, file: funcBody.curFile)
        block.body[lastIndex] = ret
    }
}

private func AddReturnExprForFuncBody(body: FuncBody, enableCoverage: Bool): Unit {
    if (ShouldInsertReturnUnit(body)) {
        InsertUnitForFuncBody(body, enableCoverage)
        return
    }
    if (Ty.IsTyCorrect(body.GetTy())) {
        MakeLastNodeReturn(body)
    }
}

private func InsertStaticInitCall(decl: InheritableDecl, staticInit: FuncDecl): Unit {
    if (staticInit.TestAttr(Attribute.FROM_COMMON_PART)) {
        return
    }
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    let args = ArrayList<FuncArg>()
    let initializer = CreateCallExpr(CreateRefExpr(staticInit), args, staticInit, unitTy, CallKind.CALL_DECLARED_FUNCTION)
    initializer.begin = decl.begin
    let initVar = CreateVarDecl(STATIC_INIT_VAR_NAME, initializer, None)
    initVar.fullPackageName = decl.fullPackageName
    initVar.outerDecl = decl
    initVar.EnableAttr(Attribute.STATIC)
    initVar.EnableAttr(Attribute.PRIVATE)
    initVar.toBeCompiled = staticInit.toBeCompiled
    if (decl.IsClassLikeDecl()) {
        initVar.EnableAttr(Attribute.IN_CLASSLIKE)
    } else {
        initVar.EnableAttr(Attribute.IN_STRUCT)
    }
    AddCurFile(initVar, file: decl.curFile)
    decl.GetMemberDecls().add(initVar)
}

private func AddStaticInitForTypeDecl(decl: InheritableDecl): Unit {
    var staticInitBody: Option<FuncBody> = None
    for (member in decl.GetMemberDecls()) {
        if (!member.TestAttr(Attribute.STATIC)) {
            continue
        }
        if (member.astKind == ASTKind.FUNC_DECL && member.TestAttr(Attribute.CONSTRUCTOR)) {
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                staticInitBody = funcDecl.funcBody
            }
        }
    }
    if (let Some(body) <- staticInitBody) {
        if (let Some(funcDecl) <- body.funcDecl) {
            funcDecl.identifier = SrcIdentifier(STATIC_INIT_FUNC_NAME)
            InsertStaticInitCall(decl, funcDecl)
        }
    }
}

private func CloneAnnotationInto(source: ArrayList<Annotation>, target: ArrayList<Annotation>): Unit {
    for (annotation in source) {
        if (let Some(cloned) <- (ASTCloner.Clone(annotation) as Annotation)) {
            target.add(cloned)
        }
    }
}

private func CopyNecessaryAnnoForPropDecl(propDecl: PropDecl): Unit {
    let hasFrozen = propDecl.HasAnno(AstAnnotationKind.FROZEN)
    for (getter in propDecl.getters) {
        CloneAnnotationInto(propDecl.annotations, getter.annotations)
        getter.isFrozen = hasFrozen
    }
    for (setter in propDecl.setters) {
        CloneAnnotationInto(propDecl.annotations, setter.annotations)
        setter.isFrozen = hasFrozen
    }
}

public func DesugarDeclsForPackage(pkg: Package, enableCoverage: Bool): Unit {
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(decl) <- (node as InheritableDecl)) {
            if (node.astKind == ASTKind.CLASS_DECL || node.astKind == ASTKind.STRUCT_DECL) {
                AddStaticInitForTypeDecl(decl)
            }
        } else if (let Some(funcBody) <- (node as FuncBody)) {
            AddReturnExprForFuncBody(funcBody, enableCoverage)
        } else if (let Some(propDecl) <- (node as PropDecl)) {
            CopyNecessaryAnnoForPropDecl(propDecl)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}
