package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    public func LowerInterfaceDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        def.EnableAttr(Attribute.ABSTRACT)
        LowerClassLikeDecl(spec, def)
    }
}
