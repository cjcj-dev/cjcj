package cjcj::sema

import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::utils.FloatFormat

public func ChkFloatTypeOverflow(expr: LitConstExpr, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let info = GetFloatTypeInfoByKind(expr.TyKind())
    match (expr.constNumValue.asFloat.flowStatus) {
        case FlowStatus.OVER =>
            if (let Some(diagValue) <- diag) {
                let builder = DiagnoseRefactor(diagValue,
                    BasicDiagKindRefactor.sema_float_literal_too_large,
                    expr,
                    arguments: [(expr.GetTy() ?? TypeManager.GetInvalidTy()).String(), info.max])
                builder.Emit()
            }
            return false
        case FlowStatus.UNDER =>
            if (let Some(diagValue2) <- diag) {
                let builder = DiagnoseRefactor(diagValue2,
                    BasicDiagKindRefactor.sema_float_literal_too_small,
                    expr,
                    arguments: [(expr.GetTy() ?? TypeManager.GetInvalidTy()).String(), info.min])
                builder.Emit()
            }
            return false
        case _ => ()
    }
    var value: UInt64 = 0u64
    match (expr.TyKind()) {
        case TypeKind.TYPE_FLOAT16 =>
            let f32 = Float32(expr.constNumValue.asFloat.value)
            value = UInt64(FloatFormat.Float32ToFloat16(f32)) << 1u64
        case TypeKind.TYPE_FLOAT32 =>
            let f32 = Float32(expr.constNumValue.asFloat.value)
            value = UInt64(f32.toBits() << 1u32)
        case TypeKind.TYPE_FLOAT64 =>
            let f64 = expr.constNumValue.asFloat.value
            value = f64.toBits() << 1u64
        case _ => return true
    }
    if (expr.constNumValue.asFloat.value != 0.0 && value == 0u64) {
        if (let Some(diagValue3) <- diag) {
            let builder = DiagnoseRefactor(diagValue3,
                BasicDiagKindRefactor.sema_float_literal_too_small,
                expr,
                arguments: [(expr.GetTy() ?? TypeManager.GetInvalidTy()).String(), info.min])
            builder.Emit()
        }
        return false
    } else if (value == info.inf) {
        if (let Some(diagValue4) <- diag) {
            let builder = DiagnoseRefactor(diagValue4,
                BasicDiagKindRefactor.sema_float_literal_too_large,
                expr,
                arguments: [(expr.GetTy() ?? TypeManager.GetInvalidTy()).String(), info.max])
            builder.Emit()
        }
        return false
    }
    return true
}

public func ChkLitConstExprRange(expr: LitConstExpr, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return false
    }
    InitializeLitConstValue(expr)
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.IsInteger()) {
            expr.constNumValue.asInt.SetOutOfRange(exprTy)
            if (expr.constNumValue.asInt.IsOutOfRange()) {
                if (let Some(diagValue) <- diag) {
                    var typeName = exprTy.String()
                    if (exprTy.IsIdeal()) {
                        typeName += "64"
                    }
                    let builder = DiagnoseRefactor(diagValue,
                        BasicDiagKindRefactor.sema_exceed_num_value_range,
                        expr,
                        arguments: [expr.stringValue, typeName])
                    builder.Emit()
                }
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        } else if (exprTy.IsFloating()) {
            let _ = ChkFloatTypeOverflow(expr, diag: diag)
        }
    }
    return true
}

public func ReplaceIdealTy(typeManager: TypeManager, node: Node, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!Ty.IsTyCorrect(node.GetTy())) {
        return false
    }
    if (let Some(nodeTy) <- node.GetTy()) {
        node.SetTy(typeManager.ReplaceIdealTy(nodeTy))
        if (let Some(lit) <- (node as LitConstExpr)) {
            return ChkLitConstExprRange(lit, diag: diag)
        }
        return true
    }
    return false
}
