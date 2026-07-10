package cjcj::chir

import std.collection.*
import cjcj::utils.{CJC_ASSERT, CORE_PACKAGE_NAME}

private let CONST_EXCEPTIONS: Array<String> = [
    "@_CNat19ArithmeticExceptionE",
    "@_CNat5ErrorE",
    "@_CNat9ExceptionE",
    "@_CNat24IllegalArgumentExceptionE",
    "@_CNat25IndexOutOfBoundsExceptionE",
    "@_CNat18NoneValueExceptionE",
    "@_CNat17OverflowExceptionE",
]

private let CONST_FUNCTIONS: Array<String> = [
    "@_CNat19ArithmeticException6<init>Hv",
    "@_CNat19ArithmeticException6<init>HRNat6StringE",
    "@_CNat9Exception6<init>Hv",
    "@_CNat9Exception6<init>HRNat6StringE",
    "@_CNat5Error6<init>Hv",
    "@_CNat5Error6<init>HRNat6StringE",
    "@_CNat24IllegalArgumentException6<init>Hv",
    "@_CNat24IllegalArgumentException6<init>HRNat6StringE",
    "@_CNat25IndexOutOfBoundsException6<init>Hv",
    "@_CNat25IndexOutOfBoundsException6<init>HRNat6StringE",
    "@_CNat17OverflowException6<init>Hv",
    "@_CNat17OverflowException6<init>HRNat6StringE",
    "@_CNat5ArrayIhE5cloneHv",
    "@_CNat6String7toArrayHv",
]

public class CHIR2BCHIRContext {
    public let definition: BCHIRDefinition = BCHIRDefinition()
    public var localVarId: Int64 = 0
    public let valueToLocal: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    public let blockToIndex: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    public let blockPlaceholders: HashMap<Int64, ArrayList<Int64>> = HashMap<Int64, ArrayList<Int64>>()
}

public class CHIR2BCHIR {
    let bchir: BCHIR
    private let isIncremental: Bool
    private let stringMemo: HashMap<String, Int64> = HashMap<String, Int64>()
    private let typeMemo: HashMap<Int64, Int64> = HashMap<Int64, Int64>()

    public init(bchir: BCHIR, isIncremental!: Bool = false) {
        this.bchir = bchir
        this.isIncremental = isIncremental
    }

    public static func CompilePackage(chirPkg: Package, destBchir: BCHIR,
        initFuncsForConstVar!: ArrayList<Function> = ArrayList<Function>(), forConstEval!: Bool = false,
        incremental!: Bool = false): Unit {
        let compiler = CHIR2BCHIR(destBchir, isIncremental: incremental)
        compiler.TranslatePackage(chirPkg, initFuncsForConstVar: initFuncsForConstVar, forConstEval: forConstEval)
    }

    public func TranslatePackage(chirPkg: Package,
        initFuncsForConstVar!: ArrayList<Function> = ArrayList<Function>(), forConstEval!: Bool = false): Unit {
        bchir.packageName = chirPkg.GetName()
        if (chirPkg.GetName() == CORE_PACKAGE_NAME) {
            bchir.SetAsCore()
            bchir.AddSClass("_CN8std$core6ObjectE", BCHIRSClassInfo())
        }
        TranslateClassesLike(chirPkg, forConstEval: forConstEval)
        TranslateGlobalVars(chirPkg, forConstEval: forConstEval)
        TranslateFunctions(chirPkg, forConstEval: forConstEval)
        if (let Some(initFunc) <- chirPkg.GetPackageInitFunc()) {
            bchir.SetGlobalInitFunc(initFunc.GetIdentifierWithoutPrefix())
        }
        if (forConstEval) {
            for (initFuncForConstVar in initFuncsForConstVar) {
                bchir.initFuncsForConsts.add(initFuncForConstVar.GetIdentifierWithoutPrefix())
            }
        }
        if (let Some(literalInitFunc) <- chirPkg.GetPackageLiteralInitFunc()) {
            bchir.SetGlobalInitLiteralFunc(BCHIRMangledName(literalInitFunc))
        }
    }

    private func TranslateClassesLike(chirPkg: Package, forConstEval!: Bool): Unit {
        for (classDef in chirPkg.GetAllClassDef()) {
            if (forConstEval && !classDef.IsInterface() && !IsConstClass(classDef)) {
                continue
            }
            let info = BCHIRSClassInfo()
            if (let Some(superClass) <- classDef.GetSuperClassDef()) {
                info.superClasses.add(BCHIRMangledName(superClass))
            }
            if (let Some(finalizer) <- classDef.GetFinalizer()) {
                info.finalizer = finalizer.GetIdentifierWithoutPrefix()
            }
            CollectMethods(classDef, info)
            AddClassInfo(BCHIRMangledName(classDef), info)
        }
        for (structDef in chirPkg.GetAllStructDef()) {
            if (forConstEval && !IsConstClass(structDef)) {
                continue
            }
            let info = BCHIRSClassInfo()
            CollectMethods(structDef, info)
            AddClassInfo(BCHIRMangledName(structDef), info)
        }
        for (enumDef in chirPkg.GetAllEnumDef()) {
            let info = BCHIRSClassInfo()
            CollectMethods(enumDef, info)
            AddClassInfo(BCHIRMangledName(enumDef), info)
        }
        for (extendDef in chirPkg.GetAllExtendDef()) {
            if (let Some(extendedDef) <- extendDef.GetExtendedCustomTypeDef()) {
                if (forConstEval && !IsConstClass(extendedDef)) {
                    continue
                }
                let name = BCHIRMangledName(extendedDef)
                if (let Some(info) <- bchir.GetSClass(name)) {
                    CollectMethods(extendDef, info)
                } else {
                    CJC_ASSERT(forConstEval)
                    continue
                }
            } else if (let Some(extendedTy) <- extendDef.GetExtendedType()) {
                CJC_ASSERT(extendedTy.IsPrimitive() || extendedTy.IsCString() || extendedTy.IsCPointer())
                let name = extendedTy.ToString()
                if (let Some(info) <- bchir.GetSClass(name)) {
                    CollectMethods(extendDef, info)
                } else {
                    let freshInfo = BCHIRSClassInfo()
                    CollectMethods(extendDef, freshInfo)
                    AddClassInfo(name, freshInfo)
                }
            } else {
                CJC_ASSERT(false)
            }
        }
    }

    private func AddClassInfo(classMangledName: String, classInfo: BCHIRSClassInfo): Unit {
        if (isIncremental) {
            bchir.RemoveClass(classMangledName)
        }
        bchir.AddSClass(classMangledName, classInfo)
    }

    private func IsConstClass(def: CustomTypeDef): Bool {
        for (name in CONST_EXCEPTIONS) {
            if (def.GetIdentifier() == name) {
                return true
            }
        }
        if (def.IsClassLike()) {
            if (def.TestAttr(Attribute.COMPILER_ADD)) {
                return true
            }
            let methods = def.GetMethods()
            for (extendDef in def.GetExtends()) {
                for (method in extendDef.GetMethods()) {
                    methods.add(method)
                }
            }
            for (method in methods) {
                if (method.TestAttr(Attribute.CONST)) {
                    return true
                }
            }
            return methods.isEmpty()
        } else {
            return true
        }
    }

    private func CollectMethods(def: CustomTypeDef, info: BCHIRSClassInfo): Unit {
        for (vtable in def.GetDefVTable().GetTypeVTables()) {
            for (funcInfo in vtable.GetVirtualMethods()) {
                let methodName = MangleMethodName(funcInfo.GetMethodName(), funcInfo.GetMethodSigType())
                let method = funcInfo.GetVirtualMethod().getOrThrow()
                if (!method.IsPureAbstract()) {
                    info.vtable[methodName] = method.GetIdentifierWithoutPrefix()
                }
            }
        }
    }

    private func TranslateGlobalVars(chirPkg: Package, forConstEval!: Bool): Unit {
        for (globalVar in chirPkg.GetGlobalVarsWithInit()) {
            if (forConstEval && !globalVar.IsCompileTimeValue()) {
                continue
            }
            let context = TranslateGlobalVar(globalVar, forConstEval: forConstEval)
            let mangledName = globalVar.GetIdentifierWithoutPrefix()
            if (mangledName == "$has_applied_pkg_init_func") {
                let fixedMangledName = "$has_applied_pkg_init_func-" + bchir.packageName
                bchir.RemoveGlobalVar(fixedMangledName)
                bchir.AddGlobalVar(fixedMangledName, context.definition)
            } else {
                bchir.AddGlobalVar(mangledName, context.definition)
            }
        }
        bchir.SetNumGlobalVars(chirPkg.GetGlobalVars().size)
    }

    private func TranslateGlobalVar(globalVar: GlobalVar, forConstEval!: Bool): CHIR2BCHIRContext {
        let context = CHIR2BCHIRContext()
        if (let Some(initValue) <- globalVar.GetInitializer()) {
            TranslateLiteralValue(context, initValue)
        } else {
            let initFunc = globalVar.GetInitFunc() ??
                throw IllegalStateException("global var without literal initializer requires init function: " +
                    globalVar.GetIdentifierWithoutPrefix())
            let placeholder = context.definition.NextIndex()
            context.definition.PushOp(OpCode.NULLPTR)
            if (forConstEval) {
                context.definition.AddMangledNameAnnotation(placeholder, BCHIRMangledName(initFunc))
            }
        }
        return context
    }

    private func TranslateFunctions(chirPkg: Package, forConstEval!: Bool): Unit {
        for (function in chirPkg.GetGlobalFuncsWithBody()) {
            if (forConstEval && !ShouldTranslateFunctionForConstEval(function)) {
                continue
            }
            let context = CHIR2BCHIRContext()
            TranslateFuncDef(context, function)
            let name = BCHIRMangledName(function)
            bchir.AddFunction(name, context.definition)
            if (function.GetFuncKind() == FuncKind.MAIN_ENTRY) {
                bchir.SetMainMangledName(name)
                bchir.SetMainExpectedArgs(function.GetNumOfParams())
            }
        }
    }

    private func ShouldTranslateFunctionForConstEval(function: Function): Bool {
        if (function.IsCompileTimeValue()) {
            return true
        }
        for (name in CONST_FUNCTIONS) {
            if (function.GetIdentifier() == name) {
                return true
            }
        }
        if (bchir.IsCore()) {
            let functionIdent = function.GetIdentifierWithoutPrefix()
            for (name in BCHIRDefaultFunctionMangledNames()) {
                if (functionIdent == name) {
                    return true
                }
            }
        }
        return function.IsFinalizer()
    }

    public func TranslateFuncDef(context: CHIR2BCHIRContext, function: Function): Unit {
        let params = function.GetParams()
        var idx = params.size - 1
        while (idx >= 0) {
            context.definition.PushOp(OpCode.LVAR_SET)
            context.definition.PushCell(LVarId(context, params[idx]))
            idx--
        }
        context.definition.PushOp(OpCode.DROP)
        if (let Some(body) <- function.GetBody()) {
            if (let Some(entry) <- body.GetEntryBlock()) {
                TranslateBlock(context, entry)
                for (block in body.GetBlocks()) {
                    if (block.nodeId != entry.nodeId) {
                        TranslateBlock(context, block)
                    }
                }
            }
        }
        context.definition.SetNumArgs(function.GetNumOfParams())
        context.definition.SetNumLVars(context.localVarId)
    }

    public func TranslateBlock(context: CHIR2BCHIRContext, block: Block): Unit {
        ResolveBlockPlaceholders(context, block, context.definition.NextIndex())
        for (expr in block.GetExpressions()) {
            if (expr.IsDebug()) {
                continue
            }
            TranslateExpression(context, expr)
            if (!expr.IsTerminator()) {
                if (let Some(result) <- expr.GetResult()) {
                    context.definition.PushOp(OpCode.LVAR_SET)
                    context.definition.PushCell(LVarId(context, result))
                }
            }
        }
    }

    public func TranslateExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
        if (expr.GetExprKind() == ExprKind.INVOKE || expr.GetExprKind() == ExprKind.INVOKE_WITH_EXCEPTION) {
            context.definition.PushOp(OpCode.NULLPTR)
        }
        for (operand in expr.GetOperands()) {
            CHIR2BCHIRTranslateValue(this, context, operand)
        }
        match (expr.GetExprMajorKind()) {
            case ExprMajorKind.TERMINATOR => CHIR2BCHIRTranslateTerminatorExpression(this, context, expr)
            case ExprMajorKind.UNARY_EXPR => CHIR2BCHIRTranslateUnaryExpression(context, expr)
            case ExprMajorKind.BINARY_EXPR => CHIR2BCHIRTranslateBinaryExpression(context, expr)
            case ExprMajorKind.MEMORY_EXPR => CHIR2BCHIRTranslateMemoryExpression(context, expr)
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => CHIR2BCHIRTranslateStructuredExpression(context, expr)
            case ExprMajorKind.OTHERS => CHIR2BCHIRTranslateOtherExpression(this, context, expr)
        }
    }

    public func TranslateLiteralValue(context: CHIR2BCHIRContext, literal: LiteralValue): Unit {
        if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
            context.definition.PushOp(OpCode.BOOL)
            context.definition.PushCell(if (boolLiteral.GetVal()) { 1 } else { 0 })
        } else if (let Some(floatLiteral) <- (literal as FloatLiteral)) {
            TranslateFloatValue(context, floatLiteral)
        } else if (let Some(intLiteral) <- (literal as IntLiteral)) {
            TranslateIntValue(context, intLiteral)
        } else if (literal.IsNullLit()) {
            context.definition.PushOp(OpCode.NULLPTR)
        } else if (let Some(runeLiteral) <- (literal as RuneLiteral)) {
            context.definition.PushOp(OpCode.RUNE)
            context.definition.PushCell(Int64(UInt32(runeLiteral.GetVal())))
        } else if (let Some(stringLiteral) <- (literal as StringLiteral)) {
            context.definition.PushOp(OpCode.STRING)
            context.definition.PushCell(GetStringIdx(stringLiteral.GetVal()))
        } else if (literal.IsUnitLit()) {
            context.definition.PushOp(OpCode.UNIT)
        } else {
            CJC_ASSERT(false)
        }
    }

    private func TranslateIntValue(context: CHIR2BCHIRContext, value: IntLiteral): Unit {
        let typeKind = value.GetType().getOrThrow().GetTypeKind()
        let opCode = BCHIRPrimitiveTypeKindToOpCode(typeKind)
        CJC_ASSERT(opCode != OpCode.INVALID)
        context.definition.PushOp(opCode)
        if (typeKind == TypeKind.TYPE_INT64 || typeKind == TypeKind.TYPE_UINT64 ||
            typeKind == TypeKind.TYPE_INT_NATIVE || typeKind == TypeKind.TYPE_UINT_NATIVE) {
            context.definition.Push8Bytes(BCHIRCellFromUInt64(value.GetUnsignedVal()))
        } else {
            context.definition.PushCell(Int64(value.GetUnsignedVal() & 0xffffffffu64))
        }
    }

    private func TranslateFloatValue(context: CHIR2BCHIRContext, value: FloatLiteral): Unit {
        let typeKind = value.GetType().getOrThrow().GetTypeKind()
        let opCode = BCHIRPrimitiveTypeKindToOpCode(typeKind)
        CJC_ASSERT(opCode != OpCode.INVALID)
        context.definition.PushOp(opCode)
        if (typeKind == TypeKind.TYPE_FLOAT64) {
            context.definition.Push8Bytes(BCHIRCellFromUInt64(value.GetVal().toBits()))
        } else {
            let floatValue = Float32(value.GetVal())
            context.definition.PushCell(Int64(floatValue.toBits()))
        }
    }

    public func GetStringIdx(value: String): Int64 {
        if (let Some(index) <- stringMemo.get(value)) {
            return index
        }
        let next = bchir.AddString(value)
        stringMemo[value] = next
        return next
    }

    public func GetTypeIdx(ty: Type): Int64 {
        let key = ty.objectId
        if (let Some(index) <- typeMemo.get(key)) {
            return index
        }
        let next = bchir.AddType(ty)
        typeMemo[key] = next
        match (ty.GetTypeKind()) {
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 |
                TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 |
                TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE | TypeKind.TYPE_FLOAT16 |
                TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 | TypeKind.TYPE_BOOLEAN | TypeKind.TYPE_RUNE |
                TypeKind.TYPE_NOTHING | TypeKind.TYPE_CSTRING | TypeKind.TYPE_ENUM | TypeKind.TYPE_STRUCT |
                TypeKind.TYPE_UNIT => ()
            case TypeKind.TYPE_CPOINTER =>
                let cPointerTy = (ty as CPointerType).getOrThrow()
                let _ = GetTypeIdx(cPointerTy.GetElementType())
            case TypeKind.TYPE_TUPLE =>
                let tupleTy = (ty as TupleType).getOrThrow()
                for (elementTy in tupleTy.GetTypeArgs()) {
                    let _ = GetTypeIdx(elementTy)
                }
            case TypeKind.TYPE_FUNC =>
                let funcTy = (ty as FuncType).getOrThrow()
                for (paramTy in funcTy.GetParamTypes()) {
                    let _ = GetTypeIdx(paramTy)
                }
                let _ = GetTypeIdx(funcTy.GetReturnType())
            case TypeKind.TYPE_RAWARRAY =>
                let rawArrayTy = (ty as RawArrayType).getOrThrow()
                let _ = GetTypeIdx(rawArrayTy.GetElementType())
            case TypeKind.TYPE_REFTYPE =>
                let refTy = (ty as RefType).getOrThrow()
                let _ = GetTypeIdx(refTy.GetBaseType())
            case TypeKind.TYPE_CLASS => ()
            case _ => ()
        }
        return next
    }

    public func BlockIndex(context: CHIR2BCHIRContext, block: Block, placeholder: Int64): Int64 {
        if (let Some(index) <- context.blockToIndex.get(block.nodeId)) {
            return index
        }
        if (let Some(placeholders) <- context.blockPlaceholders.get(block.nodeId)) {
            placeholders.add(placeholder)
        } else {
            let placeholders = ArrayList<Int64>()
            placeholders.add(placeholder)
            context.blockPlaceholders[block.nodeId] = placeholders
        }
        return 0
    }

    public func ResolveBlockPlaceholders(context: CHIR2BCHIRContext, block: Block, index: Int64): Unit {
        context.blockToIndex[block.nodeId] = index
        if (let Some(placeholders) <- context.blockPlaceholders.get(block.nodeId)) {
            for (placeholder in placeholders) {
                context.definition.Set(placeholder, index)
            }
            context.blockPlaceholders.remove(block.nodeId)
        }
    }

    public func LVarId(context: CHIR2BCHIRContext, value: Value): Int64 {
        if (let Some(index) <- context.valueToLocal.get(value.nodeId)) {
            return index
        }
        let next = context.localVarId
        context.valueToLocal[value.nodeId] = next
        context.localVarId++
        return next
    }
}
