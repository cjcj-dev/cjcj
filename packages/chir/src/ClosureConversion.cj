package cjcj::chir

import std.collection.*
import cjcj::basic.Linkage as BasicLinkage
import cjcj::option.GlobalOptions
import cjcj::utils.{CJC_ASSERT, StaticCast}
import cjcj::utils.ProfileRecorder

private let GENERIC_VIRTUAL_FUNC: String = "$GenericVirtualFunc"
private let INST_VIRTUAL_FUNC: String = "$InstVirtualFunc"
private let CC_GENERIC_BASE_PREFIX: String = "$Cg"
private let CC_INSTANTIATED_BASE_PREFIX: String = "$Ci"
private let CC_FUNC_IMPL_PREFIX: String = "$Cf"
private let CC_LAMBDA_IMPL_PREFIX: String = "$Cl"
private let CC_CAPTURED_PREFIX: String = "$Captured_"
private let CC_FUNC_PREFIX: String = "_CC"
private let MANGLE_CANGJIE_PREFIX: String = "_C"
private let GENERIC_THIS_SRC_NAME: String = "This"

private func LiftCustomDefType(def: CustomTypeDef, converter: TypeConverterForCC): Unit {
    let preVisit = { expr: Expression =>
        converter.VisitExpr(expr)
        return VisitResult.CONTINUE
    }
    for (method in def.GetMethods()) {
        Visitor.Visit(method, preVisit)
        converter.VisitValue(method)
    }
    converter.VisitDef(def)
}

public class ClosureConversion {
    private let builder: CHIRBuilder
    private let opts: GlobalOptions
    private var pkg: Option<Package> = None
    private let genericAutoEnvBaseDefs: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let instAutoEnvBaseDefs: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let instAutoEnvWrapperDefs: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let autoEnvImplDefs: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let boxClassMap: HashMap<String, ClassDef> = HashMap<String, ClassDef>()
    private let convertedCache: HashMap<Int64, Function> = HashMap<Int64, Function>()
    private let duplicateLambdaName: HashMap<String, Int64> = HashMap<String, Int64>()
    private let typeConvertMap: HashMap<String, Type> = HashMap<String, Type>()
    private let needConvertedGenericTys: HashMap<Int64, GenericType> = HashMap<Int64, GenericType>()
    private let srcCodeImportedFuncs: ArrayList<Function> = ArrayList<Function>()
    private let uselessClasses: ArrayList<ClassDef> = ArrayList<ClassDef>()
    private let uselessLambda: ArrayList<Function> = ArrayList<Function>()

    public init(builder: CHIRBuilder, opts!: GlobalOptions = GlobalOptions(),
        srcCodeImportedFuncs!: ArrayList<Function> = ArrayList<Function>()) {
        this.builder = builder
        this.opts = opts
        for (fn in srcCodeImportedFuncs) {
            this.srcCodeImportedFuncs.add(fn)
        }
    }

    public func GetUselessClassDef(): ArrayList<ClassDef> {
        return uselessClasses.clone()
    }

    public func GetUselessLambda(): ArrayList<Function> {
        return uselessLambda.clone()
    }

    public func RunOnPackage(pkg: Package): Unit {
        this.pkg = pkg
        ConvertGlobalFunctions(pkg)
        // GAP_TODO: C++ runs DoFunctionInlineForLambda(InlineLambda) here on this collection
        // (ClosureConversion.cpp:3160-3162), gated by FUNC_INLINING at O2 (LambdaInline.cpp:61);
        // InlineLambda is not yet ported, so this first collection's result is unused.
        let _ = CollectNestedFunctions(pkg)
        let nestedFuncs = CollectNestedFunctions(pkg)
        ConvertNestedFunctions(nestedFuncs)
        ConvertExpressions(pkg)
        LiftType(pkg)
        ModifyTypeMismatchInVTable()
        ModifyTypeMismatchInExpr()
        CreateVTableForAutoEnvDef()
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

    private func CreateVTableForAutoEnvDef(): Unit {
        try (recorder = ProfileRecorder("ClosureConversion", "CreateVTableForAutoEnvDef")) {
            let defs = ArrayList<CustomTypeDef>()
            for ((_, genericDef) in genericAutoEnvBaseDefs) {
                defs.add(genericDef)
            }
            for ((_, instDef) in instAutoEnvBaseDefs) {
                defs.add(instDef)
            }
            for ((_, wrapperDef) in instAutoEnvWrapperDefs) {
                defs.add(wrapperDef)
            }
            for ((_, implDef) in autoEnvImplDefs) {
                defs.add(implDef)
            }
            let generator = GenerateVTable(CurrentPackage(), defs, builder, opts, "CreateVTableForAutoEnvDef")
            generator.CreateVTable()
            generator.SetSrcFuncType()
        }
    }

    private func ConvertNestedFunctions(funcs: ArrayList<Lambda>): Unit {
        for (lambdaFunc in funcs) {
            RecordDuplicateLambdaName(lambdaFunc)
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
            RemoveGetInstantiateValue(users)
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
            }
            RemoveGetInstantiateValue(users)
        }
    }

    private func LiftType(pkg: Package): Unit {
        let convertTypeToClosure: ConvertTypeFunc = { ty: Type => ConvertTypeToClosureType(ty) }
        func convertTypeToInstBase(ty: Type): Type {
            let funcType = StaticCast<FuncType>(ty)
            let autoEnvBaseDef = GetOrCreateAutoEnvBaseDef(funcType)
            let nestedConverter = TypeConverterForCC(convertTypeToClosure, convertTypeToInstBase, builder)
            LiftCustomDefType(autoEnvBaseDef, nestedConverter)
            let convertedFuncType = ConvertFuncArgsAndRetType(funcType)
            return builder.context.GetRefTy(InstantiateAutoEnvBaseType(autoEnvBaseDef, convertedFuncType))
        }
        let converter = TypeConverterForCC(convertTypeToClosure, convertTypeToInstBase, builder)
        let preVisit = { expr: Expression =>
            converter.VisitExpr(expr)
            return VisitResult.CONTINUE
        }
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (fn.GetBody().isSome()) {
                Visitor.Visit(fn, preVisit)
            }
            converter.VisitValue(fn)
        }
        for (globalVar in pkg.GetGlobalVars()) {
            converter.VisitValue(globalVar)
        }
        for (def in pkg.GetAllCustomTypeDef()) {
            if (def.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            converter.VisitDef(def)
        }
        LiftGenericTypes()
        for ((_, ty) in builder.GetAllCustomTypes()) {
            ty.ResetAllInstantiatedType()
        }
    }

    private func ConvertExpressions(pkg: Package): Unit {
        let funcs = pkg.GetGlobalFuncsWithBody()
        for (fn in funcs) {
            if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
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
                if (TypeCastNeedConvertToBox(expr)) {
                    let cast = (expr as TypeCast) ??
                        throw IllegalStateException("ClosureConversion TypeCast branch is not a TypeCast")
                    let resultTy = cast.GetResultType() ??
                        throw IllegalStateException("ClosureConversion TypeCast has no result type")
                    let parent = cast.GetParentBlock() ??
                        throw IllegalStateException("ClosureConversion TypeCast has no parent block")
                    let box = builder.CreateBox(resultTy, cast.GetSourceValue(), parent)
                    cast.ReplaceWith(box)
                    continue
                }
                if (TypeCastNeedConvertToUnBox(expr)) {
                    let cast = (expr as TypeCast) ??
                        throw IllegalStateException("ClosureConversion TypeCast branch is not a TypeCast")
                    let resultTy = cast.GetResultType() ??
                        throw IllegalStateException("ClosureConversion TypeCast has no result type")
                    let parent = cast.GetParentBlock() ??
                        throw IllegalStateException("ClosureConversion TypeCast has no parent block")
                    let unbox = builder.CreateUnBox(resultTy, cast.GetSourceValue(), parent)
                    cast.ReplaceWith(unbox)
                    continue
                }
                if (BoxNeedConvertToTypeCast(expr)) {
                    let box = (expr as Box) ??
                        throw IllegalStateException("ClosureConversion Box branch is not a Box")
                    let resultTy = box.GetResultType() ??
                        throw IllegalStateException("ClosureConversion Box has no result type")
                    let parent = box.GetParentBlock() ??
                        throw IllegalStateException("ClosureConversion Box has no parent block")
                    let typecast = builder.CreateTypeCast(resultTy, box.GetSourceValue(), parent)
                    box.ReplaceWith(typecast)
                    continue
                }
                if (UnBoxNeedConvertToTypeCast(expr)) {
                    let unbox = (expr as UnBox) ??
                        throw IllegalStateException("ClosureConversion UnBox branch is not an UnBox")
                    let resultTy = unbox.GetResultType() ??
                        throw IllegalStateException("ClosureConversion UnBox has no result type")
                    let parent = unbox.GetParentBlock() ??
                        throw IllegalStateException("ClosureConversion UnBox has no parent block")
                    let typecast = builder.CreateTypeCast(resultTy, unbox.GetSourceValue(), parent)
                    unbox.ReplaceWith(typecast)
                    continue
                }
                for (subGroup in expr.GetBlockGroups()) {
                    ConvertExpressionsInBlockGroup(subGroup)
                }
            }
        }
    }

    private func ConvertTypeToClosureType(ty: Type): Type {
        if (ty.IsPrimitive() || ty.IsInvalid() || ty.IsAny() || ty.IsVoid() || ty.IsCFunc() ||
            ty.IsCString() || ty.IsThis()) {
            return ty
        }
        if (ty.IsGeneric()) {
            let genericTy = StaticCast<GenericType>(ty)
            needConvertedGenericTys[genericTy.objectId] = genericTy
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

    private func LiftGenericTypes(): Unit {
        let temp = needConvertedGenericTys.clone()
        for ((_, ty) in temp) {
            let newUpperBounds = ArrayList<Type>()
            for (upperBound in ty.GetUpperBounds()) {
                newUpperBounds.add(ConvertTypeToClosureType(upperBound))
            }
            ty.SetUpperBounds(newUpperBounds)
        }
    }

    private func ConvertTypeArgs(types: ArrayList<Type>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (ty in types) {
            out.add(ConvertTypeToClosureType(ty))
        }
        return out
    }

    private func ConvertFuncType(funcTy: FuncType): Type {
        let autoEnvBaseDef = GetOrCreateGenericAutoEnvBaseDef(funcTy.GetParamTypes().size)
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
        let classTy = builder.context.GetClassTy(classDef, paramsAndRet)
        classDef.SetType(classTy)
        SetAutoEnvBaseDefAttr(classDef)
        classDef.EnableAttr(Attribute.GENERIC)
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
        SetAutoEnvBaseDefAttr(classDef)
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
        method.EnableAttr(Attribute.NO_DEBUG_INFO)
        var paramIdx: Int64 = 0
        while (paramIdx + 1 < paramsAndRetType.size) {
            builder.CreateParameter(paramTypes[paramIdx], INVALID_LOCATION, method)
            paramIdx++
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
        let parentFunc = lambda.GetTopLevelFunc() ??
            throw IllegalStateException("ClosureConversion lambda has no top-level function")
        if (ContainsFunction(srcCodeImportedFuncs, parentFunc)) {
            AddClassNoDup(uselessClasses, classDef)
            AddFunctionNoDup(uselessLambda, globalFunc)
        }
        CreateGenericOverrideMethodInAutoEnvImplDef(classDef, globalFunc, genericMap)
        CreateInstOverrideMethodInAutoEnvImplDef(classDef, globalFunc, genericMap)
        autoEnvImplDefs[className] = classDef
        return classDef
    }

    private func CreateAutoEnvImplDef(className: String, genericTypes: ArrayList<GenericType>, srcFunc: Value,
        superClassDef: ClassDef, genericMap: HashMap<String, Type>): ClassDef {
        let classDef = builder.CreateClassDef(CurrentPackage().GetName(), className, "")
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
            let newGeneric = (classTypeArgs[idx] as GenericType).getOrThrow()
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
        SetAutoEnvImplDefAttr(classDef)
        if (!classTypeArgs.isEmpty()) {
            classDef.EnableAttr(Attribute.GENERIC)
        }
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
        SetMemberMethodAttr(method, srcFunc.TestAttr(Attribute.CONST))
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
        SetMemberMethodAttr(method, srcFunc.TestAttr(Attribute.CONST))
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
        // ClosureConversion.cpp:371 GetMethodTypeInAutoEnvGenericDef: def.GetType()->IsAutoEnvGenericBase().
        if (def.GetType().getOrThrow().IsAutoEnvGenericBase()) {
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
            builder.CreateParameter(paramTy, INVALID_LOCATION, method)
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
            let paramTy = params[idx].GetType() ??
                throw IllegalStateException("ClosureConversion parameter has no type")
            if (paramTy.IsCJFunc()) {
                CJC_ASSERT(expectedTy == paramTy)
                applyArgs.add(RequireResult(builder.CreateTypeCast(paramTy, params[idx], entry)))
            } else {
                applyArgs.add(TypeCastOrBoxIfNeeded(params[idx], expectedTy, builder, entry, INVALID_LOCATION))
            }
            idx++
        }

        let applyRetTy = SubstituteGenericTypes(srcFuncTy.GetReturnType(), genericMap)
        let apply = builder.CreateApply(applyRetTy, srcFunc, FuncCallContext(args: applyArgs,
            instTypeArgs: CreateSubstitutedInstTypeArgs(srcFunc, genericMap),
            thisType: CreateSubstitutedThisType(srcFunc, genericMap)), entry)
        let applyResult = TypeCastOrBoxIfNeeded(RequireResult(apply), methodRetTy, builder, entry, INVALID_LOCATION)
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
            builder.CreateParameter(paramTy, INVALID_LOCATION, method)
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
        SetLiftedLambdaAttr(globalFunc, lambda)
        let sigInfo = FuncSigInfo(lambdaTy, funcName: lambda.GetSrcCodeIdentifier(),
            genericTypeParams: lambda.GetGenericTypeParams())
        globalFunc.SetOriginalLambdaInfo(sigInfo)
        if (let Some(parentFunc) <- lambda.GetTopLevelFunc()) {
            globalFunc.InheritIDFromFunc(parentFunc)
        }
        let thisParam = builder.CreateParameter(params[0], INVALID_LOCATION, globalFunc)
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
        ReplaceThisTypeInApplyAndInvoke(lambda, convertedGenericParams)
        globalFunc.InitBody(body)
        if (let Some(retValue) <- lambda.GetReturnValue()) {
            globalFunc.SetReturnValue(retValue)
        }
        var envParamDebug: Option<Expression> = None
        if (classDef.GetAllInstanceVarNum() != 0) {
            let debugExpr = builder.CreateDebug(builder.context.GetUnitTy(), thisParam, "$env",
                globalFunc.GetEntryBlock().getOrThrow())
            globalFunc.GetEntryBlock().getOrThrow().InsertExprIntoHead(debugExpr)
            envParamDebug = Some(debugExpr)
        }
        ReplaceEnvVarWithMemberVar(capturedValues, envParamDebug, globalFunc, thisParam)
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

    // Mirror C++ ReplaceThisTypeInApplyAndInvoke
    // (src/CHIR/Transformation/ClosureConversion.cpp:464-482).
    private func ReplaceThisTypeInApplyAndInvoke(lambda: Lambda, genericTypeParams: ArrayList<GenericType>): Unit {
        let result = lambda.GetResult() ??
            throw IllegalStateException("ClosureConversion lambda has no result")
        if (!NeedAddThisType(result)) {
            return
        }
        CJC_ASSERT(!genericTypeParams.isEmpty())
        let thisType = genericTypeParams[0]
        let body = lambda.GetBody() ??
            throw IllegalStateException("ClosureConversion lambda has no body")
        ConvertBlockGroupThisTypes(body, thisType)
    }

    private func ConvertBlockGroupThisTypes(group: BlockGroup, thisType: Type): Unit {
        for (block in group.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                ConvertExpressionThisTypes(expr, thisType)
                for (subGroup in expr.GetBlockGroups()) {
                    ConvertBlockGroupThisTypes(subGroup, thisType)
                }
            }
        }
    }

    private func ConvertExpressionThisTypes(expr: Expression, thisType: Type): Unit {
        if (let Some(result) <- expr.GetResult()) {
            ConvertValueThisType(result, thisType)
        }
        if (let Some(allocate) <- (expr as Allocate)) {
            allocate.SetType(ReplaceThisTypeToConcreteType(allocate.GetType(), thisType, builder))
        } else if (let Some(allocateWithException) <- (expr as AllocateWithException)) {
            allocateWithException.SetType(ReplaceThisTypeToConcreteType(allocateWithException.GetType(), thisType,
                builder))
        } else if (let Some(instanceOfExpr) <- (expr as InstanceOf)) {
            instanceOfExpr.SetTestedType(ReplaceThisTypeToConcreteType(instanceOfExpr.GetType(), thisType, builder))
        } else if (let Some(rawArrayAllocate) <- (expr as RawArrayAllocate)) {
            rawArrayAllocate.SetElementType(ReplaceThisTypeToConcreteType(rawArrayAllocate.GetElementType(), thisType,
                builder))
        } else if (let Some(rawArrayAllocateWithException) <- (expr as RawArrayAllocateWithException)) {
            rawArrayAllocateWithException.SetElementType(
                ReplaceThisTypeToConcreteType(rawArrayAllocateWithException.GetElementType(), thisType, builder))
        } else if (let Some(getRTTIStatic) <- (expr as GetRTTIStatic)) {
            getRTTIStatic.SetRTTIType(ReplaceThisTypeToConcreteType(getRTTIStatic.GetRTTIType(), thisType, builder))
        }
        if (let Some(call) <- (expr as FuncCall)) {
            ConvertFuncCallThisTypes(call, thisType)
        }
        if (let Some(callWithException) <- (expr as FuncCallWithException)) {
            ConvertFuncCallWithExceptionThisTypes(callWithException, thisType)
        }
        if (let Some(dispatch) <- (expr as DynamicDispatch)) {
            dispatch.SetMethodType(ConvertFuncParamsAndRetTypeWithThisType(dispatch.GetMethodType(), thisType))
        }
        if (let Some(dispatchWithException) <- (expr as DynamicDispatchWithException)) {
            dispatchWithException.SetMethodType(
                ConvertFuncParamsAndRetTypeWithThisType(dispatchWithException.GetMethodType(), thisType))
        }
        if (let Some(constant) <- (expr as Constant)) {
            ConvertValueThisType(constant.GetValue(), thisType)
        }
        if (let Some(intrinsic) <- (expr as Intrinsic)) {
            intrinsic.SetInstantiatedTypeArgs(ConvertTypeArgsWithThisType(intrinsic.GetInstantiatedTypeArgs(), thisType))
        }
        if (let Some(intrinsicWithException) <- (expr as IntrinsicWithException)) {
            intrinsicWithException.SetInstantiatedTypeArgs(
                ConvertTypeArgsWithThisType(intrinsicWithException.GetInstantiatedTypeArgs(), thisType))
        }
        if (let Some(getInstantiateValue) <- (expr as GetInstantiateValue)) {
            let instantiateTypes = getInstantiateValue.GetInstantiateTypesRef()
            var idx: Int64 = 0
            while (idx < instantiateTypes.size) {
                instantiateTypes[idx] = ReplaceThisTypeToConcreteType(instantiateTypes[idx], thisType, builder)
                idx++
            }
        }
        if (let Some(lambdaExpr) <- (expr as Lambda)) {
            if (let Some(lambdaTy) <- lambdaExpr.GetFuncType()) {
                lambdaExpr.SetFuncType(ConvertFuncParamsAndRetTypeWithThisType(lambdaTy, thisType))
            }
            for (param in lambdaExpr.GetParams()) {
                ConvertValueThisType(param, thisType)
            }
        }
    }

    private func ConvertFuncCallThisTypes(call: FuncCall, thisType: Type): Unit {
        if (let Some(rawThisTy) <- call.GetThisType()) {
            call.SetThisType(ReplaceThisTypeToConcreteType(rawThisTy, thisType, builder))
        }
        call.SetInstantiatedTypeArgs(ConvertTypeArgsWithThisType(call.GetInstantiatedTypeArgs(), thisType))
    }

    private func ConvertFuncCallWithExceptionThisTypes(call: FuncCallWithException, thisType: Type): Unit {
        if (let Some(rawThisTy) <- call.GetThisType()) {
            call.SetThisType(ReplaceThisTypeToConcreteType(rawThisTy, thisType, builder))
        }
        call.SetInstantiatedTypeArgs(ConvertTypeArgsWithThisType(call.GetInstantiatedTypeArgs(), thisType))
    }

    private func ConvertFuncParamsAndRetTypeWithThisType(funcTy: FuncType, thisType: Type): FuncType {
        let params = ArrayList<Type>()
        for (paramTy in funcTy.GetParamTypes()) {
            params.add(ReplaceThisTypeToConcreteType(paramTy, thisType, builder))
        }
        return builder.context.GetFuncTy(params, ReplaceThisTypeToConcreteType(funcTy.GetReturnType(), thisType, builder),
            hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
    }

    private func ConvertTypeArgsWithThisType(args: ArrayList<Type>, thisType: Type): ArrayList<Type> {
        let converted = ArrayList<Type>()
        for (arg in args) {
            converted.add(ReplaceThisTypeToConcreteType(arg, thisType, builder))
        }
        return converted
    }

    private func ConvertValueThisType(value: Value, thisType: Type): Unit {
        if (let Some(valueTy) <- value.GetType()) {
            value.SetType(ReplaceThisTypeToConcreteType(valueTy, thisType, builder))
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
        SetLiftedLambdaAttr(globalFunc, lambda)
        let sigInfo = FuncSigInfo(lambda.GetFuncType().getOrThrow(), funcName: lambda.GetSrcCodeIdentifier(),
            genericTypeParams: lambda.GetGenericTypeParams())
        globalFunc.SetOriginalLambdaInfo(sigInfo)
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

    private func ReplaceEnvVarWithMemberVar(capturedValues: ArrayList<Value>, firstExpr: Option<Expression>,
        globalFunc: Function, thisParam: Value): Unit {
        let entry = globalFunc.GetEntryBlock() ??
            throw IllegalStateException("ClosureConversion lifted function has no entry block")
        var lastExpr = firstExpr
        var capturedIndex: UInt64 = 0u64
        for (captured in capturedValues) {
            let capturedTy = captured.GetType() ??
                throw IllegalStateException("ClosureConversion captured value has no type")
            let fieldRefTy = if (IsMutableVarType(captured)) {
                capturedTy
            } else {
                builder.context.GetRefTy(capturedTy)
            }
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
        let converted = CastTypeFromAutoEnvRefToFuncType(fn.GetFuncType().getOrThrow(), baseObj, user,
            GetOutDefDeclaredTypes(fn))
        user.ReplaceOperand(fn, converted)
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
        let converted = CastTypeFromAutoEnvRefToFuncType((result.GetType().getOrThrow() as FuncType).getOrThrow(),
            autoEnvObj, user, GetOutDefDeclaredTypes(result))
        user.ReplaceOperand(result, converted)
    }

    private func CreateAutoEnvImplObject(parent: Block, autoEnvImplType: ClassType, envs: ArrayList<Value>,
        user: Expression, srcFunc: Value): LocalVar {
        let instantiateClassTy = GenerateInstantiatedClassType(autoEnvImplType, user, srcFunc)
        let refType = builder.context.GetRefTy(instantiateClassTy)
        let allocate = builder.CreateAllocate(refType, instantiateClassTy, parent)
        let obj = RequireResult(allocate)
        var idx: UInt64 = 0u64
        for (env in envs) {
            let path = ArrayList<UInt64>()
            path.add(idx)
            let store = builder.CreateStoreElementRef(env, obj, path, parent)
            store.MoveBefore(user)
            idx++
        }
        // If not moved to head, recursive lambda calls can leave unreachable expressions.
        parent.InsertExprIntoHead(allocate)
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
        if (let Some(giv) <- (user as GetInstantiateValue)) {
            let givInstTypes = giv.GetInstantiateTypes()
            let funcGenericParamNum = GetFuncGenericTypeParamNum(srcFunc)
            CJC_ASSERT(funcGenericParamNum <= autoEnvInstTypeArgs.size)
            CJC_ASSERT(funcGenericParamNum <= givInstTypes.size)
            let instArgsOffset = autoEnvInstTypeArgs.size - funcGenericParamNum
            let givInstTysOffset = givInstTypes.size - funcGenericParamNum
            var idx: Int64 = 0
            while (idx < funcGenericParamNum) {
                autoEnvInstTypeArgs[instArgsOffset + idx] = givInstTypes[givInstTysOffset + idx]
                idx++
            }
            let instTypeParams = GetInstTypeParamsForCustomTypeDef(givInstTypes, srcFunc)
            idx = 0
            while (idx < instTypeParams.size) {
                autoEnvInstTypeArgs[idx] = instTypeParams[idx]
                idx++
            }
        } else if (let Some(apply) <- (user as Apply)) {
            if (apply.GetCallee().nodeId == srcFunc.nodeId) {
                OverlayInstantiatedTypeArgs(autoEnvInstTypeArgs, apply.GetInstantiatedTypeArgs())
            }
        } else if (let Some(awe) <- (user as ApplyWithException)) {
            if (awe.GetCallee().nodeId == srcFunc.nodeId) {
                OverlayInstantiatedTypeArgs(autoEnvInstTypeArgs, awe.GetInstantiatedTypeArgs())
            }
        }
        if (NeedAddThisType(srcFunc)) {
            autoEnvInstTypeArgs.add(builder.context.GetThisTy(), at: 0)
        }
        CJC_ASSERT(autoEnvImplType.GetGenericArgs().size == autoEnvInstTypeArgs.size)
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

    private func GetFuncGenericTypeParamNum(srcFunc: Value): Int64 {
        if (let Some(fn) <- srcFunc.AsFunction()) {
            return fn.GetGenericTypeParams().size
        }
        let local = srcFunc.AsLocalVar() ??
            throw IllegalStateException("ClosureConversion generic-param source is not a function or lambda result")
        let lambda = (local.GetExpr().getOrThrow() as Lambda).getOrThrow()
        return lambda.GetGenericTypeParams().size
    }

    private func GetInstTypeParamsForCustomTypeDef(givInstTypes: ArrayList<Type>,
        srcFunc: Value): ArrayList<Type> {
        let result = ArrayList<Type>()
        let memberFunc = GetTopLevelFunctionForValue(srcFunc) ??
            throw IllegalStateException("ClosureConversion instantiated type source has no top-level function")
        let parentCustomTypeDef = memberFunc.GetParentCustomTypeDef() ?? return result
        if (let Some(extendDef) <- (parentCustomTypeDef as ExtendDef)) {
            let extendedType = extendDef.GetExtendedType() ??
                throw IllegalStateException("ClosureConversion extend def has no extended type")
            let genericTypeArgs = extendedType.GetTypeArgs()
            CJC_ASSERT(genericTypeArgs.size <= givInstTypes.size)
            let genericMap = HashMap<Int64, Type>()
            var idx: Int64 = 0
            while (idx < genericTypeArgs.size) {
                let newMap = genericTypeArgs[idx].CalculateGenericTyMapping(givInstTypes[idx])
                CJC_ASSERT(newMap[0])
                for ((key, value) in newMap[1]) {
                    if (!genericMap.contains(key)) {
                        genericMap[key] = value
                    }
                }
                idx++
            }
            for (ty in extendDef.GetGenericTypeParams()) {
                result.add(genericMap.get(ty.objectId).getOrThrow())
            }
            return result
        }
        let offset = parentCustomTypeDef.GetGenericTypeParams().size
        CJC_ASSERT(offset <= givInstTypes.size)
        var idx2: Int64 = 0
        while (idx2 < offset) {
            result.add(givInstTypes[idx2])
            idx2++
        }
        return result
    }

    private func GetOutDefDeclaredTypes(innerDef: Value): ArrayList<Type> {
        let visibleGenericTypes = GetVisiableGenericTypes(innerDef)
        let instArgs = ArrayList<Type>()
        for (genericTy in visibleGenericTypes) {
            instArgs.add(genericTy)
        }
        if (let Some(parentFunc) <- GetTopLevelFunctionForValue(innerDef)) {
            if (let Some(parentDef) <- parentFunc.GetParentCustomTypeDef()) {
                if (let Some(extendDef) <- (parentDef as ExtendDef)) {
                    let exGenericTypes = extendDef.GetGenericTypeParams()
                    var removeCount: Int64 = 0
                    while (removeCount < exGenericTypes.size && !instArgs.isEmpty()) {
                        instArgs.remove(at: 0)
                        removeCount++
                    }
                    if (let Some(extendedTy) <- extendDef.GetExtendedType()) {
                        let exTypeArgs = extendedTy.GetTypeArgs()
                        var insertIdx: Int64 = 0
                        for (argTy in exTypeArgs) {
                            instArgs.add(argTy, at: insertIdx)
                            insertIdx++
                        }
                    }
                }
            }
        }
        return instArgs
    }

    private func GetTopLevelFunctionForValue(value: Value): Option<Function> {
        if (let Some(fn) <- value.AsFunction()) {
            return Some(fn)
        }
        if (let Some(param) <- value.AsParameter()) {
            return param.GetTopLevelFunc()
        }
        if (let Some(local) <- value.AsLocalVar()) {
            return local.GetTopLevelFunc()
        }
        return None
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

    private func RemoveGetInstantiateValue(maybeGetInsValue: ArrayList<Expression>): Unit {
        for (expr in maybeGetInsValue) {
            if (let Some(getInsValue) <- (expr as GetInstantiateValue)) {
                let op = getInsValue.GetGenericResult()
                let getInsResult = getInsValue.GetResult() ??
                    throw IllegalStateException("ClosureConversion GetInstantiateValue has no result")
                let users = getInsResult.GetUsers()
                for (user in users) {
                    user.ReplaceOperand(getInsResult, op)
                }
                getInsValue.RemoveSelfFromBlock()
            }
        }
    }

    private func CastTypeFromAutoEnvRefToFuncType(srcFuncType: FuncType, autoEnvObj: Value, user: Expression,
        genericTypeParams: ArrayList<Type>): Value {
        var unboxRetTy = RemoveBoxTypeShellIfNeed(srcFuncType)
        if (let Some(giv) <- (user as GetInstantiateValue)) {
            let allInstTypes = giv.GetInstantiateTypes()
            let replaceMap = HashMap<Int64, Type>()
            CJC_ASSERT(allInstTypes.size >= genericTypeParams.size)
            let offset = allInstTypes.size - genericTypeParams.size
            var instIdx = offset
            var genericIdx: Int64 = 0
            while (instIdx < allInstTypes.size) {
                if (let Some(genericTy) <- (genericTypeParams[genericIdx] as GenericType)) {
                    replaceMap[genericTy.objectId] = allInstTypes[instIdx]
                }
                instIdx++
                genericIdx++
            }
            unboxRetTy = ReplaceRawGenericArgType(unboxRetTy, replaceMap, builder)
        } else {
            let autoEnvObjTy = (autoEnvObj.GetType().getOrThrow() as RefType).getOrThrow().GetBaseType()
            unboxRetTy = GetFuncTypeWithoutThisPtrFromAutoEnvType((autoEnvObjTy as ClassType).getOrThrow())
        }
        let parent = user.GetParentBlock() ??
            throw IllegalStateException("ClosureConversion auto-env cast user has no parent block")
        let unbox = builder.CreateUnBox(unboxRetTy, autoEnvObj, parent)
        unbox.MoveBefore(user)
        return RequireResult(unbox)
    }

    private func GetFuncTypeWithoutThisPtrFromAutoEnvType(autoEnvType: ClassType): FuncType {
        CJC_ASSERT(autoEnvType.IsAutoEnv())
        if (autoEnvType.IsAutoEnvBase()) {
            let (_, methodTy) = GetFuncTypeFromAutoEnvBaseDef(autoEnvType.GetClassDef())
            let params = methodTy.GetParamTypes()
            let newParams = ArrayList<Type>()
            var idx: Int64 = 1
            while (idx < params.size) {
                newParams.add(params[idx])
                idx++
            }
            return builder.context.GetFuncTy(newParams, methodTy.GetReturnType(),
                hasVarLenParam: methodTy.HasVarArg(), isCFunc: methodTy.IsCFunc())
        }
        return GetFuncTypeWithoutThisPtrFromAutoEnvType(autoEnvType.GetSuperClassTy(builder: builder).getOrThrow())
    }

    private func BoxAllMutableVars(rawEnvs: ArrayList<Value>): ArrayList<Value> {
        let boxedEnvs = ArrayList<Value>()
        for (env in rawEnvs) {
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
        let invoke = builder.CreateInvoke(retTy, invokeContext, parent)
        invoke.SetVirtualMethodOffset(0u64)
        apply.ReplaceWith(invoke)
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

    private func ResolveAutoEnvCallParentType(callee: Value, call: Expression): ClassType {
        if (let Some(calleeTy) <- callee.GetType()) {
            if (let Some(funcTy) <- (calleeTy as FuncType)) {
                let baseDef = GetOrCreateAutoEnvBaseDef(funcTy)
                let instParentType = InstantiateAutoEnvBaseType(baseDef, funcTy)
                return InstantiateAutoEnvGenericBaseType(instParentType, call)
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

    private func GetAutoEnvGenericBase(closureType: ClassType): ClassType {
        if (closureType.IsAutoEnvGenericBase()) {
            return closureType
        }
        return GetAutoEnvGenericBase(closureType.GetSuperClassTy(builder: builder).getOrThrow())
    }

    private func InstantiateAutoEnvGenericBaseType(closureType: ClassType, expr: Expression): ClassType {
        if (!closureType.IsGenericRelated()) {
            return closureType
        }
        let funcTypeArgs = ArrayList<Type>()
        if (let Some(apply) <- (expr as Apply)) {
            for (arg in apply.GetArgs()) {
                funcTypeArgs.add(arg.GetType().getOrThrow())
            }
        } else if (let Some(applyE) <- (expr as ApplyWithException)) {
            for (arg in applyE.GetArgs()) {
                funcTypeArgs.add(arg.GetType().getOrThrow())
            }
        } else {
            return closureType
        }
        funcTypeArgs.add(expr.GetResultType().getOrThrow())
        let autoEnvGenericBase = GetAutoEnvGenericBase(closureType)
        let autoEnvTypeArgs = autoEnvGenericBase.GetGenericArgs()
        let replaceTable = HashMap<Int64, Type>()
        CJC_ASSERT(autoEnvTypeArgs.size == funcTypeArgs.size)
        var idx: Int64 = 0
        while (idx < funcTypeArgs.size) {
            if (autoEnvTypeArgs[idx].IsGeneric() && !funcTypeArgs[idx].IsGeneric()) {
                replaceTable[(autoEnvTypeArgs[idx] as GenericType).getOrThrow().objectId] = funcTypeArgs[idx]
            }
            idx++
        }
        return (ReplaceRawGenericArgType(closureType, replaceTable, builder) as ClassType).getOrThrow()
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
        if (apply.GetCallee().IsFunc()) {
            return false
        }
        if (let Some(calleeTy) <- apply.GetCallee().GetType()) {
            return calleeTy.IsCJFunc()
        }
        return false
    }

    private func ApplyWithExceptionNeedConvertToInvokeWithException(apply: ApplyWithException): Bool {
        if (apply.GetCallee().IsFunc()) {
            return false
        }
        if (let Some(calleeTy) <- apply.GetCallee().GetType()) {
            return calleeTy.IsCJFunc()
        }
        return false
    }

    private func TypeCastNeedConvertToBox(expr: Expression): Bool {
        let typecast = (expr as TypeCast) ?? return false
        let targetTy = typecast.GetTargetTy() ??
            throw IllegalStateException("ClosureConversion TypeCast has no target type")
        let sourceTy = typecast.GetSourceTy() ??
            throw IllegalStateException("ClosureConversion TypeCast has no source type")
        return targetTy.IsCJFunc() && !sourceTy.IsCJFunc()
    }

    private func TypeCastNeedConvertToUnBox(expr: Expression): Bool {
        let typecast = (expr as TypeCast) ?? return false
        let sourceTy = typecast.GetSourceTy() ??
            throw IllegalStateException("ClosureConversion TypeCast has no source type")
        let targetTy = typecast.GetTargetTy() ??
            throw IllegalStateException("ClosureConversion TypeCast has no target type")
        return sourceTy.IsCJFunc() && !targetTy.IsCJFunc()
    }

    private func BoxNeedConvertToTypeCast(expr: Expression): Bool {
        let box = (expr as Box) ?? return false
        let sourceTy = box.GetSourceTy() ??
            throw IllegalStateException("ClosureConversion Box has no source type")
        return sourceTy.IsCJFunc()
    }

    private func UnBoxNeedConvertToTypeCast(expr: Expression): Bool {
        let unbox = (expr as UnBox) ?? return false
        let targetTy = unbox.GetTargetTy() ??
            throw IllegalStateException("ClosureConversion UnBox has no target type")
        return targetTy.IsCJFunc()
    }

    private func InstantiateAutoEnvBaseType(autoEnvBaseDef: ClassDef, funcTy: FuncType): ClassType {
        let args = if (autoEnvBaseDef.GetGenericTypeParams().isEmpty()) {
            ArrayList<Type>()
        } else {
            funcTy.GetTypeArgs()
        }
        return builder.context.GetClassTy(autoEnvBaseDef, args)
    }

    private func OperandNeedTypeCast(args: ArrayList<Value>, paramTypes: ArrayList<Type>,
        offset: Int64): ArrayList<Int64> {
        let index = ArrayList<Int64>()
        CJC_ASSERT(args.size == paramTypes.size)
        var idx: Int64 = 0
        while (idx < paramTypes.size) {
            let paramTy = paramTypes[idx].StripAllRefs()
            let argTy = args[idx].GetType().getOrThrow().StripAllRefs()
            if (!paramTy.IsAutoEnvBase() || !argTy.IsAutoEnvBase()) {
                idx++
                continue
            }
            let paramTyDef = (paramTy as ClassType).getOrThrow().GetClassDef()
            let argTyDef = (argTy as ClassType).getOrThrow().GetClassDef()
            if (let Some(argSuperDef) <- argTyDef.GetSuperClassDef()) {
                if (refEq(argSuperDef, paramTyDef)) {
                    index.add(idx + offset)
                }
            }
            idx++
        }
        return index
    }

    private func GetFieldBaseType(base: Value): Option<Type> {
        if (!base.IsLocalVar()) {
            return base.GetType()
        }
        let expr = (base as LocalVar).getOrThrow().GetExpr() ?? return base.GetType()
        if (expr.GetExprKind() != ExprKind.TYPECAST) {
            return base.GetType()
        }
        let srcValType = (expr as TypeCast).getOrThrow().GetSourceValue().GetType().getOrThrow()
        if (srcValType.IsEnum()) {
            return None
        }
        return base.GetType()
    }

    private func FieldRetValNeedWrapper(e: Field): Bool {
        let fieldRetType = e.GetResult().getOrThrow().GetType().getOrThrow().StripAllRefs()
        if (!fieldRetType.IsAutoEnvInstBase()) {
            return false
        }
        var declaredType = GetFieldBaseType(e.GetBase())
        if (declaredType.isNone()) {
            return true
        }
        for (idx in e.GetPath()) {
            declaredType = GetFieldOfType(declaredType.getOrThrow(), idx, builder)
            CJC_ASSERT(declaredType.isSome())
        }
        return !declaredType.getOrThrow().StripAllRefs().IsAutoEnvInstBase()
    }

    private func IsAutoEnvGenericType(ty: Type): Bool {
        if (!ty.IsAutoEnv()) {
            return false
        }
        if (ty.IsAutoEnvGenericBase()) {
            return true
        }
        let classTy = (ty as ClassType).getOrThrow()
        let parentType = classTy.GetClassDef().GetSuperClassTy()
        return parentType.isSome() && parentType.getOrThrow().IsAutoEnvGenericBase() && !ty.IsAutoEnvInstBase()
    }

    private func EnumConstructorNeedTypeCast(e: Expression): (Bool, ArrayList<Int64>) {
        let index = ArrayList<Int64>()
        let tuple = (e as Tuple) ?? return (false, index)
        let resultType = tuple.GetResult().getOrThrow().GetType().getOrThrow()
        if (!resultType.IsEnum()) {
            return (false, index)
        }
        let enumDef = (resultType as EnumType).getOrThrow().GetEnumDef()
        let selectorExpr = ((tuple.GetOperand(0) as LocalVar).getOrThrow().GetExpr().getOrThrow() as Constant).
            getOrThrow()
        var ctorIndex: Int64 = 0
        if (selectorExpr.IsIntLit()) {
            ctorIndex = Int64(selectorExpr.GetUnsignedIntLitVal())
        } else if (selectorExpr.IsBoolLit()) {
            ctorIndex = if (selectorExpr.GetBoolLitVal()) { 1 } else { 0 }
        } else {
            throw IllegalStateException("ClosureConversion enum constructor selector is not int or bool")
        }
        let constructor = enumDef.GetCtor(ctorIndex)
        let paramTypes = constructor.funcType.getOrThrow().GetParamTypes()
        let args = tuple.GetOperands()
        args.remove(at: 0)
        let castIndex = OperandNeedTypeCast(args, paramTypes, 1)
        return (!castIndex.isEmpty(), castIndex)
    }

    private func TupleNeedTypeCast(e: Expression): (Bool, ArrayList<Int64>) {
        let index = ArrayList<Int64>()
        let tuple = (e as Tuple) ?? return (false, index)
        let resultType = tuple.GetResult().getOrThrow().GetType().getOrThrow()
        let tupleType = (resultType as TupleType) ?? return (false, index)
        let castIndex = OperandNeedTypeCast(tuple.GetOperands(), tupleType.GetElementTypes(), 0)
        return (!castIndex.isEmpty(), castIndex)
    }

    private func AddTypeCastForOperand(expr: Expression, index: ArrayList<Int64>): Unit {
        let parentBlock = expr.GetParentBlock() ??
            throw IllegalStateException("ClosureConversion typecast operand has no parent block")
        for (idx in index) {
            let op = expr.GetOperand(idx)
            let opClassTy = (op.GetType().getOrThrow().StripAllRefs() as ClassType).getOrThrow()
            let expectedType = builder.context.GetRefTy(opClassTy.GetClassDef().GetSuperClassTy().getOrThrow())
            let typecast = builder.CreateTypeCast(expectedType, op, parentBlock)
            typecast.MoveBefore(expr)
            expr.ReplaceOperand(idx, RequireResult(typecast))
        }
    }

    private func ReplaceOperandWithAutoEnvWrapperClass(op: Value, autoEnvWrapperClass: Value,
        skip: ArrayList<Expression>): Unit {
        for (user in op.GetUsers()) {
            var shouldSkip = user.GetExprKind() == ExprKind.INSTANCEOF
            if (!shouldSkip) {
                for (skipExpr in skip) {
                    if (refEq(skipExpr, user)) {
                        shouldSkip = true
                        break
                    }
                }
            }
            if (!shouldSkip) {
                user.ReplaceOperand(op, autoEnvWrapperClass)
            }
        }
    }

    private func GetFuncTypeFromAutoEnvBaseDef(autoEnvBaseDef: ClassDef): (String, FuncType) {
        let methods = autoEnvBaseDef.GetMethods()
        CJC_ASSERT(methods.size == 1)
        return (methods[0].GetSrcCodeIdentifier(), methods[0].GetFuncType().getOrThrow())
    }

    private func CreateAutoEnvWrapper(className: String, superClassType: ClassType): ClassDef {
        let wrapperClassDef = builder.CreateClassDef(CurrentPackage().GetName(), className, "")
        let classType = builder.context.GetClassTy(wrapperClassDef, ArrayList<Type>())
        wrapperClassDef.SetType(classType)
        wrapperClassDef.SetSuperClassTy(superClassType)
        SetAutoEnvImplDefAttr(wrapperClassDef)
        AddClassToPackage(wrapperClassDef)
        return wrapperClassDef
    }

    private func CreateMemberVarInAutoEnvWrapper(autoEnvWrapperDef: ClassDef): Unit {
        let memberVarBaseType = autoEnvWrapperDef.GetSuperClassTy().getOrThrow().GetSuperClassTy(builder: builder).
            getOrThrow()
        let memberVarType = builder.context.GetRefTy(memberVarBaseType)
        let memberVar = MemberVarInfo("v", memberVarType, isStatic: false, isReadOnly: false,
            rawMangledName: "v")
        memberVar.attributeInfo.Enable(Attribute.PUBLIC)
        autoEnvWrapperDef.AddInstanceVar(memberVar)
    }

    private func CreateGenericMethodInAutoEnvWrapper(autoEnvWrapperDef: ClassDef): Function {
        let memberVars = autoEnvWrapperDef.GetDirectInstanceVars()
        CJC_ASSERT(memberVars.size == 1)
        let memberVarType = (memberVars[0].ty.StripAllRefs() as ClassType).getOrThrow()
        let (paramTypes, retType) = CreateFuncTypeWithBoxType(autoEnvWrapperDef, memberVarType.GetGenericArgs(),
            HashMap<String, Type>())
        paramTypes.add(builder.context.GetRefTy(RequireClassType(autoEnvWrapperDef)), at: 0)
        let funcType = builder.context.GetFuncTy(paramTypes, retType)
        let funcMangledName = GenerateWrapperClassGenericOverrideFuncMangleName(autoEnvWrapperDef)
        let fn = CreateCCFunction(funcType, funcMangledName, GENERIC_VIRTUAL_FUNC)
        autoEnvWrapperDef.AddMethod(fn)
        SetMemberMethodAttr(fn, false)

        let blockGroup = builder.CreateBlockGroup(fn)
        fn.InitBody(blockGroup)
        let entry = builder.CreateBlock(blockGroup)
        blockGroup.SetEntryBlock(entry)
        for (paramTy in paramTypes) {
            builder.CreateParameter(paramTy, INVALID_LOCATION, fn)
        }

        let retVal = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(retType), retType, entry))
        fn.SetReturnValue(retVal)

        let instCustomType = memberVarType
        let (methodName, originalFuncType) = GetFuncTypeFromAutoEnvBaseDef(instCustomType.GetClassDef())
        let funcParams = fn.GetParams()
        let invokeArgs = ArrayList<Value>()
        var idx: Int64 = 1
        while (idx < funcParams.size) {
            invokeArgs.add(funcParams[idx])
            idx++
        }

        let memberVarRefType = builder.context.GetRefTy(memberVarType)
        let memberVarRefRefType = builder.context.GetRefTy(memberVarRefType)
        let path = ArrayList<UInt64>()
        path.add(0u64)
        let memberVarRefRef = RequireResult(builder.CreateGetElementRef(memberVarRefRefType, funcParams[0], path, entry))
        let memberVarRef = RequireResult(builder.CreateLoad(memberVarRefType, memberVarRefRef, entry))
        let invokeInfo = InvokeCallContext(memberVarRef,
            FuncCallContext(args: invokeArgs, thisType: Some(instCustomType)),
            FuncSigInfo(originalFuncType, funcName: methodName))
        let invoke = builder.CreateInvoke(retType, invokeInfo, entry)
        invoke.SetVirtualMethodOffset(0u64)
        builder.CreateStore(RequireResult(invoke), retVal, entry)
        builder.CreateExit(None, entry)
        return fn
    }

    private func CreateInstMethodInAutoEnvWrapper(autoEnvWrapperDef: ClassDef, genericFunc: Function): Unit {
        let superDef = autoEnvWrapperDef.GetSuperClassDef().getOrThrow()
        CJC_ASSERT(superDef.GetType().getOrThrow().IsAutoEnvInstBase())
        let methods = superDef.GetMethods()
        CJC_ASSERT(methods.size == 1)
        let parentFuncType = methods[0].GetFuncType().getOrThrow()
        let paramTypes = parentFuncType.GetParamTypes()
        CJC_ASSERT(!paramTypes.isEmpty())
        paramTypes[0] = builder.context.GetRefTy(RequireClassType(autoEnvWrapperDef))
        let retType = parentFuncType.GetReturnType()
        let funcType = builder.context.GetFuncTy(paramTypes, retType)
        let funcMangledName = GenerateWrapperClassInstOverrideFuncMangleName(autoEnvWrapperDef)
        let fn = CreateCCFunction(funcType, funcMangledName, INST_VIRTUAL_FUNC)
        autoEnvWrapperDef.AddMethod(fn)
        SetMemberMethodAttr(fn, false)

        let blockGroup = builder.CreateBlockGroup(fn)
        fn.InitBody(blockGroup)
        let entry = builder.CreateBlock(blockGroup)
        blockGroup.SetEntryBlock(entry)
        for (paramTy in paramTypes) {
            builder.CreateParameter(paramTy, INVALID_LOCATION, fn)
        }

        let retVal = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(retType), retType, entry))
        fn.SetReturnValue(retVal)
        let applyArgs = ArrayList<Value>()
        for (param in fn.GetParams()) {
            applyArgs.add(param)
        }
        let apply = builder.CreateApply(retType, genericFunc, FuncCallContext(args: applyArgs,
            thisType: Some(RequireClassType(autoEnvWrapperDef))), entry)
        builder.CreateStore(RequireResult(apply), retVal, entry)
        builder.CreateExit(None, entry)
        CastApplyArgAndRetIfNeed(apply)
    }

    private func GetOrCreateAutoEnvWrapper(instAutoEnvBaseType: ClassType): ClassDef {
        let instAutoEnvBaseDef = instAutoEnvBaseType.GetClassDef()
        let wrapperName = GenerateWrapperClassMangleName(instAutoEnvBaseDef)
        if (let Some(found) <- instAutoEnvWrapperDefs.get(wrapperName)) {
            return found
        }
        let wrapperClassDef = CreateAutoEnvWrapper(wrapperName, instAutoEnvBaseType)
        CreateMemberVarInAutoEnvWrapper(wrapperClassDef)
        let genericFunc = CreateGenericMethodInAutoEnvWrapper(wrapperClassDef)
        CreateInstMethodInAutoEnvWrapper(wrapperClassDef, genericFunc)
        instAutoEnvWrapperDefs[wrapperName] = wrapperClassDef
        return wrapperClassDef
    }

    private func CastApplyArgAndRetIfNeed(e: Apply): Unit {
        let maybeCalleeType = e.GetCallee().GetType().getOrThrow() as FuncType
        if (maybeCalleeType.isNone()) {
            return
        }
        let calleeType = maybeCalleeType.getOrThrow()
        if (!calleeType.IsCJFunc()) {
            return
        }
        let index = OperandNeedTypeCast(e.GetArgs(), calleeType.GetParamTypes(), 1)
        if (!index.isEmpty()) {
            AddTypeCastForOperand(e, index)
        }
        let declaredRetType = calleeType.GetReturnType().StripAllRefs()
        let applyRetType = e.GetResult().getOrThrow().GetType().getOrThrow().StripAllRefs()
        if (!declaredRetType.IsAutoEnvInstBase() && applyRetType.IsAutoEnvInstBase()) {
            WrapApplyRetVal(e)
        }
    }

    private func WrapApplyRetVal(apply: Apply): Unit {
        let applyRetVal = apply.GetResult().getOrThrow()
        let applyRetType = applyRetVal.GetType().getOrThrow()
        let applyRetTypeNoRef = (applyRetType.StripAllRefs() as ClassType).getOrThrow()
        let autoEnvWrapperDef = GetOrCreateAutoEnvWrapper(applyRetTypeNoRef)
        let newApplyRetType = builder.context.GetRefTy(autoEnvWrapperDef.GetSuperClassDef().getOrThrow().
            GetSuperClassTy().getOrThrow())
        applyRetVal.SetType(newApplyRetType)
        let parentBlock = apply.GetParentBlock().getOrThrow()
        let autoEnvWrapperType = RequireClassType(autoEnvWrapperDef)
        let allocate = builder.CreateAllocate(builder.context.GetRefTy(autoEnvWrapperType), autoEnvWrapperType,
            parentBlock)
        allocate.MoveAfter(apply)
        let path = ArrayList<UInt64>()
        path.add(0u64)
        let storeMemberVar = builder.CreateStoreElementRef(applyRetVal, RequireResult(allocate), path, parentBlock)
        storeMemberVar.MoveAfter(allocate)
        let typecast = builder.CreateTypeCast(applyRetType, RequireResult(allocate), parentBlock)
        typecast.MoveAfter(storeMemberVar)
        let skip = ArrayList<Expression>()
        skip.add(storeMemberVar)
        ReplaceOperandWithAutoEnvWrapperClass(applyRetVal, RequireResult(typecast), skip)
    }

    private func CastApplyWithExceptionArgAndRetIfNeed(e: ApplyWithException): Unit {
        let maybeCalleeType = e.GetCallee().GetType().getOrThrow() as FuncType
        if (maybeCalleeType.isNone()) {
            return
        }
        let calleeType = maybeCalleeType.getOrThrow()
        if (!calleeType.IsCJFunc()) {
            return
        }
        let index = OperandNeedTypeCast(e.GetArgs(), calleeType.GetParamTypes(), 1)
        if (!index.isEmpty()) {
            AddTypeCastForOperand(e, index)
        }
        let declaredRetType = calleeType.GetReturnType().StripAllRefs()
        let applyRetType = e.GetResult().getOrThrow().GetType().getOrThrow().StripAllRefs()
        if (!declaredRetType.IsAutoEnvInstBase() && applyRetType.IsAutoEnvInstBase()) {
            WrapApplyWithExceptionRetVal(e)
        }
    }

    private func WrapApplyWithExceptionRetVal(apply: ApplyWithException): Unit {
        let applyRetVal = apply.GetResult().getOrThrow()
        let applyRetType = applyRetVal.GetType().getOrThrow()
        let applyRetTypeNoRef = (applyRetType.StripAllRefs() as ClassType).getOrThrow()
        let autoEnvWrapperDef = GetOrCreateAutoEnvWrapper(applyRetTypeNoRef)
        let newApplyRetType = builder.context.GetRefTy(autoEnvWrapperDef.GetSuperClassDef().getOrThrow().
            GetSuperClassTy().getOrThrow())
        applyRetVal.SetType(newApplyRetType)
        let autoEnvWrapperType = RequireClassType(autoEnvWrapperDef)
        let autoEnvWrapperRefType = builder.context.GetRefTy(autoEnvWrapperType)
        for (user in applyRetVal.GetUsers()) {
            if (user.GetExprKind() == ExprKind.INSTANCEOF) {
                continue
            }
            let userParentBlock = user.GetParentBlock().getOrThrow()
            let allocate = builder.CreateAllocate(autoEnvWrapperRefType, autoEnvWrapperType, userParentBlock)
            allocate.MoveBefore(user)
            let path = ArrayList<UInt64>()
            path.add(0u64)
            let storeMemberVar = builder.CreateStoreElementRef(applyRetVal, RequireResult(allocate), path,
                userParentBlock)
            storeMemberVar.MoveAfter(allocate)
            let typecast = builder.CreateTypeCast(applyRetType, RequireResult(allocate), userParentBlock)
            typecast.MoveAfter(storeMemberVar)
            user.ReplaceOperand(applyRetVal, RequireResult(typecast))
        }
    }

    private func CastInvokeRetIfNeed(e: DynamicDispatch): Unit {
        let declaredRetType = e.GetMethodType().GetReturnType().StripAllRefs()
        let invokeRetType = e.GetResult().getOrThrow().GetType().getOrThrow().StripAllRefs()
        if (!declaredRetType.IsAutoEnvInstBase() && invokeRetType.IsAutoEnvInstBase()) {
            WrapInvokeRetVal(e)
        }
    }

    private func WrapInvokeRetVal(e: DynamicDispatch): Unit {
        let invokeRetVal = e.GetResult().getOrThrow()
        let invokeRetType = invokeRetVal.GetType().getOrThrow()
        let invokeRetTypeNoRef = (invokeRetType.StripAllRefs() as ClassType).getOrThrow()
        let autoEnvWrapperDef = GetOrCreateAutoEnvWrapper(invokeRetTypeNoRef)
        let newInvokeRetType = builder.context.GetRefTy(autoEnvWrapperDef.GetSuperClassDef().getOrThrow().
            GetSuperClassTy().getOrThrow())
        invokeRetVal.SetType(newInvokeRetType)
        let parentBlock = e.GetParentBlock().getOrThrow()
        let autoEnvWrapperType = RequireClassType(autoEnvWrapperDef)
        let allocate = builder.CreateAllocate(builder.context.GetRefTy(autoEnvWrapperType), autoEnvWrapperType,
            parentBlock)
        allocate.MoveAfter(e)
        let path = ArrayList<UInt64>()
        path.add(0u64)
        let storeMemberVar = builder.CreateStoreElementRef(invokeRetVal, RequireResult(allocate), path, parentBlock)
        storeMemberVar.MoveAfter(allocate)
        let typecast = builder.CreateTypeCast(invokeRetType, RequireResult(allocate), parentBlock)
        typecast.MoveAfter(storeMemberVar)
        let skip = ArrayList<Expression>()
        skip.add(storeMemberVar)
        ReplaceOperandWithAutoEnvWrapperClass(invokeRetVal, RequireResult(typecast), skip)
    }

    private func CastInvokeWithExceptionRetIfNeed(e: DynamicDispatchWithException): Unit {
        let declaredRetType = e.GetMethodType().GetReturnType().StripAllRefs()
        let invokeRetType = e.GetResult().getOrThrow().GetType().getOrThrow().StripAllRefs()
        if (!declaredRetType.IsAutoEnvInstBase() && invokeRetType.IsAutoEnvInstBase()) {
            WrapInvokeWithExceptionRetVal(e)
        }
    }

    private func WrapInvokeWithExceptionRetVal(e: DynamicDispatchWithException): Unit {
        let invokeRetVal = e.GetResult().getOrThrow()
        let invokeRetType = invokeRetVal.GetType().getOrThrow()
        let invokeRetTypeNoRef = (invokeRetType.StripAllRefs() as ClassType).getOrThrow()
        let autoEnvWrapperDef = GetOrCreateAutoEnvWrapper(invokeRetTypeNoRef)
        let newInvokeRetType = builder.context.GetRefTy(autoEnvWrapperDef.GetSuperClassDef().getOrThrow().
            GetSuperClassTy().getOrThrow())
        invokeRetVal.SetType(newInvokeRetType)
        let autoEnvWrapperType = RequireClassType(autoEnvWrapperDef)
        let autoEnvWrapperRefType = builder.context.GetRefTy(autoEnvWrapperType)
        for (user in invokeRetVal.GetUsers()) {
            if (user.GetExprKind() == ExprKind.INSTANCEOF) {
                continue
            }
            let userParentBlock = user.GetParentBlock().getOrThrow()
            let allocate = builder.CreateAllocate(autoEnvWrapperRefType, autoEnvWrapperType, userParentBlock)
            allocate.MoveBefore(user)
            let path = ArrayList<UInt64>()
            path.add(0u64)
            let storeMemberVar = builder.CreateStoreElementRef(invokeRetVal, RequireResult(allocate), path,
                userParentBlock)
            storeMemberVar.MoveAfter(allocate)
            let typecast = builder.CreateTypeCast(invokeRetType, RequireResult(allocate), userParentBlock)
            typecast.MoveAfter(storeMemberVar)
            user.ReplaceOperand(invokeRetVal, RequireResult(typecast))
        }
    }

    private func CastGetElementRefRetIfNeed(e: GetElementRef): Unit {
        let getEleRefRetType = e.GetResult().getOrThrow().GetType().getOrThrow().StripAllRefs()
        if (!getEleRefRetType.IsAutoEnvInstBase()) {
            return
        }
        var locationType = e.GetLocation().GetType().getOrThrow()
        for (idx in e.GetPath()) {
            locationType = GetFieldOfType(locationType, idx, builder).getOrThrow()
        }
        if (!locationType.StripAllRefs().IsAutoEnvInstBase()) {
            WrapGetElementRefRetVal(e)
        }
    }

    private func WrapGetElementRefRetVal(getEleRef: GetElementRef): Unit {
        let getEleRefRetVal = getEleRef.GetResult().getOrThrow()
        let getEleRefRetType = getEleRefRetVal.GetType().getOrThrow()
        CJC_ASSERT(getEleRefRetType.IsReferenceTypeWithRefDims(2))
        let getEleRefRetTypeNoRef = (getEleRefRetType.StripAllRefs() as ClassType).getOrThrow()
        let autoEnvWrapperDef = GetOrCreateAutoEnvWrapper(getEleRefRetTypeNoRef)
        let newGetEleRefRetType = builder.context.GetRefTy(builder.context.GetRefTy(
            autoEnvWrapperDef.GetSuperClassDef().getOrThrow().GetSuperClassTy().getOrThrow()))
        getEleRefRetVal.SetType(newGetEleRefRetType)
        let parentBlock = getEleRef.GetParentBlock().getOrThrow()
        let autoEnvWrapperType = RequireClassType(autoEnvWrapperDef)
        let allocate1 = builder.CreateAllocate(builder.context.GetRefTy(autoEnvWrapperType), autoEnvWrapperType,
            parentBlock)
        allocate1.MoveAfter(getEleRef)
        let loadRetType = (newGetEleRefRetType as RefType).getOrThrow().GetBaseType()
        let load = builder.CreateLoad(loadRetType, getEleRefRetVal, parentBlock)
        load.MoveAfter(allocate1)
        let path = ArrayList<UInt64>()
        path.add(0u64)
        let storeMemberVar = builder.CreateStoreElementRef(RequireResult(load), RequireResult(allocate1), path,
            parentBlock)
        storeMemberVar.MoveAfter(load)
        let expectedType = (getEleRefRetType as RefType).getOrThrow().GetBaseType()
        let typecast = builder.CreateTypeCast(expectedType, RequireResult(allocate1), parentBlock)
        typecast.MoveAfter(storeMemberVar)
        let typecastRetType = RequireResult(typecast).GetType().getOrThrow()
        let allocate2 = builder.CreateAllocate(builder.context.GetRefTy(typecastRetType), typecastRetType,
            parentBlock)
        allocate2.MoveAfter(typecast)
        let store = builder.CreateStore(RequireResult(typecast), RequireResult(allocate2), parentBlock)
        store.MoveAfter(allocate2)
        let skip = ArrayList<Expression>()
        skip.add(load)
        ReplaceOperandWithAutoEnvWrapperClass(getEleRefRetVal, RequireResult(allocate2), skip)
    }

    private func WrapFieldRetVal(field: Field): Unit {
        let fieldRetVal = field.GetResult().getOrThrow()
        let fieldRetType = fieldRetVal.GetType().getOrThrow()
        CJC_ASSERT(fieldRetType.IsReferenceTypeWithRefDims(1))
        let fieldRetTypeNoRef = (fieldRetType.StripAllRefs() as ClassType).getOrThrow()
        let autoEnvWrapperDef = GetOrCreateAutoEnvWrapper(fieldRetTypeNoRef)
        let newFieldRetType = builder.context.GetRefTy(autoEnvWrapperDef.GetSuperClassDef().getOrThrow().
            GetSuperClassTy().getOrThrow())
        fieldRetVal.SetType(newFieldRetType)
        let parentBlock = field.GetParentBlock().getOrThrow()
        let autoEnvWrapperType = RequireClassType(autoEnvWrapperDef)
        let allocate = builder.CreateAllocate(builder.context.GetRefTy(autoEnvWrapperType), autoEnvWrapperType,
            parentBlock)
        allocate.MoveAfter(field)
        let path = ArrayList<UInt64>()
        path.add(0u64)
        let storeMemberVar = builder.CreateStoreElementRef(fieldRetVal, RequireResult(allocate), path, parentBlock)
        storeMemberVar.MoveAfter(allocate)
        let typecast = builder.CreateTypeCast(fieldRetType, RequireResult(allocate), parentBlock)
        typecast.MoveAfter(storeMemberVar)
        let skip = ArrayList<Expression>()
        skip.add(storeMemberVar)
        ReplaceOperandWithAutoEnvWrapperClass(fieldRetVal, RequireResult(typecast), skip)
    }

    private func CastRawArrayInitByValueArgIfNeed(e: RawArrayInitByValue): Unit {
        let rawArrayType = (e.GetRawArray().GetType().getOrThrow().StripAllRefs() as RawArrayType).getOrThrow()
        let expectedType = ArrayList<Type>()
        expectedType.add(rawArrayType.GetElementType())
        let initValue = ArrayList<Value>()
        initValue.add(e.GetInitValue())
        let index = OperandNeedTypeCast(initValue, expectedType, 2)
        if (!index.isEmpty()) {
            AddTypeCastForOperand(e, index)
        }
    }

    private func CastTypeCastArgIfNeed(e: TypeCast): Unit {
        let srcType = e.GetSourceTy().getOrThrow().StripAllRefs()
        let targetType = e.GetTargetTy().getOrThrow().StripAllRefs()
        if (IsAutoEnvGenericType(srcType) && targetType.IsAutoEnvInstBase()) {
            WrapTypeCastSrcVal(e)
        }
    }

    private func WrapTypeCastSrcVal(typecast: TypeCast): Unit {
        let targetTypeNoRef = (typecast.GetTargetTy().getOrThrow().StripAllRefs() as ClassType).getOrThrow()
        let autoEnvWrapperDef = GetOrCreateAutoEnvWrapper(targetTypeNoRef)
        let parentBlock = typecast.GetParentBlock().getOrThrow()
        let autoEnvWrapperType = RequireClassType(autoEnvWrapperDef)
        let allocate = builder.CreateAllocate(builder.context.GetRefTy(autoEnvWrapperType), autoEnvWrapperType,
            parentBlock)
        allocate.MoveBefore(typecast)
        let srcVal = typecast.GetSourceValue()
        let path = ArrayList<UInt64>()
        path.add(0u64)
        let storeMemberVar = builder.CreateStoreElementRef(srcVal, RequireResult(allocate), path, parentBlock)
        storeMemberVar.MoveAfter(allocate)
        typecast.ReplaceOperand(srcVal, RequireResult(allocate))
    }

    private func CastSpawnArgIfNeed(e: Spawn): Unit {
        if (!e.IsExecuteClosure()) {
            return
        }
        let funcType = e.GetExecuteClosure().getOrThrow().GetFuncType().getOrThrow()
        let index = OperandNeedTypeCast(e.GetOperands(), funcType.GetParamTypes(), 0)
        if (!index.isEmpty()) {
            AddTypeCastForOperand(e, index)
        }
    }

    private func ModifyTypeMismatchInExpr(): Unit {
        for (fn in CurrentPackage().GetGlobalFuncsWithBody()) {
            if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            if (let Some(body) <- fn.GetBody()) {
                ModifyTypeMismatchInBlockGroup(body)
            }
        }
    }

    private func ModifyTypeMismatchInBlockGroup(group: BlockGroup): Unit {
        for (block in group.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (let Some(apply) <- (expr as Apply)) {
                    CastApplyArgAndRetIfNeed(apply)
                } else if (let Some(applyWithException) <- (expr as ApplyWithException)) {
                    CastApplyWithExceptionArgAndRetIfNeed(applyWithException)
                } else if (let Some(invoke) <- (expr as Invoke)) {
                    CastInvokeRetIfNeed(invoke)
                } else if (let Some(invokeWithException) <- (expr as InvokeWithException)) {
                    CastInvokeWithExceptionRetIfNeed(invokeWithException)
                } else {
                    let enumRes = EnumConstructorNeedTypeCast(expr)
                    if (enumRes[0]) {
                        AddTypeCastForOperand(expr, enumRes[1])
                    } else {
                        let tupleRes = TupleNeedTypeCast(expr)
                        if (tupleRes[0]) {
                            AddTypeCastForOperand(expr, tupleRes[1])
                        } else if (let Some(getElementRef) <- (expr as GetElementRef)) {
                            CastGetElementRefRetIfNeed(getElementRef)
                        } else if (let Some(field) <- (expr as Field)) {
                            if (FieldRetValNeedWrapper(field)) {
                                WrapFieldRetVal(field)
                            }
                        } else if (let Some(rawArrayInitByValue) <- (expr as RawArrayInitByValue)) {
                            CastRawArrayInitByValueArgIfNeed(rawArrayInitByValue)
                        } else if (let Some(typecast) <- (expr as TypeCast)) {
                            CastTypeCastArgIfNeed(typecast)
                        } else if (let Some(spawnExpr) <- (expr as Spawn)) {
                            CastSpawnArgIfNeed(spawnExpr)
                        }
                    }
                }
                for (subGroup in expr.GetBlockGroups()) {
                    ModifyTypeMismatchInBlockGroup(subGroup)
                }
            }
        }
    }

    private func ModifyTypeMismatchInFunc(fn: Function, paramIndex: Int64): Unit {
        let param = fn.GetParam(paramIndex)
        let paramType = param.GetType().getOrThrow().StripAllRefs()
        let autoEnvWrapperDef = GetOrCreateAutoEnvWrapper((paramType as ClassType).getOrThrow())
        let parentBlock = fn.GetBody().getOrThrow().GetEntryBlock().getOrThrow()
        let autoEnvWrapperType = RequireClassType(autoEnvWrapperDef)
        let allocate = builder.CreateAllocate(builder.context.GetRefTy(autoEnvWrapperType), autoEnvWrapperType,
            parentBlock)
        parentBlock.InsertExprIntoHead(allocate)
        let path = ArrayList<UInt64>()
        path.add(0u64)
        let storeMemberVar = builder.CreateStoreElementRef(param, RequireResult(allocate), path, parentBlock)
        storeMemberVar.MoveAfter(allocate)
        let typecast = builder.CreateTypeCast(param.GetType().getOrThrow(), RequireResult(allocate), parentBlock)
        typecast.MoveAfter(storeMemberVar)
        let skip = ArrayList<Expression>()
        skip.add(storeMemberVar)
        ReplaceOperandWithAutoEnvWrapperClass(param, RequireResult(typecast), skip)
    }

    private func ModifyTypeMismatchInVTable(): Unit {
        for (fn in CurrentPackage().GetGlobalFuncsWithBody()) {
            if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            let rawFuncType = fn.GetOverrideSrcFuncType() ?? continue
            let rawParamTypes = rawFuncType.GetParamTypes()
            let paramTypes = fn.GetFuncType().getOrThrow().GetParamTypes()
            CJC_ASSERT(rawParamTypes.size == paramTypes.size)
            var idx: Int64 = 0
            while (idx < rawParamTypes.size) {
                if (rawParamTypes[idx].StripAllRefs().IsAutoEnvGenericBase() &&
                    paramTypes[idx].StripAllRefs().IsAutoEnvInstBase()) {
                    ModifyTypeMismatchInFunc(fn, idx)
                }
                idx++
            }
        }
    }

    private func CreateGenericTypeParamsForAutoEnvImplDef(value: Value): ArrayList<GenericType> {
        let result = GetVisiableGenericTypes(value)
        if (NeedAddThisType(value)) {
            result.add(builder.context.GetGenericTy("This", GENERIC_THIS_SRC_NAME), at: 0)
        }
        return result
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
        return fn
    }

    private func SetLiftedLambdaAttr(fn: Function, lambda: Lambda): Unit {
        fn.EnableAttr(Attribute.COMPILER_ADD)
        fn.EnableAttr(Attribute.NO_REFLECT_INFO)
        fn.EnableAttr(Attribute.INTERNAL)
        fn.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        fn.SetFuncKind(FuncKind.LAMBDA)
        if (!lambda.GetGenericTypeParams().isEmpty()) {
            fn.EnableAttr(Attribute.GENERIC)
        }
        if (lambda.IsCompileTimeValue()) {
            fn.EnableAttr(Attribute.CONST)
        }
        if (let Some(body) <- lambda.GetBody()) {
            if (body.TestAttr(Attribute.NO_INLINE)) {
                fn.EnableAttr(Attribute.NO_INLINE)
            }
        }
    }

    private func SetMemberMethodAttr(fn: Function, isConst: Bool): Unit {
        fn.EnableAttr(Attribute.COMPILER_ADD)
        fn.EnableAttr(Attribute.NO_REFLECT_INFO)
        fn.EnableAttr(Attribute.INTERNAL)
        fn.EnableAttr(Attribute.PUBLIC)
        fn.EnableAttr(Attribute.NO_DEBUG_INFO)
        fn.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        if (isConst) {
            fn.EnableAttr(Attribute.CONST)
        }
    }

    private func SetObjectSuperClass(classDef: ClassDef): Unit {
        if (let Some(objectTy) <- builder.context.GetObjectTy()) {
            classDef.SetSuperClassTy(objectTy)
        }
    }

    private func MarkAutoEnvClass(classDef: ClassDef): Unit {
        // ClosureConversion.cpp:113 SetAutoEnvImplDefAttr: def.Set<IsAutoEnvClass>(true).
        classDef.Set<IsAutoEnvClass, Bool>(true)
    }

    private func SetAutoEnvImplDefAttr(classDef: ClassDef): Unit {
        classDef.EnableAttr(Attribute.COMPILER_ADD)
        classDef.EnableAttr(Attribute.NO_REFLECT_INFO)
        MarkAutoEnvClass(classDef)
        classDef.SetLinkTypeInfo(BasicLinkage.INTERNAL)
    }

    private func SetAutoEnvBaseDefAttr(classDef: ClassDef): Unit {
        SetAutoEnvImplDefAttr(classDef)
        classDef.EnableAttr(Attribute.ABSTRACT)
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

    private func FindMethodBySrcName(def: ClassDef, name: String): Option<Function> {
        for (method in def.GetMethods()) {
            if (method.GetSrcCodeIdentifier() == name || method.GetIdentifierWithoutPrefix() == name) {
                return Some(method)
            }
        }
        return None
    }

    private func IsInstAutoEnvBaseDef(def: ClassDef): Bool {
        // Type.cpp:80 IsAutoEnvInstBase = IsAutoEnvBase && argTys.empty().
        return def.GetType().getOrThrow().IsAutoEnvInstBase()
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

    private func ContainsFunction(functions: ArrayList<Function>, target: Function): Bool {
        for (fn in functions) {
            if (fn.nodeId == target.nodeId) {
                return true
            }
        }
        return false
    }

    private func AddFunctionNoDup(functions: ArrayList<Function>, target: Function): Unit {
        if (!ContainsFunction(functions, target)) {
            functions.add(target)
        }
    }

    private func ContainsClassDef(classes: ArrayList<ClassDef>, target: ClassDef): Bool {
        for (classDef in classes) {
            if (classDef.nodeId == target.nodeId) {
                return true
            }
        }
        return false
    }

    private func AddClassNoDup(classes: ArrayList<ClassDef>, target: ClassDef): Unit {
        if (!ContainsClassDef(classes, target)) {
            classes.add(target)
        }
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
