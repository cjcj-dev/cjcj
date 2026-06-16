package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    public func LowerEnumDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        if (let Some(enumDef) <- (def as EnumDef)) {
            for (ctorSpec in spec.enumCtors) {
                enumDef.AddCtor(EnumCtorInfo(ctorSpec.name, ctorSpec.payloadTypes))
            }
        }
        LowerMemberVarsAndMethods(spec, def)
    }
}
