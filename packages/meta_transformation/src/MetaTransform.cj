package cjcj::meta_transformation

import cjcj::chir.Function as CHIRFunction
import cjcj::chir.Package as CHIRPackage

public type NativeMetaTransformPluginBuilderRef = CPointer<NativeMetaTransformPluginBuilder>

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
        return IsForFunc() || IsForPackage()
    }

    public func IsForFunc(): Bool {
        return this is MetaTransform<CHIRFunction>
    }

    public func IsForPackage(): Bool {
        return this is MetaTransform<CHIRPackage>
    }
}

public interface MetaTransformRunner<DeclT> {
    func Run(decl: DeclT): Unit
}

public abstract class MetaTransform<DeclT> <: MetaTransformConcept & MetaTransformRunner<DeclT> {
    public init() {
        super()
    }
}

@C
public struct NativeMetaTransformPluginBuilder {
    public init() {
        throw Exception("NativeMetaTransformPluginBuilder is an opaque C++ MetaTransformPluginBuilder reference")
    }
}

@C
public struct MetaTransformPluginInfo {
    public let cjcVersion: CString
    public let registerTo: CFunc<(NativeMetaTransformPluginBuilderRef) -> Unit>

    public init() {
        cjcVersion = CString(CPointer<UInt8>())
        registerTo = CFunc<(NativeMetaTransformPluginBuilderRef) -> Unit>(CPointer<Unit>())
    }

    public init(cjcVersion: CString, registerTo: CFunc<(NativeMetaTransformPluginBuilderRef) -> Unit>) {
        this.cjcVersion = cjcVersion
        this.registerTo = registerTo
    }
}
