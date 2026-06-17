package cangjie_compiler::chir

import std.collection.*

extend AST2CHIRDeclTranslator {
    public func LowerFunction(defaultPackage: String, spec: AST2CHIRFunctionSpec): Function {
        if (let Some(existing) <- TryGetFunctionSpec(defaultPackage, spec)) {
            ApplyAttributes(existing, spec.attributes)
            ApplyFunctionSemanticAttributes(existing, spec)
            ApplyFunctionSourceInfo(existing, spec)
            AttachFunctionToOwner(existing, spec)
            LowerDefaultParamFunctions(defaultPackage, existing, spec)
            LowerGenericInstantiationFunctions(defaultPackage, existing, spec)
            return existing
        }
        let funcTy = BuildFunctionType(spec)
        let packageName = ResolvePackageName(defaultPackage, spec.packageName)
        let fn = builder.CreateFunction(funcTy, spec.name, srcCodeIdentifier: spec.srcCodeIdentifier,
            rawMangledName: spec.rawMangledName, packageName: packageName)
        fn.SetFuncKind(spec.funcKind)
        ApplyAttributes(fn, spec.attributes)
        ApplyFunctionSemanticAttributes(fn, spec)
        ApplyFunctionSourceInfo(fn, spec)
        CreateFunctionParameters(fn, spec)
        if (ShouldEmitBody(spec)) {
            if (spec.hasRealBody) {
                CreateRealBody(fn, spec)
            } else if (spec.hasLiteralReturn) {
                CreateLiteralReturnBody(fn, BuildLiteralReturn(spec))
            } else {
                CreateEmptyBody(fn)
            }
        }
        var printIdx = 0
        for (printString in spec.printStrings) {
            fn.printStrings.add(printString)
            let newline = if (printIdx < spec.printNewlines.size) {
                spec.printNewlines[printIdx]
            } else {
                true
            }
            fn.printNewlines.add(newline)
            let isInt = if (printIdx < spec.printIsInt.size) {
                spec.printIsInt[printIdx]
            } else {
                false
            }
            fn.printIsInt.add(isInt)
            printIdx++
        }
        RegisterFunctionSpec(defaultPackage, spec, fn)
        WireGenericDecl(fn, spec)
        if (let Some(pkg) <- currentPackage) {
            AddFunctionToPackage(pkg, fn)
        }
        AttachFunctionToOwner(fn, spec)
        LowerDefaultParamFunctions(defaultPackage, fn, spec)
        LowerGenericInstantiationFunctions(defaultPackage, fn, spec)
        return fn
    }

    private func BuildLiteralReturn(spec: AST2CHIRFunctionSpec): LiteralValue {
        if (spec.literalReturnKind == AST2CHIR_LITERAL_BOOL) {
            return BoolLiteral(spec.literalReturnBoolValue)
        }
        if (spec.literalReturnKind == AST2CHIR_LITERAL_INT) {
            return IntLiteral(spec.literalReturnIntValue)
        }
        if (spec.literalReturnKind == AST2CHIR_LITERAL_FLOAT) {
            return FloatLiteral(spec.literalReturnFloatValue)
        }
        return UnitLiteral()
    }

    private func ApplyFunctionSemanticAttributes(fn: Function, spec: AST2CHIRFunctionSpec): Unit {
        if (spec.attributes.contains(Attribute.FOREIGN)) {
            fn.EnableAttr(Attribute.IMPORTED)
        }
    }

    private func ApplyFunctionSourceInfo(fn: Function, spec: AST2CHIRFunctionSpec): Unit {
        ApplyFeatures(fn, spec.features)
        if (let Some(loc) <- spec.debugLocation) {
            fn.SetDebugLocation(loc)
        }
        if (let Some(propLoc) <- spec.propertyLocation) {
            fn.SetPropLocation(propLoc)
        }
    }

    private func BuildFunctionType(spec: AST2CHIRFunctionSpec): FuncType {
        let adjustedParams = ArrayList<Type>()
        if (spec.isInstanceMember) {
            if (let Some(ownerName) <- spec.ownerTypeName) {
                if (let Some(ownerDef) <- TryGetTypeDef(ownerName)) {
                    adjustedParams.add(GetInstanceThisType(ownerDef, spec))
                }
            }
        }
        for (paramTy in spec.paramTypes) {
            adjustedParams.add(paramTy)
        }
        let adjustedReturn = if (spec.IsConstructorLike()) { builder.context.GetUnitTy() } else { spec.returnType }
        return builder.context.GetFuncTy(adjustedParams, adjustedReturn, hasVarLenParam: spec.hasVariableLenArg,
            isCFunc: spec.isCFunc || spec.hasVariableLenArg)
    }

    private func CreateFunctionParameters(fn: Function, spec: AST2CHIRFunctionSpec): Unit {
        if (spec.isInstanceMember) {
            if (let Some(funcTy) <- fn.GetFuncType()) {
                if (funcTy.GetNumOfParams() > 0) {
                    let thisParam = builder.CreateParameter(funcTy.GetParamType(0), "this", fn)
                    thisParam.SetSrcCodeIdentifier("this")
                }
            }
        }
        var specParamIndex: Int64 = 0
        while (specParamIndex < spec.paramTypes.size) {
            let typeIndex = if (spec.isInstanceMember) { specParamIndex + 1 } else { specParamIndex }
            let paramName = if (specParamIndex < spec.paramNames.size) {
                spec.paramNames[specParamIndex]
            } else {
                "%arg${specParamIndex}"
            }
            if (let Some(funcTy) <- fn.GetFuncType()) {
                if (typeIndex < funcTy.GetNumOfParams()) {
                    let param = builder.CreateParameter(funcTy.GetParamType(typeIndex), paramName, fn)
                    param.SetSrcCodeIdentifier(paramName)
                }
            }
            specParamIndex++
        }
    }

    private func WireGenericDecl(fn: Function, spec: AST2CHIRFunctionSpec): Unit {
        if (let Some(declName) <- spec.genericDeclName) {
            if (let Some(genericFn) <- TryGetFunction(declName)) {
                fn.SetGenericDecl(genericFn)
            }
        }
    }

    private func AttachFunctionToOwner(fn: Function, spec: AST2CHIRFunctionSpec): Unit {
        if (fn.GetFuncKind() == FuncKind.GLOBALVAR_INIT) {
            return
        }
        if (let Some(ownerName) <- spec.ownerTypeName) {
            if (let Some(ownerDef) <- TryGetTypeDef(ownerName)) {
                ownerDef.AddMethod(fn)
            }
        }
    }

    private func LowerDefaultParamFunctions(defaultPackage: String, host: Function, spec: AST2CHIRFunctionSpec): Unit {
        for (defaultSpec in spec.defaultParamFunctions) {
            if (let Some(ownerName) <- spec.ownerTypeName) {
                if (defaultSpec.ownerTypeName.isNone()) {
                    defaultSpec.SetOwnerType(ownerName, isInstanceMember: spec.isInstanceMember)
                }
            }
            let defaultFn = LowerFunction(defaultPackage, defaultSpec)
            defaultFn.SetParamDftValHostFunc(host)
        }
    }

    private func LowerGenericInstantiationFunctions(defaultPackage: String, host: Function,
        spec: AST2CHIRFunctionSpec): Unit {
        for (instSpec in spec.genericInstantiations) {
            if (let Some(ownerName) <- spec.ownerTypeName) {
                if (instSpec.ownerTypeName.isNone()) {
                    instSpec.SetOwnerType(ownerName, isInstanceMember: spec.isInstanceMember)
                }
            }
            if (instSpec.genericDeclName.isNone()) {
                instSpec.SetGenericDeclName(host.GetIdentifier())
            }
            LowerFunction(defaultPackage, instSpec)
        }
    }

    public func AddFunctionToPackage(pkg: Package, fn: Function): Unit {
        if (pkg.TryGetGlobalFunc(fn.GetIdentifier()).isNone()) {
            pkg.AddGlobalFunc(fn)
        }
    }
}
