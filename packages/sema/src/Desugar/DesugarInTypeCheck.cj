package cjcj::sema.Desugar

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind

private let COMPOSITION_FUNC_NAME: String = "composition"
private let CALL_OPERATOR_NAME: String = "()"
private let SUBSCRIPT_OPERATOR_NAME: String = "[]"
private let VARIADIC_VALUE_NAME: String = "value"
private let INIT_FUNC_NAME: String = "init"
private let THIS_NAME: String = "this"

private func TryDesugarFunctionCallExpr(base: Expr): Expr {
    if (!Ty.IsInitialTy(base.GetTy()) && base.TyKind() != TypeKind.TYPE_FUNC) {
        let memberAccess = CreateMemberAccess(base, CALL_OPERATOR_NAME)
        memberAccess.scopeName = base.scopeName
        memberAccess.scopeLevel = base.scopeLevel
        memberAccess.begin = base.begin
        memberAccess.end = base.end
        return memberAccess
    }
    return base
}

private func CopyUnsafeAttr(source: Expr, target: Expr): Unit {
    if (source.TestAttr(Attribute.UNSAFE)) {
        target.EnableAttr(Attribute.UNSAFE)
    }
}

private func SetFieldPosition(field: SrcIdentifier, begin: Position, width: Int64): Unit {
    field.SetPos(begin, begin + width)
}

public func GetCompoundAssignBaseOp(op: TokenKind): TokenKind {
    return match (op) {
        case TokenKind.ADD_ASSIGN => TokenKind.ADD
        case TokenKind.SUB_ASSIGN => TokenKind.SUB
        case TokenKind.MUL_ASSIGN => TokenKind.MUL
        case TokenKind.EXP_ASSIGN => TokenKind.EXP
        case TokenKind.DIV_ASSIGN => TokenKind.DIV
        case TokenKind.MOD_ASSIGN => TokenKind.MOD
        case TokenKind.AND_ASSIGN => TokenKind.AND
        case TokenKind.OR_ASSIGN => TokenKind.OR
        case TokenKind.BITAND_ASSIGN => TokenKind.BITAND
        case TokenKind.BITOR_ASSIGN => TokenKind.BITOR
        case TokenKind.BITXOR_ASSIGN => TokenKind.BITXOR
        case TokenKind.LSHIFT_ASSIGN => TokenKind.LSHIFT
        case TokenKind.RSHIFT_ASSIGN => TokenKind.RSHIFT
        case _ => TokenKind.ILLEGAL
    }
}

private func IsCompoundAssignOp(op: TokenKind): Bool {
    return GetCompoundAssignBaseOp(op) != TokenKind.ILLEGAL
}

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

private func CloneType(typeNode: Type): Option<Type> {
    return ASTCloner.Clone(typeNode, SetIsClonedSourceCode) as Type
}

private func CloneExprAsSource(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr, SetIsClonedSourceCode) as Expr
}

private func CloneAnnotationAsSource(annotation: Annotation): Option<Annotation> {
    return ASTCloner.Clone(annotation, SetIsClonedSourceCode) as Annotation
}

private func CloneNodeAsSource(node: Node): Option<Node> {
    return ASTCloner.Clone(node, SetIsClonedSourceCode)
}

private func CloneTypeOptionAsSource(typeNode: Option<Type>): Option<Type> {
    if (let Some(value) <- typeNode) {
        return CloneType(value)
    }
    return None
}

private func CloneExprOptionAsSource(expr: Option<Expr>): Option<Expr> {
    if (let Some(value) <- expr) {
        return CloneExprAsSource(value)
    }
    return None
}

private func CloneAnnotationOption(annotationArray: Option<ArrayLit>): Option<ArrayLit> {
    if (let Some(value) <- annotationArray) {
        return ASTCloner.Clone(value, SetIsClonedSourceCode) as ArrayLit
    }
    return None
}

private func CloneSrcIdentifier(source: SrcIdentifier): SrcIdentifier {
    return SrcIdentifier(source.Val(), source.Begin(), source.End(), source.IsRaw())
}

private func CreateOperatorMemberAccess(source: Node, base: Expr, fieldName: String, pos: Position): MemberAccess {
    let memberAccess = MemberAccess()
    CopyBasicInfo(source, memberAccess)
    memberAccess.baseExpr = base
    memberAccess.field = SrcIdentifier(fieldName)
    SetFieldPosition(memberAccess.field, pos, fieldName.size)
    return memberAccess
}

private func MoveArgsInto(target: ArrayList<FuncArg>, source: ArrayList<FuncArg>): Unit {
    for (arg in source) {
        target.add(arg)
    }
    source.clear()
}

private func AppendDeclToClassOrStructBody(decl: Decl, member: Decl): Unit {
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        if (let Some(body) <- classDecl.body) {
            body.decls.add(member)
        }
    } else if (let Some(structDecl) <- (decl as StructDecl)) {
        if (let Some(body) <- structDecl.body) {
            body.decls.add(member)
        }
    }
}

private func CopyModifiersInto(source: ArrayList<Modifier>, target: ArrayList<Modifier>): Unit {
    for (modifier in source) {
        if (let Some(cloned) <- (ASTCloner.Clone(modifier, SetIsClonedSourceCode) as Modifier)) {
            target.add(cloned)
        }
    }
}

private func CopyParamAnnotationsInto(source: FuncParam, target: FuncParam): Unit {
    for (annotation in source.annotations) {
        if (annotation.kind == AstAnnotationKind.DEPRECATED || annotation.kind == AstAnnotationKind.CUSTOM) {
            if (let Some(cloned) <- CloneAnnotationAsSource(annotation)) {
                target.annotations.add(cloned)
            }
        }
    }
}

private func MoveAnnotationsInto(source: ArrayList<Annotation>, target: ArrayList<Annotation>): Unit {
    for (annotation in source) {
        target.add(annotation)
    }
    source.clear()
}

private func IsLeadingSuperCall(node: Node): Bool {
    if (let Some(callExpr) <- (node as CallExpr)) {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            if (let Some(refExpr) <- (baseFunc as RefExpr)) {
                return refExpr.isSuper
            }
        }
    }
    return false
}

private func DesugarPrimaryCtorHandleSuper(decl: Decl, sourceBody: FuncBody, targetBody: FuncBody): Int64 {
    if (decl.astKind != ASTKind.CLASS_DECL) {
        return 0
    }
    if (let Some(block) <- sourceBody.body) {
        if (!block.body.isEmpty() && IsLeadingSuperCall(block.body[0])) {
            if (let Some(cloned) <- CloneNodeAsSource(block.body[0])) {
                targetBody.body.getOrThrow().body.add(cloned)
                return 1
            }
        }
    }
    return 0
}

private func CreatePrimaryCtorMemberDecl(decl: Decl, ctor: PrimaryCtorDecl, param: FuncParam): VarDecl {
    let member = VarDecl()
    CopyBasicInfo(param, member)
    for (annotation in param.annotations) {
        if (let Some(cloned) <- CloneAnnotationAsSource(annotation)) {
            member.annotations.add(cloned)
        }
    }
    member.annotationsArray = CloneAnnotationOption(param.annotationsArray)
    member.isVar = param.isVar
    member.isConst = param.isConst
    CopyModifiersInto(param.modifiers, member.modifiers)
    member.CloneAttrs(param)
    member.keywordPos = param.begin
    member.colonPos = param.colonPos
    member.typeNode = CloneTypeOptionAsSource(param.typeNode)
    member.identifier = CloneSrcIdentifier(param.identifier)
    member.isMemberParam = true
    member.rawMangleName = param.rawMangleName
    member.toBeCompiled = ctor.toBeCompiled
    member.outerDecl = decl
    member.EnableAttr(Attribute.COMPILER_ADD)
    member.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
    return member
}

private func CreatePrimaryCtorMemberAssign(ctor: PrimaryCtorDecl, param: FuncParam): AssignExpr {
    let thisExpr = CreateRefExpr(THIS_NAME)
    thisExpr.isThis = true
    thisExpr.EnableAttr(Attribute.IMPLICIT_ADD)
    CopyBasicInfo(param, thisExpr)
    if (let Some(funcBody) <- ctor.funcBody) {
        thisExpr.ref.identifier.SetFileID(funcBody.begin.fileID)
    }

    let left = CreateMemberAccess(thisExpr, param.identifier.Val())
    left.field = CloneSrcIdentifier(param.identifier)
    left.EnableAttr(Attribute.IMPLICIT_ADD)
    CopyBasicInfo(param, left)

    let right = CreateRefExpr(param.identifier.Val())
    right.ref.identifier = CloneSrcIdentifier(param.identifier)
    right.EnableAttr(Attribute.IMPLICIT_ADD)
    if (let Some(typeNode) <- param.typeNode) {
        CopyBasicInfo(typeNode, right)
    } else {
        CopyBasicInfo(param, right)
    }
    right.sourceExpr = left
    if (let Some(funcBody) <- ctor.funcBody) {
        right.ref.identifier.SetFileID(funcBody.begin.fileID)
    }

    let assignment = AssignExpr()
    CopyBasicInfo(param, assignment)
    assignment.EnableAttr(Attribute.COMPILER_ADD)
    assignment.leftValue = left
    assignment.rightExpr = right
    assignment.op = TokenKind.ASSIGN
    return assignment
}

private func DesugarPrimaryCtorHandleParamSetEachParam(
    decl: Decl, ctor: PrimaryCtorDecl, targetBody: FuncBody): Unit {
    if (let Some(sourceBody) <- ctor.funcBody) {
        if (sourceBody.paramLists.isEmpty()) {
            return
        }
        for (param in sourceBody.paramLists[0].params) {
            if (!param.isMemberParam || param.TestAttr(Attribute.STATIC)) {
                continue
            }
            let member = CreatePrimaryCtorMemberDecl(decl, ctor, param)
            AppendDeclToClassOrStructBody(decl, member)
            if (let Some(block) <- targetBody.body) {
                block.body.add(CreatePrimaryCtorMemberAssign(ctor, param))
            }
        }
    }
}

private func DesugarPrimaryCtorHandleParam(
    decl: Decl, ctor: PrimaryCtorDecl, targetBody: FuncBody, targetParamList: FuncParamList): Unit {
    if (let Some(sourceBody) <- ctor.funcBody) {
        if (sourceBody.paramLists.isEmpty()) {
            return
        }
        let sourceParamList = sourceBody.paramLists[0]
        CopyBasicInfo(sourceParamList, targetParamList)
        for (param in sourceParamList.params) {
            let clonedParam = CreateFuncParam(
                param.identifier.Val(), CloneTypeOptionAsSource(param.typeNode),
                CloneExprOptionAsSource(param.assignment), param.GetTy())
            clonedParam.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
            param.EnableAttr(Attribute.COMPILER_ADD)
            CopyBasicInfo(param, clonedParam)
            clonedParam.identifier.SetPos(param.identifier.Begin(), param.identifier.End())
            clonedParam.identifier.SetRaw(param.identifier.IsRaw())
            clonedParam.isNamedParam = param.isNamedParam
            clonedParam.isMemberParam = param.isMemberParam
            CopyParamAnnotationsInto(param, clonedParam)
            targetParamList.params.add(clonedParam)
        }
        DesugarPrimaryCtorHandleParamSetEachParam(decl, ctor, targetBody)
    }
}

private func DesugarPrimaryCtorSetPrimaryFunc(decl: Decl, ctor: PrimaryCtorDecl, targetBody: FuncBody): Unit {
    let primaryFunc = FuncDecl()
    CopyBasicInfo(ctor, primaryFunc)
    primaryFunc.toBeCompiled = ctor.toBeCompiled
    primaryFunc.funcBody = targetBody
    targetBody.funcDecl = primaryFunc
    primaryFunc.identifier = SrcIdentifier(INIT_FUNC_NAME, ctor.identifier.Begin(), ctor.identifier.End(), false)
    primaryFunc.identifierForLsp = ctor.identifier.Val()
    CopyModifiersInto(ctor.modifiers, primaryFunc.modifiers)
    primaryFunc.constructorCall = ConstructorCall.NONE
    primaryFunc.CloneAttrs(ctor)
    primaryFunc.EnableAttr(Attribute.COMPILER_ADD)
    primaryFunc.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
    primaryFunc.EnableAttr(Attribute.CONSTRUCTOR)
    primaryFunc.EnableAttr(Attribute.PRIMARY_CONSTRUCTOR)
    MoveAnnotationsInto(ctor.annotations, primaryFunc.annotations)
    primaryFunc.overflowStrategy = ctor.overflowStrategy
    primaryFunc.isFastNative = ctor.isFastNative
    primaryFunc.isConst = ctor.isConst
    primaryFunc.isFrozen = primaryFunc.HasAnno(AstAnnotationKind.FROZEN)
    primaryFunc.rawMangleName = ctor.rawMangleName
    primaryFunc.moduleName = ctor.moduleName
    primaryFunc.fullPackageName = ctor.fullPackageName
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        targetBody.parentClassLike = classDecl
        primaryFunc.outerDecl = classDecl
        primaryFunc.EnableAttr(Attribute.IN_CLASSLIKE)
        if (let Some(body) <- classDecl.body) {
            body.decls.add(primaryFunc)
        }
    } else if (let Some(structDecl) <- (decl as StructDecl)) {
        targetBody.parentStruct = structDecl
        primaryFunc.outerDecl = structDecl
        primaryFunc.EnableAttr(Attribute.IN_STRUCT)
        if (let Some(body) <- structDecl.body) {
            body.decls.add(primaryFunc)
        }
    }
}

private func MoveSubscriptIndicesIntoArgs(callExpr: CallExpr, subscript: SubscriptExpr,
    preserveMapExpr!: Bool = false): Unit {
    for (indexExpr in subscript.indexExprs) {
        let arg = FuncArg()
        CopyBasicInfo(indexExpr, arg)
        arg.expr = indexExpr
        if (preserveMapExpr) {
            indexExpr.mapExpr = indexExpr
        }
        arg.scopeName = indexExpr.scopeName
        callExpr.args.add(arg)
    }
    subscript.indexExprs.clear()
}

private func CreateArgumentForCompoundAssignOverload(ae: AssignExpr, createdCall: CallExpr,
    basePtr: Expr, indexPtrs: ArrayList<Expr>): Option<Expr> {
    if (let Some(right) <- ae.rightExpr) {
        if (let Some(clonedCall) <- CloneExpr(createdCall)) {
            if (let Some(clonedCallExpr) <- (clonedCall as CallExpr)) {
                if (let Some(baseFunc) <- clonedCallExpr.baseFunc) {
                    if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                        if (let Some(baseExpr) <- memberAccess.baseExpr) {
                            baseExpr.mapExpr = basePtr
                        }
                    }
                }
                var idx: Int64 = 0
                while (idx < indexPtrs.size) {
                    clonedCallExpr.args[idx].expr.getOrThrow().mapExpr = indexPtrs[idx]
                    idx++
                }
            }
            let binaryExpr = BinaryExpr()
            CopyBasicInfo(ae, binaryExpr)
            binaryExpr.leftExpr = clonedCall
            binaryExpr.leftExpr.getOrThrow().sourceExpr = ae
            binaryExpr.rightExpr = right
            binaryExpr.op = GetCompoundAssignBaseOp(ae.op)
            binaryExpr.operatorPos = ae.assignPos
            return binaryExpr
        }
    }
    return None
}

private func DesugarPipelineExpr(expr: BinaryExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(right) <- expr.rightExpr) {
            let callExpr = CallExpr()
            CopyBasicInfo(expr, callExpr)
            callExpr.baseFunc = TryDesugarFunctionCallExpr(right)
            let funcArg = FuncArg()
            CopyBasicInfo(left, funcArg)
            funcArg.expr = left
            callExpr.args.add(funcArg)
            callExpr.sourceExpr = expr
            CopyUnsafeAttr(expr, callExpr)
            AddCurFile(callExpr, file: expr.curFile)
            expr.desugarExpr = callExpr
        }
    }
}

private func MakeFlowFuncArg(source: Expr): FuncArg {
    let arg = FuncArg()
    CopyBasicInfo(source, arg)
    let callee = TryDesugarFunctionCallExpr(source)
    callee.isInFlowExpr = true
    arg.expr = callee
    return arg
}

private func DesugarCompositionExpr(expr: BinaryExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(right) <- expr.rightExpr) {
            let callExpr = CallExpr()
            CopyBasicInfo(expr, callExpr)
            let baseFunc = CreateRefExprInCore(COMPOSITION_FUNC_NAME)
            CopyBasicInfo(expr, baseFunc)
            callExpr.baseFunc = baseFunc
            callExpr.args.add(MakeFlowFuncArg(left))
            callExpr.args.add(MakeFlowFuncArg(right))
            callExpr.sourceExpr = expr
            CopyUnsafeAttr(expr, callExpr)
            AddCurFile(callExpr, file: expr.curFile)
            expr.desugarExpr = callExpr
        }
    }
}

public func DesugarOperatorOverloadExpr(expr: BinaryExpr, ctx!: Option<ASTContext> = None): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(right) <- expr.rightExpr) {
            let callExpr = CallExpr()
            CopyBasicInfo(expr, callExpr)
            if (let Some(context) <- ctx) {
                context.RemoveTypeCheckCache(callExpr)
            }
            let callBase = CreateOperatorMemberAccess(expr, left, TokenKindLiteral(expr.op), expr.operatorPos)
            if (let Some(context2) <- ctx) {
                context2.RemoveTypeCheckCache(callBase)
            }
            callExpr.baseFunc = callBase
            let arg = FuncArg()
            CopyBasicInfo(right, arg)
            if (let Some(context3) <- ctx) {
                context3.RemoveTypeCheckCache(arg)
            }
            arg.expr = right
            if (let Some(rightTy) <- right.GetTy()) {
                arg.SetTy(rightTy)
            }
            callExpr.args.add(arg)
            callExpr.sourceExpr = expr
            CopyUnsafeAttr(expr, callExpr)
            AddCurFile(callExpr, file: expr.curFile)
            expr.desugarExpr = callExpr
        }
    }
}

public func DesugarOperatorOverloadExpr(expr: UnaryExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(operand) <- expr.expr) {
        let callExpr = CallExpr()
        callExpr.sourceExpr = expr
        callExpr.begin = expr.begin
        callExpr.end = expr.end
        callExpr.baseFunc = CreateOperatorMemberAccess(expr, operand, TokenKindLiteral(expr.op), expr.operatorPos)
        CopyUnsafeAttr(expr, callExpr)
        AddCurFile(callExpr, file: expr.curFile)
        expr.desugarExpr = callExpr
    }
}

public func DesugarOperatorOverloadExpr(ctx: ASTContext, expr: SubscriptExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    let callExpr = CallExpr()
    CopyBasicInfo(expr, callExpr)
    ctx.RemoveTypeCheckCache(callExpr)
    let callBase = CreateOperatorMemberAccess(
        expr, expr.baseExpr.getOrThrow(), SUBSCRIPT_OPERATOR_NAME, expr.leftParenPos)
    ctx.RemoveTypeCheckCache(callBase)
    callExpr.baseFunc = callBase
    MoveSubscriptIndicesIntoArgs(callExpr, expr)
    for (arg in callExpr.args) {
        ctx.RemoveTypeCheckCache(arg)
    }
    callExpr.sourceExpr = expr
    CopyUnsafeAttr(expr, callExpr)
    AddCurFile(callExpr, file: expr.curFile)
    expr.desugarExpr = callExpr
}

public func DesugarSubscriptOverloadExpr(ctx: ASTContext, expr: AssignExpr): Unit {
    if (expr.leftValue.isNone() || expr.rightExpr.isNone()) {
        return
    }
    if ((expr.leftValue.getOrThrow() as SubscriptExpr).isNone()) {
        return
    }
    let subscript = (expr.leftValue.getOrThrow() as SubscriptExpr).getOrThrow()
    let basePtr = subscript.baseExpr.getOrThrow()
    let indexPtrs = ArrayList<Expr>()
    for (indexExpr in subscript.indexExprs) {
        indexPtrs.add(indexExpr)
    }
    let callExpr = CallExpr()
    CopyBasicInfo(expr, callExpr)
    ctx.RemoveTypeCheckCache(callExpr)
    let callBase = MemberAccess()
    CopyBasicInfo(expr, callBase)
    ctx.RemoveTypeCheckCache(callBase)
    callBase.baseExpr = basePtr
    if (expr.isCompound) {
        callBase.baseExpr.getOrThrow().mapExpr = basePtr
    }
    callBase.field = SrcIdentifier(SUBSCRIPT_OPERATOR_NAME)
    SetFieldPosition(callBase.field, subscript.leftParenPos, SUBSCRIPT_OPERATOR_NAME.size)
    callExpr.baseFunc = callBase
    callExpr.sourceExpr = expr
    for (idx in 0..subscript.indexExprs.size) {
        let funcArg = FuncArg()
        CopyBasicInfo(subscript.indexExprs[idx], funcArg)
        ctx.RemoveTypeCheckCache(funcArg)
        funcArg.expr = subscript.indexExprs[idx]
        if (expr.isCompound) {
            funcArg.expr.getOrThrow().mapExpr = indexPtrs[idx]
        }
        funcArg.scopeName = funcArg.expr.getOrThrow().scopeName
        callExpr.args.add(funcArg)
    }
    subscript.indexExprs.clear()
    let valueArg = FuncArg()
    ctx.RemoveTypeCheckCache(valueArg)
    valueArg.name = SrcIdentifier(VARIADIC_VALUE_NAME)
    valueArg.expr = if (expr.isCompound) {
        CreateArgumentForCompoundAssignOverload(expr, callExpr, basePtr, indexPtrs)
    } else {
        expr.rightExpr
    }
    CopyBasicInfo(valueArg.expr.getOrThrow(), valueArg)
    ctx.ClearTypeCheckCache(valueArg.expr.getOrThrow())
    callExpr.args.add(valueArg)
    CopyUnsafeAttr(expr, callExpr)
    if (expr.isCompound) {
        callExpr.EnableAttr(Attribute.SIDE_EFFECT)
    }
    expr.desugarExpr = callExpr
    AddCurFile(expr, file: expr.curFile)
}

public func DesugarOperatorOverloadExpr(expr: AssignExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (!IsCompoundAssignOp(expr.op)) {
        return
    }
    if (let Some(leftValue) <- expr.leftValue) {
        if (let Some(right) <- expr.rightExpr) {
            if (let Some(clonedLeft) <- CloneExpr(leftValue)) {
                let assignExpr = AssignExpr()
                CopyBasicInfo(expr, assignExpr)
                assignExpr.sourceExpr = expr
                assignExpr.op = TokenKind.ASSIGN
                assignExpr.leftValue = leftValue
                leftValue.mapExpr = leftValue

                let callBase = CreateOperatorMemberAccess(expr, clonedLeft,
                    TokenKindLiteral(GetCompoundAssignBaseOp(expr.op)), expr.assignPos)
                if (let Some(baseExpr) <- callBase.baseExpr) {
                    baseExpr.DisableAttr(Attribute.LEFT_VALUE)
                    baseExpr.mapExpr = leftValue
                }
                let arg = FuncArg()
                CopyBasicInfo(expr, arg)
                arg.expr = right

                let callExpr = CallExpr()
                CopyBasicInfo(expr, callExpr)
                callExpr.sourceExpr = expr
                callExpr.baseFunc = callBase
                callExpr.args.add(arg)
                CopyUnsafeAttr(expr, callExpr)
                assignExpr.rightExpr = callExpr
                assignExpr.EnableAttr(Attribute.SIDE_EFFECT)
                AddCurFile(assignExpr, file: expr.curFile)
                expr.desugarExpr = assignExpr
            }
        }
    }
}

public func DesugarCallExpr(expr: CallExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(baseFunc) <- expr.baseFunc) {
        let callExpr = CallExpr()
        callExpr.sourceExpr = expr
        callExpr.begin = expr.begin
        callExpr.end = expr.end
        let memberAccess = MemberAccess()
        memberAccess.scopeName = baseFunc.scopeName
        memberAccess.field = SrcIdentifier(CALL_OPERATOR_NAME)
        SetFieldPosition(memberAccess.field, expr.leftParenPos, CALL_OPERATOR_NAME.size)
        memberAccess.begin = baseFunc.begin
        memberAccess.end = baseFunc.end
        memberAccess.baseExpr = baseFunc
        callExpr.baseFunc = memberAccess
        MoveArgsInto(callExpr.args, expr.args)
        CopyUnsafeAttr(expr, callExpr)
        AddCurFile(callExpr, file: expr.curFile)
        expr.desugarExpr = callExpr
    }
}

public func DesugarVariadicCallExpr(expr: CallExpr, fixedPositionalArity: Int64): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(baseFunc) <- expr.baseFunc) {
        if (expr.args.size < fixedPositionalArity) {
            return
        }
        let callExpr = CallExpr()
        callExpr.callKind = expr.callKind
        expr.callKind = CallKind.CALL_VARIADIC_FUNCTION
        callExpr.sourceExpr = expr
        CopyBasicInfo(expr, callExpr)
        callExpr.baseFunc = baseFunc
        // Mirrors C++ std::move(ce.baseFunc): the original call no longer owns the moved base.
        expr.baseFunc = None

        var idx: Int64 = 0
        while (idx < fixedPositionalArity) {
            callExpr.args.add(expr.args[idx])
            idx++
        }
        let arrayLit = ArrayLit()
        CopyBasicInfo(expr, arrayLit)
        if (idx >= expr.args.size) {
            arrayLit.begin = expr.rightParenPos
            arrayLit.end = expr.rightParenPos
        } else {
            arrayLit.begin = expr.args[idx].begin
            arrayLit.end = expr.args[expr.args.size - 1].end
        }
        while (idx < expr.args.size && expr.args[idx].name.Empty()) {
            if (let Some(argExpr) <- expr.args[idx].expr) {
                arrayLit.children.add(argExpr)
            }
            idx++
        }
        callExpr.args.add(CreateFuncArg(arrayLit))
        while (idx < expr.args.size) {
            callExpr.args.add(expr.args[idx])
            idx++
        }
        // Faithful to C++ DesugarVariadicCallExpr (DesugarInTypeCheck.cpp:513): the original arguments are
        // moved into the desugared call (std::move), which preserves ce.args' SIZE. Do NOT clear here -
        // RecoverFromVariadicCallExpr (RecoverDesugar.cj:257) assigns back into ce.args[idx] by index and
        // requires those slots to still exist.
        CopyUnsafeAttr(expr, callExpr)
        AddCurFile(callExpr, file: expr.curFile)
        expr.desugarExpr = callExpr
    }
}

public func DesugarPrimaryCtor(decl: Decl, ctor: PrimaryCtorDecl): Unit {
    if (decl.astKind != ASTKind.CLASS_DECL && decl.astKind != ASTKind.STRUCT_DECL) {
        return
    }
    if (let Some(sourceBody) <- ctor.funcBody) {
        let targetBody = FuncBody()
        CopyBasicInfo(sourceBody, targetBody)
        let targetBlock = Block()
        CopyBasicInfo(sourceBody, targetBlock)
        targetBody.body = targetBlock
        targetBody.retType = CloneTypeOptionAsSource(sourceBody.retType)
        if (let Some(retType) <- targetBody.retType) {
            retType.DisableAttr(Attribute.COMPILER_ADD)
        }
        let targetParamList = FuncParamList()
        CopyFileID(targetParamList, ctor)
        var bodyStartIndex = DesugarPrimaryCtorHandleSuper(decl, sourceBody, targetBody)
        DesugarPrimaryCtorHandleParam(decl, ctor, targetBody, targetParamList)

        if (let Some(sourceBlock) <- sourceBody.body) {
            while (bodyStartIndex < sourceBlock.body.size) {
                if (let Some(cloned) <- CloneNodeAsSource(sourceBlock.body[bodyStartIndex])) {
                    targetBody.body.getOrThrow().body.add(cloned)
                }
                bodyStartIndex++
            }
        } else if (ctor.TestAttr(Attribute.COMMON)) {
            targetBody.body = None
        }
        targetBody.paramLists.add(targetParamList)
        DesugarPrimaryCtorSetPrimaryFunc(decl, ctor, targetBody)
    }
}

public func DesugarInTypeCheck(root: Node): Unit {
    let walker = Walker(root, visitPost: { node: Node =>
        if (let Some(binaryExpr) <- (node as BinaryExpr)) {
            if (binaryExpr.op == TokenKind.PIPELINE) {
                DesugarPipelineExpr(binaryExpr)
            } else if (binaryExpr.op == TokenKind.COMPOSITION) {
                DesugarCompositionExpr(binaryExpr)
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}
