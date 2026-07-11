package cjcj::chir

import std.collection.*
import cjcj::ast.ASTKind
import cjcj::ast.Decl as AstDecl
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::basic.Position as BasicPosition
import cjcj::basic.Range as BasicRange
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, FileUtil}

public let ANY_TYPE: String = "ANY_TYPE"
public let NOT_CARE: String = "NOT_CARE"
private let STD_PACKAGE_PREFIX: String = "std."

public func TryGetFromCache<T>(key: String, cache: HashMap<String, Value>): Option<T> where T <: Value {
    let value = cache.get(key) ?? return None
    return value as T
}

public func AdjustVarInitType(funcType: FuncType, outerDecl: AstDecl, builder: CHIRBuilder,
    chirType: CHIRType): FuncType {
    let params = funcType.GetParamTypes()
    let paramsTy = ArrayList<Type>()
    let thisTy = chirType.TranslateType(outerDecl.GetTy().getOrThrow())
    if (outerDecl.astKind == ASTKind.STRUCT_DECL) {
        paramsTy.add(builder.context.GetRefTy(thisTy))
    } else {
        paramsTy.add(thisTy)
    }
    for (param in params) {
        paramsTy.add(param)
    }
    return builder.context.GetFuncTy(paramsTy, funcType.GetReturnType())
}

public type OptEffectCHIRMap = HashMap<Value, HashSet<Value>>

public class FuncInfo {
    public let funcName: String
    public let parentTy: String
    public let params: Array<String>
    public let returnTy: String
    public let pkgName: String

    public init(funcName: String, parentTy: String, params: Array<String>, returnTy: String, pkgName: String) {
        this.funcName = funcName
        this.parentTy = parentTy
        this.params = params
        this.returnTy = returnTy
        this.pkgName = pkgName
    }
}

public func MergeEffectMap(from: OptEffectCHIRMap, to: OptEffectCHIRMap): Unit {
    for ((value, fromValues) in from) {
        if (let Some(toValues) <- to.get(value)) {
            for (affected in fromValues) {
                toValues.add(affected)
            }
        } else {
            let values = HashSet<Value>()
            for (affected in fromValues) {
                values.add(affected)
            }
            to[value] = values
        }
    }
}

public class GenericTypeConvertor {
    private let instMap: HashMap<GenericType, Type>
    private let builder: CHIRBuilder

    public init(instMap: HashMap<GenericType, Type>, builder: CHIRBuilder) {
        this.instMap = instMap
        this.builder = builder
    }

    public func ConvertToInstantiatedType(ty: Type): Type {
        return ReplaceRawGenericArgType(ty, instMap, builder)
    }
}

public func GetInstMapFromCurDefToCurType(curType: CustomType): HashMap<GenericType, Type> {
    let genericTypeArgs = curType.GetCustomTypeDef().GetGenericTypeParams()
    let instTypeArgs = curType.GetTypeArgs()
    if (!genericTypeArgs.isEmpty()) {
        CJC_ASSERT(genericTypeArgs.size == instTypeArgs.size)
    }
    let replaceTable = HashMap<GenericType, Type>()
    var idx: Int64 = 0
    while (idx < genericTypeArgs.size) {
        replaceTable[genericTypeArgs[idx]] = instTypeArgs[idx]
        idx++
    }
    return replaceTable
}

public func GetInstMapFromCurDefAndExDefToCurType(curType: CustomType): HashMap<GenericType, Type> {
    let replaceTable = GetInstMapFromCurDefToCurType(curType)
    for (extendDef in curType.GetCustomTypeDef().GetExtends()) {
        let tempTable = extendDef.GetExtendedType().getOrThrow().CalculateGenericTyMapping(curType)[1]
        for ((key, value) in tempTable) {
            if (!replaceTable.contains(key)) {
                replaceTable[key] = value
            }
        }
    }
    return replaceTable
}

public func ReplaceThisTypeToConcreteType(ty: Type, concreteType: Type, builder: CHIRBuilder): Type {
    if (let Some(refTy) <- (ty as RefType)) {
        if (refTy.GetBaseType().IsThis()) {
            return concreteType
        }
    }
    if (ty.IsThis()) {
        return concreteType
    }
    let newArgs = ArrayList<Type>()
    for (argTy in ty.GetTypeArgs()) {
        newArgs.add(ReplaceThisTypeToConcreteType(argTy, concreteType, builder))
    }
    return CreateNewTypeWithArgs(ty, newArgs, builder)
}

private func GetMemberVarByName(def: CustomTypeDef, varName: String): MemberVarInfo {
    let vars = def.GetAllInstanceVars()
    var idx = vars.size
    while (idx > 0) {
        idx--
        if (vars[idx].name == varName) {
            return vars[idx]
        }
    }
    CJC_ABORT()
    throw IllegalStateException("member variable is not available")
}

public func GetInstMemberTypeByName(rootType: CustomType, names: ArrayList<String>,
    builder: CHIRBuilder): Type {
    return GetInstMemberTypeByNameCheckingReadOnly(rootType, names, builder)[0]
}

public func GetInstMemberTypeByNameCheckingReadOnly(rootType: CustomType, names: ArrayList<String>,
    builder: CHIRBuilder): (Type, Bool) {
    if (names.isEmpty()) {
        CJC_ABORT()
        return (rootType, false)
    }
    let customTypeDef = rootType.GetCustomTypeDef()
    let instMap = HashMap<Int64, (GenericType, Type)>()
    rootType.GetInstMap(instMap, builder)
    let currentName = names[0]
    let member = GetMemberVarByName(customTypeDef, currentName)
    let isReadOnly = member.TestAttr(Attribute.READONLY)
    let memberTy = ReplaceRawGenericArgType(member.ty, instMap, builder)
    if (names.size > 1) {
        let pureMemberTy = memberTy.StripAllRefs()
        if (pureMemberTy.IsNominal()) {
            let subNames = names.clone()
            subNames.remove(at: 0)
            let (memberType, isMemberReadOnly) = GetInstMemberTypeByNameCheckingReadOnly(
                (pureMemberTy as CustomType).getOrThrow(), subNames, builder)
            return (memberType, isReadOnly || isMemberReadOnly)
        } else if (pureMemberTy.IsGeneric()) {
            let subNames = names.clone()
            subNames.remove(at: 0)
            let (memberType, isMemberReadOnly) = GetInstMemberTypeByNameCheckingReadOnly(
                (pureMemberTy as GenericType).getOrThrow(), subNames, builder)
            return (memberType, isReadOnly || isMemberReadOnly)
        } else {
            CJC_ABORT()
        }
    }
    return (memberTy, isReadOnly)
}

public func GetInstMemberTypeByNameCheckingReadOnly(rootType: GenericType, names: ArrayList<String>,
    builder: CHIRBuilder): (Type, Bool) {
    var concreteType: Option<Type> = None
    for (upperBound in rootType.GetUpperBounds()) {
        let upperBoundCustomType = (upperBound.StripAllRefs() as CustomType).getOrThrow()
        if (upperBoundCustomType.GetCustomTypeDef().IsClassLike()) {
            if (concreteType.isNone()) {
                concreteType = upperBound
            } else if (upperBoundCustomType.IsEqualOrSubTypeOf(concreteType.getOrThrow(), builder)) {
                concreteType = upperBound
            }
        }
    }
    CJC_NULLPTR_CHECK(concreteType)
    return GetInstMemberTypeByNameCheckingReadOnly(
        (concreteType.getOrThrow().StripAllRefs() as CustomType).getOrThrow(), names, builder)
}

public func IsExpectedFunction(fn: Function, funcInfo: FuncInfo): Bool {
    return CheckFuncName(fn, funcInfo) && CheckParentTy(fn, funcInfo) && CheckParametersTy(fn, funcInfo) &&
        CheckReturnTy(fn, funcInfo) && CheckPkgName(fn, funcInfo)
}

public func PrintOptInfo(expr: Expression, debug: Bool, optName: String): Unit {
    if (!debug) {
        return
    }
    let position = expr.GetDebugLocation().GetBeginPos()
    let strPos = "in the line:" + position.line.toString() + " and the column:" + position.column.toString()
    let message = "The " + expr.GetExprKindName() + " node " + strPos + ", was optimized by " + optName
    println(message)
}

public func IsSTDFunction(fn: Function): Bool {
    return fn.GetPackageName().startsWith(STD_PACKAGE_PREFIX)
}

private func CheckFuncName(fn: Function, funcInfo: FuncInfo): Bool {
    return fn.GetSrcCodeIdentifier() == funcInfo.funcName
}

private func CheckParentTy(fn: Function, funcInfo: FuncInfo): Bool {
    if (funcInfo.parentTy == NOT_CARE) {
        return true
    }
    if (let Some(parentTy) <- fn.GetParentCustomTypeOrExtendedType()) {
        if (funcInfo.parentTy == ANY_TYPE) {
            return true
        }
        if (let Some(customTy) <- (parentTy as CustomType)) {
            return customTy.GetCustomTypeDef().GetIdentifier() == funcInfo.parentTy
        }
        return parentTy.ToSrcCodeString() == funcInfo.parentTy
    }
    return funcInfo.parentTy.isEmpty()
}

private func CheckParametersTy(fn: Function, funcInfo: FuncInfo): Bool {
    if (let Some(funcTy) <- fn.GetFuncType()) {
        let paramTys = funcTy.GetParamTypes()
        if (fn.IsMemberFunc() && !fn.TestAttr(Attribute.STATIC) && !paramTys.isEmpty()) {
            paramTys.remove(at: 0)
        }
        var needToMatchArgsNum = true
        let loopCnt = if (funcInfo.params.size < paramTys.size) { funcInfo.params.size } else { paramTys.size }
        var idx: Int64 = 0
        while (idx < loopCnt) {
            let expectedTy = funcInfo.params[idx]
            if (expectedTy == ANY_TYPE) {
                idx++
                continue
            }
            if (expectedTy == NOT_CARE) {
                needToMatchArgsNum = false
                break
            }
            if (expectedTy != paramTys[idx].ToSrcCodeString()) {
                return false
            }
            idx++
        }
        if (funcInfo.params.size > loopCnt && funcInfo.params[loopCnt] == NOT_CARE) {
            needToMatchArgsNum = false
        }
        if (needToMatchArgsNum && funcInfo.params.size != paramTys.size) {
            return false
        }
        return true
    }
    return funcInfo.params.isEmpty()
}

private func CheckReturnTy(fn: Function, funcInfo: FuncInfo): Bool {
    if (funcInfo.returnTy == NOT_CARE || funcInfo.returnTy == ANY_TYPE) {
        return true
    }
    if (let Some(returnTy) <- fn.GetReturnType()) {
        return returnTy.ToSrcCodeString() == funcInfo.returnTy
    }
    return false
}

private func CheckPkgName(fn: Function, funcInfo: FuncInfo): Bool {
    if (funcInfo.pkgName == NOT_CARE || funcInfo.pkgName == ANY_TYPE) {
        return true
    }
    return fn.GetPackageName() == funcInfo.pkgName
}

public func IsGetOrThrowFunction(expr: Expression): Bool {
    if (expr.GetExprKind() != ExprKind.APPLY || expr.GetNumOfOperands() == 0) {
        return false
    }
    if (let Some(callee) <- expr.GetOperand(0).AsFunction()) {
        let getOrThrowInfo = FuncInfo("getOrThrow", NOT_CARE, [NOT_CARE], NOT_CARE, "std.core")
        return IsExpectedFunction(callee, getOrThrowInfo)
    }
    return false
}

public func ReplaceUsesWithWrapper(curFunc: Value, apply: Option<Apply>, wrapperFunc: Value,
    isForeign!: Bool = false): Unit {
    for (user in curFunc.GetUsers()) {
        if (let Some(wrapperApply) <- apply) {
            if (refEq(user, wrapperApply)) {
                continue
            }
        }
        if (user.GetExprKind() == ExprKind.APPLY) {
            let applyNode = (user as Apply).getOrThrow()
            if (!isForeign && refEq(applyNode.GetCallee(), curFunc)) {
                continue
            }
        }
        if (user.GetExprKind() == ExprKind.APPLY_WITH_EXCEPTION) {
            let applyNode = (user as ApplyWithException).getOrThrow()
            if (!isForeign && refEq(applyNode.GetCallee(), curFunc)) {
                continue
            }
        }
        user.ReplaceOperand(curFunc, wrapperFunc)
    }
}

public func IsStructEnum(typeValue: Type): Bool {
    if (let Some(enumTy) <- (typeValue as EnumType)) {
        return !enumTy.GetEnumDef().GetCtors().isEmpty()
    }
    return false
}

public func GetFuncParams(funcBody: BlockGroup): ArrayList<Parameter> {
    if (let Some(fn) <- funcBody.GetOwnerFunc()) {
        return fn.GetParams()
    }
    let lambdaExpr = (funcBody.GetOwnerExpression().getOrThrow() as Lambda).getOrThrow()
    return lambdaExpr.GetParams()
}

public func GetReturnValue(funcBody: BlockGroup): Option<LocalVar> {
    if (let Some(fn) <- funcBody.GetOwnerFunc()) {
        return fn.GetReturnValue()
    }
    let lambdaExpr = (funcBody.GetOwnerExpression().getOrThrow() as Lambda).getOrThrow()
    return lambdaExpr.GetReturnValue()
}

public func GetFuncType(funcBody: BlockGroup): Option<FuncType> {
    if (let Some(fn) <- funcBody.GetOwnerFunc()) {
        return fn.GetFuncType()
    }
    let lambdaExpr = (funcBody.GetOwnerExpression().getOrThrow() as Lambda).getOrThrow()
    return lambdaExpr.GetFuncType()
}

public func GetSuperTypesRecusively(subType: Type, builder: CHIRBuilder): ArrayList<ClassType> {
    let result = ArrayList<ClassType>()
    if (let Some(customType) <- (subType as CustomType)) {
        return customType.GetSuperTypesRecusively(builder)
    } else if (let Some(builtinType) <- (subType as BuiltinType)) {
        return builtinType.GetSuperTypesRecusively(builder)
    } else if (let Some(genericType) <- (subType as GenericType)) {
        for (upperBound in genericType.GetUpperBounds()) {
            let classType = (upperBound.StripAllRefs() as ClassType).getOrThrow()
            result.add(classType)
            for (parent in GetSuperTypesRecusively(classType, builder)) {
                var containsParent = false
                for (item in result) {
                    if (item == parent) {
                        containsParent = true
                        break
                    }
                }
                if (!containsParent) {
                    result.add(parent)
                }
            }
        }
    } else {
        CJC_ABORT()
    }
    return result
}

private func GetInstParentType(candidate: ArrayList<ClassType>, callee: Function, args: ArrayList<Value>,
    builder: CHIRBuilder): ClassType {
    CJC_ASSERT(!candidate.isEmpty())
    if (candidate.size == 1) {
        return candidate[0]
    }
    let classDefs = HashSet<Int64>()
    for (parentTy in candidate) {
        classDefs.add(parentTy.GetClassDef().nodeId)
    }
    CJC_ASSERT(classDefs.size == 1)

    let offset: Int64 = if (callee.TestAttr(Attribute.STATIC)) { 0 } else { 1 }
    let argTypes = ArrayList<Type>()
    var argIdx = offset
    while (argIdx < args.size) {
        argTypes.add(args[argIdx].GetType().getOrThrow())
        argIdx++
    }
    let paramTypes = callee.GetFuncType().getOrThrow().GetParamTypes()
    if (!callee.TestAttr(Attribute.STATIC)) {
        paramTypes.remove(at: 0)
    }
    CJC_ASSERT(argTypes.size == paramTypes.size)
    for (parentTy in candidate) {
        let res = parentTy.GetClassDef().GetType().getOrThrow().CalculateGenericTyMapping(parentTy)
        CJC_ASSERT(res[0])
        var argTypeMatched = true
        var paramIdx: Int64 = 0
        while (paramIdx < paramTypes.size) {
            let instType = ReplaceRawGenericArgType(paramTypes[paramIdx], res[1], builder)
            if (!ParamTypeIsEquivalent(instType, argTypes[paramIdx])) {
                argTypeMatched = false
                break
            }
            paramIdx++
        }
        if (argTypeMatched) {
            return parentTy
        }
    }
    CJC_ABORT()
    throw IllegalStateException("instantiated parent type of callee is not available")
}

public func GetInstParentType(instSubType: Type, genericParentType: Type, builder: CHIRBuilder): Type {
    if (!genericParentType.IsGenericRelated()) {
        return genericParentType
    }
    if (instSubType == genericParentType) {
        return genericParentType
    }
    let parentDerefType = genericParentType.StripAllRefs()
    var pair = parentDerefType.CalculateGenericTyMapping(instSubType)
    var res = pair[0]
    var replaceTable = pair[1]
    if (!res) {
        for (parent in GetSuperTypesRecusively(instSubType, builder)) {
            pair = parentDerefType.CalculateGenericTyMapping(parent)
            res = pair[0]
            replaceTable = pair[1]
            if (res) {
                break
            }
        }
    }
    CJC_ASSERT(res)
    return ReplaceRawGenericArgType(genericParentType, replaceTable, builder)
}

public func GetInstParentCustomTyOfCallee(value: Value, args: ArrayList<Value>, thisType: Option<Type>,
    builder: CHIRBuilder): Option<Type> {
    let callee = value.AsFunction() ?? return None
    if (!callee.IsMemberFunc()) {
        return None
    }

    var calleeParentDef = callee.GetParentCustomTypeDef().getOrThrow()
    let thisTy = thisType ?? return calleeParentDef.GetType()

    let calleeParentTy = calleeParentDef.GetType().getOrThrow()
    if (!calleeParentTy.IsBuiltinType() && calleeParentDef.IsExtend()) {
        calleeParentDef = (calleeParentTy as CustomType).getOrThrow().GetCustomTypeDef()
    }
    let derefThisType = thisTy.StripAllRefs()
    CJC_ASSERT(!(derefThisType.IsCustomType() && calleeParentDef.GetType().getOrThrow().IsBuiltinType()))
    let typeAndDefIsEquivalent = { ty: CustomType, def: CustomTypeDef =>
        let typeDef = ty.GetCustomTypeDef()
        if (typeDef.nodeId == def.nodeId) {
            true
        } else if (let Some(defTy) <- def.GetType()) {
            ty == defTy || typeDef.GetIdentifier() == def.GetIdentifier()
        } else {
            typeDef.GetIdentifier() == def.GetIdentifier()
        }
    }

    if (let Some(customType) <- (derefThisType as CustomType)) {
        if (typeAndDefIsEquivalent(customType, calleeParentDef)) {
            return Some(derefThisType)
        }
    } else if (let Some(builtinType) <- (derefThisType as BuiltinType)) {
        if (builtinType.IsSameTypeKind(calleeParentDef.GetType().getOrThrow())) {
            return Some(derefThisType)
        }
    }

    let parentTypes = GetSuperTypesRecusively(derefThisType, builder)
    let matchedTypes = ArrayList<ClassType>()
    for (parentTy in parentTypes) {
        if (typeAndDefIsEquivalent(parentTy, calleeParentDef)) {
            matchedTypes.add(parentTy)
        }
    }
    if (matchedTypes.isEmpty()) {
        return Some(derefThisType)
    }
    return Some(GetInstParentType(matchedTypes, callee, args, builder))
}

public func GetInstParentCustomTypeForApplyCallee(expr: Apply, builder: CHIRBuilder): Option<Type> {
    return GetInstParentCustomTyOfCallee(expr.GetCallee(), expr.GetArgs(), expr.GetThisType(), builder)
}

public func GetInstParentCustomTypeForAweCallee(expr: ApplyWithException, builder: CHIRBuilder): Option<Type> {
    return GetInstParentCustomTyOfCallee(expr.GetCallee(), expr.GetArgs(), expr.GetThisType(), builder)
}

public func ToPosInfo(loc: DebugLocation, isPrintFileName!: Bool = false): String {
    let beginPos = loc.GetBeginPos()
    let fileName = if (isPrintFileName) { FileUtil.GetFileName(loc.GetAbsPath()) + "," } else { "" }
    return " at [" + fileName + beginPos.line.toString() + "," + beginPos.column.toString() + "]"
}

public func ToPosition(loc: DebugLocation): BasicPosition {
    let begin = loc.GetBeginPos()
    return BasicPosition(UInt64(loc.GetFileID()), Int64(begin.line), Int64(begin.column))
}

public func ToRange(loc: DebugLocation): BasicRange {
    let begin = loc.GetBeginPos()
    let end = loc.GetEndPos()
    let beginPos = BasicPosition(UInt64(loc.GetFileID()), Int64(begin.line), Int64(begin.column))
    let endPos = BasicPosition(UInt64(loc.GetFileID()), Int64(end.line), Int64(end.column))
    return BasicMakeRange(beginPos, endPos)
}

public func ToRangeIfNotZero(loc: DebugLocation): (Bool, BasicRange) {
    let begin = loc.GetBeginPos()
    let end = loc.GetEndPos()
    let beginPos = BasicPosition(UInt64(loc.GetFileID()), Int64(begin.line), Int64(begin.column))
    let endPos = BasicPosition(UInt64(loc.GetFileID()), Int64(end.line), Int64(end.column))
    let range = BasicMakeRange(beginPos, endPos)
    if (!beginPos.IsZero() && !endPos.IsZero()) {
        return (true, range)
    }
    return (false, range)
}

public func GetDebugPos(expr: Base): (Bool, BasicRange) {
    let warningRange = ToRangeIfNotZero(expr.GetDebugLocationInfoForWarning())
    if (warningRange[0]) {
        return warningRange
    }
    return ToRangeIfNotZero(expr.GetDebugLocation())
}

public func IsCrossPackage(pos: BasicPosition, currentPackage: String, diag: BasicDiagnosticEngine): Bool {
    let source = diag.GetSourceManager().GetSource(pos.fileID)
    if (let Some(packageName) <- source.packageName) {
        if (currentPackage != packageName) {
            return true
        }
    }
    return false
}

public func CheckCustomTypeDefIsExpected(def: CustomTypeDef, packageName: String, defSrcCodeName: String): Bool {
    var pkgName = def.GetPackageName()
    if (let Some(genericDecl) <- def.GetGenericDecl()) {
        pkgName = genericDecl.GetPackageName()
    }
    return pkgName == packageName && def.GetSrcCodeIdentifier() == defSrcCodeName
}

public func ReturnTypeShouldBeVoid(fn: Function): Bool {
    return fn.IsGVInit() || fn.IsFinalizer() || (fn.IsConstructor() && !fn.TestAttr(Attribute.STATIC))
}

public func GetMethodIdxInAutoEnvObject(methodName: String): UInt64 {
    var methodIdx = 0u64
    if (methodName == "$GenericVirtualFunc") {
        methodIdx = 0u64
    } else if (methodName == "$InstVirtualFunc") {
        methodIdx = 1u64
    } else {
        CJC_ABORT()
    }
    return methodIdx
}

public func MangleMethodName(methodName: String, funcTy: FuncType, omitFirstArg!: Bool = false): String {
    var res = methodName + "("
    let paramTys = funcTy.GetParamTypes()
    var idx = if (omitFirstArg) { 1 } else { 0 }
    while (idx < paramTys.size) {
        res += paramTys[idx].ToString() + " "
        idx++
    }
    res += ")"
    return res
}

public func JoinStrings(values: ArrayList<String>, delimiter: String): String {
    var out = ""
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            out += delimiter
        }
        out += values[idx]
        idx++
    }
    return out
}

public func RequiredResultType(expr: Expression): Type {
    if (let Some(resultTy) <- expr.GetResultType()) {
        return resultTy
    }
    throw IllegalArgumentException("expression clone requires a result type: " + expr.GetExprKindName())
}

public func IsApplyToLambda(expr: Expression): Option<Lambda> {
    if (expr.GetExprKind() != ExprKind.APPLY && expr.GetExprKind() != ExprKind.APPLY_WITH_EXCEPTION) {
        return None
    }
    if (expr.GetNumOfOperands() == 0) {
        throw IllegalStateException("IsApplyToLambda expected at least one operand")
    }
    if (let Some(callee) <- expr.GetOperand(0).AsLocalVar()) {
        let calleeExpr = callee.GetExpr() ??
            throw IllegalStateException("IsApplyToLambda expected callee expression")
        return calleeExpr as Lambda
    }
    return None
}

public func IsInitialisingMemberVar(functionValue: Function, store: StoreElementRef): Option<Int64> {
    let location = store.GetLocation()
    if ((functionValue.IsConstructor() || functionValue.GetFuncKind() == FuncKind.INSTANCEVAR_INIT) &&
        location.IsParameter()) {
        let paths = store.GetPath()
        if (refEq(location, functionValue.GetParam(0)) && paths.size == 1) {
            return Int64(paths[0])
        }
    }
    return None
}

public func TryGetInstanceVarInitFromApply(expr: Expression): Option<Function> {
    if (expr.GetExprKind() == ExprKind.APPLY) {
        if (let Some(applyExpr) <- (expr as Apply)) {
            let callee = applyExpr.GetCallee()
            if (callee.IsFuncWithBody()) {
                if (let Some(fn) <- callee.AsFunction()) {
                    if (fn.IsInstanceVarInit()) {
                        return fn
                    }
                }
            }
        }
    }
    return None
}

private class VisitStackElem {
    public let block: Block
    public let successors: ArrayList<Block>

    public init(block: Block, successors: ArrayList<Block>) {
        this.block = block
        this.successors = successors
    }
}

public func TopologicalSort(entryBlock: Block): ArrayList<Block> {
    let result = ArrayList<Block>()
    let visited = ArrayList<Int64>()
    let visitStack = ArrayList<VisitStackElem>()
    visited.add(entryBlock.nodeId)
    visitStack.add(VisitStackElem(entryBlock, entryBlock.GetSuccessors()))

    while (!visitStack.isEmpty()) {
        while (!visitStack[visitStack.size - 1].successors.isEmpty()) {
            let top = visitStack[visitStack.size - 1]
            let lastSuccessor = top.successors[top.successors.size - 1]
            top.successors.remove(at: top.successors.size - 1)
            var hasVisited = false
            for (id in visited) {
                if (id == lastSuccessor.nodeId) {
                    hasVisited = true
                    break
                }
            }
            if (!hasVisited) {
                visited.add(lastSuccessor.nodeId)
                visitStack.add(VisitStackElem(lastSuccessor, lastSuccessor.GetSuccessors()))
            }
        }

        var shouldContinue = true
        while (shouldContinue && !visitStack.isEmpty()) {
            result.add(visitStack[visitStack.size - 1].block, at: 0)
            visitStack.remove(at: visitStack.size - 1)
            shouldContinue = !visitStack.isEmpty() && visitStack[visitStack.size - 1].successors.isEmpty()
        }
    }
    return result
}

public func GetLambdaCapturedVarsRecursively(lambda: Lambda): ArrayList<Value> {
    let capturedVars = ArrayList<Value>()
    let visitedLambdas = ArrayList<Lambda>()
    CollectLambdaCapturedVarsRecursively(lambda, capturedVars, visitedLambdas)
    return capturedVars
}

private func CollectLambdaCapturedVarsRecursively(lambda: Lambda, capturedVars: ArrayList<Value>,
    visitedLambdas: ArrayList<Lambda>): Unit {
    for (visited in visitedLambdas) {
        if (refEq(visited, lambda)) {
            return
        }
    }
    visitedLambdas.add(lambda)
    if (let Some(lambdaBody) <- lambda.GetBody()) {
        VisitLambdaBodyForCapturedVars(lambdaBody, capturedVars, visitedLambdas)
    }
    for (captured in lambda.GetCapturedVariables()) {
        var hasCaptured = false
        for (value in capturedVars) {
            if (refEq(value, captured)) {
                hasCaptured = true
                break
            }
        }
        if (IsRefValue(captured) && !hasCaptured) {
            capturedVars.add(captured)
        }
    }
}

private func VisitLambdaBodyForCapturedVars(body: BlockGroup, capturedVars: ArrayList<Value>,
    visitedLambdas: ArrayList<Lambda>): Unit {
    for (block in body.GetBlocksRef()) {
        for (expr in block.GetExpressionsRef()) {
            if (let Some(appliedLambda) <- IsApplyToLambda(expr)) {
                CollectLambdaCapturedVarsRecursively(appliedLambda, capturedVars, visitedLambdas)
            } else if ((expr as Lambda).isSome()) {
                continue
            } else {
                for (group in expr.GetBlockGroups()) {
                    VisitLambdaBodyForCapturedVars(group, capturedVars, visitedLambdas)
                }
            }
        }
    }
}

private func IsRefValue(value: Value): Bool {
    if (let Some(ty) <- value.GetType()) {
        return ty.IsRef()
    }
    return false
}
