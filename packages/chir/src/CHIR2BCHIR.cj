package cangjie_compiler::chir

import std.collection.*

public class CHIR2BCHIRContext {
    public let definition: BCHIRDefinition = BCHIRDefinition()
    public var localVarId: Int64 = 0
    public let valueToLocal: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    public let blockToIndex: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    public let blockPlaceholders: HashMap<Int64, ArrayList<Int64>> = HashMap<Int64, ArrayList<Int64>>()
}

public class CHIR2BCHIR {
    private let bchir: BCHIR
    private let stringMemo: HashMap<String, Int64> = HashMap<String, Int64>()
    private let typeMemo: HashMap<Int64, Int64> = HashMap<Int64, Int64>()

    public init(bchir: BCHIR) {
        this.bchir = bchir
    }

    public static func CompilePackage(chirPkg: Package, destBchir: BCHIR, forConstEval!: Bool = false): Unit {
        let compiler = CHIR2BCHIR(destBchir)
        compiler.TranslatePackage(chirPkg, forConstEval: forConstEval)
    }

    public func TranslatePackage(chirPkg: Package, forConstEval!: Bool = false): Unit {
        bchir.packageName = chirPkg.GetName()
        if (chirPkg.GetName() == "std.core") {
            bchir.SetAsCore()
        }
        TranslateClassesLike(chirPkg)
        TranslateGlobalVars(chirPkg, forConstEval: forConstEval)
        TranslateFunctions(chirPkg, forConstEval: forConstEval)
        if (let Some(initFunc) <- chirPkg.GetPackageInitFunc()) {
            bchir.SetGlobalInitFunc(BCHIRMangledName(initFunc))
        }
        if (let Some(literalInitFunc) <- chirPkg.GetPackageLiteralInitFunc()) {
            bchir.SetGlobalInitLiteralFunc(BCHIRMangledName(literalInitFunc))
        }
    }

    private func TranslateClassesLike(chirPkg: Package): Unit {
        for (classDef in chirPkg.GetAllClassDef()) {
            let info = BCHIRSClassInfo()
            if (let Some(superClass) <- classDef.GetSuperClassDef()) {
                info.superClasses.add(BCHIRMangledName(superClass))
            }
            for (interfaceDef in classDef.GetImplementedInterfaceDefs()) {
                info.superClasses.add(BCHIRMangledName(interfaceDef))
            }
            CollectMethods(classDef, info)
            bchir.AddSClass(BCHIRMangledName(classDef), info)
        }
        for (structDef in chirPkg.GetAllStructDef()) {
            let info = BCHIRSClassInfo()
            CollectMethods(structDef, info)
            bchir.AddSClass(BCHIRMangledName(structDef), info)
        }
        for (enumDef in chirPkg.GetAllEnumDef()) {
            let info = BCHIRSClassInfo()
            CollectMethods(enumDef, info)
            bchir.AddSClass(BCHIRMangledName(enumDef), info)
        }
        for (extendDef in chirPkg.GetAllExtendDef()) {
            if (let Some(extendedTy) <- extendDef.extendedType) {
                let name = extendedTy.ToString()
                let info = bchir.GetSClass(name) ?? BCHIRSClassInfo()
                CollectMethods(extendDef, info)
                bchir.AddSClass(name, info)
            }
        }
    }

    private func CollectMethods(def: CustomTypeDef, info: BCHIRSClassInfo): Unit {
        for (method in def.GetMethods()) {
            let methodName = method.GetSrcCodeIdentifier()
            let key = if (methodName.isEmpty()) { BCHIRMangledName(method) } else { methodName }
            info.vtable[key] = BCHIRMangledName(method)
        }
        for (extendDef in def.GetExtends()) {
            for (method in extendDef.GetMethods()) {
                let methodName = method.GetSrcCodeIdentifier()
                let key = if (methodName.isEmpty()) { BCHIRMangledName(method) } else { methodName }
                info.vtable[key] = BCHIRMangledName(method)
            }
        }
    }

    private func TranslateGlobalVars(chirPkg: Package, forConstEval!: Bool): Unit {
        for (globalVar in chirPkg.GetGlobalVarsWithInit()) {
            if (forConstEval && !globalVar.IsCompileTimeValue()) {
                continue
            }
            let context = TranslateGlobalVar(globalVar)
            bchir.AddGlobalVar(BCHIRMangledName(globalVar), context.definition)
        }
        bchir.SetNumGlobalVars(chirPkg.GetGlobalVars().size)
    }

    private func TranslateGlobalVar(globalVar: GlobalVar): CHIR2BCHIRContext {
        let context = CHIR2BCHIRContext()
        if (let Some(initValue) <- globalVar.GetInitializerValue()) {
            if (!TranslateInitializerValue(context, initValue)) {
                context.definition.PushOp(OpCode.NULLPTR)
            }
        } else {
            context.definition.PushOp(OpCode.NULLPTR)
        }
        return context
    }

    private func TranslateInitializerValue(context: CHIR2BCHIRContext, value: Value): Bool {
        if (let Some(local) <- value.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                if (let Some(constant) <- (expr as Constant)) {
                    TranslateLiteralValue(context, constant.literal)
                    return true
                }
                let eval = ConstEval()
                if (let Some(literal) <- eval.EvaluateToLiteral(expr)) {
                    TranslateLiteralValue(context, literal)
                    return true
                }
            }
        }
        if (let Some(globalVar) <- value.AsGlobalVar()) {
            if (let Some(nested) <- globalVar.GetInitializerValue()) {
                return TranslateInitializerValue(context, nested)
            }
        }
        return false
    }

    private func TranslateFunctions(chirPkg: Package, forConstEval!: Bool): Unit {
        for (function in chirPkg.GetGlobalFuncsWithBody()) {
            if (forConstEval && !function.IsCompileTimeValue() && function.GetFuncKind() != FuncKind.MAIN_ENTRY) {
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
            context.definition.PushCell(if (boolLiteral.value) { 1 } else { 0 })
        } else if (let Some(intLiteral) <- (literal as IntLiteral)) {
            let opCode = BCHIRPrimitiveTypeKindToOpCode(LiteralIntType())
            context.definition.PushOp(if (opCode == OpCode.INVALID) { OpCode.INT64 } else { opCode })
            if (BCHIRIsWideIntegerOp(opCode) || opCode == OpCode.INVALID) {
                context.definition.Push8Bytes(intLiteral.value)
            } else {
                context.definition.PushCell(intLiteral.value)
            }
        } else if (let Some(floatLiteral) <- (literal as FloatLiteral)) {
            context.definition.PushOp(OpCode.FLOAT64)
            context.definition.Push8Bytes(Int64(floatLiteral.value))
        } else if (let Some(runeLiteral) <- (literal as RuneLiteral)) {
            context.definition.PushOp(OpCode.RUNE)
            context.definition.PushCell(runeLiteral.value.toString().hashCode())
        } else if (let Some(stringLiteral) <- (literal as StringLiteral)) {
            context.definition.PushOp(OpCode.STRING)
            context.definition.PushCell(GetStringIdx(stringLiteral.value))
        } else if (literal.IsNullLit()) {
            context.definition.PushOp(OpCode.NULLPTR)
        } else if (literal.IsUnitLit()) {
            context.definition.PushOp(OpCode.UNIT)
        } else {
            context.definition.PushOp(OpCode.NOT_SUPPORTED)
        }
    }

    private func LiteralIntType(): TypeKind {
        return TypeKind.TYPE_INT64
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
        let key = ty.Hash()
        if (let Some(index) <- typeMemo.get(key)) {
            return index
        }
        let next = bchir.AddType(ty)
        typeMemo[key] = next
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
