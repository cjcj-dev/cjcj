package cangjie_compiler::chir

import std.collection.*

public enum CHIRCheckerRule {
    | EMPTY_BLOCK
    | CHECK_FUNC_BODY
    | GET_INSTANTIATE_VALUE_SHOULD_GONE
    | CHIR_GET_RTTI_STATIC_TYPE
    | RETURN_TYPE_NEED_BE_VOID
    | IMPORTED_CONST_VAR_SHOULD_HAVE_INITIALIZER
}

public func CHIRCheckerRuleIndex(rule: CHIRCheckerRule): Int64 {
    return match (rule) {
        case CHIRCheckerRule.EMPTY_BLOCK => 0
        case CHIRCheckerRule.CHECK_FUNC_BODY => 1
        case CHIRCheckerRule.GET_INSTANTIATE_VALUE_SHOULD_GONE => 2
        case CHIRCheckerRule.CHIR_GET_RTTI_STATIC_TYPE => 3
        case CHIRCheckerRule.RETURN_TYPE_NEED_BE_VOID => 4
        case CHIRCheckerRule.IMPORTED_CONST_VAR_SHOULD_HAVE_INITIALIZER => 5
    }
}

extend CHIRCheckerRule <: Equatable<CHIRCheckerRule> {
    public operator func ==(right: CHIRCheckerRule): Bool {
        return CHIRCheckerRuleIndex(this) == CHIRCheckerRuleIndex(right)
    }

    public operator func !=(right: CHIRCheckerRule): Bool {
        return !(this == right)
    }
}

public class CHIRCheckResult {
    public var ok: Bool = true
    public let errors: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func AddError(message: String): Unit {
        ok = false
        errors.add(message)
    }

    public func ToString(): String {
        if (ok) {
            return "ok"
        }
        return JoinStrings(errors, "\n")
    }
}

public class CHIRChecker {
    private let rules: ArrayList<CHIRCheckerRule> = ArrayList<CHIRCheckerRule>()
    private let identifiers: ArrayList<String> = ArrayList<String>()
    private let duplicatedGlobalIds: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func CheckPackage(pkg: Package): CHIRCheckResult {
        return CheckPackage(pkg, CHIRCheckerDefaultRules())
    }

    public func CheckPackage(pkg: Package, enabledRules: ArrayList<CHIRCheckerRule>): CHIRCheckResult {
        Reset(enabledRules)
        let result = CHIRCheckResult()
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            CheckFunction(fn, result)
        }
        for (globalVar in pkg.GetGlobalVarsWithInit()) {
            CheckGlobalVar(globalVar, result)
        }
        for (globalVar in pkg.GetGlobalVarsWithoutInit()) {
            CheckGlobalVar(globalVar, result)
        }
        for (fn in pkg.GetGlobalFuncsWithoutBody(includePureAbstract: true)) {
            CheckFuncBase(fn, result)
        }
        for (def in pkg.GetAllCustomTypeDef()) {
            CheckCustomTypeDef(def, result)
        }
        for (id in duplicatedGlobalIds) {
            result.AddError("duplicated identifier `${id}` found.")
        }
        return result
    }

    public func CheckFunction(fn: Function, result: CHIRCheckResult): Unit {
        if (!CheckFuncBase(fn, result)) {
            return
        }
        if (let Some(funcTy) <- fn.GetFuncType()) {
            CheckFuncParams(fn.GetParams(), funcTy, fn.GetIdentifier(), result)
            CheckFuncRetValue(fn.GetReturnValue(), funcTy.GetReturnType(), fn, result)
        }
        if (let Some(body) <- fn.GetBody()) {
            if (!fn.GetIdentifier().contains("$Mocked")) {
                CheckBlockGroup(body, fn, result)
            }
            CheckLocalId(body, fn, result)
            CheckUnreachableOpAndGenericTyInFuncBody(body, fn, result)
        } else {
            result.AddError("func ${fn.GetIdentifier()} doesn't have body.")
        }
        if (fn.TestAttr(Attribute.ABSTRACT)) {
            result.AddError("func ${fn.GetIdentifier()} shouldn't have attribute: ABSTRACT.")
        }
    }

    public func CheckBlock(block: Block, result: CHIRCheckResult): Unit {
        if (let Some(topLevelFunc) <- block.GetTopLevelFunc()) {
            CheckBlock(block, topLevelFunc, result)
        } else {
            result.AddError("can't get top-level function from block ${block.GetIdentifier()}.")
        }
    }

    private func Reset(enabledRules: ArrayList<CHIRCheckerRule>): Unit {
        rules.clear()
        identifiers.clear()
        duplicatedGlobalIds.clear()
        for (rule in enabledRules) {
            rules.add(rule)
        }
    }

    private func HasRule(rule: CHIRCheckerRule): Bool {
        return CHIRCheckerContainsRule(rules, rule)
    }

    private func CheckGlobalValueIdentifier(value: Value, result: CHIRCheckResult): Bool {
        let identifier = CHIRCheckerIdentifierWithoutPrefix(value.GetIdentifier())
        if (identifier.isEmpty()) {
            result.AddError(value.GetIdentifier() + " doesn't have identifier.")
            return false
        }
        if (value.TestAttr(Attribute.IMPORTED)) {
            if (let Some(valueTy) <- value.GetType()) {
                if (let Some(funcTy) <- (valueTy as FuncType)) {
                    if (funcTy.IsCFunc()) {
                        return true
                    }
                }
            }
        }
        if (!CHIRCheckerAddIdentifier(identifiers, identifier)) {
            CHIRCheckerAddUniqueString(duplicatedGlobalIds, identifier)
            return false
        }
        return true
    }

    private func CheckCustomTypeDefIdentifier(def: CustomTypeDef, result: CHIRCheckResult): Bool {
        let identifier = CHIRCheckerIdentifierWithoutPrefix(def.GetIdentifier())
        if (identifier.isEmpty()) {
            result.AddError(def.ToString() + " doesn't have identifier.")
            return false
        }
        if (!CHIRCheckerAddIdentifier(identifiers, identifier)) {
            CHIRCheckerAddUniqueString(duplicatedGlobalIds, identifier)
            return false
        }
        return true
    }

    private func CheckGlobalVar(globalVar: GlobalVar, result: CHIRCheckResult): Unit {
        if (!CheckGlobalValueIdentifier(globalVar, result)) {
            return
        }
        if (let Some(globalTy) <- globalVar.GetType()) {
            if (!CHIRCheckerTypeMustBeRef(globalTy)) {
                let valueType = globalTy.StripAllRefs()
                let expectedType = if (valueType.IsReferenceType()) {
                    valueType.ToString() + "&&"
                } else {
                    valueType.ToString() + "&"
                }
                result.AddError("the type of global var ${globalVar.GetIdentifier()} should be ${expectedType}, " +
                    "but now it's ${globalTy.ToString()}")
            }
        } else {
            result.AddError("global var ${globalVar.GetIdentifier()} doesn't have type.")
        }
        var shouldHaveInitializer = !globalVar.TestAttr(Attribute.IMPORTED) || globalVar.IsCompileTimeValue()
        if (!HasRule(CHIRCheckerRule.IMPORTED_CONST_VAR_SHOULD_HAVE_INITIALIZER) &&
            globalVar.TestAttr(Attribute.IMPORTED)) {
            shouldHaveInitializer = false
        }
        if (shouldHaveInitializer && globalVar.GetInitializerValue().isNone()) {
            result.AddError("global var ${globalVar.GetIdentifier()} should be initialized by literal or function, " +
                "it must have one of them.")
        }
        if (!globalVar.TestAttr(Attribute.IMPLICIT_ADD) && globalVar.GetSrcCodeIdentifier().isEmpty()) {
            result.AddError("global var ${globalVar.GetIdentifier()} doesn't have src code identifier.")
        }
        if (globalVar.GetPackageName().isEmpty()) {
            result.AddError("global var ${globalVar.GetIdentifier()} doesn't have package name.")
        }
        if (globalVar.GetParentCustomTypeDef().isSome() && !globalVar.TestAttr(Attribute.STATIC)) {
            result.AddError("global var ${globalVar.GetIdentifier()} should be a static member var, " +
                "but it doesn't have Attribute `STATIC`.")
        } else if (globalVar.GetParentCustomTypeDef().isNone() && globalVar.TestAttr(Attribute.STATIC)) {
            result.AddError("global var ${globalVar.GetIdentifier()} has Attribute `STATIC` but it isn't member var.")
        }
    }

    private func CheckFuncBase(fn: Function, result: CHIRCheckResult): Bool {
        if (!CheckGlobalValueIdentifier(fn, result)) {
            return false
        }
        if (!CheckFuncType(fn.GetType(), None, fn, result)) {
            return false
        }
        if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
            if (!CheckParentCustomTypeDef(fn, parentDef, false, result)) {
                return false
            }
        }
        if (fn.GetPackageName().isEmpty()) {
            result.AddError("we need to set package name in func ${fn.GetIdentifier()}.")
            return false
        }
        return true
    }

    private func CheckFuncType(typeOpt: Option<Type>, lambdaOpt: Option<Lambda>, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        if (typeOpt.isNone()) {
            if (lambdaOpt.isNone()) {
                result.AddError("func ${topLevelFunc.GetIdentifier()} doesn't have type.")
            } else if (let Some(lambdaExpr) <- lambdaOpt) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, " +
                    "${CHIRCheckerExpressionString(lambdaExpr)} doesn't have type.")
            }
            return false
        }
        if (let Some(valueTy) <- typeOpt) {
            if (let Some(funcTy) <- (valueTy as FuncType)) {
                if (funcTy.IsCJFunc() && funcTy.HasVarArg()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, this isn't CFunc, " +
                        "but it has variable length parameters.")
                    return false
                }
                if (funcTy.IsCFunc()) {
                    return CheckCFuncType(funcTy, lambdaOpt, topLevelFunc, result)
                }
                if (lambdaOpt.isNone()) {
                    CheckRetureTypeIfIsVoid(topLevelFunc, funcTy, result)
                }
                return CheckParamTypes(funcTy.GetParamTypes(), lambdaOpt, topLevelFunc, result)
            }
            if (lambdaOpt.isNone()) {
                result.AddError("the type of func ${topLevelFunc.GetIdentifier()} isn't func type.")
            } else if (let Some(lambdaExpr) <- lambdaOpt) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, the type of " +
                    "${CHIRCheckerExpressionString(lambdaExpr)} isn't func type.")
            }
        }
        return false
    }

    private func CheckCFuncType(funcTy: FuncType, lambdaOpt: Option<Lambda>, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        var typeMatched = true
        if (lambdaOpt.isNone() && topLevelFunc.GetParentCustomTypeDef().isSome()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, this is a member method, " +
                "but @C can only used in global function.")
            typeMatched = false
        }
        var idx: Int64 = 0
        while (idx < funcTy.GetNumOfParams()) {
            let paramTy = funcTy.GetParamType(idx)
            if (!CHIRCheckerIsCType(paramTy)) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, this is a CFunc, but the " +
                    CHIRCheckerIndexToString(idx) + " paramter type is ${paramTy.ToString()}, it's not a CType.")
                typeMatched = false
            }
            idx++
        }
        let retTy = funcTy.GetReturnType()
        if (!CHIRCheckerIsCType(retTy)) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, this is a CFunc, but return type is " +
                "${retTy.ToString()}, it's not a CType.")
            typeMatched = false
        } else if (retTy.IsVArray()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, VArray can't be CFunc's return type.")
            typeMatched = false
        }
        return typeMatched
    }

    private func CheckRetureTypeIfIsVoid(topLevelFunc: Function, funcTy: FuncType, result: CHIRCheckResult): Unit {
        if (HasRule(CHIRCheckerRule.RETURN_TYPE_NEED_BE_VOID)) {
            if (!ReturnTypeShouldBeVoid(topLevelFunc)) {
                return
            }
            if (!funcTy.GetReturnType().IsVoid()) {
                result.AddError("function ${topLevelFunc.GetIdentifier()} is global var init, its return type is " +
                    "${funcTy.GetReturnType().ToString()}, but `Void` is expected")
            }
        } else if (funcTy.GetReturnType().IsVoid()) {
            result.AddError("function ${topLevelFunc.GetIdentifier()} return type can't be `Void` in current stage")
        }
    }

    private func CheckParamTypes(paramTypes: ArrayList<Type>, lambdaOpt: Option<Lambda>, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let parentType = topLevelFunc.GetParentCustomTypeOrExtendedType()
        let firstParamIsThis = lambdaOpt.isNone() && parentType.isSome() && !topLevelFunc.TestAttr(Attribute.STATIC)
        var firstParamIsRef = false
        if (firstParamIsThis) {
            if (let Some(parentTy) <- parentType) {
                firstParamIsRef = parentTy.IsReferenceType() || topLevelFunc.TestAttr(Attribute.MUT) ||
                    topLevelFunc.IsConstructor() || topLevelFunc.GetSrcCodeIdentifier().contains("$varInit")
            }
        }
        var typeMatched = true
        var idx: Int64 = 0
        while (idx < paramTypes.size) {
            let paramTy = paramTypes[idx]
            if (idx == 0 && firstParamIsThis) {
                if (let Some(parentTy) <- parentType) {
                    let expectedType = if (firstParamIsRef) { RefType(parentTy) } else { parentTy }
                    if (!CHIRCheckerTypesEqual(paramTy, expectedType) && !CHIRCheckerIsAnyRef(paramTy)) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, " +
                            "${expectedType.ToString()} type is expected for the 1st parameter, but now it's " +
                            "${paramTy.ToString()}.")
                        typeMatched = false
                    }
                }
                idx++
                continue
            }
            if (paramTy.IsValueType() || paramTy.IsGeneric()) {
                idx++
                continue
            }
            let errMsg = "the " + CHIRCheckerIndexToString(idx) + " paramter type is " + paramTy.ToString()
            if (paramTy.IsReferenceType()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, ${errMsg}, " +
                    "but you should add `&` behind it.")
                typeMatched = false
                idx++
                continue
            }
            if (let Some(refTy) <- (paramTy as RefType)) {
                let baseTy = refTy.GetBaseType()
                if (baseTy.IsThis()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, ${errMsg}, " +
                        "it shouldn't be parameter's type.")
                    typeMatched = false
                } else if (!baseTy.IsClassOrArray() && !baseTy.IsBox()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, ${errMsg}, " +
                        "but only Class type, RawArray type and Box type can use `&`.")
                    typeMatched = false
                }
            }
            idx++
        }
        return typeMatched
    }

    private func CheckParentCustomTypeDef(fn: Function, def: CustomTypeDef, isInDef: Bool,
        result: CHIRCheckResult): Bool {
        if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
            if (parentDef.nodeId != def.nodeId) {
                result.AddError("parent CustomTypeDef of func ${fn.GetIdentifier()} is " +
                    "${parentDef.GetIdentifier()}, but this function is also member method of ${def.GetIdentifier()}.")
                return false
            }
            if (isInDef) {
                return true
            }
            for (method in def.GetMethods()) {
                if (method.nodeId == fn.nodeId) {
                    return true
                }
            }
            result.AddError("parent CustomTypeDef of func ${fn.GetIdentifier()} is " +
                "${parentDef.GetIdentifier()}, but there isn't this method in this CustomTypeDef.")
            return false
        }
        result.AddError("func ${fn.GetIdentifier()} is member func of ${def.GetIdentifier()}, " +
            "but it doesn't set parent CustomTypeDef.")
        return false
    }

    private func CheckFuncParams(params: ArrayList<Parameter>, funcTy: FuncType, funcIdentifier: String,
        result: CHIRCheckResult): Unit {
        let paramNumInFuncType = funcTy.GetNumOfParams()
        if (paramNumInFuncType != params.size) {
            let errMsg = "inconsistent number of parameters in func ${funcIdentifier}, there are " +
                "${params.size} parameter(s) in func body, but there are ${paramNumInFuncType} parameter(s) in func type.\n"
            let hint1 = "        parameter type in func body is " + CHIRCheckerParamsToString(params) + "\n"
            let hint2 = "        parameter type in func type is " + CHIRCheckerFuncTyParamsToString(funcTy) + "\n"
            result.AddError(errMsg + hint1 + hint2)
            return
        }
        let errIdx = ArrayList<Int64>()
        var idx: Int64 = 0
        while (idx < paramNumInFuncType) {
            if (let Some(paramTy) <- params[idx].GetType()) {
                if (!CHIRCheckerTypesEqual(funcTy.GetParamType(idx), paramTy)) {
                    errIdx.add(idx)
                }
            } else {
                errIdx.add(idx)
            }
            idx++
        }
        if (!errIdx.isEmpty()) {
            var errMsg = "inconsistent parameter type between func body and func type"
            for (item in errIdx) {
                errMsg += ", ${item}-th"
            }
            errMsg += " parameter type(s) are mismatched.\n"
            let hint1 = "        parameter type in func body is " + CHIRCheckerParamsToString(params) + "\n"
            let hint2 = "        parameter type in func type is " + CHIRCheckerFuncTyParamsToString(funcTy) + "\n"
            result.AddError(errMsg + hint1 + hint2)
        }
    }

    private func CheckFuncRetValue(retVal: Option<LocalVar>, retTy: Type, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (retVal.isNone()) {
            if (!retTy.IsNothing() && !retTy.IsVoid()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, you should set a return value.")
            }
            return
        }
        if (let Some(returnValue) <- retVal) {
            if (let Some(returnValueTy) <- returnValue.GetType()) {
                if (let Some(refTy) <- (returnValueTy as RefType)) {
                    if (!CHIRCheckerTypesEqual(refTy.GetBaseType(), retTy)) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, its return value is " +
                            "${returnValue.GetIdentifier()}, this value's type should be ${retTy.ToString()}&, " +
                            "but not ${returnValueTy.ToString()}.")
                    }
                } else {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, its return value is " +
                        "${returnValue.GetIdentifier()}, this value's type should be reference type.")
                }
            } else {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, its return value is " +
                    "${returnValue.GetIdentifier()}, this value doesn't have type.")
            }
        }
    }

    private func CheckCustomTypeDef(def: CustomTypeDef, result: CHIRCheckResult): Unit {
        if (!CheckCustomTypeDefIdentifier(def, result)) {
            return
        }
        CheckInstanceMemberVar(def, result)
        for (method in def.GetMethods()) {
            CheckParentCustomTypeDef(method, def, true, result)
        }
        if (let Some(extendDef) <- (def as ExtendDef)) {
            CheckExtendDef(extendDef, result)
        }
    }

    private func CheckInstanceMemberVar(def: CustomTypeDef, result: CHIRCheckResult): Unit {
        let memberVarNames = ArrayList<String>()
        for (memberVar in def.GetInstanceVars()) {
            if (memberVar.name.isEmpty()) {
                result.AddError("member var in ${def.GetIdentifier()} doesn't have name.")
                continue
            }
            if (!CHIRCheckerAddIdentifier(memberVarNames, memberVar.name)) {
                result.AddError("duplicated member var name `${memberVar.name}` in ${def.GetIdentifier()}.")
            }
            if (memberVar.ty.IsInvalid()) {
                result.AddError("member var ${memberVar.name} in ${def.GetIdentifier()} doesn't set type.")
            }
        }
    }

    private func CheckExtendDef(def: ExtendDef, result: CHIRCheckResult): Unit {
        if (def.extendedType.isNone()) {
            result.AddError("extend definition ${def.GetIdentifier()} doesn't set extended type.")
            return
        }
        if (let Some(extendedTy) <- def.extendedType) {
            if (!extendedTy.IsCustomType() && !extendedTy.IsBuiltinType()) {
                result.AddError("extend definition ${def.GetIdentifier()} extends ${extendedTy.ToString()}, " +
                    "it should be custom type or builtin type.")
            }
        }
    }

    private func CheckBlockGroup(blockGroup: BlockGroup, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!HasRule(CHIRCheckerRule.CHECK_FUNC_BODY)) {
            return
        }
        if (blockGroup.GetIdentifier().isEmpty()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, there is block group without identifier.")
            return
        }
        CheckTopLevelFunc(blockGroup.GetTopLevelFunc(), topLevelFunc, "block group", blockGroup.GetIdentifier(), result)
        if (blockGroup.GetEntryBlock().isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, there is no entry block in block group " +
                "${blockGroup.GetIdentifier()}.")
        }
        let ownerFunc = blockGroup.GetOwnerFunc()
        let ownerExpr = blockGroup.GetOwnerExpression()
        if (ownerFunc.isNone() && ownerExpr.isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, we need to set owner func or owner " +
                "expression for block group ${blockGroup.GetIdentifier()}.")
        } else if (ownerFunc.isSome() && ownerExpr.isSome()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, we can only set owner func or owner " +
                "expression, not both for block group ${blockGroup.GetIdentifier()}.")
        }
        let blocks = blockGroup.GetBlocksRef()
        if (blocks.isEmpty()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, there is no block in block group " +
                "${blockGroup.GetIdentifier()}.")
        }
        let blockIds = ArrayList<String>()
        var idx: Int64 = 0
        while (idx < blocks.size) {
            let id = blocks[idx].GetIdentifier()
            if (id.isEmpty()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, the " +
                    CHIRCheckerIndexToString(idx) + " block's id is empty.")
            } else if (!CHIRCheckerAddIdentifier(blockIds, id)) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, block's id ${id} is duplicated.")
            }
            idx++
        }
        for (block in blocks) {
            CheckBlock(block, topLevelFunc, result)
        }
    }

    private func CheckBlock(block: Block, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (block.GetIdentifier().isEmpty()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, there is block without identifier.")
            return
        }
        if (block.GetParentBlockGroup().isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, block ${block.GetIdentifier()}'s " +
                "parent block group is null.")
        }
        CheckTopLevelFunc(block.GetTopLevelFunc(), topLevelFunc, "block", block.GetIdentifier(), result)
        let exprs = block.GetExpressionsRef()
        if (HasRule(CHIRCheckerRule.EMPTY_BLOCK) && exprs.isEmpty()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, there is no expression in block " +
                "${block.GetIdentifier()}.")
        }
        if (!exprs.isEmpty()) {
            var idx: Int64 = 0
            while (idx + 1 < exprs.size) {
                if (exprs[idx].IsTerminator()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, terminator found in the middle " +
                        "of block ${block.GetIdentifier()}.")
                    break
                }
                idx++
            }
            if (!exprs[exprs.size - 1].IsTerminator()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, the last expression in block " +
                    "${block.GetIdentifier()} is not terminator.")
            } else if (let Some(term) <- exprs[exprs.size - 1].AsTerminator()) {
                CheckTerminatorJump(term, topLevelFunc, result)
            } else {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, terminator " +
                    "${exprs[exprs.size - 1].ToString(0)} is not a Terminator node.")
            }
        }
        CheckPredecessors(block, topLevelFunc, result)
        for (expr in exprs) {
            CheckExpression(expr, topLevelFunc, result)
        }
    }

    private func CheckTerminatorJump(term: Terminator, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (let Some(parentBlock) <- term.GetParentBlock()) {
            if (let Some(curGroup) <- parentBlock.GetParentBlockGroup()) {
                for (successor in term.GetSuccessors()) {
                    if (let Some(successorGroup) <- successor.GetParentBlockGroup()) {
                        if (successorGroup.nodeId != curGroup.nodeId) {
                            result.AddError("in function ${topLevelFunc.GetIdentifier()}, terminator " +
                                "${term.ToString(0)} in block group ${curGroup.GetIdentifier()} jumps to an " +
                                "unreachable block ${successor.GetIdentifier()} in block group " +
                                "${successorGroup.GetIdentifier()}")
                        }
                    } else {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, terminator ${term.ToString(0)} " +
                            "jumps to block ${successor.GetIdentifier()} without parent block group.")
                    }
                }
            }
        }
    }

    private func CheckPredecessors(block: Block, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        for (predecessor in block.GetPredecessorsRef()) {
            if (let Some(term) <- predecessor.GetTerminator()) {
                if (!CHIRCheckerContainsBlock(term.GetSuccessors(), block)) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, block ${block.GetIdentifier()}'s " +
                        "predecessor is ${predecessor.GetIdentifier()}, but block ${predecessor.GetIdentifier()}'s " +
                        "successor is not ${block.GetIdentifier()}.")
                }
            } else {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, block ${block.GetIdentifier()}'s " +
                    "predecessor ${predecessor.GetIdentifier()} doesn't have terminator.")
            }
        }
        if (let Some(term) <- block.GetTerminator()) {
            for (successor in term.GetSuccessors()) {
                if (!CHIRCheckerContainsBlock(successor.GetPredecessorsRef(), block)) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, block ${block.GetIdentifier()} " +
                        "jumps to ${successor.GetIdentifier()}, but that block doesn't record it as predecessor.")
                }
            }
        }
    }

    private func CheckTopLevelFunc(calculatedFunc: Option<Function>, realFunc: Function, valueName: String,
        valueId: String, result: CHIRCheckResult): Unit {
        if (calculatedFunc.isNone()) {
            result.AddError("in function ${realFunc.GetIdentifier()}, can't get top-level function from " +
                "${valueName} ${valueId}.")
        } else if (let Some(fn) <- calculatedFunc) {
            if (fn.nodeId != realFunc.nodeId) {
                result.AddError("in function ${realFunc.GetIdentifier()}, get a wrong top-level function from " +
                    "${valueName} ${valueId}.\n        wrong func name is ${fn.GetIdentifier()}.")
            }
        }
    }

    private func CheckExpression(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (expr.GetParentBlock().isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, expression ${expr.ToString(0)} " +
                "doesn't have parent block.")
            return
        }
        if (!expr.IsTerminator() && expr.GetResult().isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${CHIRCheckerExpressionString(expr)}`, " +
                "this expression should have result.")
            return
        }
        if (let Some(resultValue) <- expr.GetResult()) {
            if (let Some(ownerExpr) <- resultValue.GetExpr()) {
                if (ownerExpr.nodeId != expr.nodeId) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, result " +
                        "${resultValue.GetIdentifier()} is owned by a different expression.")
                }
            } else {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, result ${resultValue.GetIdentifier()} " +
                    "doesn't point back to its expression.")
            }
        }
        for (operand in expr.GetOperands()) {
            if (!ContainsExpression(operand.GetUsersRef(), expr)) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, operand ${operand.GetIdentifier()} " +
                    "is missing user ${expr.GetExprKindName()}.")
            }
        }
        for (blockGroup in expr.GetBlockGroups()) {
            if (let Some(ownerExpr) <- blockGroup.GetOwnerExpression()) {
                if (ownerExpr.nodeId != expr.nodeId) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, block group " +
                        "${blockGroup.GetIdentifier()} is owned by a different expression.")
                }
            } else {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, block group " +
                    "${blockGroup.GetIdentifier()} doesn't point back to owner expression.")
            }
        }
        match (expr.GetExprMajorKind()) {
            case ExprMajorKind.TERMINATOR => CheckTerminator(expr, topLevelFunc, result)
            case ExprMajorKind.UNARY_EXPR => CheckUnaryExpression(expr, topLevelFunc, result)
            case ExprMajorKind.BINARY_EXPR => CheckBinaryExpression(expr, topLevelFunc, result)
            case ExprMajorKind.MEMORY_EXPR => CheckMemoryExpression(expr, topLevelFunc, result)
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => CheckControlFlowExpression(expr, topLevelFunc, result)
            case ExprMajorKind.OTHERS => CheckOtherExpression(expr, topLevelFunc, result)
        }
    }

    private func CheckTerminator(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (let Some(term) <- expr.AsTerminator()) {
            match (expr.GetExprKind()) {
                case ExprKind.GOTO => CheckGoTo(term, topLevelFunc, result)
                case ExprKind.EXIT => CheckExit(term, topLevelFunc, result)
                case ExprKind.BRANCH => CheckBranch(term, topLevelFunc, result)
                case ExprKind.MULTIBRANCH => CheckMultiBranch(term, topLevelFunc, result)
                case ExprKind.RAISE_EXCEPTION => CheckRaiseException(term, topLevelFunc, result)
                case ExprKind.APPLY_WITH_EXCEPTION | ExprKind.INVOKE_WITH_EXCEPTION |
                    ExprKind.INVOKESTATIC_WITH_EXCEPTION | ExprKind.SPAWN_WITH_EXCEPTION |
                    ExprKind.TYPECAST_WITH_EXCEPTION | ExprKind.INTRINSIC_WITH_EXCEPTION |
                    ExprKind.ALLOCATE_WITH_EXCEPTION | ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION |
                    ExprKind.INT_OP_WITH_EXCEPTION => CheckWithExceptionTerminator(term, topLevelFunc, result)
                case _ => result.AddError("in function ${topLevelFunc.GetIdentifier()}, in " +
                    "`${CHIRCheckerExpressionString(expr)}`, find unrecongnized ExprKind `${expr.GetExprKindName()}`.")
            }
        } else {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, ${expr.ToString(0)} is terminator kind " +
                "but not a Terminator node.")
        }
    }

    private func CheckGoTo(term: Terminator, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        CheckOperandNumEqual(0, term, topLevelFunc, result)
        CheckSuccessorNumEqual(1, term, topLevelFunc, result)
        ShouldNotHaveResult(term, topLevelFunc, result)
    }

    private func CheckExit(term: Terminator, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        CheckOperandNumIn(term, [0, 1], topLevelFunc, result)
        CheckSuccessorNumEqual(0, term, topLevelFunc, result)
        ShouldNotHaveResult(term, topLevelFunc, result)
        if (term.GetNumOfOperands() == 1) {
            if (let Some(retTy) <- topLevelFunc.GetReturnType()) {
                let value = term.GetOperand(0)
                if (let Some(valueTy) <- value.GetType()) {
                    if (!CHIRCheckerTypeIsExpected(valueTy, retTy)) {
                        TypeCheckError(term, value, retTy.ToString(), topLevelFunc, result)
                    }
                }
            }
        }
    }

    private func CheckBranch(term: Terminator, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        ShouldNotHaveResult(term, topLevelFunc, result)
        if (!CheckOperandNumEqual(1, term, topLevelFunc, result)) {
            return
        }
        if (!CheckSuccessorNumEqual(2, term, topLevelFunc, result)) {
            return
        }
        if (let Some(condTy) <- term.GetOperand(0).GetType()) {
            if (!condTy.IsBoolean() && !condTy.IsNothing()) {
                TypeCheckError(term, term.GetOperand(0), "Bool", topLevelFunc, result)
            }
        }
    }

    private func CheckMultiBranch(term: Terminator, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        ShouldNotHaveResult(term, topLevelFunc, result)
        if (!CheckOperandNumAtLeast(1, term, topLevelFunc, result)) {
            return
        }
        if (!CheckSuccessorNumAtLeast(2, term, topLevelFunc, result)) {
            return
        }
        if (let Some(condTy) <- term.GetOperand(0).GetType()) {
            if (!condTy.IsInteger()) {
                TypeCheckError(term, term.GetOperand(0), "Int", topLevelFunc, result)
            }
        }
    }

    private func CheckRaiseException(term: Terminator, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        ShouldNotHaveResult(term, topLevelFunc, result)
        if (!CheckOperandNumAtLeast(1, term, topLevelFunc, result)) {
            return
        }
        let exceptionValue = term.GetOperand(0)
        if (let Some(exceptionType) <- exceptionValue.GetType()) {
            let strippedTy = exceptionType.StripAllRefs()
            if (!exceptionType.IsRef() && !exceptionType.IsGeneric() && !strippedTy.IsClass()) {
                TypeCheckError(term, exceptionValue, "Class& or Generic", topLevelFunc, result)
            }
        }
    }

    private func CheckWithExceptionTerminator(term: Terminator, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (!CheckHaveResult(term, topLevelFunc, result)) {
            return
        }
        CheckOperandNumAtLeast(1, term, topLevelFunc, result)
        CheckSuccessorNumEqual(2, term, topLevelFunc, result)
    }

    private func CheckUnaryExpression(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        let operand = expr.GetOperand(0)
        if (let Some(operandTy) <- operand.GetType()) {
            if (operandTy.IsNothing()) {
                return
            }
            if (let Some(resultTy) <- expr.GetResultType()) {
                match (expr.GetExprKind()) {
                    case ExprKind.NEG =>
                        if (!operandTy.IsNumeric()) {
                            TypeCheckError(expr, operand, "Int or Float", topLevelFunc, result)
                        }
                        CheckResultType(expr, resultTy, operandTy, topLevelFunc, result)
                    case ExprKind.NOT =>
                        if (!operandTy.IsBoolean()) {
                            TypeCheckError(expr, operand, "Bool", topLevelFunc, result)
                        }
                        if (!resultTy.IsBoolean()) {
                            TypeCheckResultError(expr, "Bool", topLevelFunc, result)
                        }
                    case ExprKind.BITNOT =>
                        if (!operandTy.IsInteger()) {
                            TypeCheckError(expr, operand, "Int", topLevelFunc, result)
                        }
                        CheckResultType(expr, resultTy, operandTy, topLevelFunc, result)
                    case _ => result.AddError("in function ${topLevelFunc.GetIdentifier()}, in " +
                        "`${CHIRCheckerExpressionString(expr)}`, find unrecongnized ExprKind " +
                        "`${expr.GetExprKindName()}`.")
                }
            }
        }
    }

    private func CheckBinaryExpression(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(2, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        let left = expr.GetOperand(0)
        let right = expr.GetOperand(1)
        if (let Some(leftTy) <- left.GetType()) {
            if (let Some(rightTy) <- right.GetType()) {
                if (let Some(resultTy) <- expr.GetResultType()) {
                    let kind = expr.GetExprKind()
                    if (leftTy.IsNothing() || rightTy.IsNothing()) {
                        return
                    }
                    if (CHIRCheckerIsCalculExpr(kind)) {
                        CheckCalculExpression(expr, left, right, leftTy, rightTy, resultTy, topLevelFunc, result)
                    } else if (kind == ExprKind.EXP) {
                        CheckExponentiationExpression(expr, left, right, leftTy, rightTy, resultTy, topLevelFunc, result)
                    } else if (CHIRCheckerIsBitExpr(kind)) {
                        CheckBitExpression(expr, left, right, leftTy, rightTy, topLevelFunc, result)
                    } else if (CHIRCheckerIsCompareExpr(kind)) {
                        CheckCompareExpression(expr, right, leftTy, rightTy, resultTy, topLevelFunc, result)
                    } else if (kind == ExprKind.AND || kind == ExprKind.OR) {
                        CheckLogicExpression(expr, left, right, leftTy, rightTy, resultTy, topLevelFunc, result)
                    }
                }
            }
        }
    }

    private func CheckCalculExpression(expr: Expression, left: Value, right: Value, leftTy: Type, rightTy: Type,
        resultTy: Type, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (expr.GetExprKind() == ExprKind.MOD) {
            if (!leftTy.IsInteger()) {
                TypeCheckError(expr, left, "Int or UInt", topLevelFunc, result)
            }
            if (!rightTy.IsInteger()) {
                TypeCheckError(expr, right, "Int or UInt", topLevelFunc, result)
            }
        } else {
            if (!leftTy.IsNumeric()) {
                TypeCheckError(expr, left, "numeric", topLevelFunc, result)
            }
            if (!rightTy.IsNumeric()) {
                TypeCheckError(expr, right, "numeric", topLevelFunc, result)
            }
        }
        if (!CHIRCheckerTypesEqual(leftTy, rightTy)) {
            TypeCheckError(expr, right, leftTy.ToString(), topLevelFunc, result)
        } else {
            CheckResultType(expr, resultTy, leftTy, topLevelFunc, result)
        }
    }

    private func CheckExponentiationExpression(expr: Expression, left: Value, right: Value, leftTy: Type, rightTy: Type,
        resultTy: Type, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        let leftKind = leftTy.GetTypeKind()
        let rightKind = rightTy.GetTypeKind()
        if (leftKind != TypeKind.TYPE_INT64 && leftKind != TypeKind.TYPE_FLOAT64) {
            TypeCheckError(expr, left, "Int64 or Float64", topLevelFunc, result)
            return
        }
        if (leftKind == TypeKind.TYPE_INT64) {
            if (rightKind != TypeKind.TYPE_UINT64) {
                TypeCheckError(expr, right, "UInt64", topLevelFunc, result)
            }
            if (resultTy.GetTypeKind() != TypeKind.TYPE_INT64) {
                TypeCheckResultError(expr, "Int64", topLevelFunc, result)
            }
        } else if (leftKind == TypeKind.TYPE_FLOAT64) {
            if (rightKind != TypeKind.TYPE_INT64 && rightKind != TypeKind.TYPE_FLOAT64) {
                TypeCheckError(expr, right, "Int64 or Float64", topLevelFunc, result)
            }
            if (resultTy.GetTypeKind() != TypeKind.TYPE_FLOAT64) {
                TypeCheckResultError(expr, "Float64", topLevelFunc, result)
            }
        }
    }

    private func CheckBitExpression(expr: Expression, left: Value, right: Value, leftTy: Type, rightTy: Type,
        topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!leftTy.IsInteger()) {
            TypeCheckError(expr, left, "Int", topLevelFunc, result)
        }
        if (!rightTy.IsInteger()) {
            TypeCheckError(expr, right, "Int", topLevelFunc, result)
        }
    }

    private func CheckCompareExpression(expr: Expression, right: Value, leftTy: Type, rightTy: Type, resultTy: Type,
        topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CHIRCheckerTypesEqual(leftTy, rightTy)) {
            TypeCheckError(expr, right, leftTy.ToString(), topLevelFunc, result)
        }
        if (!resultTy.IsBoolean()) {
            TypeCheckResultError(expr, "Bool", topLevelFunc, result)
        }
    }

    private func CheckLogicExpression(expr: Expression, left: Value, right: Value, leftTy: Type, rightTy: Type,
        resultTy: Type, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!leftTy.IsBoolean()) {
            TypeCheckError(expr, left, "Bool", topLevelFunc, result)
        }
        if (!rightTy.IsBoolean()) {
            TypeCheckError(expr, right, "Bool", topLevelFunc, result)
        }
        if (!resultTy.IsBoolean()) {
            TypeCheckResultError(expr, "Bool", topLevelFunc, result)
        }
    }

    private func CheckMemoryExpression(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        match (expr.GetExprKind()) {
            case ExprKind.ALLOCATE =>
                CheckOperandNumEqual(0, expr, topLevelFunc, result)
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.LOAD => CheckLoad(expr, topLevelFunc, result)
            case ExprKind.STORE => CheckStore(expr, topLevelFunc, result)
            case ExprKind.GET_ELEMENT_REF | ExprKind.GET_ELEMENT_BY_NAME =>
                CheckOperandNumAtLeast(1, expr, topLevelFunc, result)
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.STORE_ELEMENT_REF | ExprKind.STORE_ELEMENT_BY_NAME =>
                CheckOperandNumAtLeast(2, expr, topLevelFunc, result)
                CheckUnitResult(expr, topLevelFunc, result)
            case _ => result.AddError("in function ${topLevelFunc.GetIdentifier()}, in " +
                "`${CHIRCheckerExpressionString(expr)}`, find unrecongnized ExprKind `${expr.GetExprKindName()}`.")
        }
    }

    private func CheckLoad(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        let location = expr.GetOperand(0)
        if (let Some(locationTy) <- location.GetType()) {
            if (let Some(resultTy) <- expr.GetResultType()) {
                if (let Some(refTy) <- (locationTy as RefType)) {
                    if (!CHIRCheckerTypesEqual(refTy.GetBaseType(), resultTy)) {
                        TypeCheckResultError(expr, refTy.GetBaseType().ToString(), topLevelFunc, result)
                    }
                } else {
                    TypeCheckError(expr, location, resultTy.ToString() + "&", topLevelFunc, result)
                }
            }
        }
    }

    private func CheckStore(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(2, expr, topLevelFunc, result)) {
            return
        }
        let location = expr.GetOperand(0)
        let value = expr.GetOperand(1)
        if (let Some(locationTy) <- location.GetType()) {
            if (let Some(valueTy) <- value.GetType()) {
                if (let Some(refTy) <- (locationTy as RefType)) {
                    if (!CHIRCheckerTypeIsExpected(valueTy, refTy.GetBaseType())) {
                        TypeCheckError(expr, value, refTy.GetBaseType().ToString(), topLevelFunc, result)
                    }
                } else {
                    TypeCheckError(expr, location, locationTy.ToString() + "&", topLevelFunc, result)
                }
            }
        }
        CheckUnitResult(expr, topLevelFunc, result)
    }

    private func CheckControlFlowExpression(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (expr.GetExprKind() == ExprKind.LAMBDA) {
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                if (let Some(body) <- lambdaExpr.GetBody()) {
                    CheckBlockGroup(body, topLevelFunc, result)
                    if (let Some(funcTy) <- lambdaExpr.GetResultType()) {
                        CheckFuncType(funcTy, lambdaExpr, topLevelFunc, result)
                    }
                } else {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, lambda doesn't have body.")
                }
            }
            return
        }
        CheckHaveResult(expr, topLevelFunc, result)
    }

    private func CheckOtherExpression(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        match (expr.GetExprKind()) {
            case ExprKind.CONSTANT => CheckConstant(expr, topLevelFunc, result)
            case ExprKind.DEBUGEXPR =>
                CheckOperandNumEqual(1, expr, topLevelFunc, result)
                CheckUnitResult(expr, topLevelFunc, result)
            case ExprKind.TUPLE => CheckTuple(expr, topLevelFunc, result)
            case ExprKind.VARRAY => CheckVArray(expr, topLevelFunc, result)
            case ExprKind.FIELD | ExprKind.FIELD_BY_NAME | ExprKind.GET_EXCEPTION =>
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.APPLY | ExprKind.INVOKE | ExprKind.INVOKESTATIC => CheckCallLike(expr, topLevelFunc, result)
            case ExprKind.INSTANCEOF =>
                CheckOperandNumEqual(1, expr, topLevelFunc, result)
                CheckBoolResult(expr, topLevelFunc, result)
            case ExprKind.TYPECAST | ExprKind.BOX | ExprKind.UNBOX | ExprKind.TRANSFORM_TO_GENERIC |
                ExprKind.TRANSFORM_TO_CONCRETE | ExprKind.UNBOX_TO_REF =>
                CheckOperandNumEqual(1, expr, topLevelFunc, result)
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.RAW_ARRAY_ALLOCATE | ExprKind.RAW_ARRAY_INIT_BY_VALUE | ExprKind.VARRAY_BUILDER |
                ExprKind.INTRINSIC | ExprKind.SPAWN | ExprKind.GET_RTTI | ExprKind.GET_RTTI_STATIC =>
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.RAW_ARRAY_LITERAL_INIT =>
                CheckOperandNumAtLeast(1, expr, topLevelFunc, result)
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.GET_INSTANTIATE_VALUE => CheckGetInstantiateValue(expr, topLevelFunc, result)
            case _ => result.AddError("in function ${topLevelFunc.GetIdentifier()}, in " +
                "`${CHIRCheckerExpressionString(expr)}`, find unrecongnized ExprKind `${expr.GetExprKindName()}`.")
        }
    }

    private func CheckConstant(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(0, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(constant) <- (expr as Constant)) {
            if (let Some(resultTy) <- expr.GetResultType()) {
                let literal = constant.literal
                if (literal.IsNullLit()) {
                    return
                }
                if (literal.IsBoolLit() && !resultTy.IsBoolean()) {
                    TypeCheckResultError(expr, "Bool", topLevelFunc, result)
                } else if (literal.IsIntLit() && !resultTy.IsInteger()) {
                    TypeCheckResultError(expr, "Int", topLevelFunc, result)
                } else if (literal.IsFloatLit() && !resultTy.IsFloat()) {
                    TypeCheckResultError(expr, "Float", topLevelFunc, result)
                } else if (literal.IsRuneLit() && !resultTy.IsRune()) {
                    TypeCheckResultError(expr, "Rune", topLevelFunc, result)
                } else if (literal.IsStringLit() && !resultTy.IsString()) {
                    TypeCheckResultError(expr, "String", topLevelFunc, result)
                } else if (literal.IsUnitLit() && !resultTy.IsUnit()) {
                    TypeCheckResultError(expr, "Unit", topLevelFunc, result)
                }
            }
        }
    }

    private func CheckTuple(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumAtLeast(1, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (resultTy.IsEnum()) {
                CheckEnumTuple(expr, resultTy, topLevelFunc, result)
            } else if (resultTy.IsTuple()) {
                CheckNormalTuple(expr, resultTy, topLevelFunc, result)
            } else if (resultTy.IsStruct()) {
                CheckStructTuple(expr, resultTy, topLevelFunc, result)
            } else {
                TypeCheckResultError(expr, "Enum, Tuple or Struct", topLevelFunc, result)
            }
        }
    }

    private func CheckEnumTuple(expr: Expression, resultTy: Type, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        let operandsNum = expr.GetNumOfOperands()
        if (operandsNum == 0) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, must have one operand in `" +
                CHIRCheckerExpressionString(expr) + "` at least, and the 1st operand's type is UInt32 or Bool.")
            return
        }
        let selector = expr.GetOperand(0)
        if (let Some(selectorTy) <- selector.GetType()) {
            if (!CHIRCheckerIsEnumSelectorType(selectorTy)) {
                TypeCheckError(expr, selector, "UInt32 or Bool", topLevelFunc, result)
                return
            }
        }
        let maybeCtorIndex = CHIRCheckerConstEnumSelectorIndex(selector)
        if (maybeCtorIndex.isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, the 1st operand in `" +
                CHIRCheckerExpressionString(expr) + "` must be from Constant UInt32 or Constant Bool.")
            return
        }
        if (operandsNum == 1) {
            return
        }
        if (let Some(enumTy) <- (resultTy as EnumType)) {
            if (let Some(enumDef) <- (enumTy.GetCustomTypeDef() as EnumDef)) {
                if (let Some(ctorIndex) <- maybeCtorIndex) {
                    let ctors = enumDef.GetCtors()
                    if (ctorIndex < 0 || ctorIndex >= ctors.size) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, index out of range, in `" +
                            CHIRCheckerExpressionString(expr) + "` its enum constructor's number is ${ctors.size} " +
                            "but the index is ${ctorIndex}.")
                        return
                    }
                    let payloadTypes = ctors[ctorIndex].payloadTypes
                    if (operandsNum - 1 != payloadTypes.size) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                            "${payloadTypes.size} parameter(s) in the ${ctorIndex}-th constructor, but " +
                            "${operandsNum - 1} arguments are provided in `" + CHIRCheckerExpressionString(expr) + "`.")
                        return
                    }
                    var idx: Int64 = 1
                    while (idx < operandsNum) {
                        let operand = expr.GetOperand(idx)
                        if (let Some(operandTy) <- operand.GetType()) {
                            let expectedTy = payloadTypes[idx - 1]
                            if (!CHIRCheckerTypeIsExpected(operandTy, expectedTy)) {
                                result.AddError("in function ${topLevelFunc.GetIdentifier()}, type mismatched, the " +
                                    "${idx - 1}-th parameter type is ${expectedTy.ToString()}, but " +
                                    "${operand.GetIdentifier()}'s type is ${operandTy.ToString()} in `" +
                                    CHIRCheckerExpressionString(expr) + "`.")
                            }
                        }
                        idx++
                    }
                }
            }
        }
    }

    private func CheckNormalTuple(expr: Expression, resultTy: Type, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (let Some(tupleTy) <- (resultTy as TupleType)) {
            let elementTypes = tupleTy.GetTypeArgsRef()
            let operandsNum = expr.GetNumOfOperands()
            if (operandsNum != elementTypes.size) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                    "${elementTypes.size} element(s) in the tuple type `${resultTy.ToString()}`, but ${operandsNum} " +
                    "operand(s) are provided in `" + CHIRCheckerExpressionString(expr) + "`.")
                return
            }
            var idx: Int64 = 0
            while (idx < elementTypes.size) {
                let operand = expr.GetOperand(idx)
                if (let Some(operandTy) <- operand.GetType()) {
                    let expectedTy = elementTypes[idx]
                    if (!CHIRCheckerTypeIsExpected(operandTy, expectedTy)) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, type mismatched, the ${idx}-th " +
                            "element type in tuple type `${resultTy.ToString()}` is ${expectedTy.ToString()}, but " +
                            "${operand.GetIdentifier()}'s type is ${operandTy.ToString()} in `" +
                            CHIRCheckerExpressionString(expr) + "`.")
                    }
                }
                idx++
            }
        }
    }

    private func CheckStructTuple(expr: Expression, resultTy: Type, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (let Some(structTy) <- (resultTy as StructType)) {
            if (let Some(structDef) <- (structTy.GetCustomTypeDef() as StructDef)) {
                let memberVars = structDef.GetInstanceVars()
                let operandsNum = expr.GetNumOfOperands()
                if (operandsNum != memberVars.size) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                        "${memberVars.size} instance member var(s) in the struct ${structDef.GetIdentifier()}, but " +
                        "${operandsNum} operand(s) are provided in `" + CHIRCheckerExpressionString(expr) + "`.")
                    return
                }
                var idx: Int64 = 0
                while (idx < memberVars.size) {
                    let operand = expr.GetOperand(idx)
                    if (let Some(operandTy) <- operand.GetType()) {
                        let memberTy = memberVars[idx].ty
                        if (!CHIRCheckerTypeIsExpected(operandTy, memberTy)) {
                            result.AddError("in function ${topLevelFunc.GetIdentifier()}, type mismatched, the " +
                                "${idx}-th member var type in struct ${structDef.GetIdentifier()} is " +
                                "${memberTy.ToString()}, but ${operand.GetIdentifier()}'s type is " +
                                "${operandTy.ToString()} in `" + CHIRCheckerExpressionString(expr) + "`.")
                        }
                    }
                    idx++
                }
            }
        }
    }

    private func CheckVArray(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (let Some(varrayTy) <- (resultTy as VArrayType)) {
                let elementTy = varrayTy.GetElementType()
                for (operand in expr.GetOperands()) {
                    if (let Some(operandTy) <- operand.GetType()) {
                        if (!CHIRCheckerTypeIsExpected(operandTy, elementTy)) {
                            TypeCheckError(expr, operand, elementTy.ToString(), topLevelFunc, result)
                        }
                    }
                }
            } else {
                TypeCheckResultError(expr, "VArray", topLevelFunc, result)
            }
        }
    }

    private func CheckCallLike(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumAtLeast(1, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        let callee = expr.GetOperand(0)
        if (let Some(calleeTy) <- callee.GetType()) {
            if (let Some(funcTy) <- (calleeTy as FuncType)) {
                let argCount = expr.GetNumOfOperands() - 1
                if (!funcTy.HasVarArg() && argCount != funcTy.GetNumOfParams()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                        "${argCount} arg(s) in function call `${CHIRCheckerExpressionString(expr)}`, but there are " +
                        "${funcTy.GetNumOfParams()} parameter(s) in function declare.")
                    return
                }
                var idx: Int64 = 0
                while (idx < argCount && idx < funcTy.GetNumOfParams()) {
                    let arg = expr.GetOperand(idx + 1)
                    if (let Some(argTy) <- arg.GetType()) {
                        let paramTy = funcTy.GetParamType(idx)
                        if (!CHIRCheckerTypeIsExpected(argTy, paramTy)) {
                            TypeCheckError(expr, arg, paramTy.ToString(), topLevelFunc, result)
                        }
                    }
                    idx++
                }
                if (let Some(resultTy) <- expr.GetResultType()) {
                    if (!CHIRCheckerTypeIsExpected(funcTy.GetReturnType(), resultTy)) {
                        TypeCheckResultError(expr, funcTy.GetReturnType().ToString(), topLevelFunc, result)
                    }
                }
            } else {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, callee of `" +
                    "${CHIRCheckerExpressionString(expr)}` should have func type, not ${calleeTy.ToString()}.")
            }
        }
        if (callee.TestAttr(Attribute.ABSTRACT)) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, callee of `" +
                "${CHIRCheckerExpressionString(expr)}` can't be abstract.")
        }
    }

    private func CheckGetInstantiateValue(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (HasRule(CHIRCheckerRule.GET_INSTANTIATE_VALUE_SHOULD_GONE)) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in " +
                "`${CHIRCheckerExpressionString(expr)}`, `GetInstantiateValue` should be removed now, " +
                "it can't be seen in CodeGen Stage.")
            return
        }
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        if (let Some(funcTy) <- expr.GetOperand(0).GetType()) {
            if (!funcTy.IsFunc()) {
                TypeCheckError(expr, expr.GetOperand(0), "Function", topLevelFunc, result)
            }
        }
    }

    private func CheckHaveResult(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Bool {
        if (expr.GetResult().isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${CHIRCheckerExpressionString(expr)}`, " +
                "this expression should have result.")
            return false
        }
        return true
    }

    private func ShouldNotHaveResult(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (expr.GetResult().isSome()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${CHIRCheckerExpressionString(expr)}`, " +
                "this terminator shouldn't have result.")
        }
    }

    private func CheckUnitResult(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (!resultTy.IsUnit()) {
                TypeCheckResultError(expr, "Unit", topLevelFunc, result)
            }
        }
    }

    private func CheckBoolResult(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (!resultTy.IsBoolean()) {
                TypeCheckResultError(expr, "Bool", topLevelFunc, result)
            }
        }
    }

    private func CheckResultType(expr: Expression, resultTy: Type, expectedTy: Type, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (!CHIRCheckerTypesEqual(resultTy, expectedTy)) {
            TypeCheckResultError(expr, expectedTy.ToString(), topLevelFunc, result)
        }
    }

    private func TypeCheckResultError(expr: Expression, expectedType: String, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (let Some(resultValue) <- expr.GetResult()) {
            TypeCheckError(expr, resultValue, expectedType, topLevelFunc, result)
        }
    }

    private func TypeCheckError(expr: Expression, value: Value, expectedType: String, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        let actualType = if (let Some(valueTy) <- value.GetType()) { valueTy.ToString() } else { "<none>" }
        result.AddError("in function ${topLevelFunc.GetIdentifier()}, value ${value.GetIdentifier()} used in " +
            "${CHIRCheckerExpressionString(expr)} has type ${actualType}, but ${expectedType} type is expected.")
    }

    private func CheckOperandNumEqual(expectedNum: Int64, expr: Expression, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = expr.GetNumOfOperands()
        if (expectedNum != realNum) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${CHIRCheckerExpressionString(expr)}`, " +
                "expect ${expectedNum} operand(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func CheckOperandNumAtLeast(expectedNum: Int64, expr: Expression, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = expr.GetNumOfOperands()
        if (expectedNum > realNum) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${CHIRCheckerExpressionString(expr)}`, " +
                "expect at least ${expectedNum} operand(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func CheckOperandNumIn(expr: Expression, expectedNums: Array<Int64>, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = expr.GetNumOfOperands()
        for (expected in expectedNums) {
            if (expected == realNum) {
                return true
            }
        }
        result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${CHIRCheckerExpressionString(expr)}`, " +
            "expect " + CHIRCheckerIntArrayToString(expectedNums) + " operand(s), but there are ${realNum} in fact.")
        return false
    }

    private func CheckSuccessorNumEqual(expectedNum: Int64, term: Terminator, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = term.GetSuccessors().size
        if (expectedNum != realNum) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${CHIRCheckerExpressionString(term)}`, " +
                "expect ${expectedNum} successor(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func CheckSuccessorNumAtLeast(expectedNum: Int64, term: Terminator, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = term.GetSuccessors().size
        if (expectedNum > realNum) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${CHIRCheckerExpressionString(term)}`, " +
                "expect at least ${expectedNum} successor(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func CheckLocalId(blockGroup: BlockGroup, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        let allIds = ArrayList<String>()
        let duplicatedLocalIds = ArrayList<String>()
        let exprResWithoutId = ArrayList<Expression>()
        for (param in topLevelFunc.GetParams()) {
            let id = param.GetIdentifier()
            if (!CHIRCheckerAddIdentifier(allIds, id)) {
                CHIRCheckerAddUniqueString(duplicatedLocalIds, id)
            }
        }
        CheckLocalIdInBlockGroup(blockGroup, allIds, duplicatedLocalIds, exprResWithoutId)
        if (!duplicatedLocalIds.isEmpty()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, there are duplicated local id: " +
                JoinStrings(duplicatedLocalIds, ", "))
        }
        for (expr in exprResWithoutId) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, the result of expression " +
                "${expr.ToString(0)} doesn't have identifier.")
        }
    }

    private func CheckLocalIdInBlockGroup(blockGroup: BlockGroup, allIds: ArrayList<String>,
        duplicatedLocalIds: ArrayList<String>, exprResWithoutId: ArrayList<Expression>): Unit {
        for (block in blockGroup.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (let Some(resultValue) <- expr.GetResult()) {
                    let id = resultValue.GetIdentifier()
                    if (id.isEmpty()) {
                        exprResWithoutId.add(expr)
                    } else if (!CHIRCheckerAddIdentifier(allIds, id)) {
                        CHIRCheckerAddUniqueString(duplicatedLocalIds, id)
                    }
                }
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    for (param in lambdaExpr.GetParams()) {
                        let id = param.GetIdentifier()
                        if (!CHIRCheckerAddIdentifier(allIds, id)) {
                            CHIRCheckerAddUniqueString(duplicatedLocalIds, id)
                        }
                    }
                }
                for (nestedGroup in expr.GetBlockGroups()) {
                    CheckLocalIdInBlockGroup(nestedGroup, allIds, duplicatedLocalIds, exprResWithoutId)
                }
            }
        }
    }

    private func CheckUnreachableOpAndGenericTyInFuncBody(blockGroup: BlockGroup, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        let reachableValues = ArrayList<Value>()
        let reachableGenericTypes = ArrayList<GenericType>()
        CheckUnreachableOpAndGenericTyInBG(blockGroup, topLevelFunc, reachableValues, reachableGenericTypes, result)
    }

    private func CheckUnreachableOpAndGenericTyInBG(blockGroup: BlockGroup, topLevelFunc: Function,
        reachableValues: ArrayList<Value>, reachableGenericTypes: ArrayList<GenericType>,
        result: CHIRCheckResult): Unit {
        let valueSize = reachableValues.size
        let typeSize = reachableGenericTypes.size
        if (let Some(ownerExpr) <- blockGroup.GetOwnerExpression()) {
            if (let Some(lambdaExpr) <- (ownerExpr as Lambda)) {
                for (param in lambdaExpr.GetParams()) {
                    reachableValues.add(param)
                    if (let Some(paramTy) <- param.GetType()) {
                        if (!CHIRCheckerGenericTypeIsInContainer(paramTy, reachableGenericTypes)) {
                            result.AddError("in function ${topLevelFunc.GetIdentifier()}, generic type " +
                                "${param.ToString(0)}is unreachable, the type is parameter in lambda.")
                        }
                    }
                }
            }
        } else if (let Some(fn) <- blockGroup.GetOwnerFunc()) {
            if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
                for (genericTy in parentDef.genericTypeParams) {
                    reachableGenericTypes.add(genericTy)
                }
            }
            for (param in fn.GetParams()) {
                reachableValues.add(param)
                if (let Some(paramTy) <- param.GetType()) {
                    if (!CHIRCheckerGenericTypeIsInContainer(paramTy, reachableGenericTypes)) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, generic type " +
                            "${param.ToString(0)}is unreachable, the type is parameter in function " +
                            "${fn.GetIdentifier()}.")
                    }
                }
            }
        }
        if (let Some(entryBlock) <- blockGroup.GetEntryBlock()) {
            let visitedBlocks = ArrayList<Int64>()
            CheckUnreachableOpAndGenericTyInBlock(entryBlock, topLevelFunc, reachableValues, reachableGenericTypes,
                visitedBlocks, result)
        }
        CHIRCheckerTrimValues(reachableValues, valueSize)
        CHIRCheckerTrimGenericTypes(reachableGenericTypes, typeSize)
    }

    private func CheckUnreachableOpAndGenericTyInBlock(block: Block, topLevelFunc: Function,
        reachableValues: ArrayList<Value>, reachableGenericTypes: ArrayList<GenericType>,
        visitedBlocks: ArrayList<Int64>, result: CHIRCheckResult): Unit {
        if (CHIRCheckerContainsId(visitedBlocks, block.nodeId)) {
            return
        }
        visitedBlocks.add(block.nodeId)
        let valueSize = reachableValues.size
        for (expr in block.GetExpressionsRef()) {
            CheckUnreachableOpAndGenericTyInExpr(expr, topLevelFunc, reachableValues, reachableGenericTypes, result)
            if (let Some(resultValue) <- expr.GetResult()) {
                reachableValues.add(resultValue)
            }
            for (nestedGroup in expr.GetBlockGroups()) {
                CheckUnreachableOpAndGenericTyInBG(nestedGroup, topLevelFunc, reachableValues, reachableGenericTypes,
                    result)
            }
            if (let Some(term) <- expr.AsTerminator()) {
                for (successor in term.GetSuccessors()) {
                    CheckUnreachableOpAndGenericTyInBlock(successor, topLevelFunc, reachableValues,
                        reachableGenericTypes, visitedBlocks, result)
                }
            }
        }
        CHIRCheckerTrimValues(reachableValues, valueSize)
    }

    private func CheckUnreachableOpAndGenericTyInExpr(expr: Expression, topLevelFunc: Function,
        reachableValues: ArrayList<Value>, reachableGenericTypes: ArrayList<GenericType>,
        result: CHIRCheckResult): Unit {
        for (operand in expr.GetOperands()) {
            if (operand.IsLiteral() || operand.IsGlobal()) {
                continue
            }
            if (!CHIRCheckerContainsValue(reachableValues, operand)) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, ${operand.GetIdentifier()} in " +
                    "${expr.ToString(0)} is unreachable.")
            }
        }
        if (let Some(resultValue) <- expr.GetResult()) {
            if (let Some(resultTy) <- resultValue.GetType()) {
                if (!CHIRCheckerGenericTypeIsInContainer(resultTy, reachableGenericTypes)) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, generic type " +
                        "${resultTy.ToString()} is unreachable, the type is from result in expression " +
                        "${expr.ToString(0)}.")
                }
            }
        }
    }
}

public func CHIRCheckerDefaultRules(): ArrayList<CHIRCheckerRule> {
    let out = ArrayList<CHIRCheckerRule>()
    out.add(CHIRCheckerRule.CHECK_FUNC_BODY)
    out.add(CHIRCheckerRule.EMPTY_BLOCK)
    out.add(CHIRCheckerRule.RETURN_TYPE_NEED_BE_VOID)
    return out
}

private func CHIRCheckerContainsRule(values: ArrayList<CHIRCheckerRule>, rule: CHIRCheckerRule): Bool {
    for (value in values) {
        if (value == rule) {
            return true
        }
    }
    return false
}

private func CHIRCheckerIdentifierWithoutPrefix(identifier: String): String {
    if (identifier.size > 0) {
        return identifier[1..]
    }
    return identifier
}

private func CHIRCheckerAddIdentifier(values: ArrayList<String>, identifier: String): Bool {
    if (CHIRCheckerContainsString(values, identifier)) {
        return false
    }
    values.add(identifier)
    return true
}

private func CHIRCheckerAddUniqueString(values: ArrayList<String>, value: String): Unit {
    if (!CHIRCheckerContainsString(values, value)) {
        values.add(value)
    }
}

private func CHIRCheckerContainsString(values: ArrayList<String>, value: String): Bool {
    for (item in values) {
        if (item == value) {
            return true
        }
    }
    return false
}

private func CHIRCheckerContainsId(values: ArrayList<Int64>, value: Int64): Bool {
    for (item in values) {
        if (item == value) {
            return true
        }
    }
    return false
}

private func CHIRCheckerContainsValue(values: ArrayList<Value>, value: Value): Bool {
    for (item in values) {
        if (item.nodeId == value.nodeId) {
            return true
        }
    }
    return false
}

private func CHIRCheckerContainsBlock(values: ArrayList<Block>, value: Block): Bool {
    for (item in values) {
        if (item.nodeId == value.nodeId) {
            return true
        }
    }
    return false
}

private func CHIRCheckerTrimValues(values: ArrayList<Value>, size: Int64): Unit {
    while (values.size > size) {
        values.remove(at: values.size - 1)
    }
}

private func CHIRCheckerTrimGenericTypes(values: ArrayList<GenericType>, size: Int64): Unit {
    while (values.size > size) {
        values.remove(at: values.size - 1)
    }
}

private func CHIRCheckerIndexToString(index: Int64): String {
    let unitDigit = index % 10
    let suffix = if (index > 10 && index < 20) {
        "th"
    } else if (unitDigit == 1) {
        "st"
    } else if (unitDigit == 2) {
        "nd"
    } else if (unitDigit == 3) {
        "rd"
    } else {
        "th"
    }
    return "${index}" + suffix
}

private func CHIRCheckerIntArrayToString(values: Array<Int64>): String {
    var out = "{"
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            out += ", "
        }
        out += "${values[idx]}"
        idx++
    }
    return out + "}"
}

private func CHIRCheckerParamsToString(params: ArrayList<Parameter>): String {
    let parts = ArrayList<String>()
    for (param in params) {
        if (let Some(paramTy) <- param.GetType()) {
            parts.add(paramTy.ToString())
        } else {
            parts.add("<none>")
        }
    }
    return "(" + JoinStrings(parts, ", ") + ")"
}

private func CHIRCheckerFuncTyParamsToString(funcTy: FuncType): String {
    let parts = ArrayList<String>()
    var idx: Int64 = 0
    while (idx < funcTy.GetNumOfParams()) {
        parts.add(funcTy.GetParamType(idx).ToString())
        idx++
    }
    return "(" + JoinStrings(parts, ", ") + ")"
}

private func CHIRCheckerExpressionString(expr: Expression): String {
    if (let Some(lambdaExpr) <- (expr as Lambda)) {
        if (let Some(resultValue) <- lambdaExpr.GetResult()) {
            return "lambda " + resultValue.GetIdentifier()
        }
        return "lambda"
    }
    if (let Some(resultValue) <- expr.GetResult()) {
        return resultValue.ToString(0)
    }
    return expr.ToString(0)
}

private func CHIRCheckerTypesEqual(left: Type, right: Type): Bool {
    return left.IsEqual(right)
}

private func CHIRCheckerTypeIsExpected(srcType: Type, dstType: Type): Bool {
    if (CHIRCheckerTypesEqual(srcType, dstType)) {
        return true
    }
    if (srcType.IsNothing()) {
        return true
    }
    if (srcType.IsValueType() && dstType.StripAllRefs().IsClass()) {
        return false
    }
    return srcType.ToString() == dstType.ToString()
}

private func CHIRCheckerIsEnumSelectorType(ty: Type): Bool {
    return ty.IsBoolean() || ty.GetTypeKind() == TypeKind.TYPE_UINT32
}

private func CHIRCheckerConstEnumSelectorIndex(value: Value): Option<Int64> {
    if (let Some(localVar) <- value.AsLocalVar()) {
        if (let Some(ownerExpr) <- localVar.GetExpr()) {
            if (let Some(constantExpr) <- (ownerExpr as Constant)) {
                if (let Some(boolLiteral) <- (constantExpr.literal as BoolLiteral)) {
                    return if (boolLiteral.value) { 1 } else { 0 }
                }
                if (let Some(intLiteral) <- (constantExpr.literal as IntLiteral)) {
                    return intLiteral.value
                }
            }
        }
    }
    return None
}

private func CHIRCheckerTypeMustBeRef(ty: Type): Bool {
    if (!ty.IsRef()) {
        return false
    }
    if (let Some(refTy) <- (ty as RefType)) {
        let baseType = refTy.GetBaseType()
        if (baseType.IsReferenceType()) {
            return false
        }
        if (baseType.IsValueOrGenericType()) {
            return true
        }
        if (let Some(baseRefTy) <- (baseType as RefType)) {
            return baseRefTy.GetBaseType().IsReferenceType()
        }
    }
    return false
}

private func CHIRCheckerIsAnyRef(ty: Type): Bool {
    if (let Some(refTy) <- (ty as RefType)) {
        return refTy.GetBaseType().IsAny()
    }
    return false
}

private func CHIRCheckerIsCType(ty: Type): Bool {
    return CHIRCheckerIsOptionalCType(ty, false)
}

private func CHIRCheckerIsOptionalCType(ty: Type, includeNormalStruct: Bool): Bool {
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        return CHIRCheckerIsOptionalCType(varrayTy.GetElementType(), includeNormalStruct)
    }
    if (let Some(tupleTy) <- (ty as TupleType)) {
        for (elementTy in tupleTy.GetTypeArgsRef()) {
            if (!CHIRCheckerIsOptionalCType(elementTy, includeNormalStruct)) {
                return false
            }
        }
        return true
    }
    if (let Some(refTy) <- (ty as RefType)) {
        return CHIRCheckerIsOptionalCType(refTy.GetBaseType(), includeNormalStruct)
    }
    if (let Some(funcTy) <- (ty as FuncType)) {
        if (funcTy.IsCFunc()) {
            if (!CHIRCheckerIsOptionalCType(funcTy.GetReturnType(), includeNormalStruct)) {
                return false
            }
            for (paramTy in funcTy.GetParamTypes()) {
                if (!CHIRCheckerIsOptionalCType(paramTy, includeNormalStruct)) {
                    return false
                }
            }
            return true
        }
    }
    let kindIndex = TypeKindIndex(ty.GetTypeKind())
    let isPrimitiveCType = kindIndex >= TypeKindIndex(TypeKind.TYPE_INT8) &&
        kindIndex <= TypeKindIndex(TypeKind.TYPE_VOID)
    if (isPrimitiveCType || ty.IsCPointer() || ty.IsCString()) {
        return true
    }
    if (let Some(structTy) <- (ty as StructType)) {
        return includeNormalStruct || structTy.GetCustomTypeDef().TestAttr(Attribute.C)
    }
    return false
}

private func CHIRCheckerGenericTypeIsInContainer(ty: Type, container: ArrayList<GenericType>): Bool {
    if (let Some(genericTy) <- (ty as GenericType)) {
        for (item in container) {
            if (item.name == genericTy.name) {
                return true
            }
        }
        return false
    }
    for (argTy in ty.GetTypeArgsRef()) {
        if (!CHIRCheckerGenericTypeIsInContainer(argTy, container)) {
            return false
        }
    }
    return true
}

private func CHIRCheckerIsCalculExpr(kind: ExprKind): Bool {
    return kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.MUL || kind == ExprKind.DIV ||
        kind == ExprKind.MOD
}

private func CHIRCheckerIsBitExpr(kind: ExprKind): Bool {
    return kind == ExprKind.LSHIFT || kind == ExprKind.RSHIFT || kind == ExprKind.BITAND ||
        kind == ExprKind.BITOR || kind == ExprKind.BITXOR
}

private func CHIRCheckerIsCompareExpr(kind: ExprKind): Bool {
    return kind == ExprKind.LT || kind == ExprKind.GT || kind == ExprKind.LE || kind == ExprKind.GE ||
        kind == ExprKind.EQUAL || kind == ExprKind.NOTEQUAL
}
