package cangjie_compiler::chir

import std.collection.*

public class AST2CHIRDeclTranslator {
    public let builder: CHIRBuilder
    public var currentPackage: Option<Package> = None
    public let typeDefs: HashMap<String, CustomTypeDef> = HashMap<String, CustomTypeDef>()
    public let functions: HashMap<String, Function> = HashMap<String, Function>()
    public let globals: HashMap<String, GlobalVar> = HashMap<String, GlobalVar>()
    public var mergingSpecific: Bool = false

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RegisterFunction(fn: Function): Unit {
        functions[fn.GetIdentifier()] = fn
    }

    public func RegisterFunctionAlias(name: String, fn: Function): Unit {
        if (!name.isEmpty()) {
            functions[name] = fn
        }
    }

    public func RegisterFunctionSpec(defaultPackage: String, spec: AST2CHIRFunctionSpec, fn: Function): Unit {
        RegisterFunction(fn)
        RegisterFunctionAlias(spec.rawMangledName, fn)
        RegisterFunctionAlias(ScopedDeclName(ResolvePackageName(defaultPackage, spec.packageName), spec.name), fn)
        // Also expose the plain source identifier so the real-body call translator can resolve a
        // user-defined callee by the name written at the call site (e.g. `add`). Only register
        // top-level (non-member) functions this way to avoid colliding method names across types.
        if (spec.ownerTypeName.isNone() && !spec.srcCodeIdentifier.isEmpty()) {
            RegisterFunctionAlias(spec.srcCodeIdentifier, fn)
        }
    }

    public func RegisterGlobal(globalVar: GlobalVar): Unit {
        globals[globalVar.GetIdentifier()] = globalVar
    }

    public func RegisterGlobalAlias(name: String, globalVar: GlobalVar): Unit {
        if (!name.isEmpty()) {
            globals[name] = globalVar
        }
    }

    public func RegisterGlobalSpec(defaultPackage: String, spec: AST2CHIRGlobalSpec, globalVar: GlobalVar): Unit {
        RegisterGlobal(globalVar)
        RegisterGlobalAlias(spec.rawMangledName, globalVar)
        RegisterGlobalAlias(ScopedDeclName(ResolvePackageName(defaultPackage, spec.packageName), spec.name), globalVar)
    }

    public func RegisterTypeDef(name: String, def: CustomTypeDef): Unit {
        typeDefs[name] = def
    }

    public func RegisterTypeDefAlias(name: String, def: CustomTypeDef): Unit {
        if (!name.isEmpty()) {
            typeDefs[name] = def
        }
    }

    public func RegisterNominalSpec(defaultPackage: String, spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        RegisterTypeDef(spec.name, def)
        RegisterTypeDefAlias(spec.rawMangledName, def)
        RegisterTypeDefAlias(ScopedDeclName(ResolvePackageName(defaultPackage, spec.packageName), spec.name), def)
    }

    public func TryGetTypeDef(name: String): Option<CustomTypeDef> {
        return typeDefs.get(name)
    }

    public func TryGetFunction(name: String): Option<Function> {
        return functions.get(name)
    }

    public func TryGetNominalSpec(defaultPackage: String, spec: AST2CHIRNominalSpec): Option<CustomTypeDef> {
        if (let Some(foundByScoped) <- typeDefs.get(
            ScopedDeclName(ResolvePackageName(defaultPackage, spec.packageName), spec.name))) {
            return foundByScoped
        }
        if (!spec.rawMangledName.isEmpty()) {
            if (let Some(foundByRaw) <- typeDefs.get(spec.rawMangledName)) {
                return foundByRaw
            }
        }
        return typeDefs.get(spec.name)
    }

    public func TryGetFunctionSpec(defaultPackage: String, spec: AST2CHIRFunctionSpec): Option<Function> {
        if (let Some(foundByScoped) <- functions.get(
            ScopedDeclName(ResolvePackageName(defaultPackage, spec.packageName), spec.name))) {
            return foundByScoped
        }
        if (!spec.rawMangledName.isEmpty()) {
            if (let Some(foundByRaw) <- functions.get(spec.rawMangledName)) {
                return foundByRaw
            }
        }
        return functions.get(spec.name)
    }

    public func TryGetGlobalSpec(defaultPackage: String, spec: AST2CHIRGlobalSpec): Option<GlobalVar> {
        if (let Some(foundByScoped) <- globals.get(
            ScopedDeclName(ResolvePackageName(defaultPackage, spec.packageName), spec.name))) {
            return foundByScoped
        }
        if (!spec.rawMangledName.isEmpty()) {
            if (let Some(foundByRaw) <- globals.get(spec.rawMangledName)) {
                return foundByRaw
            }
        }
        return globals.get(spec.name)
    }

    public func ResolvePackageName(defaultPackage: String, declaredPackage: String): String {
        return if (declaredPackage.isEmpty()) { defaultPackage } else { declaredPackage }
    }

    public func ScopedDeclName(packageName: String, identifier: String): String {
        if (packageName.isEmpty()) {
            return identifier
        }
        return packageName + "." + identifier
    }

    public func ActivePackageName(fallback: String): String {
        if (!fallback.isEmpty()) {
            return fallback
        }
        if (let Some(pkg) <- currentPackage) {
            return pkg.GetName()
        }
        return fallback
    }

    public func ApplyAttributes(target: Base, attrs: ArrayList<Attribute>): Unit {
        target.AppendAttributeInfo(BuildAttributeInfo(attrs))
    }

    public func ApplyFeatures(target: GlobalValue, features: ArrayList<String>): Unit {
        for (featureName in features) {
            target.AddFeature(featureName)
        }
    }

    public func CreateEmptyBody(fn: Function): Unit {
        let body = builder.CreateBlockGroup(fn.GetIdentifier() + ".body")
        fn.InitBody(body)
        let entry = builder.CreateBlock("entry", body)
        EnsureReturnSlot(fn, entry)
        builder.CreateExit(None, entry)
    }

    public func CreateLiteralReturnBody(fn: Function, literal: LiteralValue): Unit {
        let body = builder.CreateBlockGroup(fn.GetIdentifier() + ".body")
        fn.InitBody(body)
        let entry = builder.CreateBlock("entry", body)
        EnsureReturnSlot(fn, entry)
        if (let Some(returnTy) <- fn.GetReturnType()) {
            if (IsVoidLikeReturn(returnTy)) {
                builder.CreateExit(None, entry)
                return
            }
            let constant = builder.CreateConstant(returnTy, literal, entry)
            if (let Some(result) <- constant.GetResult()) {
                builder.CreateExit(Some(result), entry)
                return
            }
        }
        builder.CreateExit(None, entry)
    }

    public func EnsureReturnSlot(fn: Function, entry: Block): Unit {
        if (let Some(returnTy) <- fn.GetReturnType()) {
            if (!returnTy.IsVoid()) {
                let retRefTy = builder.context.GetRefTy(returnTy)
                let allocate = builder.CreateExpression(ExprKind.ALLOCATE, Some(retRefTy),
                    ArrayList<Value>(), entry)
                if (let Some(result) <- allocate.GetResult()) {
                    fn.SetReturnValue(result)
                }
            }
        }
    }

    public func ShouldEmitBody(spec: AST2CHIRFunctionSpec): Bool {
        if (!spec.emitBody) {
            return false
        }
        if (spec.attributes.contains(Attribute.ABSTRACT) || spec.attributes.contains(Attribute.FOREIGN)) {
            return false
        }
        if (spec.attributes.contains(Attribute.IMPORTED) && !spec.attributes.contains(Attribute.SRC_CODE_IMPORTED)) {
            return false
        }
        return true
    }

    private func IsVoidLikeReturn(returnTy: Type): Bool {
        return returnTy.IsVoid() || returnTy.IsUnit() || returnTy.IsNothing()
    }

    public func ShouldTranslateMember(owner: AST2CHIRNominalSpec, memberFileKey: String): Bool {
        if (!mergingSpecific) {
            return true
        }
        if (owner.attributes.contains(Attribute.IMPORTED)) {
            return true
        }
        if (!owner.isSpecificDecl) {
            return true
        }
        if (owner.attributes.contains(Attribute.GENERIC_INSTANTIATED)) {
            return true
        }
        if (owner.sourceFileKey.isEmpty() || memberFileKey.isEmpty()) {
            return true
        }
        return owner.sourceFileKey == memberFileKey
    }

    public func GetNominalType(def: CustomTypeDef): Type {
        let typeArgs = ArrayList<Type>()
        for (param in def.genericTypeParams) {
            typeArgs.add(param)
        }
        if (let Some(classDef) <- (def as ClassDef)) {
            return builder.context.GetClassTy(classDef, typeArgs)
        }
        if (let Some(structDef) <- (def as StructDef)) {
            return builder.context.GetStructTy(structDef, typeArgs)
        }
        if (let Some(enumDef) <- (def as EnumDef)) {
            return builder.context.GetEnumTy(enumDef, typeArgs)
        }
        if (let Some(extendDef) <- (def as ExtendDef)) {
            if (let Some(extendedTy) <- extendDef.extendedType) {
                return extendedTy
            }
        }
        return builder.context.GetInvalidTy()
    }

    public func GetInstanceThisType(def: CustomTypeDef, fnSpec: AST2CHIRFunctionSpec): Type {
        let nominalTy = GetNominalType(def)
        if (let Some(_) <- (def as ClassDef)) {
            return nominalTy
        }
        if (let Some(_) <- (def as ExtendDef)) {
            return if (fnSpec.attributes.contains(Attribute.MUT) || fnSpec.funcKind == FuncKind.INSTANCEVAR_INIT) {
                builder.context.GetRefTy(nominalTy)
            } else {
                nominalTy
            }
        }
        if (fnSpec.attributes.contains(Attribute.MUT) || fnSpec.IsConstructorLike()) {
            return builder.context.GetRefTy(nominalTy)
        }
        return nominalTy
    }
}

extend AST2CHIRDeclTranslator {
    public func LowerPackage(spec: AST2CHIRPackageSpec): AST2CHIRResult {
        let pkg = builder.CreatePackage(spec.name)
        currentPackage = Some(pkg)
        mergingSpecific = spec.mergingSpecific
        var sourceFileIndex: Int64 = 0
        while (sourceFileIndex < spec.sourceFileIds.size && sourceFileIndex < spec.sourceFileNames.size) {
            builder.context.RegisterSourceFileName(spec.sourceFileIds[sourceFileIndex],
                spec.sourceFileNames[sourceFileIndex])
            sourceFileIndex++
        }
        pkg.SetPackageAccessLevel(spec.accessLevel)
        for (typeSpec in spec.types) {
            CreateNominalDef(spec.name, typeSpec)
        }
        for (globalSpec in spec.globals) {
            LowerGlobalVar(spec.name, globalSpec)
        }
        // Pre-declare all top-level functions before emitting any body so a real body can resolve a
        // callee Function by name regardless of source order (and for self-recursion).
        for (funcSpec in spec.functions) {
            PredeclareFunction(spec.name, funcSpec)
        }
        for (funcSpec in spec.functions) {
            LowerFunction(spec.name, funcSpec)
        }
        if (let Some(initSpec) <- spec.packageInitFunction) {
            let initFn = LowerFunction(spec.name, initSpec)
            pkg.SetPackageInitFunc(initFn)
        }
        if (let Some(literalInitSpec) <- spec.packageLiteralInitFunction) {
            let literalInitFn = LowerFunction(spec.name, literalInitSpec)
            pkg.SetPackageLiteralInitFunc(literalInitFn)
        }
        for (typeSpec in spec.types) {
            LowerNominalDecl(spec.name, typeSpec)
        }
        return AST2CHIRResult(pkg)
    }
}

extend AST2CHIRFunctionSpec {
    public func IsConstructorLike(): Bool {
        return funcKind == FuncKind.CLASS_CONSTRUCTOR || funcKind == FuncKind.PRIMAL_CLASS_CONSTRUCTOR ||
            funcKind == FuncKind.STRUCT_CONSTRUCTOR || funcKind == FuncKind.PRIMAL_STRUCT_CONSTRUCTOR ||
            funcKind == FuncKind.FINALIZER
    }
}
