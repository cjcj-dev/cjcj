package cangjie_compiler::chir

import std.collection.*

extend AST2CHIRDeclTranslator {
    public func CreateNominalDef(defaultPackage: String, spec: AST2CHIRNominalSpec): CustomTypeDef {
        if (let Some(existing) <- TryGetTypeDef(spec.name)) {
            return existing
        }
        let packageName = ResolvePackageName(defaultPackage, spec.packageName)
        let def = match (spec.kind) {
            case AST2CHIRNominalKind.CLASS => builder.CreateClassDef(packageName, spec.name)
            case AST2CHIRNominalKind.INTERFACE => builder.CreateClassDef(packageName, spec.name)
            case AST2CHIRNominalKind.STRUCT => builder.CreateStructDef(packageName, spec.name)
            case AST2CHIRNominalKind.ENUM => builder.CreateEnumDef(packageName, spec.name)
            case AST2CHIRNominalKind.EXTEND => builder.CreateExtendDef(packageName, spec.name)
        }
        ApplyAttributes(def, spec.attributes)
        if (spec.kind == AST2CHIRNominalKind.INTERFACE) {
            def.EnableAttr(Attribute.ABSTRACT)
        }
        for (genericParam in spec.genericTypeParams) {
            def.AddGenericTypeParam(genericParam)
        }
        RegisterTypeDef(spec.name, def)
        if (let Some(pkg) <- currentPackage) {
            AddTypeDefToPackage(pkg, spec, def)
        }
        return def
    }

    public func LowerNominalDecl(defaultPackage: String, spec: AST2CHIRNominalSpec): Unit {
        let def = CreateNominalDef(defaultPackage, spec)
        match (spec.kind) {
            case AST2CHIRNominalKind.CLASS => LowerClassDecl(spec, def)
            case AST2CHIRNominalKind.INTERFACE => LowerInterfaceDecl(spec, def)
            case AST2CHIRNominalKind.STRUCT => LowerStructDecl(spec, def)
            case AST2CHIRNominalKind.ENUM => LowerEnumDecl(spec, def)
            case AST2CHIRNominalKind.EXTEND => LowerExtendDecl(spec, def)
        }
    }

    public func LowerClassDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        LowerClassLikeDecl(spec, def)
    }

    public func LowerClassLikeDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        if (let Some(classDef) <- (def as ClassDef)) {
            if (let Some(superName) <- spec.superClassName) {
                if (let Some(superDef) <- TryGetTypeDef(superName)) {
                    if (let Some(superClass) <- (superDef as ClassDef)) {
                        classDef.SetSuperClassDef(superClass)
                    }
                }
            }
            for (interfaceName in spec.implementedInterfaces) {
                if (let Some(interfaceDef) <- TryGetTypeDef(interfaceName)) {
                    if (let Some(interfaceClass) <- (interfaceDef as ClassDef)) {
                        classDef.AddImplementedInterfaceDef(interfaceClass)
                    }
                }
            }
        }
        LowerMemberVarsAndMethods(spec, def)
    }

    public func LowerMemberVarsAndMethods(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        if (!spec.memberDecls.isEmpty()) {
            for (memberSpec in spec.memberDecls) {
                LowerNominalMember(spec, def, memberSpec)
            }
            return
        }
        LowerLegacyMemberLists(spec, def)
    }

    private func LowerLegacyMemberLists(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        for (varSpec in spec.instanceVars) {
            LowerMemberVarSpec(spec, def, varSpec)
        }
        for (methodSpec in spec.methods) {
            LowerMemberMethodSpec(spec, methodSpec)
        }
        for (propertySpec in spec.properties) {
            LowerPropertySpec(spec, propertySpec)
        }
    }

    private func LowerNominalMember(spec: AST2CHIRNominalSpec, def: CustomTypeDef,
        memberSpec: AST2CHIRNominalMemberSpec): Unit {
        match (memberSpec.kind) {
            case AST2CHIRNominalMemberKind.VAR =>
                if (let Some(varSpec) <- memberSpec.varSpec) {
                    LowerMemberVarSpec(spec, def, varSpec)
                }
            case AST2CHIRNominalMemberKind.METHOD =>
                if (let Some(methodSpec) <- memberSpec.methodSpec) {
                    LowerMemberMethodSpec(spec, methodSpec)
                }
            case AST2CHIRNominalMemberKind.PROPERTY =>
                if (let Some(propertySpec) <- memberSpec.propertySpec) {
                    LowerPropertySpec(spec, propertySpec)
                }
        }
    }

    private func LowerMemberVarSpec(owner: AST2CHIRNominalSpec, def: CustomTypeDef,
        varSpec: AST2CHIRMemberVarSpec): Unit {
        if (ShouldTranslateMember(owner, varSpec.sourceFileKey)) {
            if (ShouldAddMemberVar(def, varSpec)) {
                AddMemberVarDecl(def, varSpec)
                LowerMemberVarInitializer(owner, varSpec)
            }
        }
    }

    private func LowerMemberMethodSpec(owner: AST2CHIRNominalSpec, methodSpec: AST2CHIRFunctionSpec): Unit {
        if (ShouldTranslateFunctionMember(owner, methodSpec)) {
            methodSpec.SetOwnerType(owner.name, isInstanceMember: !methodSpec.attributes.contains(Attribute.STATIC))
            LowerFunction(ActivePackageName(owner.packageName), methodSpec)
        }
    }

    private func LowerPropertySpec(owner: AST2CHIRNominalSpec, propertySpec: AST2CHIRPropertySpec): Unit {
        if (propertySpec.isCommonMatchedWithSpecific) {
            return
        }
        if (!ShouldTranslateMember(owner, propertySpec.sourceFileKey)) {
            return
        }
        for (getterSpec in propertySpec.getters) {
            LowerMemberMethodSpec(owner, getterSpec)
        }
        for (setterSpec in propertySpec.setters) {
            LowerMemberMethodSpec(owner, setterSpec)
        }
    }

    public func AddMemberVarDecl(def: CustomTypeDef, spec: AST2CHIRMemberVarSpec): Unit {
        let readOnly = spec.isReadOnly || spec.attributes.contains(Attribute.READONLY) ||
            spec.attributes.contains(Attribute.CONST)
        let info = MemberVarInfo(spec.name, spec.ty, isStatic: spec.isStatic, isReadOnly: readOnly)
        def.AddInstanceVar(info)
    }

    private func ShouldAddMemberVar(def: CustomTypeDef, spec: AST2CHIRMemberVarSpec): Bool {
        return !spec.isSpecificDecl || def.TestAttr(Attribute.GENERIC_INSTANTIATED)
    }

    private func LowerMemberVarInitializer(owner: AST2CHIRNominalSpec, varSpec: AST2CHIRMemberVarSpec): Unit {
        if (varSpec.isStatic) {
            return
        }
        if (let Some(initSpec) <- varSpec.initializerFunc) {
            initSpec.SetOwnerType(owner.name, isInstanceMember: true)
            initSpec.AddAttribute(Attribute.MUT)
            LowerFunction(ActivePackageName(owner.packageName), initSpec)
        }
    }

    private func ShouldTranslateFunctionMember(owner: AST2CHIRNominalSpec, methodSpec: AST2CHIRFunctionSpec): Bool {
        if (methodSpec.isCommonMatchedWithSpecific) {
            return false
        }
        return ShouldTranslateMember(owner, methodSpec.sourceFileKey)
    }

    private func AddTypeDefToPackage(pkg: Package, spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        let useImportedList = spec.attributes.contains(Attribute.IMPORTED) &&
            !spec.attributes.contains(Attribute.SRC_CODE_IMPORTED)
        match (spec.kind) {
            case AST2CHIRNominalKind.CLASS =>
                if (let Some(classDef) <- (def as ClassDef)) {
                    if (useImportedList) { pkg.AddImportedClass(classDef) } else { pkg.AddClass(classDef) }
                }
            case AST2CHIRNominalKind.INTERFACE =>
                if (let Some(interfaceDef) <- (def as ClassDef)) {
                    if (useImportedList) { pkg.AddImportedClass(interfaceDef) } else { pkg.AddClass(interfaceDef) }
                }
            case AST2CHIRNominalKind.STRUCT =>
                if (let Some(structDef) <- (def as StructDef)) {
                    if (useImportedList) { pkg.AddImportedStruct(structDef) } else { pkg.AddStruct(structDef) }
                }
            case AST2CHIRNominalKind.ENUM =>
                if (let Some(enumDef) <- (def as EnumDef)) {
                    if (useImportedList) { pkg.AddImportedEnum(enumDef) } else { pkg.AddEnum(enumDef) }
                }
            case AST2CHIRNominalKind.EXTEND =>
                if (let Some(extendDef) <- (def as ExtendDef)) {
                    if (useImportedList) { pkg.AddImportedExtend(extendDef) } else { pkg.AddExtend(extendDef) }
                }
        }
    }
}
