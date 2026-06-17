package cangjie_compiler::ast

import std.collection.*

private var tmpVarIndex: UInt64 = 1u64

public func CopyNodeScopeInfo(ret: Option<Node>, source: Option<Node>): Unit {
    if (let Some(target) <- ret) {
        if (let Some(value) <- source) {
            target.curFile = value.curFile
            target.scopeName = value.scopeName
            target.scopeLevel = value.scopeLevel
        }
    }
}

public func CopyFileID(ret: Option<Node>, source: Option<Node>): Unit {
    if (let Some(target) <- ret) {
        if (let Some(value) <- source) {
            target.begin.fileID = value.begin.fileID
            target.end.fileID = value.end.fileID
        }
    }
}

public func CopyNodeWithFileID(ret: Option<Node>, source: Option<Node>): Unit {
    CopyNodeScopeInfo(ret, source)
    CopyFileID(ret, source)
}

private func markCompilerAdd(node: Node): Unit {
    node.EnableAttr(Attribute.COMPILER_ADD)
}

private func markImplicitCompilerAdd(node: Node): Unit {
    node.EnableAttr(Attribute.COMPILER_ADD)
    node.EnableAttr(Attribute.IMPLICIT_ADD)
}

private func cloneTypeNode(node: Option<Type>): Option<Type> {
    if (let Some(value) <- node) {
        return ASTCloner.Clone(value) as Type
    }
    return None
}

private func cloneExprNode(node: Option<Expr>): Option<Expr> {
    if (let Some(value) <- node) {
        return ASTCloner.Clone(value) as Expr
    }
    return None
}

private func cloneFuncParam(node: FuncParam): FuncParam {
    if (let Some(value) <- (ASTCloner.Clone(node) as FuncParam)) {
        return value
    }
    return FuncParam()
}

private func cloneTypeArgInto(target: ArrayList<Type>, source: ArrayList<Type>): Unit {
    for (arg in source) {
        if (let Some(cloned) <- (ASTCloner.Clone(arg) as Type)) {
            target.add(cloned)
        }
    }
}

private func attachBlockAsDesugar(expr: Expr): Expr {
    if (expr.astKind == ASTKind.BLOCK) {
        let refExpr = CreateRefExpr("$dummy")
        if (let Some(ty) <- expr.GetTy()) {
            refExpr.SetTy(ty)
        }
        refExpr.desugarExpr = expr
        return refExpr
    }
    return expr
}

private func setTyIfCorrect(node: Node, ty: Option<Ty>): Unit {
    if (Ty.IsTyCorrect(ty)) {
        if (let Some(value) <- ty) {
            node.SetTy(value)
        }
    }
}

private func splitQualifiedName(name: String): ArrayList<String> {
    let out = ArrayList<String>()
    var part = ""
    for (byte in name.toArray()) {
        if (byte == b'.') {
            out.add(part)
            part = ""
        } else {
            part += String.fromUtf8([byte])
        }
    }
    out.add(part)
    return out
}

private func makeReferenceType(name: String, args: ArrayList<Type>): RefType {
    let refType = RefType()
    refType.ref.identifier = SrcIdentifier(name)
    cloneTypeArgInto(refType.typeArguments, args)
    markCompilerAdd(refType)
    return refType
}

public func CreateUnitExpr(): Expr {
    let ret = LitConstExpr()
    ret.kind = LitConstKind.UNIT
    ret.stringValue = "()"
    markCompilerAdd(ret)
    return ret
}

public func CreateUnitExpr(ty: Ty): Expr {
    let ret = CreateUnitExpr()
    ret.SetTy(ty)
    return ret
}

public func CreateBoolLit(isTrue: Bool): LitConstExpr {
    let ret = LitConstExpr()
    ret.kind = LitConstKind.BOOL
    ret.stringValue = if (isTrue) { "true" } else { "false" }
    ret.constNumValue.asBoolean = isTrue
    markCompilerAdd(ret)
    return ret
}

public func CreateForInExpr(pattern: Pattern, inExpression: Expr, body: Block): ForInExpr {
    let ret = ForInExpr()
    ret.pattern = pattern
    ret.inExpression = inExpression
    ret.body = body
    markCompilerAdd(ret)
    return ret
}

public func CreateBreakExpr(refLoop: Expr): JumpExpr {
    let ret = JumpExpr()
    ret.isBreak = true
    ret.refLoop = refLoop
    markCompilerAdd(ret)
    return ret
}

public func CreateUnaryExpr(expr: Expr, op: TokenKind): UnaryExpr {
    let ret = UnaryExpr()
    ret.expr = expr
    ret.op = op
    if (let Some(ty) <- expr.GetTy()) {
        ret.SetTy(ty)
    }
    CopyNodeScopeInfo(ret, expr)
    markCompilerAdd(ret)
    return ret
}

public func CreateBinaryExpr(leftExpr: Expr, rightExpr: Expr, op: TokenKind): BinaryExpr {
    let ret = BinaryExpr()
    ret.leftExpr = leftExpr
    ret.rightExpr = rightExpr
    ret.op = op
    if (let Some(ty) <- leftExpr.GetTy()) {
        ret.SetTy(ty)
    }
    CopyNodeScopeInfo(ret, leftExpr)
    markCompilerAdd(ret)
    return ret
}

public func CreateAssignExpr(leftValue: Expr, rightExpr: Expr): AssignExpr {
    return CreateAssignExpr(leftValue, rightExpr, None)
}

public func CreateAssignExpr(leftValue: Expr, rightExpr: Expr, ty: Option<Ty>): AssignExpr {
    let ret = AssignExpr()
    ret.leftValue = leftValue
    ret.rightExpr = rightExpr
    ret.op = TokenKind.ASSIGN
    setTyIfCorrect(ret, ty)
    CopyNodeScopeInfo(ret, leftValue)
    markCompilerAdd(ret)
    return ret
}

public func CreateFuncArg(expr: Expr): FuncArg {
    return CreateFuncArg(expr, "", None)
}

public func CreateFuncArg(expr: Expr, argName: String): FuncArg {
    return CreateFuncArg(expr, argName, None)
}

public func CreateFuncArg(expr: Expr, argName: String, ty: Option<Ty>): FuncArg {
    let ret = FuncArg()
    CopyBasicInfo(expr, ret)
    ret.expr = attachBlockAsDesugar(expr)
    ret.name = SrcIdentifier(argName)
    if (Ty.IsTyCorrect(ty)) {
        if (let Some(value) <- ty) {
            ret.SetTy(value)
        }
    } else if (let Some(value) <- expr.GetTy()) {
        ret.SetTy(value)
    }
    markCompilerAdd(ret)
    return ret
}

public func CreateFuncArgForOptional(param: FuncParam): FuncArg {
    let ret = FuncArg()
    ret.name = param.identifier
    ret.begin = param.begin
    ret.end = param.end
    ret.expr = cloneExprNode(param.assignment)
    if (let Some(ty) <- param.GetTy()) {
        ret.SetTy(ty)
    }
    CopyNodeScopeInfo(ret, param)
    markCompilerAdd(ret)
    return ret
}

public func CreateFuncParamForOptional(param: FuncParam): FuncParam {
    let ret = FuncParam()
    ret.identifier = param.identifier
    ret.begin = param.begin
    ret.end = param.end
    ret.typeNode = cloneTypeNode(param.typeNode)
    ret.assignment = cloneExprNode(param.assignment)
    if (let Some(ty) <- param.GetTy()) {
        ret.SetTy(ty)
    }
    CopyNodeScopeInfo(ret, param)
    markCompilerAdd(ret)
    return ret
}

public func CreateFuncParamList(params: ArrayList<FuncParam>): FuncParamList {
    let ret = FuncParamList()
    for (param in params) {
        let cloned = cloneFuncParam(param)
        CopyNodeScopeInfo(ret, cloned)
        ret.params.add(cloned)
    }
    markCompilerAdd(ret)
    return ret
}

public func CreateRefTypeInCore(name: String): RefType {
    let ret = CreateRefType(name)
    ret.EnableAttr(Attribute.IN_CORE)
    return ret
}

public func CreateTmpVarDecl(): VarDecl {
    return CreateTmpVarDecl(None, None)
}

public func CreateTmpVarDecl(typeNode: Option<Type>, initializer: Option<Expr>): VarDecl {
    let name = "$tmp${tmpVarIndex}"
    tmpVarIndex++
    return CreateVarDecl(name, cloneExprNode(initializer), cloneTypeNode(typeNode))
}

public func CreateVarPattern(varName: String): VarPattern {
    return CreateVarPattern(varName, None)
}

public func CreateVarPattern(varName: String, ty: Option<Ty>): VarPattern {
    let ret = VarPattern()
    let decl = VarDecl()
    decl.identifier = SrcIdentifier(varName)
    decl.parentPattern = ret
    markImplicitCompilerAdd(decl)
    if (Ty.IsTyCorrect(ty)) {
        if (let Some(value) <- ty) {
            ret.SetTy(value)
            decl.SetTy(value)
        }
    }
    ret.varDecl = decl
    markCompilerAdd(ret)
    return ret
}

public func CreateRefExpr(name: String): RefExpr {
    return CreateRefExpr(name, INVALID_POSITION)
}

public func CreateRefExpr(name: String, pos: Position): RefExpr {
    return CreateRefExpr(SrcIdentifier(name, pos, pos, false), None, pos, ArrayList<Type>())
}

public func CreateRefExpr(id: SrcIdentifier, ty: Option<Ty>, pos: Position, args: ArrayList<Type>): RefExpr {
    let ret = RefExpr()
    ret.ref.identifier = id
    ret.begin = pos
    ret.end = pos
    if (!id.IsRaw()) {
        ret.isThis = id == "this"
        ret.isSuper = id == "super"
    }
    cloneTypeArgInto(ret.typeArguments, args)
    setTyIfCorrect(ret, ty)
    markCompilerAdd(ret)
    return ret
}

public func CreateRefExprInCore(name: String): RefExpr {
    let ret = CreateRefExpr(name)
    ret.EnableAttr(Attribute.IN_CORE)
    return ret
}

public func CreateRefExprInAST(name: String): RefExpr {
    let ret = CreateRefExpr(name)
    ret.EnableAttr(Attribute.IN_MACRO)
    return ret
}

public func CreateRefExpr(decl: Decl): RefExpr {
    let ret = RefExpr()
    ret.ref.identifier = decl.identifier
    ret.ref.target = decl
    if (let Some(ty) <- decl.GetTy()) {
        ret.SetTy(ty)
    }
    markCompilerAdd(ret)
    return ret
}

public func CreateRefExpr(decl: Decl, pos: Node): RefExpr {
    let ret = RefExpr()
    ret.ref.identifier = SrcIdentifier(decl.identifier.Val(), pos.begin, pos.end, decl.identifier.IsRaw())
    ret.ref.target = decl
    ret.begin = pos.begin
    ret.end = pos.end
    if (let Some(ty) <- decl.GetTy()) {
        ret.SetTy(ty)
    }
    markCompilerAdd(ret)
    return ret
}

public func CreateRefType(name: String): RefType {
    return makeReferenceType(name, ArrayList<Type>())
}

public func CreateRefType(name: String, args: ArrayList<Type>): RefType {
    return makeReferenceType(name, args)
}

public func CreateRefType(typeDecl: InheritableDecl): RefType {
    return CreateRefType(typeDecl, typeDecl.GetTy())
}

public func CreateRefType(typeDecl: InheritableDecl, instantTy: Option<Ty>): RefType {
    let ret = RefType()
    ret.ref.identifier = typeDecl.identifier
    ret.ref.target = typeDecl
    setTyIfCorrect(ret, instantTy)
    markCompilerAdd(ret)
    return ret
}

public func CreateRefType(name: String, begin: Position, end: Position): RefType {
    let ret = CreateRefType(name)
    ret.ref.identifier.SetPos(begin, end)
    ret.begin = begin
    ret.end = end
    return ret
}

public func CreateMemberAccess(expr: Expr, field: String): MemberAccess {
    let ret = MemberAccess()
    ret.field = SrcIdentifier(field)
    ret.baseExpr = attachBlockAsDesugar(expr)
    if (let Some(base) <- ret.baseExpr) {
        CopyBasicInfo(base, ret)
        if (let Some(baseTy) <- base.GetTy()) {
            if (let Some(classTy) <- (baseTy as ClassTy)) {
                if (let Some(classDecl) <- classTy.decl) {
                    setMemberTargetFromClassHierarchy(ret, classDecl, field)
                }
            } else if (let Some(structTy) <- (baseTy as StructTy)) {
                if (let Some(structDecl) <- structTy.decl) {
                    setMemberTargetFromDecls(ret, structDecl.GetMemberDeclPtrs(), field)
                }
            } else if (let Some(interfaceTy) <- (baseTy as InterfaceTy)) {
                if (let Some(interfaceDecl) <- interfaceTy.decl) {
                    setMemberTargetFromDecls(ret, interfaceDecl.GetMemberDeclPtrs(), field)
                }
            } else if (let Some(enumTy) <- (baseTy as EnumTy)) {
                if (let Some(enumDecl) <- enumTy.decl) {
                    setMemberTargetFromDecls(ret, enumDecl.GetMemberDeclPtrs(), field)
                }
            }
        }
    }
    markCompilerAdd(ret)
    return ret
}

private func setMemberTargetFromDecls(memberAccess: MemberAccess, decls: ArrayList<Decl>, field: String): Bool {
    for (decl in decls) {
        if (decl.identifier == field) {
            memberAccess.target = decl
            if (let Some(ty) <- decl.GetTy()) {
                memberAccess.SetTy(ty)
            }
            return true
        }
    }
    return false
}

private func setMemberTargetFromClassHierarchy(memberAccess: MemberAccess, classDecl: ClassDecl, field: String): Unit {
    var current: Option<ClassDecl> = classDecl
    while (let Some(currentClass) <- current) {
        let found = setMemberTargetFromDecls(memberAccess, currentClass.GetMemberDeclPtrs(), field)
        if (found || !Ty.IsInitialTy(memberAccess.GetTy())) {
            return
        }
        current = currentClass.GetSuperClassDecl()
    }
}

public func CreateMemberAccess(expr: Expr, field: Decl): MemberAccess {
    let ret = MemberAccess()
    ret.baseExpr = attachBlockAsDesugar(expr)
    ret.field = SrcIdentifier(field.identifier.Val(), field.identifier.Begin(), field.identifier.End(), field.identifier.IsRaw())
    ret.target = field
    if (let Some(ty) <- field.GetTy()) {
        ret.SetTy(ty)
        ret.isExposedAccess = ty.HasGeneric()
    }
    markCompilerAdd(ret)
    return ret
}

public func CreateConstraintForFFI(upperBound: String): GenericConstraint {
    let ret = GenericConstraint()
    let refType = RefType()
    refType.ref.identifier = SrcIdentifier("T")
    ret.refType = refType
    ret.begin = DEFAULT_POSITION
    ret.end = DEFAULT_POSITION
    let ctype = RefType()
    ctype.ref.identifier = SrcIdentifier(upperBound)
    ret.upperBounds.add(ctype)
    return ret
}

public func CreateMatchCase(pattern: Pattern, expr: Expr): MatchCase {
    let ret = MatchCase()
    ret.patterns.add(pattern)
    if (let Some(ty) <- expr.GetTy()) {
        ret.SetTy(ty)
    }
    let caseBlock = Block()
    caseBlock.body.add(expr)
    if (let Some(ty) <- expr.GetTy()) {
        caseBlock.SetTy(ty)
    }
    markCompilerAdd(caseBlock)
    ret.exprOrDecls = caseBlock
    markCompilerAdd(ret)
    return ret
}

public func CreateMatchExpr(selector: Expr, matchCases: ArrayList<MatchCase>, ty: Ty): MatchExpr {
    return CreateMatchExpr(selector, matchCases, ty, SugarKind.NO_SUGAR)
}

public func CreateMatchExpr(selector: Expr, matchCases: ArrayList<MatchCase>, ty: Ty, sugarKind: SugarKind): MatchExpr {
    let ret = MatchExpr()
    ret.matchMode = true
    ret.selector = selector
    for (item in matchCases) {
        ret.matchCases.add(item)
    }
    ret.sugarKind = sugarKind
    ret.SetTy(ty)
    markCompilerAdd(ret)
    return ret
}

public func CreateLitConstExpr(kind: LitConstKind, value: String): LitConstExpr {
    let ret = LitConstExpr(kind, value)
    InitializeLitConstValue(ret)
    return ret
}

public func CreateLitConstExpr(kind: LitConstKind, value: String, ty: Ty): LitConstExpr {
    return CreateLitConstExpr(kind, value, ty, false)
}

public func CreateLitConstExpr(kind: LitConstKind, value: String, ty: Ty, needToMakeRef: Bool): LitConstExpr {
    let ret = LitConstExpr(kind, value)
    ret.SetTy(ty)
    InitializeLitConstValue(ret)
    if (needToMakeRef) {
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(decl) <- classTy.decl) {
                ret.ref = CreateRefType(decl)
            }
        } else if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(decl) <- structTy.decl) {
                ret.ref = CreateRefType(decl)
            }
        } else if (let Some(enumTy) <- (ty as EnumTy)) {
            if (let Some(decl) <- enumTy.decl) {
                ret.ref = CreateRefType(decl)
            }
        }
    }
    return ret
}

public func CreateTupleLit(elements: ArrayList<Expr>, ty: Ty): TupleLit {
    let ret = TupleLit()
    for (element in elements) {
        ret.children.add(element)
    }
    ret.SetTy(ty)
    return ret
}

public func CreateArrayLit(elements: ArrayList<Expr>, ty: Ty): ArrayLit {
    let ret = ArrayLit()
    for (element in elements) {
        ret.children.add(element)
    }
    ret.SetTy(ty)
    return ret
}

public func CreateCallExpr(funcExpr: Expr, args: ArrayList<FuncArg>): CallExpr {
    return CreateCallExpr(funcExpr, args, None, None, CallKind.CALL_INVALID)
}

public func CreateCallExpr(funcExpr: Expr, args: ArrayList<FuncArg>, resolvedFunc: Option<FuncDecl>,
    ty: Option<Ty>, callTy: CallKind): CallExpr {
    let ret = CallExpr()
    if (let Some(member) <- (funcExpr as MemberAccess)) {
        member.callOrPattern = ret
    }
    if (let Some(refExpr) <- (funcExpr as RefExpr)) {
        refExpr.callOrPattern = ret
    }
    ret.baseFunc = funcExpr
    for (arg in args) {
        ret.args.add(arg)
    }
    ret.callKind = callTy
    setTyIfCorrect(ret, ty)
    CopyBasicInfo(funcExpr, ret)
    if (let Some(funcDecl) <- resolvedFunc) {
        ret.resolvedFunction = funcDecl
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            if (let Some(callTyValue) <- ret.GetTy()) {
                if (let Some(_) <- (callTyValue as StructTy)) {
                    ret.callKind = CallKind.CALL_STRUCT_CREATION
                } else if (let Some(_) <- (callTyValue as ClassTy)) {
                    ret.callKind = CallKind.CALL_OBJECT_CREATION
                }
            }
        }
        if (ret.callKind == CallKind.CALL_INVALID) {
            ret.callKind = CallKind.CALL_DECLARED_FUNCTION
        }
    }
    markCompilerAdd(ret)
    return ret
}

public func CreateLambdaExpr(funcBody: FuncBody): LambdaExpr {
    let ret = LambdaExpr(funcBody)
    if (let Some(ty) <- funcBody.GetTy()) {
        ret.SetTy(ty)
    }
    return ret
}

public func CreateFuncParamList(params: ArrayList<FuncParam>, ty: Option<Ty>): FuncParamList {
    let ret = FuncParamList()
    for (param in params) {
        ret.params.add(param)
    }
    setTyIfCorrect(ret, ty)
    return ret
}

public func CreateFuncParam(paramName: String): FuncParam {
    return CreateFuncParam(paramName, None, None, None)
}

public func CreateFuncParam(paramName: String, paramType: Option<Type>, paramValue: Option<Expr>, ty: Option<Ty>): FuncParam {
    let ret = FuncParam()
    ret.identifier = SrcIdentifier(paramName)
    ret.typeNode = paramType
    ret.assignment = paramValue
    if (let Some(value) <- paramValue) {
        CopyNodeScopeInfo(ret, value)
    }
    if (Ty.IsTyCorrect(ty)) {
        if (let Some(value) <- ty) {
            ret.SetTy(value)
        }
    } else if (let Some(typeNode) <- paramType) {
        if (let Some(value) <- typeNode.GetTy()) {
            ret.SetTy(value)
        }
    }
    markCompilerAdd(ret)
    return ret
}

public func CreateFuncBody(paramLists: ArrayList<FuncParamList>, retType: Option<Type>, body: Option<Block>,
    ty: Option<Ty>): FuncBody {
    let ret = FuncBody()
    for (params in paramLists) {
        ret.paramLists.add(params)
    }
    ret.retType = retType
    ret.body = body
    if (let Some(bodyValue) <- body) {
        CopyNodeScopeInfo(ret, bodyValue)
    }
    setTyIfCorrect(ret, ty)
    markCompilerAdd(ret)
    return ret
}

public func CreateFuncDecl(funcName: String): FuncDecl {
    return CreateFuncDecl(funcName, None, None)
}

public func CreateFuncDecl(funcName: String, body: Option<FuncBody>, ty: Option<Ty>): FuncDecl {
    let ret = FuncDecl()
    ret.identifier = SrcIdentifier(funcName)
    ret.funcBody = body
    setTyIfCorrect(ret, ty)
    if (!Ty.IsTyCorrect(ty)) {
        if (let Some(funcBody) <- ret.funcBody) {
            funcBody.funcDecl = ret
            CopyNodeScopeInfo(ret, funcBody)
            if (let Some(bodyTy) <- funcBody.GetTy()) {
                ret.SetTy(bodyTy)
            }
        }
    }
    ret.toBeCompiled = true
    markCompilerAdd(ret)
    return ret
}

public func CreateBlock(nodes: ArrayList<Node>): Block {
    return CreateBlock(nodes, None)
}

public func CreateBlock(nodes: ArrayList<Node>, ty: Option<Ty>): Block {
    let ret = Block()
    for (node in nodes) {
        if (node.IsDecl() || node.IsExpr()) {
            ret.body.add(node)
        }
    }
    setTyIfCorrect(ret, ty)
    markCompilerAdd(ret)
    return ret
}

public func CreateIfExpr(condExpr: Expr, body: Block): IfExpr {
    return CreateIfExpr(condExpr, body, None, None)
}

public func CreateIfExpr(condExpr: Expr, body: Block, elseBody: Option<Block>, semaType: Option<Ty>): IfExpr {
    let ret = IfExpr()
    ret.condExpr = condExpr
    ret.thenBody = body
    if (let Some(elseBlock) <- elseBody) {
        ret.elseBody = elseBlock
    }
    setTyIfCorrect(ret, semaType)
    if (!Ty.IsTyCorrect(semaType)) {
        if (let Some(elseValue) <- elseBody) {
            if (let Some(thenTy) <- body.GetTy()) {
                if (let Some(otherTy) <- elseValue.GetTy()) {
                    if (thenTy.Hash() == otherTy.Hash()) {
                        ret.SetTy(thenTy)
                    }
                }
            }
        }
    }
    ret.hasElse = if (let Some(_) <- elseBody) { true } else { false }
    markCompilerAdd(ret)
    return ret
}

public func CreateVarDecl(varName: String): VarDecl {
    return CreateVarDecl(varName, None, None)
}

public func CreateVarDecl(varName: String, initializer: Option<Expr>, typeNode: Option<Type>): VarDecl {
    let ret = VarDecl()
    ret.identifier = SrcIdentifier(varName)
    ret.typeNode = cloneTypeNode(typeNode)
    ret.initializer = initializer
    if (let Some(initExpr) <- initializer) {
        if (let Some(ty) <- initExpr.GetTy()) {
            ret.SetTy(ty)
        }
        CopyNodeScopeInfo(ret, initExpr)
    }
    ret.toBeCompiled = true
    markImplicitCompilerAdd(ret)
    return ret
}

public func CreateTupleAccess(expr: Expr, index: UInt64): SubscriptExpr {
    let ret = SubscriptExpr()
    ret.isTupleAccess = true
    ret.baseExpr = expr
    let lit = LitConstExpr(LitConstKind.INTEGER, "${index}")
    lit.constNumValue.asInt.SetUint64(index)
    ret.indexExprs.add(lit)
    if (let Some(exprTy) <- expr.GetTy()) {
        if (let Some(tupleTy) <- (exprTy as TupleTy)) {
            if (index < UInt64(tupleTy.typeArgs.size)) {
                ret.SetTy(tupleTy.typeArgs[Int64(index)])
            }
        }
    }
    return ret
}

public func CreateReturnExpr(expr: Expr): ReturnExpr {
    return CreateReturnExpr(expr, None)
}

public func CreateReturnExpr(expr: Expr, refFuncBody: Option<FuncBody>): ReturnExpr {
    let ret = ReturnExpr()
    ret.expr = expr
    ret.refFuncBody = refFuncBody
    CopyNodeScopeInfo(ret, expr)
    markCompilerAdd(ret)
    return ret
}

public func CreateThrowExpr(decl: Decl): ThrowExpr {
    let ret = ThrowExpr()
    ret.expr = CreateRefExpr(decl)
    return ret
}

public func CreatePerformExpr(decl: Decl): PerformExpr {
    let ret = PerformExpr()
    ret.expr = CreateRefExpr(decl)
    return ret
}

public func CreateResumeExpr(decl: Decl): ResumeExpr {
    let ret = ResumeExpr()
    ret.withExpr = CreateRefExpr(decl)
    return ret
}

public func CreateTypePattern(pattern: Pattern, typeNode: Type, selector: Expr): TypePattern {
    let ret = TypePattern()
    ret.ctxExpr = selector
    ret.pattern = pattern
    ret.typeNode = typeNode
    if (let Some(ty) <- typeNode.GetTy()) {
        pattern.SetTy(ty)
        ret.SetTy(ty)
    }
    ret.curFile = selector.curFile
    markCompilerAdd(ret)
    return ret
}

public func CreateImportSpec(fullPackageName: String): ImportSpec {
    return CreateImportSpec(fullPackageName, "*", "")
}

public func CreateImportSpec(fullPackageName: String, item: String, alias: String): ImportSpec {
    let ret = ImportSpec()
    let names = splitQualifiedName(fullPackageName)
    if (!alias.isEmpty()) {
        ret.content.kind = ImportKind.IMPORT_ALIAS
    } else if (item != "*") {
        ret.content.kind = ImportKind.IMPORT_SINGLE
    } else {
        ret.content.kind = ImportKind.IMPORT_ALL
    }
    for (name in names) {
        if (!name.isEmpty()) {
            ret.content.prefixPaths.add(name)
        }
    }
    ret.content.identifier = Identifier(item, DEFAULT_POSITION, DEFAULT_POSITION)
    ret.content.aliasName = Identifier(alias, DEFAULT_POSITION, DEFAULT_POSITION)
    markImplicitCompilerAdd(ret)
    ret.EnableAttr(Attribute.PRIVATE)
    return ret
}

public func CreatePackage(name: String): Package {
    return Package(name)
}

public func CreateFile(path: String): File {
    let file = File()
    file.filePath = path
    file.fileName = path
    return file
}
