package cjcj::chir

import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::option.GlobalOptions
import cjcj::utils.CJC_ASSERT
import cjcj::utils.FileUtil
import cjcj::utils.InternalError
import std.collection.*

public class ConstEvalPass {
    private let builder: CHIRBuilder
    private let opts: GlobalOptions
    private let diag: BasicDiagnosticEngine

    public init(builder: CHIRBuilder, diag: BasicDiagnosticEngine, opts!: GlobalOptions = GlobalOptions()) {
        this.builder = builder
        this.diag = diag
        this.opts = opts
    }

    public func RunOnPackage(pkg: Package, initFuncsForConstVar: ArrayList<Function>,
        bchirPackages: ArrayList<BCHIR>): Unit {
        RunInterpreter(pkg, bchirPackages, initFuncsForConstVar)
    }

    private func RunInterpreter(pkg: Package, bchirPackages: ArrayList<BCHIR>,
        initFuncsForConstVar: ArrayList<Function>): Unit {
        let packageBchir = BCHIR()
        CHIR2BCHIR.CompilePackage(pkg, packageBchir, diag.GetSourceManager(),
            initFuncsForConstVar: initFuncsForConstVar,
            forConstEval: true)
        bchirPackages.add(packageBchir)

        let linker = BCHIRLinker()
        let globalInitValues = linker.RunForConstEval(bchirPackages)
        let linkedBchir = linker.GetLinkedBCHIR()
        let fePlayground = linkedBchir.GetLinkedByteCode().Size()
        let extraReqSpace = BCHIRInterpreter.INTERNAL_PLAYGROUND_SIZE + BCHIRInterpreter.EXTERNAL_PLAYGROUND_SIZE
        linkedBchir.Resize(fePlayground + extraReqSpace)

        let interpreter = BCHIRInterpreter(linkedBchir, diag)
        interpreter.SetGlobalVars(globalInitValues)
        let result = interpreter.Run(baseIndex: 0, expectsReturn: false)
        match (result) {
            case INotRun => ReplaceGlobalConstantInitializers(pkg, interpreter, linker)
            case IException(_) => ()
            case ISuccess(_) => ()
        }
    }

    // Mirrors CC src/CHIR/Interpreter/ConstEval.cpp:386-420.
    private func ReplaceGlobalConstantInitializers(pkg: Package, interpreter: BCHIRInterpreter,
        linker: BCHIRLinker): Unit {
        builder.context.SetCurPackage(pkg)
        let allFuncs = pkg.GetGlobalFunctions()
        let newFuncs = ArrayList<Function>()
        for (fn in allFuncs) {
            if (fn.GetFuncKind() != FuncKind.GLOBALVAR_INIT || !fn.TestAttr(Attribute.CONST)) {
                newFuncs.add(fn)
                continue
            }
            let optNewBody = CreateNewInitializer(fn, interpreter, linker, pkg)
            if (opts.chirDebugOptimizer) {
                PrintDebugMessage(fn.GetDebugLocation(), fn, optNewBody)
            }
            match (optNewBody) {
                case None =>
                    newFuncs.add(fn)
                case Some(newBody) =>
                    if (let None <- newBody) {
                        for (user in fn.GetUsers()) {
                            user.RemoveSelfFromBlock()
                        }
                        fn.DestroySelf()
                    } else if (let Some(body) <- newBody) {
                        let entry = body.GetEntryBlock() ??
                            throw IllegalStateException("const-eval replacement body has no entry block")
                        let createdExit78 = builder.CreateExit(None, entry)
                        entry.AppendExpression(createdExit78)
                        fn.ReplaceBody(body)
                        newFuncs.add(fn)
                    }
            }
        }
        pkg.SetAllGlobalFuncs(newFuncs)
    }

    // Mirrors CC src/CHIR/Interpreter/ConstEval.cpp:424-470.
    private func CreateNewInitializer(oldInitializer: Function, interpreter: BCHIRInterpreter, linker: BCHIRLinker,
        pkg: Package): Option<Option<BlockGroup>> {
        var newBody: Option<BlockGroup> = None
        if (opts.enIncrementalCompilation) {
            let created = builder.CreateBlockGroup(oldInitializer)
            created.SetOwnerFunc(oldInitializer)
            created.SetEntryBlock(builder.CreateBlock(created))
            newBody = created
        }
        let body = oldInitializer.GetBody().getOrThrow()
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
                CJC_ASSERT(varId != -1)
                let val = interpreter.PeekValueOfGlobal(varId)
                let varRefType = global.GetType().getOrThrow()
                CJC_ASSERT(varRefType.IsRef())
                let varType = (varRefType as RefType).getOrThrow().GetBaseType()
                let val2chir = IVal2CHIR(builder, interpreter, pkg)
                if (let Some(constant) <- val2chir.TryConvertToConstant(varType, val, block)) {
                    block.AppendExpression(constant)
                    if (!constant.IsConstantNull()) {
                        global.SetInitializer(constant.GetValue())
                        continue
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
                let insertExpr = { expr: Expression => newBlock.AppendExpression(expr) }
                let constValue = val2chir.ConvertToChir(varType, val, insertExpr, newBlock) ??
                    return None
                let createdStore136 = builder.CreateStore(constValue, global, newBlock)
                newBlock.AppendExpression(createdStore136)
            }
        }
        return Some(newBody)
    }

    private func PrintDebugMessage(loc: DebugLocation, oldInit: Function, newInit: Option<Option<BlockGroup>>): Unit {
        let file = FileUtil.GetFileName(loc.GetAbsPath())
        let beginPos = loc.GetBeginPos()
        let endPos = loc.GetEndPos()
        let begin = file + ":" + beginPos.line.toString() + ":" + beginPos.column.toString()
        let end = file + ":" + endPos.line.toString() + ":" + endPos.column.toString()

        match (newInit) {
            case None =>
                println("debug: consteval at " + begin + " - " + end + " function `" +
                    oldInit.GetSrcCodeIdentifier() + "` not evaluated successfully.")
            case Some(None) =>
                println("debug: consteval at " + begin + " - " + end + " replaced initializer function `" +
                    oldInit.GetSrcCodeIdentifier() + "` with initializer constant(s).")
            case Some(Some(newBody)) =>
                var oldExprs: Int64 = 0
                for (block in oldInit.GetBody().getOrThrow().GetBlocks()) {
                    oldExprs += block.GetExpressions().size
                }
                var newExprs: Int64 = 0
                for (block in newBody.GetBlocks()) {
                    newExprs += block.GetExpressions().size
                }
                println("debug: consteval at " + begin + " - " + end + " evaluated initializer function `" +
                    oldInit.GetSrcCodeIdentifier() + "` of " + oldExprs.toString() + " expressions to one of " +
                    newExprs.toString() + " expressions.")
        }
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
                if (val.IsIntLike()) {
                    let constant = builder.CreateConstant(ty, IntLiteral(val.GetInt()), parent)
                    Some(constant)
                } else {
                    None
                }
            case TypeKind.TYPE_FLOAT16 | TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 =>
                if (val.IsFloatLike()) {
                    let constant = builder.CreateConstant(ty, FloatLiteral(val.GetFloat()), parent)
                    Some(constant)
                } else {
                    None
                }
            case TypeKind.TYPE_RUNE =>
                if (val.kind == InterpreterValueKind.IRUNE) {
                    let createdConstant194 = builder.CreateConstant(ty, RuneLiteral(Rune(val.GetInt())), parent)
                    Some(createdConstant194)
                } else {
                    None
                }
            case TypeKind.TYPE_BOOLEAN =>
                if (val.kind == InterpreterValueKind.IBOOL) {
                    let createdConstant200 = builder.CreateConstant(ty, BoolLiteral(val.GetBool()), parent)
                    Some(createdConstant200)
                } else {
                    None
                }
            case _ =>
                if (val.kind == InterpreterValueKind.INULLPTR) {
                    let createdConstant206 = builder.CreateConstant(ty, NullLiteral(), parent)
                    Some(createdConstant206)
                } else {
                    None
                }
        }
    }

    public func ConvertToChir(ty: Type, val: InterpreterValue,
        insertExpr: (Expression) -> Unit, parent: Block): Option<Value> {
        if (let Some(constant) <- TryConvertToConstant(ty, val, parent)) {
            insertExpr(constant)
            return ExprResultAsValue(constant)
        }
        return match (ty.GetTypeKind()) {
            case TypeKind.TYPE_TUPLE | TypeKind.TYPE_STRUCT =>
                if (ty.IsString()) {
                    ConvertStringToChir(ty, val, insertExpr, parent)
                } else {
                    ConvertTupleToChir(ty, val, insertExpr, parent)
                }
            case TypeKind.TYPE_ENUM =>
                if (let Some(enumTy) <- (ty as EnumType)) {
                    ConvertEnumToChir(enumTy, val, insertExpr, parent)
                } else {
                    None
                }
            case TypeKind.TYPE_REFTYPE =>
                if (let Some(refTy) <- (ty as RefType)) {
                    ConvertRefToChir(refTy, val, insertExpr, parent)
                } else {
                    None
                }
            case TypeKind.TYPE_UNIT =>
                let createdConstant237 = builder.CreateConstant(ty, UnitLiteral(), parent)
                insertExpr(createdConstant237)
                ExprResultAsValue(createdConstant237)
            case TypeKind.TYPE_VARRAY =>
                if (let Some(varrayTy) <- (ty as VArrayType)) {
                    ConvertArrayToChir(varrayTy, val, insertExpr, parent)
                } else {
                    None
                }
            case TypeKind.TYPE_CLASS | TypeKind.TYPE_FUNC | TypeKind.TYPE_GENERIC | TypeKind.TYPE_NOTHING |
                TypeKind.TYPE_RAWARRAY | TypeKind.TYPE_CPOINTER | TypeKind.TYPE_CSTRING | TypeKind.TYPE_VOID |
                TypeKind.TYPE_INVALID => None
            case _ =>
                InternalError("unsupported type kind")
                None
        }
    }

    private func ConvertStringToChir(ty: Type, val: InterpreterValue,
        insertExpr: (Expression) -> Unit, parent: Block): Option<Value> {
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
        let out = ArrayList<UInt8>()
        var idx: Int64 = 0
        while (idx < len) {
            if (!arrData[idx + 1].IsIntLike()) {
                return None
            }
            out.add(UInt8(arrData[idx + 1].GetInt()))
            idx++
        }
        let createdConstant282 = builder.CreateConstant(ty,
            StringLiteral(unsafe { String.fromUtf8Unchecked(out.toArray()) }), parent)
        insertExpr(createdConstant282)
        return ExprResultAsValue(createdConstant282)
    }

    private func ConvertTupleToChir(ty: Type, val: InterpreterValue,
        insertExpr: (Expression) -> Unit, parent: Block): Option<Value> {
        if (val.kind != InterpreterValueKind.ITUPLE) {
            return None
        }
        let elementTys = if (ty.GetTypeKind() == TypeKind.TYPE_STRUCT) {
            if (let Some(customTy) <- (ty as CustomType)) {
                customTy.GetInstantiatedMemberTys(builder)
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
            let elementVal = ConvertToChir(elementTys[idx], elementVals[idx], insertExpr, parent) ?? return None
            elements.add(elementVal)
            idx++
        }
        if (ty.IsStruct()) {
            let refTy = builder.context.GetRefTy(ty)
            let createdAllocate312 = builder.CreateAllocate(refTy, ty, parent)
            insertExpr(createdAllocate312)
            let allocate = ExprResultAsValue(createdAllocate312) ?? return None
            var fieldIdx: Int64 = 0
            while (fieldIdx < elements.size) {
                let path = ArrayList<UInt64>()
                path.add(UInt64(fieldIdx))
                let createdStoreElementRef317 = builder.CreateStoreElementRef(elements[fieldIdx], allocate, path, parent)
                insertExpr(createdStoreElementRef317)
                fieldIdx++
            }
            let createdLoad320 = builder.CreateLoad(ty, allocate, parent)
            insertExpr(createdLoad320)
            return ExprResultAsValue(createdLoad320)
        }
        let createdTuple322 = builder.CreateTuple(ty, elements, parent)
        insertExpr(createdTuple322)
        return ExprResultAsValue(createdTuple322)
    }

    private func ConvertEnumToChir(ty: EnumType, val: InterpreterValue,
        insertExpr: (Expression) -> Unit, parent: Block): Option<Value> {
        let selectorTy = builder.context.ToSelectorType(GetEnumSelectorType(ty.GetEnumDef()))
        if (ty.GetEnumDef().IsAllCtorsTrivial()) {
            if (!val.IsIntLike() && val.kind != InterpreterValueKind.IBOOL) {
                return None
            }
            let selector = if (selectorTy.IsBoolean()) {
                let createdConstant332 = builder.CreateConstant(selectorTy, BoolLiteral(if (val.kind == InterpreterValueKind.IBOOL) {
                    val.GetBool()
                } else {
                    val.GetInt() != 0
                }), parent)
                insertExpr(createdConstant332)
                ExprResultAsValue(createdConstant332) ?? return None
            } else {
                let createdConstant338 = builder.CreateConstant(selectorTy, IntLiteral(val.GetInt()), parent)
                insertExpr(createdConstant338)
                ExprResultAsValue(createdConstant338) ?? return None
            }
            let createdTypeCast340 = builder.CreateTypeCast(ty, selector, parent)
            insertExpr(createdTypeCast340)
            return ExprResultAsValue(createdTypeCast340)
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
            elements.add(ConvertToChir(selectorTy, elementVals[0], insertExpr, parent) ?? return None)
            if (elementVals[0].GetBool()) { 1 } else { 0 }
        } else {
            if (!elementVals[0].IsIntLike()) {
                return None
            }
            elements.add(ConvertToChir(selectorTy, elementVals[0], insertExpr, parent) ?? return None)
            elementVals[0].GetInt()
        }
        let ctorInfos = ty.GetConstructorInfos(builder)
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
            let elementVal = ConvertToChir(elementTys[idx], elementVals[idx + 1], insertExpr, parent) ?? return None
            elements.add(elementVal)
            idx++
        }
        let createdTuple388 = builder.CreateTuple(ty, elements, parent)
        insertExpr(createdTuple388)
        return ExprResultAsValue(createdTuple388)
    }

    private func ConvertRefToChir(ty: RefType, val: InterpreterValue,
        insertExpr: (Expression) -> Unit, parent: Block): Option<Value> {
        let referencedType = ty.GetBaseType()
        let valContent = interpreter.DereferenceValue(val) ?? return None
        return match (referencedType.GetTypeKind()) {
            case TypeKind.TYPE_CLASS =>
                if (valContent.kind != InterpreterValueKind.IOBJECT) {
                    return None
                }
                var classType = (referencedType as ClassType).getOrThrow()
                let classInfo = interpreter.GetBCHIR().GetClass(valContent.GetClassId()) ?? return None
                let valClassName = classInfo.mangledName
                var refType = ty
                var needCast = false
                if (valClassName != classType.GetClassDef().GetIdentifierWithoutPrefix()) {
                    needCast = true
                    classType = FindClassType(valClassName) ?? return None
                    refType = builder.context.GetRefTy(classType)
                }
                let allocExpr = builder.CreateAllocate(refType, classType, parent)
                insertExpr(allocExpr)
                let classVal = ExprResultAsValue(allocExpr) ?? return None
                let members = classType.GetClassDef().GetAllInstanceVars()
                let content = valContent.GetElementsRef()
                CJC_ASSERT(members.size == content.size)
                var idx: Int64 = 0
                while (idx < members.size) {
                    let memberVal = ConvertToChir(members[idx].ty, content[idx], insertExpr, parent) ?? return None
                    let path = ArrayList<UInt64>()
                    path.add(UInt64(idx))
                    let createdStoreElementRef419 = builder.CreateStoreElementRef(memberVal, classVal, path, parent)
                    insertExpr(createdStoreElementRef419)
                    idx++
                }
                if (needCast) {
                    let createdTypeCast423 = builder.CreateTypeCast(ty, classVal, parent)
                    insertExpr(createdTypeCast423)
                    return ExprResultAsValue(createdTypeCast423)
                }
                Some(classVal)
            case _ => None
        }
    }

    private func FindClassType(mangledName: String): Option<ClassType> {
        var resultClassDef: Option<ClassDef> = None
        for (classDef in pkg.GetClasses()) {
            if (mangledName == classDef.GetIdentifierWithoutPrefix()) {
                resultClassDef = classDef
                break
            }
        }
        if (let None <- resultClassDef) {
            for (classDef in pkg.GetImportedClasses()) {
                if (mangledName == classDef.GetIdentifierWithoutPrefix()) {
                    resultClassDef = classDef
                    break
                }
            }
        }
        let classDef = resultClassDef ?? return None
        if (!classDef.GetGenericTypeParams().isEmpty()) {
            return None
        }
        return builder.context.GetClassTy(classDef, ArrayList<Type>())
    }

    private func ConvertArrayToChir(ty: VArrayType, val: InterpreterValue,
        insertExpr: (Expression) -> Unit, parent: Block): Option<Value> {
        if (val.kind != InterpreterValueKind.IARRAY) {
            return None
        }
        let elementVals = val.GetElementsRef()
        let elements = ArrayList<Value>()
        for (elementVal in elementVals) {
            elements.add(ConvertToChir(ty.GetElementType(), elementVal, insertExpr, parent) ?? return None)
        }
        let createdVArray462 = builder.CreateVArray(ty, elements, parent)
        insertExpr(createdVArray462)
        return ExprResultAsValue(createdVArray462)
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
