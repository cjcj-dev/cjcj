package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class ExtendBoxMarker {
    private var typeManager: TypeManager

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
    }

    public static func MustUnboxDownCast(selectorTy: Ty, patternTy: Ty): Bool {
        return selectorTy.IsInterface() && patternTy.IsClass()
    }

    public static func GetMarkExtendBoxFunc(typeManager: TypeManager): (Node) -> VisitAction {
        let marker = ExtendBoxMarker(typeManager)
        return { node: Node => marker.Visit(node) }
    }

    public static func Mark(typeManager: TypeManager, root: Node): Unit {
        let walker = Walker(root, visitPre: ExtendBoxMarker.GetMarkExtendBoxFunc(typeManager))
        let _ = walker.Walk()
    }

    public func Visit(node: Node): VisitAction {
        if (let Some(varDecl) <- (node as VarDecl)) {
            return MarkBoxPointHandleVarDecl(varDecl)
        }
        if (let Some(assignExpr) <- (node as AssignExpr)) {
            return MarkBoxPointHandleAssignExpr(assignExpr)
        }
        if (let Some(callExpr) <- (node as CallExpr)) {
            return MarkBoxPointHandleCallExpr(callExpr)
        }
        if (let Some(ifExpr) <- (node as IfExpr)) {
            return MarkBoxPointHandleIfExpr(ifExpr)
        }
        if (let Some(returnExpr) <- (node as ReturnExpr)) {
            return MarkBoxPointHandleReturnExpr(returnExpr)
        }
        if (let Some(matchExpr) <- (node as MatchExpr)) {
            return MarkBoxPointHandleMatchExpr(matchExpr)
        }
        if (let Some(tryExpr) <- (node as TryExpr)) {
            return MarkBoxPointHandleTryExpr(tryExpr)
        }
        if (let Some(arrayExpr) <- (node as ArrayExpr)) {
            return MarkBoxPointHandleArrayExpr(arrayExpr)
        }
        if (let Some(arrayLit) <- (node as ArrayLit)) {
            return MarkBoxPointHandleArrayLit(arrayLit)
        }
        if (let Some(tupleLit) <- (node as TupleLit)) {
            return MarkBoxPointHandleTupleLit(tupleLit)
        }
        if (let Some(whileExpr) <- (node as WhileExpr)) {
            return MarkBoxPointHandleWhileExpr(whileExpr)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func NeedAutoBox(child: Option<Ty>, interfaceTy: Option<Ty>, isUpcast!: Bool = true): Bool {
        if (let Some(childTy) <- child) {
            if (let Some(targetTy) <- interfaceTy) {
                return NeedAutoBox(childTy, targetTy, isUpcast: isUpcast)
            }
        }
        return false
    }

    private func NeedAutoBox(child: Ty, interfaceTy: Ty, isUpcast!: Bool = true): Bool {
        if (child.HasInvalidTy() || interfaceTy.HasInvalidTy()) {
            return false
        }
        var target = interfaceTy
        while (CountOptionNestedLevel(child) < CountOptionNestedLevel(target) && target.typeArgs.size == 1) {
            target = target.typeArgs[0]
        }
        let isExtended = typeManager.HasExtensionRelation(child, target)
        if (isExtended && isUpcast) {
            typeManager.RecordUsedExtend(child, target)
        }
        return isExtended
    }

    private func CheckBlockNeedBox(block: Block, targetTy: Ty, nodeToCheck: Node): Unit {
        var lastTy: Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        if (let Some(lastNode) <- block.GetLastExprOrDecl()) {
            if (let Some(expr) <- (lastNode as Expr)) {
                if (let Some(exprTy) <- expr.GetTy()) {
                    lastTy = exprTy
                }
            }
        }
        if (NeedAutoBox(lastTy, targetTy)) {
            nodeToCheck.EnableAttr(Attribute.NEED_AUTO_BOX)
        }
    }

    private func MarkBoxPointHandleVarDecl(varDecl: VarDecl): VisitAction {
        if (let Some(initializer) <- varDecl.initializer) {
            if (NeedAutoBox(initializer.GetTy(), varDecl.GetTy())) {
                varDecl.EnableAttr(Attribute.NEED_AUTO_BOX)
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleAssignExpr(assignExpr: AssignExpr): VisitAction {
        if (let None <- assignExpr.desugarExpr) {
            if (let Some(right) <- assignExpr.rightExpr) {
                if (let Some(left) <- assignExpr.leftValue) {
                    if (NeedAutoBox(right.GetTy(), left.GetTy())) {
                        assignExpr.EnableAttr(Attribute.NEED_AUTO_BOX)
                    }
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleCallExpr(callExpr: CallExpr): VisitAction {
        if (let Some(base) <- callExpr.baseFunc) {
            if (let Some(baseTy) <- base.GetTy()) {
                if (let Some(funcTy) <- (baseTy as FuncTy)) {
                    checkCallArgs(callExpr, callExpr.args, funcTy)
                    return VisitAction.WALK_CHILDREN
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func checkCallArgs(callExpr: CallExpr, args: ArrayList<FuncArg>, funcTy: FuncTy): Unit {
        var count: Int64 = 0
        while (count < args.size && count < funcTy.paramTys.size) {
            if (let Some(argExpr) <- args[count].expr) {
                if (NeedAutoBox(argExpr.GetTy(), Some(funcTy.paramTys[count]))) {
                    callExpr.EnableAttr(Attribute.NEED_AUTO_BOX)
                }
            }
            count++
        }
    }

    private func MarkBoxPointHandleIfExpr(ifExpr: IfExpr): VisitAction {
        if (Ty.IsTyCorrect(ifExpr.GetTy())) {
            if (let Some(cond) <- ifExpr.condExpr) {
                if (Ty.IsTyCorrect(cond.GetTy())) {
                    MarkBoxPointHandleCondition(cond)
                }
            }
            if (let Some(ifTy) <- ifExpr.GetTy()) {
                if (!ifTy.IsUnitOrNothing()) {
                    if (let Some(thenBody) <- ifExpr.thenBody) {
                        CheckBlockNeedBox(thenBody, ifTy, ifExpr)
                    }
                    if (ifExpr.hasElse) {
                        if (let Some(elseExpr) <- ifExpr.elseBody) {
                            if (let Some(block) <- (elseExpr as Block)) {
                                CheckBlockNeedBox(block, ifTy, ifExpr)
                            } else if (NeedAutoBox(elseExpr.GetTy(), Some(ifTy))) {
                                ifExpr.EnableAttr(Attribute.NEED_AUTO_BOX)
                            }
                        }
                    }
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleWhileExpr(whileExpr: WhileExpr): VisitAction {
        if (Ty.IsTyCorrect(whileExpr.GetTy())) {
            if (let Some(cond) <- whileExpr.condExpr) {
                if (Ty.IsTyCorrect(cond.GetTy())) {
                    MarkBoxPointHandleCondition(cond)
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleCondition(expr: Expr): Unit {
        let stack = ArrayList<Expr>()
        stack.add(expr)
        while (!stack.isEmpty()) {
            let lastIndex = stack.size - 1
            let current = stack[lastIndex]
            stack.remove(at: lastIndex)
            if (!Ty.IsTyCorrect(current.GetTy())) {
                continue
            }
            if (let Some(letExpr) <- (current as LetPatternDestructor)) {
                if (let Some(initializer) <- letExpr.initializer) {
                    if (Ty.IsTyCorrect(initializer.GetTy())) {
                        for (pattern in letExpr.patterns) {
                            if (let Some(initTy) <- initializer.GetTy()) {
                                if (IsTypePatternNeedBox(pattern, initTy)) {
                                    expr.EnableAttr(Attribute.NEED_AUTO_BOX)
                                    pattern.EnableAttr(Attribute.NEED_AUTO_BOX)
                                }
                            }
                        }
                    }
                }
            }
            if (let Some(paren) <- (current as ParenExpr)) {
                if (let Some(inner) <- paren.expr) {
                    stack.add(inner)
                }
            }
            if (let Some(binary) <- (current as BinaryExpr)) {
                if (binary.op == TokenKind.AND || binary.op == TokenKind.OR) {
                    if (let Some(left) <- binary.leftExpr) {
                        stack.add(left)
                    }
                    if (let Some(right) <- binary.rightExpr) {
                        stack.add(right)
                    }
                }
            }
        }
    }

    private func MarkBoxPointHandleReturnExpr(returnExpr: ReturnExpr): VisitAction {
        if (let Some(expr) <- returnExpr.expr) {
            if (let Some(body) <- returnExpr.refFuncBody) {
                if (let Some(bodyTy) <- body.GetTy()) {
                    if (let Some(funcTy) <- (bodyTy as FuncTy)) {
                        if (NeedAutoBox(expr.GetTy(), Some(funcTy.retTy))) {
                            returnExpr.EnableAttr(Attribute.NEED_AUTO_BOX)
                        }
                    }
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleArrayLit(arrayLit: ArrayLit): VisitAction {
        if (let Some(litTy) <- arrayLit.GetTy()) {
            if (litTy.typeArgs.size == 1) {
                for (child in arrayLit.children) {
                    if (NeedAutoBox(child.GetTy(), Some(litTy.typeArgs[0]))) {
                        arrayLit.EnableAttr(Attribute.NEED_AUTO_BOX)
                    }
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleArrayExpr(arrayExpr: ArrayExpr): VisitAction {
        if (!Ty.IsTyCorrect(arrayExpr.GetTy()) || arrayExpr.args.isEmpty()) {
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(arrayTy) <- arrayExpr.GetTy()) {
            if (arrayTy.typeArgs.size == 1) {
                let elemTy = arrayTy.typeArgs[0]
                if (arrayExpr.isValueArray) {
                    if (let Some(argExpr) <- arrayExpr.args[0].expr) {
                        if (NeedAutoBox(argExpr.GetTy(), Some(elemTy))) {
                            arrayExpr.EnableAttr(Attribute.NEED_AUTO_BOX)
                        }
                    }
                } else if (let None <- arrayExpr.initFunc) {
                    if (arrayExpr.args.size > 1) {
                        if (let Some(argExpr) <- arrayExpr.args[1].expr) {
                            if (NeedAutoBox(argExpr.GetTy(), Some(elemTy))) {
                                arrayExpr.EnableAttr(Attribute.NEED_AUTO_BOX)
                            }
                        }
                    }
                } else {
                    if (let Some(argExpr) <- arrayExpr.args[0].expr) {
                        if (NeedAutoBox(argExpr.GetTy(), Some(elemTy))) {
                            arrayExpr.EnableAttr(Attribute.NEED_AUTO_BOX)
                        }
                    }
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleTupleLit(tupleLit: TupleLit): VisitAction {
        if (let Some(tupleTyValue) <- tupleLit.GetTy()) {
            if (let Some(tupleTy) <- (tupleTyValue as TupleTy)) {
                var idx: Int64 = 0
                while (idx < tupleLit.children.size && idx < tupleTy.typeArgs.size) {
                    if (NeedAutoBox(tupleLit.children[idx].GetTy(), Some(tupleTy.typeArgs[idx]))) {
                        tupleLit.EnableAttr(Attribute.NEED_AUTO_BOX)
                    }
                    idx++
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleTryExpr(tryExpr: TryExpr): VisitAction {
        if (!Ty.IsTyCorrect(tryExpr.GetTy())) {
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(tryTy) <- tryExpr.GetTy()) {
            if (let Some(tryBlock) <- tryExpr.tryBlock) {
                CheckBlockNeedBox(tryBlock, tryTy, tryExpr)
            }
            for (catchBlock in tryExpr.catchBlocks) {
                CheckBlockNeedBox(catchBlock, tryTy, tryExpr)
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func MarkBoxPointHandleMatchExpr(matchExpr: MatchExpr): VisitAction {
        if (!Ty.IsTyCorrect(matchExpr.GetTy())) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(matchTy) <- matchExpr.GetTy()) {
            for (matchCase in matchExpr.matchCases) {
                if (let Some(selector) <- matchExpr.selector) {
                    if (let Some(selectorTy) <- selector.GetTy()) {
                        for (pattern in matchCase.patterns) {
                            if (IsTypePatternNeedBox(pattern, selectorTy)) {
                                matchExpr.EnableAttr(Attribute.NEED_AUTO_BOX)
                            }
                        }
                    }
                }
                if (let Some(body) <- matchCase.exprOrDecls) {
                    CheckBlockNeedBox(body, matchTy, matchExpr)
                }
            }
            for (other in matchExpr.matchCaseOthers) {
                if (let Some(body) <- other.exprOrDecls) {
                    CheckBlockNeedBox(body, matchTy, matchExpr)
                }
            }
        }
        return VisitAction.WALK_CHILDREN
    }

    private func IsTypePatternNeedBox(pattern: Pattern, selectorTy: Ty): Bool {
        if (selectorTy.IsNothing()) {
            return false
        }
        var boxOrUnbox = false
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            if (let Some(patternTy) <- typePattern.GetTy()) {
                let needDownCastBox = NeedAutoBox(patternTy, selectorTy, isUpcast: false)
                let needUpCastBox = NeedAutoBox(selectorTy, patternTy)
                boxOrUnbox = needDownCastBox || needUpCastBox ||
                    ExtendBoxMarker.MustUnboxDownCast(selectorTy, patternTy)
            }
        } else if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            if (let Some(tupleTy) <- (selectorTy as TupleTy)) {
                var idx: Int64 = 0
                while (idx < tuplePattern.patterns.size && idx < tupleTy.typeArgs.size) {
                    if (IsTypePatternNeedBox(tuplePattern.patterns[idx], tupleTy.typeArgs[idx])) {
                        boxOrUnbox = true
                    }
                    idx++
                }
            }
        } else if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            if (let Some(constructor) <- enumPattern.constructor) {
                if (let Some(constructorTyValue) <- constructor.GetTy()) {
                    if (let Some(constructorTy) <- (constructorTyValue as FuncTy)) {
                        var idx: Int64 = 0
                        while (idx < enumPattern.patterns.size && idx < constructorTy.paramTys.size) {
                            if (IsTypePatternNeedBox(enumPattern.patterns[idx], constructorTy.paramTys[idx])) {
                                boxOrUnbox = true
                            }
                            idx++
                        }
                    }
                }
            }
        }
        return boxOrUnbox
    }
}

public func MarkExtendBox(typeManager: TypeManager, root: Node): Unit {
    ExtendBoxMarker.Mark(typeManager, root)
}

public func SelfhostPortStatus_ExtendBoxMarker(): Bool {
    return true
}
