package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    public func LowerExtendDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        if (let Some(extendDef) <- (def as ExtendDef)) {
            if (let Some(targetTy) <- spec.extendedType) {
                extendDef.extendedType = Some(targetTy)
                let strippedTy = targetTy.StripAllRefs()
                if (let Some(customTy) <- (strippedTy as CustomType)) {
                    customTy.GetCustomTypeDef().AddExtend(extendDef)
                } else if (let Some(builtinTy) <- (strippedTy as BuiltinType)) {
                    builtinTy.AddExtend(extendDef)
                }
            }
        }
        LowerMemberVarsAndMethods(spec, def)
        let defaultPackage = ActivePackageName(spec.packageName)
        for (interfaceName in spec.implementedInterfaces) {
            AddImplementedInterfaceByName(defaultPackage, def, interfaceName)
        }
    }
}
