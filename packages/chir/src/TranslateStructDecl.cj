package cangjie_compiler::chir

extend AST2CHIRDeclTranslator {
    public func LowerStructDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        LowerMemberVarsAndMethods(spec, def)
        let defaultPackage = ActivePackageName(spec.packageName)
        for (interfaceName in spec.implementedInterfaces) {
            AddImplementedInterfaceByName(defaultPackage, def, interfaceName)
        }
    }
}
