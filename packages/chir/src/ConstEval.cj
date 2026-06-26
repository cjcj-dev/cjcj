package cangjie_compiler::chir

import std.collection.*

public class ConstEvalPass {
    public init() {}

    public static func HasConstGlobalVarInitFuncs(pkg: Package): Bool {
        for (fn in pkg.GetGlobalFuncsWithBody(includeSrcCodeImported: false)) {
            if (fn.IsGVInit() && fn.IsCompileTimeValue()) {
                return true
            }
        }
        return false
    }

    public func RunOnPackage(pkg: Package): Unit {
        let initFuncsForConstVar = CollectConstGlobalVarInitFuncs(pkg)
        if (initFuncsForConstVar.isEmpty()) {
            return
        }
        RunInterpreter(pkg, initFuncsForConstVar)
    }

    private func RunInterpreter(pkg: Package, initFuncsForConstVar: ArrayList<Function>): Unit {
        let bchirPackages = ArrayList<BCHIR>()
        let packageBchir = BCHIR()
        CHIR2BCHIR.CompilePackage(pkg, packageBchir, forConstEval: true)
        for (fn in initFuncsForConstVar) {
            packageBchir.initFuncsForConsts.add(BCHIRMangledName(fn))
        }
        bchirPackages.add(packageBchir)

        let linker = BCHIRLinker()
        let globalInitValues = linker.RunForConstEval(bchirPackages)
        let linkedBchir = linker.GetLinkedBCHIR()
        let fePlayground = linkedBchir.GetLinkedByteCode().Size()
        let extraReqSpace = BCHIRInterpreter.INTERNAL_PLAYGROUND_SIZE + BCHIRInterpreter.EXTERNAL_PLAYGROUND_SIZE
        linkedBchir.Resize(fePlayground + extraReqSpace)

        let interpreter = BCHIRInterpreter(linkedBchir)
        interpreter.SetGlobalVars(globalInitValues)
        let result = interpreter.Run(baseIndex: 0, expectsReturn: false)
        if (result.kind == BCHIRResultKind.TRAP || result.kind == BCHIRResultKind.UNSUPPORTED) {
            let message = if (result.message.isEmpty()) { "no message" } else { result.message }
            throw IllegalStateException("ConstEvalPass interpreter failed: " + message)
        }
        ReplaceGlobalConstantInitializers(pkg, interpreter, linker)
    }

    private func CollectConstGlobalVarInitFuncs(pkg: Package): ArrayList<Function> {
        let funcs = ArrayList<Function>()
        for (fn in pkg.GetGlobalFuncsWithBody(includeSrcCodeImported: false)) {
            if (fn.IsGVInit() && fn.IsCompileTimeValue()) {
                funcs.add(fn)
            }
        }
        return funcs
    }

    // Mirrors CC src/CHIR/Interpreter/ConstEval.cpp:386-420.
    private func ReplaceGlobalConstantInitializers(pkg: Package, interpreter: BCHIRInterpreter,
        linker: BCHIRLinker): Unit {
        let builder = CHIRBuilder(CHIRContext())
        builder.context.SetCurPackage(pkg)
        let allFuncs = pkg.GetGlobalFunctions(includePureAbstract: true)
        let newFuncs = ArrayList<Function>()
        for (fn in allFuncs) {
            if (fn.GetFuncKind() != FuncKind.GLOBALVAR_INIT || !fn.TestAttr(Attribute.CONST)) {
                newFuncs.add(fn)
                continue
            }
            let rewrite = CreateNewInitializer(fn, interpreter, linker, pkg, builder)
            if (rewrite.kind == ConstInitRewriteKind.FAILED) {
                newFuncs.add(fn)
            } else if (rewrite.kind == ConstInitRewriteKind.REMOVE) {
                for (user in fn.GetUsers()) {
                    user.RemoveSelfFromBlock()
                }
                fn.DestroySelf()
            } else if (let Some(newBody) <- rewrite.body) {
                let entry = newBody.GetEntryBlock() ??
                    throw IllegalStateException("const-eval replacement body has no entry block")
                builder.CreateExit(None, entry)
                fn.ReplaceBody(newBody)
                newFuncs.add(fn)
            } else {
                newFuncs.add(fn)
            }
        }
        pkg.SetAllGlobalFuncs(newFuncs)
    }

    // Mirrors CC src/CHIR/Interpreter/ConstEval.cpp:424-470.
    private func CreateNewInitializer(oldInitializer: Function, interpreter: BCHIRInterpreter, linker: BCHIRLinker,
        pkg: Package, builder: CHIRBuilder): ConstInitRewrite {
        var newBody: Option<BlockGroup> = None
        let body = oldInitializer.GetBody() ?? return ConstInitRewrite.Remove()
        for (block in body.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (expr.GetExprKind() != ExprKind.STORE) {
                    continue
                }
                let store = expr as Store
                if (let None <- store) {
                    continue
                }
                let location = store.getOrThrow().GetLocation()
                if (!location.IsGlobalVarWithInitializer()) {
                    continue
                }
                let global = location.AsGlobalVar() ?? continue
                let varId = linker.GetGVARId(global.GetIdentifierWithoutPrefix())
                if (varId < 0) {
                    return ConstInitRewrite.Failed("missing global id for " + global.GetIdentifierWithoutPrefix())
                }
                let val = interpreter.PeekValueOfGlobal(varId)
                let varRefType = global.GetType() ?? return ConstInitRewrite.Failed(
                    "global has no type: " + global.GetIdentifierWithoutPrefix())
                let refTy = varRefType as RefType
                if (let None <- refTy) {
                    return ConstInitRewrite.Failed("global type is not a ref: " + varRefType.ToString())
                }
                let varType = refTy.getOrThrow().GetBaseType()
                let val2chir = IVal2CHIR(builder, interpreter, pkg)
                if (let Some(constant) <- val2chir.TryConvertToConstant(varType, val, block)) {
                    if (!constant.IsConstantNull()) {
                        if (let Some(result) <- constant.GetResult()) {
                            global.SetInitializerValue(result)
                            continue
                        }
                    }
                }
                if (let None <- newBody) {
                    let created = builder.CreateBlockGroup(oldInitializer)
                    created.SetOwnerFunc(oldInitializer)
                    created.SetEntryBlock(builder.CreateBlock(created))
                    newBody = created
                }
                let targetBody = newBody.getOrThrow()
                let newBlock = targetBody.GetEntryBlock() ??
                    throw IllegalStateException("const-eval new initializer body has no entry block")
                let constValue = val2chir.ConvertToChir(varType, val, newBlock) ??
                    return ConstInitRewrite.Failed("cannot convert " + TypeKindName(varType.GetTypeKind()) +
                        " from " + IValUtils.ToString(val))
                builder.CreateStore(constValue, global, newBlock)
            }
        }
        if (let Some(replacement) <- newBody) {
            return ConstInitRewrite.Replace(replacement)
        }
        return ConstInitRewrite.Remove()
    }
}

private enum ConstInitRewriteKind {
    | FAILED | REMOVE | REPLACE
}

private func ConstInitRewriteKindIndex(kind: ConstInitRewriteKind): Int64 {
    return match (kind) {
        case ConstInitRewriteKind.FAILED => 0
        case ConstInitRewriteKind.REMOVE => 1
        case ConstInitRewriteKind.REPLACE => 2
    }
}

extend ConstInitRewriteKind <: Equatable<ConstInitRewriteKind> {
    public operator func ==(right: ConstInitRewriteKind): Bool {
        return ConstInitRewriteKindIndex(this) == ConstInitRewriteKindIndex(right)
    }

    public operator func !=(right: ConstInitRewriteKind): Bool {
        return !(this == right)
    }
}

private class ConstInitRewrite {
    public let kind: ConstInitRewriteKind
    public let body: Option<BlockGroup>

    private init(kind: ConstInitRewriteKind, body!: Option<BlockGroup> = None) {
        this.kind = kind
        this.body = body
    }

    public static func Failed(reason: String): ConstInitRewrite {
        let _ = reason
        return ConstInitRewrite(ConstInitRewriteKind.FAILED)
    }

    public static func Remove(): ConstInitRewrite {
        return ConstInitRewrite(ConstInitRewriteKind.REMOVE)
    }

    public static func Replace(body: BlockGroup): ConstInitRewrite {
        return ConstInitRewrite(ConstInitRewriteKind.REPLACE, body: body)
    }
}

// Mirrors CC src/CHIR/Interpreter/ConstEval.cpp:28-150 and aggregate helpers at 79-232.
private class IVal2CHIR {
    private let builder: CHIRBuilder
    private let interpreter: BCHIRInterpreter
    private let pkg: Package

    public init(builder: CHIRBuilder, interpreter: BCHIRInterpreter, pkg: Package) {
        this.builder = builder
        this.interpreter = interpreter
        this.pkg = pkg
    }

    public func TryConvertToConstant(ty: Type, val: InterpreterValue, parent: Block): Option<Constant> {
        return match (ty.GetTypeKind()) {
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 |
                TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT8 | TypeKind.TYPE_UINT16 | TypeKind.TYPE_UINT32 |
                TypeKind.TYPE_UINT64 | TypeKind.TYPE_UINT_NATIVE =>
                if (val.IsIntLike()) { Some(builder.CreateConstant(ty, IntLiteral(val.GetInt()), parent)) } else { None }
            case TypeKind.TYPE_FLOAT16 | TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 =>
                if (val.IsFloatLike()) { Some(builder.CreateConstant(ty, FloatLiteral(val.GetFloat()), parent)) } else { None }
            case TypeKind.TYPE_RUNE =>
                if (val.kind == InterpreterValueKind.IRUNE) {
                    Some(builder.CreateConstant(ty, RuneLiteral(Rune(val.GetInt())), parent))
                } else {
                    None
                }
            case TypeKind.TYPE_BOOLEAN =>
                if (val.kind == InterpreterValueKind.IBOOL) {
                    Some(builder.CreateConstant(ty, BoolLiteral(val.GetBool()), parent))
                } else {
                    None
                }
            case _ =>
                if (val.kind == InterpreterValueKind.INULLPTR) {
                    Some(builder.CreateConstant(ty, NullLiteral(), parent))
                } else {
                    None
                }
        }
    }

    public func ConvertToChir(ty: Type, val: InterpreterValue, parent: Block): Option<Value> {
        if (let Some(constant) <- TryConvertToConstant(ty, val, parent)) {
            return ExprResultAsValue(constant)
        }
        return match (ty.GetTypeKind()) {
            case TypeKind.TYPE_TUPLE | TypeKind.TYPE_STRUCT =>
                if (ty.IsString()) {
                    ConvertStringToChir(ty, val, parent)
                } else {
                    ConvertTupleToChir(ty, val, parent)
                }
            case TypeKind.TYPE_ENUM =>
                if (let Some(enumTy) <- (ty as EnumType)) {
                    ConvertEnumToChir(enumTy, val, parent)
                } else {
                    None
                }
            case TypeKind.TYPE_UNIT =>
                ExprResultAsValue(builder.CreateConstant(ty, UnitLiteral(), parent))
            case TypeKind.TYPE_VARRAY =>
                if (let Some(varrayTy) <- (ty as VArrayType)) {
                    ConvertArrayToChir(varrayTy, val, parent)
                } else {
                    None
                }
            case _ => None
        }
    }

    private func ConvertStringToChir(ty: Type, val: InterpreterValue, parent: Block): Option<Value> {
        if (val.kind == InterpreterValueKind.ISTRING) {
            return ExprResultAsValue(builder.CreateConstant(ty, StringLiteral(val.GetText()), parent))
        }
        if (val.kind != InterpreterValueKind.ITUPLE) {
            return None
        }
        let fields = val.GetElementsRef()
        if (fields.size < 3 || !fields[1].IsIntLike() || !fields[2].IsIntLike()) {
            return None
        }
        if (fields[1].GetInt() != 0) {
            return None
        }
        let arr = interpreter.DereferenceValue(fields[0]) ?? return None
        if (arr.kind != InterpreterValueKind.IARRAY) {
            return None
        }
        let arrData = arr.GetElementsRef()
        let len = fields[2].GetInt()
        if (len < 0 || arrData.size <= len) {
            return None
        }
        var out = ""
        var idx: Int64 = 0
        while (idx < len) {
            if (!arrData[idx + 1].IsIntLike()) {
                return None
            }
            out += String.fromUtf8([UInt8(arrData[idx + 1].GetInt())])
            idx++
        }
        return ExprResultAsValue(builder.CreateConstant(ty, StringLiteral(out), parent))
    }

    private func ConvertTupleToChir(ty: Type, val: InterpreterValue, parent: Block): Option<Value> {
        if (val.kind != InterpreterValueKind.ITUPLE) {
            return None
        }
        let elementTys = if (ty.GetTypeKind() == TypeKind.TYPE_STRUCT) {
            if (let Some(customTy) <- (ty as CustomType)) {
                customTy.GetInstantiatedMemberTys()
            } else {
                ArrayList<Type>()
            }
        } else {
            ty.GetTypeArgs()
        }
        let elementVals = val.GetElementsRef()
        if (elementVals.size != elementTys.size) {
            return None
        }
        let elements = ArrayList<Value>()
        var idx: Int64 = 0
        while (idx < elementVals.size) {
            let elementVal = ConvertToChir(elementTys[idx], elementVals[idx], parent) ?? return None
            elements.add(elementVal)
            idx++
        }
        if (ty.IsStruct()) {
            let refTy = builder.context.GetRefTy(ty)
            let allocate = ExprResultAsValue(builder.CreateAllocate(refTy, ty, parent)) ?? return None
            var fieldIdx: Int64 = 0
            while (fieldIdx < elements.size) {
                let path = ArrayList<UInt64>()
                path.add(UInt64(fieldIdx))
                builder.CreateStoreElementRef(elements[fieldIdx], allocate, path, parent)
                fieldIdx++
            }
            return ExprResultAsValue(builder.CreateLoad(ty, allocate, parent))
        }
        return ExprResultAsValue(builder.CreateTuple(ty, elements, parent))
    }

    private func ConvertEnumToChir(ty: EnumType, val: InterpreterValue, parent: Block): Option<Value> {
        let selectorTy = builder.context.ToSelectorType(GetEnumSelectorType(ty.GetEnumDef()))
        if (ty.GetEnumDef().IsAllCtorsTrivial()) {
            if (!val.IsIntLike() && val.kind != InterpreterValueKind.IBOOL) {
                return None
            }
            let selector = if (selectorTy.IsBoolean()) {
                ExprResultAsValue(builder.CreateConstant(selectorTy, BoolLiteral(if (val.kind == InterpreterValueKind.IBOOL) {
                    val.GetBool()
                } else {
                    val.GetInt() != 0
                }), parent)) ?? return None
            } else {
                ExprResultAsValue(builder.CreateConstant(selectorTy, IntLiteral(val.GetInt()), parent)) ?? return None
            }
            return ExprResultAsValue(builder.CreateTypeCast(ty, selector, parent))
        }
        if (val.kind != InterpreterValueKind.ITUPLE) {
            return None
        }
        let elementVals = val.GetElementsRef()
        if (elementVals.isEmpty()) {
            return None
        }
        let elements = ArrayList<Value>()
        let variantIndex = if (selectorTy.IsBoolean()) {
            if (elementVals[0].kind != InterpreterValueKind.IBOOL) {
                return None
            }
            elements.add(ConvertToChir(selectorTy, elementVals[0], parent) ?? return None)
            if (elementVals[0].GetBool()) { 1 } else { 0 }
        } else {
            if (!elementVals[0].IsIntLike()) {
                return None
            }
            elements.add(ConvertToChir(selectorTy, elementVals[0], parent) ?? return None)
            elementVals[0].GetInt()
        }
        let ctorInfos = ty.GetEnumDef().GetConstructorInfos(builder: builder)
        if (variantIndex < 0 || variantIndex >= ctorInfos.size) {
            return None
        }
        let ctor = ctorInfos[variantIndex]
        let elementTys = ArrayList<Type>()
        match (ctor.funcType) {
            case Some(funcTy) =>
                for (paramTy in funcTy.GetParamTypes()) {
                    elementTys.add(paramTy)
                }
            case None =>
                for (payloadTy in ctor.payloadTypes) {
                    elementTys.add(payloadTy)
                }
        }
        if (elementVals.size != elementTys.size + 1) {
            return None
        }
        var idx: Int64 = 0
        while (idx < elementTys.size) {
            let elementVal = ConvertToChir(elementTys[idx], elementVals[idx + 1], parent) ?? return None
            elements.add(elementVal)
            idx++
        }
        return ExprResultAsValue(builder.CreateTuple(ty, elements, parent))
    }

    private func ConvertArrayToChir(ty: VArrayType, val: InterpreterValue, parent: Block): Option<Value> {
        if (val.kind != InterpreterValueKind.IARRAY) {
            return None
        }
        let elementVals = val.GetElementsRef()
        let elements = ArrayList<Value>()
        for (elementVal in elementVals) {
            elements.add(ConvertToChir(ty.GetElementType(), elementVal, parent) ?? return None)
        }
        return ExprResultAsValue(builder.CreateVArray(ty, elements, parent))
    }

    private func GetEnumSelectorType(def: EnumDef): TypeKind {
        if (!def.IsExhaustive()) {
            return TypeKind.TYPE_UINT32
        }
        if (def.IsOptionLike()) {
            return TypeKind.TYPE_BOOLEAN
        }
        return TypeKind.TYPE_UINT32
    }

    private func ExprResultAsValue(expr: Expression): Option<Value> {
        if (let Some(result) <- expr.GetResult()) {
            return Some(result)
        }
        return None
    }
}
