package cangjie_compiler::sema.Desugar.AfterTypeCheck

import cangjie_compiler::ast.*

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
