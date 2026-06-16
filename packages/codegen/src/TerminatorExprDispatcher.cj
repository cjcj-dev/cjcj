package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Block
import cangjie_compiler::chir.ExprKind

public func HandleTerminatorExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let kind = chirExpr.GetExprKind()
    if (kind == ExprKind.GOTO) {
        let successors = GetTerminatorSuccessors(chirExpr)
        if (!successors.isEmpty()) {
            return irBuilder.CreateBr(GetOrCreateTerminatorDest(irBuilder, successors[0]))
        }
        return irBuilder.CreateRetVoid()
    }
    if (kind == ExprKind.BRANCH) {
        let successors = GetTerminatorSuccessors(chirExpr)
        if (chirExpr.GetNumOfOperands() > 0 && successors.size >= 2) {
            let condValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
            return irBuilder.CreateCondBr(condValue.GetRawValue(), GetOrCreateTerminatorDest(irBuilder, successors[0]),
                GetOrCreateTerminatorDest(irBuilder, successors[1]))
        }
        return LLVMNullValue()
    }
    if (kind == ExprKind.EXIT) {
        if (chirExpr.GetNumOfOperands() == 0) {
            return irBuilder.CreateRetVoid()
        }
        let retValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
        return irBuilder.CreateRet(retValue.GetRawValue())
    }
    let exceptionalSuccessors = GetTerminatorSuccessors(chirExpr)
    if (!exceptionalSuccessors.isEmpty()) {
        return irBuilder.CreateBr(GetOrCreateTerminatorDest(irBuilder, exceptionalSuccessors[0]))
    }
    return LLVMNullValue()
}

private func GetTerminatorSuccessors(chirExpr: Expression): ArrayList<Block> {
    if (let Some(term) <- chirExpr.AsTerminator()) {
        return term.GetSuccessors()
    }
    return ArrayList<Block>()
}

private func GetOrCreateTerminatorDest(irBuilder: IRBuilder2, block: Block): LLVMBasicBlockRef {
    if (let Some(dest) <- irBuilder.GetCGModule().GetMappedBB(block)) {
        return dest
    }
    if (let Some(cgFunc) <- irBuilder.GetInsertCGFunction()) {
        return irBuilder.GetCGModule().CreateOrGetMappedBB(irBuilder, cgFunc.GetRawFunction(), block)
    }
    return LLVMNullBasicBlock()
}
