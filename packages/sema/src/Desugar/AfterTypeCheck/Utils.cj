package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func LookupEnumMember(decl: Option<Decl>, identifier: String): Option<Decl> {
    if (let Some(value) <- decl) {
        return LookupEnumMember(value, identifier)
    }
    return None
}

public func LookupEnumMember(decl: Decl, identifier: String): Option<Decl> {
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        for (member in enumDecl.constructors) {
            if (member.identifier.Val() == identifier) {
                return member
            }
        }
    }
    return None
}

public func UnitifyBlock(posSrc: Expr, block: Block, unitTy: Ty): Unit {
    let unitExpr = CreateUnitExpr(unitTy)
    unitExpr.begin = posSrc.begin
    unitExpr.begin.Mark(PositionStatus.IGNORE)
    unitExpr.end = posSrc.end
    block.body.add(unitExpr)
    block.SetTy(unitTy)
}

private func sameNode(left: Node, right: Node): Bool {
    return left.astKind == right.astKind && left.begin == right.begin && left.end == right.end
}

public func RearrangeRefLoop(src: Expr, dst: Expr, loopBody: Option<Node>): Unit {
    if (let Some(root) <- loopBody) {
        let walker = Walker(root, visitPre: { node: Node =>
            if (let Some(jumpExpr) <- (node as JumpExpr)) {
                if (let Some(refLoop) <- jumpExpr.refLoop) {
                    if (sameNode(refLoop, src)) {
                        jumpExpr.refLoop = dst
                    }
                }
            }
            if (node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.LAMBDA_EXPR) {
                return VisitAction.SKIP_CHILDREN
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }
}

private func CompoundAssignOp(op: TokenKind): Option<TokenKind> {
    return match (op) {
        case TokenKind.ADD_ASSIGN => Some(TokenKind.ADD)
        case TokenKind.SUB_ASSIGN => Some(TokenKind.SUB)
        case TokenKind.MUL_ASSIGN => Some(TokenKind.MUL)
        case TokenKind.EXP_ASSIGN => Some(TokenKind.EXP)
        case TokenKind.DIV_ASSIGN => Some(TokenKind.DIV)
        case TokenKind.MOD_ASSIGN => Some(TokenKind.MOD)
        case TokenKind.AND_ASSIGN => Some(TokenKind.AND)
        case TokenKind.OR_ASSIGN => Some(TokenKind.OR)
        case TokenKind.BITAND_ASSIGN => Some(TokenKind.BITAND)
        case TokenKind.BITOR_ASSIGN => Some(TokenKind.BITOR)
        case TokenKind.BITXOR_ASSIGN => Some(TokenKind.BITXOR)
        case TokenKind.LSHIFT_ASSIGN => Some(TokenKind.LSHIFT)
        case TokenKind.RSHIFT_ASSIGN => Some(TokenKind.RSHIFT)
        case _ => None
    }
}

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

private func TrySetMappedExprForProp(expr: Expr, mapExpr: Option<Expr>): Unit {
    if (let Some(callExpr) <- (expr as CallExpr)) {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            if (let Some(member) <- (baseFunc as MemberAccess)) {
                if (let Some(memberBase) <- member.baseExpr) {
                    if (let Some(_) <- memberBase.mapExpr) {
                        if (let Some(baseMember) <- (memberBase as MemberAccess)) {
                            if (let Some(baseMemberBase) <- baseMember.baseExpr) {
                                baseMemberBase.mapExpr = mapExpr
                                memberBase.mapExpr = None
                            }
                        }
                    }
                }
            }
        }
    }
}

private func CreatePropCompoundArg(typeManager: TypeManager, expr: Expr, propTy: Ty,
    mapExpr: Option<Expr>, getFunc: FuncDecl): Option<FuncArg> {
    var op = TokenKind.ADD
    var rightExpr: Option<Expr> = None
    if (let Some(assignExpr) <- (expr as AssignExpr)) {
        if (let Some(assignRight) <- assignExpr.rightExpr) {
            if (assignExpr.isCompound) {
                if (let Some(mappedOp) <- CompoundAssignOp(assignExpr.op)) {
                    op = mappedOp
                }
                rightExpr = CloneExpr(assignRight)
            } else if (let Some(clonedRight) <- CloneExpr(assignRight)) {
                TrySetMappedExprForProp(clonedRight, mapExpr)
                return Some(CreateFuncArg(clonedRight))
            }
        }
    } else if (let Some(incOrDecExpr) <- (expr as IncOrDecExpr)) {
        op = if (incOrDecExpr.op == TokenKind.INCR) { TokenKind.ADD } else { TokenKind.SUB }
        rightExpr = Some(CreateLitConstExpr(LitConstKind.INTEGER, "1", propTy))
    }
    if (let Some(rightValue) <- rightExpr) {
        var leftBaseExpr: Expr = CreateRefExpr(getFunc)
        if (let Some(mappedExpr) <- mapExpr) {
            if (let Some(clonedMapped) <- CloneExpr(mappedExpr)) {
                leftBaseExpr = CreateMemberAccess(clonedMapped, getFunc)
            } else {
                return None
            }
        }
        leftBaseExpr.SetTy(typeManager.GetFunctionTy(Array<Ty>(), propTy))
        var isMemberAccessSuperCall = false
        if (let Some(member) <- (leftBaseExpr as MemberAccess)) {
            if (let Some(baseValue) <- member.baseExpr) {
                if (let Some(refValue) <- (baseValue as RefExpr)) {
                    isMemberAccessSuperCall = refValue.isSuper
                }
                if (let Some(target) <- baseValue.GetTarget()) {
                    if (!target.IsNominalDecl()) {
                        baseValue.mapExpr = mapExpr
                    }
                } else {
                    baseValue.mapExpr = mapExpr
                }
            }
        }
        CopyBasicInfo(expr, leftBaseExpr)
        let leftExpr = CreateCallExpr(leftBaseExpr, ArrayList<FuncArg>())
        leftExpr.callKind = if (isMemberAccessSuperCall) {
            CallKind.CALL_SUPER_FUNCTION
        } else {
            CallKind.CALL_DECLARED_FUNCTION
        }
        leftExpr.resolvedFunction = getFunc
        leftExpr.SetTy(propTy)
        let binaryExpr = CreateBinaryExpr(leftExpr, rightValue, op)
        CopyBasicInfo(expr, binaryExpr)
        return Some(CreateFuncArg(binaryExpr))
    }
    return None
}

private func DesugarGetForPropDecl(typeManager: TypeManager, expr: Expr): Unit {
    if ((let Some(_) <- expr.desugarExpr) || !Ty.IsTyCorrect(expr.GetTy()) ||
        expr.TestAttr(Attribute.LEFT_VALUE) || expr.TestAttr(Attribute.UNREACHABLE) ||
        !expr.IsReferenceExpr()) {
        return
    }
    if (let Some(target) <- expr.GetTarget()) {
        if (let Some(propDecl) <- (target as PropDecl)) {
            let usedDecl = GetUsedMemberDecl(propDecl, true)
            if (let Some(getFunc) <- (usedDecl as FuncDecl)) {
                var baseExpr: Option<Expr> = None
                var isMemberAccessSuperCall = false
                if (let Some(member) <- (expr as MemberAccess)) {
                    if (let Some(memberBase) <- member.baseExpr) {
                        if (let Some(refValue) <- (memberBase as RefExpr)) {
                            isMemberAccessSuperCall = refValue.isSuper
                        }
                        if (let Some(clonedBase) <- CloneExpr(memberBase)) {
                            baseExpr = Some(CreateMemberAccess(clonedBase, getFunc))
                        }
                    }
                } else {
                    baseExpr = Some(CreateRefExpr(getFunc))
                }
                if (let Some(baseValue) <- baseExpr) {
                    if (let Some(exprTy) <- expr.GetTy()) {
                        baseValue.SetTy(typeManager.GetFunctionTy(Array<Ty>(), exprTy))
                        CopyBasicInfo(expr, baseValue)
                        let lastCall = CreateCallExpr(baseValue, ArrayList<FuncArg>())
                        lastCall.callKind = if (isMemberAccessSuperCall) {
                            CallKind.CALL_SUPER_FUNCTION
                        } else {
                            CallKind.CALL_DECLARED_FUNCTION
                        }
                        lastCall.resolvedFunction = getFunc
                        lastCall.SetTy(exprTy)
                        CopyBasicInfo(expr, lastCall)
                        AddCurFile(lastCall, file: expr.curFile)
                        expr.desugarExpr = lastCall
                    }
                }
            }
        }
    }
}

private func DesugarSetForPropDecl(typeManager: TypeManager, expr: Expr): Unit {
    if ((let Some(_) <- expr.desugarExpr) || !Ty.IsTyCorrect(expr.GetTy())) {
        return
    }
    var subExpr: Option<Expr> = None
    var isCompound = false
    if (let Some(incOrDecExpr) <- (expr as IncOrDecExpr)) {
        subExpr = incOrDecExpr.expr
        isCompound = true
    } else if (let Some(assignExpr) <- (expr as AssignExpr)) {
        subExpr = assignExpr.leftValue
        isCompound = assignExpr.isCompound || expr.TestAttr(Attribute.SIDE_EFFECT)
        expr.DisableAttr(Attribute.SIDE_EFFECT)
    }
    if (let Some(subValue) <- subExpr) {
        if (!Ty.IsTyCorrect(subValue.GetTy())) {
            return
        }
        if (let Some(target) <- subValue.GetTarget()) {
            if (let Some(propDecl) <- (target as PropDecl)) {
                if (!propDecl.isVar) {
                    return
                }
                let accessors = GetUsableGetterSetterForProperty(propDecl)
                if (let Some(getFunc) <- accessors[0]) {
                    if (let Some(setFunc) <- accessors[1]) {
                        subValue.EnableAttr(Attribute.UNREACHABLE)
                        var baseExpr: Option<Expr> = None
                        if (let Some(member) <- (subValue as MemberAccess)) {
                            if (let Some(memberBase) <- member.baseExpr) {
                                if (let Some(clonedBase) <- CloneExpr(memberBase)) {
                                    baseExpr = Some(CreateMemberAccess(clonedBase, setFunc))
                                }
                            }
                        } else {
                            baseExpr = Some(CreateRefExpr(setFunc))
                        }
                        if (let Some(baseValue) <- baseExpr) {
                            if (let Some(subTy) <- subValue.GetTy()) {
                                baseValue.SetTy(typeManager.GetFunctionTy([subTy], TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
                                CopyBasicInfo(subValue, baseValue)
                                var basePtr: Option<Expr> = None
                                var isMemberAccessSuperCall = false
                                if (let Some(memberBase) <- (baseValue as MemberAccess)) {
                                    if (let Some(memberBaseExpr) <- memberBase.baseExpr) {
                                        basePtr = Some(memberBaseExpr)
                                        if (let Some(refValue) <- (memberBaseExpr as RefExpr)) {
                                            isMemberAccessSuperCall = refValue.isSuper
                                        }
                                        if (let Some(targetValue) <- memberBaseExpr.GetTarget()) {
                                            if (!targetValue.IsNominalDecl()) {
                                                memberBaseExpr.mapExpr = basePtr
                                            }
                                        } else {
                                            memberBaseExpr.mapExpr = basePtr
                                        }
                                    }
                                }
                                if (let Some(arg) <- CreatePropCompoundArg(typeManager, expr, subTy, basePtr, getFunc)) {
                                    let args = ArrayList<FuncArg>()
                                    args.add(arg)
                                    let lastCall = CreateCallExpr(baseValue, args)
                                    CopyBasicInfo(subValue, lastCall)
                                    lastCall.callKind = if (isMemberAccessSuperCall) {
                                        CallKind.CALL_SUPER_FUNCTION
                                    } else {
                                        CallKind.CALL_DECLARED_FUNCTION
                                    }
                                    lastCall.resolvedFunction = setFunc
                                    lastCall.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
                                    AddCurFile(lastCall, file: expr.curFile)
                                    if (isCompound) {
                                        lastCall.EnableAttr(Attribute.SIDE_EFFECT)
                                    }
                                    expr.desugarExpr = lastCall
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

public func DesugarForPropDecl(typeManager: TypeManager, root: Node): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (node.TestAnyAttr(Attribute.HAS_BROKEN, Attribute.IS_BROKEN)) {
            return VisitAction.SKIP_CHILDREN
        }
        match (node.astKind) {
            case ASTKind.REF_EXPR =>
                if (let Some(expr) <- (node as Expr)) {
                    DesugarGetForPropDecl(typeManager, expr)
                }
            case ASTKind.MEMBER_ACCESS =>
                if (let Some(expr) <- (node as Expr)) {
                    DesugarGetForPropDecl(typeManager, expr)
                }
            case ASTKind.ASSIGN_EXPR =>
                if (let Some(expr) <- (node as Expr)) {
                    DesugarSetForPropDecl(typeManager, expr)
                }
            case ASTKind.INC_OR_DEC_EXPR =>
                if (let Some(expr) <- (node as Expr)) {
                    DesugarSetForPropDecl(typeManager, expr)
                }
            case _ => ()
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}
