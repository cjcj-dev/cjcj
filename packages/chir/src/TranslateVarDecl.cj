package cangjie_compiler::chir

import std.collection.*

extend AST2CHIRDeclTranslator {
    public func LowerGlobalVar(defaultPackage: String, spec: AST2CHIRGlobalSpec): GlobalVar {
        if (let Some(existing) <- globals.get(spec.name)) {
            return existing
        }
        let storageTy = if (spec.useRefStorage) { builder.context.GetRefTy(spec.ty) } else { spec.ty }
        let packageName = ResolvePackageName(defaultPackage, "")
        let globalVar = builder.CreateGlobalVar(storageTy, spec.name, srcCodeIdentifier: spec.srcCodeIdentifier,
            rawMangledName: spec.rawMangledName, packageName: packageName)
        ApplyAttributes(globalVar, spec.attributes)
        RegisterGlobal(globalVar)
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
        let packageName = ResolvePackageName(defaultPackage, "")
        let initFn = builder.CreateFunction(initFnTy, initIdentifier, srcCodeIdentifier: initSrcCodeIdentifier,
            rawMangledName: initRawMangledName, packageName: packageName)
        initFn.SetFuncKind(FuncKind.GLOBALVAR_INIT)
        let body = builder.CreateBlockGroup(initFn.GetIdentifier() + ".body")
        initFn.InitBody(body)
        let entry = builder.CreateBlock("entry", body)
        let constant = builder.CreateConstant(spec.ty, literal, entry)
        if (let Some(result) <- constant.GetResult()) {
            globalVar.SetInitializerValue(result)
        }
        builder.CreateExit(None, entry)
        RegisterFunction(initFn)
        if (let Some(pkg) <- currentPackage) {
            AddFunctionToPackage(pkg, initFn)
        }
    }
}
