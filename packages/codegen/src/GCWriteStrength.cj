package cjcj::codegen

import std.collection.ArrayList
import cjcj::chir.{CheckCustomTypeDefIsExpected, CustomType, Expression, GetElementByName, GetElementRef, LocalVar, Value}
import cjcj::utils.REF_PACKAGE_NAME

// LLVM GCWriteRef::StrengthKind. Like ZGC access decorators, this belongs to
// the access, not to the type of the value being stored.
public enum GCWriteStrength {
    | UNKNOWN | STRONG | NO_KEEP_ALIVE

    public func Encode(): UInt64 {
        match (this) {
            case UNKNOWN => 0u64
            case STRONG => 1u64
            case NO_KEEP_ALIVE => 2u64
        }
    }
}

public func GetAddressStoreStrength(irBuilder: IRBuilder2, address: Value,
    store: Expression): GCWriteStrength {
    return GetAddressAccessStrength(irBuilder, address, store, false)
}

// The referent is identified by its declaring field, not by the class of
// the receiver. Queue and chain fields use ordinary strong loads.
public func IsWeakReferentLoad(irBuilder: IRBuilder2, address: Value, load: Expression): Bool {
    match (GetAddressAccessStrength(irBuilder, address, load, true)) {
        case GCWriteStrength.NO_KEEP_ALIVE => true
        case _ => false
    }
}

private func GetAddressAccessStrength(irBuilder: IRBuilder2, address: Value,
    access: Expression, isLoad: Bool): GCWriteStrength {
    let local = (address as LocalVar) ?? return GCWriteStrength.UNKNOWN
    let expression = local.GetExpr() ?? return GCWriteStrength.UNKNOWN
    if (let Some(field) <- (expression as GetElementRef)) {
        return GetMemberAccessStrength(irBuilder, field.GetLocation(), field.GetPath(), access, isLoad)
    }
    if (let Some(field) <- (expression as GetElementByName)) {
        let base = field.GetLocation()
        let baseType = base.GetType() ?? return GCWriteStrength.UNKNOWN
        let path = ResolveElementPathByNames(irBuilder.GetCGModule(), baseType, field.GetNames()) ??
            return GCWriteStrength.UNKNOWN
        return GetMemberAccessStrength(irBuilder, base, path, access, isLoad)
    }
    return GCWriteStrength.UNKNOWN
}

public func GetMemberStoreStrength(irBuilder: IRBuilder2, base: Value, path: ArrayList<UInt64>,
    store: Expression): GCWriteStrength {
    return GetMemberAccessStrength(irBuilder, base, path, store, false)
}

private func GetMemberAccessStrength(irBuilder: IRBuilder2, base: Value, path: ArrayList<UInt64>,
    access: Expression, isLoad: Bool): GCWriteStrength {
    let baseType = base.GetType() ?? return GCWriteStrength.UNKNOWN
    var current = baseType.StripAllRefs()
    var strength = GCWriteStrength.UNKNOWN
    for (index in path) {
        if (current.IsGeneric()) {
            return GCWriteStrength.UNKNOWN
        }
        if (let Some(custom) <- (current as CustomType)) {
            let fields = custom.GetCustomTypeDef().GetAllInstanceVars()
            if (index >= UInt64(fields.size)) {
                return GCWriteStrength.UNKNOWN
            }
            let field = fields[Int64(index)]
            let owner = field.outerDef ?? return GCWriteStrength.UNKNOWN
            // Resolve the declaring field, including inherited access through
            // WeakRef<T>. An unrelated field called _value is not a referent.
            let isReferent = CheckCustomTypeDefIsExpected(owner, REF_PACKAGE_NAME, "WeakRefBase") &&
                field.name == "_value"
            strength = if (isReferent) { GCWriteStrength.NO_KEEP_ALIVE } else { GCWriteStrength.STRONG }
            // ZGC parse3.cpp:317-320: initialization is an ordinary putfield.
            // Only the constructor's own receiver qualifies, not another ref.
            if (!isLoad && isReferent && path.size == 1) {
                if (let Some(function) <- access.GetTopLevelFunc()) {
                    if (function.IsConstructor() && function.GetNumOfParams() > 0 &&
                        function.GetParam(0).nodeId == base.nodeId) {
                        strength = GCWriteStrength.STRONG
                    }
                }
            }
            let types = custom.GetInstantiatedMemberTys(irBuilder.GetCGContext().GetCHIRBuilder())
            if (index >= UInt64(types.size)) {
                return GCWriteStrength.UNKNOWN
            }
            current = types[Int64(index)].StripAllRefs()
        } else {
            // Arrays, tuples and boxed payloads have no referent field.
            let cgType = CGType.GetOrCreate(irBuilder.GetCGModule(), current)
            let types = cgType.GetContainedTypes()
            let typeIndex = if (current.IsRawArray() || current.IsVArray()) { 0u64 } else { index }
            if (typeIndex >= UInt64(types.size)) {
                return GCWriteStrength.UNKNOWN
            }
            current = types[Int64(typeIndex)].GetOriginal().StripAllRefs()
            strength = GCWriteStrength.STRONG
        }
    }
    return strength
}
