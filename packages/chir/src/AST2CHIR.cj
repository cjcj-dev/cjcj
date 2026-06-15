package cangjie_compiler::chir

import std.collection.*

public class AST2CHIRResult {
    public let pkg: Package

    public init(pkg: Package) {
        this.pkg = pkg
    }
}

public class AST2CHIRGlobalSpec {
    public let name: String
    public let srcCodeIdentifier: String
    public let rawMangledName: String
    public let ty: Type
    public let initialValue: Option<LiteralValue>

    public init(name: String, ty: Type, srcCodeIdentifier!: String = "", rawMangledName!: String = "",
        initialValue!: Option<LiteralValue> = None) {
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        this.ty = ty
        this.initialValue = initialValue
    }
}

public class AST2CHIRFunctionSpec {
    public let name: String
    public let srcCodeIdentifier: String
    public let rawMangledName: String
    public let paramTypes: ArrayList<Type> = ArrayList<Type>()
    public let returnType: Type
    public let funcKind: FuncKind
    public let emitBody: Bool

    public init(name: String, paramTypes: ArrayList<Type>, returnType: Type, srcCodeIdentifier!: String = "",
        rawMangledName!: String = "", funcKind!: FuncKind = FuncKind.DEFAULT, emitBody!: Bool = true) {
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        for (ty in paramTypes) {
            this.paramTypes.add(ty)
        }
        this.returnType = returnType
        this.funcKind = funcKind
        this.emitBody = emitBody
    }
}

public class AST2CHIRPackageSpec {
    public let name: String
    public let globals: ArrayList<AST2CHIRGlobalSpec> = ArrayList<AST2CHIRGlobalSpec>()
    public let functions: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()

    public init(name: String) {
        this.name = name
    }

    public func AddGlobal(spec: AST2CHIRGlobalSpec): AST2CHIRPackageSpec {
        globals.add(spec)
        return this
    }

    public func AddFunction(spec: AST2CHIRFunctionSpec): AST2CHIRPackageSpec {
        functions.add(spec)
        return this
    }
}

public class AST2CHIR {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func CreateEmptyPackage(name: String): AST2CHIRResult {
        return AST2CHIRResult(builder.CreatePackage(name))
    }

    public func LowerPackage(spec: AST2CHIRPackageSpec): AST2CHIRResult {
        let pkg = builder.CreatePackage(spec.name)
        for (globalSpec in spec.globals) {
            let globalVar = builder.CreateGlobalVar(globalSpec.ty, globalSpec.name,
                srcCodeIdentifier: globalSpec.srcCodeIdentifier, rawMangledName: globalSpec.rawMangledName,
                packageName: spec.name)
            if (let Some(literal) <- globalSpec.initialValue) {
                let initFnTy = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetUnitTy())
                let initFn = builder.CreateFunction(initFnTy, globalSpec.name + "$init",
                    srcCodeIdentifier: globalSpec.srcCodeIdentifier + "$init",
                    rawMangledName: globalSpec.rawMangledName + "$init", packageName: spec.name)
                initFn.SetFuncKind(FuncKind.GLOBALVAR_INIT)
                let body = builder.CreateBlockGroup(initFn.GetIdentifier() + ".body")
                initFn.InitBody(body)
                let entry = builder.CreateBlock("entry", body)
                let constant = builder.CreateConstant(globalSpec.ty, literal, entry)
                if (let Some(result) <- constant.GetResult()) {
                    globalVar.SetInitializerValue(result)
                }
                builder.CreateExit(None, entry)
                pkg.AddGlobalFunc(initFn)
            }
            pkg.AddGlobalVar(globalVar)
        }
        for (funcSpec in spec.functions) {
            let funcTy = builder.context.GetFuncTy(funcSpec.paramTypes, funcSpec.returnType)
            let fn = builder.CreateFunction(funcTy, funcSpec.name, srcCodeIdentifier: funcSpec.srcCodeIdentifier,
                rawMangledName: funcSpec.rawMangledName, packageName: spec.name)
            fn.SetFuncKind(funcSpec.funcKind)
            var paramIndex: Int64 = 0
            for (paramTy in funcSpec.paramTypes) {
                builder.CreateParameter(paramTy, "%arg${paramIndex}", fn)
                paramIndex++
            }
            if (funcSpec.emitBody) {
                let body = builder.CreateBlockGroup(fn.GetIdentifier() + ".body")
                fn.InitBody(body)
                let entry = builder.CreateBlock("entry", body)
                builder.CreateExit(None, entry)
            }
            pkg.AddGlobalFunc(fn)
        }
        return AST2CHIRResult(pkg)
    }
}

public func ToCHIR(packageName: String, builder: CHIRBuilder): Package {
    return AST2CHIR(builder).CreateEmptyPackage(packageName).pkg
}

public func ToCHIR(spec: AST2CHIRPackageSpec, builder: CHIRBuilder): Package {
    return AST2CHIR(builder).LowerPackage(spec).pkg
}
