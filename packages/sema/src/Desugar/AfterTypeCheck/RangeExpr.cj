package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let INT64_MAX_STRING: String = "9223372036854775807"

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

private func CreateRangeExprArgs(expr: RangeExpr, rangeTy: Ty): Option<ArrayList<FuncArg>> {
    if (rangeTy.typeArgs.isEmpty()) {
        return None
    }
    let elemTy = rangeTy.typeArgs[0]
    let args = ArrayList<FuncArg>()
    if (let Some(start) <- expr.startExpr) {
        if (let Some(clonedStart) <- CloneExpr(start)) {
            args.add(CreateFuncArg(clonedStart))
        } else {
            return None
        }
    } else {
        args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, "0", elemTy)))
    }
    if (let Some(stop) <- expr.stopExpr) {
        if (let Some(clonedStop) <- CloneExpr(stop)) {
            args.add(CreateFuncArg(clonedStop))
        } else {
            return None
        }
    } else {
        args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.INTEGER, INT64_MAX_STRING, elemTy)))
    }
    if (let Some(step) <- expr.stepExpr) {
        if (let Some(clonedStep) <- CloneExpr(step)) {
            args.add(CreateFuncArg(clonedStep))
        } else {
            return None
        }
    } else {
        args.add(CreateFuncArg(CreateLitConstExpr(
            LitConstKind.INTEGER, "1", TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))))
    }
    let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
    let hasStartText = if (let Some(_) <- expr.startExpr) { "true" } else { "false" }
    let hasStopText = if (let Some(_) <- expr.stopExpr) { "true" } else { "false" }
    let isClosedText = if (expr.isClosed) { "true" } else { "false" }
    args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.BOOL, hasStartText, boolTy)))
    args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.BOOL, hasStopText, boolTy)))
    args.add(CreateFuncArg(CreateLitConstExpr(LitConstKind.BOOL, isClosedText, boolTy)))
    return args
}

private func RetargetRangeConstructor(typeManager: TypeManager, callExpr: CallExpr, rangeDecl: StructDecl,
    genericTy: GenericsTy, elemTy: Ty): Unit {
    if (let Some(body) <- rangeDecl.body) {
        let typeMapping = TypeSubst()
        typeMapping.Put(genericTy, elemTy)
        for (decl in body.decls) {
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (IsInstanceConstructor(funcDecl)) {
                    if (let Some(base) <- callExpr.baseFunc) {
                        if (let Some(refExpr) <- (base as RefExpr)) {
                            refExpr.SetTarget(funcDecl)
                            if (let Some(funcTy) <- funcDecl.GetTy()) {
                                refExpr.SetTy(typeManager.GetInstantiatedTy(funcTy, typeMapping))
                            }
                            callExpr.resolvedFunction = funcDecl
                            callExpr.callKind = CallKind.CALL_OBJECT_CREATION
                        }
                    }
                    return
                }
            }
        }
    }
}

public func DesugarRangeExpr(typeManager: TypeManager, expr: RangeExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(rangeDecl) <- expr.decl) {
        if (let Some(rangeTy) <- expr.GetTy()) {
            if (rangeTy.typeArgs.isEmpty()) {
                return
            }
            if (let Some(generic) <- rangeDecl.generic) {
                if (generic.typeParameters.isEmpty() || rangeTy.typeArgs.size != generic.typeParameters.size) {
                    return
                }
                if (let Some(genericParamTy) <- generic.typeParameters[0].GetTy()) {
                    if (!Ty.IsTyCorrect(genericParamTy)) {
                        return
                    }
                    if (let Some(genericTy) <- (genericParamTy as GenericsTy)) {
                        let rangeFunc = CreateRefExpr(rangeDecl.identifier.Val())
                        rangeFunc.ref.identifier = SrcIdentifier(
                            rangeDecl.identifier.Val(), rangeDecl.identifier.Begin(),
                            rangeDecl.identifier.End(), rangeDecl.identifier.IsRaw())
                        CopyBasicInfo(expr, rangeFunc)
                        rangeFunc.instTys.add(rangeTy.typeArgs[0])
                        if (let Some(args) <- CreateRangeExprArgs(expr, rangeTy)) {
                            let callExpr = CreateCallExpr(rangeFunc, args)
                            callExpr.SetTy(rangeTy)
                            RetargetRangeConstructor(typeManager, callExpr, rangeDecl, genericTy, rangeTy.typeArgs[0])
                            CopyBasicInfo(expr, callExpr)
                            AddCurFile(callExpr, file: expr.curFile)
                            expr.desugarExpr = callExpr
                        }
                    }
                }
            }
        }
    }
}
