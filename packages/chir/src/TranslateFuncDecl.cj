package cangjie_compiler::chir

import std.collection.*

extend AST2CHIRDeclTranslator {
    public func LowerFunction(defaultPackage: String, spec: AST2CHIRFunctionSpec): Function {
        if (let Some(existing) <- TryGetFunctionSpec(defaultPackage, spec)) {
            ApplyAttributes(existing, spec.attributes)
            ApplyFunctionSemanticAttributes(existing, spec)
            ApplyFunctionSourceInfo(existing, spec)
            AttachFunctionToOwner(existing, spec)
            // The function may have been pre-declared (shell only) so that call sites in other
            // function bodies could resolve it regardless of lowering order. If so, emit its body now.
            if (existing.GetBody().isNone() && ShouldEmitBody(spec)) {
                EmitFunctionBody(existing, spec)
            }
            LowerDefaultParamFunctions(defaultPackage, existing, spec)
            LowerGenericInstantiationFunctions(defaultPackage, existing, spec)
            return existing
        }
        let fn = DeclareFunctionShell(defaultPackage, spec)
        if (ShouldEmitBody(spec)) {
            EmitFunctionBody(fn, spec)
        }
        LowerDefaultParamFunctions(defaultPackage, fn, spec)
        LowerGenericInstantiationFunctions(defaultPackage, fn, spec)
        return fn
    }

    // Pre-declare every top-level function spec (create the Function, parameters, registration, and
    // package wiring) WITHOUT emitting a body. Running this before any body is lowered lets a real
    // body resolve a callee Function by name even when the callee appears later in source / is the
    // function itself (recursion). Idempotent: an already-declared spec is skipped.
    public func PredeclareFunction(defaultPackage: String, spec: AST2CHIRFunctionSpec): Unit {
        if (TryGetFunctionSpec(defaultPackage, spec).isSome()) {
            return
        }
        DeclareFunctionShell(defaultPackage, spec)
    }

    // Create the Function shell: signature, attributes, parameters, print metadata, registration,
    // and package attachment. Does not emit a body.
    private func DeclareFunctionShell(defaultPackage: String, spec: AST2CHIRFunctionSpec): Function {
        let funcTy = BuildFunctionType(spec)
        let packageName = ResolvePackageName(defaultPackage, spec.packageName)
        let fn = builder.CreateFunction(funcTy, spec.name, srcCodeIdentifier: spec.srcCodeIdentifier,
            rawMangledName: spec.rawMangledName, packageName: packageName)
        fn.SetFuncKind(spec.funcKind)
        ApplyAttributes(fn, spec.attributes)
        ApplyFunctionSemanticAttributes(fn, spec)
        ApplyFunctionSourceInfo(fn, spec)
        CreateFunctionParameters(fn, spec)
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
        return fn
    }

    private func EmitFunctionBody(fn: Function, spec: AST2CHIRFunctionSpec): Unit {
        if (spec.hasRealBody) {
            CreateRealBody(fn, spec)
        } else if (spec.hasLiteralReturn) {
            CreateLiteralReturnBody(fn, BuildLiteralReturn(spec))
        } else {
            CreateEmptyBody(fn)
        }
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
                    // Each parameter needs a unique value identifier (codegen keys the value mapping
                    // by GetIdentifierWithoutPrefix); use a %-prefixed, per-index name and keep the
                    // source name as the srcCodeIdentifier.
                    let thisParam = builder.CreateParameter(funcTy.GetParamType(0), "%this", fn)
                    thisParam.SetSrcCodeIdentifier("this")
                }
            }
        }
        var specParamIndex: Int64 = 0
        while (specParamIndex < spec.paramTypes.size) {
            let typeIndex = if (spec.isInstanceMember) { specParamIndex + 1 } else { specParamIndex }
            let srcName = if (specParamIndex < spec.paramNames.size) {
                spec.paramNames[specParamIndex]
            } else {
                "arg${specParamIndex}"
            }
            // Distinct %-prefixed identifier so two parameters never collide in codegen's value map
            // (which is keyed by the identifier with its leading prefix char stripped).
            let paramIdentifier = "%arg${typeIndex}"
            if (let Some(funcTy) <- fn.GetFuncType()) {
                if (typeIndex < funcTy.GetNumOfParams()) {
                    let param = builder.CreateParameter(funcTy.GetParamType(typeIndex), paramIdentifier, fn)
                    param.SetSrcCodeIdentifier(srcName)
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
