package cangjie_compiler::chir

import std.collection.*

private let GENERIC_VIRTUAL_FUNC: String = "$GenericVirtualFunc"
private let INST_VIRTUAL_FUNC: String = "$InstVirtualFunc"
private let CC_GENERIC_BASE_PREFIX: String = "$Cg"
private let CC_INSTANTIATED_BASE_PREFIX: String = "$Ci"
private let CC_FUNC_IMPL_PREFIX: String = "$Cf"
private let CC_LAMBDA_IMPL_PREFIX: String = "$Cl"
private let CC_CAPTURED_PREFIX: String = "$Captured_"
private let CC_FUNC_PREFIX: String = "_CC"
private let MANGLE_CANGJIE_PREFIX: String = "_C"
private let CC_AUTO_ENV_CLASS_ANNOTATION: String = "IsAutoEnvClass"
private let CC_AUTO_ENV_BASE_ANNOTATION: String = "IsAutoEnvBase"
private let CC_AUTO_ENV_GENERIC_BASE_ANNOTATION: String = "IsAutoEnvGenericBase"
private let CC_AUTO_ENV_INST_BASE_ANNOTATION: String = "IsAutoEnvInstBase"
private let CC_AUTO_ENV_IMPL_ANNOTATION: String = "IsAutoEnvImpl"

public class ClosureConversion {
    private let builder: CHIRBuilder
    private var pkg: Option<Package> = None
    private let convertedLambdaExpressions: ArrayList<Lambda> = ArrayList<Lambda>()
    private let capturedValues: ArrayList<Value> = ArrayList<Value>()
    private let genericAutoEnvBaseDefs: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let instAutoEnvBaseDefs: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let autoEnvImplDefs: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let boxClassMap: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let convertedCache: HashMap<Int64, Function> = HashMap<Int64, Function>()
    private let duplicateLambdaName: HashMap<String, Int64> = HashMap<String, Int64>()
    private let typeConvertMap: HashMap<String, Type> = HashMap<String, Type>()

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package): Unit {
        this.pkg = pkg
        let nestedFuncs = CollectNestedFunctions(pkg)
        ConvertNestedFunctions(nestedFuncs)
        ConvertGlobalFunctions(pkg)
        LiftType(pkg)
        ConvertExpressions(pkg)
    }

    public func GetConvertedLambdaExpressions(): ArrayList<Lambda> {
        let out = ArrayList<Lambda>()
        for (lambdaExpr in convertedLambdaExpressions) {
            out.add(lambdaExpr)
        }
        return out
    }

    public func GetCapturedValues(): ArrayList<Value> {
        return CopyValueList(capturedValues)
    }

    private func CurrentPackage(): Package {
        return pkg ?? throw IllegalStateException("ClosureConversion package is not initialized")
    }

    private func CollectNestedFunctions(pkg: Package): ArrayList<Lambda> {
        let nestedFuncs = ArrayList<Lambda>()
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (let Some(body) <- fn.GetBody()) {
                CollectNestedFunctionsInBlockGroup(body, nestedFuncs)
            }
        }
        return nestedFuncs
    }

    private func CollectNestedFunctionsInBlockGroup(group: BlockGroup, nestedFuncs: ArrayList<Lambda>): Unit {
        for (block in group.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        CollectNestedFunctionsInBlockGroup(lambdaBody, nestedFuncs)
                    }
                    nestedFuncs.add(lambdaExpr)
                } else {
                    for (subGroup in expr.GetBlockGroups()) {
                        CollectNestedFunctionsInBlockGroup(subGroup, nestedFuncs)
                    }
                }
            }
        }
    }

    private func ConvertNestedFunctions(funcs: ArrayList<Lambda>): Unit {
        for (lambdaFunc in funcs) {
            RecordDuplicateLambdaName(lambdaFunc)
            if (!ContainsLambda(convertedLambdaExpressions, lambdaFunc)) {
                convertedLambdaExpressions.add(lambdaFunc)
            }
            let funcTy = lambdaFunc.GetFuncType() ??
                throw IllegalStateException("ClosureConversion lambda has no function type")
            if (funcTy.IsCFunc()) {
                LiftNestedFunctionWithCFuncType(lambdaFunc)
                continue
            }
            let rawEnvs = lambdaFunc.GetCapturedVariables()
            let boxedEnvs = BoxAllMutableVars(rawEnvs)
            let autoEnvBaseDef = GetOrCreateAutoEnvBaseDef(funcTy)
            let autoEnvImplDef = GetOrCreateAutoEnvImplDef(lambdaFunc, autoEnvBaseDef, boxedEnvs)
            let result = lambdaFunc.GetResult() ??
                throw IllegalStateException("ClosureConversion lambda has no result")
            let users = result.GetUsers()
            for (user in users) {
                if (user.GetParentBlock().isSome()) {
                    ReplaceUserPoint(lambdaFunc, user, boxedEnvs, autoEnvImplDef)
                }
            }
            lambdaFunc.DetachLiftedBodyAndRemoveSelf()
        }
    }

    private func ConvertGlobalFunctions(pkg: Package): Unit {
        let funcs = pkg.GetGlobalFunctions(includePureAbstract: true)
        for (fn in funcs) {
            if (IsClosureConversionGeneratedFunction(fn)) {
                continue
            }
            if (fn.IsCFFIWrapper()) {
                continue
            }
            let funcTy = fn.GetFuncType() ?? continue
            if (funcTy.IsCFunc()) {
                continue
            }
            let users = fn.GetUsers()
            var converted = false
            for (user in users) {
                if (IsCalleeOfApply(user, fn)) {
                    continue
                }
                if (user.GetParentBlock().isNone()) {
                    continue
                }
                let autoEnvBaseDef = GetOrCreateAutoEnvBaseDef(funcTy)
                let autoEnvImplDef = GetOrCreateAutoEnvImplDef(fn, autoEnvBaseDef)
                ReplaceUserPoint(fn, user, autoEnvImplDef)
                converted = true
            }
            if (converted) {
                fn.EnableAttr(Attribute.BOXED)
            }
        }
    }

    private func LiftType(pkg: Package): Unit {
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            ConvertFunctionSignature(fn)
            if (let Some(body) <- fn.GetBody()) {
                ConvertBlockGroupTypes(body)
            }
            for (param in fn.GetParams()) {
                ConvertValueType(param)
            }
            if (let Some(retVal) <- fn.GetReturnValue()) {
                ConvertValueType(retVal)
            }
        }
        for (globalVar in pkg.GetGlobalVars()) {
            ConvertValueType(globalVar)
        }
        for (def in pkg.GetAllCustomTypeDef()) {
            ConvertCustomDefTypes(def)
        }
    }

    private func ConvertExpressions(pkg: Package): Unit {
        let funcs = pkg.GetGlobalFuncsWithBody()
        for (fn in funcs) {
            if (let Some(body) <- fn.GetBody()) {
                ConvertExpressionsInBlockGroup(body)
            }
        }
    }

    private func ConvertExpressionsInBlockGroup(group: BlockGroup): Unit {
        for (block in group.GetBlocks()) {
            let exprs = block.GetExpressions()
            for (expr in exprs) {
                if (expr.GetParentBlock().isNone()) {
                    continue
                }
                if (let Some(apply) <- (expr as Apply)) {
                    if (ApplyNeedConvertToInvoke(apply)) {
                        ConvertApplyToInvoke(apply)
                        continue
                    }
                }
                if (let Some(applyWithException) <- (expr as ApplyWithException)) {
                    if (ApplyWithExceptionNeedConvertToInvokeWithException(applyWithException)) {
                        ConvertApplyWithExceptionToInvokeWithException(applyWithException)
                        continue
                    }
                }
                for (subGroup in expr.GetBlockGroups()) {
                    ConvertExpressionsInBlockGroup(subGroup)
                }
            }
        }
    }

    private func ConvertBlockGroupTypes(group: BlockGroup): Unit {
        for (block in group.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                ConvertExpressionTypes(expr)
                for (subGroup in expr.GetBlockGroups()) {
                    ConvertBlockGroupTypes(subGroup)
                }
            }
        }
    }

    private func ConvertExpressionTypes(expr: Expression): Unit {
        if (let Some(result) <- expr.GetResult()) {
            ConvertValueType(result)
        }
        if (let Some(allocate) <- (expr as Allocate)) {
            allocate.SetType(ConvertTypeToClosureType(allocate.GetType()))
        } else if (let Some(rawArrayAllocate) <- (expr as RawArrayAllocate)) {
            rawArrayAllocate.SetElementType(ConvertTypeToClosureType(rawArrayAllocate.GetElementType()))
        } else if (let Some(getRTTIStatic) <- (expr as GetRTTIStatic)) {
            getRTTIStatic.SetRTTIType(ConvertTypeToClosureType(getRTTIStatic.GetRTTIType()))
        } else if (let Some(instanceOfExpr) <- (expr as InstanceOf)) {
            instanceOfExpr.SetTestedType(ConvertTypeToClosureType(instanceOfExpr.GetType()))
        }
        if (let Some(call) <- (expr as FuncCall)) {
            if (let Some(thisTy) <- call.GetThisType()) {
                call.SetThisType(ConvertTypeToClosureType(thisTy))
            }
        }
        if (let Some(callWithException) <- (expr as FuncCallWithException)) {
            if (let Some(thisTy2) <- callWithException.GetThisType()) {
                callWithException.SetThisType(ConvertTypeToClosureType(thisTy2))
            }
        }
    }

    private func ConvertCustomDefTypes(def: CustomTypeDef): Unit {
        let genericParams = def.GetGenericTypeParams()
        for (genericParam in genericParams) {
            let convertedBounds = ArrayList<Type>()
            for (bound in genericParam.GetUpperBounds()) {
                convertedBounds.add(ConvertTypeToClosureType(bound))
            }
            genericParam.SetUpperBounds(convertedBounds)
        }
        let vars = def.GetDirectInstanceVars()
        for (member in vars) {
            member.ty = ConvertTypeToClosureType(member.ty)
        }
        if (let Some(classDef) <- (def as ClassDef)) {
            if (let Some(superTy) <- classDef.GetSuperClassTy()) {
                if (let Some(convertedSuper) <- (ConvertTypeToClosureType(superTy) as ClassType)) {
                    classDef.SetSuperClassTy(convertedSuper)
                }
            }
        }
        let interfaces = def.GetImplementedInterfaceTys()
        if (!interfaces.isEmpty()) {
            let retained = ArrayList<ClassType>()
            for (interfaceTy in interfaces) {
                if (let Some(convertedInterface) <- (ConvertTypeToClosureType(interfaceTy) as ClassType)) {
                    retained.add(convertedInterface)
                }
            }
            // Existing CHIR does not expose a replace API for interface types. The translated programs
            // that use closures through interfaces get their function-typed members converted above.
            let _ = retained
        }
    }

    private func ConvertFunctionSignature(fn: Function): Unit {
        if (let Some(funcTy) <- fn.GetFuncType()) {
            fn.SetType(ConvertFuncArgsAndRetType(funcTy))
        }
    }

    private func ConvertValueType(value: Value): Unit {
        if (value.AsFunction().isSome()) {
            return
        }
        if (let Some(valueTy) <- value.GetType()) {
            value.SetType(ConvertTypeToClosureType(valueTy))
        }
    }

    private func ConvertTypeToClosureType(ty: Type): Type {
        if (ty.IsPrimitive() || ty.IsInvalid() || ty.IsAny() || ty.IsVoid() || ty.IsCFunc() ||
            ty.IsCString() || ty.IsThis()) {
            return ty
        }
        if (ty.IsGeneric()) {
            return ty
        }
        let key = "cc:" + ty.ToString()
        if (let Some(cached) <- typeConvertMap.get(key)) {
            return cached
        }
        var converted: Type = ty
        if (let Some(tupleTy) <- (ty as TupleType)) {
            converted = builder.context.GetTupleTy(ConvertTypeArgs(tupleTy.GetTypeArgs()))
        } else if (let Some(funcTy) <- (ty as FuncType)) {
            converted = ConvertFuncType(funcTy)
        } else if (let Some(structTy) <- (ty as StructType)) {
            converted = builder.context.GetStructTy(structTy.GetStructDef(), ConvertTypeArgs(structTy.GetGenericArgs()))
        } else if (let Some(classTy) <- (ty as ClassType)) {
            converted = builder.context.GetClassTy(classTy.GetClassDef(), ConvertTypeArgs(classTy.GetGenericArgs()))
        } else if (let Some(enumTy) <- (ty as EnumType)) {
            converted = builder.context.GetEnumTy(enumTy.GetEnumDef(), ConvertTypeArgs(enumTy.GetGenericArgs()))
        } else if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            converted = builder.context.GetRawArrayTy(ConvertTypeToClosureType(rawArrayTy.GetElementType()),
                dims: rawArrayTy.GetDims())
        } else if (let Some(varrayTy) <- (ty as VArrayType)) {
            converted = builder.context.GetVArrayTy(ConvertTypeToClosureType(varrayTy.GetElementType()),
                varrayTy.size)
        } else if (let Some(pointerTy) <- (ty as CPointerType)) {
            converted = builder.context.GetCPointerTy(ConvertTypeToClosureType(pointerTy.GetElementType()))
        } else if (let Some(refTy) <- (ty as RefType)) {
            converted = builder.context.GetRefTy(ConvertTypeToClosureType(refTy.GetBaseType()))
        } else if (let Some(boxTy) <- (ty as BoxType)) {
            converted = builder.context.GetBoxTy(ConvertTypeToClosureType(boxTy.GetBaseType()))
        }
        typeConvertMap[key] = converted
        return converted
    }

    private func ConvertTypeArgs(types: ArrayList<Type>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (ty in types) {
            out.add(ConvertTypeToClosureType(ty))
        }
        return out
    }

    private func ConvertFuncType(funcTy: FuncType): Type {
        if (funcTy.IsCFunc()) {
            return funcTy
        }
        let autoEnvBaseDef = GetOrCreateAutoEnvBaseDef(funcTy)
        let convertedFuncType = ConvertFuncArgsAndRetType(funcTy)
        let autoEnvBaseTy = InstantiateAutoEnvBaseType(autoEnvBaseDef, convertedFuncType)
        return builder.context.GetRefTy(autoEnvBaseTy)
    }

    private func ConvertFuncArgsAndRetType(funcTy: FuncType): FuncType {
        let params = ArrayList<Type>()
        for (paramTy in funcTy.GetParamTypes()) {
            params.add(ConvertTypeToClosureType(paramTy))
        }
        return builder.context.GetFuncTy(params, ConvertTypeToClosureType(funcTy.GetReturnType()),
            hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
    }

    private func GetOrCreateAutoEnvBaseDef(funcTy: FuncType): ClassDef {
        let genericBase = GetOrCreateGenericAutoEnvBaseDef(funcTy.GetParamTypes().size)
        if (funcTy.IsGenericRelated()) {
            return genericBase
        }
        return GetOrCreateInstAutoEnvBaseDef(funcTy, genericBase)
    }

    private func GetOrCreateGenericAutoEnvBaseDef(paramNum: Int64): ClassDef {
        let className = CC_GENERIC_BASE_PREFIX + paramNum.toString() + "_"
        if (let Some(found) <- genericAutoEnvBaseDefs.get(className)) {
            return found
        }
        let classDef = builder.CreateClassDef(CurrentPackage().GetName(), className)
        SetObjectSuperClass(classDef)
        let paramsAndRet = ArrayList<Type>()
        var idx: Int64 = 0
        while (idx < paramNum) {
            let genericTy = builder.context.GetGenericTy("ccbase_p${paramNum}_${idx}", "ccbase_p${paramNum}_${idx}")
            classDef.AddGenericTypeParam(genericTy)
            paramsAndRet.add(genericTy)
            idx++
        }
        let retTy = builder.context.GetGenericTy("ccbase_r${paramNum}", "ccbase_r${paramNum}")
        classDef.AddGenericTypeParam(retTy)
        paramsAndRet.add(retTy)
        let classArgs = TypesFromGenerics(classDef.GetGenericTypeParams())
        let classTy = builder.context.GetClassTy(classDef, classArgs)
        classDef.SetType(classTy)
        MarkAutoEnvClass(classDef)
        classDef.SetAnnotation(CC_AUTO_ENV_BASE_ANNOTATION, "true")
        classDef.SetAnnotation(CC_AUTO_ENV_GENERIC_BASE_ANNOTATION, "true")
        classDef.EnableAttr(Attribute.ABSTRACT)
        classDef.EnableAttr(Attribute.PUBLIC)
        AddClassToPackage(classDef)
        CreateVirtualFuncInAutoEnvBaseDef(classDef, GENERIC_VIRTUAL_FUNC, paramsAndRet)
        genericAutoEnvBaseDefs[className] = classDef
        return classDef
    }

    private func GetOrCreateInstAutoEnvBaseDef(funcTy: FuncType, superClass: ClassDef): ClassDef {
        let className = CC_INSTANTIATED_BASE_PREFIX + TypeKey(funcTy)
        if (let Some(found) <- instAutoEnvBaseDefs.get(className)) {
            return found
        }
        let classDef = builder.CreateClassDef(CurrentPackage().GetName(), className)
        let classTy = builder.context.GetClassTy(classDef, ArrayList<Type>())
        classDef.SetType(classTy)
        classDef.SetSuperClassTy(builder.context.GetClassTy(superClass, funcTy.GetTypeArgs()))
        MarkAutoEnvClass(classDef)
        classDef.SetAnnotation(CC_AUTO_ENV_BASE_ANNOTATION, "true")
        classDef.SetAnnotation(CC_AUTO_ENV_INST_BASE_ANNOTATION, "true")
        classDef.EnableAttr(Attribute.ABSTRACT)
        classDef.EnableAttr(Attribute.PUBLIC)
        AddClassToPackage(classDef)
        CreateVirtualFuncInAutoEnvBaseDef(classDef, INST_VIRTUAL_FUNC, funcTy.GetTypeArgs())
        instAutoEnvBaseDefs[className] = classDef
        return classDef
    }

    private func CreateVirtualFuncInAutoEnvBaseDef(classDef: ClassDef, funcName: String,
        paramsAndRetType: ArrayList<Type>): Function {
        if (paramsAndRetType.isEmpty()) {
            throw IllegalStateException("ClosureConversion AutoEnv virtual method needs a return type")
        }
        let paramTypes = ArrayList<Type>()
        paramTypes.add(builder.context.GetRefTy(RequireClassType(classDef)))
        var idx: Int64 = 0
        while (idx + 1 < paramsAndRetType.size) {
            paramTypes.add(paramsAndRetType[idx])
            idx++
        }
        let methodTy = builder.context.GetFuncTy(paramTypes, paramsAndRetType[paramsAndRetType.size - 1])
        let suffix = if (funcName == GENERIC_VIRTUAL_FUNC) { "$vg" } else { "$vi" }
        let method = CreateCCFunction(methodTy, CC_FUNC_PREFIX + classDef.GetIdentifier() + suffix, funcName,
            genericTypeParams: ArrayList<GenericType>())
        method.EnableAttr(Attribute.ABSTRACT)
        method.EnableAttr(Attribute.PUBLIC)
        method.EnableAttr(Attribute.VIRTUAL)
        for (paramTy in paramTypes) {
            builder.CreateParameter(paramTy, "%p${method.GetNumOfParams()}", Some(method))
        }
        classDef.AddMethod(method)
        return method
    }

    private func GetOrCreateAutoEnvImplDef(fn: Function, superClassDef: ClassDef): ClassDef {
        let className = ReplaceManglePrefixWith(fn.GetIdentifierWithoutPrefix(), CC_FUNC_IMPL_PREFIX)
        if (let Some(found) <- autoEnvImplDefs.get(className)) {
            return found
        }
        let genericMap = HashMap<String, Type>()
        let genericTypes = CreateGenericTypeParamsForAutoEnvImplDef(fn)
        let classDef = CreateAutoEnvImplDef(className, genericTypes, fn, superClassDef, genericMap)
        CreateGenericOverrideMethodInAutoEnvImplDef(classDef, fn, genericMap)
        CreateInstOverrideMethodInAutoEnvImplDef(classDef, fn, genericMap)
        autoEnvImplDefs[className] = classDef
        return classDef
    }

    private func GetOrCreateAutoEnvImplDef(lambda: Lambda, superClassDef: ClassDef,
        boxedEnvs: ArrayList<Value>): ClassDef {
        let count = duplicateLambdaName.get(lambda.GetIdentifier()) ?? 0
        let className = ReplaceManglePrefixWith(lambda.GetIdentifier(), CC_LAMBDA_IMPL_PREFIX) + "$" + count.toString()
        if (let Some(found) <- autoEnvImplDefs.get(className)) {
            return found
        }
        let result = lambda.GetResult() ??
            throw IllegalStateException("ClosureConversion lambda has no result")
        let genericMap = HashMap<String, Type>()
        let genericTypes = CreateGenericTypeParamsForAutoEnvImplDef(result)
        let classDef = CreateAutoEnvImplDef(className, genericTypes, result, superClassDef, genericMap)
        CreateMemberVarInAutoEnvImplDef(classDef, boxedEnvs, genericMap)
        let globalFunc = LiftLambdaToGlobalFunc(classDef, lambda, genericTypes, genericMap, boxedEnvs)
        CreateGenericOverrideMethodInAutoEnvImplDef(classDef, globalFunc, genericMap)
        CreateInstOverrideMethodInAutoEnvImplDef(classDef, globalFunc, genericMap)
        autoEnvImplDefs[className] = classDef
        return classDef
    }

    private func CreateAutoEnvImplDef(className: String, genericTypes: ArrayList<GenericType>, srcFunc: Value,
        superClassDef: ClassDef, genericMap: HashMap<String, Type>): ClassDef {
        let classDef = builder.CreateClassDef(CurrentPackage().GetName(), className)
        let classTypeArgs = ArrayList<Type>()
        var idx: Int64 = 0
        while (idx < genericTypes.size) {
            let oldGeneric = genericTypes[idx]
            let newGeneric = builder.context.GetGenericTy(className + "_" + idx.toString(),
                oldGeneric.GetSrcCodeIdentifier())
            genericMap[GenericTypeKey(oldGeneric)] = newGeneric
            classDef.AddGenericTypeParam(newGeneric)
            classTypeArgs.add(newGeneric)
            idx++
        }
        idx = 0
        while (idx < genericTypes.size) {
            let newGeneric = classDef.GetGenericTypeParams()[idx]
            let newBounds = ArrayList<Type>()
            for (bound in genericTypes[idx].GetUpperBounds()) {
                newBounds.add(SubstituteGenericTypes(bound, genericMap))
            }
            newGeneric.SetUpperBounds(newBounds)
            idx++
        }
        let classTy = builder.context.GetClassTy(classDef, classTypeArgs)
        classDef.SetType(classTy)
        let superArgs = ArrayList<Type>()
        if (!superClassDef.GetGenericTypeParams().isEmpty()) {
            if (let Some(srcTy) <- srcFunc.GetType()) {
                if (let Some(funcTy) <- (srcTy as FuncType)) {
                    for (paramTy in funcTy.GetParamTypes()) {
                        superArgs.add(SubstituteGenericTypes(paramTy, genericMap))
                    }
                    superArgs.add(SubstituteGenericTypes(funcTy.GetReturnType(), genericMap))
                }
            }
        }
        classDef.SetSuperClassTy(builder.context.GetClassTy(superClassDef, superArgs))
        MarkAutoEnvClass(classDef)
        classDef.SetAnnotation(CC_AUTO_ENV_IMPL_ANNOTATION, "true")
        classDef.EnableAttr(Attribute.PUBLIC)
        AddClassToPackage(classDef)
        return classDef
    }

    private func CreateMemberVarInAutoEnvImplDef(classDef: ClassDef, boxedEnvs: ArrayList<Value>,
        genericMap: HashMap<String, Type>): Unit {
        for (env in boxedEnvs) {
            let envTy = env.GetType() ??
                throw IllegalStateException("ClosureConversion captured value has no type")
            let memberTy = SubstituteGenericTypes(envTy, genericMap)
            let memberName = GenerateCapturedMemberName(env)
            let info = MemberVarInfo(memberName, memberTy, isStatic: false, isReadOnly: false,
                rawMangledName: memberName)
            info.attributeInfo.Enable(Attribute.PUBLIC)
            classDef.AddInstanceVar(info)
        }
    }

    private func CreateGenericOverrideMethodInAutoEnvImplDef(classDef: ClassDef, srcFunc: Function,
        genericMap: HashMap<String, Type>): Function {
        let srcFuncTy = srcFunc.GetFuncType() ??
            throw IllegalStateException("ClosureConversion source function has no type")
        let srcTypeArgs = srcFuncTy.GetTypeArgs()
        if (srcFunc.IsLambda() && !srcTypeArgs.isEmpty()) {
            srcTypeArgs.remove(at: 0)
        }
        let (boxedParams, boxedRetTy) = CreateFuncTypeWithBoxType(classDef, srcTypeArgs, genericMap)
        let params = ArrayList<Type>()
        params.add(builder.context.GetRefTy(RequireClassType(classDef)))
        for (paramTy in boxedParams) {
            params.add(paramTy)
        }
        let methodTy = builder.context.GetFuncTy(params, boxedRetTy)
        let method = CreateCCFunction(methodTy, GenericOverrideFuncName(srcFunc), GENERIC_VIRTUAL_FUNC,
            genericTypeParams: ArrayList<GenericType>())
        SetMemberMethodAttr(method)
        classDef.AddMethod(method)
        CreateGenericOverrideMethodBody(method, srcFunc, boxedRetTy, genericMap)
        return method
    }

    private func CreateInstOverrideMethodInAutoEnvImplDef(classDef: ClassDef, srcFunc: Function,
        genericMap: HashMap<String, Type>): Option<Function> {
        if (FuncTypeHasGenericT(srcFunc)) {
            return None
        }
        let srcFuncTy = srcFunc.GetFuncType() ??
            throw IllegalStateException("ClosureConversion source function has no type")
        let srcParams = srcFuncTy.GetParamTypes()
        let params = ArrayList<Type>()
        params.add(builder.context.GetRefTy(RequireClassType(classDef)))
        let start = if (srcFunc.IsLambda()) { 1 } else { 0 }
        var idx: Int64 = start
        while (idx < srcParams.size) {
            params.add(SubstituteGenericTypes(srcParams[idx], genericMap))
            idx++
        }
        let retTy = SubstituteGenericTypes(srcFuncTy.GetReturnType(), genericMap)
        let methodTy = builder.context.GetFuncTy(params, retTy)
        let method = CreateCCFunction(methodTy, InstOverrideFuncName(srcFunc), INST_VIRTUAL_FUNC,
            genericTypeParams: ArrayList<GenericType>())
        SetMemberMethodAttr(method)
        classDef.AddMethod(method)
        CreateOverrideMethodBody(method, srcFunc, retTy, genericMap, directParamsStart: 0)
        return Some(method)
    }

    private func CreateFuncTypeWithBoxType(classDef: ClassDef, instFuncTypeArgs: ArrayList<Type>,
        genericMap: HashMap<String, Type>): (ArrayList<Type>, Type) {
        let parentFuncType = GetMethodTypeInAutoEnvGenericDef(classDef)
        let genericParamTypes = parentFuncType.GetParamTypes()
        if (genericParamTypes.isEmpty() || instFuncTypeArgs.isEmpty()) {
            throw IllegalStateException("ClosureConversion AutoEnv generic method type is malformed")
        }
        genericParamTypes.remove(at: 0)
        if (genericParamTypes.size + 1 != instFuncTypeArgs.size) {
            throw IllegalStateException("ClosureConversion AutoEnv generic method type arity mismatch")
        }
        let paramTypes = ArrayList<Type>()
        var idx: Int64 = 0
        while (idx + 1 < instFuncTypeArgs.size) {
            let paramTy = SubstituteGenericTypes(instFuncTypeArgs[idx], genericMap)
            paramTypes.add(if (VirtualParamTypeMatches(genericParamTypes[idx], paramTy)) {
                paramTy
            } else {
                CreateBoxRefTypeIfNeeded(paramTy)
            })
            idx++
        }
        var retTy = SubstituteGenericTypes(instFuncTypeArgs[instFuncTypeArgs.size - 1], genericMap)
        if (!VirtualReturnTypeMatches(retTy, parentFuncType.GetReturnType())) {
            retTy = CreateBoxRefTypeIfNeeded(retTy)
        }
        return (paramTypes, retTy)
    }

    private func GetMethodTypeInAutoEnvGenericDef(def: ClassDef): FuncType {
        if (def.GetAnnotation(CC_AUTO_ENV_GENERIC_BASE_ANNOTATION).isSome()) {
            let methods = def.GetMethods()
            if (methods.size != 1) {
                throw IllegalStateException("ClosureConversion AutoEnv generic base must have one method")
            }
            return methods[0].GetFuncType() ??
                throw IllegalStateException("ClosureConversion AutoEnv generic base method has no type")
        }
        let superDef = def.GetSuperClassDef() ??
            throw IllegalStateException("ClosureConversion AutoEnv generic base not found")
        return GetMethodTypeInAutoEnvGenericDef(superDef)
    }

    private func CreateBoxRefTypeIfNeeded(ty: Type): Type {
        if (ty.IsRef()) {
            return ty
        }
        return builder.context.GetRefTy(builder.context.GetBoxTy(ty))
    }

    private func VirtualParamTypeMatches(left: Type, right: Type): Bool {
        if ((left.IsGeneric() || left.IsRef() || left.IsCJFunc()) &&
            (right.IsGeneric() || right.IsRef() || right.IsCJFunc())) {
            return true
        }
        return TypeShapeMatches(left, right)
    }

    private func VirtualReturnTypeMatches(left: Type, right: Type): Bool {
        if (left.IsGeneric() && right.IsGeneric()) {
            return true
        }
        if ((left.IsRef() || left.IsCJFunc()) && (right.IsRef() || right.IsCJFunc())) {
            return true
        }
        return TypeShapeMatches(left, right)
    }

    private func TypeShapeMatches(left: Type, right: Type): Bool {
        if (left.GetTypeKind() != right.GetTypeKind()) {
            return false
        }
        let leftArgs = left.GetTypeArgs()
        let rightArgs = right.GetTypeArgs()
        if (leftArgs.size != rightArgs.size) {
            return false
        }
        var idx: Int64 = 0
        while (idx < leftArgs.size) {
            if (!TypeShapeMatches(leftArgs[idx], rightArgs[idx])) {
                return false
            }
            idx++
        }
        return true
    }

    private func CreateGenericOverrideMethodBody(method: Function, srcFunc: Function, methodRetTy: Type,
        genericMap: HashMap<String, Type>): Unit {
        let body = builder.CreateBlockGroup(method)
        method.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let methodTy = method.GetFuncType() ??
            throw IllegalStateException("ClosureConversion override method has no type")
        for (paramTy in methodTy.GetParamTypes()) {
            builder.CreateParameter(paramTy, "%p${method.GetNumOfParams()}", Some(method))
        }
        let retSlot = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(methodRetTy), methodRetTy, entry))
        method.SetReturnValue(retSlot)

        let srcFuncTy = srcFunc.GetFuncType() ??
            throw IllegalStateException("ClosureConversion source function has no type")
        let expectedParamTypes = srcFuncTy.GetParamTypes()
        var idx: Int64 = 0
        while (idx < expectedParamTypes.size) {
            expectedParamTypes[idx] = SubstituteGenericTypes(expectedParamTypes[idx], genericMap)
            idx++
        }

        let params = method.GetParams()
        let applyArgs = ArrayList<Value>()
        let offset = if (srcFunc.IsLambda()) { 0 } else { 1 }
        idx = offset
        while (idx < params.size) {
            let expectedTy = expectedParamTypes[idx - offset]
            applyArgs.add(TypeCastOrBoxIfNeeded(params[idx], expectedTy, entry))
            idx++
        }

        let applyRetTy = SubstituteGenericTypes(srcFuncTy.GetReturnType(), genericMap)
        let apply = builder.CreateApply(applyRetTy, srcFunc, FuncCallContext(args: applyArgs,
            instTypeArgs: CreateSubstitutedInstTypeArgs(srcFunc, genericMap),
            thisType: CreateSubstitutedThisType(srcFunc, genericMap)), entry)
        let applyResult = TypeCastOrBoxIfNeeded(RequireResult(apply), methodRetTy, entry)
        if (!methodRetTy.IsUnit() && !methodRetTy.IsVoid() && !methodRetTy.IsNothing()) {
            builder.CreateStore(applyResult, retSlot, entry)
        }
        builder.CreateExit(None, entry)
    }

    private func CreateOverrideMethodBody(method: Function, srcFunc: Function, retTy: Type,
        genericMap: HashMap<String, Type>, directParamsStart!: Int64): Unit {
        let body = builder.CreateBlockGroup(method)
        method.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let methodTy = method.GetFuncType() ??
            throw IllegalStateException("ClosureConversion override method has no type")
        for (paramTy in methodTy.GetParamTypes()) {
            builder.CreateParameter(paramTy, "%p${method.GetNumOfParams()}", Some(method))
        }
        let retSlot = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(retTy), retTy, entry))
        method.SetReturnValue(retSlot)
        let applyArgs = ArrayList<Value>()
        if (srcFunc.IsLambda()) {
            applyArgs.add(method.GetParam(0))
        }
        var idx: Int64 = directParamsStart + 1
        while (idx < method.GetNumOfParams()) {
            applyArgs.add(method.GetParam(idx))
            idx++
        }
        let apply = builder.CreateApply(retTy, srcFunc, FuncCallContext(args: applyArgs,
            instTypeArgs: CreateSubstitutedInstTypeArgs(srcFunc, genericMap),
            thisType: CreateSubstitutedThisType(srcFunc, genericMap)), entry)
        if (!retTy.IsUnit() && !retTy.IsVoid() && !retTy.IsNothing()) {
            builder.CreateStore(RequireResult(apply), retSlot, entry)
        }
        builder.CreateExit(None, entry)
    }

    private func TypeCastOrBoxIfNeeded(value: Value, expectedTy: Type, parent: Block): Value {
        let valueTy = value.GetType() ??
            throw IllegalStateException("ClosureConversion value has no type")
        if (valueTy.IsNothing()) {
            return value
        }
        if (let Some(boxed) <- BoxIfNeeded(value, valueTy, expectedTy, parent)) {
            return boxed
        }
        if (let Some(transformed) <- TransformGenericIfNeeded(value, valueTy, expectedTy, parent)) {
            return transformed
        }
        if (valueTy.IsEqual(expectedTy)) {
            return value
        }
        var castSource = value
        if (valueTy.StripAllRefs().IsGeneric() && valueTy.IsRef()) {
            castSource = RequireResult(builder.CreateLoad(valueTy.StripAllRefs(), value, parent))
        }
        return RequireResult(builder.CreateTypeCast(expectedTy, castSource, parent))
    }

    private func BoxIfNeeded(value: Value, valueTy: Type, expectedTy: Type, parent: Block): Option<Value> {
        let srcIsValueTy = if (let Some(refTy) <- (valueTy as RefType)) {
            refTy.GetBaseType().IsValueType()
        } else {
            valueTy.IsValueType()
        }
        let srcIsReferenceTy = if (let Some(refTy2) <- (valueTy as RefType)) {
            refTy2.GetBaseType().IsReferenceType()
        } else {
            false
        }
        let dstIsValueTy = if (let Some(expectedRefTy) <- (expectedTy as RefType)) {
            expectedRefTy.GetBaseType().IsValueType()
        } else {
            expectedTy.IsValueType()
        }
        let dstIsReferenceTy = if (let Some(expectedRefTy2) <- (expectedTy as RefType)) {
            expectedRefTy2.GetBaseType().IsReferenceType()
        } else {
            false
        }
        if (srcIsValueTy && dstIsReferenceTy) {
            let boxSource = if (let Some(srcRefTy) <- (valueTy as RefType)) {
                RequireResult(builder.CreateLoad(srcRefTy.GetBaseType(), value, parent))
            } else {
                value
            }
            return Some(RequireResult(builder.CreateBox(expectedTy, boxSource, parent)))
        }
        if (srcIsReferenceTy && dstIsValueTy) {
            if (expectedTy.IsRef()) {
                return Some(RequireResult(builder.CreateUnBoxToRef(expectedTy, value, parent)))
            }
            return Some(RequireResult(builder.CreateUnBox(expectedTy, value, parent)))
        }
        if (LeftTypeIsBoxOfRightType(valueTy, expectedTy)) {
            return Some(RequireResult(builder.CreateUnBox(expectedTy, value, parent)))
        }
        if (LeftTypeIsBoxOfRightType(expectedTy, valueTy)) {
            return Some(RequireResult(builder.CreateBox(expectedTy, value, parent)))
        }
        return None
    }

    private func LeftTypeIsBoxOfRightType(left: Type, right: Type): Bool {
        if (let Some(leftRefTy) <- (left as RefType)) {
            if (let Some(boxTy) <- (leftRefTy.GetBaseType() as BoxType)) {
                return right.IsEqual(boxTy.GetBaseType())
            }
        }
        return false
    }

    private func TransformGenericIfNeeded(value: Value, valueTy: Type, expectedTy: Type,
        parent: Block): Option<Value> {
        if (HasGenericInNonFuncScope(expectedTy) && !HasGenericInNonFuncScope(valueTy)) {
            return Some(RequireResult(builder.CreateTransformToGeneric(expectedTy, value, parent)))
        }
        if (HasGenericInNonFuncScope(valueTy) && !HasGenericInNonFuncScope(expectedTy)) {
            return Some(RequireResult(builder.CreateTransformToConcrete(expectedTy, value, parent)))
        }
        return None
    }

    private func HasGenericInNonFuncScope(ty: Type): Bool {
        if (ty.IsFunc()) {
            return false
        }
        if (ty.IsGeneric()) {
            return true
        }
        for (arg in ty.GetTypeArgs()) {
            if (HasGenericInNonFuncScope(arg)) {
                return true
            }
        }
        return false
    }

    private func CreateSubstitutedInstTypeArgs(srcFunc: Function,
        genericMap: HashMap<String, Type>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (ty in srcFunc.GetGenericTypeParams()) {
            out.add(SubstituteGenericTypes(ty, genericMap))
        }
        return out
    }

    private func CreateSubstitutedThisType(srcFunc: Function,
        genericMap: HashMap<String, Type>): Option<Type> {
        if (let Some(thisTy) <- srcFunc.GetParentCustomTypeOrExtendedType()) {
            return Some(SubstituteGenericTypes(thisTy, genericMap))
        }
        return None
    }

    private func LiftLambdaToGlobalFunc(classDef: ClassDef, lambda: Lambda, genericTypeParams: ArrayList<GenericType>,
        genericMap: HashMap<String, Type>, capturedValues: ArrayList<Value>): Function {
        let lambdaTy = lambda.GetFuncType() ??
            throw IllegalStateException("ClosureConversion lambda has no function type")
        let params = ArrayList<Type>()
        params.add(builder.context.GetRefTy(RequireClassType(classDef)))
        for (paramTy in lambdaTy.GetParamTypes()) {
            params.add(SubstituteGenericTypes(paramTy, genericMap))
        }
        let retTy = SubstituteGenericTypes(lambdaTy.GetReturnType(), genericMap)
        let funcTy = builder.context.GetFuncTy(params, retTy)
        let convertedGenericParams = ArrayList<GenericType>()
        for (genericTy in genericTypeParams) {
            if (let Some(mappedTy) <- genericMap.get(GenericTypeKey(genericTy))) {
                if (let Some(newTy) <- (mappedTy as GenericType)) {
                    convertedGenericParams.add(newTy)
                }
            }
        }
        let globalFunc = CreateCCFunction(funcTy, GenerateGlobalFuncIdentifier(lambda), lambda.GetSrcCodeIdentifier(),
            genericTypeParams: convertedGenericParams)
        globalFunc.SetFuncKind(FuncKind.LAMBDA)
        if (lambda.IsCompileTimeValue()) {
            globalFunc.EnableAttr(Attribute.CONST)
        }
        if (let Some(parentFunc) <- lambda.GetTopLevelFunc()) {
            globalFunc.InheritIDFromFunc(parentFunc)
        }
        let thisParam = builder.CreateParameter(params[0], "$env", Some(globalFunc))
        thisParam.SetSrcCodeIdentifier("$env")
        for (param in lambda.GetParams()) {
            param.SetOwnerFunc(globalFunc)
            globalFunc.AddParam(param)
            if (let Some(paramTy) <- param.GetType()) {
                param.SetType(SubstituteGenericTypes(paramTy, genericMap))
            }
        }
        let body = lambda.GetBody() ??
            throw IllegalStateException("ClosureConversion lambda has no body")
        globalFunc.InitBody(body)
        if (let Some(retValue) <- lambda.GetReturnValue()) {
            globalFunc.SetReturnValue(retValue)
        }
        ReplaceEnvVarWithMemberVar(capturedValues, globalFunc, thisParam)
        // Mirror C++ LiftLambdaToGlobalFunc step 3 (ClosureConversion.cpp:2008-2028):
        // traverse the lifted body and re-map the original generics (e.g. the
        // enclosing func's `T`) to the lifted func's own generic params, so the
        // body's stored types match the new signature and instantiate correctly.
        ConvertBlockGroupTypesWithGenericMap(globalFunc.GetBody().getOrThrow(), genericMap)
        for (param in globalFunc.GetParams()) {
            ConvertValueTypeWithGenericMap(param, genericMap)
        }
        if (let Some(retValue) <- globalFunc.GetReturnValue()) {
            ConvertValueTypeWithGenericMap(retValue, genericMap)
        }
        convertedCache[lambda.nodeId] = globalFunc
        return globalFunc
    }

    private func ConvertBlockGroupTypesWithGenericMap(group: BlockGroup,
        genericMap: HashMap<String, Type>): Unit {
        for (block in group.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                ConvertExpressionTypesWithGenericMap(expr, genericMap)
                for (subGroup in expr.GetBlockGroups()) {
                    ConvertBlockGroupTypesWithGenericMap(subGroup, genericMap)
                }
            }
        }
    }

    private func ConvertExpressionTypesWithGenericMap(expr: Expression,
        genericMap: HashMap<String, Type>): Unit {
        if (let Some(result) <- expr.GetResult()) {
            ConvertValueTypeWithGenericMap(result, genericMap)
        }
        if (let Some(allocate) <- (expr as Allocate)) {
            allocate.SetType(SubstituteGenericTypes(allocate.GetType(), genericMap))
        } else if (let Some(rawArrayAllocate) <- (expr as RawArrayAllocate)) {
            rawArrayAllocate.SetElementType(SubstituteGenericTypes(rawArrayAllocate.GetElementType(), genericMap))
        } else if (let Some(getRTTIStatic) <- (expr as GetRTTIStatic)) {
            getRTTIStatic.SetRTTIType(SubstituteGenericTypes(getRTTIStatic.GetRTTIType(), genericMap))
        } else if (let Some(instanceOfExpr) <- (expr as InstanceOf)) {
            instanceOfExpr.SetTestedType(SubstituteGenericTypes(instanceOfExpr.GetType(), genericMap))
        }
        if (let Some(call) <- (expr as FuncCall)) {
            if (let Some(thisTy) <- call.GetThisType()) {
                call.SetThisType(SubstituteGenericTypes(thisTy, genericMap))
            }
            call.SetInstantiatedTypeArgs(SubstituteGenericTypeArgs(call.GetInstantiatedTypeArgs(), genericMap))
        }
        if (let Some(callWithException) <- (expr as FuncCallWithException)) {
            if (let Some(thisTy2) <- callWithException.GetThisType()) {
                callWithException.SetThisType(SubstituteGenericTypes(thisTy2, genericMap))
            }
            callWithException.SetInstantiatedTypeArgs(
                SubstituteGenericTypeArgs(callWithException.GetInstantiatedTypeArgs(), genericMap))
        }
    }

    private func ConvertValueTypeWithGenericMap(value: Value, genericMap: HashMap<String, Type>): Unit {
        if (value.AsFunction().isSome()) {
            return
        }
        if (let Some(valueTy) <- value.GetType()) {
            value.SetType(SubstituteGenericTypes(valueTy, genericMap))
        }
    }

    private func LiftNestedFunctionWithCFuncType(lambda: Lambda): Unit {
        let result = lambda.GetResult() ??
            throw IllegalStateException("ClosureConversion CFunc lambda has no result")
        let resultTy = result.GetType() ??
            throw IllegalStateException("ClosureConversion CFunc lambda result has no type")
        let funcTy = (resultTy as FuncType) ??
            throw IllegalStateException("ClosureConversion CFunc lambda result is not a function type")
        let globalFunc = CreateCCFunction(funcTy, GenerateGlobalFuncIdentifier(lambda), lambda.GetSrcCodeIdentifier(),
            genericTypeParams: lambda.GetGenericTypeParams())
        globalFunc.SetFuncKind(FuncKind.LAMBDA)
        if (let Some(parentFunc) <- lambda.GetTopLevelFunc()) {
            globalFunc.InheritIDFromFunc(parentFunc)
        }
        for (param in lambda.GetParams()) {
            param.SetOwnerFunc(globalFunc)
            globalFunc.AddParam(param)
        }
        let body = lambda.GetBody() ??
            throw IllegalStateException("ClosureConversion CFunc lambda has no body")
        globalFunc.InitBody(body)
        if (let Some(retValue) <- lambda.GetReturnValue()) {
            globalFunc.SetReturnValue(retValue)
        }
        let users = result.GetUsers()
        for (user in users) {
            user.ReplaceOperand(result, globalFunc)
        }
        convertedCache[lambda.nodeId] = globalFunc
        lambda.DetachLiftedBodyAndRemoveSelf()
    }

    private func ReplaceEnvVarWithMemberVar(capturedValues: ArrayList<Value>, globalFunc: Function,
        thisParam: Value): Unit {
        let entry = globalFunc.GetEntryBlock() ??
            throw IllegalStateException("ClosureConversion lifted function has no entry block")
        var lastExpr: Option<Expression> = None
        var capturedIndex: UInt64 = 0u64
        for (captured in capturedValues) {
            let capturedTy = captured.GetType() ??
                throw IllegalStateException("ClosureConversion captured value has no type")
            let fieldRefTy = builder.context.GetRefTy(capturedTy)
            let path = ArrayList<UInt64>()
            path.add(capturedIndex)
            let fieldRef = builder.CreateGetElementRef(fieldRefTy, thisParam, path, entry)
            if (let Some(prev) <- lastExpr) {
                fieldRef.MoveAfter(prev)
            } else {
                entry.InsertExprIntoHead(fieldRef)
            }
            let loaded = builder.CreateLoad(capturedTy, RequireResult(fieldRef), entry)
            loaded.MoveAfter(fieldRef)
            lastExpr = Some(loaded)
            let loadedValue = RequireResult(loaded)
            let users = captured.GetUsers()
            for (user in users) {
                if (let Some(owner) <- user.GetTopLevelFunc()) {
                    if (owner.nodeId == globalFunc.nodeId && user.nodeId != fieldRef.nodeId && user.nodeId != loaded.nodeId) {
                        user.ReplaceOperand(captured, loadedValue)
                    }
                }
            }
            capturedIndex++
        }
    }

    private func ReplaceUserPoint(fn: Function, user: Expression, autoEnvImplDef: ClassDef): Unit {
        let parent = user.GetParentBlock() ??
            throw IllegalStateException("ClosureConversion function user has no parent block")
        let envs = ArrayList<Value>()
        let obj = CreateAutoEnvImplObject(parent, RequireClassType(autoEnvImplDef), envs, user, fn)
        let baseObj = CastAutoEnvObjToSuper(obj, autoEnvImplDef, user)
        user.ReplaceOperand(fn, baseObj)
    }

    private func ReplaceUserPoint(lambda: Lambda, user: Expression, envs: ArrayList<Value>,
        autoEnvImplDef: ClassDef): Unit {
        let parent = user.GetParentBlock() ??
            throw IllegalStateException("ClosureConversion lambda user has no parent block")
        let result = lambda.GetResult() ??
            throw IllegalStateException("ClosureConversion lambda has no result")
        let globalFunc = convertedCache.get(lambda.nodeId) ??
            throw IllegalStateException("ClosureConversion lambda was not lifted")
        var autoEnvObj: Value
        if (let Some(owner) <- user.GetTopLevelFunc()) {
            if (owner.nodeId == globalFunc.nodeId) {
                autoEnvObj = globalFunc.GetParam(0)
            } else {
                autoEnvObj = CreateAutoEnvImplObject(parent, RequireClassType(autoEnvImplDef), envs, user, result)
            }
        } else {
            autoEnvObj = CreateAutoEnvImplObject(parent, RequireClassType(autoEnvImplDef), envs, user, result)
        }
        if (let Some(apply) <- (user as Apply)) {
            if (apply.GetCallee().nodeId == result.nodeId) {
                let methods = autoEnvImplDef.GetMethods()
                let method = methods[methods.size - 1]
                let args = apply.GetArgs()
                args.add(autoEnvObj, at: 0)
                let retTy = apply.GetResultType() ??
                    throw IllegalStateException("ClosureConversion apply has no result type")
                let newApply = builder.CreateApply(retTy, method, FuncCallContext(args: args,
                    thisType: autoEnvObj.GetType()), parent)
                apply.ReplaceWith(newApply)
                return
            }
        }
        if (let Some(applyWithException) <- (user as ApplyWithException)) {
            if (applyWithException.GetCallee().nodeId == result.nodeId) {
                let methods = autoEnvImplDef.GetMethods()
                let method = methods[methods.size - 1]
                let args = applyWithException.GetArgs()
                args.add(autoEnvObj, at: 0)
                let retTy = applyWithException.GetResultType() ??
                    throw IllegalStateException("ClosureConversion apply-with-exception has no result type")
                let newApply = builder.CreateApplyWithException(retTy, method, FuncCallContext(args: args,
                    thisType: autoEnvObj.GetType()), applyWithException.GetSuccessBlock(),
                    applyWithException.GetErrorBlock(), parent)
                applyWithException.ReplaceWith(newApply)
                return
            }
        }
        let baseObj = CastAutoEnvObjToSuper(autoEnvObj, autoEnvImplDef, user)
        user.ReplaceOperand(result, baseObj)
    }

    private func CreateAutoEnvImplObject(parent: Block, autoEnvImplType: ClassType, envs: ArrayList<Value>,
        user: Expression, srcFunc: Value): LocalVar {
        let instantiateClassTy = GenerateInstantiatedClassType(autoEnvImplType, user, srcFunc)
        let refType = builder.context.GetRefTy(instantiateClassTy)
        let allocate = builder.CreateAllocate(refType, instantiateClassTy, parent)
        parent.InsertExprIntoHead(allocate)
        let obj = RequireResult(allocate)
        var idx: UInt64 = 0u64
        for (env in envs) {
            let path = ArrayList<UInt64>()
            path.add(idx)
            let store = builder.CreateStoreElementRef(env, obj, path, parent)
            store.MoveBefore(user)
            idx++
        }
        return obj
    }

    // Mirror C++ ClosureConversion::GenerateInstantiatedClassType
    // (src/CHIR/Transformation/ClosureConversion.cpp:1011-1054). The AutoEnv impl
    // class is declared over the generic params visible at the closure-creation
    // site (outer-scope decl + func itself). The allocation must bind those
    // params to the concrete type args in scope so that, after generic
    // instantiation, the env allocation specializes to the captured concrete type.
    private func GenerateInstantiatedClassType(autoEnvImplType: ClassType, user: Expression,
        srcFunc: Value): ClassType {
        let autoEnvInstTypeArgs = ArrayList<Type>()
        for (genericTy in GetVisiableGenericTypes(srcFunc)) {
            autoEnvInstTypeArgs.add(genericTy)
        }
        // Overlay any explicit instantiated type args carried by the call site that
        // applies srcFunc onto the trailing func-generic slots.
        if (let Some(apply) <- (user as Apply)) {
            if (apply.GetCallee().nodeId == srcFunc.nodeId) {
                OverlayInstantiatedTypeArgs(autoEnvInstTypeArgs, apply.GetInstantiatedTypeArgs())
            }
        } else if (let Some(awe) <- (user as ApplyWithException)) {
            if (awe.GetCallee().nodeId == srcFunc.nodeId) {
                OverlayInstantiatedTypeArgs(autoEnvInstTypeArgs, awe.GetInstantiatedTypeArgs())
            }
        }
        if (NeedAddThisType(srcFunc)) {
            autoEnvInstTypeArgs.add(ThisType(), at: 0)
        }
        if (autoEnvImplType.GetGenericArgs().size != autoEnvInstTypeArgs.size) {
            return autoEnvImplType
        }
        return builder.context.GetClassTy(autoEnvImplType.GetClassDef(), autoEnvInstTypeArgs)
    }

    private func OverlayInstantiatedTypeArgs(autoEnvInstTypeArgs: ArrayList<Type>,
        partInstTys: ArrayList<Type>): Unit {
        if (autoEnvInstTypeArgs.size < partInstTys.size) {
            return
        }
        let offset = autoEnvInstTypeArgs.size - partInstTys.size
        var i = offset
        var j = 0
        while (i < autoEnvInstTypeArgs.size) {
            autoEnvInstTypeArgs[i] = partInstTys[j]
            i++
            j++
        }
    }

    // Mirror C++ GetVisiableGenericTypes (src/CHIR/Utils/Utils.cpp:1050-1108):
    // collect the generic params of srcFunc and of the lexically enclosing
    // lambdas/funcs (and any owning custom type def), outermost first.
    private func GetVisiableGenericTypes(srcFunc: Value): ArrayList<GenericType> {
        let result = ArrayList<GenericType>()
        CollectVisiableGenericTypes(srcFunc, result)
        return result
    }

    private func CollectVisiableGenericTypes(value: Value, result: ArrayList<GenericType>): Unit {
        if (let Some(fn) <- value.AsFunction()) {
            CollectVisiableGenericTypesFromFunction(fn, result)
            return
        }
        if (let Some(local) <- value.AsLocalVar()) {
            CollectVisiableGenericTypesFromLocalVar(local, result)
            return
        }
        if (let Some(param) <- value.AsParameter()) {
            if (let Some(topLevelFunc) <- param.GetTopLevelFunc()) {
                CollectVisiableGenericTypesFromFunction(topLevelFunc, result)
            }
        }
    }

    private func CollectVisiableGenericTypesFromFunction(fn: Function, result: ArrayList<GenericType>): Unit {
        InsertGenericTypesAtFront(result, fn.GetGenericTypeParams())
        if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
            InsertGenericTypesAtFront(result, parentDef.GetGenericTypeParams())
        }
    }

    private func CollectVisiableGenericTypesFromLocalVar(value: LocalVar, result: ArrayList<GenericType>): Unit {
        let expr = value.GetExpr() ??
            throw IllegalStateException("ClosureConversion visible-generic local var has no expression")
        // A lambda's return value can see generic types declared in the lambda itself.
        if (let Some(lambda) <- (expr as Lambda)) {
            InsertGenericTypesAtFront(result, lambda.GetGenericTypeParams())
        }
        var curPos = expr.GetParentBlockGroup() ??
            throw IllegalStateException("ClosureConversion visible-generic local var has no parent block group")
        while (curPos.GetOwnerFunc().isNone()) {
            let ownedExpr = curPos.GetOwnerExpression() ??
                throw IllegalStateException("ClosureConversion visible-generic block group has no owner")
            if (let Some(lam) <- (ownedExpr as Lambda)) {
                InsertGenericTypesAtFront(result, lam.GetGenericTypeParams())
                curPos = lam.GetParentBlockGroup() ??
                    throw IllegalStateException("ClosureConversion visible-generic lambda has no parent block group")
            } else {
                curPos = ownedExpr.GetParentBlockGroup() ??
                    throw IllegalStateException("ClosureConversion visible-generic expr has no parent block group")
            }
        }
        let ownFunc = curPos.GetOwnerFunc() ??
            throw IllegalStateException("ClosureConversion visible-generic block group has no owner func")
        CollectVisiableGenericTypesFromFunction(ownFunc, result)
    }

    private func InsertGenericTypesAtFront(target: ArrayList<GenericType>,
        values: ArrayList<GenericType>): Unit {
        var idx: Int64 = 0
        for (value in values) {
            target.add(value, at: idx)
            idx++
        }
    }

    // Mirror C++ NeedAddThisType (src/CHIR/Transformation/ClosureConversion.cpp:192-211):
    // only a lambda whose enclosing member method lives in an inheritable class
    // needs a leading `This` type arg.
    private func NeedAddThisType(srcFunc: Value): Bool {
        let local = srcFunc.AsLocalVar() ?? return false
        let expr = local.GetExpr() ?? return false
        let lambda = (expr as Lambda) ?? return false
        if (let Some(lambdaTy) <- lambda.GetFuncType()) {
            if (lambdaTy.IsCFunc()) {
                return false
            }
        }
        let topLevelFunc = local.GetTopLevelFunc() ?? return false
        let outerDecl = topLevelFunc.GetParentCustomTypeDef() ?? return false
        if (outerDecl.IsEnum() || outerDecl.IsStruct()) {
            return false
        }
        return outerDecl.CanBeInherited()
    }

    private func CastAutoEnvObjToSuper(autoEnvObj: Value, autoEnvImplDef: ClassDef, user: Expression): Value {
        if (let Some(superTy) <- autoEnvImplDef.GetSuperClassTy()) {
            let parent = user.GetParentBlock() ??
                throw IllegalStateException("ClosureConversion user has no parent block")
            let superRefTy = builder.context.GetRefTy(superTy)
            let castToBase = builder.CreateTypeCast(superRefTy, autoEnvObj, parent)
            castToBase.MoveBefore(user)
            return RequireResult(castToBase)
        }
        return autoEnvObj
    }

    private func BoxAllMutableVars(rawEnvs: ArrayList<Value>): ArrayList<Value> {
        let boxedEnvs = ArrayList<Value>()
        for (env in rawEnvs) {
            if (!ContainsValue(capturedValues, env)) {
                capturedValues.add(env)
            }
            if (IsMutableVarType(env)) {
                if (let Some(local) <- env.AsLocalVar()) {
                    boxedEnvs.add(BoxMutableVar(local))
                } else {
                    boxedEnvs.add(env)
                }
            } else {
                boxedEnvs.add(env)
            }
        }
        return boxedEnvs
    }

    private func BoxMutableVar(env: LocalVar): Value {
        let rawEnvTy = env.GetType() ??
            throw IllegalStateException("ClosureConversion mutable capture has no type")
        let envTy = (rawEnvTy as RefType) ??
            throw IllegalStateException("ClosureConversion mutable capture is not a ref")
        let valueTy = envTy.GetBaseType()
        let classDef = CreateBoxClassDef(valueTy)
        let classTy = RequireClassType(classDef)
        let envExpr = env.GetExpr() ??
            throw IllegalStateException("ClosureConversion mutable capture has no defining expression")
        let parent = envExpr.GetParentBlock() ??
            throw IllegalStateException("ClosureConversion mutable capture has no parent block")
        let boxObjExpr = builder.CreateAllocate(builder.context.GetRefTy(classTy), classTy, parent)
        boxObjExpr.MoveBefore(envExpr)
        let boxObj = RequireResult(boxObjExpr)
        let users = env.GetUsers()
        for (user in users) {
            if (user.nodeId == boxObjExpr.nodeId || user.GetParentBlock().isNone()) {
                continue
            }
            let userParent = user.GetParentBlock() ??
                throw IllegalStateException("ClosureConversion mutable capture user has no parent block")
            let path = ArrayList<UInt64>()
            path.add(0u64)
            if (let Some(store) <- (user as Store)) {
                if (store.GetLocation().nodeId == env.nodeId) {
                    let storeField = builder.CreateStoreElementRef(store.GetValue(), boxObj, path, userParent)
                    storeField.MoveBefore(user)
                    user.RemoveSelfFromBlock()
                    continue
                }
            }
            let fieldRef = builder.CreateGetElementRef(env.GetType() ??
                throw IllegalStateException("ClosureConversion mutable capture has no type"), boxObj, path, userParent)
            fieldRef.MoveBefore(user)
            user.ReplaceOperand(env, RequireResult(fieldRef))
        }
        envExpr.RemoveSelfFromBlock()
        env.EnableAttr(Attribute.BOXED)
        return boxObj
    }

    private func CreateBoxClassDef(valueTy: Type): ClassDef {
        let className = CC_CAPTURED_PREFIX + TypeKey(valueTy)
        if (let Some(found) <- boxClassMap.get(className)) {
            return found
        }
        let classDef = builder.CreateClassDef(CurrentPackage().GetName(), className)
        SetObjectSuperClass(classDef)
        let genericTypes = ArrayList<GenericType>()
        CollectGenericTypes(valueTy, genericTypes)
        let typeArgs = ArrayList<Type>()
        for (genericTy in genericTypes) {
            classDef.AddGenericTypeParam(genericTy)
            typeArgs.add(genericTy)
        }
        let classTy = builder.context.GetClassTy(classDef, typeArgs)
        classDef.SetType(classTy)
        let memberInfo = MemberVarInfo("value", valueTy, isStatic: false, isReadOnly: false, rawMangledName: "value")
        memberInfo.attributeInfo.Enable(Attribute.PUBLIC)
        classDef.AddInstanceVar(memberInfo)
        classDef.EnableAttr(Attribute.PUBLIC)
        AddClassToPackage(classDef)
        boxClassMap[className] = classDef
        return classDef
    }

    private func ConvertApplyToInvoke(apply: Apply): Unit {
        let callee = apply.GetCallee()
        let instParentType = ResolveAutoEnvCallParentType(callee, apply)
        let method = ResolveAutoEnvVirtualMethod(instParentType)
        let funcContext = FuncCallContext(args: apply.GetArgs(), thisType: Some(instParentType))
        let methodTy = method.GetFuncType() ??
            throw IllegalStateException("ClosureConversion AutoEnv method has no type")
        let methodContext = FuncSigInfo(methodTy,
            funcName: method.GetSrcCodeIdentifier(), genericTypeParams: method.GetGenericTypeParams())
        let invokeContext = InvokeCallContext(callee, funcContext, methodContext)
        let retTy = apply.GetResultType() ??
            throw IllegalStateException("ClosureConversion apply has no result type")
        let parent = apply.GetParentBlock() ??
            throw IllegalStateException("ClosureConversion apply has no parent block")
        let invokeRetTy = GetInvokeABIResultType(methodTy.GetReturnType(), retTy)
        let invoke = builder.CreateInvoke(invokeRetTy, invokeContext, parent)
        invoke.SetVirtualMethodOffset(0u64)
        apply.ReplaceWith(invoke)
        InsertInvokeResultConversionIfNeeded(invoke, retTy)
    }

    private func ConvertApplyWithExceptionToInvokeWithException(apply: ApplyWithException): Unit {
        let callee = apply.GetCallee()
        let instParentType = ResolveAutoEnvCallParentType(callee, apply)
        let method = ResolveAutoEnvVirtualMethod(instParentType)
        let funcContext = FuncCallContext(args: apply.GetArgs(), thisType: Some(instParentType))
        let methodContext = FuncSigInfo(method.GetFuncType() ??
            throw IllegalStateException("ClosureConversion AutoEnv method has no type"),
            funcName: method.GetSrcCodeIdentifier(), genericTypeParams: method.GetGenericTypeParams())
        let invokeContext = InvokeCallContext(callee, funcContext, methodContext)
        let retTy = apply.GetResultType() ??
            throw IllegalStateException("ClosureConversion apply-with-exception has no result type")
        let invoke = builder.CreateInvokeWithException(retTy, invokeContext, apply.GetSuccessBlock(),
            apply.GetErrorBlock(), apply.GetParentBlock() ??
                throw IllegalStateException("ClosureConversion apply-with-exception has no parent block"))
        invoke.SetVirtualMethodOffset(0u64)
        apply.ReplaceWith(invoke)
    }

    private func GetInvokeABIResultType(methodRetTy: Type, expectedRetTy: Type): Type {
        if (methodRetTy.IsGeneric() && !expectedRetTy.IsGeneric()) {
            return methodRetTy
        }
        return expectedRetTy
    }

    private func InsertInvokeResultConversionIfNeeded(invoke: Invoke, expectedRetTy: Type): Unit {
        let invokeResult = RequireResult(invoke)
        let invokeRetTy = invokeResult.GetType() ??
            throw IllegalStateException("ClosureConversion invoke result has no type")
        if (invokeRetTy.IsEqual(expectedRetTy)) {
            return
        }
        let parent = invoke.GetParentBlock() ??
            throw IllegalStateException("ClosureConversion invoke has no parent block")
        let converted = TypeCastOrBoxIfNeeded(invokeResult, expectedRetTy, parent)
        if (let Some(convertedExpr) <- ValueExpr(converted)) {
            convertedExpr.MoveAfter(invoke)
            let users = invokeResult.GetUsers()
            for (user in users) {
                if (user.nodeId != convertedExpr.nodeId) {
                    user.ReplaceOperand(invokeResult, converted)
                }
            }
        }
    }

    private func ValueExpr(value: Value): Option<Expression> {
        if (let Some(local) <- value.AsLocalVar()) {
            return local.GetExpr()
        }
        return None
    }

    private func ResolveAutoEnvCallParentType(callee: Value, call: Expression): ClassType {
        if (let Some(calleeTy) <- callee.GetType()) {
            if (let Some(funcTy) <- (calleeTy as FuncType)) {
                let baseDef = GetOrCreateAutoEnvBaseDef(funcTy)
                return InstantiateAutoEnvBaseType(baseDef, ConvertFuncArgsAndRetType(funcTy))
            }
            if (let Some(refTy) <- (calleeTy as RefType)) {
                if (let Some(classTy) <- (refTy.GetBaseType() as ClassType)) {
                    return classTy
                }
            }
        }
        let _ = call
        throw IllegalStateException("not yet handled in ClosureConversion: applying non-AutoEnv callee")
    }

    private func ResolveAutoEnvVirtualMethod(classTy: ClassType): Function {
        let def = classTy.GetClassDef()
        let methodName = if (IsInstAutoEnvBaseDef(def)) { INST_VIRTUAL_FUNC } else { GENERIC_VIRTUAL_FUNC }
        if (let Some(method) <- FindMethodBySrcName(def, methodName)) {
            return method
        }
        if (let Some(superDef) <- def.GetSuperClassDef()) {
            if (let Some(method2) <- FindMethodBySrcName(superDef, methodName)) {
                return method2
            }
        }
        throw IllegalStateException("ClosureConversion AutoEnv method not found: " + methodName)
    }

    private func ApplyNeedConvertToInvoke(apply: Apply): Bool {
        return !apply.GetCallee().IsFunc() && IsAutoEnvRefType(apply.GetCallee().GetType())
    }

    private func ApplyWithExceptionNeedConvertToInvokeWithException(apply: ApplyWithException): Bool {
        return !apply.GetCallee().IsFunc() && IsAutoEnvRefType(apply.GetCallee().GetType())
    }

    private func IsAutoEnvRefType(tyOpt: Option<Type>): Bool {
        if (let Some(ty) <- tyOpt) {
            if (let Some(refTy) <- (ty as RefType)) {
                if (let Some(classTy) <- (refTy.GetBaseType() as ClassType)) {
                    return IsAutoEnvDef(classTy.GetClassDef())
                }
            }
        }
        return false
    }

    private func InstantiateAutoEnvBaseType(autoEnvBaseDef: ClassDef, funcTy: FuncType): ClassType {
        let args = if (autoEnvBaseDef.GetGenericTypeParams().isEmpty()) {
            ArrayList<Type>()
        } else {
            funcTy.GetTypeArgs()
        }
        return builder.context.GetClassTy(autoEnvBaseDef, args)
    }

    private func CreateGenericTypeParamsForAutoEnvImplDef(value: Value): ArrayList<GenericType> {
        let result = ArrayList<GenericType>()
        if (let Some(fn) <- value.AsFunction()) {
            AddGenericParamsNoDup(result, GenericParamsFromFunction(fn))
            return result
        }
        if (let Some(local) <- value.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                if (let Some(lambda) <- (expr as Lambda)) {
                    AddGenericParamsNoDup(result, lambda.GetGenericTypeParams())
                }
            }
            if (let Some(topLevelFunc) <- local.GetTopLevelFunc()) {
                AddGenericParamsNoDup(result, GenericParamsFromFunction(topLevelFunc))
            }
            return result
        }
        if (let Some(param) <- value.AsParameter()) {
            if (let Some(topLevelFunc2) <- param.GetTopLevelFunc()) {
                AddGenericParamsNoDup(result, GenericParamsFromFunction(topLevelFunc2))
            }
        }
        return result
    }

    private func GenericParamsFromFunction(fn: Function): ArrayList<GenericType> {
        let out = ArrayList<GenericType>()
        if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) {
            AddGenericParamsNoDup(out, parentDef.GetGenericTypeParams())
        }
        AddGenericParamsNoDup(out, fn.GetGenericTypeParams())
        return out
    }

    private func AddGenericParamsNoDup(target: ArrayList<GenericType>, values: ArrayList<GenericType>): Unit {
        for (value in values) {
            var found = false
            for (existing in target) {
                if (GenericTypeKey(existing) == GenericTypeKey(value)) {
                    found = true
                    break
                }
            }
            if (!found) {
                target.add(value)
            }
        }
    }

    private func SubstituteGenericTypes(ty: Type, genericMap: HashMap<String, Type>): Type {
        if (let Some(genericTy) <- (ty as GenericType)) {
            return genericMap.get(GenericTypeKey(genericTy)) ?? ty
        }
        if (let Some(refTy) <- (ty as RefType)) {
            return builder.context.GetRefTy(SubstituteGenericTypes(refTy.GetBaseType(), genericMap))
        }
        if (let Some(funcTy) <- (ty as FuncType)) {
            let params = ArrayList<Type>()
            for (paramTy in funcTy.GetParamTypes()) {
                params.add(SubstituteGenericTypes(paramTy, genericMap))
            }
            return builder.context.GetFuncTy(params, SubstituteGenericTypes(funcTy.GetReturnType(), genericMap),
                hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            return builder.context.GetTupleTy(SubstituteGenericTypeArgs(tupleTy.GetTypeArgs(), genericMap))
        }
        if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            return builder.context.GetRawArrayTy(SubstituteGenericTypes(rawArrayTy.GetElementType(), genericMap),
                dims: rawArrayTy.GetDims())
        }
        if (let Some(varrayTy) <- (ty as VArrayType)) {
            return builder.context.GetVArrayTy(SubstituteGenericTypes(varrayTy.GetElementType(), genericMap),
                varrayTy.size)
        }
        if (let Some(pointerTy) <- (ty as CPointerType)) {
            return builder.context.GetCPointerTy(SubstituteGenericTypes(pointerTy.GetElementType(), genericMap))
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return builder.context.GetBoxTy(SubstituteGenericTypes(boxTy.GetBaseType(), genericMap))
        }
        if (let Some(structTy) <- (ty as StructType)) {
            return builder.context.GetStructTy(structTy.GetStructDef(),
                SubstituteGenericTypeArgs(structTy.GetGenericArgs(), genericMap))
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            return builder.context.GetClassTy(classTy.GetClassDef(),
                SubstituteGenericTypeArgs(classTy.GetGenericArgs(), genericMap))
        }
        if (let Some(enumTy) <- (ty as EnumType)) {
            return builder.context.GetEnumTy(enumTy.GetEnumDef(),
                SubstituteGenericTypeArgs(enumTy.GetGenericArgs(), genericMap))
        }
        return ty
    }

    private func SubstituteGenericTypeArgs(args: ArrayList<Type>, genericMap: HashMap<String, Type>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (arg in args) {
            out.add(SubstituteGenericTypes(arg, genericMap))
        }
        return out
    }

    private func CollectGenericTypes(ty: Type, out: ArrayList<GenericType>): Unit {
        if (let Some(genericTy) <- (ty as GenericType)) {
            AddGenericParamsNoDup(out, MakeGenericList(genericTy))
            return
        }
        for (arg in ty.GetTypeArgs()) {
            CollectGenericTypes(arg, out)
        }
    }

    private func MakeGenericList(genericTy: GenericType): ArrayList<GenericType> {
        let out = ArrayList<GenericType>()
        out.add(genericTy)
        return out
    }

    private func FuncTypeHasGenericT(fn: Function): Bool {
        let funcTy = fn.GetFuncType() ??
            throw IllegalStateException("ClosureConversion function has no type")
        let params = funcTy.GetParamTypes()
        if (fn.IsLambda() && !params.isEmpty()) {
            params.remove(at: 0)
        }
        for (paramTy in params) {
            if (paramTy.IsGenericRelated()) {
                return true
            }
        }
        return funcTy.GetReturnType().IsGenericRelated()
    }

    private func IsMutableVarType(value: Value): Bool {
        if (value.IsParameter()) {
            return false
        }
        if (let Some(valueTy) <- value.GetType()) {
            if (let Some(refTy) <- (valueTy as RefType)) {
                return !refTy.GetBaseType().IsClassOrArray()
            }
        }
        return false
    }

    private func IsCalleeOfApply(user: Expression, op: Value): Bool {
        if (let Some(apply) <- (user as Apply)) {
            return apply.GetCallee().nodeId == op.nodeId
        }
        if (let Some(applyWithException) <- (user as ApplyWithException)) {
            return applyWithException.GetCallee().nodeId == op.nodeId
        }
        if (let Some(invoke) <- (user as Invoke)) {
            return invoke.GetObject().nodeId == op.nodeId
        }
        if (let Some(invokeWithException) <- (user as InvokeWithException)) {
            return invokeWithException.GetObject().nodeId == op.nodeId
        }
        return false
    }

    private func RecordDuplicateLambdaName(lambdaFunc: Lambda): Unit {
        let name = lambdaFunc.GetIdentifier()
        if (duplicateLambdaName.contains(name)) {
            duplicateLambdaName[name] = (duplicateLambdaName.get(name) ?? 0) + 1
        } else {
            duplicateLambdaName[name] = 0
        }
    }

    private func GenerateGlobalFuncIdentifier(lambda: Lambda): String {
        let count = duplicateLambdaName.get(lambda.GetIdentifier()) ?? 0
        if (count == 0) {
            return lambda.GetIdentifier()
        }
        return lambda.GetIdentifier() + "$" + count.toString()
    }

    private func CreateCCFunction(funcTy: FuncType, identifier: String, srcCodeIdentifier: String,
        genericTypeParams!: ArrayList<GenericType> = ArrayList<GenericType>()): Function {
        let fn = builder.CreateFunction(funcTy, identifier, srcCodeIdentifier: srcCodeIdentifier,
            rawMangledName: identifier, packageName: CurrentPackage().GetName(),
            genericTypeParams: genericTypeParams)
        AddFunctionToPackage(fn)
        return fn
    }

    private func SetMemberMethodAttr(fn: Function): Unit {
        fn.EnableAttr(Attribute.PUBLIC)
        fn.EnableAttr(Attribute.VIRTUAL)
    }

    private func SetObjectSuperClass(classDef: ClassDef): Unit {
        if (let Some(objectTy) <- builder.context.GetObjectTy()) {
            classDef.SetSuperClassTy(objectTy)
        }
    }

    private func MarkAutoEnvClass(classDef: ClassDef): Unit {
        classDef.SetAnnotation(CC_AUTO_ENV_CLASS_ANNOTATION, "true")
    }

    private func AddFunctionToPackage(fn: Function): Unit {
        if (CurrentPackage().TryGetGlobalFunc(fn.GetIdentifier()).isNone()) {
            CurrentPackage().AddGlobalFunc(fn)
        }
    }

    private func AddClassToPackage(classDef: ClassDef): Unit {
        if (CurrentPackage().TryGetClassDef(classDef.GetIdentifier()).isNone()) {
            CurrentPackage().AddClass(classDef)
        }
    }

    private func RequireResult(expr: Expression): LocalVar {
        return expr.GetResult() ?? throw IllegalStateException("ClosureConversion expression has no result")
    }

    private func RequireClassType(classDef: ClassDef): ClassType {
        let ty = classDef.GetType() ??
            throw IllegalStateException("ClosureConversion class has no type: " + classDef.GetIdentifier())
        return (ty as ClassType) ??
            throw IllegalStateException("ClosureConversion class has no class type: " + classDef.GetIdentifier())
    }

    private func TypesFromGenerics(genericTypes: ArrayList<GenericType>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (genericTy in genericTypes) {
            out.add(genericTy)
        }
        return out
    }

    private func FindMethodBySrcName(def: ClassDef, name: String): Option<Function> {
        for (method in def.GetMethods()) {
            if (method.GetSrcCodeIdentifier() == name || method.GetIdentifierWithoutPrefix() == name) {
                return Some(method)
            }
        }
        return None
    }

    private func IsAutoEnvDef(def: ClassDef): Bool {
        return def.GetAnnotation(CC_AUTO_ENV_CLASS_ANNOTATION).isSome()
    }

    private func IsInstAutoEnvBaseDef(def: ClassDef): Bool {
        return def.GetAnnotation(CC_AUTO_ENV_INST_BASE_ANNOTATION).isSome()
    }

    private func GenericOverrideFuncName(srcFunc: Function): String {
        return ReplaceManglePrefixWith(srcFunc.GetIdentifierWithoutPrefix(), CC_FUNC_PREFIX) + "$g"
    }

    private func InstOverrideFuncName(srcFunc: Function): String {
        return ReplaceManglePrefixWith(srcFunc.GetIdentifierWithoutPrefix(), CC_FUNC_PREFIX) + "$i"
    }

    private func GenerateCapturedMemberName(value: Value): String {
        let srcName = value.GetSrcCodeIdentifier()
        if (!srcName.isEmpty()) {
            return srcName
        }
        return value.GetIdentifier()
    }

    private func IsClosureConversionGeneratedFunction(fn: Function): Bool {
        return StripGlobalPrefix(fn.GetIdentifierWithoutPrefix()).startsWith(CC_FUNC_PREFIX)
    }

    private func StripGlobalPrefix(identifier: String): String {
        if (identifier.startsWith("@")) {
            return identifier[1..]
        }
        return identifier
    }

    private func ReplaceManglePrefixWith(identifier: String, newPrefix: String): String {
        if (identifier.startsWith(MANGLE_CANGJIE_PREFIX)) {
            return newPrefix + identifier[MANGLE_CANGJIE_PREFIX.size..]
        }
        throw IllegalArgumentException("Mangle name has no _C prefix to be replaced: " + identifier)
    }

    private func TypeKey(ty: Type): String {
        return ty.ToString().replace(" ", "_").replace(",", "_").replace("(", "_").replace(")", "_").
            replace("<", "_").replace(">", "_").replace("&", "R").replace("-", "_").replace(":", "_").
            replace(".", "_")
    }

    private func GenericTypeKey(ty: GenericType): String {
        return ty.GetIdentifier() + "#" + ty.GetSrcCodeIdentifier()
    }
}

private func ContainsLambda(values: ArrayList<Lambda>, lambdaExpr: Lambda): Bool {
    for (value in values) {
        if (value.nodeId == lambdaExpr.nodeId) {
            return true
        }
    }
    return false
}
