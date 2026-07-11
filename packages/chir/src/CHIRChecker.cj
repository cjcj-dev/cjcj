package cjcj::chir

import std.collection.*
import cjcj::utils.CJC_ASSERT

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
    public let notes: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()

    public init() {}

    public func AddError(message: String): Unit {
        ok = false
        errors.add(message)
        notes.add(ArrayList<String>())
    }

    public func AddNote(message: String): Unit {
        if (errors.isEmpty()) {
            throw IllegalStateException("CHIRCheckResult AddNote expected primary diagnostic")
        }
        notes[notes.size - 1].add(message)
    }

    public func ToString(): String {
        if (ok) {
            return "ok"
        }
        let lines = ArrayList<String>()
        var idx: Int64 = 0
        while (idx < errors.size) {
            lines.add(errors[idx])
            if (idx < notes.size) {
                for (note in notes[idx]) {
                    lines.add(note)
                }
            }
            idx++
        }
        return JoinStrings(lines, "\n")
    }
}

public class CHIRChecker {
    private let rules: ArrayList<CHIRCheckerRule> = ArrayList<CHIRCheckerRule>()
    private let identifiers: HashSet<String> = HashSet<String>()
    private let duplicatedGlobalIds: ArrayList<String> = ArrayList<String>()
    private let duplicatedGlobalIdSet: HashSet<String> = HashSet<String>()

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
        for (def in pkg.GetAllStructDef()) {
            CheckStructDef(def, result)
        }
        for (def in pkg.GetAllClassDef()) {
            CheckClassDef(def, result)
        }
        for (def in pkg.GetAllEnumDef()) {
            CheckEnumDef(def, result)
        }
        for (def in pkg.GetAllExtendDef()) {
            CheckExtendDef(def, result)
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
        duplicatedGlobalIdSet.clear()
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
            CHIRCheckerAddUniqueString(duplicatedGlobalIds, duplicatedGlobalIdSet, identifier)
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
            CHIRCheckerAddUniqueString(duplicatedGlobalIds, duplicatedGlobalIdSet, identifier)
            return false
        }
        return true
    }

    private func CheckGlobalVar(globalVar: GlobalVar, result: CHIRCheckResult): Unit {
        if (!CheckGlobalValueIdentifier(globalVar, result)) {
            return
        }
        if (let Some(globalTy) <- globalVar.GetType()) {
            if (!CheckTypeMustBeRef(globalTy)) {
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
        if (shouldHaveInitializer) {
            let initByFunc = globalVar.GetInitFunc().isSome()
            let initByLiteral = globalVar.GetInitializer().isSome()
            let errMsg = "global var ${globalVar.GetIdentifier()} should be initialized by literal or function, "
            var hint = ""
            if (initByFunc && initByLiteral) {
                hint = "can't be both."
            } else if (!initByFunc && !initByLiteral) {
                if (!globalVar.TestAttr(Attribute.COMMON)) {
                    hint = "it must have one of them."
                }
            }
            if (!hint.isEmpty()) {
                result.AddError(errMsg)
            }
        }
        if (!globalVar.TestAttr(Attribute.COMPILER_ADD) && globalVar.GetSrcCodeIdentifier().isEmpty()) {
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
        if (!CheckOriginalLambdaInfo(fn, result)) {
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
                    "${GetExpressionString(lambdaExpr)} doesn't have type.")
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
                if (lambdaOpt.isNone() && !CheckLiftedLambdaType(topLevelFunc, result)) {
                    return false
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
                    "${GetExpressionString(lambdaExpr)} isn't func type.")
            }
        }
        return false
    }

    private func CheckOriginalLambdaInfo(fn: Function, result: CHIRCheckResult): Bool {
        if (!fn.IsLambda()) {
            return true
        }
        var res = true
        if (fn.GetOriginalLambdaType().isNone()) {
            result.AddError("func ${fn.GetIdentifier()} is lifted lambda, original lambda type should be set.")
            res = false
        }
        let originalTypeParams = fn.GetOriginalGenericTypeParamsRef()
        let curTypeParams = fn.GetGenericTypeParams()
        if (originalTypeParams.size > curTypeParams.size) {
            result.AddError("func ${fn.GetIdentifier()} is lifted lambda, original lambda generic type params' size is " +
                "${originalTypeParams.size}, current func's generic type params' size is ${curTypeParams.size}, " +
                "original size should be equal or less than current size.")
            res = false
        }
        return res
    }

    private func CheckLiftedLambdaType(fn: Function, result: CHIRCheckResult): Bool {
        if (!fn.IsLambda()) {
            return true
        }

        let funcTy = fn.GetFuncType().getOrThrow()
        var errMsg = "func ${fn.GetIdentifier()} is lifted lambda, its first parameter type should be Class-Env&, " +
            "but now func type is ${funcTy.ToString()}."
        let paramTypes = funcTy.GetParamTypes()
        if (paramTypes.isEmpty()) {
            result.AddError(errMsg)
            return false
        }
        let firstParamType = paramTypes[0] as RefType
        if (firstParamType.isNone()) {
            result.AddError(errMsg)
            return false
        }
        let firstParamTypeDeref = firstParamType.getOrThrow().GetBaseType()
        if (!firstParamTypeDeref.IsAutoEnv()) {
            result.AddError(errMsg)
            return false
        }
        if (firstParamTypeDeref.IsAutoEnvBase()) {
            errMsg = "func ${fn.GetIdentifier()} is lifted lambda, its first parameter type should be Class-Env&, " +
                "but now it's Class-EnvBase&."
            result.AddError(errMsg)
            return false
        }
        return true
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
            if (!IsCType(paramTy)) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, this is a CFunc, but the " +
                    IndexToString(idx) + " paramter type is ${paramTy.ToString()}, it's not a CType.")
                typeMatched = false
            }
            idx++
        }
        let retTy = funcTy.GetReturnType()
        if (!IsCType(retTy)) {
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
            if (topLevelFunc.IsConstructor() && funcTy.GetReturnType().IsUnit()) {
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
            let errMsg = "the " + IndexToString(idx) + " paramter type is " + paramTy.ToString()
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
        CheckCustomType(def, result)
        CheckInstanceMemberVar(def, result)
        CheckStaticMemberVar(def, result)
        CheckVTable(def, result)
        for (method in def.GetMethods()) {
            CheckParentCustomTypeDef(method, def, true, result)
        }
        CheckImplementedInterfaceTypes(def, result)
    }

    private func CheckStructDef(def: StructDef, result: CHIRCheckResult): Unit {
        CheckCustomTypeDef(def, result)
        CheckCStruct(def, result)
    }

    private func CheckClassDef(def: ClassDef, result: CHIRCheckResult): Unit {
        CheckCustomTypeDef(def, result)
    }

    private func CheckEnumDef(def: EnumDef, result: CHIRCheckResult): Unit {
        CheckCustomTypeDef(def, result)
    }

    private func CheckCustomType(def: CustomTypeDef, result: CHIRCheckResult): Unit {
        if ((def as ExtendDef).isSome()) {
            return
        }
        if (def.GetType().isNone()) {
            result.AddError(def.GetIdentifier() + " should set type.")
            return
        }
        if (let Some(defTy) <- def.GetType()) {
            let kind = def.GetCustomKind()
            if (kind == CustomDefKind.TYPE_STRUCT && !defTy.IsStruct()) {
                result.AddError(def.GetIdentifier() + " is struct definition, but its type is " +
                    defTy.ToString() + ".")
            } else if (kind == CustomDefKind.TYPE_CLASS && !defTy.IsClass()) {
                result.AddError(def.GetIdentifier() + " is class definition, but its type is " +
                    defTy.ToString() + ".")
            } else if (kind == CustomDefKind.TYPE_ENUM && !defTy.IsEnum()) {
                result.AddError(def.GetIdentifier() + " is enum definition, but its type is " +
                    defTy.ToString() + ".")
            }
        }
    }

    private func CheckInstanceMemberVar(def: CustomTypeDef, result: CHIRCheckResult): Unit {
        let memberVarNames = HashSet<String>()
        for (memberVar in def.GetDirectInstanceVars()) {
            if (memberVar.name.isEmpty()) {
                result.AddError("member var in ${def.GetIdentifier()} doesn't have name.")
                continue
            }
            if (!CHIRCheckerAddIdentifier(memberVarNames, memberVar.name)) {
                result.AddError("duplicated member var name `${memberVar.name}` in ${def.GetIdentifier()}.")
            }
            if (memberVar.outerDef.isNone()) {
                result.AddError("member var ${memberVar.name} in ${def.GetIdentifier()} doesn't set outer " +
                    "CustomTypeDef.")
            } else if (let Some(outerDef) <- memberVar.outerDef) {
                if (outerDef.nodeId != def.nodeId) {
                    result.AddError("outer CustomTypeDef of member var ${memberVar.name} is " +
                        "${outerDef.GetIdentifier()}, but it should be ${def.GetIdentifier()}.")
                }
            }
            if (memberVar.ty.IsInvalid()) {
                result.AddError("member var ${memberVar.name} in ${def.GetIdentifier()} doesn't set type.")
            }
        }
        for (memberVar in def.GetAllInstanceVars()) {
            if (memberVar.outerDef.isNone()) {
                continue
            }
            if (let Some(outerDef) <- memberVar.outerDef) {
                if (outerDef.nodeId == def.nodeId) {
                    continue
                }
                if ((memberVar.TestAttr(Attribute.PUBLIC) || memberVar.TestAttr(Attribute.PROTECTED)) &&
                    memberVarNames.contains(memberVar.name)) {
                    result.AddError("duplicated member var name `${memberVar.name}` in ${def.GetIdentifier()}, " +
                        "it has same name with parent class ${outerDef.GetIdentifier()} member var.")
                }
            }
        }
    }

    private func CheckStaticMemberVar(def: CustomTypeDef, result: CHIRCheckResult): Unit {
        for (memberVar in def.GetStaticMemberVars()) {
            if (!memberVar.TestAttr(Attribute.STATIC)) {
                result.AddError("static member var ${memberVar.GetIdentifier()} of ${def.GetIdentifier()} " +
                    "doesn't have Attribute `STATIC`.")
            }
            if (memberVar.GetParentCustomTypeDef().isNone()) {
                result.AddError("static member var ${memberVar.GetIdentifier()} doesn't set parent CustomTypeDef.")
            } else if (let Some(parentDef) <- memberVar.GetParentCustomTypeDef()) {
                if (parentDef.nodeId != def.nodeId) {
                    result.AddError("parent CustomTypeDef of static member var ${memberVar.GetIdentifier()} is " +
                        "${parentDef.GetIdentifier()}, but it should be ${def.GetIdentifier()}.")
                }
            }
        }
    }

    private func CheckVTable(def: CustomTypeDef, result: CHIRCheckResult): Unit {
        for (vtable in def.GetDefVTable().GetTypeVTables()) {
            let parentInstType = vtable.GetSrcParentType().getOrThrow()
            let parentDef = parentInstType.GetClassDef()
            let parentOriginalType = (parentDef.GetType().getOrThrow() as ClassType).getOrThrow()
            let parentVTable = parentDef.GetDefVTable().GetExpectedTypeVTable(parentOriginalType)
            if (parentVTable.IsEmpty()) {
                result.AddError("in vtable of ${def.GetIdentifier()}, parent type ${parentInstType.ToString()} " +
                    "can't be found in vtable of parent class ${parentDef.GetIdentifier()}.")
                continue
            }
            if (vtable.GetMethodNum() != parentVTable.GetMethodNum()) {
                result.AddError("in vtable of ${def.GetIdentifier()}, parent type ${parentInstType.ToString()} " +
                    "has ${vtable.GetMethodNum()} virtual method(s), but in vtable of parent class " +
                    "${parentDef.GetIdentifier()}, this parent type has ${parentVTable.GetMethodNum()} virtual " +
                    "method(s).")
                continue
            }
            let canHaveAbstractMethod = isAllowedToHaveAbstractMethod(def)
            var idx: Int64 = 0
            while (idx < vtable.GetMethodNum()) {
                if (vtable.GetVirtualMethods()[idx].GetVirtualMethod().getOrThrow().IsPureAbstract() &&
                    !canHaveAbstractMethod) {
                    result.AddError("in vtable of ${def.GetIdentifier()}, parent type ${parentInstType.ToString()}, " +
                        "the ${IndexToString(idx)} virtual method is unimplemented, but only interface " +
                        "or abstract class can have this kind of method.")
                }
                idx++
            }
        }
    }

    private func CheckImplementedInterfaceTypes(def: CustomTypeDef, result: CHIRCheckResult): Unit {
        for (parentType in def.GetImplementedInterfaceTys()) {
            if (!parentType.GetClassDef().IsInterface()) {
                result.AddError("there is non-interface type ${parentType.ToString()} in implemented interface " +
                    "list of ${def.GetIdentifier()}.")
            }
        }
    }

    private func CheckCStruct(def: StructDef, result: CHIRCheckResult): Unit {
        if (!def.IsCStruct()) {
            return
        }
        for (memberVar in def.GetDirectInstanceVars()) {
            if (!IsCType(memberVar.ty)) {
                result.AddError("in C-struct ${def.GetIdentifier()}, member var ${memberVar.name} has type " +
                    "${memberVar.ty.ToString()}, but it should be CType.")
            }
        }
    }

    private func CheckExtendDef(def: ExtendDef, result: CHIRCheckResult): Unit {
        CheckCustomTypeDef(def, result)
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
        let blockIds = HashSet<String>()
        var idx: Int64 = 0
        while (idx < blocks.size) {
            let id = blocks[idx].GetIdentifier()
            if (id.isEmpty()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, the " +
                    IndexToString(idx) + " block's id is empty.")
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
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
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
            var hasUser = false
            for (user in operand.GetUsersRef()) {
                if (refEq(user, expr)) {
                    hasUser = true
                    break
                }
            }
            if (!hasUser) {
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
                    "`${GetExpressionString(expr)}`, find unrecongnized ExprKind `${expr.GetExprKindName()}`.")
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
            if (let Some(retTy) <- ExpectedExitReturnType(term, topLevelFunc)) {
                let value = term.GetOperand(0)
                if (let Some(valueTy) <- value.GetType()) {
                    if (!CHIRCheckerTypeIsExpected(valueTy, retTy)) {
                        TypeCheckError(term, value, retTy.ToString(), topLevelFunc, result)
                    }
                }
            }
        }
    }

    private func ExpectedExitReturnType(term: Terminator, topLevelFunc: Function): Option<Type> {
        if (let Some(group) <- term.GetParentBlockGroup()) {
            var current = group
            while (current.GetOwnerFunc().isNone()) {
                if (let Some(ownerExpr) <- current.GetOwnerExpression()) {
                    if (let Some(lambdaExpr) <- (ownerExpr as Lambda)) {
                        return lambdaExpr.GetReturnType()
                    }
                    if (let Some(parentGroup) <- ownerExpr.GetParentBlockGroup()) {
                        current = parentGroup
                        continue
                    }
                }
                break
            }
        }
        return topLevelFunc.GetReturnType()
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
        if (!CheckOperandNumEqual(1, term, topLevelFunc, result)) {
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
        if (let Some(multiBranch) <- (term as MultiBranch)) {
            if (multiBranch.GetNormalBlocks().size != multiBranch.GetCaseVals().size) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(term)}`, value's size and normal block's size must be equal, " +
                    "but now there are ${multiBranch.GetCaseVals().size} value(s) and " +
                    "${multiBranch.GetNormalBlocks().size} normal block(s).")
            }
            if (multiBranch.GetDefaultBlock().GetIdentifier().isEmpty()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(term)}`, default block shouldn't be empty.")
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
                        "`${GetExpressionString(expr)}`, find unrecongnized ExprKind " +
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
                "`${GetExpressionString(expr)}`, find unrecongnized ExprKind `${expr.GetExprKindName()}`.")
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
        let value = expr.GetOperand(0)
        let location = expr.GetOperand(1)
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
        if (let Some(localVar) <- (location as LocalVar)) {
            if (localVar.GetExpr().getOrThrow().GetExprKind() == ExprKind.GET_ELEMENT_REF) {
                let resultValue = expr.GetResult().getOrThrow()
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, destination of Store `" +
                    "${resultValue.GetIdentifier()}` should not be GetElementRef.")
            }
        }
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
            case ExprKind.FIELD | ExprKind.GET_EXCEPTION =>
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.FIELD_BY_NAME =>
                if (let Some(fieldByNameExpr) <- (expr as FieldByName)) {
                    CheckFieldByName(fieldByNameExpr, topLevelFunc, result)
                }
            case ExprKind.APPLY =>
                if (let Some(applyExpr) <- (expr as Apply)) {
                    CheckApply(applyExpr, topLevelFunc, result)
                }
            case ExprKind.INVOKE =>
                if (let Some(invokeExpr) <- (expr as Invoke)) {
                    CheckInvoke(invokeExpr, topLevelFunc, result)
                }
            case ExprKind.INVOKESTATIC =>
                if (let Some(invokeStaticExpr) <- (expr as InvokeStatic)) {
                    CheckInvokeStatic(invokeStaticExpr, topLevelFunc, result)
                }
            case ExprKind.INSTANCEOF =>
                if (let Some(instanceOfExpr) <- (expr as InstanceOf)) {
                    CheckInstanceOf(instanceOfExpr, topLevelFunc, result)
                }
            case ExprKind.TYPECAST =>
                CheckOperandNumEqual(1, expr, topLevelFunc, result)
                CheckHaveResult(expr, topLevelFunc, result)
                if (let Some(typeCastExpr) <- (expr as TypeCast)) {
                    CheckTypeCast(typeCastExpr, topLevelFunc, result)
                }
            case ExprKind.BOX =>
                if (let Some(boxExpr) <- (expr as Box)) {
                    CheckBox(boxExpr, topLevelFunc, result)
                }
            case ExprKind.UNBOX =>
                if (let Some(unBoxExpr) <- (expr as UnBox)) {
                    CheckUnBox(unBoxExpr, topLevelFunc, result)
                }
            case ExprKind.TRANSFORM_TO_GENERIC =>
                if (let Some(transformExpr) <- (expr as TransformToGeneric)) {
                    CheckTransformToGeneric(transformExpr, topLevelFunc, result)
                }
            case ExprKind.TRANSFORM_TO_CONCRETE =>
                if (let Some(transformExpr) <- (expr as TransformToConcrete)) {
                    CheckTransformToConcrete(transformExpr, topLevelFunc, result)
                }
            case ExprKind.UNBOX_TO_REF =>
                if (let Some(unBoxToRefExpr) <- (expr as UnBoxToRef)) {
                    CheckUnBoxToRef(unBoxToRefExpr, topLevelFunc, result)
                }
            case ExprKind.RAW_ARRAY_ALLOCATE | ExprKind.RAW_ARRAY_INIT_BY_VALUE | ExprKind.SPAWN =>
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.GET_RTTI =>
                if (let Some(getRTTIExpr) <- (expr as GetRTTI)) {
                    CheckGetRTTI(getRTTIExpr, topLevelFunc, result)
                }
            case ExprKind.GET_RTTI_STATIC =>
                if (let Some(getRTTIStaticExpr) <- (expr as GetRTTIStatic)) {
                    CheckGetRTTIStatic(getRTTIStaticExpr, topLevelFunc, result)
                }
            case ExprKind.VARRAY_BUILDER =>
                if (let Some(varrayBuilderExpr) <- (expr as VArrayBuilder)) {
                    CheckVArrayBuilder(varrayBuilderExpr, topLevelFunc, result)
                }
            case ExprKind.INTRINSIC =>
                if (let Some(intrinsicExpr) <- (expr as Intrinsic)) {
                    CheckIntrinsic(intrinsicExpr, topLevelFunc, result)
                }
            case ExprKind.RAW_ARRAY_LITERAL_INIT =>
                CheckOperandNumAtLeast(1, expr, topLevelFunc, result)
                CheckHaveResult(expr, topLevelFunc, result)
            case ExprKind.GET_INSTANTIATE_VALUE => CheckGetInstantiateValue(expr, topLevelFunc, result)
            case _ => result.AddError("in function ${topLevelFunc.GetIdentifier()}, in " +
                "`${GetExpressionString(expr)}`, find unrecongnized ExprKind `${expr.GetExprKindName()}`.")
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
                GetExpressionString(expr) + "` at least, and the 1st operand's type is UInt32 or Bool.")
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
                GetExpressionString(expr) + "` must be from Constant UInt32 or Constant Bool.")
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
                            GetExpressionString(expr) + "` its enum constructor's number is ${ctors.size} " +
                            "but the index is ${ctorIndex}.")
                        return
                    }
                    let payloadTypes = ctors[ctorIndex].payloadTypes
                    if (operandsNum - 1 != payloadTypes.size) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                            "${payloadTypes.size} parameter(s) in the ${ctorIndex}-th constructor, but " +
                            "${operandsNum - 1} arguments are provided in `" + GetExpressionString(expr) + "`.")
                        return
                    }
                    var idx: Int64 = 1
                    while (idx < operandsNum) {
                        let operand = expr.GetOperand(idx)
                        if (let Some(operandTy) <- operand.GetType()) {
                            let expectedTy = SubstituteGenericType(payloadTypes[idx - 1],
                                enumTy.GetEnumDef().GetGenericTypeParams(), enumTy.GetGenericArgs())
                            if (!CHIRCheckerTypeIsExpected(operandTy, expectedTy)) {
                                result.AddError("in function ${topLevelFunc.GetIdentifier()}, type mismatched, the " +
                                    "${idx - 1}-th parameter type is ${expectedTy.ToString()}, but " +
                                    "${operand.GetIdentifier()}'s type is ${operandTy.ToString()} in `" +
                                    GetExpressionString(expr) + "`.")
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
                    "operand(s) are provided in `" + GetExpressionString(expr) + "`.")
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
                            GetExpressionString(expr) + "`.")
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
                        "${operandsNum} operand(s) are provided in `" + GetExpressionString(expr) + "`.")
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
                                "${operandTy.ToString()} in `" + GetExpressionString(expr) + "`.")
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
                if (!IsCTypeInVArray(elementTy)) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                        "${GetExpressionString(expr)}`, its element type is ${elementTy.ToString()}, " +
                        "but a C type is expected.\n    C type includes: numeric data types, Rune, Bool, Unit, " +
                        "Nothing, CPointer, CString, CFunc and Struct.")
                    return
                }
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

    private func CheckFieldByName(expr: FieldByName, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
            "you should convert this expression to `Field`.")
    }

    private func CheckVArrayBuilder(expr: VArrayBuilder, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(3, expr, topLevelFunc, result)) {
            return
        }
        let resultValue = expr.GetResult().getOrThrow()
        if (!resultValue.GetType().getOrThrow().IsVArray()) {
            TypeCheckError(expr, resultValue, "VArray", topLevelFunc, result)
        }
        let size = expr.GetSize()
        if (size.GetType().getOrThrow().GetTypeKind() != TypeKind.TYPE_INT64) {
            TypeCheckError(expr, size, "Int64", topLevelFunc, result)
        }
        let item = ConvertToNullLiteral(expr.GetItem())
        let initFunc = ConvertToNullLiteral(expr.GetInitFunc())
        if (item.isNone() && initFunc.isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
                "one of item and init func should be null.")
        } else if (item.isSome() && initFunc.isSome()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
                "item and init func can't be both null.")
        }
        let funcType = expr.GetInitFunc().GetType().getOrThrow()
        if (!IsFuncTypeOrClosureBaseRefType(funcType)) {
            TypeCheckError(expr, expr.GetInitFunc(), "Function type or closure ref", topLevelFunc, result)
        }
    }

    private func CheckInstanceOf(expr: InstanceOf, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        CheckBoolResult(expr, topLevelFunc, result)
        CheckTypeIsValid(expr.GetType(), "target", expr, topLevelFunc, result)
        if (let Some(objectTy) <- expr.GetObject().GetType()) {
            if (objectTy.StripAllRefs().IsPrimitive() && expr.GetType().StripAllRefs().IsPrimitive()) {
                if (let Some(resultValue) <- expr.GetResult()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, invalid InstanceOf `" +
                        "${resultValue.ToString(0)}`, source type is ${objectTy.StripAllRefs().ToString()}, " +
                        "target type is ${expr.GetType().ToString()}, they are both exact type, doesn't need to " +
                        "use `InstanceOf` to check in runtime.")
                }
            }
        }
    }

    private func CheckTypeCast(expr: TypeCast, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        let _ = expr
        let _ = topLevelFunc
        let _ = result
    }

    private func CheckBox(expr: Box, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            if (let Some(sourceTy) <- expr.GetSourceTy()) {
                if (!targetTy.IsRef()) {
                    TypeCheckResultError(expr, "reference", topLevelFunc, result)
                } else {
                    let strippedTy = targetTy.StripAllRefs()
                    if (let Some(boxTy) <- (strippedTy as BoxType)) {
                        if (boxTy.GetBaseType().objectId != sourceTy.objectId) {
                            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                                "${GetExpressionString(expr)}`, the target type is ${targetTy.ToString()}, " +
                                "then source type must be its base type, can't be ${sourceTy.ToString()}.")
                        }
                    } else if (!strippedTy.IsClass()) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                            "${GetExpressionString(expr)}`, the target type must be Class& or Box&, " +
                            "can't be ${targetTy.ToString()}.")
                    }
                }
                if (!sourceTy.IsValueType()) {
                    TypeCheckError(expr, expr.GetSourceValue(), "value", topLevelFunc, result)
                }
            }
        }
    }

    private func CheckUnBox(expr: UnBox, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            if (let Some(sourceTy) <- expr.GetSourceTy()) {
                if (!sourceTy.IsRef()) {
                    TypeCheckError(expr, expr.GetSourceValue(), "reference", topLevelFunc, result)
                } else {
                    let strippedTy = sourceTy.StripAllRefs()
                    if (let Some(boxTy) <- (strippedTy as BoxType)) {
                        if (boxTy.GetBaseType().objectId != targetTy.objectId) {
                            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                                "${GetExpressionString(expr)}`, the source type is ${sourceTy.ToString()}, " +
                                "then target type must be its base type, can't be ${targetTy.ToString()}.")
                        }
                    } else if (!strippedTy.IsClass()) {
                        result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                            "${GetExpressionString(expr)}`, the source type must be Class& or Box&, " +
                            "can't be ${sourceTy.ToString()}.")
                    }
                }
                if (!targetTy.IsValueType()) {
                    TypeCheckResultError(expr, "value", topLevelFunc, result)
                }
            }
        }
    }

    private func CheckTransformToGeneric(expr: TransformToGeneric, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            if (!targetTy.IsGenericRelated()) {
                TypeCheckResultError(expr, "generic related", topLevelFunc, result)
            }
        }
        if (let Some(sourceTy) <- expr.GetSourceTy()) {
            if (sourceTy.IsGeneric()) {
                TypeCheckError(expr, expr.GetSourceValue(), "concrete", topLevelFunc, result)
            }
        }
    }

    private func CheckTransformToConcrete(expr: TransformToConcrete, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            if (targetTy.IsGeneric()) {
                TypeCheckResultError(expr, "concrete", topLevelFunc, result)
            }
        }
        if (let Some(sourceTy) <- expr.GetSourceTy()) {
            if (!sourceTy.IsGenericRelated()) {
                TypeCheckError(expr, expr.GetSourceValue(), "generic related", topLevelFunc, result)
            }
        }
    }

    private func CheckUnBoxToRef(expr: UnBoxToRef, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            var isValueRefType = false
            if (let Some(refTy) <- (targetTy as RefType)) {
                isValueRefType = refTy.GetBaseType().IsValueType()
            }
            if (!isValueRefType) {
                TypeCheckResultError(expr, "Value&", topLevelFunc, result)
            }
        }
        if (let Some(sourceTy) <- expr.GetSourceTy()) {
            var isReferenceRefType = false
            if (let Some(refTy) <- (sourceTy as RefType)) {
                isReferenceRefType = refTy.GetBaseType().IsReferenceType()
            }
            if (!isReferenceRefType) {
                TypeCheckError(expr, expr.GetSourceValue(), "Reference&", topLevelFunc, result)
            }
        }
    }

    private func CheckGetRTTI(expr: GetRTTI, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        CheckUnitResult(expr, topLevelFunc, result)
        let operand = expr.GetOperand()
        if (let Some(operandTy) <- operand.GetType()) {
            if (let Some(refTy) <- (operandTy as RefType)) {
                let baseTy = refTy.GetBaseType()
                if (!baseTy.IsClass() && !baseTy.IsThis()) {
                    TypeCheckError(expr, operand, "Class& or This&", topLevelFunc, result)
                }
            } else {
                TypeCheckError(expr, operand, "Class& or This&", topLevelFunc, result)
            }
        }
    }

    private func CheckGetRTTIStatic(expr: GetRTTIStatic, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (!CheckOperandNumEqual(0, expr, topLevelFunc, result)) {
            return
        }
        CheckUnitResult(expr, topLevelFunc, result)
        if (!HasRule(CHIRCheckerRule.CHIR_GET_RTTI_STATIC_TYPE)) {
            return
        }
        let rttiTy = expr.GetRTTIType()
        let strippedTy = rttiTy.StripAllRefs()
        if (!strippedTy.IsGeneric() && !strippedTy.IsThis()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                "${GetExpressionString(expr)}`, RTTI type should be `This` or Generic type, but now it's " +
                "${rttiTy.ToString()}.")
        }
    }

    private func CheckApply(expr: Apply, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumAtLeast(1, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        let callee = expr.GetCallee()
        if (!CheckCallee(callee, expr, topLevelFunc, result)) {
            return
        }
        if (!CheckApplyInstantiatedTypeArgs(expr, callee, topLevelFunc, result)) {
            return
        }
        CheckApplyThisType(expr, callee, topLevelFunc, result)
        if (let Some(calleeTy) <- callee.GetType()) {
            if (let Some(funcTy) <- (calleeTy as FuncType)) {
                let instFuncTy = InstantiateApplyFuncType(funcTy, expr, callee)
                CheckApplyFuncArgs(expr.GetArgs(), instFuncTy, expr, topLevelFunc, result)
                CheckCallReturnType(instFuncTy.GetReturnType(), expr, topLevelFunc, result)
            }
        }
    }

    private func CheckInvoke(expr: Invoke, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumAtLeast(1, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (!CheckInstantiatedTypeArgs(expr.GetInstantiatedTypeArgs(), expr.GetGenericTypeParams(), expr,
            topLevelFunc, result)) {
            return
        }
        if (let Some(objectTy) <- expr.GetObject().GetType()) {
            CheckInvokeThisType(objectTy, expr.GetThisType(), expr, topLevelFunc, result)
        }
        CheckInvokeFuncArgs(expr.GetArgs(), expr.GetMethodType(), expr, 1, topLevelFunc, result)
        CheckCallReturnType(expr.GetMethodType().GetReturnType(), expr, topLevelFunc, result)
    }

    private func CheckInvokeStatic(expr: InvokeStatic, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckOperandNumAtLeast(1, expr, topLevelFunc, result) || !CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (!CheckInstantiatedTypeArgs(expr.GetInstantiatedTypeArgs(), expr.GetGenericTypeParams(), expr,
            topLevelFunc, result)) {
            return
        }
        if (let Some(objectTy) <- ResolveRTTIObjectType(expr.GetRTTIValue())) {
            CheckInvokeThisType(objectTy, expr.GetThisType(), expr, topLevelFunc, result)
        } else {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                "${GetExpressionString(expr)}`, its first operand must be from `GetRTTI` or `GetRTTIStatic`.")
        }
        CheckInvokeFuncArgs(expr.GetArgs(), expr.GetMethodType(), expr, 0, topLevelFunc, result)
        CheckCallReturnType(expr.GetMethodType().GetReturnType(), expr, topLevelFunc, result)
    }

    private func CheckCallee(callee: Value, expr: Expression, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        if (let Some(calleeTy) <- callee.GetType()) {
            if (!calleeTy.IsFunc()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, callee of `" +
                    "${GetExpressionString(expr)}` should have func type, not ${calleeTy.ToString()}.")
                return false
            }
        }
        if (callee.TestAttr(Attribute.ABSTRACT)) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, callee of `" +
                "${GetExpressionString(expr)}` can't be abstract.")
            return false
        }
        return true
    }

    private func CheckApplyInstantiatedTypeArgs(expr: Apply, callee: Value, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        if (callee.AsFunction().isSome()) {
            return true
        }
        let genericTypeParams = ArrayList<GenericType>()
        if (let Some(localVar) <- callee.AsLocalVar()) {
            if (let Some(calleeExpr) <- localVar.GetExpr()) {
                if (let Some(lambdaExpr) <- (calleeExpr as Lambda)) {
                    for (genericTy in lambdaExpr.GetGenericTypeParams()) {
                        genericTypeParams.add(genericTy)
                    }
                }
            }
        }
        return CheckInstantiatedTypeArgs(expr.GetInstantiatedTypeArgs(), genericTypeParams, expr, topLevelFunc,
            result)
    }

    private func CheckInstantiatedTypeArgs(instantiatedTypeArgs: ArrayList<Type>,
        genericTypeParams: ArrayList<GenericType>, expr: Expression, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        if (instantiatedTypeArgs.size != genericTypeParams.size) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                "${instantiatedTypeArgs.size} instantiated type args in function call `" +
                "${GetExpressionString(expr)}`, but there are ${genericTypeParams.size} generic type args " +
                "in function declare.")
            return false
        }
        return true
    }

    private func CheckApplyThisType(expr: Apply, callee: Value, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (let Some(thisTy) <- expr.GetThisType()) {
            let derefTy = thisTy.StripAllRefs()
            if (!derefTy.IsBuiltinType() && !derefTy.IsCustomType() && !derefTy.IsGeneric()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(expr)}`, ThisType must be builtin type, custom type or generic " +
                    "type, can't be ${thisTy.ToString()}.")
            }
            if (callee.AsFunction().isNone()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(expr)}`, callee isn't member method, but there is ThisType: " +
                    "${thisTy.ToString()}.")
            }
        }
        if (let Some(fn) <- callee.AsFunction()) {
            if (fn.IsMemberFunc() && expr.GetThisType().isNone()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(expr)}`, callee is member method, but there is no ThisType.")
            } else if (!fn.IsMemberFunc() && expr.GetThisType().isSome()) {
                if (let Some(thisTy2) <- expr.GetThisType()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                        "${GetExpressionString(expr)}`, callee isn't member method, but there is ThisType: " +
                        "${thisTy2.ToString()}.")
                }
            }
        }
    }

    private func CheckInvokeThisType(objectTy: Type, maybeThisType: Option<Type>, expr: Expression,
        topLevelFunc: Function, result: CHIRCheckResult): Bool {
        let _ = objectTy
        if (maybeThisType.isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                "${GetExpressionString(expr)}`, we must have `ThisType`, can't be None.")
            return false
        }
        if (let Some(thisTy) <- maybeThisType) {
            let thisDerefTy = thisTy.StripAllRefs()
            if (!thisDerefTy.IsBuiltinType() && !thisDerefTy.IsCustomType() && !thisDerefTy.IsThis() &&
                !thisDerefTy.IsGeneric()) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(expr)}`, ThisType must be builtin type, custom type, `This` type " +
                    "or generic type, can't be ${thisTy.ToString()}.")
                return false
            }
            if (let Some(genericTy) <- (thisDerefTy as GenericType)) {
                if (genericTy.GetUpperBounds().isEmpty()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                        "${GetExpressionString(expr)}`, ThisType is ${thisTy.ToString()}, a generic type, " +
                        "but it doesn't have upper bounds.")
                    return false
                }
            }
        }
        return true
    }

    private func ResolveRTTIObjectType(value: Value): Option<Type> {
        if (let Some(localVar) <- value.AsLocalVar()) {
            if (let Some(ownerExpr) <- localVar.GetExpr()) {
                if (let Some(getRttiExpr) <- (ownerExpr as GetRTTI)) {
                    return getRttiExpr.GetOperand().GetType()
                }
                if (let Some(getRttiStaticExpr) <- (ownerExpr as GetRTTIStatic)) {
                    return getRttiStaticExpr.GetRTTIType()
                }
            }
        }
        return None
    }

    private func InstantiateApplyFuncType(funcTy: FuncType, expr: Apply, callee: Value): FuncType {
        let genericParams = ArrayList<GenericType>()
        let replacements = ArrayList<Type>()
        AddParentGenericReplacements(expr, callee, genericParams, replacements)
        if (let Some(fn) <- callee.AsFunction()) {
            let fnGenericParams = fn.GetGenericTypeParams()
            let instArgs = expr.GetInstantiatedTypeArgs()
            var idx: Int64 = 0
            while (idx < fnGenericParams.size && idx < instArgs.size) {
                genericParams.add(fnGenericParams[idx])
                replacements.add(instArgs[idx])
                idx++
            }
        }
        if (genericParams.isEmpty()) {
            return funcTy
        }
        let params = ArrayList<Type>()
        for (paramTy in funcTy.GetParamTypes()) {
            params.add(SubstituteGenericType(paramTy, genericParams, replacements))
        }
        let retTy = SubstituteGenericType(funcTy.GetReturnType(), genericParams, replacements)
        return FuncType(params, retTy, hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
    }

    private func AddParentGenericReplacements(expr: Apply, callee: Value, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): Unit {
        let fn = callee.AsFunction() ?? return
        let parentDef = fn.GetParentCustomTypeDef() ?? return
        let thisTy = match (expr.GetThisType()) {
            case Some(value) => value
            case None => return
        }
        if (let Some(extendDef) <- (parentDef as ExtendDef)) {
            AddExtendGenericReplacements(extendDef, thisTy, genericParams, replacements)
            return
        }
        let thisCustom = match (thisTy.StripAllRefs() as CustomType) {
            case Some(value) => value
            case None => return
        }
        if (!SameCustomDefForGenericInstantiation(thisCustom.GetCustomTypeDef(), parentDef)) {
            return
        }
        let parentGenericParams = parentDef.GetGenericTypeParams()
        let parentArgs = thisCustom.GetGenericArgs()
        var idx: Int64 = 0
        while (idx < parentGenericParams.size && idx < parentArgs.size) {
            genericParams.add(parentGenericParams[idx])
            replacements.add(parentArgs[idx])
            idx++
        }
    }

    private func AddExtendGenericReplacements(extendDef: ExtendDef, thisTy: Type,
        genericParams: ArrayList<GenericType>, replacements: ArrayList<Type>): Unit {
        if (let Some(extendedTy) <- extendDef.GetExtendedType()) {
            CollectGenericReplacementsFromTypes(extendedTy.StripAllRefs(), thisTy.StripAllRefs(), genericParams,
                replacements)
        }
    }

    private func CollectGenericReplacementsFromTypes(pattern: Type, actual: Type,
        genericParams: ArrayList<GenericType>, replacements: ArrayList<Type>): Unit {
        if (let Some(genericTy) <- (pattern as GenericType)) {
            AddGenericReplacementIfMissing(genericTy, actual, genericParams, replacements)
            return
        }
        if (let Some(patternRef) <- (pattern as RefType)) {
            if (let Some(actualRef) <- (actual as RefType)) {
                CollectGenericReplacementsFromTypes(patternRef.GetBaseType(), actualRef.GetBaseType(),
                    genericParams, replacements)
            }
            return
        }
        if (let Some(patternCustom) <- (pattern as CustomType)) {
            if (let Some(actualCustom) <- (actual as CustomType)) {
                if (SameCustomDefForGenericInstantiation(patternCustom.GetCustomTypeDef(),
                    actualCustom.GetCustomTypeDef())) {
                    CollectGenericReplacementsFromTypeArgs(patternCustom.GetGenericArgs(),
                        actualCustom.GetGenericArgs(), genericParams, replacements)
                }
            }
            return
        }
        if (let Some(patternRawArray) <- (pattern as RawArrayType)) {
            if (let Some(actualRawArray) <- (actual as RawArrayType)) {
                CollectGenericReplacementsFromTypes(patternRawArray.GetElementType(),
                    actualRawArray.GetElementType(), genericParams, replacements)
            }
            return
        }
        if (let Some(patternVArray) <- (pattern as VArrayType)) {
            if (let Some(actualVArray) <- (actual as VArrayType)) {
                CollectGenericReplacementsFromTypes(patternVArray.GetElementType(), actualVArray.GetElementType(),
                    genericParams, replacements)
            }
            return
        }
        if (let Some(patternPointer) <- (pattern as CPointerType)) {
            if (let Some(actualPointer) <- (actual as CPointerType)) {
                CollectGenericReplacementsFromTypes(patternPointer.GetElementType(), actualPointer.GetElementType(),
                    genericParams, replacements)
            }
            return
        }
        if (let Some(patternBox) <- (pattern as BoxType)) {
            if (let Some(actualBox) <- (actual as BoxType)) {
                CollectGenericReplacementsFromTypes(patternBox.GetBaseType(), actualBox.GetBaseType(),
                    genericParams, replacements)
            }
            return
        }
        if (let Some(patternTuple) <- (pattern as TupleType)) {
            if (let Some(actualTuple) <- (actual as TupleType)) {
                CollectGenericReplacementsFromTypeArgs(patternTuple.GetTypeArgs(), actualTuple.GetTypeArgs(),
                    genericParams, replacements)
            }
            return
        }
        if (let Some(patternFunc) <- (pattern as FuncType)) {
            if (let Some(actualFunc) <- (actual as FuncType)) {
                CollectGenericReplacementsFromTypeArgs(patternFunc.GetParamTypes(), actualFunc.GetParamTypes(),
                    genericParams, replacements)
                CollectGenericReplacementsFromTypes(patternFunc.GetReturnType(), actualFunc.GetReturnType(),
                    genericParams, replacements)
            }
        }
    }

    private func CollectGenericReplacementsFromTypeArgs(patterns: ArrayList<Type>, actuals: ArrayList<Type>,
        genericParams: ArrayList<GenericType>, replacements: ArrayList<Type>): Unit {
        var idx: Int64 = 0
        while (idx < patterns.size && idx < actuals.size) {
            CollectGenericReplacementsFromTypes(patterns[idx], actuals[idx], genericParams, replacements)
            idx++
        }
    }

    private func AddGenericReplacementIfMissing(genericTy: GenericType, replacement: Type,
        genericParams: ArrayList<GenericType>, replacements: ArrayList<Type>): Unit {
        var idx: Int64 = 0
        while (idx < genericParams.size && idx < replacements.size) {
            if (genericTy.IsEqual(genericParams[idx])) {
                return
            }
            idx++
        }
        genericParams.add(genericTy)
        replacements.add(replacement)
    }

    private func SubstituteGenericType(ty: Type, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): Type {
        if (let Some(genericTy) <- (ty as GenericType)) {
            if (let Some(replacement) <- FindGenericReplacement(genericTy, genericParams, replacements)) {
                return replacement
            }
            return ty
        }
        if (let Some(refTy) <- (ty as RefType)) {
            return RefType(SubstituteGenericType(refTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            return RawArrayType(SubstituteGenericType(rawArrayTy.GetElementType(), genericParams, replacements),
                dims: rawArrayTy.GetDims())
        }
        if (let Some(varrayTy) <- (ty as VArrayType)) {
            return VArrayType(SubstituteGenericType(varrayTy.GetElementType(), genericParams, replacements),
                varrayTy.size)
        }
        if (let Some(pointerTy) <- (ty as CPointerType)) {
            return CPointerType(SubstituteGenericType(pointerTy.GetElementType(), genericParams, replacements))
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return BoxType(SubstituteGenericType(boxTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            return TupleType(SubstituteGenericTypeArgs(tupleTy.GetTypeArgs(), genericParams, replacements))
        }
        if (let Some(funcTy) <- (ty as FuncType)) {
            let params = SubstituteGenericTypeArgs(funcTy.GetParamTypes(), genericParams, replacements)
            let retTy = SubstituteGenericType(funcTy.GetReturnType(), genericParams, replacements)
            return FuncType(params, retTy, hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
        }
        if (let Some(structTy) <- (ty as StructType)) {
            return StructType(structTy.GetStructDef(),
                SubstituteGenericTypeArgs(structTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            return ClassType(classTy.GetClassDef(),
                SubstituteGenericTypeArgs(classTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(enumTy) <- (ty as EnumType)) {
            return EnumType(enumTy.GetEnumDef(),
                SubstituteGenericTypeArgs(enumTy.GetGenericArgs(), genericParams, replacements))
        }
        return ty
    }

    private func SubstituteGenericTypeArgs(args: ArrayList<Type>, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (arg in args) {
            out.add(SubstituteGenericType(arg, genericParams, replacements))
        }
        return out
    }

    private func FindGenericReplacement(genericTy: GenericType, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): Option<Type> {
        var idx: Int64 = 0
        while (idx < genericParams.size && idx < replacements.size) {
            if (genericTy.IsEqual(genericParams[idx])) {
                return Some(replacements[idx])
            }
            idx++
        }
        return None
    }

    private func SameCustomDefForGenericInstantiation(left: CustomTypeDef, right: CustomTypeDef): Bool {
        if (left.nodeId == right.nodeId) {
            return true
        }
        return left.GetPackageName() == right.GetPackageName() &&
            left.GetSrcCodeIdentifier() == right.GetSrcCodeIdentifier()
    }

    private func CheckApplyFuncArgs(args: ArrayList<Value>, funcTy: FuncType, expr: Expression,
        topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!funcTy.HasVarArg() && args.size != funcTy.GetNumOfParams()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                "${args.size} arg(s) in function call `${GetExpressionString(expr)}`, but there are " +
                "${funcTy.GetNumOfParams()} parameter(s) in function declare.")
            return
        }
        var idx: Int64 = 0
        while (idx < args.size && idx < funcTy.GetNumOfParams()) {
            let arg = args[idx]
            if (let Some(argTy) <- arg.GetType()) {
                let paramTy = funcTy.GetParamType(idx)
                if (!CHIRCheckerTypeIsExpected(argTy, paramTy)) {
                    TypeCheckError(expr, arg, paramTy.ToString(), topLevelFunc, result)
                }
            }
            idx++
        }
    }

    private func CheckInvokeFuncArgs(args: ArrayList<Value>, funcTy: FuncType, expr: Expression, skipArgs: Int64,
        topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (args.size != funcTy.GetNumOfParams()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                "${args.size} arg(s) in function call `${GetExpressionString(expr)}`, but there are " +
                "${funcTy.GetNumOfParams()} parameter(s) in function declare.")
            return
        }
        var idx: Int64 = skipArgs
        while (idx < args.size && idx < funcTy.GetNumOfParams()) {
            let arg = args[idx]
            if (let Some(argTy) <- arg.GetType()) {
                let paramTy = funcTy.GetParamType(idx)
                if (!CHIRCheckerTypeIsExpected(argTy, paramTy)) {
                    TypeCheckError(expr, arg, paramTy.ToString(), topLevelFunc, result)
                }
            }
            idx++
        }
    }

    private func CheckCallReturnType(expectedRetTy: Type, expr: Expression, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (!CHIRCheckerTypeIsExpected(expectedRetTy, resultTy) &&
                !CHIRCheckerTypeIsExpected(resultTy, expectedRetTy)) {
                TypeCheckResultError(expr, expectedRetTy.ToString(), topLevelFunc, result)
            }
        }
    }

    private func CheckIntrinsic(expr: Intrinsic, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (!CheckHaveResult(expr, topLevelFunc, result)) {
            return
        }
        if (expr.GetIntrinsicKind() == IntrinsicKind.NOT_INTRINSIC ||
            expr.GetIntrinsicKind() == IntrinsicKind.NOT_IMPLEMENTED) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                "${GetExpressionString(expr)}`, intrinsic kind must be valid.")
        }
        CheckInout(expr, topLevelFunc, result)
    }

    private func CheckInout(expr: Intrinsic, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (expr.GetIntrinsicKind() != IntrinsicKind.INOUT_PARAM) {
            return
        }
        if (!expr.GetInstantiatedTypeArgs().isEmpty()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                "${GetExpressionString(expr)}`, `inout` intrinsic can't have type args.")
        }
        if (!CheckOperandNumEqual(1, expr, topLevelFunc, result)) {
            return
        }
        let operand = expr.GetOperand(0)
        if (let Some(opTy) <- operand.GetType()) {
            if (let Some(refTy) <- (opTy as RefType)) {
                let baseTy = refTy.GetBaseType()
                if (baseTy.IsRef()) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                        "${GetExpressionString(expr)}`, `inout` operand's type is `${opTy.ToString()}`, " +
                        "but type&& is NOT allowed.")
                    return
                }
                CheckInoutOpSrc(operand, expr, topLevelFunc, result)
            } else {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(expr)}`, `inout` operand's type is `${opTy.ToString()}`, but ref " +
                    "type is expected.")
                return
            }
        }
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (!resultTy.IsCPointer()) {
                TypeCheckResultError(expr, "CPointer", topLevelFunc, result)
                return
            }
            if (!IsCTypeInInout(resultTy)) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(expr)}`, the pointed type of result CPointer is not CType " +
                    "(exclude CString).")
            }
        }
    }

    private func CheckInoutOpSrc(op: Value, expr: Intrinsic, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        if (op.IsBlock() || op.IsBlockGroup() || op.IsFunc() || op.IsLiteral()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                "${GetExpressionString(expr)}`, `inout` operand can't be Block, BlockGroup, Literal or " +
                "Function.")
            return
        }
        if (let Some(opTy) <- op.GetType()) {
            let strippedTy = opTy.StripAllRefs()
            if (!IsCTypeInInout(strippedTy)) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(expr)}`, `inout` operand's type is `${strippedTy.ToString()}`, " +
                    "but C-type (exclude CString) is expected.")
            }
        }
    }

    private func CheckGetInstantiateValue(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (HasRule(CHIRCheckerRule.GET_INSTANTIATE_VALUE_SHOULD_GONE)) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in " +
                "`${GetExpressionString(expr)}`, `GetInstantiateValue` should be removed now, " +
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

    private func CheckTypeIsValid(ty: Type, typeName: String, expr: Expression, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        if (let Some(customTy) <- (ty as CustomType)) {
            if (let Some(genericTy) <- customTy.GetCustomTypeDef().GetType()) {
                let declaredSize = genericTy.GetTypeArgsRef().size
                let callSiteSize = customTy.GetTypeArgsRef().size
                if (declaredSize != callSiteSize) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `" +
                        "${GetExpressionString(expr)}`, type args' size NOT matched, the ${typeName} type " +
                        "is `${customTy.ToString()}` which has ${callSiteSize} type arg(s), but its original type " +
                        "is `${genericTy.ToString()}` which has ${declaredSize} type arg(s).")
                    return false
                }
            }
        }
        return true
    }

    private func CheckHaveResult(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Bool {
        if (expr.GetResult().isNone()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
                "this expression should have result.")
            return false
        }
        return true
    }

    private func ShouldNotHaveResult(expr: Expression, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        if (expr.GetResult().isSome()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
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
            "${GetExpressionString(expr)} has type ${actualType}, but ${expectedType} type is expected.")
    }

    private func CheckOperandNumEqual(expectedNum: Int64, expr: Expression, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = expr.GetNumOfOperands()
        if (expectedNum != realNum) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
                "expect ${expectedNum} operand(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func CheckOperandNumAtLeast(expectedNum: Int64, expr: Expression, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = expr.GetNumOfOperands()
        if (expectedNum > realNum) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
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
        result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
            "expect " + CHIRCheckerIntArrayToString(expectedNums) + " operand(s), but there are ${realNum} in fact.")
        return false
    }

    private func CheckSuccessorNumEqual(expectedNum: Int64, term: Terminator, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = term.GetSuccessors().size
        if (expectedNum != realNum) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(term)}`, " +
                "expect ${expectedNum} successor(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func CheckSuccessorNumAtLeast(expectedNum: Int64, term: Terminator, topLevelFunc: Function,
        result: CHIRCheckResult): Bool {
        let realNum = term.GetSuccessors().size
        if (expectedNum > realNum) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(term)}`, " +
                "expect at least ${expectedNum} successor(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func CheckLocalId(blockGroup: BlockGroup, topLevelFunc: Function, result: CHIRCheckResult): Unit {
        let allIds = HashSet<String>()
        let duplicatedLocalIds = ArrayList<String>()
        let duplicatedLocalIdSet = HashSet<String>()
        let exprResWithoutId = ArrayList<Expression>()
        for (param in topLevelFunc.GetParams()) {
            let id = param.GetIdentifier()
            if (!CHIRCheckerAddIdentifier(allIds, id)) {
                CHIRCheckerAddUniqueString(duplicatedLocalIds, duplicatedLocalIdSet, id)
            }
        }
        CheckLocalIdInBlockGroup(blockGroup, allIds, duplicatedLocalIds, duplicatedLocalIdSet, exprResWithoutId)
        if (!duplicatedLocalIds.isEmpty()) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, there are duplicated local id: " +
                JoinStrings(duplicatedLocalIds, ", "))
        }
        for (expr in exprResWithoutId) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, the result of expression " +
                "${expr.ToString(0)} doesn't have identifier.")
        }
    }

    private func CheckLocalIdInBlockGroup(blockGroup: BlockGroup, allIds: HashSet<String>,
        duplicatedLocalIds: ArrayList<String>, duplicatedLocalIdSet: HashSet<String>,
        exprResWithoutId: ArrayList<Expression>): Unit {
        for (block in blockGroup.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (let Some(resultValue) <- expr.GetResult()) {
                    let id = resultValue.GetIdentifier()
                    if (id.isEmpty()) {
                        exprResWithoutId.add(expr)
                    } else if (!CHIRCheckerAddIdentifier(allIds, id)) {
                        CHIRCheckerAddUniqueString(duplicatedLocalIds, duplicatedLocalIdSet, id)
                    }
                }
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    for (param in lambdaExpr.GetParams()) {
                        let id = param.GetIdentifier()
                        if (!CHIRCheckerAddIdentifier(allIds, id)) {
                            CHIRCheckerAddUniqueString(duplicatedLocalIds, duplicatedLocalIdSet, id)
                        }
                    }
                }
                for (nestedGroup in expr.GetBlockGroups()) {
                    CheckLocalIdInBlockGroup(nestedGroup, allIds, duplicatedLocalIds, duplicatedLocalIdSet,
                        exprResWithoutId)
                }
            }
        }
    }

    private func CheckUnreachableOpAndGenericTyInFuncBody(blockGroup: BlockGroup, topLevelFunc: Function,
        result: CHIRCheckResult): Unit {
        let reachableValues = ArrayList<Value>()
        let reachableValueCounts = HashMap<Int64, Int64>()
        let reachableGenericTypes = ArrayList<GenericType>()
        CheckUnreachableOpAndGenericTyInBG(blockGroup, topLevelFunc, reachableValues, reachableValueCounts,
            reachableGenericTypes, result)
    }

    private func CheckUnreachableOpAndGenericTyInBG(blockGroup: BlockGroup, topLevelFunc: Function,
        reachableValues: ArrayList<Value>, reachableValueCounts: HashMap<Int64, Int64>,
        reachableGenericTypes: ArrayList<GenericType>, result: CHIRCheckResult): Unit {
        let valueSize = reachableValues.size
        let typeSize = reachableGenericTypes.size
        if (let Some(ownerExpr) <- blockGroup.GetOwnerExpression()) {
            if (let Some(lambdaExpr) <- (ownerExpr as Lambda)) {
                for (genericTy in lambdaExpr.GetGenericTypeParams()) {
                    reachableGenericTypes.add(genericTy)
                }
                for (param in lambdaExpr.GetParams()) {
                    CHIRCheckerAddReachableValue(reachableValues, reachableValueCounts, param)
                    if (let Some(paramTy) <- param.GetType()) {
                        if (!GenericTypeIsInContainer(paramTy, reachableGenericTypes)) {
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
                for (genericTy in fn.GetGenericTypeParams()) {
                    reachableGenericTypes.add(genericTy)
                }
                for (param in fn.GetParams()) {
                    CHIRCheckerAddReachableValue(reachableValues, reachableValueCounts, param)
                    if (let Some(paramTy) <- param.GetType()) {
                        if (!GenericTypeIsInContainer(paramTy, reachableGenericTypes)) {
                            result.AddError("in function ${topLevelFunc.GetIdentifier()}, generic type " +
                            "${param.ToString(0)}is unreachable, the type is parameter in function " +
                            "${fn.GetIdentifier()}.")
                    }
                }
            }
        }
        if (let Some(entryBlock) <- blockGroup.GetEntryBlock()) {
            let visitedBlocks = HashSet<Int64>()
            CheckUnreachableOpAndGenericTyInBlock(entryBlock, topLevelFunc, reachableValues, reachableGenericTypes,
                reachableValueCounts, visitedBlocks, result)
        }
        CHIRCheckerTrimValues(reachableValues, reachableValueCounts, valueSize)
        CHIRCheckerTrimGenericTypes(reachableGenericTypes, typeSize)
    }

    private func CheckUnreachableOpAndGenericTyInBlock(block: Block, topLevelFunc: Function,
        reachableValues: ArrayList<Value>, reachableGenericTypes: ArrayList<GenericType>,
        reachableValueCounts: HashMap<Int64, Int64>, visitedBlocks: HashSet<Int64>, result: CHIRCheckResult): Unit {
        if (visitedBlocks.contains(block.nodeId)) {
            return
        }
        visitedBlocks.add(block.nodeId)
        let valueSize = reachableValues.size
        for (expr in block.GetExpressionsRef()) {
            let typeSize = reachableGenericTypes.size
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                for (genericTy in lambdaExpr.GetGenericTypeParams()) {
                    reachableGenericTypes.add(genericTy)
                }
            }
            CheckUnreachableOpAndGenericTyInExpr(expr, topLevelFunc, reachableValueCounts, reachableGenericTypes, result)
            if (let Some(resultValue) <- expr.GetResult()) {
                CHIRCheckerAddReachableValue(reachableValues, reachableValueCounts, resultValue)
            }
            for (nestedGroup in expr.GetBlockGroups()) {
                CheckUnreachableOpAndGenericTyInBG(nestedGroup, topLevelFunc, reachableValues, reachableValueCounts,
                    reachableGenericTypes, result)
            }
            CHIRCheckerTrimGenericTypes(reachableGenericTypes, typeSize)
            if (let Some(term) <- expr.AsTerminator()) {
                for (successor in term.GetSuccessors()) {
                    CheckUnreachableOpAndGenericTyInBlock(successor, topLevelFunc, reachableValues,
                        reachableGenericTypes, reachableValueCounts, visitedBlocks, result)
                }
            }
        }
        CHIRCheckerTrimValues(reachableValues, reachableValueCounts, valueSize)
    }

    private func CheckUnreachableOpAndGenericTyInExpr(expr: Expression, topLevelFunc: Function,
        reachableValueCounts: HashMap<Int64, Int64>,
        reachableGenericTypes: ArrayList<GenericType>, result: CHIRCheckResult): Unit {
        for (operand in expr.GetOperands()) {
            if (operand.IsLiteral() || operand.IsGlobal()) {
                continue
            }
            if (!CHIRCheckerContainsValue(reachableValueCounts, operand)) {
                result.AddError("in function ${topLevelFunc.GetIdentifier()}, ${operand.GetIdentifier()} in " +
                    "${expr.ToString(0)} is unreachable.")
            }
        }
        if (let Some(resultValue) <- expr.GetResult()) {
            if (let Some(resultTy) <- resultValue.GetType()) {
                if (!GenericTypeIsInContainer(resultTy, reachableGenericTypes)) {
                    result.AddError("in function ${topLevelFunc.GetIdentifier()}, generic type " +
                        "${resultTy.ToString()} is unreachable, the type is from result in expression " +
                        "${expr.ToString(0)}.")
                }
            }
        }
        if (let Some(allocateExpr) <- (expr as Allocate)) {
            CheckReachableGenericType(allocateExpr.GetType(), "allocated type", expr, topLevelFunc,
                reachableGenericTypes, result)
        } else if (let Some(funcCallExpr) <- (expr as FuncCall)) {
            var instIdx: Int64 = 0
            let instantiatedTypeArgs = funcCallExpr.GetInstantiatedTypeArgs()
            while (instIdx < instantiatedTypeArgs.size) {
                CheckReachableGenericType(instantiatedTypeArgs[instIdx],
                    "${instIdx}-th instantiated type args", expr, topLevelFunc, reachableGenericTypes, result)
                instIdx++
            }
            if (let Some(thisTy) <- funcCallExpr.GetThisType()) {
                CheckReachableGenericType(thisTy, "ThisType", expr, topLevelFunc, reachableGenericTypes, result)
            }
        } else if (let Some(rttiStaticExpr) <- (expr as GetRTTIStatic)) {
            CheckReachableGenericType(rttiStaticExpr.GetRTTIType(), "rtti type", expr, topLevelFunc,
                reachableGenericTypes, result)
        } else if (let Some(instanceOfExpr) <- (expr as InstanceOf)) {
            CheckReachableGenericType(instanceOfExpr.GetType(), "instanceOf type", expr, topLevelFunc,
                reachableGenericTypes, result)
        } else if (let Some(rawArrayExpr) <- (expr as RawArrayAllocate)) {
            CheckReachableGenericType(rawArrayExpr.GetElementType(), "element type", expr, topLevelFunc,
                reachableGenericTypes, result)
        } else if (let Some(intrinsicExpr) <- (expr as Intrinsic)) {
            var intrinsicIdx: Int64 = 0
            let intrinsicTypeArgs = intrinsicExpr.GetInstantiatedTypeArgs()
            while (intrinsicIdx < intrinsicTypeArgs.size) {
                CheckReachableGenericType(intrinsicTypeArgs[intrinsicIdx],
                    "${intrinsicIdx}-th instantiated type args", expr, topLevelFunc, reachableGenericTypes, result)
                intrinsicIdx++
            }
        }
    }

    private func CheckReachableGenericType(ty: Type, label: String, expr: Expression, topLevelFunc: Function,
        reachableGenericTypes: ArrayList<GenericType>, result: CHIRCheckResult): Unit {
        if (!GenericTypeIsInContainer(ty, reachableGenericTypes)) {
            result.AddError("in function ${topLevelFunc.GetIdentifier()}, generic type ${ty.ToString()} is " +
                "unreachable, the type is ${label} in expression ${expr.ToString(0)}.")
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

private func CHIRCheckerAddIdentifier(values: HashSet<String>, identifier: String): Bool {
    if (values.contains(identifier)) {
        return false
    }
    values.add(identifier)
    return true
}

private func CHIRCheckerAddUniqueString(values: ArrayList<String>, valueSet: HashSet<String>, value: String): Unit {
    if (valueSet.contains(value)) {
        return
    }
    valueSet.add(value)
    values.add(value)
}

private func CHIRCheckerAddReachableValue(values: ArrayList<Value>, counts: HashMap<Int64, Int64>, value: Value): Unit {
    values.add(value)
    counts[value.nodeId] = (counts.get(value.nodeId) ?? 0) + 1
}

private func CHIRCheckerContainsValue(counts: HashMap<Int64, Int64>, value: Value): Bool {
    return (counts.get(value.nodeId) ?? 0) > 0
}

private func CHIRCheckerContainsBlock(values: ArrayList<Block>, value: Block): Bool {
    for (item in values) {
        if (item.nodeId == value.nodeId) {
            return true
        }
    }
    return false
}

private func CHIRCheckerTrimValues(values: ArrayList<Value>, counts: HashMap<Int64, Int64>, size: Int64): Unit {
    while (values.size > size) {
        let nodeId = values[values.size - 1].nodeId
        let count = counts.get(nodeId) ?? 0
        if (count <= 1) {
            counts.remove(nodeId)
        } else {
            counts[nodeId] = count - 1
        }
        values.remove(at: values.size - 1)
    }
}

private func CHIRCheckerTrimGenericTypes(values: ArrayList<GenericType>, size: Int64): Unit {
    while (values.size > size) {
        values.remove(at: values.size - 1)
    }
}

private func IndexToString(index: Int64): String {
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

private func GetExpressionString(expr: Expression): String {
    if (let Some(lambdaExpr) <- (expr as Lambda)) {
        return "lambda " + lambdaExpr.GetIdentifier()
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

private func IsFuncTypeOrClosureBaseRefType(ty: Type): Bool {
    if (ty.IsFunc()) {
        return true
    }
    if (let Some(refTy) <- (ty as RefType)) {
        return refTy.GetBaseType().IsAutoEnvBase()
    }
    return false
}

private func ConvertToNullLiteral(value: Value): Option<NullLiteral> {
    if (value.GetType().getOrThrow().IsNothing()) {
        return None
    }
    if (let Some(localVar) <- value.AsLocalVar()) {
        if (let Some(ownerExpr) <- localVar.GetExpr()) {
            if (let Some(constExpr) <- (ownerExpr as Constant)) {
                return constExpr.GetValue() as NullLiteral
            }
        }
    }
    return None
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

private func CheckTypeMustBeRef(ty: Type): Bool {
    if (!ty.IsRef()) {
        return false
    }
    var baseType = (ty as RefType).getOrThrow().GetBaseType()
    if (baseType.IsReferenceType()) {
        return false
    }
    if (baseType.IsValueOrGenericType()) {
        return true
    }
    baseType = (baseType as RefType).getOrThrow().GetBaseType()
    return baseType.IsReferenceType()
}

private func CHIRCheckerIsAnyRef(ty: Type): Bool {
    if (let Some(refTy) <- (ty as RefType)) {
        return refTy.GetBaseType().IsAny()
    }
    return false
}

private func IsCType(ty: Type): Bool {
    return IsOptionalCType(ty, false)
}

private func IsStructOrCStruct(ty: Type, includeNormalStruct: Bool): Bool {
    if (!ty.IsStruct()) {
        return false
    }
    if (includeNormalStruct) {
        return true
    }
    return (ty as StructType).getOrThrow().GetStructDef().IsCStruct()
}

private func isAllowedToHaveAbstractMethod(def: CustomTypeDef): Bool {
    if (def.IsInterface()) {
        return true
    } else if (def.IsClass()) {
        return def.TestAttr(Attribute.ABSTRACT)
    } else if (let Some(extendDef) <- (def as ExtendDef)) {
        if (let Some(classType) <- (extendDef.GetExtendedType().getOrThrow() as ClassType)) {
            return classType.GetClassDef().IsAbstract()
        }
        return false
    }
    return false
}

private func IsCTypeInVArray(ty: Type): Bool {
    return IsOptionalCType(ty, true)
}

private func IsOptionalCType(ty: Type, includeNormalStruct: Bool): Bool {
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        return IsOptionalCType(varrayTy.GetElementType(), includeNormalStruct)
    }
    if (let Some(tupleTy) <- (ty as TupleType)) {
        for (elementTy in tupleTy.GetTypeArgsRef()) {
            if (!IsOptionalCType(elementTy, includeNormalStruct)) {
                return false
            }
        }
        return true
    }
    if (let Some(refTy) <- (ty as RefType)) {
        return IsOptionalCType(refTy.GetBaseType(), includeNormalStruct)
    }
    if (let Some(pointerTy) <- (ty as CPointerType)) {
        return IsOptionalCType(pointerTy.GetElementType(), includeNormalStruct)
    }
    if (let Some(funcTy) <- (ty as FuncType)) {
        if (funcTy.IsCFunc()) {
            if (!IsOptionalCType(funcTy.GetReturnType(), includeNormalStruct)) {
                return false
            }
            for (paramTy in funcTy.GetParamTypes()) {
                if (!IsOptionalCType(paramTy, includeNormalStruct)) {
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
    return IsStructOrCStruct(ty, includeNormalStruct)
}

private func IsCTypeInInout(ty: Type): Bool {
    if (ty.IsCString()) {
        return false
    }
    return IsOptionalCType(ty, true)
}

private func GenericTypeIsInContainer(ty: Type, container: ArrayList<GenericType>): Bool {
    if (let Some(genericTy) <- (ty as GenericType)) {
        for (item in container) {
            if (item.objectId == genericTy.objectId) {
                return true
            }
        }
        return false
    }
    for (argTy in ty.GetTypeArgsRef()) {
        if (!GenericTypeIsInContainer(argTy, container)) {
            return false
        }
    }
    return true
}

private func ValueSymbolToString(value: Value): String {
    if (let Some(`func`) <- value.AsFunction()) {
        var text = "Func " + `func`.GetIdentifier() +
            TypeVecToString("<", `func`.GetGenericTypeParams(), ">") + "("
        let parameters = `func`.GetParams()
        for (param in parameters) {
            text += "\n" + param.ToString(1)
        }
        if (!parameters.isEmpty()) {
            text += "\n" + IndentToString(0)
        }
        return text + "): " + `func`.GetReturnType().getOrThrow().ToString()
    }
    return value.ToString(0)
}

private func IsUnreachableApply(thisType: Option<Type>): Bool {
    if (let Some(ty) <- thisType) {
        return ty.StripAllRefs().IsNothing()
    }
    return false
}

private func FuncCanBeDynamicDispatch(`func`: Function): Bool {
    if (`func`.TestAttr(Attribute.STATIC)) {
        return !`func`.TestAttr(Attribute.PRIVATE)
    }
    return (`func`.TestAttr(Attribute.PUBLIC) || `func`.TestAttr(Attribute.PROTECTED)) &&
        `func`.TestAttr(Attribute.VIRTUAL)
}

private func CalculateAllUpperBounds(genericType: GenericType, builder: CHIRBuilder): ArrayList<Type> {
    let upperBounds = genericType.GetUpperBounds()
    let extraUpperBounds = ArrayList<Type>()
    let replaceTable = HashMap<Int64, Type>()
    for (upperBound in upperBounds) {
        let derefUpperBound = upperBound.StripAllRefs() as ClassType
        if (let None <- derefUpperBound) {
            continue
        }
        let originalType = derefUpperBound.getOrThrow().GetClassDef().GetType().getOrThrow()
        let mapping = originalType.CalculateGenericTyMapping(derefUpperBound.getOrThrow())
        CJC_ASSERT(mapping[0])
        for (originalArg in originalType.GetTypeArgsRef()) {
            if (let Some(mappedGeneric) <- (originalArg as GenericType)) {
                let instType = mapping[1].get(mappedGeneric.objectId) ?? continue
                if (instType.objectId != genericType.objectId) {
                    continue
                }
                let temp = mappedGeneric.GetUpperBounds()
                var tempIdx = temp.size - 1
                while (tempIdx >= 0) {
                    extraUpperBounds.add(temp[tempIdx], at: 0)
                    tempIdx--
                }
                replaceTable[mappedGeneric.objectId] = instType
            }
        }
    }
    for (ty in extraUpperBounds) {
        upperBounds.add(ReplaceRawGenericArgType(ty, replaceTable, builder))
    }
    return upperBounds
}

private func Generic1IsEqualOrSubTypeOfGeneric2(generic1: GenericType, generic2: GenericType,
    builder: CHIRBuilder): Bool {
    let parentUpperBounds = generic2.GetUpperBounds()
    let replaceTable = HashMap<Int64, Type>()
    replaceTable[generic2.objectId] = generic1
    let subUpperBounds = CalculateAllUpperBounds(generic1, builder)
    while (!parentUpperBounds.isEmpty()) {
        if (subUpperBounds.isEmpty()) {
            return false
        }
        let subType = subUpperBounds.remove(at: subUpperBounds.size - 1)
        var parentIdx: Int64 = 0
        while (parentIdx < parentUpperBounds.size) {
            let parentType = ReplaceRawGenericArgType(parentUpperBounds[parentIdx], replaceTable, builder)
            if (subType.IsEqualOrSubTypeOf(parentType, builder)) {
                parentUpperBounds.remove(at: parentIdx)
            } else {
                parentIdx++
            }
        }
    }
    return true
}

private func VectorTypesToString<T>(firstChar: String, types: ArrayList<T>, lastChar: String): String where T <: Type {
    var res = firstChar
    for (ty in types) {
        res += ty.ToString() + ", "
    }
    res = res[0..res.size - 2]
    return res + lastChar
}

private func IsBoxRefType(ty: Type): Bool {
    if (!ty.IsRef()) {
        return false
    }
    return (ty as RefType).getOrThrow().GetBaseType().IsBox()
}

private func GetOwnerFuncOrLambda(blockGroup: BlockGroup): Value {
    if (let Some(ownerFunc) <- blockGroup.GetOwnerFunc()) {
        return ownerFunc
    }
    let ownerExpr = blockGroup.GetOwnerExpression().getOrThrow()
    if (ownerExpr.IsLambda()) {
        return ownerExpr.GetResult().getOrThrow()
    }
    return GetOwnerFuncOrLambda(ownerExpr.GetParentBlockGroup().getOrThrow())
}

private func CollectFuncAndGenericTypesRecursively(`func`: Value,
    result: ArrayList<(Value, ArrayList<GenericType>)>): Unit {
    if (let Some(lambdaRes) <- `func`.AsLocalVar()) {
        let lambda = (lambdaRes.GetExpr().getOrThrow() as Lambda).getOrThrow()
        let parentFuncOrLambda = GetOwnerFuncOrLambda(lambda.GetParentBlockGroup().getOrThrow())
        CollectFuncAndGenericTypesRecursively(parentFuncOrLambda, result)
        result.add((lambdaRes, lambda.GetGenericTypeParams()))
    } else {
        let funcBase = `func`.AsFunction().getOrThrow()
        result.add((funcBase, funcBase.GetGenericTypeParams()))
    }
}

private func GetFuncIdentifier(`func`: Value): String {
    if (let Some(funcBase) <- `func`.AsFunction()) {
        return funcBase.GetIdentifier()
    }
    let lambda = (`func`.AsLocalVar().getOrThrow().GetExpr().getOrThrow() as Lambda).getOrThrow()
    return lambda.GetIdentifier()
}

private func ClosureTypeIsExpected(argType: Type, thisType: Type, builder: CHIRBuilder): Bool {
    if (!argType.IsAutoEnv() || !thisType.IsAutoEnv()) {
        return false
    }
    return thisType.IsEqualOrInstantiatedTypeOf(argType, builder)
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
