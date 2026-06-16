package cangjie_compiler::chir

import std.collection.*

public class AST2CHIRDeclTranslator {
    public let builder: CHIRBuilder
    public var currentPackage: Option<Package> = None
    public let typeDefs: HashMap<String, CustomTypeDef> = HashMap<String, CustomTypeDef>()
    public let functions: HashMap<String, Function> = HashMap<String, Function>()
    public let globals: HashMap<String, GlobalVar> = HashMap<String, GlobalVar>()

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RegisterFunction(fn: Function): Unit {
        functions[fn.GetIdentifier()] = fn
    }

    public func RegisterGlobal(globalVar: GlobalVar): Unit {
        globals[globalVar.GetIdentifier()] = globalVar
    }

    public func RegisterTypeDef(name: String, def: CustomTypeDef): Unit {
        typeDefs[name] = def
    }

    public func TryGetTypeDef(name: String): Option<CustomTypeDef> {
        return typeDefs.get(name)
    }

    public func TryGetFunction(name: String): Option<Function> {
        return functions.get(name)
    }

    public func ResolvePackageName(defaultPackage: String, declaredPackage: String): String {
        return if (declaredPackage.isEmpty()) { defaultPackage } else { declaredPackage }
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

    public func CreateEmptyBody(fn: Function): Unit {
        let body = builder.CreateBlockGroup(fn.GetIdentifier() + ".body")
        fn.InitBody(body)
        let entry = builder.CreateBlock("entry", body)
        builder.CreateExit(None, entry)
    }

    public func ShouldEmitBody(spec: AST2CHIRFunctionSpec): Bool {
        if (!spec.emitBody) {
            return false
        }
        if (spec.attributes.contains(Attribute.ABSTRACT) || spec.attributes.contains(Attribute.FOREIGN)) {
            return false
        }
        return true
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
        for (typeSpec in spec.types) {
            CreateNominalDef(spec.name, typeSpec)
        }
        for (globalSpec in spec.globals) {
            LowerGlobalVar(spec.name, globalSpec)
        }
        for (funcSpec in spec.functions) {
            LowerFunction(spec.name, funcSpec)
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
