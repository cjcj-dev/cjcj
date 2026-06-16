package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    public func LowerStructDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        LowerMemberVarsAndMethods(spec, def)
    }
}
