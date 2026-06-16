package cangjie_compiler::meta_transformation

import cangjie_compiler::basic.CANGJIE_VERSION
import cangjie_compiler::chir.CHIRBuilder
import cangjie_compiler::chir.Function as CHIRFunction
import cangjie_compiler::chir.Package as CHIRPackage

public type MetaTransformRegisterCallback = (MetaTransformPluginBuilder) -> Unit

public enum MetaTransformKind {
    | UNKNOWN
    | FOR_CHIR_FUNC
    | FOR_CHIR_PACKAGE
    | FOR_CHIR
}

public func MetaTransformKindIndex(kind: MetaTransformKind): Int64 {
    return match (kind) {
        case MetaTransformKind.UNKNOWN => 0
        case MetaTransformKind.FOR_CHIR_FUNC => 1
        case MetaTransformKind.FOR_CHIR_PACKAGE => 2
        case MetaTransformKind.FOR_CHIR => 3
    }
}

extend MetaTransformKind <: Equatable<MetaTransformKind> & Comparable<MetaTransformKind> {
    public operator func ==(right: MetaTransformKind): Bool {
        return MetaTransformKindIndex(this) == MetaTransformKindIndex(right)
    }

    public operator func !=(right: MetaTransformKind): Bool {
        return !(this == right)
    }

    public operator func <(right: MetaTransformKind): Bool {
        return MetaTransformKindIndex(this) < MetaTransformKindIndex(right)
    }

    public operator func <=(right: MetaTransformKind): Bool {
        return MetaTransformKindIndex(this) <= MetaTransformKindIndex(right)
    }

    public operator func >(right: MetaTransformKind): Bool {
        return MetaTransformKindIndex(this) > MetaTransformKindIndex(right)
    }

    public operator func >=(right: MetaTransformKind): Bool {
        return MetaTransformKindIndex(this) >= MetaTransformKindIndex(right)
    }

    public func compare(right: MetaTransformKind): Ordering {
        let leftIndex = MetaTransformKindIndex(this)
        let rightIndex = MetaTransformKindIndex(right)
        if (leftIndex < rightIndex) {
            return Ordering.LT
        }
        if (leftIndex > rightIndex) {
            return Ordering.GT
        }
        return Ordering.EQ
    }
}

public open class MetaTransformConcept {
    protected var kind: MetaTransformKind = MetaTransformKind.UNKNOWN

    public init() {}

    protected init(kind: MetaTransformKind) {
        this.kind = kind
    }

    public func GetKind(): MetaTransformKind {
        return kind
    }

    public func IsForCHIR(): Bool {
        return kind > MetaTransformKind.UNKNOWN && kind < MetaTransformKind.FOR_CHIR
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

    protected init(kind: MetaTransformKind) {
        super(kind)
    }
}

public abstract class CHIRFunctionMetaTransform <: MetaTransform<CHIRFunction> {
    public init() {
        super(MetaTransformKind.FOR_CHIR_FUNC)
    }
}

public abstract class CHIRPackageMetaTransform <: MetaTransform<CHIRPackage> {
    public init() {
        super(MetaTransformKind.FOR_CHIR_PACKAGE)
    }
}

public struct MetaTransformPluginInfo {
    public let cjcVersion: String
    public let registerTo: MetaTransformRegisterCallback

    public init(cjcVersion: String, registerTo: MetaTransformRegisterCallback) {
        this.cjcVersion = cjcVersion
        this.registerTo = registerTo
    }
}

public func MakeCHIRPluginInfo(
    cjcVersion: String,
    factory: (CHIRBuilder) -> MetaTransformConcept
): MetaTransformPluginInfo {
    return MetaTransformPluginInfo(cjcVersion, { builder: MetaTransformPluginBuilder =>
        builder.RegisterCHIRPluginCallback({ manager: CHIRPluginManager, chirBuilder: CHIRBuilder =>
            manager.AddMetaTransform(factory(chirBuilder))
        })
    })
}

public func MakeCHIRPluginInfo(factory: (CHIRBuilder) -> MetaTransformConcept): MetaTransformPluginInfo {
    return MakeCHIRPluginInfo(CANGJIE_VERSION, factory)
}
