package cangjie_compiler::chir

import std.collection.*

extend AST2CHIRDeclTranslator {
    public func LowerGlobalVar(defaultPackage: String, spec: AST2CHIRGlobalSpec): GlobalVar {
        if (let Some(existing) <- TryGetGlobalSpec(defaultPackage, spec)) {
            ApplyAttributes(existing, spec.attributes)
            ApplyGlobalSourceInfo(existing, spec)
            return existing
        }
        let storageTy = if (spec.useRefStorage) { builder.context.GetRefTy(spec.ty) } else { spec.ty }
        let packageName = ResolvePackageName(defaultPackage, spec.packageName)
        let globalVar = builder.CreateGlobalVar(storageTy, spec.name, srcCodeIdentifier: spec.srcCodeIdentifier,
            rawMangledName: spec.rawMangledName, packageName: packageName)
        ApplyAttributes(globalVar, spec.attributes)
        ApplyGlobalSourceInfo(globalVar, spec)
        RegisterGlobalSpec(defaultPackage, spec, globalVar)
        if (let Some(literal) <- spec.initialValue) {
            LowerGlobalLiteralInitializer(defaultPackage, globalVar, spec, literal)
        }
        if (let Some(pkg) <- currentPackage) {
            if (pkg.TryGetGlobalVar(globalVar.GetIdentifier()).isNone()) {
                pkg.AddGlobalVar(globalVar)
            }
        }
        return globalVar
    }

    private func ApplyGlobalSourceInfo(globalVar: GlobalVar, spec: AST2CHIRGlobalSpec): Unit {
        if (let Some(loc) <- spec.debugLocation) {
            globalVar.SetDebugLocation(loc)
        }
    }

    private func LowerGlobalLiteralInitializer(defaultPackage: String, globalVar: GlobalVar,
        spec: AST2CHIRGlobalSpec, literal: LiteralValue): Unit {
        let initFnTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetUnitTy())
        let initIdentifier = spec.name + "$init"
        let initSrcCodeIdentifier = if (spec.srcCodeIdentifier.isEmpty()) {
            initIdentifier
        } else {
            spec.srcCodeIdentifier + "$init"
        }
        let initRawMangledName = if (spec.rawMangledName.isEmpty()) {
            initIdentifier
        } else {
            spec.rawMangledName + "$init"
        }
        let packageName = ResolvePackageName(defaultPackage, spec.packageName)
        let initFn = builder.CreateFunction(initFnTy, initIdentifier, srcCodeIdentifier: initSrcCodeIdentifier,
            rawMangledName: initRawMangledName, packageName: packageName)
        initFn.SetFuncKind(FuncKind.GLOBALVAR_INIT)
        if (spec.attributes.contains(Attribute.CONST)) {
            initFn.EnableAttr(Attribute.CONST)
        }
        if (let Some(loc) <- spec.debugLocation) {
            initFn.SetDebugLocation(loc)
        }
        let body = builder.CreateBlockGroup(initFn.GetIdentifier() + ".body")
        initFn.InitBody(body)
        let entry = builder.CreateBlock("entry", body)
        EnsureReturnSlot(initFn, entry)
        let constant = builder.CreateConstant(spec.ty, literal, entry)
        if (let Some(result) <- constant.GetResult()) {
            globalVar.SetInitializerValue(result)
        }
        builder.CreateExit(None, entry)
        RegisterFunctionAlias(initFn.GetIdentifier(), initFn)
        RegisterFunctionAlias(initRawMangledName, initFn)
        RegisterFunctionAlias(ScopedDeclName(packageName, initIdentifier), initFn)
        if (let Some(pkg) <- currentPackage) {
            AddFunctionToPackage(pkg, initFn)
        }
    }
}
