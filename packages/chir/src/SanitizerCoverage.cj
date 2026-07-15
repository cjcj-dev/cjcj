package cjcj::chir

import std.collection.*
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.Linkage as BasicLinkage
import cjcj::mangle.{MANGLE_CANGJIE_PREFIX, MANGLE_FUNC_PARAM_TYPE_PREFIX, MANGLE_GLOBAL_FILE_INIT_PREFIX,
    MANGLE_GLOBAL_VARIABLE_INIT_PREFIX, MANGLE_VOID_TY_SUFFIX, MangleName, SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION}
import cjcj::option.{GlobalOptions, SanitizerCoverageOptions, SanitizerCoverageType}
import cjcj::utils.{CJC_ASSERT, OverflowStrategy}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:23-37.
private func CreateNonMemberApply(resultTy: Type, callee: Value, args: ArrayList<Value>, parent: Block,
    builder: CHIRBuilder, loc!: DebugLocation = INVALID_LOCATION): Apply {
    let result = builder.CreateApply(resultTy, callee, FuncCallContext(args: args), parent)
    result.SetDebugLocation(loc)
    return result
}

private func CreateMemberApply(resultTy: Type, callee: Value, thisType: Type, args: ArrayList<Value>, parent: Block,
    builder: CHIRBuilder, loc!: DebugLocation = INVALID_LOCATION): Apply {
    let result = builder.CreateApply(resultTy, callee, FuncCallContext(args: args, thisType: Some(thisType)), parent)
    result.SetDebugLocation(loc)
    return result
}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:39-114.
private let CHAR_ARRAY_TEST_PACK: String = "CharArrayTest"
private let SanCovBoolFlagInitName: String = "__cj_sancov_bool_flag_ctor"
private let SanCovCharArrayInitName: String = "__cj_sancov_8bit_counters_ctor"
private let SanCovUInt32ArrayInitName: String = "__cj_sancov_pc_guard_ctor"
private let SAN_COV_PC_GUARD: String = "__sanitizer_cov_trace_pc_guard"
private let SanCovTraceCmp1: String = "__sanitizer_cov_trace_cmp1"
private let SanCovTraceCmp2: String = "__sanitizer_cov_trace_cmp2"
private let SanCovTraceCmp4: String = "__sanitizer_cov_trace_cmp4"
private let SanCovTraceCmp8: String = "__sanitizer_cov_trace_cmp8"
private let SanCovTraceConstCmp1: String = "__sanitizer_cov_trace_const_cmp1"
private let SanCovTraceConstCmp2: String = "__sanitizer_cov_trace_const_cmp2"
private let SanCovTraceConstCmp4: String = "__sanitizer_cov_trace_const_cmp4"
private let SanCovTraceConstCmp8: String = "__sanitizer_cov_trace_const_cmp8"
private let SAN_COV_TRACE_MEM_CMP: String = "__cj_sanitizer_weak_hook_memcmp"
private let SAN_COV_TRACE_STRN_CMP: String = "__cj_sanitizer_weak_hook_strncmp"
private let SAN_COV_TRACE_STR_CMP: String = "__cj_sanitizer_weak_hook_strcmp"
private let SAN_COV_TRACE_STR_CASE_CMP: String = "__cj_sanitizer_weak_hook_strcasecmp"
private let SanCovTraceSwitchName: String = "__sanitizer_cov_trace_switch"
private let SanCovCreatePCTable: String = "__cj_sancov_pcs_init"
private let SanCovUpdateStackDepth: String = "__cj_sancov_update_stack_depth"

private let SAN_COV_CTOR2_GLOBAL_VAR_NAME = HashMap<String, String>([
    (SanCovBoolFlagInitName, "sancov$_bool_flag"),
    (SanCovCharArrayInitName, "sancov$_8bit_counters"),
    (SanCovUInt32ArrayInitName, "sancov$_pc_guard")
])

private let STRING_FUNC_NAME2_SAN_COV_FUNC = HashMap<String, String>([
    ("==", SAN_COV_TRACE_MEM_CMP),
    ("startsWith", SAN_COV_TRACE_MEM_CMP),
    ("endsWith", SAN_COV_TRACE_MEM_CMP),
    ("indexOf", SAN_COV_TRACE_MEM_CMP),
    ("replace", SAN_COV_TRACE_MEM_CMP),
    ("contains", SAN_COV_TRACE_MEM_CMP)
])

private let CSTRING_FUNC_NAME2_SAN_COV_FUNC = HashMap<String, String>([
    ("equals", SAN_COV_TRACE_STR_CMP),
    ("startsWith", SAN_COV_TRACE_MEM_CMP),
    ("endsWith", SAN_COV_TRACE_STRN_CMP),
    ("compare", SAN_COV_TRACE_STR_CMP),
    ("equalsLower", SAN_COV_TRACE_STR_CASE_CMP)
])

private let HAS_N_PARAMETER_MEM_CMP_SET = HashSet<String>([
    SAN_COV_TRACE_MEM_CMP,
    SAN_COV_TRACE_STRN_CMP
])

private enum MemCmpType {
    | STRING_TYPE
    | CSTRING_TYPE
    | ARRAY_TYPE
    | ARRAYLIST_TYPE
}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:116-131.
private func GetStringSanConvFunc(cmpType: MemCmpType, funcName: String): Option<String> {
    if ((let MemCmpType.STRING_TYPE <- cmpType) && STRING_FUNC_NAME2_SAN_COV_FUNC.contains(funcName)) {
        return STRING_FUNC_NAME2_SAN_COV_FUNC.get(funcName)
    }
    if ((let MemCmpType.CSTRING_TYPE <- cmpType) && CSTRING_FUNC_NAME2_SAN_COV_FUNC.contains(funcName)) {
        return CSTRING_FUNC_NAME2_SAN_COV_FUNC.get(funcName)
    }
    if ((let MemCmpType.ARRAY_TYPE <- cmpType) && funcName == "==") {
        return Some(SAN_COV_TRACE_MEM_CMP)
    }
    if ((let MemCmpType.ARRAYLIST_TYPE <- cmpType) && funcName == "==") {
        return Some(SAN_COV_TRACE_MEM_CMP)
    }
    return None
}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:133-156.
private func GetTraceCompareType(kind: TypeKind): TypeKind {
    if (kind == TypeKind.TYPE_INT64 || kind == TypeKind.TYPE_UINT64) {
        return TypeKind.TYPE_UINT64
    }
    if (kind == TypeKind.TYPE_INT32 || kind == TypeKind.TYPE_UINT32) {
        return TypeKind.TYPE_UINT32
    }
    if (kind == TypeKind.TYPE_INT16 || kind == TypeKind.TYPE_UINT16) {
        return TypeKind.TYPE_UINT16
    }
    if (kind == TypeKind.TYPE_INT8 || kind == TypeKind.TYPE_UINT8) {
        return TypeKind.TYPE_UINT8
    }
    return TypeKind.TYPE_UNIT
}

// C++: CHIR/Transformation/SanitizerCoverage.cpp:158-183.
private func GetTraceCompareSyscallName(binaryOp: BinaryExpression): String {
    let compareMap = HashMap<TypeKind, String>([
        (TypeKind.TYPE_UINT8, SanCovTraceCmp1),
        (TypeKind.TYPE_UINT16, SanCovTraceCmp2),
        (TypeKind.TYPE_UINT32, SanCovTraceCmp4),
        (TypeKind.TYPE_UINT64, SanCovTraceCmp8)
    ])
    let compareConstMap = HashMap<TypeKind, String>([
        (TypeKind.TYPE_UINT8, SanCovTraceConstCmp1),
        (TypeKind.TYPE_UINT16, SanCovTraceConstCmp2),
        (TypeKind.TYPE_UINT32, SanCovTraceConstCmp4),
        (TypeKind.TYPE_UINT64, SanCovTraceConstCmp8)
    ])
    let lhsTy = binaryOp.GetLHSOperand().GetType().getOrThrow()
    let rhsTy = binaryOp.GetRHSOperand().GetType().getOrThrow()
    let curSize = GetTraceCompareType(lhsTy.GetTypeKind())
    let hasArgsConst = lhsTy.IsConstant() || rhsTy.IsConstant()
    return if (hasArgsConst) {
        compareConstMap.get(curSize).getOrThrow()
    } else {
        compareMap.get(curSize).getOrThrow()
    }
}

// C++: CHIR/Transformation/SanitizerCoverage.h:21-100 and SanitizerCoverage.cpp:185-188.
public class SanitizerCoverage {
    private let sanCovOption: SanitizerCoverageOptions
    private let pcArray: ArrayList<(String, DebugLocation)> = ArrayList<(String, DebugLocation)>()
    private let funcBag: HashMap<String, Function> = HashMap<String, Function>()
    private let globalVarBag: HashMap<String, GlobalVar> = HashMap<String, GlobalVar>()
    private var bbCounter: Int64 = 0
    private var packageName: String = ""
    private let builder: CHIRBuilder

    public init(option: GlobalOptions, builder: CHIRBuilder) {
        sanCovOption = option.sancovOption
        this.builder = builder
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:190-196.
    private func InitFuncBag(`package`: Package): Unit {
        for (v in `package`.GetGlobalFuncsWithoutBody()) {
            funcBag[v.GetIdentifierWithoutPrefix()] = v
        }
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:198-221.
    public func RunOnPackage(`package`: Package, diag: BasicDiagnosticEngine, isDebug: Bool): Bool {
        if (!CheckSancovOption(diag)) {
            return false
        }
        InitFuncBag(`package`)
        packageName = `package`.GetName()
        for (`func` in `package`.GetGlobalFuncsWithBody()) {
            if (`func`.IsGVInit() || `func`.TestAttr(Attribute.COMPILER_ADD) ||
                `func`.GetPackageName() != `package`.GetName()) {
                continue
            }
            let targetSuffix = SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION + MANGLE_FUNC_PARAM_TYPE_PREFIX +
                MANGLE_VOID_TY_SUFFIX
            if (`func`.GetIdentifier().endsWith(targetSuffix)) {
                continue
            }
            RunOnFunc(`func`, isDebug)
        }
        GenerateInitFunc(`package`.GetPackageInitFunc().getOrThrow(), isDebug)
        return true
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:223-265.
    private func RunOnFunc(`func`: Function, isDebug: Bool): Unit {
        if (sanCovOption.traceCmp) {
            let visitAction: VisitExprActionFunc = { expr: Expression =>
                if (expr.GetExprKind() == ExprKind.MULTIBRANCH) {
                    let mb = (expr as MultiBranch).getOrThrow()
                    InjectTraceForSwitch(mb, isDebug)
                }
                if (expr.IsBinaryExpr()) {
                    let binary = (expr as BinaryExpression).getOrThrow()
                    InjectTraceForCmp(binary, isDebug)
                }
                return VisitResult.CONTINUE
            }
            Visitor.Visit(`func`, visitAction)
        }
        if (sanCovOption.traceMemCmp) {
            let visitAction: VisitExprActionFunc = { expr: Expression =>
                InjectTraceMemCmp(expr, isDebug)
                return VisitResult.CONTINUE
            }
            Visitor.Visit(`func`, visitAction)
        }
        let isCoverageOpen = sanCovOption.inlineBoolFlag || sanCovOption.inline8bitCounters ||
            sanCovOption.tracePCGuard || sanCovOption.stackDepth
        if (!isCoverageOpen) {
            return
        }
        let isBasicBlockLevel = sanCovOption.coverageType == SanitizerCoverageType.SCK_BB ||
            sanCovOption.coverageType == SanitizerCoverageType.SCK_UNKNOW
        for (block in `func`.GetBody().getOrThrow().GetBlocks()) {
            if (isBasicBlockLevel || block.IsEntry()) {
                InsertCoverageAheadBlock(block, isDebug)
            }
        }
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:267-288.
    private func CheckSancovOption(diag: BasicDiagnosticEngine): Bool {
        let isSancov = sanCovOption.inline8bitCounters || sanCovOption.inlineBoolFlag ||
            sanCovOption.tracePCGuard
        let isSancovLevelVaild = sanCovOption.coverageType == SanitizerCoverageType.SCK_FUNCTION ||
            sanCovOption.coverageType == SanitizerCoverageType.SCK_BB
        if (!isSancov && sanCovOption.pcTable) {
            diag.Diagnose(BasicDiagKind.chir_sancov_illegal_usage_of_pc_table)
            return false
        }
        if (isSancov && sanCovOption.coverageType == SanitizerCoverageType.SCK_NONE) {
            diag.Diagnose(BasicDiagKind.chir_sancov_illegal_usage_of_level)
            return false
        }
        if (!isSancov && isSancovLevelVaild) {
            diag.Diagnose(BasicDiagKind.chir_sancov_illegal_usage_of_level)
            return false
        }
        return true
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:290-343.
    private func InjectTraceForCmp(binary: BinaryExpression, isDebug: Bool): Unit {
        let cmpToken = ArrayList<ExprKind>([
            ExprKind.LT, ExprKind.GT, ExprKind.LE, ExprKind.GE, ExprKind.NOTEQUAL, ExprKind.EQUAL
        ])
        if (!cmpToken.contains(binary.GetExprKind())) {
            return
        }

        var lhs = binary.GetLHSOperand()
        var rhs = binary.GetRHSOperand()
        let lhsTy = lhs.GetType().getOrThrow()
        let curSize = GetTraceCompareType(lhsTy.GetTypeKind())
        if (curSize == TypeKind.TYPE_UNIT) {
            return
        }

        let parent = binary.GetParentBlock().getOrThrow()
        if ((let Some(intTy) <- (lhsTy as IntType)) && intTy.IsSigned()) {
            let unsignedType = if (curSize == TypeKind.TYPE_UINT8) {
                builder.context.GetUInt8Ty()
            } else if (curSize == TypeKind.TYPE_UINT16) {
                builder.context.GetUInt16Ty()
            } else if (curSize == TypeKind.TYPE_UINT32) {
                builder.context.GetUInt32Ty()
            } else {
                builder.context.GetUInt64Ty()
            }
            let lhsCast = builder.CreateTypeCast(unsignedType, lhs, parent)
            let rhsCast = builder.CreateTypeCast(unsignedType, rhs, parent)
            lhsCast.SetDebugLocation(binary.GetDebugLocation())
            rhsCast.SetDebugLocation(binary.GetDebugLocation())
            lhs = lhsCast.GetResult().getOrThrow()
            rhs = rhsCast.GetResult().getOrThrow()
            lhsCast.MoveBefore(binary)
            rhsCast.MoveBefore(binary)
        }

        let callName = GetTraceCompareSyscallName(binary)
        let paramTypes = ArrayList<Type>([lhs.GetType().getOrThrow(), rhs.GetType().getOrThrow()])
        let funcTy = builder.context.GetFuncTy(paramTypes, builder.context.GetUnitTy(), isCFunc: true)
        let callee = GenerateForeignFunc(callName, binary.GetDebugLocation(), funcTy, packName: packageName)
        let syscall = CreateNonMemberApply(builder.context.GetUnitTy(), callee,
            ArrayList<Value>([lhs, rhs]), parent, builder, loc: binary.GetDebugLocation())
        syscall.MoveBefore(binary)

        if (isDebug) {
            println("[SanitizerCoverage] Add trace compares" + ToPosInfo(binary.GetDebugLocation()) + ".")
        }
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:345-399.
    private func InjectTraceForSwitch(mb: MultiBranch, isDebug: Bool): Unit {
        let conditionTy = mb.GetCondition().GetType().getOrThrow()
        if (!conditionTy.IsInteger() && !conditionTy.IsRune()) {
            return
        }
        let u64Ty = builder.context.GetUInt64Ty()
        let cPointTy = builder.context.GetCPointerTy(u64Ty)
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>([u64Ty, cPointTy]),
            builder.context.GetUnitTy(), isCFunc: true)
        let callee = GenerateForeignFunc(SanCovTraceSwitchName, mb.GetDebugLocation(), funcTy,
            packName: packageName)
        let parent = mb.GetParentBlock().getOrThrow()
        let caseValList = CreateArrayForSwitchCaseList(mb)
        caseValList.MoveBefore(mb)
        let rawDataAcquire = CreateRawDataAcquire(caseValList, u64Ty)
        rawDataAcquire.MoveBefore(mb)
        var switchVal = mb.GetCondition()
        if (switchVal.GetType().getOrThrow().GetTypeKind() != TypeKind.TYPE_UINT64) {
            let typeCast = builder.CreateTypeCast(u64Ty, switchVal, parent)
            typeCast.SetDebugLocation(mb.GetDebugLocation())
            switchVal = typeCast.GetResult().getOrThrow()
            typeCast.MoveBefore(mb)
        }
        let syscall = CreateNonMemberApply(builder.context.GetUnitTy(), callee,
            ArrayList<Value>([switchVal, rawDataAcquire.GetResult().getOrThrow()]), parent, builder,
            loc: mb.GetDebugLocation())
        syscall.MoveBefore(mb)
        if (isDebug) {
            println("[SanitizerCoverage] Add trace switch" + ToPosInfo(mb.GetDebugLocation()) + ".")
        }
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:401-460.
    private func GenerateCStringMemCmp(fuzzName: String, oper1: Value, oper2: Value,
        apply: Apply): ArrayList<Value> {
        let parent = apply.GetParentBlock().getOrThrow()
        let loc = apply.GetDebugLocation()
        let res = ArrayList<Value>()
        let cPointerType = builder.context.GetCPointerTy(builder.context.GetUInt8Ty())
        let callContext1 = IntrisicCallContext(kind: IntrinsicKind.CSTRING_CONVERT_CSTR_TO_PTR,
            args: ArrayList<Value>([oper1]))
        var cPointer = builder.CreateIntrinsic(cPointerType, callContext1, parent)
        cPointer.SetDebugLocation(loc)
        cPointer.MoveBefore(apply)
        let callContext2 = IntrisicCallContext(kind: IntrinsicKind.CSTRING_CONVERT_CSTR_TO_PTR,
            args: ArrayList<Value>([oper2]))
        var cPointer2 = builder.CreateIntrinsic(cPointerType, callContext2, parent)
        cPointer2.SetDebugLocation(loc)
        cPointer2.MoveBefore(apply)
        if (fuzzName == SAN_COV_TRACE_MEM_CMP) {
            let typeTarget = builder.context.GetCPointerTy(builder.context.GetVoidTy())
            let callContext3 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
                args: ArrayList<Value>([cPointer.GetResult().getOrThrow()]))
            cPointer = builder.CreateIntrinsic(typeTarget, callContext3, parent)
            cPointer.SetDebugLocation(loc)
            cPointer.MoveBefore(apply)
            let callContext4 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
                args: ArrayList<Value>([cPointer2.GetResult().getOrThrow()]))
            cPointer2 = builder.CreateIntrinsic(typeTarget, callContext4, parent)
            cPointer2.SetDebugLocation(loc)
            cPointer2.MoveBefore(apply)
        }
        res.add(cPointer.GetResult().getOrThrow())
        res.add(cPointer2.GetResult().getOrThrow())
        if (HAS_N_PARAMETER_MEM_CMP_SET.contains(fuzzName)) {
            let getSize = GetImportedFunc(FUNC_MANGLE_NAME_CSTRING_SIZE)
            let sizeN = CreateMemberApply(builder.context.GetInt64Ty(), getSize,
                oper1.GetType().getOrThrow(), ArrayList<Value>([oper1]), parent, builder, loc: loc)
            sizeN.MoveBefore(apply)
            let sizeNCasted = builder.CreateTypeCast(builder.context.GetUInt32Ty(),
                sizeN.GetResult().getOrThrow(), parent)
            sizeNCasted.SetDebugLocation(loc)
            sizeNCasted.MoveBefore(apply)
            res.add(sizeNCasted.GetResult().getOrThrow())
        }
        return res
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:462-501.
    private func CreateOneCPointFromList(array: Value, apply: Apply, elementType: Type,
        startType: Type): Expression {
        let parent = apply.GetParentBlock().getOrThrow()
        let loc = apply.GetDebugLocation()
        let rawArrayType = builder.context.GetRefTy(builder.context.GetRawArrayTy(elementType))
        let rawArray = builder.CreateField(rawArrayType, array, ArrayList<UInt64>([0u64]), parent)
        rawArray.SetDebugLocation(loc)
        rawArray.MoveBefore(apply)
        let start = builder.CreateField(startType, array, ArrayList<UInt64>([1u64]), parent)
        start.SetDebugLocation(loc)
        start.MoveBefore(apply)
        var startRes = start.GetResult().getOrThrow()
        if (startRes.GetType().getOrThrow() != builder.context.GetInt64Ty()) {
            let castToInt64 = builder.CreateTypeCast(builder.context.GetInt64Ty(), startRes, parent)
            castToInt64.SetDebugLocation(loc)
            castToInt64.MoveBefore(apply)
            startRes = castToInt64.GetResult().getOrThrow()
        }
        let origPointerType = builder.context.GetCPointerTy(elementType)
        let callContext1 = IntrisicCallContext(kind: IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA,
            args: ArrayList<Value>([rawArray.GetResult().getOrThrow()]),
            instTypeArgs: ArrayList<Type>([elementType]))
        let cPointerAcquire = builder.CreateIntrinsic(origPointerType, callContext1, parent)
        cPointerAcquire.SetDebugLocation(loc)
        cPointerAcquire.MoveBefore(apply)
        let callContext2 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_ADD,
            args: ArrayList<Value>([cPointerAcquire.GetResult().getOrThrow(), startRes]),
            instTypeArgs: ArrayList<Type>([elementType]))
        let pointAdd = builder.CreateIntrinsic(origPointerType, callContext2, parent)
        pointAdd.SetDebugLocation(loc)
        pointAdd.MoveBefore(apply)
        return pointAdd
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:503-556.
    private func GenerateStringMemCmp(fuzzName: String, oper1: Value, oper2: Value,
        apply: Apply): ArrayList<Value> {
        let res = ArrayList<Value>()
        let parent = apply.GetParentBlock().getOrThrow()
        let loc = apply.GetDebugLocation()
        var cPoint1 = CreateOneCPointFromList(oper1, apply, builder.context.GetUInt8Ty(),
            builder.context.GetUInt32Ty())
        var cPoint2 = CreateOneCPointFromList(oper2, apply, builder.context.GetUInt8Ty(),
            builder.context.GetUInt32Ty())
        if (fuzzName == SAN_COV_TRACE_MEM_CMP) {
            let typeTarget = builder.context.GetCPointerTy(builder.context.GetVoidTy())
            let callContext1 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
                args: ArrayList<Value>([cPoint1.GetResult().getOrThrow()]))
            cPoint1 = builder.CreateIntrinsic(typeTarget, callContext1, parent)
            cPoint1.SetDebugLocation(loc)
            cPoint1.MoveBefore(apply)
            let callContext2 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
                args: ArrayList<Value>([cPoint2.GetResult().getOrThrow()]))
            cPoint2 = builder.CreateIntrinsic(typeTarget, callContext2, parent)
            cPoint2.SetDebugLocation(loc)
            cPoint2.MoveBefore(apply)
        }
        res.add(cPoint1.GetResult().getOrThrow())
        res.add(cPoint2.GetResult().getOrThrow())
        if (HAS_N_PARAMETER_MEM_CMP_SET.contains(fuzzName)) {
            let sizeN = builder.CreateField(builder.context.GetUInt32Ty(), oper1,
                ArrayList<UInt64>([2u64]), parent)
            sizeN.SetDebugLocation(loc)
            sizeN.MoveBefore(apply)
            res.add(sizeN.GetResult().getOrThrow())
        }
        return res
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:558-629.
    private func GenerateArrayCmp(fuzzName: String, oper1: Value, oper2: Value,
        apply: Apply): ArrayList<Value> {
        let res = ArrayList<Value>()
        let parent = apply.GetParentBlock().getOrThrow()
        let loc = apply.GetDebugLocation()
        CJC_ASSERT(oper1.GetType().getOrThrow().GetTypeKind() == TypeKind.TYPE_STRUCT)
        let arrayType = (oper1.GetType().getOrThrow() as StructType).getOrThrow()
        CJC_ASSERT(arrayType.GetGenericArgs().size == 1)
        let elementType = arrayType.GetGenericArgs()[0]
        let cPointer1 = CreateOneCPointFromList(oper1, apply, elementType, builder.context.GetInt64Ty())
        let cPointer2 = CreateOneCPointFromList(oper2, apply, elementType, builder.context.GetInt64Ty())
        var typeTarget: Type = builder.context.GetCPointerTy(builder.context.GetUInt8Ty())
        if (fuzzName == SAN_COV_TRACE_MEM_CMP) {
            typeTarget = builder.context.GetCPointerTy(builder.context.GetVoidTy())
        }
        let callContext1 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
            args: ArrayList<Value>([cPointer1.GetResult().getOrThrow()]))
        let typeCast1 = builder.CreateIntrinsic(typeTarget, callContext1, parent)
        typeCast1.SetDebugLocation(loc)
        typeCast1.MoveBefore(apply)
        let callContext2 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1,
            args: ArrayList<Value>([cPointer2.GetResult().getOrThrow()]))
        let typeCast2 = builder.CreateIntrinsic(typeTarget, callContext2, parent)
        typeCast2.SetDebugLocation(loc)
        typeCast2.MoveBefore(apply)
        res.add(typeCast1.GetResult().getOrThrow())
        res.add(typeCast2.GetResult().getOrThrow())
        if (HAS_N_PARAMETER_MEM_CMP_SET.contains(fuzzName)) {
            let sizeN = builder.CreateField(builder.context.GetInt64Ty(), oper1,
                ArrayList<UInt64>([2u64]), parent)
            sizeN.SetDebugLocation(loc)
            sizeN.MoveBefore(apply)
            let elementSizeContext = IntrisicCallContext(kind: IntrinsicKind.SIZE_OF,
                args: ArrayList<Value>(), instTypeArgs: ArrayList<Type>([elementType]))
            let elementSize = builder.CreateIntrinsic(builder.context.GetInt64Ty(), elementSizeContext, parent)
            elementSize.SetDebugLocation(loc)
            elementSize.MoveBefore(apply)
            let calSize = builder.CreateBinaryExpression(ExprKind.MUL, builder.context.GetInt64Ty(),
                sizeN.GetResult().getOrThrow(), elementSize.GetResult().getOrThrow(), parent,
                overflowStrategy: OverflowStrategy.WRAPPING)
            calSize.SetDebugLocation(loc)
            calSize.MoveBefore(apply)
            let sizeNCasted = builder.CreateTypeCast(builder.context.GetUInt32Ty(),
                calSize.GetResult().getOrThrow(), parent)
            sizeNCasted.SetDebugLocation(loc)
            sizeNCasted.MoveBefore(apply)
            res.add(sizeNCasted.GetResult().getOrThrow())
        }
        return res
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:631-669.
    private func CastArrayListToArray(oper1: Value, oper2: Value, apply: Apply): (Value, Value) {
        let loc = apply.GetDebugLocation()
        let refType = (oper1.GetType().getOrThrow() as RefType).getOrThrow()
        let rawArrayType = (refType.GetBaseType() as ClassType).getOrThrow()
        CJC_ASSERT(rawArrayType.GetGenericArgs().size == 1)
        let elementType = rawArrayType.GetGenericArgs()[0]
        let arrayGeneric = builder.GetStructType("std.core", "Array").getOrThrow()
        CJC_ASSERT(arrayGeneric.GetGenericArgs().size == 1)
        let genericType = (arrayGeneric.GetGenericArgs()[0] as GenericType).getOrThrow()
        let table = HashMap<GenericType, Type>([(genericType, elementType)])
        let arrayType = ReplaceRawGenericArgType(arrayGeneric, table, builder)
        let arrayRefType = builder.context.GetRefTy(arrayType)
        let parent = apply.GetParentBlock().getOrThrow()
        let arrayRef1 = builder.CreateGetElementRef(arrayRefType, oper1, ArrayList<UInt64>([0u64]), parent)
        arrayRef1.SetDebugLocation(loc)
        arrayRef1.MoveBefore(apply)
        let arrayRef2 = builder.CreateGetElementRef(arrayRefType, oper2, ArrayList<UInt64>([0u64]), parent)
        arrayRef2.SetDebugLocation(loc)
        arrayRef2.MoveBefore(apply)
        let array1 = builder.CreateLoad(arrayType, arrayRef1.GetResult().getOrThrow(), parent)
        array1.SetDebugLocation(loc)
        array1.MoveBefore(apply)
        let array2 = builder.CreateLoad(arrayType, arrayRef2.GetResult().getOrThrow(), parent)
        array2.SetDebugLocation(loc)
        array2.MoveBefore(apply)
        return (array1.GetResult().getOrThrow(), array2.GetResult().getOrThrow())
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:671-682.
    private func CreateMemCmpFunc(intrinsicName: String, paramsType: Type, params: ArrayList<Value>,
        loc: DebugLocation, parent: Block): Expression {
        let paramType = ArrayList<Type>([paramsType, paramsType])
        if (HAS_N_PARAMETER_MEM_CMP_SET.contains(intrinsicName)) {
            paramType.add(builder.context.GetUInt32Ty())
        }
        let funcTy = builder.context.GetFuncTy(paramType, builder.context.GetUnitTy(), isCFunc: true)
        let memCmpFunc = GenerateForeignFunc(intrinsicName, loc, funcTy, packName: packageName)
        return CreateNonMemberApply(builder.context.GetUnitTy(), memCmpFunc, params, parent, builder, loc: loc)
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:684-735.
    private func GetMemFuncSymbols(oper1: Value, oper2: Value, apply: Apply): (String, ArrayList<Value>) {
        var intrinsicName: Option<String> = Some("")
        var params = ArrayList<Value>()
        let defaultValue = ("", ArrayList<Value>())
        let applyCallName = apply.GetCallee().GetSrcCodeIdentifier()
        if (oper1.GetType().getOrThrow().GetTypeKind() == TypeKind.TYPE_CSTRING) {
            intrinsicName = GetStringSanConvFunc(MemCmpType.CSTRING_TYPE, applyCallName)
            if (let None <- intrinsicName) {
                return defaultValue
            }
            params = GenerateCStringMemCmp(intrinsicName.getOrThrow(), oper1, oper2, apply)
        } else if (oper1.GetType().getOrThrow().GetTypeKind() == TypeKind.TYPE_STRUCT) {
            let structType = (oper1.GetType().getOrThrow() as StructType).getOrThrow()
            if (structType.GetStructDef().GetPackageName() != "std.core") {
                return defaultValue
            } else if (structType.GetStructDef().GetSrcCodeIdentifier() == "String") {
                intrinsicName = GetStringSanConvFunc(MemCmpType.STRING_TYPE, applyCallName)
                if (let None <- intrinsicName) {
                    return defaultValue
                }
                if (!oper2.GetType().getOrThrow().IsString()) {
                    return defaultValue
                }
                params = GenerateStringMemCmp(intrinsicName.getOrThrow(), oper1, oper2, apply)
            } else if (structType.GetStructDef().GetSrcCodeIdentifier() == "Array") {
                intrinsicName = GetStringSanConvFunc(MemCmpType.ARRAY_TYPE, applyCallName)
                if (let None <- intrinsicName) {
                    return defaultValue
                }
                params = GenerateArrayCmp(intrinsicName.getOrThrow(), oper1, oper2, apply)
            }
        } else if (oper1.GetType().getOrThrow().GetTypeKind() == TypeKind.TYPE_REFTYPE) {
            let refType = (oper1.GetType().getOrThrow() as RefType).getOrThrow()
            if (refType.GetBaseType().GetTypeKind() != TypeKind.TYPE_CLASS) {
                return defaultValue
            }
            let classType = (refType.GetBaseType() as ClassType).getOrThrow()
            if (classType.GetClassDef().GetPackageName() != "std.collection" ||
                classType.GetClassDef().GetSrcCodeIdentifier() != "ArrayList") {
                return defaultValue
            }
            intrinsicName = GetStringSanConvFunc(MemCmpType.ARRAYLIST_TYPE, applyCallName)
            if (let None <- intrinsicName) {
                return defaultValue
            }
            let (cast0, cast1) = CastArrayListToArray(oper1, oper2, apply)
            params = GenerateArrayCmp(intrinsicName.getOrThrow(), cast0, cast1, apply)
        }
        return (intrinsicName.getOrThrow(), params)
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:737-766.
    private func InjectTraceMemCmp(expr: Expression, isDebug: Bool): Unit {
        if (expr.GetExprKind() != ExprKind.APPLY) {
            return
        }
        let applyNode = (expr as Apply).getOrThrow()
        if (applyNode.GetOperands().size < 3) {
            return
        }
        let oper1 = applyNode.GetOperand(1)
        let oper2 = applyNode.GetOperand(2)
        let (intrinsicName, params) = GetMemFuncSymbols(oper1, oper2, applyNode)
        if (intrinsicName == "" || params.isEmpty()) {
            return
        }
        let parent = expr.GetParentBlock().getOrThrow()
        let syscall = if (intrinsicName == SAN_COV_TRACE_MEM_CMP) {
            let voidPointerType = builder.context.GetCPointerTy(builder.context.GetVoidTy())
            CreateMemCmpFunc(intrinsicName, voidPointerType, params, expr.GetDebugLocation(), parent)
        } else {
            let charPointerType = builder.context.GetCPointerTy(builder.context.GetUInt8Ty())
            CreateMemCmpFunc(intrinsicName, charPointerType, params, expr.GetDebugLocation(), parent)
        }
        syscall.MoveBefore(expr)
        if (isDebug) {
            println("[SanitizerCoverage] Add trace Memory Compare" + ToPosInfo(expr.GetDebugLocation()) + ".")
        }
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:768-792.
    private func InsertCoverageAheadBlock(block: Block, isDebug: Bool): Unit {
        if (sanCovOption.pcTable) {
            let topLevelFunc = block.GetTopLevelFunc().getOrThrow()
            var blockLocation = topLevelFunc.GetDebugLocation()
            for (expr in block.GetExpressions()) {
                if (!expr.GetDebugLocation().IsInvalidPos()) {
                    blockLocation = expr.GetDebugLocation()
                    break
                }
            }
            pcArray.add((topLevelFunc.GetSrcCodeIdentifier(), blockLocation))
        }
        CJC_ASSERT(block.GetExpressions().size > 0)
        let callList = GenerateCoverageCallByOption(INVALID_LOCATION, isDebug, block)
        if (sanCovOption.stackDepth && block.IsEntry()) {
            let stackDepth = GenerateStackDepthExpr(INVALID_LOCATION, isDebug, block)
            callList.add(all: stackDepth)
        }
        let firstExpr = block.GetExpressions()[0]
        for (call in callList) {
            call.MoveBefore(firstExpr)
        }
        bbCounter++
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:848-867.
    private func GenerateCoverageCallByOption(loc: DebugLocation, isDebug: Bool,
        parent: Block): ArrayList<Expression> {
        let callList = ArrayList<Expression>()
        if (sanCovOption.tracePCGuard) {
            let guardList = GeneratePCGuardExpr(loc, isDebug, parent)
            callList.add(all: guardList)
        }
        if (sanCovOption.inline8bitCounters) {
            let inline8bitList = GenerateInline8bitExpr(loc, isDebug, parent)
            callList.add(all: inline8bitList)
        }
        if (sanCovOption.inlineBoolFlag) {
            let inlineBoolFlag = GenerateInlineBoolExpr(loc, isDebug, parent)
            callList.add(all: inlineBoolFlag)
        }
        return callList
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:869-904.
    private func GeneratePCGuardExpr(loc: DebugLocation, isDebug: Bool,
        parent: Block): ArrayList<Expression> {
        let cPointTy = builder.context.GetCPointerTy(builder.context.GetUInt32Ty())
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>([cPointTy]),
            builder.context.GetUnitTy(), isCFunc: true)
        let pcGuardFunc = GenerateForeignFunc(SAN_COV_PC_GUARD, loc, funcTy, packName: packageName)
        let globalVarType = builder.context.GetCPointerTy(builder.context.GetUInt32Ty())
        let mangleName = SAN_COV_CTOR2_GLOBAL_VAR_NAME.get(SanCovUInt32ArrayInitName).getOrThrow()
        let charArrayTest = GenerateGlobalVar(mangleName, loc, globalVarType)
        let offset = builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(UInt64(bbCounter)), parent)
        offset.SetDebugLocation(loc)
        let arrayTestLoad = builder.CreateLoad(globalVarType, charArrayTest, parent)
        arrayTestLoad.SetDebugLocation(loc)
        let callContext = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_ADD,
            args: ArrayList<Value>([arrayTestLoad.GetResult().getOrThrow(), offset.GetResult().getOrThrow()]),
            instTypeArgs: ArrayList<Type>([builder.context.GetUInt32Ty()]))
        let addPoint = builder.CreateIntrinsic(cPointTy, callContext, parent)
        addPoint.SetDebugLocation(loc)
        let syscall = CreateNonMemberApply(builder.context.GetUnitTy(), pcGuardFunc,
            ArrayList<Value>([addPoint.GetResult().getOrThrow()]), parent, builder, loc: loc)
        if (isDebug) {
            println("[SanitizerCoverage] Add trace pc guard" + ToPosInfo(loc) + ".")
        }
        return ArrayList<Expression>([arrayTestLoad, offset, addPoint, syscall])
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:906-948.
    private func GenerateInline8bitExpr(loc: DebugLocation, isDebug: Bool,
        parent: Block): ArrayList<Expression> {
        let globalVarType = builder.context.GetCPointerTy(builder.context.GetUInt8Ty())
        let mangleName = SAN_COV_CTOR2_GLOBAL_VAR_NAME.get(SanCovCharArrayInitName).getOrThrow()
        let charArrayTest = GenerateGlobalVar(mangleName, loc, globalVarType)
        let loadGlobal = builder.CreateLoad(globalVarType, charArrayTest, parent)
        loadGlobal.SetDebugLocation(loc)
        let offset = builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(UInt64(bbCounter)), parent)
        offset.SetDebugLocation(loc)
        let callContext1 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_READ,
            args: ArrayList<Value>([loadGlobal.GetResult().getOrThrow(), offset.GetResult().getOrThrow()]),
            instTypeArgs: ArrayList<Type>([builder.context.GetUInt8Ty()]))
        let readPoint = builder.CreateIntrinsic(builder.context.GetUInt8Ty(), callContext1, parent)
        readPoint.SetDebugLocation(loc)
        let one = builder.CreateConstant(builder.context.GetUInt8Ty(), IntLiteral(1u64), parent)
        one.SetDebugLocation(loc)
        let addRes = builder.CreateBinaryExpression(ExprKind.ADD, builder.context.GetUInt8Ty(),
            readPoint.GetResult().getOrThrow(), one.GetResult().getOrThrow(), parent,
            overflowStrategy: OverflowStrategy.WRAPPING)
        addRes.SetDebugLocation(loc)
        let callContext2 = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_WRITE,
            args: ArrayList<Value>([loadGlobal.GetResult().getOrThrow(), offset.GetResult().getOrThrow(),
                addRes.GetResult().getOrThrow()]), instTypeArgs: ArrayList<Type>([builder.context.GetUInt8Ty()]))
        let writePoint = builder.CreateIntrinsic(builder.context.GetUnitTy(), callContext2, parent)
        writePoint.SetDebugLocation(loc)
        if (isDebug) {
            println("[SanitizerCoverage] Add trace inline 8 bit" + ToPosInfo(loc) + ".")
        }
        return ArrayList<Expression>([loadGlobal, offset, readPoint, one, addRes, writePoint])
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:950-980.
    private func GenerateInlineBoolExpr(loc: DebugLocation, isDebug: Bool,
        parent: Block): ArrayList<Expression> {
        let globalVarType = builder.context.GetCPointerTy(builder.context.GetBoolTy())
        let mangleName = SAN_COV_CTOR2_GLOBAL_VAR_NAME.get(SanCovBoolFlagInitName).getOrThrow()
        let charArrayTest = GenerateGlobalVar(mangleName, loc, globalVarType)
        let loadGlobal = builder.CreateLoad(globalVarType, charArrayTest, parent)
        loadGlobal.SetDebugLocation(loc)
        let offset = builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(UInt64(bbCounter)), parent)
        offset.SetDebugLocation(loc)
        let boolTrue = builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(true), parent)
        boolTrue.SetDebugLocation(loc)
        let callContext = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_WRITE,
            args: ArrayList<Value>([loadGlobal.GetResult().getOrThrow(), offset.GetResult().getOrThrow(),
                boolTrue.GetResult().getOrThrow()]), instTypeArgs: ArrayList<Type>([builder.context.GetBoolTy()]))
        let writePoint = builder.CreateIntrinsic(builder.context.GetUnitTy(), callContext, parent)
        writePoint.SetDebugLocation(loc)
        if (isDebug) {
            println("[SanitizerCoverage] Add trace inline bool" + ToPosInfo(loc) + ".")
        }
        return ArrayList<Expression>([loadGlobal, offset, boolTrue, writePoint])
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:982-996.
    private func GenerateStackDepthExpr(loc: DebugLocation, isDebug: Bool,
        parent: Block): ArrayList<Expression> {
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetUnitTy(), isCFunc: true)
        let callee = GenerateForeignFunc(SanCovUpdateStackDepth, loc, funcTy, packName: packageName)
        let syscall = CreateNonMemberApply(builder.context.GetUnitTy(), callee,
            ArrayList<Value>(), parent, builder, loc: loc)
        if (isDebug) {
            println("[SanitizerCoverage] Add trace stage depth" + ToPosInfo(loc) + ".")
        }
        return ArrayList<Expression>([syscall])
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:998-1014.
    private func GenerateGlobalVar(globalVarName: String, loc: DebugLocation, globalType: Type): GlobalVar {
        if (let Some(value) <- globalVarBag.get(globalVarName)) {
            return value
        }
        let globalVar = builder.CreateGlobalVar(builder.context.GetRefTy(globalType), globalVarName,
            srcCodeIdentifier: globalVarName, packageName: packageName)
        globalVar.SetDebugLocation(loc)
        globalVar.EnableAttr(Attribute.READONLY)
        globalVar.EnableAttr(Attribute.COMPILER_ADD)
        globalVarBag[globalVarName] = globalVar
        return globalVar
    }

    private func GetGlobalVar(globalVarName: String): Option<GlobalVar> {
        return globalVarBag.get(globalVarName)
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:794-834.
    private func CreateArrayForSwitchCaseList(multiBranch: MultiBranch): RawArrayAllocate {
        let cases = multiBranch.GetCaseVals()
        let caseVals = ArrayList<Value>()
        let loc = multiBranch.GetDebugLocation()
        let parent = multiBranch.GetParentBlock().getOrThrow()
        let caseSize = builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(UInt64(cases.size)), parent)
        caseSize.SetDebugLocation(loc)
        caseVals.add(caseSize.GetResult().getOrThrow())
        caseSize.MoveBefore(multiBranch)

        let elemBitSize = builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(64u64), parent)
        elemBitSize.SetDebugLocation(loc)
        caseVals.add(elemBitSize.GetResult().getOrThrow())
        elemBitSize.MoveBefore(multiBranch)

        for (caseVal in cases) {
            let valExpr = builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(caseVal), parent)
            valExpr.SetDebugLocation(loc)
            caseVals.add(valExpr.GetResult().getOrThrow())
            valExpr.MoveBefore(multiBranch)
        }

        let listSize = builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(UInt64(cases.size + 2)), parent)
        listSize.SetDebugLocation(loc)
        listSize.MoveBefore(multiBranch)
        let arrayTy = builder.context.GetRefTy(builder.context.GetRawArrayTy(builder.context.GetUInt64Ty()))
        return builder.CreateRawArrayAllocate(arrayTy, builder.context.GetUInt64Ty(),
            listSize.GetResult().getOrThrow(), parent)
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:836-846.
    private func CreateRawDataAcquire(dataList: Expression, elementType: Type): Intrinsic {
        let cPointerTy = builder.context.GetCPointerTy(elementType)
        let callContext = IntrisicCallContext(kind: IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA,
            args: ArrayList<Value>([dataList.GetResult().getOrThrow()]),
            instTypeArgs: ArrayList<Type>([elementType]))
        let result = builder.CreateIntrinsic(cPointerTy, callContext, dataList.GetParentBlock().getOrThrow())
        result.SetDebugLocation(dataList.GetDebugLocation())
        return result
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1029-1034.
    private func GetImportedFunc(mangledName: String): Function {
        CJC_ASSERT(funcBag.contains(mangledName))
        return funcBag.get(mangledName).getOrThrow()
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1016-1027.
    private func GenerateForeignFunc(globalFuncName: String, loc: DebugLocation, funcType: FuncType,
        packName!: String = ""): Function {
        if (let Some(value) <- funcBag.get(globalFuncName)) {
            return value
        }
        let function = builder.CreateFunction(funcType, globalFuncName, srcCodeIdentifier: globalFuncName,
            packageName: packName)
        function.EnableAttr(Attribute.IMPORTED)
        function.EnableAttr(Attribute.FOREIGN)
        funcBag[globalFuncName] = function
        return function
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1036-1049.
    private func CreateInitFunc(name: String, funcType: FuncType, loc: DebugLocation): Function {
        let `func` = builder.CreateFunction(funcType, name, srcCodeIdentifier: name, packageName: packageName)
        `func`.SetDebugLocation(loc)
        let body = builder.CreateBlockGroup(`func`)
        `func`.InitBody(body)
        `func`.EnableAttr(Attribute.NO_INLINE)
        `func`.EnableAttr(Attribute.NO_REFLECT_INFO)
        `func`.EnableAttr(Attribute.COMPILER_ADD)
        `func`.SetFuncKind(FuncKind.GLOBALVAR_INIT)
        `func`.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        return `func`
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1051-1079.
    private func CreateArrayInitFunc(initItemName: String, initType: Type): Function {
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetVoidTy())
        let initName = MANGLE_CANGJIE_PREFIX + MANGLE_GLOBAL_VARIABLE_INIT_PREFIX + MangleName("default") +
            MangleName("0." + SAN_COV_CTOR2_GLOBAL_VAR_NAME.get(initItemName).getOrThrow()) +
            MANGLE_FUNC_PARAM_TYPE_PREFIX + MANGLE_VOID_TY_SUFFIX
        let `func` = CreateInitFunc(initName, funcTy, INVALID_LOCATION)
        let body = `func`.GetBody().getOrThrow()
        let block0 = builder.CreateBlock(body)
        body.SetEntryBlock(block0)
        let counterVal = builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(UInt64(bbCounter)), block0)
        counterVal.SetDebugLocation(INVALID_LOCATION)
        block0.AppendExpression(counterVal)
        let cPointTy = builder.context.GetCPointerTy(initType)
        let guardCtorTy = builder.context.GetFuncTy(ArrayList<Type>([builder.context.GetUInt64Ty()]),
            cPointTy, isCFunc: true)
        let guardCtorFunc = GenerateForeignFunc(initItemName, INVALID_LOCATION, guardCtorTy, packName: packageName)
        let apply = CreateNonMemberApply(cPointTy, guardCtorFunc,
            ArrayList<Value>([counterVal.GetResult().getOrThrow()]), block0, builder, loc: INVALID_LOCATION)
        block0.AppendExpression(apply)
        let globalVal = GetGlobalVar(SAN_COV_CTOR2_GLOBAL_VAR_NAME.get(initItemName).getOrThrow()).getOrThrow()
        let store = builder.CreateStore(apply.GetResult().getOrThrow(), globalVal, block0)
        store.SetDebugLocation(INVALID_LOCATION)
        block0.AppendExpression(store)
        globalVal.SetInitFunc(`func`)
        let exit = builder.CreateExit(None, block0)
        exit.SetDebugLocation(INVALID_LOCATION)
        return `func`
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1081-1149.
    private func CreatePCTableInitFunc(): Function {
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetVoidTy())
        let `func` = CreateInitFunc(MANGLE_CANGJIE_PREFIX + MANGLE_GLOBAL_VARIABLE_INIT_PREFIX +
            MangleName("default") + MangleName("0.pc_table") + MANGLE_FUNC_PARAM_TYPE_PREFIX +
            MANGLE_VOID_TY_SUFFIX, funcTy, INVALID_LOCATION)
        let body = `func`.GetBody().getOrThrow()
        let block0 = builder.CreateBlock(body)
        body.SetEntryBlock(block0)
        let mallocStringFunc = GetImportedFunc(FUNC_MANGLE_NAME_MALLOC_CSTRING)
        let funcSize = builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(Int64(pcArray.size)), block0)
        funcSize.SetDebugLocation(INVALID_LOCATION)
        block0.AppendExpression(funcSize)
        let stringTy = builder.context.GetStringTy().getOrThrow()
        let packExpr = builder.CreateConstant(stringTy, StringLiteral(packageName), block0)
        packExpr.SetDebugLocation(INVALID_LOCATION)
        block0.AppendExpression(packExpr)
        let libc = builder.GetStructType("std.core", "LibC").getOrThrow()
        let libcRef = builder.context.GetRefTy(libc)
        let packCString = CreateMemberApply(builder.context.GetCStringTy(), mallocStringFunc, libcRef,
            ArrayList<Value>([packExpr.GetResult().getOrThrow()]), block0, builder, loc: INVALID_LOCATION)
        block0.AppendExpression(packCString)
        let funcNameArray = ArrayList<Value>()
        let fileNameArray = ArrayList<Value>()
        let lineNumberArray = ArrayList<Value>()
        for ((pcName, pcLocation) in pcArray) {
            let funcName = builder.CreateConstant(stringTy, StringLiteral(pcName), block0)
            funcName.SetDebugLocation(INVALID_LOCATION)
            block0.AppendExpression(funcName)
            let cString = CreateMemberApply(builder.context.GetCStringTy(), mallocStringFunc, libcRef,
                ArrayList<Value>([funcName.GetResult().getOrThrow()]), block0, builder, loc: INVALID_LOCATION)
            block0.AppendExpression(cString)
            funcNameArray.add(cString.GetResult().getOrThrow())
            let fileName = builder.CreateConstant(stringTy,
                StringLiteral(builder.context.GetSourceFileName(pcLocation.GetFileID())), block0)
            fileName.SetDebugLocation(INVALID_LOCATION)
            block0.AppendExpression(fileName)
            let fileNameCString = CreateMemberApply(builder.context.GetCStringTy(), mallocStringFunc, libcRef,
                ArrayList<Value>([fileName.GetResult().getOrThrow()]), block0, builder, loc: INVALID_LOCATION)
            block0.AppendExpression(fileNameCString)
            fileNameArray.add(fileNameCString.GetResult().getOrThrow())
            let lineId = builder.CreateConstant(builder.context.GetUInt64Ty(),
                IntLiteral(UInt64(pcLocation.GetBeginPos().line)), block0)
            lineId.SetDebugLocation(INVALID_LOCATION)
            block0.AppendExpression(lineId)
            lineNumberArray.add(lineId.GetResult().getOrThrow())
        }
        let rawDataAcquireString = CreateRawDataAcquire(builder.context.GetCStringTy(), funcNameArray,
            funcSize.GetResult().getOrThrow(), block0)
        let rawDataAcquireFileName = CreateRawDataAcquire(builder.context.GetCStringTy(), fileNameArray,
            funcSize.GetResult().getOrThrow(), block0)
        let rawDataAcquireLine = CreateRawDataAcquire(builder.context.GetUInt64Ty(), lineNumberArray,
            funcSize.GetResult().getOrThrow(), block0)
        let paramTypeList = ArrayList<Type>([builder.context.GetCStringTy(), builder.context.GetUInt64Ty(),
            rawDataAcquireString.GetResult().getOrThrow().GetType().getOrThrow(),
            rawDataAcquireFileName.GetResult().getOrThrow().GetType().getOrThrow(),
            rawDataAcquireLine.GetResult().getOrThrow().GetType().getOrThrow()])
        let pcInitType = builder.context.GetFuncTy(paramTypeList, builder.context.GetUnitTy(), isCFunc: true)
        let pcInitFunc = GenerateForeignFunc(SanCovCreatePCTable, INVALID_LOCATION, pcInitType,
            packName: packageName)
        let typecast = builder.CreateTypeCast(builder.context.GetUInt64Ty(), funcSize.GetResult().getOrThrow(), block0)
        block0.AppendExpression(typecast)
        let pcInitApply = CreateNonMemberApply(builder.context.GetUnitTy(), pcInitFunc,
            ArrayList<Value>([packCString.GetResult().getOrThrow(), typecast.GetResult().getOrThrow(),
                rawDataAcquireString.GetResult().getOrThrow(), rawDataAcquireFileName.GetResult().getOrThrow(),
                rawDataAcquireLine.GetResult().getOrThrow()]), block0, builder, loc: INVALID_LOCATION)
        block0.AppendExpression(pcInitApply)
        let exit = builder.CreateExit(None, block0)
        exit.SetDebugLocation(INVALID_LOCATION)
        return `func`
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1151-1168.
    private func CreateRawDataAcquire(`type`: Type, list: ArrayList<Value>, size: Value,
        block: Block): Intrinsic {
        let arrayTy = builder.context.GetRefTy(builder.context.GetRawArrayTy(`type`))
        let expr = builder.CreateRawArrayAllocate(arrayTy, `type`, size, block)
        block.AppendExpression(expr)
        let arrayVar = expr.GetResult().getOrThrow()
        let literalInit = builder.CreateRawArrayLiteralInit(builder.context.GetUnitTy(), arrayVar, list, block)
        block.AppendExpression(literalInit)
        let cPointerTy = builder.context.GetCPointerTy(`type`)
        let callContext = IntrisicCallContext(kind: IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA,
            args: ArrayList<Value>([arrayVar]), instTypeArgs: ArrayList<Type>([`type`]))
        let rawDataAcquire = builder.CreateIntrinsic(cPointerTy, callContext, block)
        rawDataAcquire.SetDebugLocation(INVALID_LOCATION)
        block.AppendExpression(rawDataAcquire)
        return rawDataAcquire
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1170-1192.
    private func CreateTopLevelInitFunc(initFuncs: ArrayList<Function>, globalInitFunc: Function): Unit {
        if (initFuncs.isEmpty()) {
            return
        }
        let funcTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetVoidTy())
        let initName = MANGLE_CANGJIE_PREFIX + MANGLE_GLOBAL_FILE_INIT_PREFIX + MangleName("default") +
            MangleName("0.sancov") + MANGLE_FUNC_PARAM_TYPE_PREFIX + MANGLE_VOID_TY_SUFFIX
        let initFunc = CreateInitFunc(initName, funcTy, INVALID_LOCATION)
        let body = initFunc.GetBody().getOrThrow()
        let block0 = builder.CreateBlock(body)
        body.SetEntryBlock(block0)
        for (initFuncItem in initFuncs) {
            let apply = CreateNonMemberApply(initFuncItem.GetReturnType().getOrThrow(), initFuncItem,
                ArrayList<Value>(), block0, builder, loc: INVALID_LOCATION)
            block0.AppendExpression(apply)
        }
        let exit = builder.CreateExit(None, block0)
        exit.SetDebugLocation(INVALID_LOCATION)
        let initExpr = CreateNonMemberApply(builder.context.GetVoidTy(), initFunc,
            ArrayList<Value>(), globalInitFunc.GetEntryBlock().getOrThrow(), builder, loc: INVALID_LOCATION)
        AddExpressionsToGlobalInitFunc(globalInitFunc, ArrayList<Expression>([initExpr]))
    }

    // C++: CHIR/Transformation/SanitizerCoverage.cpp:1194-1225.
    private func GenerateInitFunc(globalInitFunc: Function, isDebug: Bool): Unit {
        let needInsertArray = sanCovOption.inlineBoolFlag || sanCovOption.inline8bitCounters ||
            sanCovOption.tracePCGuard
        if (!needInsertArray) {
            return
        }
        let initFuncs = ArrayList<Function>()
        if (sanCovOption.inlineBoolFlag &&
            GetGlobalVar(SAN_COV_CTOR2_GLOBAL_VAR_NAME.get(SanCovBoolFlagInitName).getOrThrow()).isSome()) {
            initFuncs.add(CreateArrayInitFunc(SanCovBoolFlagInitName, builder.context.GetBoolTy()))
        }
        if (sanCovOption.inline8bitCounters &&
            GetGlobalVar(SAN_COV_CTOR2_GLOBAL_VAR_NAME.get(SanCovCharArrayInitName).getOrThrow()).isSome()) {
            initFuncs.add(CreateArrayInitFunc(SanCovCharArrayInitName, builder.context.GetUInt8Ty()))
        }
        if (sanCovOption.tracePCGuard && funcBag.contains(SAN_COV_PC_GUARD) &&
            GetGlobalVar(SAN_COV_CTOR2_GLOBAL_VAR_NAME.get(SanCovUInt32ArrayInitName).getOrThrow()).isSome()) {
            initFuncs.add(CreateArrayInitFunc(SanCovUInt32ArrayInitName, builder.context.GetUInt32Ty()))
        }
        if (sanCovOption.pcTable && !pcArray.isEmpty()) {
            initFuncs.add(CreatePCTableInitFunc())
            if (isDebug) {
                println("[SanitizerCoverage] Add trace pc table" + ToPosInfo(INVALID_LOCATION) + ".")
            }
        }
        CreateTopLevelInitFunc(initFuncs, globalInitFunc)
    }
}
