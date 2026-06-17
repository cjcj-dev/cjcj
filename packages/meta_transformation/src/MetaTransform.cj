package cangjie_compiler::meta_transformation

import cangjie_compiler::basic.CANGJIE_VERSION
import cangjie_compiler::chir.CHIRBuilder
import cangjie_compiler::chir.Function as CHIRFunction
import cangjie_compiler::chir.Package as CHIRPackage
import std.reflect.TypeInfo

public type MetaTransformRegisterCallback = (MetaTransformPluginBuilder) -> Unit
public type MetaTransformPluginInfoGetter = () -> MetaTransformPluginInfo
public type CHIRMetaTransformFactory = (CHIRBuilder) -> MetaTransformConcept
public type CHIRFunctionMetaTransformFactory = (CHIRBuilder) -> CHIRFunctionMetaTransform
public type CHIRPackageMetaTransformFactory = (CHIRBuilder) -> CHIRPackageMetaTransform

public let META_TRANSFORM_PLUGIN_INFO_SYMBOL: String = "getMetaTransformPluginInfo"

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

private func InferMetaTransformKind<DeclT>(): MetaTransformKind {
    let declType = TypeInfo.of<DeclT>()
    if (declType == TypeInfo.of<CHIRFunction>()) {
        return MetaTransformKind.FOR_CHIR_FUNC
    }
    if (declType == TypeInfo.of<CHIRPackage>()) {
        return MetaTransformKind.FOR_CHIR_PACKAGE
    }
    return MetaTransformKind.UNKNOWN
}

public abstract class MetaTransform<DeclT> <: MetaTransformConcept & MetaTransformRunner<DeclT> {
    public init() {
        super()
        kind = InferMetaTransformKind<DeclT>()
    }

    protected init(kind: MetaTransformKind) {
        super()
        this.kind = kind
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
    public let cjcVersion: Option<String>
    public let registerTo: Option<MetaTransformRegisterCallback>

    public init() {
        cjcVersion = None
        registerTo = None
    }

    public init(cjcVersion: String, registerTo: MetaTransformRegisterCallback) {
        this.cjcVersion = Some(cjcVersion)
        this.registerTo = Some(registerTo)
    }

    public init(cjcVersion: String) {
        this.cjcVersion = Some(cjcVersion)
        this.registerTo = None
    }

    public init(cjcVersion: String, registerTo: Option<MetaTransformRegisterCallback>) {
        this.cjcVersion = Some(cjcVersion)
        this.registerTo = registerTo
    }

    public init(cjcVersion: Option<String>, registerTo: Option<MetaTransformRegisterCallback>) {
        this.cjcVersion = cjcVersion
        this.registerTo = registerTo
    }

    public func HasVersion(): Bool {
        return cjcVersion.isSome()
    }

    public func HasRegisterCallback(): Bool {
        return registerTo.isSome()
    }

    public func VersionMatches(version: String): Bool {
        if (let Some(pluginVersion) <- cjcVersion) {
            return pluginVersion == version
        }
        return false
    }

    public func IsValidForVersion(version: String): Bool {
        return VersionMatches(version) && HasRegisterCallback()
    }

    public func IsValid(): Bool {
        return IsValidForVersion(CANGJIE_VERSION)
    }

    public func TryRegisterTo(builder: MetaTransformPluginBuilder): Bool {
        if (let Some(callback) <- registerTo) {
            callback(builder)
            return true
        }
        return false
    }

    public func RegisterTo(builder: MetaTransformPluginBuilder): Unit {
        if (!TryRegisterTo(builder)) {
            throw IllegalStateException("MetaTransform plugin info has no registration callback")
        }
    }
}

public func MakeCHIRPluginInfo<MT>(
    cjcVersion: String,
    factory: (CHIRBuilder) -> MT
): MetaTransformPluginInfo where MT <: MetaTransformConcept {
    return MetaTransformPluginInfo(cjcVersion, { builder: MetaTransformPluginBuilder =>
        builder.RegisterCHIRPluginCallback({ manager: CHIRPluginManager, chirBuilder: CHIRBuilder =>
            manager.AddMetaTransform(factory(chirBuilder))
        })
    })
}

public func MakeCHIRPluginInfo<MT>(factory: (CHIRBuilder) -> MT): MetaTransformPluginInfo
    where MT <: MetaTransformConcept {
    return MakeCHIRPluginInfo(CANGJIE_VERSION, factory)
}

public func MakeCHIRPluginInfoGetter<MT>(
    cjcVersion: String,
    factory: (CHIRBuilder) -> MT
): MetaTransformPluginInfoGetter where MT <: MetaTransformConcept {
    return { => MakeCHIRPluginInfo(cjcVersion, factory) }
}

public func MakeCHIRPluginInfoGetter<MT>(factory: (CHIRBuilder) -> MT): MetaTransformPluginInfoGetter
    where MT <: MetaTransformConcept {
    return MakeCHIRPluginInfoGetter(CANGJIE_VERSION, factory)
}

public func MakeCHIRFunctionPluginInfo<MT>(
    cjcVersion: String,
    factory: (CHIRBuilder) -> MT
): MetaTransformPluginInfo where MT <: CHIRFunctionMetaTransform {
    return MakeCHIRPluginInfo(cjcVersion, { builder: CHIRBuilder => factory(builder) })
}

public func MakeCHIRFunctionPluginInfo<MT>(factory: (CHIRBuilder) -> MT): MetaTransformPluginInfo
    where MT <: CHIRFunctionMetaTransform {
    return MakeCHIRFunctionPluginInfo(CANGJIE_VERSION, factory)
}

public func MakeCHIRFunctionPluginInfoGetter<MT>(
    cjcVersion: String,
    factory: (CHIRBuilder) -> MT
): MetaTransformPluginInfoGetter where MT <: CHIRFunctionMetaTransform {
    return { => MakeCHIRFunctionPluginInfo(cjcVersion, factory) }
}

public func MakeCHIRFunctionPluginInfoGetter<MT>(factory: (CHIRBuilder) -> MT): MetaTransformPluginInfoGetter
    where MT <: CHIRFunctionMetaTransform {
    return MakeCHIRFunctionPluginInfoGetter(CANGJIE_VERSION, factory)
}

public func MakeCHIRPackagePluginInfo<MT>(
    cjcVersion: String,
    factory: (CHIRBuilder) -> MT
): MetaTransformPluginInfo where MT <: CHIRPackageMetaTransform {
    return MakeCHIRPluginInfo(cjcVersion, { builder: CHIRBuilder => factory(builder) })
}

public func MakeCHIRPackagePluginInfo<MT>(factory: (CHIRBuilder) -> MT): MetaTransformPluginInfo
    where MT <: CHIRPackageMetaTransform {
    return MakeCHIRPackagePluginInfo(CANGJIE_VERSION, factory)
}

public func MakeCHIRPackagePluginInfoGetter<MT>(
    cjcVersion: String,
    factory: (CHIRBuilder) -> MT
): MetaTransformPluginInfoGetter where MT <: CHIRPackageMetaTransform {
    return { => MakeCHIRPackagePluginInfo(cjcVersion, factory) }
}

public func MakeCHIRPackagePluginInfoGetter<MT>(factory: (CHIRBuilder) -> MT): MetaTransformPluginInfoGetter
    where MT <: CHIRPackageMetaTransform {
    return MakeCHIRPackagePluginInfoGetter(CANGJIE_VERSION, factory)
}
