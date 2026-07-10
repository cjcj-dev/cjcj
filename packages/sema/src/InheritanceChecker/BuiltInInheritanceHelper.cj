package cjcj::sema.InheritanceChecker

import cjcj::ast.*
import cjcj::basic.{DiagnosticEngine, DiagKindRefactor}
import cjcj::sema.*

private func IsBuiltinGeneralArithmeticIntKind(kind: TypeKind): Bool {
    return kind == TypeKind.TYPE_INT8 || kind == TypeKind.TYPE_INT16 || kind == TypeKind.TYPE_INT32 ||
        kind == TypeKind.TYPE_INT64 || kind == TypeKind.TYPE_INT_NATIVE || kind == TypeKind.TYPE_UINT8 ||
        kind == TypeKind.TYPE_UINT16 || kind == TypeKind.TYPE_UINT32 || kind == TypeKind.TYPE_UINT64 ||
        kind == TypeKind.TYPE_UINT_NATIVE || kind == TypeKind.TYPE_IDEAL_INT
}

private func IsBuiltinGeneralArithmeticKind(kind: TypeKind): Bool {
    return IsBuiltinGeneralArithmeticIntKind(kind) || kind == TypeKind.TYPE_FLOAT16 ||
        kind == TypeKind.TYPE_FLOAT32 || kind == TypeKind.TYPE_FLOAT64 || kind == TypeKind.TYPE_IDEAL_FLOAT
}

private func IsBuiltinRelationNumericKind(kind: TypeKind): Bool {
    return IsBuiltinGeneralArithmeticKind(kind) || kind == TypeKind.TYPE_RUNE
}

private func GetBuiltinUnaryReturnKindForInheritance(op: TokenKind, operandTy: Ty): TypeKind {
    if (!Ty.IsTyCorrect(operandTy)) {
        return TypeKind.TYPE_INVALID
    }
    let operandKind = operandTy.kind
    if (op == TokenKind.SUB && IsBuiltinGeneralArithmeticKind(operandKind)) {
        return operandKind
    }
    if (op == TokenKind.NOT &&
        (IsBuiltinGeneralArithmeticIntKind(operandKind) || operandKind == TypeKind.TYPE_BOOLEAN)) {
        return operandKind
    }
    if ((op == TokenKind.INCR || op == TokenKind.DECR) && IsBuiltinGeneralArithmeticIntKind(operandKind)) {
        return operandKind
    }
    return TypeKind.TYPE_INVALID
}

private func GetBuiltinBinaryReturnKindForInheritance(op: TokenKind, leftTy: Ty, rightTy: Ty): TypeKind {
    if (!Ty.IsTyCorrect(leftTy) || !Ty.IsTyCorrect(rightTy)) {
        return TypeKind.TYPE_INVALID
    }
    let leftKind = leftTy.kind
    let rightKind = rightTy.kind
    if (op == TokenKind.EXP) {
        if (leftKind == TypeKind.TYPE_INT64 && rightKind == TypeKind.TYPE_UINT64) {
            return TypeKind.TYPE_INT64
        }
        if (leftKind == TypeKind.TYPE_FLOAT64 &&
            (rightKind == TypeKind.TYPE_FLOAT64 || rightKind == TypeKind.TYPE_INT64)) {
            return TypeKind.TYPE_FLOAT64
        }
        return TypeKind.TYPE_INVALID
    }
    if (op == TokenKind.LSHIFT || op == TokenKind.RSHIFT) {
        if (IsBuiltinGeneralArithmeticIntKind(leftKind) && IsBuiltinGeneralArithmeticIntKind(rightKind)) {
            return leftKind
        }
        return TypeKind.TYPE_INVALID
    }
    if (!SameTy(leftTy, rightTy)) {
        return TypeKind.TYPE_INVALID
    }
    if (op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL || op == TokenKind.DIV) {
        return if (IsBuiltinGeneralArithmeticKind(leftKind)) { leftKind } else { TypeKind.TYPE_INVALID }
    }
    if (op == TokenKind.MOD || op == TokenKind.BITAND || op == TokenKind.BITXOR || op == TokenKind.BITOR) {
        return if (IsBuiltinGeneralArithmeticIntKind(leftKind)) { leftKind } else { TypeKind.TYPE_INVALID }
    }
    if (op == TokenKind.EQUAL || op == TokenKind.NOTEQ) {
        if (IsBuiltinRelationNumericKind(leftKind) || leftKind == TypeKind.TYPE_BOOLEAN ||
            leftKind == TypeKind.TYPE_UNIT) {
            return TypeKind.TYPE_BOOLEAN
        }
        return TypeKind.TYPE_INVALID
    }
    if (op == TokenKind.LT || op == TokenKind.LE || op == TokenKind.GT || op == TokenKind.GE) {
        return if (IsBuiltinRelationNumericKind(leftKind)) { TypeKind.TYPE_BOOLEAN } else { TypeKind.TYPE_INVALID }
    }
    if (op == TokenKind.AND || op == TokenKind.OR) {
        return if (leftKind == TypeKind.TYPE_BOOLEAN) { TypeKind.TYPE_BOOLEAN } else { TypeKind.TYPE_INVALID }
    }
    return TypeKind.TYPE_INVALID
}

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
                        if (let Some(extendedType) <- ed.extendedType) {
                            if (let Some(extendedTy) <- extendedType.GetTy()) {
                                if (realFuncTy.paramTys.size == 1) {
                                    let expectedRetKind = GetBuiltinBinaryReturnKindForInheritance(
                                        fd.op,
                                        extendedTy,
                                        realFuncTy.paramTys[0]
                                    )
                                    if (expectedRetKind == TypeKind.TYPE_INVALID) {
                                        return false
                                    }
                                    let expectedRetTy = TypeManager.GetPrimitiveTy(expectedRetKind)
                                    if (SameTy(expectedRetTy, realFuncTy.retTy)) {
                                        CreateBuiltInBinaryOperatorFunc(typeManager, fd.op, realFuncTy.paramTys[0], ed, expectedRetTy)
                                    } else {
                                        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                                        diag.DiagnoseRefactor(
                                            DiagKindRefactor.sema_return_type_incompatible,
                                            fd.begin,
                                            arguments: [fd.identifier.Val()]
                                        )
                                    }
                                    return true
                                } else if (realFuncTy.paramTys.isEmpty()) {
                                    let expectedUnaryRetKind = GetBuiltinUnaryReturnKindForInheritance(fd.op, extendedTy)
                                    if (expectedUnaryRetKind == TypeKind.TYPE_INVALID) {
                                        return false
                                    }
                                    let expectedUnaryRetTy = TypeManager.GetPrimitiveTy(expectedUnaryRetKind)
                                    if (SameTy(expectedUnaryRetTy, realFuncTy.retTy)) {
                                        CreateBuiltInUnaryOperatorFunc(typeManager, fd.op, ed, expectedUnaryRetTy)
                                    } else {
                                        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
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
    }
    return false
}

private func CreateBuiltinReturnType(returnTy: Ty): PrimitiveType {
    let retType = PrimitiveType()
    retType.kind = returnTy.kind
    retType.SetTy(returnTy)
    retType.EnableAttr(Attribute.COMPILER_ADD)
    return retType
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
    funcBody.retType = Some(CreateBuiltinReturnType(returnTy))

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
    funcBody.retType = Some(CreateBuiltinReturnType(returnTy))
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
