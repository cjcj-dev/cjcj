package cangjie_compiler::meta_transformation

public enum MetaTransformKind {
    | UNKNOWN
    | FOR_CHIR_FUNC
    | FOR_CHIR_PACKAGE
    | FOR_CHIR
}

private func MetaTransformKindIndex(kind: MetaTransformKind): Int64 {
    return match (kind) {
        case MetaTransformKind.UNKNOWN => 0
        case MetaTransformKind.FOR_CHIR_FUNC => 1
        case MetaTransformKind.FOR_CHIR_PACKAGE => 2
        case MetaTransformKind.FOR_CHIR => 3
    }
}

extend MetaTransformKind <: Equatable<MetaTransformKind> {
    public operator func ==(right: MetaTransformKind): Bool {
        return MetaTransformKindIndex(this) == MetaTransformKindIndex(right)
    }

    public operator func !=(right: MetaTransformKind): Bool {
        return !(this == right)
    }
}

public interface MetaTransformCHIRBuilder {}

public interface MetaTransformCHIRFunction {}

public interface MetaTransformCHIRPackage {}

public open class MetaTransformConcept {
    protected var kind: MetaTransformKind = MetaTransformKind.UNKNOWN

    public init() {}

    public init(kind: MetaTransformKind) {
        this.kind = kind
    }

    public func GetKind(): MetaTransformKind {
        return kind
    }

    public func IsForCHIR(): Bool {
        return MetaTransformKindIndex(kind) > MetaTransformKindIndex(MetaTransformKind.UNKNOWN) &&
            MetaTransformKindIndex(kind) < MetaTransformKindIndex(MetaTransformKind.FOR_CHIR)
    }

    public func IsForFunc(): Bool {
        return kind == MetaTransformKind.FOR_CHIR_FUNC
    }

    public func IsForPackage(): Bool {
        return kind == MetaTransformKind.FOR_CHIR_PACKAGE
    }
}

public interface MetaTransformRunner<DeclT> {
    func Run(decl: DeclT): Unit
}

public abstract class MetaTransform<DeclT> <: MetaTransformConcept & MetaTransformRunner<DeclT> {
    public init() {
        super(MetaTransformKind.UNKNOWN)
    }

    public init(kind: MetaTransformKind) {
        super(kind)
    }
}

public abstract class CHIRFunctionMetaTransform <: MetaTransform<MetaTransformCHIRFunction> {
    public init() {
        super(MetaTransformKind.FOR_CHIR_FUNC)
    }
}

public abstract class CHIRPackageMetaTransform <: MetaTransform<MetaTransformCHIRPackage> {
    public init() {
        super(MetaTransformKind.FOR_CHIR_PACKAGE)
    }
}

public struct MetaTransformPluginInfo {
    public let cjcVersion: String
    public let registerTo: (MetaTransformPluginBuilder) -> Unit

    public init(cjcVersion: String, registerTo: (MetaTransformPluginBuilder) -> Unit) {
        this.cjcVersion = cjcVersion
        this.registerTo = registerTo
    }
}

public func MakeCHIRPluginInfo(
    cjcVersion: String,
    factory: (MetaTransformCHIRBuilder) -> MetaTransformConcept
): MetaTransformPluginInfo {
    return MetaTransformPluginInfo(cjcVersion, { builder: MetaTransformPluginBuilder =>
        builder.RegisterCHIRPluginCallback({ manager: CHIRPluginManager, chirBuilder: MetaTransformCHIRBuilder =>
            manager.AddMetaTransform(factory(chirBuilder))
        })
    })
}
