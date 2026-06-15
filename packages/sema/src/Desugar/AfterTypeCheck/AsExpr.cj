package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let V_COMPILER: String = "v-compiler"
private let OPTION_VALUE_CTOR: String = "Some"
private let OPTION_NONE_CTOR: String = "None"

private func CloneTypeNode(typeNode: Type): Option<Type> {
    return ASTCloner.Clone(typeNode) as Type
}

private func CreateAsExprSomeCall(someDecl: FuncDecl, asType: Type, varDecl: VarDecl, someCtorTy: FuncTy): CallExpr {
    let someRef = CreateRefExpr(someDecl)
    if (let Some(typeArg) <- CloneTypeNode(asType)) {
        someRef.typeArguments.add(typeArg)
    }
    if (!someCtorTy.paramTys.isEmpty()) {
        someRef.instTys.add(someCtorTy.paramTys[0])
    }
    someRef.ref.targets.add(someDecl)
    someRef.isAlone = false
    someRef.SetTy(someCtorTy)
    let newVarRef = CreateRefExpr(varDecl)
    if (!someCtorTy.paramTys.isEmpty()) {
        newVarRef.SetTy(someCtorTy.paramTys[0])
    }
    let args = ArrayList<FuncArg>()
    let someArgTy = if (!someCtorTy.paramTys.isEmpty()) { someCtorTy.paramTys[0] } else { TypeManager.GetInvalidTy() }
    args.add(CreateFuncArg(newVarRef, "", someArgTy))
    let callExpr = CreateCallExpr(someRef, args, someDecl, someCtorTy.retTy, CallKind.CALL_DECLARED_FUNCTION)
    callExpr.resolvedFunction = someDecl
    callExpr.callKind = CallKind.CALL_DECLARED_FUNCTION
    callExpr.SetTy(someCtorTy.retTy)
    return callExpr
}

private func GetSingleParamFunctionTy(typeManager: TypeManager, paramTy: Ty, retTy: Ty): FuncTy {
    let params = ArrayList<Ty>()
    params.add(paramTy)
    return typeManager.GetFunctionTy(params.toArray(), retTy)
}

public func DesugarAsExpr(typeManager: TypeManager, expr: AsExpr): Unit {
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return
    }
    if (let Some(optionTy) <- expr.GetTy()) {
        if (!optionTy.IsCoreOptionType()) {
            return
        }
        if (let Some(_) <- expr.desugarExpr) {
            return
        }
        if (let Some(left) <- expr.leftExpr) {
            if (let Some(typeNode) <- expr.asType) {
                if (let Some(selectorTy) <- left.GetTy()) {
                    if (let Some(asTy) <- typeNode.GetTy()) {
                        if (let Some(optionEnumTy) <- (optionTy as EnumTy)) {
                            if (let Some(optionDecl) <- optionEnumTy.decl) {
                                if (let Some(someDeclNode) <- LookupEnumMember(optionDecl, OPTION_VALUE_CTOR)) {
                                    if (let Some(someDecl) <- (someDeclNode as FuncDecl)) {
                                        let varPattern = CreateVarPattern(V_COMPILER, asTy)
                                        varPattern.begin = expr.asPos
                                        varPattern.end = expr.asPos
                                        if (let Some(varDecl) <- varPattern.varDecl) {
                                            varDecl.fullPackageName = expr.GetFullPackageName()
                                            let matchCases = ArrayList<MatchCase>()
                                            let someCtorTy = GetSingleParamFunctionTy(typeManager, asTy, optionTy)
                                            let someCall = CreateAsExprSomeCall(someDecl, typeNode, varDecl, someCtorTy)
                                            let typePattern = CreateRuntimePreparedTypePattern(
                                                typeManager, varPattern, typeNode, left)
                                            matchCases.add(CreateMatchCase(typePattern, someCall))
                                            let wildcard = WildcardPattern()
                                            wildcard.SetTy(selectorTy)
                                            if (let Some(noneDecl) <- LookupEnumMember(optionDecl, OPTION_NONE_CTOR)) {
                                                let noneRef = CreateRefExpr(noneDecl)
                                                CopyBasicInfo(expr, noneRef)
                                                if (let Some(typeArg) <- CloneTypeNode(typeNode)) {
                                                    noneRef.typeArguments.add(typeArg)
                                                }
                                                noneRef.instTys.add(asTy)
                                                noneRef.SetTy(optionTy)
                                                matchCases.add(CreateMatchCase(wildcard, noneRef))
                                                let matchExpr = CreateMatchExpr(left, matchCases, optionTy, SugarKind.AS)
                                                CopyBasicInfo(expr, matchExpr)
                                                AddCurFile(matchExpr, file: expr.curFile)
                                                expr.desugarExpr = matchExpr
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
