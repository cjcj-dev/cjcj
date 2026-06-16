package cangjie_compiler::sema.Desugar

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let COMPOSITION_FUNC_NAME: String = "composition"
private let CALL_OPERATOR_NAME: String = "()"
private let SUBSCRIPT_OPERATOR_NAME: String = "[]"
private let VARIADIC_VALUE_NAME: String = "value"

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

private func GetCompoundAssignBaseOp(op: TokenKind): TokenKind {
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

private func FilterAliasTypeArgs(args: ArrayList<Type>): ArrayList<Type> {
    let out = ArrayList<Type>()
    for (arg in args) {
        if (let Some(argTy) <- arg.GetTy()) {
            if (let Some(intersectionTy) <- (argTy as IntersectionTy)) {
                if (intersectionTy.tys.isEmpty()) {
                    continue
                }
            }
        }
        out.add(arg)
    }
    return out
}

private func FirstTypeArgOrInvalid(baseArgs: ArrayList<Type>): Ty {
    if (!baseArgs.isEmpty()) {
        if (let Some(ty) <- baseArgs[0].GetTy()) {
            return ty
        }
    }
    return TypeManager.GetInvalidTy()
}

private func GetBuiltinCtorBaseTy(typeManager: TypeManager, callExpr: CallExpr): Option<Ty> {
    if (let Some(baseFunc) <- callExpr.baseFunc) {
        if (let Some(baseTy) <- baseFunc.GetTy()) {
            return typeManager.SubstituteTypeAliasInTy(baseTy)
        }
    }
    return None
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
    basePtr: Expr): Option<Expr> {
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
            }
            let binaryExpr = BinaryExpr()
            CopyBasicInfo(ae, binaryExpr)
            binaryExpr.leftExpr = clonedCall
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

public func DesugarOperatorOverloadExpr(expr: BinaryExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(right) <- expr.rightExpr) {
            let callExpr = CallExpr()
            CopyBasicInfo(expr, callExpr)
            let callBase = CreateOperatorMemberAccess(expr, left, TokenKindLiteral(expr.op), expr.operatorPos)
            callExpr.baseFunc = callBase
            let arg = FuncArg()
            CopyBasicInfo(right, arg)
            arg.expr = right
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

public func DesugarOperatorOverloadExpr(expr: SubscriptExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(baseExpr) <- expr.baseExpr) {
        let callExpr = CallExpr()
        CopyBasicInfo(expr, callExpr)
        let callBase = CreateOperatorMemberAccess(expr, baseExpr, SUBSCRIPT_OPERATOR_NAME, expr.leftParenPos)
        callExpr.baseFunc = callBase
        MoveSubscriptIndicesIntoArgs(callExpr, expr)
        callExpr.sourceExpr = expr
        CopyUnsafeAttr(expr, callExpr)
        AddCurFile(callExpr, file: expr.curFile)
        expr.desugarExpr = callExpr
    }
}

public func DesugarSubscriptOverloadExpr(expr: AssignExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftValue) {
        if (let Some(subscript) <- (left as SubscriptExpr)) {
            if (let Some(baseExpr) <- subscript.baseExpr) {
                let basePtr = baseExpr
                let callExpr = CallExpr()
                CopyBasicInfo(expr, callExpr)
                let callBase = CreateOperatorMemberAccess(expr, baseExpr, SUBSCRIPT_OPERATOR_NAME, subscript.leftParenPos)
                if (expr.isCompound) {
                    baseExpr.mapExpr = basePtr
                }
                callExpr.baseFunc = callBase
                callExpr.sourceExpr = expr
                MoveSubscriptIndicesIntoArgs(callExpr, subscript, preserveMapExpr: expr.isCompound)
                let valueArg = FuncArg()
                valueArg.name = SrcIdentifier(VARIADIC_VALUE_NAME)
                let valueExpr = if (expr.isCompound) {
                    CreateArgumentForCompoundAssignOverload(expr, callExpr, basePtr)
                } else {
                    expr.rightExpr
                }
                if (let Some(actualValue) <- valueExpr) {
                    CopyBasicInfo(actualValue, valueArg)
                    valueArg.expr = actualValue
                    callExpr.args.add(valueArg)
                    CopyUnsafeAttr(expr, callExpr)
                    if (expr.isCompound) {
                        callExpr.EnableAttr(Attribute.SIDE_EFFECT)
                    }
                    AddCurFile(callExpr, file: expr.curFile)
                    expr.desugarExpr = callExpr
                }
            }
        }
    }
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
        expr.args.clear()
        CopyUnsafeAttr(expr, callExpr)
        AddCurFile(callExpr, file: expr.curFile)
        expr.desugarExpr = callExpr
    }
}

public func DesugarPointerCall(typeManager: TypeManager, expr: CallExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(baseFunc) <- expr.baseFunc) {
        if (let Some(baseFuncTy) <- GetBuiltinCtorBaseTy(typeManager, expr)) {
            let typeNode = Type()
            let typeArgs = baseFuncTy.typeArgs
            let baseArgs = FilterAliasTypeArgs(baseFunc.GetTypeArgs())
            let usefulTypeArg = !typeArgs.isEmpty() && (!typeArgs[0].IsGeneric() || !baseArgs.isEmpty())
            let argTy = if (usefulTypeArg) { typeArgs[0] } else { FirstTypeArgOrInvalid(baseArgs) }
            typeNode.SetTy(typeManager.GetPointerTy(argTy))

            let pointerExpr = PointerExpr()
            pointerExpr.typeNode = typeNode
            if (!expr.args.isEmpty()) {
                pointerExpr.arg = expr.args[0]
            }
            expr.args.clear()
            pointerExpr.scopeName = expr.scopeName
            pointerExpr.sourceExpr = expr
            pointerExpr.begin = expr.begin
            pointerExpr.end = expr.end
            AddCurFile(pointerExpr, file: expr.curFile)
            expr.desugarExpr = pointerExpr
        }
    }
}

public func DesugarArrayCall(typeManager: TypeManager, expr: CallExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(baseFunc) <- expr.baseFunc) {
        if (let Some(baseFuncTy) <- GetBuiltinCtorBaseTy(typeManager, expr)) {
            let typeNode = Type()
            let typeArgs = typeManager.GetTypeArgs(baseFuncTy)
            let baseArgs = FilterAliasTypeArgs(baseFunc.GetTypeArgs())
            if (let Some(varrayTy) <- (baseFuncTy as VArrayTy)) {
                var argTy = if (!typeArgs.isEmpty()) { typeArgs[0] } else { TypeManager.GetInvalidTy() }
                if (!typeArgs.isEmpty() && typeArgs[0].IsGeneric() && !baseArgs.isEmpty()) {
                    argTy = FirstTypeArgOrInvalid(baseArgs)
                }
                typeNode.SetTy(typeManager.GetVArrayTy(argTy, varrayTy.size))
            } else {
                let usefulTypeArg = !typeArgs.isEmpty() && (!typeArgs[0].IsGeneric() || !baseArgs.isEmpty())
                let argTy = if (usefulTypeArg) { typeArgs[0] } else { FirstTypeArgOrInvalid(baseArgs) }
                typeNode.SetTy(typeManager.GetArrayTy(argTy, 1u64))
            }
            let arrayExpr = ArrayExpr()
            arrayExpr.typeNode = typeNode
            if (let Some(_) <- (baseFuncTy as VArrayTy)) {
                arrayExpr.isValueArray = true
            }
            MoveArgsInto(arrayExpr.args, expr.args)
            arrayExpr.scopeName = expr.scopeName
            arrayExpr.sourceExpr = expr
            arrayExpr.begin = expr.begin
            arrayExpr.end = expr.end
            AddCurFile(arrayExpr, file: expr.curFile)
            expr.desugarExpr = arrayExpr
        }
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

public func SelfhostPortStatus_Desugar_DesugarInTypeCheck(): Bool {
    return false
}
