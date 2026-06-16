package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    public func LowerEnumDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        if (let Some(enumDef) <- (def as EnumDef)) {
            for (ctorSpec in spec.enumCtors) {
                if (!HasEnumCtor(enumDef, ctorSpec)) {
                    enumDef.AddCtor(EnumCtorInfo(ctorSpec.name, ctorSpec.payloadTypes))
                }
            }
        }
        LowerMemberVarsAndMethods(spec, def)
    }

    private func HasEnumCtor(enumDef: EnumDef, ctorSpec: AST2CHIREnumCtorSpec): Bool {
        for (ctor in enumDef.GetCtors()) {
            if (ctor.name == ctorSpec.name && ctor.payloadTypes.size == ctorSpec.payloadTypes.size) {
                return true
            }
        }
        return false
    }
}
