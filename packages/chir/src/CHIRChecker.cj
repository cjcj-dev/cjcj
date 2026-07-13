package cjcj::chir

import std.collection.*
import std.sync.{AtomicBool, Mutex}
import cjcj::option.GlobalOptions
import cjcj::utils.{CJC_ASSERT, CORE_PACKAGE_NAME, GENERIC_VIRTUAL_FUNC, INST_VIRTUAL_FUNC, OverflowStrategy,
    TaskQueue, TaskResult}

public enum CHIRCheckerRule {
    | EMPTY_BLOCK
    | CHECK_FUNC_BODY
    | GET_INSTANTIATE_VALUE_SHOULD_GONE
    | CHIR_GET_RTTI_STATIC_TYPE
    | RETURN_TYPE_NEED_BE_VOID
    | IMPORTED_CONST_VAR_SHOULD_HAVE_INITIALIZER
}

extend CHIRCheckerRule <: Equatable<CHIRCheckerRule> {
    public operator func ==(right: CHIRCheckerRule): Bool {
        return match ((this, right)) {
            case (CHIRCheckerRule.EMPTY_BLOCK, CHIRCheckerRule.EMPTY_BLOCK) => true
            case (CHIRCheckerRule.CHECK_FUNC_BODY, CHIRCheckerRule.CHECK_FUNC_BODY) => true
            case (CHIRCheckerRule.GET_INSTANTIATE_VALUE_SHOULD_GONE,
                CHIRCheckerRule.GET_INSTANTIATE_VALUE_SHOULD_GONE) => true
            case (CHIRCheckerRule.CHIR_GET_RTTI_STATIC_TYPE, CHIRCheckerRule.CHIR_GET_RTTI_STATIC_TYPE) => true
            case (CHIRCheckerRule.RETURN_TYPE_NEED_BE_VOID, CHIRCheckerRule.RETURN_TYPE_NEED_BE_VOID) => true
            case (CHIRCheckerRule.IMPORTED_CONST_VAR_SHOULD_HAVE_INITIALIZER,
                CHIRCheckerRule.IMPORTED_CONST_VAR_SHOULD_HAVE_INITIALIZER) => true
            case _ => false
        }
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

private class VirMethodFullContext {
    let srcCodeIdentifier: String
    let originalFuncType: FuncType
    let offset: UInt64
    let thisType: Type
    let srcParentType: ClassType

    init(srcCodeIdentifier: String, originalFuncType: FuncType, offset: UInt64, thisType: Type,
        srcParentType: ClassType) {
        this.srcCodeIdentifier = srcCodeIdentifier
        this.originalFuncType = originalFuncType
        this.offset = offset
        this.thisType = thisType
        this.srcParentType = srcParentType
    }
}

public class CHIRChecker {
    private let `package`: Package
    private let opts: GlobalOptions
    private let builder: CHIRBuilder
    private let identifiers: HashSet<String> = HashSet<String>()
    private let duplicatedGlobalIds: ArrayList<String> = ArrayList<String>()
    private let checkIdentMutex = Mutex()
    private let checkResult = AtomicBool(true)
    private let optionalRules: ArrayList<CHIRCheckerRule> = ArrayList<CHIRCheckerRule>()

    public init(`package`: Package, opts: GlobalOptions, builder: CHIRBuilder) {
        this.`package` = `package`
        this.opts = opts
        this.builder = builder
    }

    public func CheckPackage(enabledRules: ArrayList<CHIRCheckerRule>): Bool {
        optionalRules.add(all: enabledRules)
        ParallelCheck<Function>({ fn => CheckFunc(fn) }, `package`.GetGlobalFuncsWithBody())
        ParallelCheck<GlobalVar>({ globalVar => CheckGlobalVar(globalVar) }, `package`.GetGlobalVarsWithInit())
        ParallelCheck<GlobalVar>({ globalVar => CheckGlobalVar(globalVar) }, `package`.GetGlobalVarsWithoutInit())
        ParallelCheck<Function>({ fn => let _ = CheckFuncBase(fn) }, `package`.GetGlobalFuncsWithoutBody())
        ParallelCheck<StructDef>({ def => CheckStructDef(def) }, `package`.GetAllStructDef())
        ParallelCheck<ClassDef>({ def => CheckClassDef(def) }, `package`.GetAllClassDef())
        ParallelCheck<EnumDef>({ def => CheckEnumDef(def) }, `package`.GetAllEnumDef())
        ParallelCheck<ExtendDef>({ def => CheckExtendDef(def) }, `package`.GetAllExtendDef())
        for (id in duplicatedGlobalIds) {
            Errorln("duplicated identifier `" + id + "` found.")
        }
        return checkResult.load()
    }

    private func ParallelCheck<T>(check: (T) -> Unit, items: ArrayList<T>): Unit {
        let taskQueue = TaskQueue(Int64(opts.GetJobs()))
        let results = ArrayList<TaskResult<Unit>>()
        for (item in items) {
            results.add(taskQueue.AddTask<Unit>({ => check(item) }))
        }
        taskQueue.RunAndWaitForAllTasksCompleted()
    }

    private func CheckFunc(fn: Function): Unit {
        if (!CheckFuncBase(fn)) {
            return
        }
        if (let Some(funcTy) <- fn.GetFuncType()) {
            CheckFuncParams(fn.GetParams(), funcTy, fn.GetIdentifier())
            CheckFuncRetValue(fn.GetReturnValue(), funcTy.GetReturnType(), fn)
        }
        if (let Some(body) <- fn.GetBody()) {
            if (!fn.GetIdentifier().contains("$Mocked")) {
                CheckBlockGroup(body, fn)
            }
            CheckLocalId(body, fn)
            CheckUnreachableOpAndGenericTyInFuncBody(body)
        } else {
            Errorln("func ${fn.GetIdentifier()} doesn't have body.")
        }
        if (fn.TestAttr(Attribute.ABSTRACT)) {
            Errorln("func ${fn.GetIdentifier()} shouldn't have attribute: ABSTRACT.")
        }
    }

    private func Warningln(info: String): Unit {
        eprintln("chir checker warning:\n    " + info)
    }

    private func Errorln(info: String): Unit {
        eprintln("chir checker error:\n    " + info)
        checkResult.store(false)
    }

    private func WarningInFunc(`func`: Value, info: String): Unit {
        Warningln("in function " + `func`.GetIdentifier() + ", " + info)
    }

    private func WarningInExpr(`func`: Value, expr: Expression, info: String): Unit {
        WarningInFunc(`func`, "in `" + GetExpressionString(expr) + "`, " + info)
    }

    private func ErrorInFunc(`func`: Value, info: String): Unit {
        Errorln("in function " + `func`.GetIdentifier() + ", " + info)
    }

    private func ErrorInLambdaOrFunc(`func`: Function, lambda: Option<Lambda>, info: String): Unit {
        if (let Some(lambdaExpr) <- lambda) {
            ErrorInExpr(`func`, lambdaExpr, info)
        } else {
            ErrorInFunc(`func`, info)
        }
    }

    private func ErrorInExpr(`func`: Value, expr: Expression, info: String): Unit {
        ErrorInFunc(`func`, "in `" + GetExpressionString(expr) + "`, " + info)
    }

    private func CheckGlobalValueIdentifier(value: Value): Bool {
        let identifier = value.GetIdentifierWithoutPrefix()
        if (identifier.isEmpty()) {
            Errorln(ValueSymbolToString(value) + " doesn't have identifier.")
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
        synchronized(checkIdentMutex) {
            if (identifiers.contains(identifier)) {
                duplicatedGlobalIds.add(identifier)
                return false
            }
            identifiers.add(identifier)
        }
        return true
    }

    private func CheckCustomTypeDefIdentifier(def: CustomTypeDef): Bool {
        let identifier = def.GetIdentifierWithoutPrefix()
        if (identifier.isEmpty()) {
            Errorln(def.ToString() + " doesn't have identifier.")
            return false
        }
        synchronized(checkIdentMutex) {
            if (identifiers.contains(identifier)) {
                duplicatedGlobalIds.add(identifier)
                return false
            }
            identifiers.add(identifier)
        }
        return true
    }

    private func CheckGlobalVar(globalVar: GlobalVar): Unit {
        if (!CheckGlobalValueIdentifier(globalVar)) {
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
                Errorln("the type of global var ${globalVar.GetIdentifier()} should be ${expectedType}, " +
                    "but now it's ${globalTy.ToString()}")
            }
        } else {
            Errorln("global var ${globalVar.GetIdentifier()} doesn't have type.")
        }
        var shouldHaveInitializer = !globalVar.TestAttr(Attribute.IMPORTED) || globalVar.IsCompileTimeValue()
        if (!optionalRules.contains(CHIRCheckerRule.IMPORTED_CONST_VAR_SHOULD_HAVE_INITIALIZER) &&
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
                Errorln(errMsg)
            }
        }
        if (!globalVar.TestAttr(Attribute.COMPILER_ADD) && globalVar.GetSrcCodeIdentifier().isEmpty()) {
            Errorln("global var ${globalVar.GetIdentifier()} doesn't have src code identifier.")
        }
        if (globalVar.GetPackageName().isEmpty()) {
            Errorln("global var ${globalVar.GetIdentifier()} doesn't have package name.")
        }
        if (globalVar.GetParentCustomTypeDef().isSome() && !globalVar.TestAttr(Attribute.STATIC)) {
            Errorln("global var ${globalVar.GetIdentifier()} should be a static member var, " +
                "but it doesn't have Attribute `STATIC`.")
        } else if (globalVar.GetParentCustomTypeDef().isNone() && globalVar.TestAttr(Attribute.STATIC)) {
            Errorln("global var ${globalVar.GetIdentifier()} has Attribute `STATIC` but it isn't member var.")
        }
    }

    private func CheckFuncBase(fn: Function): Bool {
        if (!CheckGlobalValueIdentifier(fn)) {
            return false
        }
        if (!CheckFuncType(fn.GetType(), None, fn)) {
            return false
        }
        if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
            if (!CheckParentCustomTypeDef(fn, parentDef, false)) {
                return false
            }
        }
        if (fn.GetPackageName().isEmpty()) {
            Errorln("we need to set package name in func ${fn.GetIdentifier()}.")
            return false
        }
        if (!CheckOriginalLambdaInfo(fn)) {
            return false
        }
        return true
    }

    private func CheckFuncType(typeOpt: Option<Type>, lambdaOpt: Option<Lambda>, topLevelFunc: Function): Bool {
        if (typeOpt.isNone()) {
            if (lambdaOpt.isNone()) {
                Errorln("func ${topLevelFunc.GetIdentifier()} doesn't have type.")
            } else if (let Some(lambdaExpr) <- lambdaOpt) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, " +
                    "${GetExpressionString(lambdaExpr)} doesn't have type.")
            }
            return false
        }
        if (let Some(valueTy) <- typeOpt) {
            if (let Some(funcTy) <- (valueTy as FuncType)) {
                if (funcTy.IsCJFunc() && funcTy.HasVarArg()) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, this isn't CFunc, " +
                        "but it has variable length parameters.")
                    return false
                }
                if (funcTy.IsCFunc()) {
                    return CheckCFuncType(funcTy, lambdaOpt, topLevelFunc)
                }
                if (lambdaOpt.isNone() && !CheckLiftedLambdaType(topLevelFunc)) {
                    return false
                }
                if (lambdaOpt.isNone()) {
                    CheckRetureTypeIfIsVoid(topLevelFunc, funcTy)
                }
                return CheckParamTypes(funcTy.GetParamTypes(), lambdaOpt, topLevelFunc)
            }
            if (lambdaOpt.isNone()) {
                Errorln("the type of func ${topLevelFunc.GetIdentifier()} isn't func type.")
            } else if (let Some(lambdaExpr) <- lambdaOpt) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, the type of " +
                    "${GetExpressionString(lambdaExpr)} isn't func type.")
            }
        }
        return false
    }

    private func CheckOriginalLambdaInfo(fn: Function): Bool {
        if (!fn.IsLambda()) {
            return true
        }
        var res = true
        if (fn.GetOriginalLambdaType().isNone()) {
            Errorln("func ${fn.GetIdentifier()} is lifted lambda, original lambda type should be set.")
            res = false
        }
        let originalTypeParams = fn.GetOriginalGenericTypeParamsRef()
        let curTypeParams = fn.GetGenericTypeParams()
        if (originalTypeParams.size > curTypeParams.size) {
            Errorln("func ${fn.GetIdentifier()} is lifted lambda, original lambda generic type params' size is " +
                "${originalTypeParams.size}, current func's generic type params' size is ${curTypeParams.size}, " +
                "original size should be equal or less than current size.")
            res = false
        }
        return res
    }

    private func CheckLiftedLambdaType(fn: Function): Bool {
        if (!fn.IsLambda()) {
            return true
        }

        let funcTy = fn.GetFuncType().getOrThrow()
        var errMsg = "func ${fn.GetIdentifier()} is lifted lambda, its first parameter type should be Class-Env&, " +
            "but now func type is ${funcTy.ToString()}."
        let paramTypes = funcTy.GetParamTypes()
        if (paramTypes.isEmpty()) {
            Errorln(errMsg)
            return false
        }
        let firstParamType = paramTypes[0] as RefType
        if (firstParamType.isNone()) {
            Errorln(errMsg)
            return false
        }
        let firstParamTypeDeref = firstParamType.getOrThrow().GetBaseType()
        if (!firstParamTypeDeref.IsAutoEnv()) {
            Errorln(errMsg)
            return false
        }
        if (firstParamTypeDeref.IsAutoEnvBase()) {
            errMsg = "func ${fn.GetIdentifier()} is lifted lambda, its first parameter type should be Class-Env&, " +
                "but now it's Class-EnvBase&."
            Errorln(errMsg)
            return false
        }
        return true
    }

    private func CheckCFuncType(funcTy: FuncType, lambdaOpt: Option<Lambda>, topLevelFunc: Function): Bool {
        var typeMatched = true
        if (lambdaOpt.isNone() && topLevelFunc.GetParentCustomTypeDef().isSome()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, this is a member method, " +
                "but @C can only used in global function.")
            typeMatched = false
        }
        var idx: Int64 = 0
        while (idx < funcTy.GetNumOfParams()) {
            let paramTy = funcTy.GetParamType(idx)
            if (!IsCType(paramTy)) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, this is a CFunc, but the " +
                    IndexToString(idx) + " paramter type is ${paramTy.ToString()}, it's not a CType.")
                typeMatched = false
            }
            idx++
        }
        let retTy = funcTy.GetReturnType()
        if (!IsCType(retTy)) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, this is a CFunc, but return type is " +
                "${retTy.ToString()}, it's not a CType.")
            typeMatched = false
        } else if (retTy.IsVArray()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, VArray can't be CFunc's return type.")
            typeMatched = false
        }
        return typeMatched
    }

    private func CheckRetureTypeIfIsVoid(topLevelFunc: Function, funcTy: FuncType): Unit {
        if (optionalRules.contains(CHIRCheckerRule.RETURN_TYPE_NEED_BE_VOID)) {
            if (!ReturnTypeShouldBeVoid(topLevelFunc)) {
                return
            }
            if (topLevelFunc.IsConstructor() && funcTy.GetReturnType().IsUnit()) {
                return
            }
            if (!funcTy.GetReturnType().IsVoid()) {
                Errorln("function ${topLevelFunc.GetIdentifier()} is global var init, its return type is " +
                    "${funcTy.GetReturnType().ToString()}, but `Void` is expected")
            }
        } else if (funcTy.GetReturnType().IsVoid()) {
            Errorln("function ${topLevelFunc.GetIdentifier()} return type can't be `Void` in current stage")
        }
    }

    private func CheckParamTypes(paramTypes: ArrayList<Type>, lambdaOpt: Option<Lambda>, topLevelFunc: Function): Bool {
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
                    let expectedType = if (firstParamIsRef) { builder.context.GetRefTy(parentTy) } else { parentTy }
                    let anyTypeRef = builder.context.GetRefTy(builder.context.GetAnyTy().getOrThrow())
                    if (paramTy != expectedType && paramTy != anyTypeRef) {
                        Errorln("in function ${topLevelFunc.GetIdentifier()}, " +
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
                Errorln("in function ${topLevelFunc.GetIdentifier()}, ${errMsg}, " +
                    "but you should add `&` behind it.")
                typeMatched = false
                idx++
                continue
            }
            if (let Some(refTy) <- (paramTy as RefType)) {
                let baseTy = refTy.GetBaseType()
                if (baseTy.IsThis()) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, ${errMsg}, " +
                        "it shouldn't be parameter's type.")
                    typeMatched = false
                } else if (!baseTy.IsClassOrArray() && !baseTy.IsBox()) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, ${errMsg}, " +
                        "but only Class type, RawArray type and Box type can use `&`.")
                    typeMatched = false
                }
            }
            idx++
        }
        return typeMatched
    }

    private func CheckParentCustomTypeDef(fn: Function, def: CustomTypeDef, isInDef: Bool): Bool {
        if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
            if (parentDef != def) {
                Errorln("parent CustomTypeDef of func ${fn.GetIdentifier()} is " +
                    "${parentDef.GetIdentifier()}, but this function is also member method of ${def.GetIdentifier()}.")
                return false
            }
            if (isInDef) {
                return true
            }
            for (method in def.GetMethods()) {
                if (method == fn) {
                    return true
                }
            }
            Errorln("parent CustomTypeDef of func ${fn.GetIdentifier()} is " +
                "${parentDef.GetIdentifier()}, but there isn't this method in this CustomTypeDef.")
            return false
        }
        Errorln("func ${fn.GetIdentifier()} is member func of ${def.GetIdentifier()}, " +
            "but it doesn't set parent CustomTypeDef.")
        return false
    }

    private func CheckFuncParams(params: ArrayList<Parameter>, funcTy: FuncType, funcIdentifier: String): Unit {
        let paramNumInFuncType = funcTy.GetNumOfParams()
        let paramTypesInBody = ArrayList<String>()
        for (param in params) {
            paramTypesInBody.add(param.GetType().getOrThrow().ToString())
        }
        let paramTypesInFuncType = ArrayList<String>()
        for (paramType in funcTy.GetParamTypes()) {
            paramTypesInFuncType.add(paramType.ToString())
        }
        let paramsStrInBody = "(" + JoinStrings(paramTypesInBody, ", ") + ")"
        let paramsStrInFuncType = "(" + JoinStrings(paramTypesInFuncType, ", ") + ")"
        if (paramNumInFuncType != params.size) {
            let errMsg = "inconsistent number of parameters in func ${funcIdentifier}, there are " +
                "${params.size} parameter(s) in func body, but there are ${paramNumInFuncType} parameter(s) in func type.\n"
            let hint1 = "        parameter type in func body is " + paramsStrInBody + "\n"
            let hint2 = "        parameter type in func type is " + paramsStrInFuncType + "\n"
            Errorln(errMsg + hint1 + hint2)
            return
        }
        let errIdx = ArrayList<Int64>()
        var idx: Int64 = 0
        while (idx < paramNumInFuncType) {
            if (let Some(paramTy) <- params[idx].GetType()) {
                if (funcTy.GetParamType(idx) != paramTy) {
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
            let hint1 = "        parameter type in func body is " + paramsStrInBody + "\n"
            let hint2 = "        parameter type in func type is " + paramsStrInFuncType + "\n"
            Errorln(errMsg + hint1 + hint2)
        }
    }

    private func CheckFuncRetValue(retVal: Option<LocalVar>, retTy: Type, topLevelFunc: Function): Unit {
        if (retVal.isNone()) {
            if (!retTy.IsNothing() && !retTy.IsVoid()) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, you should set a return value.")
            }
            return
        }
        if (let Some(returnValue) <- retVal) {
            if (let Some(returnValueTy) <- returnValue.GetType()) {
                if (let Some(refTy) <- (returnValueTy as RefType)) {
                    if (refTy.GetBaseType() != retTy) {
                        Errorln("in function ${topLevelFunc.GetIdentifier()}, its return value is " +
                            "${returnValue.GetIdentifier()}, this value's type should be ${retTy.ToString()}&, " +
                            "but not ${returnValueTy.ToString()}.")
                    }
                } else {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, its return value is " +
                        "${returnValue.GetIdentifier()}, this value's type should be reference type.")
                }
            } else {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, its return value is " +
                    "${returnValue.GetIdentifier()}, this value doesn't have type.")
            }
        }
    }

    private func CheckCustomTypeDef(def: CustomTypeDef): Unit {
        if (!CheckCustomTypeDefIdentifier(def)) {
            return
        }
        CheckCustomType(def)
        CheckInstanceMemberVar(def)
        CheckStaticMemberVar(def)
        CheckVTable(def)
        for (method in def.GetMethods()) {
            CheckParentCustomTypeDef(method, def, true)
        }
        for (parentType in def.GetImplementedInterfaceTys()) {
            if (!parentType.GetClassDef().IsInterface()) {
                Errorln("there is non-interface type ${parentType.ToString()} in implemented interface " +
                    "list of ${def.GetIdentifier()}.")
            }
        }
    }

    private func CheckStructDef(def: StructDef): Unit {
        CheckCustomTypeDef(def)
        CheckCStruct(def)
    }

    private func CheckClassDef(def: ClassDef): Unit {
        CheckCustomTypeDef(def)
    }

    private func CheckEnumDef(def: EnumDef): Unit {
        CheckCustomTypeDef(def)
    }

    private func CheckCustomType(def: CustomTypeDef): Unit {
        if ((def as ExtendDef).isSome()) {
            return
        }
        if (def.GetType().isNone()) {
            Errorln(def.GetIdentifier() + " should set type.")
            return
        }
        if (let Some(defTy) <- def.GetType()) {
            let kind = def.GetCustomKind()
            if (kind == CustomDefKind.TYPE_STRUCT && !defTy.IsStruct()) {
                Errorln(def.GetIdentifier() + " is struct definition, but its type is " +
                    defTy.ToString() + ".")
            } else if (kind == CustomDefKind.TYPE_CLASS && !defTy.IsClass()) {
                Errorln(def.GetIdentifier() + " is class definition, but its type is " +
                    defTy.ToString() + ".")
            } else if (kind == CustomDefKind.TYPE_ENUM && !defTy.IsEnum()) {
                Errorln(def.GetIdentifier() + " is enum definition, but its type is " +
                    defTy.ToString() + ".")
            }
        }
    }

    private func CheckInstanceMemberVar(def: CustomTypeDef): Unit {
        let memberVarNames = HashSet<String>()
        for (memberVar in def.GetDirectInstanceVars()) {
            if (memberVar.name.isEmpty()) {
                Errorln("member var in ${def.GetIdentifier()} doesn't have name.")
                continue
            }
            if (memberVarNames.contains(memberVar.name)) {
                Errorln("duplicated member var name `${memberVar.name}` in ${def.GetIdentifier()}.")
            } else {
                memberVarNames.add(memberVar.name)
            }
            if (memberVar.outerDef.isNone()) {
                Errorln("member var ${memberVar.name} in ${def.GetIdentifier()} doesn't set outer " +
                    "CustomTypeDef.")
            } else if (let Some(outerDef) <- memberVar.outerDef) {
                if (outerDef != def) {
                    Errorln("outer CustomTypeDef of member var ${memberVar.name} is " +
                        "${outerDef.GetIdentifier()}, but it should be ${def.GetIdentifier()}.")
                }
            }
            if (memberVar.ty.IsInvalid()) {
                Errorln("member var ${memberVar.name} in ${def.GetIdentifier()} doesn't set type.")
            }
        }
        for (memberVar in def.GetAllInstanceVars()) {
            if (memberVar.outerDef.isNone()) {
                continue
            }
            if (let Some(outerDef) <- memberVar.outerDef) {
                if (outerDef == def) {
                    continue
                }
                if ((memberVar.TestAttr(Attribute.PUBLIC) || memberVar.TestAttr(Attribute.PROTECTED)) &&
                    memberVarNames.contains(memberVar.name)) {
                    Errorln("duplicated member var name `${memberVar.name}` in ${def.GetIdentifier()}, " +
                        "it has same name with parent class ${outerDef.GetIdentifier()} member var.")
                }
            }
        }
    }

    private func CheckStaticMemberVar(def: CustomTypeDef): Unit {
        for (memberVar in def.GetStaticMemberVars()) {
            if (!memberVar.TestAttr(Attribute.STATIC)) {
                Errorln("static member var ${memberVar.GetIdentifier()} of ${def.GetIdentifier()} " +
                    "doesn't have Attribute `STATIC`.")
            }
            if (memberVar.GetParentCustomTypeDef().isNone()) {
                Errorln("static member var ${memberVar.GetIdentifier()} doesn't set parent CustomTypeDef.")
            } else if (let Some(parentDef) <- memberVar.GetParentCustomTypeDef()) {
                if (parentDef != def) {
                    Errorln("parent CustomTypeDef of static member var ${memberVar.GetIdentifier()} is " +
                        "${parentDef.GetIdentifier()}, but it should be ${def.GetIdentifier()}.")
                }
            }
        }
    }

    private func CheckVTable(def: CustomTypeDef): Unit {
        for (vtable in def.GetDefVTable().GetTypeVTables()) {
            let parentInstType = vtable.GetSrcParentType().getOrThrow()
            let parentDef = parentInstType.GetClassDef()
            let parentOriginalType = (parentDef.GetType().getOrThrow() as ClassType).getOrThrow()
            let parentVTable = parentDef.GetDefVTable().GetExpectedTypeVTable(parentOriginalType)
            if (parentVTable.IsEmpty()) {
                Errorln("in vtable of ${def.GetIdentifier()}, parent type ${parentInstType.ToString()} " +
                    "can't be found in vtable of parent class ${parentDef.GetIdentifier()}.")
                continue
            }
            if (vtable.GetMethodNum() != parentVTable.GetMethodNum()) {
                Errorln("in vtable of ${def.GetIdentifier()}, parent type ${parentInstType.ToString()} " +
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
                    Errorln("in vtable of ${def.GetIdentifier()}, parent type ${parentInstType.ToString()}, " +
                        "the ${IndexToString(idx)} virtual method is unimplemented, but only interface " +
                        "or abstract class can have this kind of method.")
                }
                idx++
            }
        }
    }

    private func CheckCStruct(def: StructDef): Unit {
        if (!def.IsCStruct()) {
            return
        }
        for (memberVar in def.GetDirectInstanceVars()) {
            if (!IsCType(memberVar.ty)) {
                Errorln("in C-struct ${def.GetIdentifier()}, member var ${memberVar.name} has type " +
                    "${memberVar.ty.ToString()}, but it should be CType.")
            }
        }
    }

    private func CheckExtendDef(def: ExtendDef): Unit {
        CheckCustomTypeDef(def)
        if (def.extendedType.isNone()) {
            Errorln("extend definition ${def.GetIdentifier()} doesn't set extended type.")
            return
        }
        if (let Some(extendedTy) <- def.extendedType) {
            if (!extendedTy.IsCustomType() && !extendedTy.IsBuiltinType()) {
                Errorln("extend definition ${def.GetIdentifier()} extends ${extendedTy.ToString()}, " +
                    "it should be custom type or builtin type.")
            }
        }
    }

    private func CheckBlockGroup(blockGroup: BlockGroup, topLevelFunc: Function): Unit {
        if (!optionalRules.contains(CHIRCheckerRule.CHECK_FUNC_BODY)) {
            return
        }
        if (blockGroup.GetIdentifier().isEmpty()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, there is block group without identifier.")
            return
        }
        CheckTopLevelFunc(blockGroup.GetTopLevelFunc(), topLevelFunc, "block group", blockGroup.GetIdentifier())
        if (blockGroup.GetEntryBlock().isNone()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, there is no entry block in block group " +
                "${blockGroup.GetIdentifier()}.")
        }
        let ownerFunc = blockGroup.GetOwnerFunc()
        let ownerExpr = blockGroup.GetOwnerExpression()
        if (ownerFunc.isNone() && ownerExpr.isNone()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, we need to set owner func or owner " +
                "expression for block group ${blockGroup.GetIdentifier()}.")
        } else if (ownerFunc.isSome() && ownerExpr.isSome()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, we can only set owner func or owner " +
                "expression, not both for block group ${blockGroup.GetIdentifier()}.")
        }
        let blocks = blockGroup.GetBlocksRef()
        if (blocks.isEmpty()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, there is no block in block group " +
                "${blockGroup.GetIdentifier()}.")
        }
        let blockIds = HashSet<String>()
        var idx: Int64 = 0
        while (idx < blocks.size) {
            let id = blocks[idx].GetIdentifier()
            if (id.isEmpty()) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, the " +
                    IndexToString(idx) + " block's id is empty.")
            } else if (blockIds.contains(id)) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, block's id ${id} is duplicated.")
            } else {
                blockIds.add(id)
            }
            idx++
        }
        for (block in blocks) {
            CheckBlock(block, topLevelFunc)
        }
    }

    private func CheckBlock(block: Block, topLevelFunc: Function): Unit {
        if (block.GetIdentifier().isEmpty()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, there is block without identifier.")
            return
        }
        if (block.GetParentBlockGroup().isNone()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, block ${block.GetIdentifier()}'s " +
                "parent block group is null.")
        }
        CheckTopLevelFunc(block.GetTopLevelFunc(), topLevelFunc, "block", block.GetIdentifier())
        let exprs = block.GetExpressionsRef()
        if (optionalRules.contains(CHIRCheckerRule.EMPTY_BLOCK) && exprs.isEmpty()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, there is no expression in block " +
                "${block.GetIdentifier()}.")
        }
        if (!exprs.isEmpty()) {
            var idx: Int64 = 0
            while (idx + 1 < exprs.size) {
                if (exprs[idx].IsTerminator()) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, terminator found in the middle " +
                        "of block ${block.GetIdentifier()}.")
                    break
                }
                idx++
            }
            if (!exprs[exprs.size - 1].IsTerminator()) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, the last expression in block " +
                    "${block.GetIdentifier()} is not terminator.")
            } else if (let Some(term) <- exprs[exprs.size - 1].AsTerminator()) {
                CheckTerminatorJump(term, topLevelFunc)
            } else {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, terminator " +
                    "${exprs[exprs.size - 1].ToString(0)} is not a Terminator node.")
            }
        }
        CheckPredecessors(block, topLevelFunc)
        for (expr in exprs) {
            CheckExpression(expr, topLevelFunc)
        }
    }

    private func CheckTerminatorJump(term: Terminator, topLevelFunc: Function): Unit {
        if (let Some(parentBlock) <- term.GetParentBlock()) {
            if (let Some(curGroup) <- parentBlock.GetParentBlockGroup()) {
                for (successor in term.GetSuccessors()) {
                    if (let Some(successorGroup) <- successor.GetParentBlockGroup()) {
                        if (successorGroup != curGroup) {
                            Errorln("in function ${topLevelFunc.GetIdentifier()}, terminator " +
                                "${term.ToString(0)} in block group ${curGroup.GetIdentifier()} jumps to an " +
                                "unreachable block ${successor.GetIdentifier()} in block group " +
                                "${successorGroup.GetIdentifier()}")
                        }
                    } else {
                        Errorln("in function ${topLevelFunc.GetIdentifier()}, terminator ${term.ToString(0)} " +
                            "jumps to block ${successor.GetIdentifier()} without parent block group.")
                    }
                }
            }
        }
    }

    private func CheckPredecessors(block: Block, topLevelFunc: Function): Unit {
        for (predecessor in block.GetPredecessorsRef()) {
            if (let Some(term) <- predecessor.GetTerminator()) {
                var found = false
                for (successor in term.GetSuccessors()) {
                    if (successor == block) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, block ${block.GetIdentifier()}'s " +
                        "predecessor is ${predecessor.GetIdentifier()}, but block ${predecessor.GetIdentifier()}'s " +
                        "successor is not ${block.GetIdentifier()}.")
                }
            } else {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, block ${block.GetIdentifier()}'s " +
                    "predecessor ${predecessor.GetIdentifier()} doesn't have terminator.")
            }
        }
        if (let Some(term) <- block.GetTerminator()) {
            for (successor in term.GetSuccessors()) {
                var found = false
                for (predecessor in successor.GetPredecessorsRef()) {
                    if (predecessor == block) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, block ${block.GetIdentifier()} " +
                        "jumps to ${successor.GetIdentifier()}, but that block doesn't record it as predecessor.")
                }
            }
        }
    }

    private func CheckTopLevelFunc(calculatedFunc: Option<Function>, realFunc: Function, valueName: String,
        valueId: String): Unit {
        if (calculatedFunc.isNone()) {
            Errorln("in function ${realFunc.GetIdentifier()}, can't get top-level function from " +
                "${valueName} ${valueId}.")
        } else if (let Some(fn) <- calculatedFunc) {
            if (fn != realFunc) {
                Errorln("in function ${realFunc.GetIdentifier()}, get a wrong top-level function from " +
                    "${valueName} ${valueId}.\n        wrong func name is ${fn.GetIdentifier()}.")
            }
        }
    }

    private func CheckExpression(expr: Expression, topLevelFunc: Function): Unit {
        if (expr.GetParentBlock().isNone()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, expression ${expr.ToString(0)} " +
                "doesn't have parent block.")
            return
        }
        if (!expr.IsTerminator() && expr.GetResult().isNone()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
                "this expression should have result.")
            return
        }
        if (let Some(resultValue) <- expr.GetResult()) {
            if (let Some(ownerExpr) <- resultValue.GetExpr()) {
                if ((ownerExpr as Value).getOrThrow() != (expr as Value).getOrThrow()) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, result " +
                        "${resultValue.GetIdentifier()} is owned by a different expression.")
                }
            } else {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, result ${resultValue.GetIdentifier()} " +
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
                Errorln("in function ${topLevelFunc.GetIdentifier()}, operand ${operand.GetIdentifier()} " +
                    "is missing user ${expr.GetExprKindName()}.")
            }
        }
        for (blockGroup in expr.GetBlockGroups()) {
            if (let Some(ownerExpr) <- blockGroup.GetOwnerExpression()) {
                if ((ownerExpr as Value).getOrThrow() != (expr as Value).getOrThrow()) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, block group " +
                        "${blockGroup.GetIdentifier()} is owned by a different expression.")
                }
            } else {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, block group " +
                    "${blockGroup.GetIdentifier()} doesn't point back to owner expression.")
            }
        }
        match (expr.GetExprMajorKind()) {
            case ExprMajorKind.TERMINATOR => CheckTerminator(expr, topLevelFunc)
            case ExprMajorKind.UNARY_EXPR => CheckUnaryExpression(expr, topLevelFunc)
            case ExprMajorKind.BINARY_EXPR => CheckBinaryExpression(expr, topLevelFunc)
            case ExprMajorKind.MEMORY_EXPR => CheckMemoryExpression(expr, topLevelFunc)
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => CheckControlFlowExpression(expr, topLevelFunc)
            case ExprMajorKind.OTHERS => CheckOtherExpression(expr, topLevelFunc)
        }
    }

    private func CheckTerminator(expr: Expression, topLevelFunc: Function): Unit {
        if (let Some(term) <- expr.AsTerminator()) {
            match (expr.GetExprKind()) {
                case ExprKind.GOTO => CheckGoTo(term, topLevelFunc)
                case ExprKind.EXIT => CheckExit(term, topLevelFunc)
                case ExprKind.BRANCH => CheckBranch(term, topLevelFunc)
                case ExprKind.MULTIBRANCH => CheckMultiBranch(term, topLevelFunc)
                case ExprKind.RAISE_EXCEPTION => CheckRaiseException(term, topLevelFunc)
                case ExprKind.APPLY_WITH_EXCEPTION =>
                    CheckApplyWithException((term as ApplyWithException).getOrThrow(), topLevelFunc)
                case ExprKind.INVOKE_WITH_EXCEPTION =>
                    CheckInvokeWithException((term as InvokeWithException).getOrThrow(), topLevelFunc)
                case ExprKind.INVOKESTATIC_WITH_EXCEPTION =>
                    CheckInvokeStaticWithException((term as InvokeStaticWithException).getOrThrow(), topLevelFunc)
                case ExprKind.INT_OP_WITH_EXCEPTION =>
                    CheckIntOpWithException((term as IntOpWithException).getOrThrow(), topLevelFunc)
                case ExprKind.SPAWN_WITH_EXCEPTION =>
                    CheckSpawnWithException((term as SpawnWithException).getOrThrow(), topLevelFunc)
                case ExprKind.TYPECAST_WITH_EXCEPTION =>
                    CheckTypeCastWithException((term as TypeCastWithException).getOrThrow(), topLevelFunc)
                case ExprKind.INTRINSIC_WITH_EXCEPTION =>
                    CheckIntrinsicWithException((term as IntrinsicWithException).getOrThrow(), topLevelFunc)
                case ExprKind.ALLOCATE_WITH_EXCEPTION =>
                    CheckAllocateWithException((term as AllocateWithException).getOrThrow(), topLevelFunc)
                case ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION =>
                    CheckRawArrayAllocateWithException((term as RawArrayAllocateWithException).getOrThrow(), topLevelFunc)
                case _ => WarningInExpr(topLevelFunc, expr,
                    "find unrecongnized ExprKind `" + expr.GetExprKindName() + "`.")
            }
        } else {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, ${expr.ToString(0)} is terminator kind " +
                "but not a Terminator node.")
        }
    }

    private func CheckGoTo(term: Terminator, topLevelFunc: Function): Unit {
        OperandNumIsEqual(0, term, topLevelFunc)
        SuccessorNumIsEqual(1, term, topLevelFunc)
        ShouldNotHaveResult(term, topLevelFunc)
    }

    private func CheckExit(term: Terminator, topLevelFunc: Function): Unit {
        OperandNumIsEqual(0, term, topLevelFunc)
        SuccessorNumIsEqual(0, term, topLevelFunc)
        ShouldNotHaveResult(term, topLevelFunc)
    }

    private func CheckBranch(term: Terminator, topLevelFunc: Function): Unit {
        ShouldNotHaveResult(term, topLevelFunc)
        if (!OperandNumIsEqual(1, term, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, term, topLevelFunc)) {
            return
        }
        if (let Some(condTy) <- term.GetOperand(0).GetType()) {
            if (!condTy.IsBoolean() && !condTy.IsNothing()) {
                TypeCheckError(term, term.GetOperand(0), "Bool", topLevelFunc)
            }
        }
    }

    private func CheckMultiBranch(term: Terminator, topLevelFunc: Function): Unit {
        ShouldNotHaveResult(term, topLevelFunc)
        if (!OperandNumIsEqual(1, term, topLevelFunc)) {
            return
        }
        if (!SuccessorNumAtLeast(2, term, topLevelFunc)) {
            return
        }
        if (let Some(condTy) <- term.GetOperand(0).GetType()) {
            if (!condTy.IsInteger()) {
                TypeCheckError(term, term.GetOperand(0), "Int", topLevelFunc)
            }
        }
        if (let Some(multiBranch) <- (term as MultiBranch)) {
            if (multiBranch.GetNormalBlocks().size != multiBranch.GetCaseVals().size) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(term)}`, value's size and normal block's size must be equal, " +
                    "but now there are ${multiBranch.GetCaseVals().size} value(s) and " +
                    "${multiBranch.GetNormalBlocks().size} normal block(s).")
            }
            if (multiBranch.GetDefaultBlock().GetIdentifier().isEmpty()) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                    "${GetExpressionString(term)}`, default block shouldn't be empty.")
            }
        }
    }

    private func CheckRaiseException(term: Terminator, topLevelFunc: Function): Unit {
        ShouldNotHaveResult(term, topLevelFunc)
        if (!OperandNumAtLeast(1, term, topLevelFunc)) {
            return
        }
        let exceptionValue = term.GetOperand(0)
        if (let Some(exceptionType) <- exceptionValue.GetType()) {
            let strippedTy = exceptionType.StripAllRefs()
            if (!exceptionType.IsRef() && !exceptionType.IsGeneric() && !strippedTy.IsClass()) {
                TypeCheckError(term, exceptionValue, "Class& or Generic", topLevelFunc)
            }
        }
    }

    private func CheckUnaryExpression(expr: Expression, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        CheckUnaryExprBase(UnaryExprBase((expr as UnaryExpression).getOrThrow()), topLevelFunc)
    }

    private func CheckBinaryExpression(expr: Expression, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        CheckBinaryExprBase(BinaryExprBase((expr as BinaryExpression).getOrThrow()), topLevelFunc)
    }

    private func CheckIntOpWithException(expr: IntOpWithException, topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (!OperandNumIsEqual([1, 2], expr, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        let exprKind = expr.GetOpKind()
        if (ExprKindIndex(exprKind) >= ExprKindIndex(ExprKind.NEG) &&
            ExprKindIndex(exprKind) <= ExprKindIndex(ExprKind.BITNOT)) {
            CheckUnaryExprBase(UnaryExprBase(expr), topLevelFunc)
        } else if (ExprKindIndex(exprKind) >= ExprKindIndex(ExprKind.ADD) &&
            ExprKindIndex(exprKind) <= ExprKindIndex(ExprKind.OR)) {
            CheckBinaryExprBase(BinaryExprBase(expr), topLevelFunc)
        } else {
            WarningInExpr(topLevelFunc, expr, "find unrecongnized ExprKind " + expr.GetOpKindName() + ".")
        }
    }

    private func CheckUnaryExprBase(expr: UnaryExprBase, topLevelFunc: Function): Unit {
        let operand = expr.GetOperand()
        let operandType = operand.GetType().getOrThrow()
        if (operandType.IsNothing()) {
            return
        }
        if (expr.GetOpKind() == ExprKind.NOT && !operandType.IsBoolean()) {
            TypeCheckError(expr.GetRawExpr(), operand, "Bool", topLevelFunc)
        } else if (expr.GetOpKind() == ExprKind.BITNOT && !operandType.IsInteger()) {
            TypeCheckError(expr.GetRawExpr(), operand, "Int", topLevelFunc)
        } else if (expr.GetOpKind() == ExprKind.NEG && !operandType.IsInteger() && !operandType.IsFloat()) {
            TypeCheckError(expr.GetRawExpr(), operand, "Int or Float", topLevelFunc)
        }
        let resultValue = expr.GetResult().getOrThrow()
        if (operandType != resultValue.GetType().getOrThrow()) {
            TypeCheckError(expr.GetRawExpr(), resultValue, operandType.ToString(), topLevelFunc)
        }
        if (expr.GetOpKind() == ExprKind.NEG) {
            OverflowStrategyMustBeValid(expr.GetOverflowStrategy(), expr.GetRawExpr(), topLevelFunc)
        }
    }

    private func CheckBinaryExprBase(expr: BinaryExprBase, topLevelFunc: Function): Unit {
        if (expr.GetLHSOperand().GetType().getOrThrow().IsNothing() ||
            expr.GetRHSOperand().GetType().getOrThrow().IsNothing()) {
            return
        }
        let exprKind = expr.GetOpKind()
        if (ExprKindIndex(exprKind) >= ExprKindIndex(ExprKind.ADD) &&
            ExprKindIndex(exprKind) <= ExprKindIndex(ExprKind.MOD)) {
            CheckCalculExpression(expr, topLevelFunc)
        } else if (exprKind == ExprKind.EXP) {
            CheckExponentiationExpression(expr, topLevelFunc)
        } else if (ExprKindIndex(exprKind) >= ExprKindIndex(ExprKind.LSHIFT) &&
            ExprKindIndex(exprKind) <= ExprKindIndex(ExprKind.BITXOR)) {
            CheckBitExpression(expr, topLevelFunc)
        } else if (ExprKindIndex(exprKind) >= ExprKindIndex(ExprKind.LT) &&
            ExprKindIndex(exprKind) <= ExprKindIndex(ExprKind.NOTEQUAL)) {
            CheckCompareExpression(expr, topLevelFunc)
        } else if (ExprKindIndex(exprKind) >= ExprKindIndex(ExprKind.AND) &&
            ExprKindIndex(exprKind) <= ExprKindIndex(ExprKind.OR)) {
            CheckLogicExpression(expr, topLevelFunc)
        } else {
            WarningInExpr(topLevelFunc, expr.GetRawExpr(),
                "find unrecongnized ExprKind " + expr.GetExprKindName() + ".")
        }
    }

    private func OverflowStrategyMustBeValid(ofs: OverflowStrategy, expr: Expression,
        topLevelFunc: Function): Unit {
        if (ofs == OverflowStrategy.OVERFLOW_STRATEGY_END) {
            ErrorInExpr(topLevelFunc, expr, "overflow strategy is invalid.")
        }
    }

    private func CheckCalculExpression(expr: BinaryExprBase, topLevelFunc: Function): Unit {
        let leftOperand = expr.GetLHSOperand()
        let rightOperand = expr.GetRHSOperand()
        let leftOpType = leftOperand.GetType().getOrThrow()
        let rightOpType = rightOperand.GetType().getOrThrow()
        let resultValue = expr.GetResult().getOrThrow()
        if (expr.GetOpKind() == ExprKind.MOD) {
            if (!leftOpType.IsInteger()) { TypeCheckError(expr.GetRawExpr(), leftOperand, "Int or UInt", topLevelFunc) }
            if (!rightOpType.IsInteger()) { TypeCheckError(expr.GetRawExpr(), rightOperand, "Int or UInt", topLevelFunc) }
        } else {
            if (!leftOpType.IsNumeric()) { TypeCheckError(expr.GetRawExpr(), leftOperand, "numeric", topLevelFunc) }
            if (!rightOpType.IsNumeric()) { TypeCheckError(expr.GetRawExpr(), rightOperand, "numeric", topLevelFunc) }
        }
        if (leftOpType != rightOpType) {
            ErrorInFunc(topLevelFunc,
                "left operand and right operand don't have same type in " + resultValue.ToString(0) + ".")
        } else if (resultValue.GetType().getOrThrow() != leftOpType) {
            ErrorInFunc(topLevelFunc,
                "the result value and operand don't have same type in " + resultValue.ToString(0) + ".")
        }
        OverflowStrategyMustBeValid(expr.GetOverflowStrategy(), expr.GetRawExpr(), topLevelFunc)
    }

    private func CheckExponentiationExpression(expr: BinaryExprBase, topLevelFunc: Function): Unit {
        let leftOperand = expr.GetLHSOperand()
        let rightOperand = expr.GetRHSOperand()
        let leftOpType = leftOperand.GetType().getOrThrow()
        let rightOpType = rightOperand.GetType().getOrThrow()
        if (leftOpType.GetTypeKind() != TypeKind.TYPE_INT64 && leftOpType.GetTypeKind() != TypeKind.TYPE_FLOAT64) {
            TypeCheckError(expr.GetRawExpr(), leftOperand, "Int64 or Float64", topLevelFunc)
        }
        let resultValue = expr.GetResult().getOrThrow()
        let resultType = resultValue.GetType().getOrThrow()
        if (leftOpType.GetTypeKind() == TypeKind.TYPE_INT64) {
            if (rightOpType.GetTypeKind() != TypeKind.TYPE_UINT64) {
                TypeCheckError(expr.GetRawExpr(), rightOperand, "UInt64", topLevelFunc)
            }
            if (resultType.GetTypeKind() != TypeKind.TYPE_INT64) {
                TypeCheckError(expr.GetRawExpr(), resultValue, "Int64", topLevelFunc)
            }
        } else if (leftOpType.GetTypeKind() == TypeKind.TYPE_FLOAT64) {
            if (rightOpType.GetTypeKind() != TypeKind.TYPE_INT64 && rightOpType.GetTypeKind() != TypeKind.TYPE_FLOAT64) {
                TypeCheckError(expr.GetRawExpr(), rightOperand, "Int64 or Float64", topLevelFunc)
            }
            if (resultType.GetTypeKind() != TypeKind.TYPE_FLOAT64) {
                TypeCheckError(expr.GetRawExpr(), resultValue, "Float64", topLevelFunc)
            }
        }
        OverflowStrategyMustBeValid(expr.GetOverflowStrategy(), expr.GetRawExpr(), topLevelFunc)
    }

    private func CheckBitExpression(expr: BinaryExprBase, topLevelFunc: Function): Unit {
        let leftOperand = expr.GetLHSOperand()
        let rightOperand = expr.GetRHSOperand()
        if (!leftOperand.GetType().getOrThrow().IsInteger()) {
            TypeCheckError(expr.GetRawExpr(), leftOperand, "Int", topLevelFunc)
        }
        if (!rightOperand.GetType().getOrThrow().IsInteger()) {
            TypeCheckError(expr.GetRawExpr(), rightOperand, "Int", topLevelFunc)
        }
        if (expr.GetOpKind() == ExprKind.LSHIFT || expr.GetOpKind() == ExprKind.RSHIFT) {
            OverflowStrategyMustBeValid(expr.GetOverflowStrategy(), expr.GetRawExpr(), topLevelFunc)
        }
    }

    private func CheckCompareExpression(expr: BinaryExprBase, topLevelFunc: Function): Unit {
        let leftOpType = expr.GetLHSOperand().GetType().getOrThrow()
        let rightOpType = expr.GetRHSOperand().GetType().getOrThrow()
        let resultValue = expr.GetResult().getOrThrow()
        if (leftOpType != rightOpType) {
            ErrorInFunc(topLevelFunc,
                "left operand and right operand don't have same type in " + resultValue.ToString(0) + ".")
        }
        if (!resultValue.GetType().getOrThrow().IsBoolean()) {
            TypeCheckError(expr.GetRawExpr(), resultValue, "Bool", topLevelFunc)
        }
    }

    private func CheckLogicExpression(expr: BinaryExprBase, topLevelFunc: Function): Unit {
        let leftOperand = expr.GetLHSOperand()
        let rightOperand = expr.GetRHSOperand()
        if (!leftOperand.GetType().getOrThrow().IsBoolean()) {
            TypeCheckError(expr.GetRawExpr(), leftOperand, "Bool", topLevelFunc)
        }
        if (!rightOperand.GetType().getOrThrow().IsBoolean()) {
            TypeCheckError(expr.GetRawExpr(), rightOperand, "Bool", topLevelFunc)
        }
        let resultValue = expr.GetResult().getOrThrow()
        if (!resultValue.GetType().getOrThrow().IsBoolean()) {
            TypeCheckError(expr.GetRawExpr(), resultValue, "Bool", topLevelFunc)
        }
    }

    private func CheckMemoryExpression(expr: Expression, topLevelFunc: Function): Unit {
        match (expr.GetExprKind()) {
            case ExprKind.ALLOCATE => CheckAllocate((expr as Allocate).getOrThrow(), topLevelFunc)
            case ExprKind.LOAD => CheckLoad(expr, topLevelFunc)
            case ExprKind.STORE => CheckStore(expr, topLevelFunc)
            case ExprKind.GET_ELEMENT_REF => CheckGetElementRef((expr as GetElementRef).getOrThrow(), topLevelFunc)
            case ExprKind.GET_ELEMENT_BY_NAME =>
                CheckGetElementByName((expr as GetElementByName).getOrThrow(), topLevelFunc)
            case ExprKind.STORE_ELEMENT_REF =>
                CheckStoreElementRef((expr as StoreElementRef).getOrThrow(), topLevelFunc)
            case ExprKind.STORE_ELEMENT_BY_NAME =>
                CheckStoreElementByName((expr as StoreElementByName).getOrThrow(), topLevelFunc)
            case _ => WarningInExpr(topLevelFunc, expr,
                "find unrecongnized ExprKind `" + expr.GetExprKindName() + "`.")
        }
    }

    private func CheckAllocate(expr: Allocate, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(0, expr, topLevelFunc)) {
            return
        }
        CheckAllocateBase(AllocateBase(expr), topLevelFunc)
    }

    private func CheckAllocateWithException(expr: AllocateWithException, topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (!OperandNumIsEqual(0, expr, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        CheckAllocateBase(AllocateBase(expr), topLevelFunc)
    }

    private func CheckAllocateBase(expr: AllocateBase, topLevelFunc: Function): Unit {
        let resultValue = expr.GetResult().getOrThrow()
        let resultTy = resultValue.GetType().getOrThrow()
        let allocatedType = expr.GetType()
        if (!resultTy.IsRef() ||
            (resultTy as RefType).getOrThrow().GetBaseType() != allocatedType) {
            TypeCheckError(expr.GetRawExpr(), resultValue, allocatedType.ToString() + "&", topLevelFunc)
        }
        if (allocatedType.IsVoid()) {
            ErrorInFunc(topLevelFunc, "can't allocate `Void` type in expression " + resultValue.ToString(0))
        }
        let _ = CheckTypeIsValid(allocatedType, "allocated", expr.GetRawExpr(), topLevelFunc)
    }

    private func CheckGetElementRef(expr: GetElementRef, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        let location = expr.GetLocation()
        var locationType = location.GetType().getOrThrow()
        if (!locationType.IsRef()) {
            TypeCheckError(expr, location, locationType.ToString() + "&", topLevelFunc)
            return
        }
        let baseType = (locationType as RefType).getOrThrow().GetBaseType()
        if (!baseType.IsClass() && !baseType.IsStruct() && !baseType.IsEnum() && !baseType.IsTuple() &&
            !baseType.IsRawArray()) {
            TypeCheckError(expr, location, "Class&, Struct&, Enum&, RawArray& or Tuple&", topLevelFunc)
            return
        }
        let path = expr.GetPath()
        let resultValue = expr.GetResult().getOrThrow()
        if (path.isEmpty()) {
            ErrorInFunc(topLevelFunc, "path is empty in GetElementRef `" + resultValue.ToString(0) + "`.")
        }
        var errMsg = "wrong path: "
        for (index in path) {
            errMsg += locationType.ToString() + "[index: ${index}] --> "
            let fieldType = GetFieldOfType(locationType, index, builder)
            if (fieldType.isNone()) {
                errMsg += "unknown type, in GetElementRef `" + resultValue.ToString(0) + "`."
                ErrorInFunc(topLevelFunc, errMsg)
            } else {
                locationType = fieldType.getOrThrow()
            }
        }
        let resultType = resultValue.GetType().getOrThrow()
        if (!resultType.IsRef()) {
            TypeCheckError(expr, resultValue, resultType.ToString() + "&", topLevelFunc)
            return
        }
        let resultBaseType = (resultType as RefType).getOrThrow().GetBaseType()
        if (!TypeIsExpected(locationType, resultBaseType)) {
            TypeCheckError(expr, resultValue, locationType.ToString() + "&", topLevelFunc)
        }
    }

    private func CheckGetElementByName(expr: GetElementByName, topLevelFunc: Function): Unit {
        ErrorInExpr(topLevelFunc, expr, "you should convert this expression to `GetElementRef`.")
    }

    private func CheckStoreElementRef(expr: StoreElementRef, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        let location = expr.GetLocation()
        var locationType = location.GetType().getOrThrow()
        if (!locationType.IsRef()) {
            TypeCheckError(expr, location, locationType.ToString() + "&", topLevelFunc)
            return
        }
        let baseType = (locationType as RefType).getOrThrow().GetBaseType()
        if (!baseType.IsClass() && !baseType.IsStruct() && !baseType.IsTuple() && !baseType.IsRawArray()) {
            TypeCheckError(expr, location, "Class&, Struct&, RawArray& or Tuple&", topLevelFunc)
        }
        let path = expr.GetPath()
        let resultValue = expr.GetResult().getOrThrow()
        if (path.isEmpty()) {
            ErrorInFunc(topLevelFunc, "path is empty in StoreElementRef `" + resultValue.ToString(0) + "`.")
        }
        var pathValid = true
        var errMsg = "wrong path: "
        for (index in path) {
            errMsg += locationType.ToString() + "[index: ${index}] --> "
            let fieldType = GetFieldOfType(locationType, index, builder)
            if (fieldType.isNone()) {
                errMsg += "unknown type, in StoreElementRef `" + resultValue.ToString(0) + "`."
                ErrorInFunc(topLevelFunc, errMsg)
                pathValid = false
            } else {
                locationType = fieldType.getOrThrow()
            }
        }
        if (pathValid) {
            let value = expr.GetValue()
            if (!TypeIsExpected(value.GetType().getOrThrow(), locationType)) {
                TypeCheckError(expr, value, locationType.ToString(), topLevelFunc)
            }
        }
        if (!resultValue.GetType().getOrThrow().IsUnit()) {
            TypeCheckError(expr, resultValue, "Unit", topLevelFunc)
        }
    }

    private func CheckStoreElementByName(expr: StoreElementByName, topLevelFunc: Function): Unit {
        ErrorInExpr(topLevelFunc, expr, "you should convert this expression to `StoreElementRef`.")
    }

    private func CheckLoad(expr: Expression, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc) || !CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        let location = expr.GetOperand(0)
        if (let Some(locationTy) <- location.GetType()) {
            if (let Some(resultTy) <- expr.GetResultType()) {
                if (let Some(refTy) <- (locationTy as RefType)) {
                    if (refTy.GetBaseType() != resultTy) {
                        TypeCheckError(expr, expr.GetResult().getOrThrow(), refTy.GetBaseType().ToString(), topLevelFunc)
                    }
                } else {
                    TypeCheckError(expr, location, resultTy.ToString() + "&", topLevelFunc)
                }
            }
        }
    }

    private func CheckStore(expr: Expression, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        let value = expr.GetOperand(0)
        let location = expr.GetOperand(1)
        if (let Some(locationTy) <- location.GetType()) {
            if (let Some(valueTy) <- value.GetType()) {
                if (let Some(refTy) <- (locationTy as RefType)) {
                    if (!TypeIsExpected(valueTy, refTy.GetBaseType())) {
                        TypeCheckError(expr, value, refTy.GetBaseType().ToString(), topLevelFunc)
                    }
                } else {
                    TypeCheckError(expr, location, locationTy.ToString() + "&", topLevelFunc)
                }
            }
        }
        if (!expr.GetResult().getOrThrow().GetType().getOrThrow().IsUnit()) {
            TypeCheckError(expr, expr.GetResult().getOrThrow(), "Unit", topLevelFunc)
        }
        if (let Some(localVar) <- (location as LocalVar)) {
            if (localVar.GetExpr().getOrThrow().GetExprKind() == ExprKind.GET_ELEMENT_REF) {
                let resultValue = expr.GetResult().getOrThrow()
                Errorln("in function ${topLevelFunc.GetIdentifier()}, destination of Store `" +
                    "${resultValue.GetIdentifier()}` should not be GetElementRef.")
            }
        }
    }

    private func CheckControlFlowExpression(expr: Expression, topLevelFunc: Function): Unit {
        if (expr.GetExprKind() == ExprKind.LAMBDA) {
            CheckLambda((expr as Lambda).getOrThrow(), topLevelFunc)
            return
        }
        WarningInExpr(topLevelFunc, expr, "find unrecongnized ExprKind `" + expr.GetExprKindName() + "`.")
    }

    private func CheckOtherExpression(expr: Expression, topLevelFunc: Function): Unit {
        match (expr.GetExprKind()) {
            case ExprKind.CONSTANT => CheckConstant(expr, topLevelFunc)
            case ExprKind.DEBUGEXPR => CheckDebug((expr as Debug).getOrThrow(), topLevelFunc)
            case ExprKind.TUPLE => CheckTuple(expr, topLevelFunc)
            case ExprKind.VARRAY => CheckVArray(expr, topLevelFunc)
            case ExprKind.FIELD => CheckField((expr as Field).getOrThrow(), topLevelFunc)
            case ExprKind.GET_EXCEPTION => CheckGetException((expr as GetException).getOrThrow(), topLevelFunc)
            case ExprKind.FIELD_BY_NAME =>
                if (let Some(fieldByNameExpr) <- (expr as FieldByName)) {
                    CheckFieldByName(fieldByNameExpr, topLevelFunc)
                }
            case ExprKind.APPLY =>
                if (let Some(applyExpr) <- (expr as Apply)) {
                    CheckApply(applyExpr, topLevelFunc)
                }
            case ExprKind.INVOKE =>
                if (let Some(invokeExpr) <- (expr as Invoke)) {
                    CheckInvoke(invokeExpr, topLevelFunc)
                }
            case ExprKind.INVOKESTATIC =>
                if (let Some(invokeStaticExpr) <- (expr as InvokeStatic)) {
                    CheckInvokeStatic(invokeStaticExpr, topLevelFunc)
                }
            case ExprKind.INSTANCEOF =>
                if (let Some(instanceOfExpr) <- (expr as InstanceOf)) {
                    CheckInstanceOf(instanceOfExpr, topLevelFunc)
                }
            case ExprKind.TYPECAST =>
                OperandNumIsEqual(1, expr, topLevelFunc)
                CheckHaveResult(expr, topLevelFunc)
                if (let Some(typeCastExpr) <- (expr as TypeCast)) {
                    CheckTypeCast(typeCastExpr, topLevelFunc)
                }
            case ExprKind.BOX =>
                if (let Some(boxExpr) <- (expr as Box)) {
                    CheckBox(boxExpr, topLevelFunc)
                }
            case ExprKind.UNBOX =>
                if (let Some(unBoxExpr) <- (expr as UnBox)) {
                    CheckUnBox(unBoxExpr, topLevelFunc)
                }
            case ExprKind.TRANSFORM_TO_GENERIC =>
                if (let Some(transformExpr) <- (expr as TransformToGeneric)) {
                    CheckTransformToGeneric(transformExpr, topLevelFunc)
                }
            case ExprKind.TRANSFORM_TO_CONCRETE =>
                if (let Some(transformExpr) <- (expr as TransformToConcrete)) {
                    CheckTransformToConcrete(transformExpr, topLevelFunc)
                }
            case ExprKind.UNBOX_TO_REF =>
                if (let Some(unBoxToRefExpr) <- (expr as UnBoxToRef)) {
                    CheckUnBoxToRef(unBoxToRefExpr, topLevelFunc)
                }
            case ExprKind.RAW_ARRAY_ALLOCATE =>
                CheckRawArrayAllocate((expr as RawArrayAllocate).getOrThrow(), topLevelFunc)
            case ExprKind.RAW_ARRAY_LITERAL_INIT =>
                CheckRawArrayLiteralInit((expr as RawArrayLiteralInit).getOrThrow(), topLevelFunc)
            case ExprKind.RAW_ARRAY_INIT_BY_VALUE =>
                CheckRawArrayInitByValue((expr as RawArrayInitByValue).getOrThrow(), topLevelFunc)
            case ExprKind.SPAWN => CheckSpawn((expr as Spawn).getOrThrow(), topLevelFunc)
            case ExprKind.GET_RTTI =>
                if (let Some(getRTTIExpr) <- (expr as GetRTTI)) {
                    CheckGetRTTI(getRTTIExpr, topLevelFunc)
                }
            case ExprKind.GET_RTTI_STATIC =>
                if (let Some(getRTTIStaticExpr) <- (expr as GetRTTIStatic)) {
                    CheckGetRTTIStatic(getRTTIStaticExpr, topLevelFunc)
                }
            case ExprKind.VARRAY_BUILDER =>
                if (let Some(varrayBuilderExpr) <- (expr as VArrayBuilder)) {
                    CheckVArrayBuilder(varrayBuilderExpr, topLevelFunc)
                }
            case ExprKind.INTRINSIC =>
                if (let Some(intrinsicExpr) <- (expr as Intrinsic)) {
                    CheckIntrinsic(intrinsicExpr, topLevelFunc)
                }
            case ExprKind.GET_INSTANTIATE_VALUE => CheckGetInstantiateValue(expr, topLevelFunc)
            case _ => WarningInExpr(topLevelFunc, expr,
                "find unrecongnized ExprKind `" + expr.GetExprKindName() + "`.")
        }
    }

    private func CheckLambda(expr: Lambda, topLevelFunc: Function): Unit {
        let resultValue = expr.GetResult().getOrThrow()
        if (expr.GetIdentifier().isEmpty()) {
            ErrorInFunc(topLevelFunc, "lambda " + resultValue.GetIdentifier() + " doesn't have identifier.")
            return
        }
        if (!resultValue.GetType().getOrThrow().IsFunc()) {
            TypeCheckError(expr, resultValue, "Function", topLevelFunc)
        }
        if (expr.GetTopLevelFunc().getOrThrow() != topLevelFunc) {
            ErrorInExpr(topLevelFunc, expr, "its top-level func is " +
                expr.GetTopLevelFunc().getOrThrow().GetIdentifier() + " by calculated, but it should be " +
                topLevelFunc.GetIdentifier() + " in fact.")
        }
        let funcTy = expr.GetFuncType()
        let funcType: Option<Type> = match (funcTy) {
            case Some(ty) => Some(ty)
            case None => None
        }
        if (!CheckFuncType(funcType, expr, topLevelFunc)) {
            return
        }
        CheckFuncParams(expr.GetParams(), funcTy.getOrThrow(), expr.GetIdentifier())
        CheckBlockGroup(expr.GetBody().getOrThrow(), topLevelFunc)
        CheckFuncRetValue(expr.GetReturnValue(), funcTy.getOrThrow().GetReturnType(), topLevelFunc)
    }

    private func CheckDebug(expr: Debug, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        let resultValue = expr.GetResult().getOrThrow()
        if (!resultValue.GetType().getOrThrow().IsUnit()) {
            TypeCheckError(expr, resultValue, "Unit", topLevelFunc)
        }
        let value = expr.GetValue()
        if (!value.IsParameter() && opts.enableCompileDebug && !CheckTypeMustBeRef(value.GetType().getOrThrow())) {
            let valueType = value.GetType().getOrThrow().StripAllRefs()
            if (valueType.IsReferenceType()) {
                TypeCheckError(expr, value, valueType.ToString() + "&&", topLevelFunc)
            } else {
                TypeCheckError(expr, value, valueType.ToString() + "&", topLevelFunc)
            }
        }
    }

    private func CheckField(expr: Field, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        let location = expr.GetBase()
        var locationType = location.GetType().getOrThrow()
        if (locationType.IsRef()) {
            TypeCheckError(expr, location, locationType.StripAllRefs().ToString(), topLevelFunc)
        } else if (!locationType.IsStruct() && !locationType.IsEnum() && !locationType.IsTuple()) {
            TypeCheckError(expr, location, "Struct, Enum or Tuple", topLevelFunc)
        }
        let path = expr.GetPath()
        let result = expr.GetResult().getOrThrow()
        if (path.isEmpty()) {
            ErrorInFunc(topLevelFunc, "path is empty in Field `" + result.ToString(0) + "`.")
        }
        var errMsg = "wrong path: "
        for (index in path) {
            errMsg += locationType.ToString() + "[index: ${index}] --> "
            let fieldType = GetFieldOfType(locationType, index, builder)
            if (fieldType.isNone()) {
                errMsg += "unknown type, in Field `" + result.ToString(0) + "`."
                ErrorInFunc(topLevelFunc, errMsg)
                return
            }
            locationType = fieldType.getOrThrow()
        }
        if (!TypeIsExpected(locationType, result.GetType().getOrThrow())) {
            TypeCheckError(expr, result, locationType.ToString(), topLevelFunc)
        }
    }

    private func CheckSpawn(expr: Spawn, topLevelFunc: Function): Unit {
        if (!OperandNumAtLeast(1, expr, topLevelFunc)) {
            return
        }
        CheckSpawnBase(SpawnBase(expr), topLevelFunc)
    }

    private func CheckSpawnWithException(expr: SpawnWithException, topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (!OperandNumIsEqual([1, 2], expr, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        CheckSpawnBase(SpawnBase(expr), topLevelFunc)
    }

    private func CheckSpawnBase(expr: SpawnBase, topLevelFunc: Function): Unit {
        let objectValue = expr.GetObject()
        let objectType = objectValue.GetType().getOrThrow()
        if (!objectType.IsRef() || !(objectType as RefType).getOrThrow().GetBaseType().IsClass()) {
            TypeCheckError(expr.GetRawExpr(), objectValue, "Class&", topLevelFunc)
            return
        }
        let def = (objectType.StripAllRefs() as ClassType).getOrThrow().GetClassDef()
        if (!IsCoreFuture(def) && !IsFuncTypeOrClosureBaseRefType(objectType)) {
            ErrorInExpr(topLevelFunc, expr.GetRawExpr(), "the first operand's type is `" + objectType.ToString() +
                "`, but Class-Future& type or closure type are expected.")
        }
        if (IsFuncTypeOrClosureBaseRefType(objectType) && !expr.IsExecuteClosure()) {
            ErrorInExpr(topLevelFunc, expr.GetRawExpr(),
                "the first operand's type is closure type but you don't set `executeClosure` function")
        }
    }

    private func CheckTypeCastWithException(expr: TypeCastWithException, topLevelFunc: Function): Unit {
        let _ = expr
        let _ = topLevelFunc
    }

    private func CheckRawArrayAllocate(expr: RawArrayAllocate, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        CheckRawArrayAllocateBase(RawArrayAllocateBase(expr), topLevelFunc)
    }

    private func CheckRawArrayAllocateWithException(expr: RawArrayAllocateWithException,
        topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        CheckRawArrayAllocateBase(RawArrayAllocateBase(expr), topLevelFunc)
    }

    private func CheckRawArrayAllocateBase(expr: RawArrayAllocateBase, topLevelFunc: Function): Unit {
        let resultValue = expr.GetResult().getOrThrow()
        let resultType = resultValue.GetType().getOrThrow()
        if (!resultType.IsRef() || !resultType.StripAllRefs().IsRawArray()) {
            TypeCheckError(expr.GetRawExpr(), resultValue, "RawArray&", topLevelFunc)
            return
        }
        if (!CheckTypeIsValid(expr.GetElementType(), "element", expr.GetRawExpr(), topLevelFunc)) {
            return
        }
        let resultTypeArg = (resultType.StripAllRefs() as RawArrayType).getOrThrow().GetElementType()
        if (resultTypeArg != expr.GetElementType()) {
            TypeCheckError(expr.GetRawExpr(), resultValue,
                "RawArray<" + expr.GetElementType().ToString() + ">&", topLevelFunc)
        }
        let sizeValue = expr.GetSize()
        if (sizeValue.GetType().getOrThrow().GetTypeKind() != TypeKind.TYPE_INT64) {
            TypeCheckError(expr.GetRawExpr(), sizeValue, "Int64", topLevelFunc)
        }
    }

    private func CheckRawArrayLiteralInit(expr: RawArrayLiteralInit, topLevelFunc: Function): Unit {
        if (!OperandNumAtLeast(1, expr, topLevelFunc)) {
            return
        }
        let resultValue = expr.GetResult().getOrThrow()
        if (!resultValue.GetType().getOrThrow().IsUnit()) {
            TypeCheckError(expr, resultValue, "Unit", topLevelFunc)
        }
        let rawArray = expr.GetRawArray()
        if (!rawArray.GetType().getOrThrow().IsRef() || !rawArray.GetType().getOrThrow().StripAllRefs().IsRawArray()) {
            TypeCheckError(expr, rawArray, "RawArray&", topLevelFunc)
        }
        let rawArrayEleTy = (rawArray.GetType().getOrThrow().StripAllRefs() as RawArrayType).getOrThrow().GetElementType()
        for (element in expr.GetElements()) {
            if (!element.GetType().getOrThrow().IsEqualOrSubTypeOf(rawArrayEleTy, builder)) {
                TypeCheckError(expr, element, rawArrayEleTy.ToString(), topLevelFunc)
            }
        }
    }

    private func CheckRawArrayInitByValue(expr: RawArrayInitByValue, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(3, expr, topLevelFunc)) {
            return
        }
        let resultValue = expr.GetResult().getOrThrow()
        if (!resultValue.GetType().getOrThrow().IsUnit()) {
            TypeCheckError(expr, resultValue, "Unit", topLevelFunc)
        }
        let sizeValue = expr.GetSize()
        if (sizeValue.GetType().getOrThrow().GetTypeKind() != TypeKind.TYPE_INT64) {
            TypeCheckError(expr, sizeValue, "Int64", topLevelFunc)
        }
        let rawArray = expr.GetRawArray()
        if (!rawArray.GetType().getOrThrow().IsRef() || !rawArray.GetType().getOrThrow().StripAllRefs().IsRawArray()) {
            TypeCheckError(expr, rawArray, "RawArray&", topLevelFunc)
        } else {
            let rawArrayEleTy =
                (rawArray.GetType().getOrThrow().StripAllRefs() as RawArrayType).getOrThrow().GetElementType()
            if (rawArrayEleTy != expr.GetInitValue().GetType().getOrThrow()) {
                TypeCheckError(expr, expr.GetInitValue(), rawArrayEleTy.ToString(), topLevelFunc)
            }
        }
    }

    private func CheckGetException(expr: GetException, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(0, expr, topLevelFunc)) {
            return
        }
        let resultValue = expr.GetResult().getOrThrow()
        let resultType = resultValue.GetType().getOrThrow()
        if (!resultType.IsRef()) {
            TypeCheckError(expr, resultValue, "Object&", topLevelFunc)
            return
        }
        let baseType = (resultType as RefType).getOrThrow().GetBaseType()
        if (!baseType.IsClass()) {
            TypeCheckError(expr, resultValue, "Object&", topLevelFunc)
            return
        }
        if (!CheckCustomTypeDefIsExpected((baseType as ClassType).getOrThrow().GetClassDef(),
            CORE_PACKAGE_NAME, "Object")) {
            TypeCheckError(expr, resultValue, "Object&", topLevelFunc)
        }
    }

    private func CheckConstant(expr: Expression, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(0, expr, topLevelFunc) || !CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (let Some(constant) <- (expr as Constant)) {
            if (let Some(resultTy) <- expr.GetResultType()) {
                let literal = constant.literal
                if (literal.IsNullLit()) {
                    return
                }
                if (literal.IsBoolLit() && !resultTy.IsBoolean()) {
                    TypeCheckError(expr, expr.GetResult().getOrThrow(), "Bool", topLevelFunc)
                } else if (literal.IsIntLit() && !resultTy.IsInteger()) {
                    TypeCheckError(expr, expr.GetResult().getOrThrow(), "Int", topLevelFunc)
                } else if (literal.IsFloatLit() && !resultTy.IsFloat()) {
                    TypeCheckError(expr, expr.GetResult().getOrThrow(), "Float", topLevelFunc)
                } else if (literal.IsRuneLit() && !resultTy.IsRune()) {
                    TypeCheckError(expr, expr.GetResult().getOrThrow(), "Rune", topLevelFunc)
                } else if (literal.IsStringLit() && !resultTy.IsString()) {
                    TypeCheckError(expr, expr.GetResult().getOrThrow(), "String", topLevelFunc)
                } else if (literal.IsUnitLit() && !resultTy.IsUnit()) {
                    TypeCheckError(expr, expr.GetResult().getOrThrow(), "Unit", topLevelFunc)
                }
            }
        }
    }

    private func CheckTuple(expr: Expression, topLevelFunc: Function): Unit {
        if (!OperandNumAtLeast(1, expr, topLevelFunc) || !CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (resultTy.IsEnum()) {
                CheckEnumTuple(expr, resultTy, topLevelFunc)
            } else if (resultTy.IsTuple()) {
                CheckNormalTuple(expr, resultTy, topLevelFunc)
            } else if (resultTy.IsStruct()) {
                CheckStructTuple(expr, resultTy, topLevelFunc)
            } else {
                TypeCheckError(expr, expr.GetResult().getOrThrow(), "Enum, Tuple or Struct", topLevelFunc)
            }
        }
    }

    private func CheckEnumTuple(expr: Expression, resultTy: Type, topLevelFunc: Function): Unit {
        let operandsNum = expr.GetNumOfOperands()
        if (operandsNum == 0) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, must have one operand in `" +
                GetExpressionString(expr) + "` at least, and the 1st operand's type is UInt32 or Bool.")
            return
        }
        let selector = expr.GetOperand(0)
        if (let Some(selectorTy) <- selector.GetType()) {
            if (!IsEnumSelectorType(selectorTy)) {
                TypeCheckError(expr, selector, "UInt32 or Bool", topLevelFunc)
                return
            }
        }
        let localVar = selector.AsLocalVar()
        if (localVar.isNone()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, the 1st operand in `" +
                GetExpressionString(expr) + "` must be from Constant UInt32 or Constant Bool.")
            return
        }
        let indexExpr = localVar.getOrThrow().GetExpr().getOrThrow()
        if (!indexExpr.IsConstantInt() && !indexExpr.IsConstantBool()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, the 1st operand in `" +
                GetExpressionString(expr) + "` must be from Constant UInt32 or Constant Bool.")
            return
        }
        if (operandsNum == 1) {
            return
        }
        if (let Some(enumTy) <- (resultTy as EnumType)) {
            if (let Some(enumDef) <- (enumTy.GetCustomTypeDef() as EnumDef)) {
                let constantExpr = (indexExpr as Constant).getOrThrow()
                let ctorIndex = if (constantExpr.IsBoolLit()) {
                    if (constantExpr.GetBoolLitVal()) { 1u64 } else { 0u64 }
                } else {
                    constantExpr.GetUnsignedIntLitVal()
                }
                let ctors = enumDef.GetConstructorInfos(builder: builder)
                if (ctorIndex >= UInt64(ctors.size)) {
                        Errorln("in function ${topLevelFunc.GetIdentifier()}, index out of range, in `" +
                            GetExpressionString(expr) + "` its enum constructor's number is ${ctors.size} " +
                            "but the index is ${ctorIndex}.")
                        return
                }
                let paramTypes = ctors[Int64(ctorIndex)].funcType.getOrThrow().GetParamTypes()
                if (operandsNum - 1 != paramTypes.size) {
                        Errorln("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                            "${paramTypes.size} parameter(s) in the ${ctorIndex}-th constructor, but " +
                            "${operandsNum - 1} arguments are provided in `" + GetExpressionString(expr) + "`.")
                        return
                }
                var idx: Int64 = 1
                while (idx < operandsNum) {
                    let operand = expr.GetOperand(idx)
                    if (let Some(operandTy) <- operand.GetType()) {
                        if (!TypeIsExpected(operandTy, paramTypes[idx - 1])) {
                                Errorln("in function ${topLevelFunc.GetIdentifier()}, type mismatched, the " +
                                    "${idx - 1}-th parameter type is ${paramTypes[idx - 1].ToString()}, but " +
                                    "${operand.GetIdentifier()}'s type is ${operandTy.ToString()} in `" +
                                    GetExpressionString(expr) + "`.")
                        }
                    }
                    idx++
                }
            }
        }
    }

    private func CheckNormalTuple(expr: Expression, resultTy: Type, topLevelFunc: Function): Unit {
        if (let Some(tupleTy) <- (resultTy as TupleType)) {
            let elementTypes = tupleTy.GetTypeArgsRef()
            let operandsNum = expr.GetNumOfOperands()
            if (operandsNum != elementTypes.size) {
                Errorln("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                    "${elementTypes.size} element(s) in the tuple type `${resultTy.ToString()}`, but ${operandsNum} " +
                    "operand(s) are provided in `" + GetExpressionString(expr) + "`.")
                return
            }
            var idx: Int64 = 0
            while (idx < elementTypes.size) {
                let operand = expr.GetOperand(idx)
                if (let Some(operandTy) <- operand.GetType()) {
                    let expectedTy = elementTypes[idx]
                    if (!TypeIsExpected(operandTy, expectedTy)) {
                        Errorln("in function ${topLevelFunc.GetIdentifier()}, type mismatched, the ${idx}-th " +
                            "element type in tuple type `${resultTy.ToString()}` is ${expectedTy.ToString()}, but " +
                            "${operand.GetIdentifier()}'s type is ${operandTy.ToString()} in `" +
                            GetExpressionString(expr) + "`.")
                    }
                }
                idx++
            }
        }
    }

    private func CheckStructTuple(expr: Expression, resultTy: Type, topLevelFunc: Function): Unit {
        if (let Some(structTy) <- (resultTy as StructType)) {
            if (let Some(structDef) <- (structTy.GetCustomTypeDef() as StructDef)) {
                let memberVars = structDef.GetInstanceVars()
                let operandsNum = expr.GetNumOfOperands()
                if (operandsNum != memberVars.size) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, size mismatched, there are " +
                        "${memberVars.size} instance member var(s) in the struct ${structDef.GetIdentifier()}, but " +
                        "${operandsNum} operand(s) are provided in `" + GetExpressionString(expr) + "`.")
                    return
                }
                var idx: Int64 = 0
                while (idx < memberVars.size) {
                    let operand = expr.GetOperand(idx)
                    if (let Some(operandTy) <- operand.GetType()) {
                        let memberTy = memberVars[idx].ty
                        if (!TypeIsExpected(operandTy, memberTy)) {
                            Errorln("in function ${topLevelFunc.GetIdentifier()}, type mismatched, the " +
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

    private func CheckVArray(expr: Expression, topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (let Some(varrayTy) <- (resultTy as VArrayType)) {
                let elementTy = varrayTy.GetElementType()
                if (!IsCTypeInVArray(elementTy)) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                        "${GetExpressionString(expr)}`, its element type is ${elementTy.ToString()}, " +
                        "but a C type is expected.\n    C type includes: numeric data types, Rune, Bool, Unit, " +
                        "Nothing, CPointer, CString, CFunc and Struct.")
                    return
                }
                for (operand in expr.GetOperands()) {
                    if (let Some(operandTy) <- operand.GetType()) {
                        if (!TypeIsExpected(operandTy, elementTy)) {
                            TypeCheckError(expr, operand, elementTy.ToString(), topLevelFunc)
                        }
                    }
                }
            } else {
                TypeCheckError(expr, expr.GetResult().getOrThrow(), "VArray", topLevelFunc)
            }
        }
    }

    private func CheckFieldByName(expr: FieldByName, topLevelFunc: Function): Unit {
        Errorln("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
            "you should convert this expression to `Field`.")
    }

    private func CheckVArrayBuilder(expr: VArrayBuilder, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(3, expr, topLevelFunc)) {
            return
        }
        let resultValue = expr.GetResult().getOrThrow()
        if (!resultValue.GetType().getOrThrow().IsVArray()) {
            TypeCheckError(expr, resultValue, "VArray", topLevelFunc)
        }
        let size = expr.GetSize()
        if (size.GetType().getOrThrow().GetTypeKind() != TypeKind.TYPE_INT64) {
            TypeCheckError(expr, size, "Int64", topLevelFunc)
        }
        let item = ConvertToNullLiteral(expr.GetItem())
        let initFunc = ConvertToNullLiteral(expr.GetInitFunc())
        if (item.isNone() && initFunc.isNone()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
                "one of item and init func should be null.")
        } else if (item.isSome() && initFunc.isSome()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, in `${GetExpressionString(expr)}`, " +
                "item and init func can't be both null.")
        }
        let funcType = expr.GetInitFunc().GetType().getOrThrow()
        if (!IsFuncTypeOrClosureBaseRefType(funcType)) {
            TypeCheckError(expr, expr.GetInitFunc(), "Function type or closure ref", topLevelFunc)
        }
    }

    private func CheckInstanceOf(expr: InstanceOf, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (!expr.GetResult().getOrThrow().GetType().getOrThrow().IsBoolean()) {
            TypeCheckError(expr, expr.GetResult().getOrThrow(), "Bool", topLevelFunc)
        }
        CheckTypeIsValid(expr.GetType(), "target", expr, topLevelFunc)
        if (let Some(objectTy) <- expr.GetObject().GetType()) {
            if (objectTy.StripAllRefs().IsPrimitive() && expr.GetType().StripAllRefs().IsPrimitive()) {
                if (let Some(resultValue) <- expr.GetResult()) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, invalid InstanceOf `" +
                        "${resultValue.ToString(0)}`, source type is ${objectTy.StripAllRefs().ToString()}, " +
                        "target type is ${expr.GetType().ToString()}, they are both exact type, doesn't need to " +
                        "use `InstanceOf` to check in runtime.")
                }
            }
        }
    }

    private func CheckTypeCast(expr: TypeCast, topLevelFunc: Function): Unit {
        let _ = expr
        let _ = topLevelFunc
    }

    private func CheckBox(expr: Box, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            if (let Some(sourceTy) <- expr.GetSourceTy()) {
                if (!targetTy.IsRef()) {
                    TypeCheckError(expr, expr.GetResult().getOrThrow(), "reference", topLevelFunc)
                } else {
                    let strippedTy = targetTy.StripAllRefs()
                    if (let Some(boxTy) <- (strippedTy as BoxType)) {
                        if (boxTy.GetBaseType() != sourceTy) {
                            Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                                "${GetExpressionString(expr)}`, the target type is ${targetTy.ToString()}, " +
                                "then source type must be its base type, can't be ${sourceTy.ToString()}.")
                        }
                    } else if (!strippedTy.IsClass()) {
                        Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                            "${GetExpressionString(expr)}`, the target type must be Class& or Box&, " +
                            "can't be ${targetTy.ToString()}.")
                    }
                }
                if (!sourceTy.IsValueType()) {
                    TypeCheckError(expr, expr.GetSourceValue(), "value", topLevelFunc)
                }
            }
        }
    }

    private func CheckUnBox(expr: UnBox, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            if (let Some(sourceTy) <- expr.GetSourceTy()) {
                if (!sourceTy.IsRef()) {
                    TypeCheckError(expr, expr.GetSourceValue(), "reference", topLevelFunc)
                } else {
                    let strippedTy = sourceTy.StripAllRefs()
                    if (let Some(boxTy) <- (strippedTy as BoxType)) {
                        if (boxTy.GetBaseType() != targetTy) {
                            Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                                "${GetExpressionString(expr)}`, the source type is ${sourceTy.ToString()}, " +
                                "then target type must be its base type, can't be ${targetTy.ToString()}.")
                        }
                    } else if (!strippedTy.IsClass()) {
                        Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                            "${GetExpressionString(expr)}`, the source type must be Class& or Box&, " +
                            "can't be ${sourceTy.ToString()}.")
                    }
                }
                if (!targetTy.IsValueType()) {
                    TypeCheckError(expr, expr.GetResult().getOrThrow(), "value", topLevelFunc)
                }
            }
        }
    }

    private func CheckTransformToGeneric(expr: TransformToGeneric, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            if (!targetTy.IsGenericRelated()) {
                TypeCheckError(expr, expr.GetResult().getOrThrow(), "generic related", topLevelFunc)
            }
        }
        if (let Some(sourceTy) <- expr.GetSourceTy()) {
            if (sourceTy.IsGeneric()) {
                TypeCheckError(expr, expr.GetSourceValue(), "concrete", topLevelFunc)
            }
        }
    }

    private func CheckTransformToConcrete(expr: TransformToConcrete, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            if (targetTy.IsGeneric()) {
                TypeCheckError(expr, expr.GetResult().getOrThrow(), "concrete", topLevelFunc)
            }
        }
        if (let Some(sourceTy) <- expr.GetSourceTy()) {
            if (!sourceTy.IsGenericRelated()) {
                TypeCheckError(expr, expr.GetSourceValue(), "generic related", topLevelFunc)
            }
        }
    }

    private func CheckUnBoxToRef(expr: UnBoxToRef, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (let Some(targetTy) <- expr.GetTargetTy()) {
            var isValueRefType = false
            if (let Some(refTy) <- (targetTy as RefType)) {
                isValueRefType = refTy.GetBaseType().IsValueType()
            }
            if (!isValueRefType) {
                TypeCheckError(expr, expr.GetResult().getOrThrow(), "Value&", topLevelFunc)
            }
        }
        if (let Some(sourceTy) <- expr.GetSourceTy()) {
            var isReferenceRefType = false
            if (let Some(refTy) <- (sourceTy as RefType)) {
                isReferenceRefType = refTy.GetBaseType().IsReferenceType()
            }
            if (!isReferenceRefType) {
                TypeCheckError(expr, expr.GetSourceValue(), "Reference&", topLevelFunc)
            }
        }
    }

    private func CheckGetRTTI(expr: GetRTTI, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (!expr.GetResult().getOrThrow().GetType().getOrThrow().IsUnit()) {
            TypeCheckError(expr, expr.GetResult().getOrThrow(), "Unit", topLevelFunc)
        }
        let operand = expr.GetOperand()
        if (let Some(operandTy) <- operand.GetType()) {
            if (let Some(refTy) <- (operandTy as RefType)) {
                let baseTy = refTy.GetBaseType()
                if (!baseTy.IsClass() && !baseTy.IsThis()) {
                    TypeCheckError(expr, operand, "Class& or This&", topLevelFunc)
                }
            } else {
                TypeCheckError(expr, operand, "Class& or This&", topLevelFunc)
            }
        }
    }

    private func CheckGetRTTIStatic(expr: GetRTTIStatic, topLevelFunc: Function): Unit {
        if (!OperandNumIsEqual(0, expr, topLevelFunc)) {
            return
        }
        if (!expr.GetResult().getOrThrow().GetType().getOrThrow().IsUnit()) {
            TypeCheckError(expr, expr.GetResult().getOrThrow(), "Unit", topLevelFunc)
        }
        if (!optionalRules.contains(CHIRCheckerRule.CHIR_GET_RTTI_STATIC_TYPE)) {
            return
        }
        let rttiTy = expr.GetRTTIType()
        let strippedTy = rttiTy.StripAllRefs()
        if (!strippedTy.IsGeneric() && !strippedTy.IsThis()) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                "${GetExpressionString(expr)}`, RTTI type should be `This` or Generic type, but now it's " +
                "${rttiTy.ToString()}.")
        }
    }

    private func CheckApply(expr: Apply, topLevelFunc: Function): Unit {
        if (!OperandNumAtLeast(1, expr, topLevelFunc)) {
            return
        }
        CheckApplyBase(ApplyBase(expr), topLevelFunc)
    }

    private func CheckApplyWithException(expr: ApplyWithException, topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (!OperandNumAtLeast(1, expr, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        CheckApplyBase(ApplyBase(expr), topLevelFunc)
    }

    private func CheckApplyBase(expr: ApplyBase, topLevelFunc: Function): Unit {
        if (IsUnreachableApply(expr.GetThisType())) {
            return
        }
        let rawExpr = expr.GetRawExpr()
        let callee = expr.GetCallee()
        if (!CheckCallee(callee, rawExpr, topLevelFunc)) {
            return
        }
        let genericTypeParams = ArrayList<GenericType>()
        if (let Some(`func`) <- callee.AsFunction()) {
            genericTypeParams.add(all: `func`.GetGenericTypeParams())
        } else if (let Some(localVar) <- callee.AsLocalVar()) {
            if (let Some(lambda) <- (localVar.GetExpr().getOrThrow() as Lambda)) {
                genericTypeParams.add(all: lambda.GetGenericTypeParams())
            }
        }
        let instTypeArgs = expr.GetInstantiatedTypeArgs()
        if (!CheckInstantiatedTypeArgs(instTypeArgs, genericTypeParams, rawExpr, topLevelFunc)) {
            return
        }
        if (!CheckApplyThisType(callee, expr.GetThisType(), rawExpr, topLevelFunc)) {
            return
        }
        let calleeType = (callee.GetType().getOrThrow() as FuncType).getOrThrow()
        let instFuncType = CalculateInstFuncType(calleeType, instTypeArgs, genericTypeParams,
            expr.GetInstParentCustomTyOfCallee(builder))
        CheckApplyFuncArgs(expr.GetArgs(), instFuncType.GetParamTypes(), calleeType.HasVarArg(), rawExpr, topLevelFunc)
        CheckApplyFuncRetValue(instFuncType.GetReturnType(), rawExpr, topLevelFunc)
    }

    private func CheckInvoke(expr: Invoke, topLevelFunc: Function): Unit {
        if (!OperandNumAtLeast(1, expr, topLevelFunc)) {
            return
        }
        CheckInvokeBase(InvokeBase(expr), topLevelFunc)
    }

    private func CheckInvokeStatic(expr: InvokeStatic, topLevelFunc: Function): Unit {
        if (!OperandNumAtLeast(1, expr, topLevelFunc)) {
            return
        }
        CheckInvokeStaticBase(InvokeStaticBase(expr), topLevelFunc)
    }

    private func CheckCallee(callee: Value, expr: Expression, topLevelFunc: Function): Bool {
        let calleeTy = callee.GetType().getOrThrow()
        if (!calleeTy.IsFunc()) {
            ErrorInFunc(topLevelFunc, "callee of `" + GetExpressionString(expr) +
                "` should have func type, not " + calleeTy.ToString() + ".")
            return false
        }
        if (callee.TestAttr(Attribute.ABSTRACT)) {
            ErrorInFunc(topLevelFunc, "callee of `" + GetExpressionString(expr) + "` can't be abstract.")
            return false
        }
        return true
    }

    private func CheckInstantiatedTypeArgs(instantiatedTypeArgs: ArrayList<Type>,
        genericTypeParams: ArrayList<GenericType>, expr: Expression, topLevelFunc: Function): Bool {
        if (instantiatedTypeArgs.size != genericTypeParams.size) {
            ErrorInFunc(topLevelFunc, "size mismatched, there are " +
                "${instantiatedTypeArgs.size} instantiated type args in function call `" +
                "${GetExpressionString(expr)}`, but there are ${genericTypeParams.size} generic type args " +
                "in function declare.")
            return false
        }
        return true
    }

    private func CheckApplyThisType(callee: Value, thisType: Option<Type>, expr: Expression,
        topLevelFunc: Function): Bool {
        let thisDerefTy: Option<Type> = if (let Some(ty) <- thisType) { Some(ty.StripAllRefs()) } else { None }
        if (let Some(derefTy) <- thisDerefTy) {
            if (!derefTy.IsBuiltinType() && !derefTy.IsCustomType() && !derefTy.IsGeneric()) {
                ErrorInExpr(topLevelFunc, expr, "ThisType must be builtin type, custom type or generic type can't be " +
                    thisType.getOrThrow().ToString() + ".")
                return false
            }
        }
        let maybeFunc = callee.AsFunction()
        if (maybeFunc.isNone() && thisDerefTy.isSome()) {
            ErrorInExpr(topLevelFunc, expr, "callee isn't member method, but there is ThisType: " +
                thisType.getOrThrow().ToString() + ".")
            return false
        }
        let `func` = maybeFunc ?? return true
        if (`func`.IsMemberFunc() && thisDerefTy.isNone()) {
            ErrorInExpr(topLevelFunc, expr, "callee is member method, but there is no ThisType.")
            return false
        }
        if (!`func`.IsMemberFunc() && thisDerefTy.isSome()) {
            ErrorInExpr(topLevelFunc, expr, "callee isn't member method, but there is ThisType: " +
                thisType.getOrThrow().ToString() + ".")
            return false
        }
        if (!`func`.IsMemberFunc() && thisDerefTy.isNone()) {
            return true
        }
        let derefTy = thisDerefTy.getOrThrow()
        if (derefTy.IsBuiltinType() || derefTy.IsCustomType()) {
            return CheckThisTypeIsEqualOrSubTypeOfFuncParentType(derefTy, `func`, expr, topLevelFunc)
        }
        if (let Some(genericType) <- (derefTy as GenericType)) {
            if (!FuncCanBeDynamicDispatch(`func`)) {
                return true
            }
            for (upperBound in genericType.GetUpperBounds()) {
                if (!(upperBound.StripAllRefs() as CustomType).getOrThrow().GetCustomTypeDef().CanBeInherited()) {
                    return true
                }
            }
            ErrorInExpr(topLevelFunc, expr, "ThisType is " + thisType.getOrThrow().ToString() +
                ", but its all upper bounds can be inherited and callee can be dynamic dispatched, " +
                "so you should use `Invoke`, not `Apply`.")
            return false
        }
        ErrorInExpr(topLevelFunc, expr,
            "ThisType is " + thisType.getOrThrow().ToString() + ", an unknown type.")
        return false
    }

    private func CheckThisTypeIsEqualOrSubTypeOfFuncParentType(thisType: Type, `func`: Function,
        expr: Expression, topLevelFunc: Function): Bool {
        CJC_ASSERT(thisType.IsBuiltinType() || thisType.IsCustomType())
        let funcParentType = `func`.GetParentCustomTypeOrExtendedType().getOrThrow()
        if (thisType.IsBuiltinType() && funcParentType.IsBuiltinType()) {
            return thisType == funcParentType
        }
        let funcParentCustomType = funcParentType as CustomType
        if (let Some(thisCustomType) <- (thisType as CustomType)) {
            if (let Some(parentCustomType) <- funcParentCustomType) {
                if (thisCustomType.GetCustomTypeDef() == parentCustomType.GetCustomTypeDef()) {
                    return true
                }
            }
        }
        let parentCustomType = funcParentCustomType.getOrThrow()
        for (parentTy in thisType.GetSuperTypesRecusively(builder)) {
            if (parentTy.GetClassDef() == parentCustomType.GetCustomTypeDef()) {
                return true
            }
        }
        let parentDef = `func`.GetParentCustomTypeDef().getOrThrow()
        ErrorInExpr(topLevelFunc, expr, "callee is " + `func`.GetIdentifier() +
            ", its parent custom type def is " + parentDef.GetIdentifier() + ", but ThisType is " +
            thisType.ToString() + ", not this parent custom type or its sub type.")
        return false
    }

    private func CalculateInstFuncType(originalFuncType: FuncType, instantiatedTypeArgs: ArrayList<Type>,
        genericTypeParams: ArrayList<GenericType>, instOuterType: Option<Type>): FuncType {
        let replaceTable = HashMap<GenericType, Type>()
        if (let Some(outerType) <- instOuterType) {
            if (let Some(customType) <- (outerType as CustomType)) {
                for ((key, value) in GetInstMapFromCurDefAndExDefToCurType(customType)) {
                    replaceTable[key] = value
                }
            }
        }
        CJC_ASSERT(genericTypeParams.size == instantiatedTypeArgs.size)
        var idx: Int64 = 0
        while (idx < genericTypeParams.size) {
            if (!replaceTable.contains(genericTypeParams[idx])) {
                replaceTable[genericTypeParams[idx]] = instantiatedTypeArgs[idx]
            }
            idx++
        }
        return (ReplaceRawGenericArgType(originalFuncType, replaceTable, builder) as FuncType).getOrThrow()
    }

    private func CheckInvokeWithException(expr: InvokeWithException, topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (!OperandNumAtLeast(1, expr, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        CheckInvokeBase(InvokeBase(expr), topLevelFunc)
    }

    private func CheckInvokeBase(expr: InvokeBase, topLevelFunc: Function): Unit {
        let rawExpr = expr.GetRawExpr()
        if (!CheckInstantiatedTypeArgs(expr.GetInstantiatedTypeArgs(), expr.GetGenericTypeParams(), rawExpr,
            topLevelFunc)) {
            return
        }
        if (!CheckInvokeThisType(expr.GetObject().GetType().getOrThrow(), expr.GetThisType(), rawExpr,
            topLevelFunc)) {
            return
        }
        let thisType = expr.GetThisType().getOrThrow().StripAllRefs()
        if (!thisType.IsAutoEnvBase()) {
            let methodContext = VirMethodFullContext(expr.GetMethodName(), expr.GetMethodType(),
                expr.GetVirtualMethodOffset(), thisType,
                expr.GetInstSrcParentCustomTypeOfMethod(builder))
            if (!CheckVirtualMethod(methodContext, rawExpr, topLevelFunc)) {
                return
            }
        }
        CheckInvokeFuncArgs(expr.GetArgs(), expr.GetMethodType().GetParamTypes(), rawExpr, topLevelFunc)
    }

    private func CheckInvokeStaticWithException(expr: InvokeStaticWithException,
        topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (!OperandNumAtLeast(1, expr, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        CheckInvokeStaticBase(InvokeStaticBase(expr), topLevelFunc)
    }

    private func CheckInvokeStaticBase(expr: InvokeStaticBase, topLevelFunc: Function): Unit {
        let rawExpr = expr.GetRawExpr()
        if (!CheckInstantiatedTypeArgs(expr.GetInstantiatedTypeArgs(), expr.GetGenericTypeParams(), rawExpr,
            topLevelFunc)) {
            return
        }
        let rtti = expr.GetRTTIValue().AsLocalVar()
        if (rtti.isNone()) {
            ErrorInExpr(topLevelFunc, rawExpr, "its first operand must be from `GetRTTI` or `GetRTTIStatic`.")
            return
        }
        let rttiExpr = rtti.getOrThrow().GetExpr()
        var objectType: Option<Type> = None
        if (let Some(ownerExpr) <- rttiExpr) {
            if (let Some(getRTTI) <- (ownerExpr as GetRTTI)) {
                objectType = getRTTI.GetOperand().GetType()
            } else if (let Some(getRTTIStatic) <- (ownerExpr as GetRTTIStatic)) {
                objectType = getRTTIStatic.GetRTTIType()
            }
        }
        if (objectType.isNone()) {
            ErrorInExpr(topLevelFunc, rawExpr, "its first operand must be from `GetRTTI` or `GetRTTIStatic`.")
            return
        }
        if (!CheckInvokeThisType(objectType.getOrThrow(), expr.GetThisType(), rawExpr, topLevelFunc)) {
            return
        }
        let methodContext = VirMethodFullContext(expr.GetMethodName(), expr.GetMethodType(),
            expr.GetVirtualMethodOffset(), expr.GetThisType().getOrThrow().StripAllRefs(),
            expr.GetInstSrcParentCustomTypeOfMethod(builder))
        if (!CheckVirtualMethod(methodContext, rawExpr, topLevelFunc)) {
            return
        }
        CheckInvokeFuncArgs(expr.GetArgs(), expr.GetMethodType().GetParamTypes(), rawExpr, topLevelFunc)
    }

    private func CheckInvokeThisType(objectTy: Type, maybeThisType: Option<Type>, expr: Expression,
        topLevelFunc: Function): Bool {
        if (maybeThisType.isNone()) {
            ErrorInExpr(topLevelFunc, expr, "we must have `ThisType`, can't be nullptr.")
            return false
        }
        let thisType = maybeThisType.getOrThrow()
        let thisDerefTy = thisType.StripAllRefs()
        if (!thisDerefTy.IsBuiltinType() && !thisDerefTy.IsCustomType() && !thisDerefTy.IsThis() &&
            !thisDerefTy.IsGeneric()) {
            ErrorInExpr(topLevelFunc, expr, "ThisType must be builtin type, custom type, `This` type or generic " +
                "type, can't be " + thisType.ToString() + ".")
            return false
        }
        if (let Some(genericType) <- (thisDerefTy as GenericType)) {
            let upperBounds = genericType.GetUpperBounds()
            if (upperBounds.isEmpty()) {
                ErrorInExpr(topLevelFunc, expr, "ThisType is " + thisType.ToString() +
                    ", a generic type, but it doesn't have upper bounds.")
                return false
            }
            let objectDerefType = objectTy.StripAllRefs()
            var ok = false
            if (let Some(objectGenericType) <- (objectDerefType as GenericType)) {
                ok = Generic1IsEqualOrSubTypeOfGeneric2(genericType, objectGenericType, builder)
            } else {
                for (upperBound in upperBounds) {
                    if (upperBound.StripAllRefs().IsEqualOrSubTypeOf(objectDerefType, builder)) {
                        ok = true
                        break
                    }
                }
            }
            if (!ok) {
                ErrorInFunc(topLevelFunc, "type mismatched, in `" + GetExpressionString(expr) +
                    "`, ThisType is " + thisType.ToString() + ", its upper bounds are " +
                    VectorTypesToString("(", upperBounds, ")") + ", but object's type is " + objectTy.ToString() +
                    ", any one of ThisType's upper bounds is not equal or sub type of object's type.")
                return false
            }
        } else if (thisDerefTy.IsThis()) {
            if (!topLevelFunc.IsMemberFunc()) {
                ErrorInFunc(topLevelFunc, "use a `This` type in `" + GetExpressionString(expr) +
                    "`, this expression is in function `" + topLevelFunc.GetIdentifier() +
                    "` which isn't member method.")
                return false
            }
            let parentDef = topLevelFunc.GetOuterDeclaredOrExtendedDef()
            if (parentDef.isNone() || !parentDef.getOrThrow().CanBeInherited()) {
                ErrorInFunc(topLevelFunc, "use a `This` type in `" + GetExpressionString(expr) +
                    "`, this expression is in function `" + topLevelFunc.GetIdentifier() +
                    "` which is member method of `" +
                    topLevelFunc.GetParentCustomTypeDef().getOrThrow().GetIdentifier() +
                    "`, but this type can't be inherited.")
                return false
            }
        } else if (!thisDerefTy.IsEqualOrSubTypeOf(objectTy.StripAllRefs(), builder) &&
            !ClosureTypeIsExpected(objectTy.StripAllRefs(), thisDerefTy, builder)) {
            ErrorInFunc(topLevelFunc, "type mismatched, in `" + GetExpressionString(expr) + "`, ThisType is " +
                thisType.ToString() + ", but object's type is " + objectTy.ToString() +
                ", ThisType is not equal or sub type of object's type.")
            return false
        }
        return true
    }

    private func CheckVirtualMethod(methodContext: VirMethodFullContext, expr: Expression,
        topLevelFunc: Function): Bool {
        let maybeVTable = CheckVTableExist(methodContext.thisType, methodContext.srcParentType, expr, topLevelFunc)
        if (maybeVTable.isNone()) {
            return false
        }
        let vtable = maybeVTable.getOrThrow()
        if (methodContext.offset >= UInt64(vtable.size)) {
            ErrorInFunc(topLevelFunc, "invoke a wrong virtual method in " + GetExpressionString(expr) +
                ", parent type " + methodContext.srcParentType.ToString() + " in vtable of " +
                methodContext.thisType.ToString() + ", only has ${vtable.size} virtual method(s), but the offset is " +
                "${methodContext.offset}.")
            return false
        }
        let funcInfo = vtable[Int64(methodContext.offset)]
        let errMsgBase = "invoke a wrong virtual method in " + GetExpressionString(expr) + ", in vtable of [" +
            methodContext.thisType.ToString() + "][" + methodContext.srcParentType.ToString() + "], the " +
            "${methodContext.offset}-th "
        if (expr.IsInvokeStaticBase() && !funcInfo.TestAttr(Attribute.STATIC)) {
            ErrorInFunc(topLevelFunc,
                errMsgBase + "virtual method is not static, `InvokeStatic` should call a static method.")
            return false
        } else if (!expr.IsInvokeStaticBase() && funcInfo.TestAttr(Attribute.STATIC)) {
            ErrorInFunc(topLevelFunc,
                errMsgBase + "virtual method is static, `Invoke` shouldn't call a static method.")
            return false
        }
        var result = true
        if (funcInfo.GetMethodName() != methodContext.srcCodeIdentifier) {
            ErrorInFunc(topLevelFunc, errMsgBase + "virtual method's name is " + funcInfo.GetMethodName() +
                ", but the method name in expression is " + methodContext.srcCodeIdentifier + ".")
            result = false
        }
        return result
    }

    private func CheckVTableExist(thisType: BuiltinType,
        srcParentType: ClassType): Option<ArrayList<VirtualMethodInfo>> {
        for (extendDef in thisType.GetExtends(builder)) {
            let mapping = extendDef.GetExtendedType().getOrThrow().CalculateGenericTyMapping(thisType)
            CJC_ASSERT(mapping[0])
            for (vtable in extendDef.GetDefVTable().GetTypeVTables()) {
                let instType = ReplaceRawGenericArgType(vtable.GetSrcParentType().getOrThrow(), mapping[1], builder)
                if (instType == srcParentType) {
                    return vtable.GetVirtualMethods()
                }
            }
        }
        return None
    }

    private func CheckVTableExist(thisType: CustomType,
        srcParentType: ClassType): Option<ArrayList<VirtualMethodInfo>> {
        let replaceTable = GetInstMapFromCurDefToCurType(thisType)
        for (vtable in thisType.GetCustomTypeDef().GetDefVTable().GetTypeVTables()) {
            let instType = ReplaceRawGenericArgType(vtable.GetSrcParentType().getOrThrow(), replaceTable, builder)
            if (instType == srcParentType) {
                return vtable.GetVirtualMethods()
            }
        }
        for (extendDef in thisType.GetCustomTypeDef().GetExtends()) {
            let mapping = extendDef.GetExtendedType().getOrThrow().CalculateGenericTyMapping(thisType)
            for (vtable in extendDef.GetDefVTable().GetTypeVTables()) {
                let instType = ReplaceRawGenericArgType(vtable.GetSrcParentType().getOrThrow(), mapping[1], builder)
                if (instType == srcParentType) {
                    return vtable.GetVirtualMethods()
                }
            }
        }
        return None
    }

    private func CheckVTableExist(srcParentType: ClassType,
        topLevelFunc: Function): Option<ArrayList<VirtualMethodInfo>> {
        let parentType = topLevelFunc.GetParentCustomTypeOrExtendedType().getOrThrow()
        if (let Some(builtinType) <- (parentType as BuiltinType)) {
            for (def in GetBuiltinTypeWithVTable(builtinType, builder).GetExtends()) {
                for (vtable in def.GetDefVTable().GetTypeVTables()) {
                    if (vtable.GetSrcParentType().getOrThrow() == srcParentType) {
                        return vtable.GetVirtualMethods()
                    }
                }
            }
        } else {
            let customType = (parentType as CustomType).getOrThrow()
            let customDef = customType.GetCustomTypeDef()
            let mapping = customDef.GetType().getOrThrow().CalculateGenericTyMapping(customType)
            CJC_ASSERT(mapping[0])
            for (vtable in customDef.GetDefVTable().GetTypeVTables()) {
                let instType = ReplaceRawGenericArgType(vtable.GetSrcParentType().getOrThrow(), mapping[1], builder)
                if (instType == srcParentType) {
                    return vtable.GetVirtualMethods()
                }
            }
            for (extendDef in customDef.GetExtends()) {
                let extendMapping = extendDef.GetType().getOrThrow().CalculateGenericTyMapping(customType)
                if (!extendMapping[0]) {
                    continue
                }
                for (vtable in extendDef.GetDefVTable().GetTypeVTables()) {
                    let instType = ReplaceRawGenericArgType(vtable.GetSrcParentType().getOrThrow(), extendMapping[1],
                        builder)
                    if (instType == srcParentType) {
                        return vtable.GetVirtualMethods()
                    }
                }
            }
        }
        return None
    }

    private func CheckVTableExist(thisType: GenericType,
        srcParentType: ClassType): Option<ArrayList<VirtualMethodInfo>> {
        for (upperBound in thisType.GetUpperBounds()) {
            let result = CheckVTableExist((upperBound.StripAllRefs() as ClassType).getOrThrow(), srcParentType)
            if (result.isSome()) {
                return result
            }
        }
        return None
    }

    private func CheckVTableExist(thisType: Type, srcParentType: ClassType, expr: Expression,
        topLevelFunc: Function): Option<ArrayList<VirtualMethodInfo>> {
        var result: Option<ArrayList<VirtualMethodInfo>> = None
        if (let Some(builtinType) <- (thisType as BuiltinType)) {
            result = CheckVTableExist(builtinType, srcParentType)
        } else if (let Some(customType) <- (thisType as CustomType)) {
            result = CheckVTableExist(customType, srcParentType)
        } else if (thisType.IsThis()) {
            result = CheckVTableExist(srcParentType, topLevelFunc)
        } else if (let Some(genericType) <- (thisType as GenericType)) {
            result = CheckVTableExist(genericType, srcParentType)
        } else {
            CJC_ASSERT(false)
        }
        if (result.isNone()) {
            var errMsg = ""
            if (thisType.IsBuiltinType() || thisType.IsCustomType()) {
                errMsg = "invoke a wrong virtual method in `" + GetExpressionString(expr) +
                    "`, we can't find super type " + srcParentType.ToString() + " in type " +
                    thisType.ToString() + "."
            } else if (thisType.IsThis()) {
                errMsg = "invoke a wrong virtual method in " + GetExpressionString(expr) +
                    ", we can't find super type " + srcParentType.ToString() + " in custom type def " +
                    topLevelFunc.GetParentCustomTypeDef().getOrThrow().GetIdentifier() + "."
            } else if (let Some(genericType) <- (thisType as GenericType)) {
                errMsg = "invoke a wrong virtual method in " + GetExpressionString(expr) +
                    ", we can't find super type " + srcParentType.ToString() + " in all upper bounds of " +
                    thisType.ToString() + ".\n        upper bounds are " +
                    VectorTypesToString("(", genericType.GetUpperBounds(), ")") + "."
            }
            ErrorInFunc(topLevelFunc, errMsg)
        }
        return result
    }

    private func CheckApplyFuncArgs(args: ArrayList<Value>, instParamTypes: ArrayList<Type>, varArgs: Bool,
        expr: Expression, topLevelFunc: Function): Unit {
        if (!varArgs && args.size != instParamTypes.size) {
            ErrorInFunc(topLevelFunc, "size mismatched, there are " +
                "${args.size} arg(s) in function call `${GetExpressionString(expr)}`, but there are " +
                "${instParamTypes.size} parameter(s) in function declare.")
            return
        }
        var idx: Int64 = 0
        while (idx < instParamTypes.size) {
            let arg = args[idx]
            let argTy = arg.GetType().getOrThrow()
            let paramTy = instParamTypes[idx]
            if (!TypeIsExpected(argTy, paramTy) &&
                !ClosureTypeIsExpected(argTy.StripAllRefs(), paramTy.StripAllRefs(), builder)) {
                TypeCheckError(expr, arg, paramTy.ToString(), topLevelFunc)
            }
            idx++
        }
    }

    private func CheckApplyFuncRetValue(instRetType: Type, expr: Expression, topLevelFunc: Function): Unit {
        let retValue = expr.GetResult().getOrThrow()
        let retType = retValue.GetType().getOrThrow()
        if (!TypeIsExpected(instRetType, retType) && !TypeIsExpected(retType, instRetType)) {
            TypeCheckError(expr, retValue, instRetType.ToString(), topLevelFunc)
        }
    }

    private func CheckInvokeFuncArgs(args: ArrayList<Value>, originalParamTypes: ArrayList<Type>,
        expr: Expression, topLevelFunc: Function): Unit {
        if (args.size != originalParamTypes.size) {
            ErrorInFunc(topLevelFunc, "size mismatched, there are ${args.size} arg(s) in function call `" +
                GetExpressionString(expr) + "`, but there are ${originalParamTypes.size} parameter(s) in function " +
                "declare.")
            return
        }
        var idx: Int64 = 0
        while (idx < originalParamTypes.size) {
            if (idx == 0) {
                idx++
                continue
            }
            if (!InstTypeCanSetToGenericRelatedType(args[idx].GetType().getOrThrow(), originalParamTypes[idx])) {
                TypeCheckError(expr, args[idx], originalParamTypes[idx].ToString(), topLevelFunc)
            }
            idx++
        }
    }

    private func InstTypeCanSetToGenericRelatedType(instType: Type, genericRelatedType: Type): Bool {
        if (instType.IsNothing() || genericRelatedType.IsAny() || instType == genericRelatedType) {
            return true
        }
        if (let Some(instRefType) <- (instType as RefType)) {
            if (let Some(genericRefType) <- (genericRelatedType as RefType)) {
                return InstTypeCanSetToGenericRelatedType(instRefType.GetBaseType(), genericRefType.GetBaseType())
            }
        }
        if (let Some(instCustomType) <- (instType as CustomType)) {
            if (let Some(genericCustomType) <- (genericRelatedType as CustomType)) {
                if (instCustomType.GetCustomTypeDef() == genericCustomType.GetCustomTypeDef()) {
                    return InstTypeArgsSatisfyGenericConstraints(instCustomType.GetGenericArgs(),
                        genericCustomType.GetGenericArgs())
                }
                for (superType in instCustomType.GetSuperTypesRecusively(builder)) {
                    if (superType.GetCustomTypeDef() == genericCustomType.GetCustomTypeDef() &&
                        InstTypeArgsSatisfyGenericConstraints(superType.GetGenericArgs(),
                            genericCustomType.GetGenericArgs())) {
                        return true
                    }
                }
                return false
            }
        }
        if (let Some(genericType) <- (genericRelatedType as GenericType)) {
            if (let Some(instGenericType) <- (instType as GenericType)) {
                return Generic1IsEqualOrSubTypeOfGeneric2(instGenericType, genericType, builder)
            }
            return instType.SatisfyGenericConstraints(genericType, builder, HashMap<GenericType, Type>())
        }
        if (instType.GetTypeKind() != genericRelatedType.GetTypeKind()) {
            return false
        }
        let instTypeArgs = instType.GetTypeArgs()
        let genericTypeArgs = genericRelatedType.GetTypeArgs()
        if (instTypeArgs.size != genericTypeArgs.size) {
            return false
        }
        var idx: Int64 = 0
        while (idx < instTypeArgs.size) {
            if (!InstTypeCanSetToGenericRelatedType(instTypeArgs[idx], genericTypeArgs[idx])) {
                return false
            }
            idx++
        }
        return true
    }

    private func InstTypeArgsSatisfyGenericConstraints(instTypeArgs: ArrayList<Type>,
        genericTypeArgs: ArrayList<Type>): Bool {
        if (instTypeArgs.size != genericTypeArgs.size) {
            return false
        }
        var idx: Int64 = 0
        while (idx < instTypeArgs.size) {
            if (!InstTypeCanSetToGenericRelatedType(instTypeArgs[idx], genericTypeArgs[idx])) {
                return false
            }
            idx++
        }
        return true
    }

    private func CheckIntrinsic(expr: Intrinsic, topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        CheckIntrinsicBase(IntrinsicBase(expr), topLevelFunc)
    }

    private func CheckIntrinsicWithException(expr: IntrinsicWithException, topLevelFunc: Function): Unit {
        if (!CheckHaveResult(expr, topLevelFunc)) {
            return
        }
        if (!SuccessorNumIsEqual(2, expr, topLevelFunc)) {
            return
        }
        CheckIntrinsicBase(IntrinsicBase(expr), topLevelFunc)
    }

    private func CheckIntrinsicBase(expr: IntrinsicBase, topLevelFunc: Function): Unit {
        if (topLevelFunc.GetIdentifier() == "@_CNbv4mockIG_HRNat5ArrayINNbv8StubModeEE" ||
            topLevelFunc.GetIdentifier() == "@_CNbv3spyIG_HG_" ||
            topLevelFunc.GetIdentifier() == "@_CNbv4mockIG_Hv") {
            return
        }
        if (expr.GetIntrinsicKind() == IntrinsicKind.NOT_INTRINSIC ||
            expr.GetIntrinsicKind() == IntrinsicKind.NOT_IMPLEMENTED) {
            ErrorInExpr(topLevelFunc, expr.GetRawExpr(), "intrinsic kind must be valid.")
        }
        CheckInout(expr, topLevelFunc)
    }

    private func CheckInout(expr: IntrinsicBase, topLevelFunc: Function): Unit {
        if (expr.GetIntrinsicKind() != IntrinsicKind.INOUT_PARAM) {
            return
        }
        let rawExpr = expr.GetRawExpr()
        if (!expr.GetInstantiatedTypeArgs().isEmpty()) {
            ErrorInExpr(topLevelFunc, rawExpr, "`inout` intrinsic can't have type args.")
        }
        if (!OperandNumIsEqual(1, rawExpr, topLevelFunc)) {
            return
        }
        let operand = rawExpr.GetOperand(0)
        let operandType = operand.GetType().getOrThrow()
        if (!operandType.IsRef()) {
            ErrorInExpr(topLevelFunc, rawExpr, "`inout` operand's type is `" + operandType.ToString() +
                "`, but ref type is expected.")
            return
        }
        let baseType = (operandType as RefType).getOrThrow().GetBaseType()
        if (baseType.IsRef()) {
            ErrorInExpr(topLevelFunc, rawExpr, "`inout` operand's type is `" + operandType.ToString() +
                "`, but type&& is NOT allowed.")
            return
        }
        CheckInoutOpSrc(operand, expr, topLevelFunc)
        let result = rawExpr.GetResult().getOrThrow()
        let resultType = result.GetType().getOrThrow()
        if (!resultType.IsCPointer()) {
            TypeCheckError(rawExpr, result, "CPointer", topLevelFunc)
            return
        }
        if (!IsCTypeInInout(resultType)) {
            ErrorInExpr(topLevelFunc, rawExpr, "the pointed type of result CPointer is `" +
                (resultType as CPointerType).getOrThrow().GetElementType().ToString() +
                "`, but CType (exclude CString) is expected.")
            return
        }
        let valuesToCheck = ArrayList<LocalVar>()
        valuesToCheck.add(result)
        while (!valuesToCheck.isEmpty()) {
            let localVar = valuesToCheck.remove(at: valuesToCheck.size - 1)
            for (user in localVar.GetUsersRef()) {
                let errMsgBase = "the result is used in a wrong expression `" + user.ToString(0) + "`, "
                let kind = user.GetExprKind()
                if (kind == ExprKind.APPLY || kind == ExprKind.APPLY_WITH_EXCEPTION) {
                    continue
                } else if (kind == ExprKind.INVOKE || kind == ExprKind.INVOKE_WITH_EXCEPTION) {
                    let funcName = InvokeBase(user).GetMethodName()
                    if (funcName != INST_VIRTUAL_FUNC && funcName != GENERIC_VIRTUAL_FUNC) {
                        ErrorInExpr(topLevelFunc, rawExpr,
                            errMsgBase + "the result can't be used as virtual method's argument.")
                    }
                    continue
                } else if (kind == ExprKind.INTRINSIC || kind == ExprKind.INTRINSIC_WITH_EXCEPTION) {
                    if (IntrinsicBase(user).GetIntrinsicKind() != IntrinsicKind.CPOINTER_INIT1) {
                        ErrorInExpr(topLevelFunc, rawExpr,
                            errMsgBase + "the result must be used as pointerInit1's argument.")
                    }
                    continue
                } else if (kind == ExprKind.TYPECAST) {
                    valuesToCheck.add(user.GetResult().getOrThrow())
                    continue
                }
                ErrorInExpr(topLevelFunc, rawExpr,
                    errMsgBase + "the result must be used as Function's or Intrinsic/pointerInit1's argument.")
            }
        }
    }

    private func CheckInoutOpSrc(op: Value, expr: IntrinsicBase, topLevelFunc: Function): Unit {
        let ty = op.GetType().getOrThrow().StripAllRefs()
        if (!IsCTypeInInout(ty)) {
            ErrorInExpr(topLevelFunc, expr.GetRawExpr(), "`inout` operand's type is `" + ty.ToString() +
                "`, but C-type (exclude CString) is expected.")
            return
        }
        if (op.IsBlock() || op.IsBlockGroup() || op.IsFunc() || op.IsLiteral()) {
            ErrorInExpr(topLevelFunc, expr.GetRawExpr(),
                "`inout` operand can't be Block, BlockGroup, Literal or Function.")
            return
        }
        if (let Some(localVar) <- op.AsLocalVar()) {
            let localExpr = localVar.GetExpr().getOrThrow()
            if (let Some(load) <- (localExpr as Load)) {
                CheckInoutOpSrc(load.GetLocation(), expr, topLevelFunc)
            } else if (let Some(getElementRef) <- (localExpr as GetElementRef)) {
                var locationType = getElementRef.GetLocation().GetType().getOrThrow().StripAllRefs()
                for (path in getElementRef.GetPath()) {
                    let fieldType = GetFieldOfType(locationType, path, builder)
                    if (fieldType.isNone()) {
                        return
                    }
                    locationType = fieldType.getOrThrow()
                    if (!IsCTypeInInout(locationType)) {
                        ErrorInExpr(topLevelFunc, expr.GetRawExpr(), "there is " + locationType.ToString() +
                            " type that is calculated by path in " + op.ToString(0) +
                            ", but C-type (exclude CString) is expected in `inout` operand chain.")
                        return
                    }
                }
                CheckInoutOpSrc(getElementRef.GetLocation(), expr, topLevelFunc)
            } else if (let Some(field) <- (localExpr as Field)) {
                var locationType = field.GetBase().GetType().getOrThrow().StripAllRefs()
                for (path in field.GetPath()) {
                    let fieldType = GetFieldOfType(locationType, path, builder)
                    if (fieldType.isNone()) {
                        return
                    }
                    locationType = fieldType.getOrThrow()
                    if (!IsCTypeInInout(locationType)) {
                        ErrorInExpr(topLevelFunc, expr.GetRawExpr(), "there is " + locationType.ToString() +
                            " type that is calculated by path in " + op.ToString(0) +
                            ", but C-type (exclude CString) is expected in `inout` operand chain.")
                        return
                    }
                }
                CheckInoutOpSrc(field.GetBase(), expr, topLevelFunc)
            } else if (localExpr.GetExprKind() == ExprKind.TYPECAST_WITH_EXCEPTION ||
                localExpr.GetExprKind() == ExprKind.TYPECAST) {
                CheckInoutOpSrc(localExpr.GetOperand(0), expr, topLevelFunc)
            } else if (!localExpr.IsFuncCall() && localExpr.GetExprKind() != ExprKind.APPLY_WITH_EXCEPTION &&
                localExpr.GetExprKind() != ExprKind.INVOKE_WITH_EXCEPTION &&
                localExpr.GetExprKind() != ExprKind.INVOKESTATIC_WITH_EXCEPTION &&
                localExpr.GetExprKind() != ExprKind.ALLOCATE_WITH_EXCEPTION &&
                localExpr.GetExprKind() != ExprKind.ALLOCATE) {
                ErrorInExpr(topLevelFunc, expr.GetRawExpr(),
                    "a wrong expression `" + op.ToString(0) + "` in `inout` operand chain.")
                return
            }
        }
    }


    private func CheckGetInstantiateValue(expr: Expression, topLevelFunc: Function): Unit {
        if (optionalRules.contains(CHIRCheckerRule.GET_INSTANTIATE_VALUE_SHOULD_GONE)) {
            Errorln("in function ${topLevelFunc.GetIdentifier()}, in " +
                "`${GetExpressionString(expr)}`, `GetInstantiateValue` should be removed now, " +
                "it can't be seen in CodeGen Stage.")
            return
        }
        if (!OperandNumIsEqual(1, expr, topLevelFunc)) {
            return
        }
        if (let Some(funcTy) <- expr.GetOperand(0).GetType()) {
            if (!funcTy.IsFunc()) {
                TypeCheckError(expr, expr.GetOperand(0), "Function", topLevelFunc)
            }
        }
    }

    private func CheckTypeIsValid(ty: Type, typeName: String, expr: Expression, topLevelFunc: Function): Bool {
        if (let Some(customTy) <- (ty as CustomType)) {
            if (let Some(genericTy) <- customTy.GetCustomTypeDef().GetType()) {
                let declaredSize = genericTy.GetTypeArgsRef().size
                let callSiteSize = customTy.GetTypeArgsRef().size
                if (declaredSize != callSiteSize) {
                    Errorln("in function ${topLevelFunc.GetIdentifier()}, in `" +
                        "${GetExpressionString(expr)}`, type args' size NOT matched, the ${typeName} type " +
                        "is `${customTy.ToString()}` which has ${callSiteSize} type arg(s), but its original type " +
                        "is `${genericTy.ToString()}` which has ${declaredSize} type arg(s).")
                    return false
                }
            }
        }
        return true
    }

    private func CheckHaveResult(expr: Expression, topLevelFunc: Function): Bool {
        if (expr.GetResult().isNone()) {
            ErrorInExpr(topLevelFunc, expr, "this expression should have result.")
            return false
        }
        return true
    }

    private func ShouldNotHaveResult(expr: Terminator, topLevelFunc: Function): Unit {
        if (expr.GetResult().isSome()) {
            ErrorInExpr(topLevelFunc, expr, "this terminator shouldn't have result.")
        }
    }

    private func TypeCheckError(expr: Expression, value: Value, expectedType: String, topLevelFunc: Function): Unit {
        let errMsg = "value " + value.GetIdentifier() + " used in " + GetExpressionString(expr) + " has type " +
            value.GetType().getOrThrow().ToString() + ", but " + expectedType + " type is expected."
        ErrorInFunc(topLevelFunc, errMsg)
    }

    private func OperandNumIsEqual(expectedNum: Int64, expr: Expression, topLevelFunc: Function): Bool {
        let realNum = expr.GetNumOfOperands()
        if (expectedNum != realNum) {
            ErrorInExpr(topLevelFunc, expr,
                "expect ${expectedNum} operand(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func OperandNumAtLeast(expectedNum: Int64, expr: Expression, topLevelFunc: Function): Bool {
        let realNum = expr.GetNumOfOperands()
        if (expectedNum > realNum) {
            ErrorInExpr(topLevelFunc, expr,
                "expect at least ${expectedNum} operand(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func OperandNumIsEqual(expectedNums: Array<Int64>, expr: Expression, topLevelFunc: Function): Bool {
        CJC_ASSERT(!expectedNums.isEmpty())
        let realNum = expr.GetNumOfOperands()
        for (expected in expectedNums) {
            if (expected == realNum) {
                return true
            }
        }
        var expectedNumStr = "{"
        for (expected in expectedNums) {
            expectedNumStr += "${expected}, "
        }
        expectedNumStr = expectedNumStr[0..expectedNumStr.size - 2] + "}"
        ErrorInExpr(topLevelFunc, expr, "expect " + expectedNumStr +
            " operand(s), but there are ${realNum} in fact.")
        return false
    }

    private func SuccessorNumIsEqual(expectedNum: Int64, term: Terminator, topLevelFunc: Function): Bool {
        let realNum = term.GetSuccessors().size
        if (expectedNum != realNum) {
            ErrorInExpr(topLevelFunc, term,
                "expect ${expectedNum} successor(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func SuccessorNumAtLeast(expectedNum: Int64, term: Terminator, topLevelFunc: Function): Bool {
        let realNum = term.GetSuccessors().size
        if (expectedNum > realNum) {
            ErrorInExpr(topLevelFunc, term,
                "expect at least ${expectedNum} successor(s), but there are ${realNum} in fact.")
            return false
        }
        return true
    }

    private func CheckLocalId(blockGroup: BlockGroup, topLevelFunc: Function): Unit {
        let allIds = HashSet<String>()
        let duplicatedLocalIds = TreeSet<String>()
        let exprResWithoutId = ArrayList<Expression>()
        for (param in topLevelFunc.GetParams()) {
            let identifier = param.GetIdentifier()
            if (allIds.contains(identifier)) {
                duplicatedLocalIds.add(identifier)
            } else {
                allIds.add(identifier)
            }
        }
        let preVisit: VisitExprActionFunc = { expr =>
            if (let Some(result) <- expr.GetResult()) {
                let identifier = result.GetIdentifier()
                if (identifier.isEmpty()) {
                    exprResWithoutId.add(expr)
                } else if (allIds.contains(identifier)) {
                    duplicatedLocalIds.add(identifier)
                } else {
                    allIds.add(identifier)
                }
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    for (param in lambdaExpr.GetParams()) {
                        let parameterIdentifier = param.GetIdentifier()
                        if (allIds.contains(parameterIdentifier)) {
                            duplicatedLocalIds.add(parameterIdentifier)
                        } else {
                            allIds.add(parameterIdentifier)
                        }
                    }
                }
            }
            return VisitResult.CONTINUE
        }
        Visitor.Visit(blockGroup, preVisit)
        if (!duplicatedLocalIds.isEmpty()) {
            ErrorInFunc(topLevelFunc, "there are duplicated local id: " + JoinStrings(ArrayList<String>(duplicatedLocalIds), ", "))
        }
        for (expr in exprResWithoutId) {
            ErrorInFunc(topLevelFunc, "the result of expression " + expr.ToString(0) + " doesn't have identifier.")
        }
    }


    private func CheckUnreachableOpAndGenericTyInFuncBody(blockGroup: BlockGroup): Unit {
        CheckUnreachableOpAndGenericTyInBG(blockGroup, ArrayList<Value>(), ArrayList<GenericType>())
    }

    private func CheckUnreachableOpAndGenericTyInBG(blockGroup: BlockGroup, reachableValues: ArrayList<Value>,
        reachableGenericTypes: ArrayList<GenericType>): Unit {
        let valueSize = reachableValues.size
        let typeSize = reachableGenericTypes.size
        if (let Some(ownerExpr) <- blockGroup.GetOwnerExpression()) {
            if (let Some(lambdaExpr) <- (ownerExpr as Lambda)) {
                reachableGenericTypes.add(all: lambdaExpr.GetGenericTypeParams())
                let params = lambdaExpr.GetParams()
                var idx: Int64 = 0
                while (idx < params.size) {
                    reachableValues.add(params[idx])
                    if (!GenericTypeIsInContainer(params[idx].GetType().getOrThrow(), reachableGenericTypes)) {
                        ErrorInFunc(blockGroup.GetTopLevelFunc().getOrThrow(), "generic type " +
                            params[idx].ToString(0) + "is unreachable, the type is ${idx}-th parameter in lambda " +
                            lambdaExpr.GetIdentifier() + ".")
                    }
                    idx++
                }
            }
        } else if (let Some(fn) <- blockGroup.GetOwnerFunc()) {
            if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
                reachableGenericTypes.add(all: parentDef.GetGenericTypeParams())
            }
            reachableGenericTypes.add(all: fn.GetGenericTypeParams())
            let params = fn.GetParams()
            var idx: Int64 = 0
            while (idx < params.size) {
                reachableValues.add(params[idx])
                if (!GenericTypeIsInContainer(params[idx].GetType().getOrThrow(), reachableGenericTypes)) {
                    ErrorInFunc(fn, "generic type " + params[idx].ToString(0) +
                        "is unreachable, the type is ${idx}-th parameter in function " + fn.GetIdentifier() + ".")
                }
                idx++
            }
        }
        if (let Some(entryBlock) <- blockGroup.GetEntryBlock()) {
            CheckUnreachableOpAndGenericTyInBlock(entryBlock, reachableValues, reachableGenericTypes,
                HashSet<Int64>())
        }
        while (reachableValues.size > valueSize) {
            reachableValues.remove(at: reachableValues.size - 1)
        }
        while (reachableGenericTypes.size > typeSize) {
            reachableGenericTypes.remove(at: reachableGenericTypes.size - 1)
        }
    }

    private func CheckUnreachableOpAndGenericTyInBlock(block: Block, reachableValues: ArrayList<Value>,
        reachableGenericTypes: ArrayList<GenericType>, visitedBlocks: HashSet<Int64>): Unit {
        if (visitedBlocks.contains(block.nodeId)) {
            return
        }
        visitedBlocks.add(block.nodeId)
        let valueSize = reachableValues.size
        for (expr in block.GetExpressionsRef()) {
            let typeSize = reachableGenericTypes.size
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                reachableGenericTypes.add(all: lambdaExpr.GetGenericTypeParams())
            }
            CheckUnreachableOpAndGenericTyInExpr(expr, reachableValues, reachableGenericTypes)
            if (let Some(result) <- expr.GetResult()) {
                reachableValues.add(result)
            }
            for (nestedGroup in expr.GetBlockGroups()) {
                CheckUnreachableOpAndGenericTyInBG(nestedGroup, reachableValues, reachableGenericTypes)
            }
            while (reachableGenericTypes.size > typeSize) {
                reachableGenericTypes.remove(at: reachableGenericTypes.size - 1)
            }
            if (let Some(terminator) <- expr.AsTerminator()) {
                for (successor in terminator.GetSuccessors()) {
                    CheckUnreachableOpAndGenericTyInBlock(successor, reachableValues, reachableGenericTypes,
                        visitedBlocks)
                }
            }
        }
        while (reachableValues.size > valueSize) {
            reachableValues.remove(at: reachableValues.size - 1)
        }
    }

    private func CheckUnreachableOpAndGenericTyInExpr(expr: Expression, reachableValues: ArrayList<Value>,
        reachableGenericTypes: ArrayList<GenericType>): Unit {
        CheckUnreachableOperandInExpr(expr, reachableValues)
        CheckUnreachableGenericTypeInExpr(expr, reachableGenericTypes)
    }

    private func CheckUnreachableOperandInExpr(expr: Expression, reachableValues: ArrayList<Value>): Unit {
        for (operand in expr.GetOperands()) {
            if (operand.IsLiteral() || operand.IsGlobal()) {
                continue
            }
            var found = false
            for (reachableValue in reachableValues) {
                if (reachableValue == operand) {
                    found = true
                    break
                }
            }
            if (!found) {
                ErrorInFunc(expr.GetTopLevelFunc().getOrThrow(), operand.GetIdentifier() + " in " +
                    expr.ToString(0) + " is unreachable.")
            }
        }
    }

    private func CheckUnreachableGenericTypeInExpr(expr: Expression,
        reachableGenericTypes: ArrayList<GenericType>): Unit {
        let topLevelFunc = expr.GetTopLevelFunc().getOrThrow()
        if (let Some(result) <- expr.GetResult()) {
            if (!GenericTypeIsInContainer(result.GetType().getOrThrow(), reachableGenericTypes)) {
                ErrorInFunc(topLevelFunc, "generic type " + result.GetType().getOrThrow().ToString() +
                    " is unreachable, the type is from result in expression " + expr.ToString(0) + ".")
            }
        }
        let kind = expr.GetExprKind()
        if (kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
            let ty = AllocateBase(expr).GetType()
            if (!GenericTypeIsInContainer(ty, reachableGenericTypes)) {
                ErrorInFunc(topLevelFunc, "generic type " + ty.ToString() +
                    " is unreachable, the type is allocated type in expression " + expr.ToString(0) + ".")
            }
        } else if (expr.IsFuncCall() || kind == ExprKind.APPLY_WITH_EXCEPTION ||
            kind == ExprKind.INVOKE_WITH_EXCEPTION || kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION) {
            let base = FuncCallBase(expr)
            let instantiatedTypeArgs = base.GetInstantiatedTypeArgs()
            var idx: Int64 = 0
            while (idx < instantiatedTypeArgs.size) {
                if (!GenericTypeIsInContainer(instantiatedTypeArgs[idx], reachableGenericTypes)) {
                    ErrorInFunc(topLevelFunc, "generic type " + instantiatedTypeArgs[idx].ToString() +
                        "is unreachable, the type is ${idx}-th instantiated type args in expression " +
                        expr.ToString(0) + ".")
                }
                idx++
            }
            if (let Some(thisType) <- base.GetThisType()) {
                if (!GenericTypeIsInContainer(thisType, reachableGenericTypes)) {
                    ErrorInFunc(topLevelFunc, "generic type " + thisType.ToString() +
                        " is unreachable, the type is ThisType in expression " + expr.ToString(0) + ".")
                }
            }
        } else if (let Some(rtti) <- (expr as GetRTTIStatic)) {
            if (!GenericTypeIsInContainer(rtti.GetRTTIType(), reachableGenericTypes)) {
                ErrorInFunc(topLevelFunc, "generic type " + rtti.GetRTTIType().ToString() +
                    " is unreachable, the type is rtti type in expression " + expr.ToString(0) + ".")
            }
        } else if (let Some(instanceOf) <- (expr as InstanceOf)) {
            if (!GenericTypeIsInContainer(instanceOf.GetType(), reachableGenericTypes)) {
                ErrorInFunc(topLevelFunc, "generic type " + instanceOf.GetType().ToString() +
                    " is unreachable, the type is instanceOf type in expression " + expr.ToString(0) + ".")
            }
        } else if (kind == ExprKind.RAW_ARRAY_ALLOCATE || kind == ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION) {
            let elementType = RawArrayAllocateBase(expr).GetElementType()
            if (!GenericTypeIsInContainer(elementType, reachableGenericTypes)) {
                ErrorInFunc(topLevelFunc, "generic type " + elementType.ToString() +
                    " is unreachable, the type is element type in expression " + expr.ToString(0) + ".")
            }
        } else if (kind == ExprKind.INTRINSIC || kind == ExprKind.INTRINSIC_WITH_EXCEPTION) {
            let instantiatedTypeArgs = IntrinsicBase(expr).GetInstantiatedTypeArgs()
            var idx: Int64 = 0
            while (idx < instantiatedTypeArgs.size) {
                if (!GenericTypeIsInContainer(instantiatedTypeArgs[idx], reachableGenericTypes)) {
                    ErrorInFunc(topLevelFunc, "generic type " + instantiatedTypeArgs[idx].ToString() +
                        "is unreachable, the type is ${idx}-th instantiated type args in expression " +
                        expr.ToString(0) + ".")
                }
                idx++
            }
        }
    }

    private func TypeIsExpected(srcType: Type, dstType: Type): Bool {
        if (srcType == dstType) {
            return true
        }
        if (srcType.IsNothing()) {
            return true
        }
        if (srcType.IsValueType() && dstType.StripAllRefs().IsClass()) {
            return false
        }
        if (srcType.IsEqualOrSubTypeOf(dstType, builder)) {
            return true
        }
        if (srcType.StripAllRefs().IsAny() && dstType.IsClassRef()) {
            return true
        }
        if (IsBoxRefType(srcType) || IsBoxRefType(dstType)) {
            return true
        }
        return false
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




private func GetExpressionString(expr: Expression): String {
    if (let Some(lambdaExpr) <- (expr as Lambda)) {
        return "lambda " + lambdaExpr.GetIdentifier()
    }
    if (let Some(resultValue) <- expr.GetResult()) {
        return resultValue.ToString(0)
    }
    return expr.ToString(0)
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
            if (item == genericTy) {
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
    let replaceTable = HashMap<GenericType, Type>()
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
                let instType = mapping[1].get(mappedGeneric) ?? continue
                if (instType != genericType) {
                    continue
                }
                let temp = mappedGeneric.GetUpperBounds()
                var tempIdx = temp.size - 1
                while (tempIdx >= 0) {
                    extraUpperBounds.add(temp[tempIdx], at: 0)
                    tempIdx--
                }
                replaceTable[mappedGeneric] = instType
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
    let replaceTable = HashMap<GenericType, Type>()
    replaceTable[generic2] = generic1
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
