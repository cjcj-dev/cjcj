package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.TypeManager
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func ToBasicRange(begin: Position, end: Position): BasicRange {
    var fixedEnd = end
    if (begin.fileID != end.fileID) {
        fixedEnd = begin + 1
    }
    return BasicRange(ToBasicPosition(begin), ToBasicPosition(fixedEnd))
}

private func TokenRange(pos: Position, tokenText: String): BasicRange {
    return ToBasicRange(pos, pos + tokenText.size)
}

private func TyString(ty: Option<Ty>): String {
    if (let Some(value) <- ty) {
        return value.String()
    }
    return TypeManager.GetInvalidTy().String()
}

private func IsOverloadableOperator(op: TokenKind): Bool {
    return op == TokenKind.ADD || op == TokenKind.BITAND || op == TokenKind.BITOR ||
        op == TokenKind.BITXOR || op == TokenKind.DIV || op == TokenKind.EQUAL ||
        op == TokenKind.EXP || op == TokenKind.GE || op == TokenKind.GT ||
        op == TokenKind.LE || op == TokenKind.LSHIFT || op == TokenKind.LT ||
        op == TokenKind.MOD || op == TokenKind.MUL || op == TokenKind.NOT ||
        op == TokenKind.NOTEQ || op == TokenKind.RSHIFT || op == TokenKind.SUB
}

private func TypeListString(indexTys: ArrayList<Ty>): String {
    let parts = ArrayList<String>()
    for (ty in indexTys) {
        parts.add(ty.String())
    }
    return JoinStrings(parts, "', '")
}

private func IndexParameterString(indexTys: ArrayList<Ty>): String {
    let parts = ArrayList<String>()
    var idx: Int64 = 0
    while (idx < indexTys.size) {
        parts.add("index${idx}: " + indexTys[idx].String())
        idx++
    }
    return JoinStrings(parts, ", ")
}

public func DiagInvalidMultipleAssignExpr(
    diag: BasicDiagnosticEngine,
    leftNode: Node,
    rightExpr: Expr,
    because: String
): Unit {
    let builder = DiagnoseRefactor(
        diag,
        BasicDiagKindRefactor.sema_mismatched_types_multiple_assign,
        rightExpr,
        arguments: [TyString(rightExpr.GetTy())])
    AddHint(builder, leftNode, arguments: [because])
    builder.Emit()
}

public func DiagInvalidBinaryExpr(diag: BasicDiagnosticEngine, be: BinaryExpr): Unit {
    if (let Some(left) <- be.leftExpr) {
        if (let Some(right) <- be.rightExpr) {
            let leftTyText = TyString(left.GetTy())
            let rightTyText = TyString(right.GetTy())
            let opStr = TokenKindText(be.op)
            let range = if (be.operatorPos.IsZero()) {
                ToBasicRange(be.begin, be.end)
            } else {
                TokenRange(be.operatorPos, opStr)
            }
            let builder = DiagnoseRefactor(
                diag,
                BasicDiagKindRefactor.sema_invalid_binary_expr,
                be,
                range,
                arguments: [opStr, leftTyText, rightTyText])
            if (let Some(leftTy) <- left.GetTy()) {
                if (leftTy.IsFunc() || leftTy.IsCFunc() || leftTy.IsTuple()) {
                    builder.Emit()
                    return
                }
                if (IsOverloadableOperator(be.op)) {
                    var note = "you may want to implement 'operator func " + opStr +
                        "(right: " + rightTyText + ")' for type '" + leftTyText + "'"
                    if (be.op == TokenKind.EXP) {
                        if (left.TyKind() == TypeKind.TYPE_INT64) {
                            note += ", or to provide a right operand of type 'UInt64'"
                        } else if (left.TyKind() == TypeKind.TYPE_FLOAT64) {
                            note += ", or to provide a right operand of type 'Int64' or 'Float64'"
                        } else if (right.TyKind() == TypeKind.TYPE_INT64) {
                            note += ", or to provide a left operand of type 'Float64'"
                        } else if (right.TyKind() == TypeKind.TYPE_FLOAT64) {
                            note += ", or to provide a left operand of type 'Float64'"
                        } else if (right.TyKind() == TypeKind.TYPE_UINT64) {
                            note += ", or to provide a left operand of type 'Int64'"
                        }
                    }
                    builder.AddNote(note)
                }
            }
            builder.Emit()
        }
    }
}

public func DiagInvalidUnaryExpr(diag: BasicDiagnosticEngine, ue: UnaryExpr): Unit {
    if (!ue.ShouldDiagnose()) {
        return
    }
    if (let Some(innerExpr) <- ue.expr) {
        let opStr = TokenKindText(ue.op)
        let exprTyText = TyString(innerExpr.GetTy())
        let builder = DiagnoseRefactor(
            diag,
            BasicDiagKindRefactor.sema_invalid_unary_expr,
            ue,
            arguments: [opStr, exprTyText])
        if (let Some(exprTy) <- innerExpr.GetTy()) {
            if (exprTy.IsExtendable()) {
                builder.AddNote("you may want to implement 'operator func " + opStr +
                    "()' for type '" + exprTyText + "'")
            }
        }
        builder.Emit()
    }
}

public func DiagInvalidUnaryExprWithTarget(diag: BasicDiagnosticEngine, ue: UnaryExpr, target: Ty): Unit {
    if (!ue.ShouldDiagnose()) {
        return
    }
    if (let Some(innerExpr) <- ue.expr) {
        let builder = DiagnoseRefactor(
            diag,
            BasicDiagKindRefactor.sema_invalid_unary_expr_with_target,
            ue,
            arguments: [TokenKindText(ue.op), TyString(innerExpr.GetTy()), target.String()])
        builder.Emit()
    }
}

private func DeclIdentifierRange(decl: Decl): BasicRange {
    let identifier = decl.identifier.Val()
    if (identifier.isEmpty()) {
        return ToBasicRange(decl.begin, decl.end)
    }
    return TokenRange(decl.identifier.Begin(), identifier)
}

public func DiagMismatchedTypesWithFoundTy(
    diag: BasicDiagnosticEngine,
    node: Node,
    expected: Ty,
    found: Ty,
    note!: String = ""
): Unit {
    if (!node.ShouldDiagnose(allowCompilerAdd: true)) {
        return
    }
    var expectedStr = expected.String()
    var foundStr = found.String()
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_mismatched_types, node)
    if (expectedStr == foundStr) {
        if (let Some(expectedDecl) <- Ty.GetDeclPtrOfTy(Some(expected))) {
            expectedStr += "' in '" + expectedDecl.fullPackageName
            AddNote(builder, expectedDecl, DeclIdentifierRange(expectedDecl), "'" + expectedStr + "'")
        }
        if (let Some(foundDecl) <- Ty.GetDeclPtrOfTy(Some(found))) {
            foundStr += "' in '" + foundDecl.fullPackageName
            AddNote(builder, foundDecl, DeclIdentifierRange(foundDecl), "'" + foundStr + "'")
        }
    }
    builder.AddMainHintArguments([expectedStr, foundStr])
    if (!note.isEmpty()) {
        builder.AddNote(note)
    }
    builder.Emit()
}

public func DiagInvalidSubscriptExpr(
    diag: BasicDiagnosticEngine,
    se: SubscriptExpr,
    baseTy: Ty,
    indexTys: ArrayList<Ty>
): Unit {
    if (!se.ShouldDiagnose() || indexTys.isEmpty()) {
        return
    }
    let indexPrefix = if (indexTys.size > 1) { "types " } else { "type " }
    let indexStr = indexPrefix + "'" + TypeListString(indexTys) + "'"
    let builder = DiagnoseRefactor(
        diag,
        BasicDiagKindRefactor.sema_invalid_subscript_expr,
        se,
        arguments: [baseTy.String(), indexStr])
    if (baseTy.IsExtendable()) {
        builder.AddNote("you may want to implement 'operator func [](" + IndexParameterString(indexTys) +
            ")' for type '" + baseTy.String() + "'")
    }
    builder.Emit()
}

public func DiagUnableToInferExpr(diag: BasicDiagnosticEngine, expr: Expr): Unit {
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_unable_to_infer_expr, expr)
    builder.Emit()
}

public func DiagUnableToInferReturnType(diag: BasicDiagnosticEngine, funcDecl: FuncDecl): Unit {
    if (Ty.IsTyCorrect(funcDecl.GetTy())) {
        let builder = DiagnoseRefactor(
            diag,
            BasicDiagKindRefactor.sema_unable_to_infer_return_type,
            funcDecl,
            DeclIdentifierRange(funcDecl))
        builder.Emit()
    }
}

public func DiagUnableToInferReturnType(diag: BasicDiagnosticEngine, funcDecl: FuncDecl, expr: Expr): Unit {
    if (Ty.IsTyCorrect(funcDecl.GetTy())) {
        let builder = DiagnoseRefactor(
            diag,
            BasicDiagKindRefactor.sema_unable_to_infer_return_type,
            funcDecl,
            DeclIdentifierRange(funcDecl))
        AddNote(builder, expr, ToBasicRange(expr.begin, expr.end), "with recursive usage from")
        builder.Emit()
    }
}

public func DiagUnableToInferReturnType(diag: BasicDiagnosticEngine, funcBody: FuncBody): Unit {
    if (let Some(funcDecl) <- funcBody.funcDecl) {
        DiagUnableToInferReturnType(diag, funcDecl)
    } else {
        let builder = DiagnoseRefactor(
            diag, BasicDiagKindRefactor.sema_unable_to_infer_return_type, funcBody)
        builder.Emit()
    }
}
