package cangjie_compiler::chir

import std.collection.*

private class GenericInstantiationBinding {
    public let params: ArrayList<GenericType> = ArrayList<GenericType>()
    public let args: ArrayList<Type> = ArrayList<Type>()

    public init() {}

    public func IsEmpty(): Bool {
        return params.isEmpty() || args.isEmpty()
    }

    public func Add(param: GenericType, arg: Type): Unit {
        var idx: Int64 = 0
        while (idx < params.size) {
            if (params[idx].IsEqual(param)) {
                args[idx] = arg
                return
            }
            idx++
        }
        params.add(param)
        args.add(arg)
    }

    public func Key(fn: Function): String {
        return "${fn.nodeId}:" + TypeListKey(args)
    }
}

private class GenericInstantiationPass {
    private let builder: CHIRBuilder
    private let cache: HashMap<String, Function> = HashMap<String, Function>()

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func Run(pkg: Package): Unit {
        var changed = true
        while (changed) {
            changed = false
            let funcs = pkg.GetGlobalFunctions()
            for (fn in funcs) {
                if (let Some(body) <- fn.GetBody()) {
                    changed = RewriteAppliesInBlockGroup(pkg, body) || changed
                }
            }
        }
        DropGenericTemplateBodies(pkg)
    }

    private func RewriteAppliesInBlockGroup(pkg: Package, group: BlockGroup): Bool {
        var changed = false
        for (block in group.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (let Some(apply) <- (expr as Apply)) {
                    changed = RewriteApply(pkg, apply) || changed
                }
                var groupIdx: Int64 = 0
                while (groupIdx < expr.GetNumOfBlockGroups()) {
                    changed = RewriteAppliesInBlockGroup(pkg, expr.GetBlockGroup(groupIdx)) || changed
                    groupIdx++
                }
            }
        }
        return changed
    }

    private func RewriteApply(pkg: Package, apply: Apply): Bool {
        let callee = apply.GetCallee().AsFunction() ?? return false
        if (callee.GetGenericDecl().isSome()) {
            return false
        }
        if (callee.GetBody().isNone()) {
            return false
        }
        let binding = BuildBinding(callee, apply)
        if (binding.IsEmpty()) {
            return false
        }
        let instantiated = InstantiateFunction(pkg, callee, binding)
        if (instantiated.nodeId == callee.nodeId) {
            return false
        }
        apply.ReplaceOperand(0, instantiated)
        if (let Some(result) <- apply.GetResult()) {
            if (let Some(resultTy) <- result.GetType()) {
                result.SetType(SubstituteType(resultTy, binding.params, binding.args))
            }
        }
        return true
    }

    private func BuildBinding(callee: Function, apply: Apply): GenericInstantiationBinding {
        let binding = GenericInstantiationBinding()
        AddParentBinding(callee, apply, binding)
        AddFunctionExplicitBinding(callee, apply, binding)
        AddFunctionInferredBinding(callee, apply, binding)
        return binding
    }

    private func AddParentBinding(callee: Function, apply: Apply, binding: GenericInstantiationBinding): Unit {
        let parentDef = callee.GetParentCustomTypeDef() ?? return
        let parentParams = parentDef.GetGenericTypeParams()
        if (parentParams.isEmpty()) {
            return
        }
        if (let Some(thisTy) <- ResolveApplyThisType(apply)) {
            if (let Some(customTy) <- (thisTy.StripAllRefs() as CustomType)) {
                let parentArgs = customTy.GetGenericArgs()
                var idx: Int64 = 0
                while (idx < parentParams.size && idx < parentArgs.size) {
                    binding.Add(parentParams[idx], parentArgs[idx])
                    idx++
                }
            }
        }
    }

    private func ResolveApplyThisType(apply: Apply): Option<Type> {
        if (let Some(thisTy) <- apply.GetThisType()) {
            return Some(thisTy)
        }
        let args = apply.GetArgs()
        if (!args.isEmpty()) {
            return args[0].GetType()
        }
        return None
    }

    private func AddFunctionExplicitBinding(callee: Function, apply: Apply,
        binding: GenericInstantiationBinding): Unit {
        let params = callee.GetGenericTypeParams()
        let args = apply.GetInstantiatedTypeArgs()
        var idx: Int64 = 0
        while (idx < params.size && idx < args.size) {
            binding.Add(params[idx], args[idx])
            idx++
        }
    }

    private func AddFunctionInferredBinding(callee: Function, apply: Apply,
        binding: GenericInstantiationBinding): Unit {
        let genericParams = callee.GetGenericTypeParams()
        if (genericParams.isEmpty()) {
            return
        }
        let funcTy = callee.GetFuncType() ?? return
        let paramTys = funcTy.GetParamTypes()
        let argValues = apply.GetArgs()
        var idx: Int64 = 0
        while (idx < paramTys.size && idx < argValues.size) {
            if (let Some(argTy) <- argValues[idx].GetType()) {
                CollectBindingFromTypes(paramTys[idx], argTy, genericParams, binding)
            }
            idx++
        }
    }

    private func CollectBindingFromTypes(pattern: Type, actual: Type, genericParams: ArrayList<GenericType>,
        binding: GenericInstantiationBinding): Unit {
        if (let Some(genericTy) <- (pattern as GenericType)) {
            if (ContainsGenericParam(genericParams, genericTy)) {
                binding.Add(genericTy, actual)
            }
            return
        }
        if (let Some(patternRef) <- (pattern as RefType)) {
            let actualBase = if (let Some(actualRef) <- (actual as RefType)) {
                actualRef.GetBaseType()
            } else {
                actual
            }
            CollectBindingFromTypes(patternRef.GetBaseType(), actualBase, genericParams, binding)
            return
        }
        if (let Some(patternCustom) <- (pattern as CustomType)) {
            if (let Some(actualCustom) <- (actual as CustomType)) {
                if (patternCustom.GetCustomTypeDef().nodeId == actualCustom.GetCustomTypeDef().nodeId) {
                    CollectBindingFromTypeLists(patternCustom.GetGenericArgs(), actualCustom.GetGenericArgs(),
                        genericParams, binding)
                }
            }
            return
        }
        if (let Some(patternTuple) <- (pattern as TupleType)) {
            if (let Some(actualTuple) <- (actual as TupleType)) {
                CollectBindingFromTypeLists(patternTuple.GetTypeArgs(), actualTuple.GetTypeArgs(),
                    genericParams, binding)
            }
            return
        }
        if (let Some(patternFunc) <- (pattern as FuncType)) {
            if (let Some(actualFunc) <- (actual as FuncType)) {
                CollectBindingFromTypeLists(patternFunc.GetParamTypes(), actualFunc.GetParamTypes(),
                    genericParams, binding)
                CollectBindingFromTypes(patternFunc.GetReturnType(), actualFunc.GetReturnType(),
                    genericParams, binding)
            }
            return
        }
        if (let Some(patternArray) <- (pattern as RawArrayType)) {
            if (let Some(actualArray) <- (actual as RawArrayType)) {
                CollectBindingFromTypes(patternArray.GetElementType(), actualArray.GetElementType(),
                    genericParams, binding)
            }
        }
    }

    private func CollectBindingFromTypeLists(patterns: ArrayList<Type>, actuals: ArrayList<Type>,
        genericParams: ArrayList<GenericType>, binding: GenericInstantiationBinding): Unit {
        var idx: Int64 = 0
        while (idx < patterns.size && idx < actuals.size) {
            CollectBindingFromTypes(patterns[idx], actuals[idx], genericParams, binding)
            idx++
        }
    }

    private func InstantiateFunction(pkg: Package, source: Function,
        binding: GenericInstantiationBinding): Function {
        let key = binding.Key(source)
        if (let Some(existing) <- cache.get(key)) {
            return existing
        }

        let sourceTy = source.GetFuncType() ?? return source
        let instTy = SubstituteType(sourceTy, binding.params, binding.args) as FuncType ??
            throw IllegalArgumentException("generic function instantiation did not produce FuncType")
        let inst = builder.CreateFunction(instTy, InstantiatedFunctionIdentifier(source, binding),
            srcCodeIdentifier: source.GetSrcCodeIdentifier(),
            rawMangledName: InstantiatedFunctionIdentifier(source, binding),
            packageName: source.GetPackageName())
        inst.CopyBaseInfoFrom(source)
        inst.SetFuncKind(source.GetFuncKind())
        inst.SetGenericDecl(source)
        if (let Some(parentDef) <- source.GetParentCustomTypeDef()) {
            inst.SetOuterDeclaredOrExtendedDef(parentDef)
        }
        CopyPrintDirectives(source, inst)
        CloneParameters(source, inst, binding)
        if (let Some(sourceBody) <- source.GetBody()) {
            let body = builder.CreateBlockGroup(inst)
            inst.InitBody(body)
            let cloneResult = BlockGroupCopyHelper(builder).CloneBlockGroup(sourceBody, body)
            RemapFunctionParameters(source, inst, cloneResult.GetBlocks())
            if (let Some(clonedReturn) <- cloneResult.GetReturnValue()) {
                inst.SetReturnValue(clonedReturn)
            }
            SubstituteFunctionValueTypes(inst, binding)
        }
        pkg.AddGlobalFunc(inst)
        cache[key] = inst
        return inst
    }

    private func InstantiatedFunctionIdentifier(source: Function, binding: GenericInstantiationBinding): String {
        let keyHash = PositiveHash(binding.Key(source))
        return source.GetIdentifierWithoutPrefix() + "$gi$${keyHash}"
    }

    private func PositiveHash(value: String): Int64 {
        let hash = value.hashCode()
        if (hash < 0) {
            return -hash
        }
        return hash
    }

    private func CloneParameters(source: Function, inst: Function,
        binding: GenericInstantiationBinding): Unit {
        for (param in source.GetParams()) {
            let paramTy = SubstituteType(param.GetType() ?? builder.context.GetInvalidTy(), binding.params, binding.args)
            let cloned = builder.CreateParameter(paramTy, param.GetIdentifier(), inst)
            cloned.SetSrcCodeIdentifier(param.GetSrcCodeIdentifier())
            cloned.CopyBaseInfoFrom(param)
        }
    }

    private func RemapFunctionParameters(source: Function, inst: Function, blocks: ArrayList<Block>): Unit {
        let valueMap = HashMap<Int64, Value>()
        let sourceParams = source.GetParams()
        let instParams = inst.GetParams()
        var idx: Int64 = 0
        while (idx < sourceParams.size && idx < instParams.size) {
            valueMap[sourceParams[idx].nodeId] = instParams[idx]
            idx++
        }
        BlockGroupCopyHelper.ReplaceExprOperands(blocks, valueMap)
    }

    private func SubstituteFunctionValueTypes(fn: Function, binding: GenericInstantiationBinding): Unit {
        if (let Some(fnTy) <- fn.GetFuncType()) {
            fn.SetType(SubstituteType(fnTy, binding.params, binding.args))
        }
        for (param in fn.GetParams()) {
            if (let Some(paramTy) <- param.GetType()) {
                param.SetType(SubstituteType(paramTy, binding.params, binding.args))
            }
        }
        if (let Some(body) <- fn.GetBody()) {
            SubstituteBlockGroupValueTypes(body, binding)
        }
    }

    private func SubstituteBlockGroupValueTypes(group: BlockGroup, binding: GenericInstantiationBinding): Unit {
        for (block in group.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (let Some(result) <- expr.GetResult()) {
                    if (let Some(resultTy) <- result.GetType()) {
                        result.SetType(SubstituteType(resultTy, binding.params, binding.args))
                    }
                }
                SubstituteExpressionStoredTypes(expr, binding)
                var groupIdx: Int64 = 0
                while (groupIdx < expr.GetNumOfBlockGroups()) {
                    SubstituteBlockGroupValueTypes(expr.GetBlockGroup(groupIdx), binding)
                    groupIdx++
                }
            }
        }
    }

    private func SubstituteExpressionStoredTypes(expr: Expression, binding: GenericInstantiationBinding): Unit {
        if (let Some(allocate) <- (expr as Allocate)) {
            allocate.SetType(SubstituteType(allocate.GetType(), binding.params, binding.args))
        } else if (let Some(rttiStatic) <- (expr as GetRTTIStatic)) {
            rttiStatic.SetRTTIType(SubstituteType(rttiStatic.GetRTTIType(), binding.params, binding.args))
        } else if (let Some(instanceOf) <- (expr as InstanceOf)) {
            instanceOf.SetTestedType(SubstituteType(instanceOf.GetType(), binding.params, binding.args))
        } else if (let Some(rawArray) <- (expr as RawArrayAllocate)) {
            rawArray.SetElementType(SubstituteType(rawArray.GetElementType(), binding.params, binding.args))
        }
    }

    private func CopyPrintDirectives(source: Function, inst: Function): Unit {
        for (value in source.printStrings) { inst.printStrings.add(value) }
        for (value in source.printNewlines) { inst.printNewlines.add(value) }
        for (value in source.printIsInt) { inst.printIsInt.add(value) }
        for (value in source.runtimePrintValueIds) { inst.runtimePrintValueIds.add(value) }
        for (value in source.runtimePrintNewlines) { inst.runtimePrintNewlines.add(value) }
        for (value in source.runtimePrintIsStr) { inst.runtimePrintIsStr.add(value) }
        for (value in source.runtimePrintStrings) { inst.runtimePrintStrings.add(value) }
        for (value in source.runtimePrintIsBool) { inst.runtimePrintIsBool.add(value) }
        for (value in source.runtimePrintIsStrValue) { inst.runtimePrintIsStrValue.add(value) }
        for (value in source.runtimePrintIsFloat) { inst.runtimePrintIsFloat.add(value) }
    }

    private func DropGenericTemplateBodies(pkg: Package): Unit {
        let kept = ArrayList<Function>()
        for (fn in pkg.GetGlobalFunctions()) {
            if (!ShouldDropGenericTemplate(fn)) {
                kept.add(fn)
            }
        }
        pkg.SetAllGlobalFuncs(kept)
    }

    private func ShouldDropGenericTemplate(fn: Function): Bool {
        if (fn.GetBody().isNone() || fn.GetGenericDecl().isSome()) {
            return false
        }
        if (!fn.GetGenericTypeParams().isEmpty()) {
            return true
        }
        if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
            return !parentDef.GetGenericTypeParams().isEmpty()
        }
        return false
    }
}

private func ContainsGenericParam(values: ArrayList<GenericType>, ty: GenericType): Bool {
    for (value in values) {
        if (value.IsEqual(ty)) {
            return true
        }
    }
    return false
}

private func SubstituteType(ty: Type, genericParams: ArrayList<GenericType>, replacements: ArrayList<Type>): Type {
    if (genericParams.isEmpty() || replacements.isEmpty()) {
        return ty
    }
    if (let Some(genericTy) <- (ty as GenericType)) {
        var idx: Int64 = 0
        while (idx < genericParams.size && idx < replacements.size) {
            if (genericTy.IsEqual(genericParams[idx])) {
                return replacements[idx]
            }
            idx++
        }
        return ty
    }
    if (let Some(refTy) <- (ty as RefType)) {
        return RefType(SubstituteType(refTy.GetBaseType(), genericParams, replacements))
    }
    if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
        return RawArrayType(SubstituteType(rawArrayTy.GetElementType(), genericParams, replacements),
            dims: rawArrayTy.GetDims())
    }
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        return VArrayType(SubstituteType(varrayTy.GetElementType(), genericParams, replacements), varrayTy.size)
    }
    if (let Some(pointerTy) <- (ty as CPointerType)) {
        return CPointerType(SubstituteType(pointerTy.GetElementType(), genericParams, replacements))
    }
    if (let Some(boxTy) <- (ty as BoxType)) {
        return BoxType(SubstituteType(boxTy.GetBaseType(), genericParams, replacements))
    }
    if (let Some(tupleTy) <- (ty as TupleType)) {
        return TupleType(SubstituteTypeList(tupleTy.GetTypeArgs(), genericParams, replacements))
    }
    if (let Some(funcTy) <- (ty as FuncType)) {
        return FuncType(SubstituteTypeList(funcTy.GetParamTypes(), genericParams, replacements),
            SubstituteType(funcTy.GetReturnType(), genericParams, replacements),
            hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
    }
    if (let Some(structTy) <- (ty as StructType)) {
        return StructType(structTy.GetStructDef(),
            SubstituteTypeList(structTy.GetGenericArgs(), genericParams, replacements))
    }
    if (let Some(classTy) <- (ty as ClassType)) {
        return ClassType(classTy.GetClassDef(),
            SubstituteTypeList(classTy.GetGenericArgs(), genericParams, replacements))
    }
    if (let Some(enumTy) <- (ty as EnumType)) {
        return EnumType(enumTy.GetEnumDef(),
            SubstituteTypeList(enumTy.GetGenericArgs(), genericParams, replacements))
    }
    return ty
}

private func SubstituteTypeList(values: ArrayList<Type>, genericParams: ArrayList<GenericType>,
    replacements: ArrayList<Type>): ArrayList<Type> {
    let out = ArrayList<Type>()
    for (value in values) {
        out.add(SubstituteType(value, genericParams, replacements))
    }
    return out
}

public func InstantiateGenericFunctionsForPackage(builder: CHIRBuilder, pkg: Package): Unit {
    GenericInstantiationPass(builder).Run(pkg)
}
