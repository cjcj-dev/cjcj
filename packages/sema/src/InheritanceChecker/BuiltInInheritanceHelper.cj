package cangjie_compiler::sema.InheritanceChecker

import cangjie_compiler::ast.*
import cangjie_compiler::basic.{DiagnosticEngine, DiagKindRefactor}
import cangjie_compiler::sema.*

func IsBuiltInOperatorFuncInExtend(
    diag: DiagnosticEngine,
    typeManager: TypeManager,
    member: MemberSignature,
    structDecl: Decl
): Bool {
    if (structDecl.astKind != ASTKind.EXTEND_DECL) {
        return false
    }
    if (let Some(memberDecl) <- member.decl) {
        if (!memberDecl.IsFunc() || !Ty.IsTyCorrect(memberDecl.GetTy()) ||
            !memberDecl.TestAttr(Attribute.ABSTRACT) || !memberDecl.TestAttr(Attribute.OPERATOR)) {
            return false
        }
        if (let Some(ed) <- (structDecl as ExtendDecl)) {
            if (let Some(fd) <- (memberDecl as FuncDecl)) {
                var actualTy = member.ty
                if (let None <- actualTy) {
                    actualTy = memberDecl.GetTy()
                }
                if (let Some(funcTy) <- actualTy) {
                    if (let Some(realFuncTy) <- (funcTy as FuncTy)) {
                        if (let Some(extendedTy) <- ed.GetTy()) {
                            if (realFuncTy.paramTys.size == 1 && IsBuiltinOperatorToken(fd.op)) {
                                let expectedRetTy = BuiltinOperatorResultTy(typeManager, fd.op, extendedTy, realFuncTy.paramTys[0])
                                if (SameTy(expectedRetTy, realFuncTy.retTy)) {
                                    CreateBuiltInBinaryOperatorFunc(typeManager, fd.op, realFuncTy.paramTys[0], ed, expectedRetTy)
                                } else {
                                    diag.DiagnoseRefactor(
                                        DiagKindRefactor.sema_return_type_incompatible,
                                        fd.begin,
                                        arguments: [fd.identifier.Val()]
                                    )
                                }
                                return true
                            } else if (realFuncTy.paramTys.isEmpty() && IsBuiltinOperatorToken(fd.op)) {
                                let expectedUnaryRetTy = BuiltinOperatorResultTy(typeManager, fd.op, extendedTy, extendedTy)
                                if (SameTy(expectedUnaryRetTy, realFuncTy.retTy)) {
                                    CreateBuiltInUnaryOperatorFunc(typeManager, fd.op, ed, expectedUnaryRetTy)
                                } else {
                                    diag.DiagnoseRefactor(
                                        DiagKindRefactor.sema_return_type_incompatible,
                                        fd.begin,
                                        arguments: [fd.identifier.Val()]
                                    )
                                }
                                return true
                            }
                        }
                    }
                }
            }
        }
    }
    return false
}

func CreateBuiltInUnaryOperatorFunc(
    typeManager: TypeManager,
    op: TokenKind,
    ed: ExtendDecl,
    returnTy: Ty
): Unit {
    let fd = FuncDecl()
    CopyBasicInfo(ed, fd)
    fd.EnableAttr(Attribute.IN_EXTEND)
    fd.EnableAttr(Attribute.PUBLIC)
    fd.EnableAttr(Attribute.OPERATOR)
    fd.EnableAttr(Attribute.IMPLICIT_ADD)
    fd.toBeCompiled = true
    fd.moduleName = ed.moduleName
    fd.fullPackageName = ed.fullPackageName
    fd.op = op
    fd.identifier = SrcIdentifier(TokenKindLiteral(op))
    fd.outerDecl = ed
    fd.SetTy(typeManager.GetFunctionTy(Array<Ty>(), returnTy))

    let funcBody = FuncBody()
    let params = FuncParamList()
    funcBody.paramLists.add(params)
    funcBody.funcDecl = fd
    funcBody.SetTy(typeManager.GetFunctionTy(Array<Ty>(), returnTy))

    let thisExpr = CreateRefExpr("this")
    thisExpr.isThis = true
    if (let Some(thisTy) <- ed.GetTy()) {
        thisExpr.SetTy(thisTy)
    }
    let unary = CreateUnaryExpr(thisExpr, op)
    unary.SetTy(returnTy)
    let ret = CreateReturnExpr(unary, Some(funcBody))
    ret.SetTy(TypeManager.GetNothingTy())
    let block = Block()
    block.SetTy(TypeManager.GetNothingTy())
    block.body.add(ret)
    funcBody.body = block
    fd.funcBody = funcBody
    AddCurFile(fd, file: ed.curFile)
    ed.members.add(fd)
}

func CreateBuiltInBinaryOperatorFunc(
    typeManager: TypeManager,
    op: TokenKind,
    rightTy: Ty,
    ed: ExtendDecl,
    returnTy: Ty
): Unit {
    let fd = FuncDecl()
    CopyBasicInfo(ed, fd)
    fd.EnableAttr(Attribute.IN_EXTEND)
    fd.EnableAttr(Attribute.PUBLIC)
    fd.EnableAttr(Attribute.OPERATOR)
    fd.EnableAttr(Attribute.IMPLICIT_ADD)
    fd.toBeCompiled = true
    fd.moduleName = ed.moduleName
    fd.fullPackageName = ed.fullPackageName
    fd.op = op
    fd.identifier = SrcIdentifier(TokenKindLiteral(op))
    fd.outerDecl = ed
    fd.SetTy(typeManager.GetFunctionTy([rightTy], returnTy))

    let funcBody = FuncBody()
    funcBody.funcDecl = fd
    funcBody.SetTy(typeManager.GetFunctionTy([rightTy], returnTy))
    let rightParam = FuncParam()
    rightParam.identifier = SrcIdentifier("right")
    rightParam.SetTy(rightTy)
    let paramList = FuncParamList()
    paramList.params.add(rightParam)
    funcBody.paramLists.add(paramList)

    let leftExpr = CreateRefExpr("this")
    leftExpr.isThis = true
    if (let Some(thisTy) <- ed.GetTy()) {
        leftExpr.SetTy(thisTy)
    }
    let rightExpr = CreateRefExpr(rightParam)
    rightExpr.SetTy(rightTy)
    let binary = CreateBinaryExpr(leftExpr, rightExpr, op)
    binary.SetTy(returnTy)
    let ret = CreateReturnExpr(binary, Some(funcBody))
    ret.SetTy(TypeManager.GetNothingTy())
    let block = Block()
    block.SetTy(TypeManager.GetNothingTy())
    block.body.add(ret)
    funcBody.body = block
    fd.funcBody = funcBody
    AddCurFile(fd, file: ed.curFile)
    ed.members.add(fd)
}

public func SelfhostPortStatus_InheritanceChecker_BuiltInInheritanceHelper(): Bool {
    return true
}
