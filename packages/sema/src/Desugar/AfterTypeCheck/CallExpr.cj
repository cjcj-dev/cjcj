package cangjie_compiler::sema.Desugar.AfterTypeCheck

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let CORE_PACKAGE_NAME: String = "std.core"

private func GetIntrinsicOp(identifier: String): TokenKind {
    if (identifier == "Int64Less" || identifier == "Int32Less" || identifier == "Int16Less" ||
        identifier == "Int8Less" || identifier == "UInt64Less" || identifier == "UInt32Less" ||
        identifier == "UInt16Less" || identifier == "UInt8Less" || identifier == "Float16Less" ||
        identifier == "Float32Less" || identifier == "Float64Less") {
        return TokenKind.LT
    }
    if (identifier == "Int64Greater" || identifier == "Int32Greater" || identifier == "Int16Greater" ||
        identifier == "Int8Greater" || identifier == "UInt64Greater" || identifier == "UInt32Greater" ||
        identifier == "UInt16Greater" || identifier == "UInt8Greater" || identifier == "Float16Greater" ||
        identifier == "Float32Greater" || identifier == "Float64Greater") {
        return TokenKind.GT
    }
    if (identifier == "Int64LessOrEqual" || identifier == "Int32LessOrEqual" ||
        identifier == "Int16LessOrEqual" || identifier == "Int8LessOrEqual" ||
        identifier == "UInt64LessOrEqual" || identifier == "UInt32LessOrEqual" ||
        identifier == "UInt16LessOrEqual" || identifier == "UInt8LessOrEqual" ||
        identifier == "Float16LessOrEqual" || identifier == "Float32LessOrEqual" ||
        identifier == "Float64LessOrEqual") {
        return TokenKind.LE
    }
    if (identifier == "Int64GreaterOrEqual" || identifier == "Int32GreaterOrEqual" ||
        identifier == "Int16GreaterOrEqual" || identifier == "Int8GreaterOrEqual" ||
        identifier == "UInt64GreaterOrEqual" || identifier == "UInt32GreaterOrEqual" ||
        identifier == "UInt16GreaterOrEqual" || identifier == "UInt8GreaterOrEqual" ||
        identifier == "Float16GreaterOrEqual" || identifier == "Float32GreaterOrEqual" ||
        identifier == "Float64GreaterOrEqual") {
        return TokenKind.GE
    }
    if (identifier == "Int64Equal" || identifier == "Int32Equal" || identifier == "Int16Equal" ||
        identifier == "Int8Equal" || identifier == "UInt64Equal" || identifier == "UInt32Equal" ||
        identifier == "UInt16Equal" || identifier == "UInt8Equal" || identifier == "Float16Equal" ||
        identifier == "Float32Equal" || identifier == "Float64Equal") {
        return TokenKind.EQUAL
    }
    if (identifier == "Int64NotEqual" || identifier == "Int32NotEqual" || identifier == "Int16NotEqual" ||
        identifier == "Int8NotEqual" || identifier == "UInt64NotEqual" || identifier == "UInt32NotEqual" ||
        identifier == "UInt16NotEqual" || identifier == "UInt8NotEqual" || identifier == "Float16NotEqual" ||
        identifier == "Float32NotEqual" || identifier == "Float64NotEqual") {
        return TokenKind.NOTEQ
    }
    return TokenKind.ILLEGAL
}

private func GetIntrinsicPackage(target: Decl): String {
    if (let Some(genericDecl) <- target.genericDecl) {
        return genericDecl.fullPackageName
    }
    if (let Some(outerDecl) <- target.outerDecl) {
        if (let Some(genericDecl) <- outerDecl.genericDecl) {
            return genericDecl.fullPackageName
        }
    }
    return target.fullPackageName
}

public func DesugarComparableIntrinsic(expr: CallExpr, op: TokenKind): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (expr.args.size != 2) {
        return
    }
    if (let Some(left) <- expr.args[0].expr) {
        if (let Some(right) <- expr.args[1].expr) {
            let binExpr = CreateBinaryExpr(left, right, op)
            binExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
            CopyBasicInfo(expr, binExpr)
            expr.desugarExpr = binExpr
        }
    }
}

public func DesugarIntrinsicCallExpr(expr: CallExpr): Unit {
    if (expr.callKind != CallKind.CALL_INTRINSIC_FUNCTION) {
        return
    }
    if (let Some(base) <- expr.baseFunc) {
        if (let Some(target) <- base.GetTarget()) {
            if (GetIntrinsicPackage(target) != CORE_PACKAGE_NAME) {
                return
            }
            let op = GetIntrinsicOp(target.identifier.Val())
            if (op != TokenKind.ILLEGAL) {
                DesugarComparableIntrinsic(expr, op)
            }
        }
    }
}

public func DesugarTokenCallExpr(expr: CallExpr): Unit {
    let _ = expr
    // TODO(selfhost:Sema): port Token(...) refreshPos rewrite after SynthesizeWithoutRecover is available.
}
