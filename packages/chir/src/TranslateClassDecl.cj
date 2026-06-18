package cangjie_compiler::chir

import std.collection.*

extend AST2CHIRDeclTranslator {
    public func CreateNominalDef(defaultPackage: String, spec: AST2CHIRNominalSpec): CustomTypeDef {
        if (let Some(existing) <- TryGetNominalSpec(defaultPackage, spec)) {
            ApplyAttributes(existing, spec.attributes)
            ApplyNominalSourceInfo(existing, spec)
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
        ApplyNominalSourceInfo(def, spec)
        if (spec.kind == AST2CHIRNominalKind.INTERFACE) {
            def.EnableAttr(Attribute.ABSTRACT)
        }
        for (genericParam in spec.genericTypeParams) {
            def.AddGenericTypeParam(genericParam)
        }
        EnsureNominalType(def)
        RegisterNominalSpec(defaultPackage, spec, def)
        if (let Some(pkg) <- currentPackage) {
            AddTypeDefToPackage(pkg, spec, def)
        }
        return def
    }

    private func ApplyNominalSourceInfo(def: CustomTypeDef, spec: AST2CHIRNominalSpec): Unit {
        if (!spec.srcCodeIdentifier.isEmpty()) {
            def.SetSrcCodeIdentifier(spec.srcCodeIdentifier)
        }
        if (let Some(loc) <- spec.debugLocation) {
            def.SetDebugLocation(loc)
        }
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
            let defaultPackage = ActivePackageName(spec.packageName)
            if (ShouldSetupNominalInheritance(spec)) {
                if (let Some(superName) <- spec.superClassName) {
                    if (let Some(superDef) <- TryGetTypeDef(defaultPackage, superName)) {
                        if (let Some(superClass) <- (superDef as ClassDef)) {
                            classDef.SetSuperClassDef(superClass)
                        }
                    }
                }
                for (interfaceName in spec.implementedInterfaces) {
                    AddImplementedInterfaceByName(defaultPackage, classDef, interfaceName)
                }
            }
        }
        LowerMemberVarsAndMethods(spec, def)
    }

    private func ShouldSetupNominalInheritance(spec: AST2CHIRNominalSpec): Bool {
        if (!spec.isSpecificDecl) {
            return true
        }
        if (spec.attributes.contains(Attribute.IMPORTED)) {
            return true
        }
        return spec.attributes.contains(Attribute.GENERIC_INSTANTIATED)
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
        if (!ShouldTranslateMember(owner, varSpec.sourceFileKey)) {
            return
        }
        if (varSpec.isStatic || varSpec.attributes.contains(Attribute.STATIC)) {
            LowerStaticMemberVarSpec(owner, def, varSpec)
            return
        }
        if (ShouldAddMemberVar(def, varSpec)) {
            let memberInfo = AddOrUpdateMemberVarDecl(def, varSpec)
            if (let Some(initFunc) <- LowerMemberVarInitializer(owner, varSpec)) {
                memberInfo.initializerFunc = Some(initFunc)
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
            if (let Some(propLoc) <- propertySpec.propertyLocation) {
                if (getterSpec.propertyLocation.isNone()) {
                    getterSpec.SetPropertyLocation(propLoc)
                }
            }
            LowerMemberMethodSpec(owner, getterSpec)
        }
        for (setterSpec in propertySpec.setters) {
            if (let Some(propLoc) <- propertySpec.propertyLocation) {
                if (setterSpec.propertyLocation.isNone()) {
                    setterSpec.SetPropertyLocation(propLoc)
                }
            }
            LowerMemberMethodSpec(owner, setterSpec)
        }
    }

    public func AddMemberVarDecl(def: CustomTypeDef, spec: AST2CHIRMemberVarSpec): Unit {
        if (spec.isStatic || spec.attributes.contains(Attribute.STATIC)) {
            let fallbackOwner = AST2CHIRNominalSpec(AST2CHIRNominalKind.STRUCT, def.GetIdentifier(),
                packageName: def.GetPackageName(), srcCodeIdentifier: def.GetSrcCodeIdentifier())
            LowerStaticMemberVarSpec(fallbackOwner, def, spec)
            return
        }
        let _ = AddOrUpdateMemberVarDecl(def, spec)
    }

    private func AddOrUpdateMemberVarDecl(def: CustomTypeDef, spec: AST2CHIRMemberVarSpec): MemberVarInfo {
        let readOnly = spec.isReadOnly || spec.attributes.contains(Attribute.READONLY) ||
            spec.attributes.contains(Attribute.CONST)
        if (let Some(existing) <- FindDirectInstanceVar(def, spec)) {
            ApplyMemberVarInfo(existing, spec, readOnly)
            return existing
        }
        let memberInfo = MemberVarInfo(spec.name, spec.ty, isReadOnly: readOnly, rawMangledName: spec.rawMangledName)
        ApplyMemberVarInfo(memberInfo, spec, readOnly)
        def.AddInstanceVar(memberInfo)
        return memberInfo
    }

    private func FindDirectInstanceVar(def: CustomTypeDef, spec: AST2CHIRMemberVarSpec): Option<MemberVarInfo> {
        for (memberInfo in def.GetDirectInstanceVars()) {
            if (!spec.rawMangledName.isEmpty() && memberInfo.rawMangledName == spec.rawMangledName) {
                return memberInfo
            }
            if (memberInfo.name == spec.name) {
                return memberInfo
            }
        }
        return None
    }

    private func ApplyMemberVarInfo(memberInfo: MemberVarInfo, spec: AST2CHIRMemberVarSpec, readOnly: Bool): Unit {
        memberInfo.name = spec.name
        memberInfo.rawMangledName = spec.rawMangledName
        memberInfo.ty = spec.ty
        memberInfo.isStatic = false
        memberInfo.isReadOnly = readOnly
        memberInfo.attributeInfo.CopyFrom(BuildAttributeInfo(spec.attributes))
        if (readOnly) {
            memberInfo.attributeInfo.Enable(Attribute.READONLY)
        }
        if (let Some(loc) <- spec.debugLocation) {
            memberInfo.loc = loc
        }
    }

    private func ShouldAddMemberVar(def: CustomTypeDef, spec: AST2CHIRMemberVarSpec): Bool {
        return !spec.isSpecificDecl || def.TestAttr(Attribute.GENERIC_INSTANTIATED)
    }

    private func LowerMemberVarInitializer(owner: AST2CHIRNominalSpec,
        varSpec: AST2CHIRMemberVarSpec): Option<Function> {
        if (let Some(initSpec) <- varSpec.initializerFunc) {
            initSpec.SetOwnerType(owner.name, isInstanceMember: true)
            initSpec.AddAttribute(Attribute.MUT)
            return LowerFunction(ActivePackageName(owner.packageName), initSpec)
        }
        return None
    }

    private func LowerStaticMemberVarSpec(owner: AST2CHIRNominalSpec, def: CustomTypeDef,
        varSpec: AST2CHIRMemberVarSpec): Unit {
        let defaultPackage = ActivePackageName(owner.packageName)
        let staticVar = if (let Some(globalSpec) <- varSpec.staticGlobalSpec) {
            LowerGlobalVar(defaultPackage, globalSpec)
        } else {
            let generatedSpec = AST2CHIRGlobalSpec(varSpec.name, varSpec.ty, srcCodeIdentifier: varSpec.name,
                rawMangledName: varSpec.rawMangledName, packageName: owner.packageName)
            generatedSpec.SetUseRefStorage(true)
            for (attr in varSpec.attributes) {
                generatedSpec.AddAttribute(attr)
            }
            generatedSpec.AddAttribute(Attribute.STATIC)
            if (varSpec.isReadOnly) {
                generatedSpec.AddAttribute(Attribute.READONLY)
            }
            if (let Some(loc) <- varSpec.debugLocation) {
                generatedSpec.SetDebugLocation(loc)
            }
            LowerGlobalVar(defaultPackage, generatedSpec)
        }
        ApplyAttributes(staticVar, varSpec.attributes)
        if (let Some(loc) <- varSpec.debugLocation) {
            staticVar.SetDebugLocation(loc)
        }
        def.AddStaticMemberVar(staticVar)
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
