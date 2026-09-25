package cjcj::chir

import std.collection.*

// Upstream ArrayListConstStartOpt.cpp:17-21 (3935aa1c).
private let ARRAY_TYPE_NAME: String = "Array"
private let ARRAYLIST_TYPE_NAME: String = "ArrayList"
private let ARRAYLIST_ITERATOR_TYPE_NAME: String = "ArrayListIterator"
private let MY_DATA_MEMBER_NAME: String = "myData"
private let START_MEMBER_NAME: String = "start"
// COLLECTION_PACKAGE_NAME is absent here; keep the existing string literals.
private let CORE_PKG: String = "std.core"
private let COLLECTION_PKG: String = "std.collection"

// Upstream ArrayListConstStartOpt.cpp:23-26.
private let ARRAY_FUNC_INLINE_WHITE_LIST: Array<FuncInfo> = [
    FuncInfo("getUnchecked", ARRAY_TYPE_NAME, [NOT_CARE], ANY_TYPE, CORE_PKG),
    FuncInfo("setUnchecked", ARRAY_TYPE_NAME, [NOT_CARE], ANY_TYPE, CORE_PKG)
]

// Upstream ArrayListConstStartOpt.cpp:28-32. Iterator `next` is in this list.
private let ARRAYLIST_FUNC_LIST: Array<FuncInfo> = [
    FuncInfo("[]", ARRAYLIST_TYPE_NAME, [NOT_CARE], ANY_TYPE, COLLECTION_PKG),
    FuncInfo("==", ARRAYLIST_TYPE_NAME, [NOT_CARE], ANY_TYPE, COLLECTION_PKG),
    FuncInfo("next", ARRAYLIST_ITERATOR_TYPE_NAME, [NOT_CARE], ANY_TYPE, COLLECTION_PKG)
]

// Upstream ArrayListConstStartOpt.cpp:34-42.
private func InWhiteList(`func`: Function, whiteList: Array<FuncInfo>): Bool {
    for (element in whiteList) {
        if (IsExpectedFunction(`func`, element)) {
            return true
        }
    }
    return false
}

// Upstream ArrayListConstStartOpt.cpp:44-59.
// GetInstanceVar takes Int64; path entries are UInt64.
private func IsMemberAccess(baseTy: Type, path: ArrayList<UInt64>, packageName: String, typeName: String,
    memberName: String): Bool {
    if (path.size != 1) {
        return false
    }
    let customTy = (baseTy.StripAllRefs() as CustomType) ?? return false
    let def = customTy.GetCustomTypeDef()
    if (!CheckCustomTypeDefIsExpected(def, packageName, typeName)) {
        return false
    }
    if (path[0] >= UInt64(def.GetAllInstanceVarNum())) {
        return false
    }
    return def.GetInstanceVar(Int64(path[0])).name == memberName
}

// Upstream ArrayListConstStartOpt.cpp:64-88.
// GetElementRef has GetLocation(), not GetBase().
private func MatchLoadOfMemberRef(value: Value, packageName: String, typeName: String,
    memberName: String): Option<Value> {
    let local = value.AsLocalVar() ?? return None
    let loadExpr = local.GetExpr() ?? return None
    let load = (loadExpr as Load) ?? return None
    let locLocal = load.GetLocation().AsLocalVar() ?? return None
    let locExpr = locLocal.GetExpr() ?? return None
    let getElementRef = (locExpr as GetElementRef) ?? return None
    let base = getElementRef.GetLocation()
    let baseTy = base.GetType() ?? return None
    if (!IsMemberAccess(baseTy, getElementRef.GetPath(), packageName, typeName, memberName)) {
        return None
    }
    return Some(base)
}

// Upstream ArrayListConstStartOpt.cpp:91-106.
private func IsFuncParamOfType(value: Value, fn: Function, packageName: String, typeName: String): Bool {
    if (!value.IsParameter()) {
        return false
    }
    let param = value.AsParameter().getOrThrow()
    var belongsToFunc = false
    for (funcParam in fn.GetParams()) {
        if (refEq(funcParam, param)) {
            belongsToFunc = true
            break
        }
    }
    if (!belongsToFunc) {
        return false
    }
    let paramTy = param.GetType() ?? return false
    let customTy = (paramTy.StripAllRefs() as CustomType) ?? return false
    return CheckCustomTypeDefIsExpected(customTy.GetCustomTypeDef(), packageName, typeName)
}

// Upstream ArrayListConstStartOpt.h:20-54; cpp:109-243.
public class ArrayListConstStartOpt {
    private let builder: CHIRBuilder
    private let optPassName: String = "ArrayListConstStartOpt Inline"
    private let pass: FunctionInline
    private let effectMap: OptEffectCHIRMap = OptEffectCHIRMap()

    public init(builder: CHIRBuilder, pass: FunctionInline) {
        this.builder = builder
        this.pass = pass
    }

    // Upstream ArrayListConstStartOpt.cpp:109-112.
    public func GetEffectMap(): OptEffectCHIRMap {
        return effectMap
    }

    // Upstream ArrayListConstStartOpt.cpp:114-121.
    private func CheckNeedInline(apply: Apply): Bool {
        if (!apply.GetCallee().IsFuncWithBody()) {
            return false
        }
        let callee = apply.GetCallee().AsFunction().getOrThrow()
        return InWhiteList(callee, ARRAY_FUNC_INLINE_WHITE_LIST)
    }

    // Upstream ArrayListConstStartOpt.cpp:132-157.
    private func IsStartOfArrayListMyData(field: Field, fn: Function): Bool {
        let baseTy = field.GetBase().GetType() ?? return false
        if (!IsMemberAccess(baseTy, field.GetPath(), CORE_PKG, ARRAY_TYPE_NAME, START_MEMBER_NAME)) {
            return false
        }
        let arrayList = MatchLoadOfMemberRef(
            field.GetBase(), COLLECTION_PKG, ARRAYLIST_TYPE_NAME, MY_DATA_MEMBER_NAME) ?? return false
        if (IsFuncParamOfType(arrayList, fn, COLLECTION_PKG, ARRAYLIST_TYPE_NAME)) {
            return true
        }
        let arrayListIterator = MatchLoadOfMemberRef(
            arrayList, COLLECTION_PKG, ARRAYLIST_ITERATOR_TYPE_NAME, MY_DATA_MEMBER_NAME) ?? return false
        return IsFuncParamOfType(arrayListIterator, fn, COLLECTION_PKG, ARRAYLIST_ITERATOR_TYPE_NAME)
    }

    // Upstream ArrayListConstStartOpt.cpp:159-168.
    // Expression.ReplaceWith already replaces result users.
    private func RewriteStartWithConstZero(oldExpr: Expression): Unit {
        let oldExprResult = oldExpr.GetResult().getOrThrow()
        let oldExprParent = oldExpr.GetParentBlock().getOrThrow()
        let literalValueZero = builder.CreateLiteralValue(IntLiteral(0u64), builder.context.GetInt64Ty())
        let newExpr = builder.CreateConstant(
            oldExprResult.GetType().getOrThrow(), literalValueZero, oldExprParent)
        newExpr.SetDebugLocation(oldExpr.GetDebugLocation())
        oldExpr.ReplaceWith(newExpr)
    }

    // Upstream ArrayListConstStartOpt.cpp:170-213.
    private func RewriteStartAfterInline(fn: Function): Unit {
        let startFields = ArrayList<Field>()
        let collect: VisitExprActionFunc = { expr =>
            if (let Some(field) <- (expr as Field)) {
                if (IsStartOfArrayListMyData(field, fn)) {
                    startFields.add(field)
                }
            }
            return VisitResult.CONTINUE
        }
        Visitor.Visit(fn, collect)
        for (field in startFields) {
            RewriteStartWithConstZero(field)
        }
    }

    // Upstream ArrayListConstStartOpt.cpp:215-242.
    public func RunOnPackage(`package`: Package): Unit {
        for (fn in `package`.GetGlobalFuncsWithBody()) {
            if (!InWhiteList(fn, ARRAYLIST_FUNC_LIST)) {
                continue
            }
            let applies = ArrayList<Apply>()
            let collectApplies: VisitExprActionFunc = { expr =>
                if (let Some(apply) <- (expr as Apply)) {
                    if (CheckNeedInline(apply)) {
                        applies.add(apply)
                    }
                }
                return VisitResult.CONTINUE
            }
            Visitor.Visit(fn, collectApplies)
            for (apply in applies) {
                pass.DoFunctionInline(apply, optPassName)
                MergeEffectMap(pass.GetEffectMap(), effectMap)
                RewriteStartAfterInline(fn)
            }
            RewriteStartAfterInline(fn)
        }
    }
}
