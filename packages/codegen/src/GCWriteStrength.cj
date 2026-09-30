package cjcj::codegen

import std.collection.ArrayList
import cjcj::chir.{CheckCustomTypeDefIsExpected, ClassType, CustomType, Expression, GetElementByName, GetElementRef, LocalVar, Value}
import cjcj::utils.CORE_PACKAGE_NAME

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
            let isReferent = CheckCustomTypeDefIsExpected(owner, CORE_PACKAGE_NAME, "Reference") &&
                field.name == "_value"
            let isFinal = if (let Some(classTy) <- (custom as ClassType)) {
                IsFinalReferenceClass(classTy)
            } else { false }
            strength = if (isReferent && !isFinal) {
                GCWriteStrength.NO_KEEP_ALIVE
            } else { GCWriteStrength.STRONG }
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

// Reference.queue/next and ReferenceQueue.head correspond to Java volatile
// reference fields (Reference.java:176,186; ReferenceQueue.java:61).
public func IsVolatileReferenceAddress(irBuilder: IRBuilder2, address: Value): Bool {
    let local = (address as LocalVar) ?? return false
    let expression = local.GetExpr() ?? return false
    if (let Some(field) <- (expression as GetElementRef)) {
        return IsVolatileReferenceMember(irBuilder, field.GetLocation(), field.GetPath())
    }
    if (let Some(field) <- (expression as GetElementByName)) {
        let base = field.GetLocation()
        let baseType = base.GetType() ?? return false
        let path = ResolveElementPathByNames(irBuilder.GetCGModule(), baseType, field.GetNames()) ?? return false
        return IsVolatileReferenceMember(irBuilder, base, path)
    }
    return false
}

public func IsVolatileReferenceMember(irBuilder: IRBuilder2, base: Value, path: ArrayList<UInt64>): Bool {
    let baseType = base.GetType() ?? return false
    var current = baseType.StripAllRefs()
    for (position in 0..path.size) {
        let index = path[position]
        if (let Some(custom) <- (current as CustomType)) {
            let fields = custom.GetCustomTypeDef().GetAllInstanceVars()
            if (index >= UInt64(fields.size)) { return false }
            let field = fields[Int64(index)]
            if (position == path.size - 1) {
                let owner = field.outerDef ?? return false
                return (CheckCustomTypeDefIsExpected(owner, CORE_PACKAGE_NAME, "Reference") &&
                    (field.name == "_queue" || field.name == "_next")) ||
                    (CheckCustomTypeDefIsExpected(owner, CORE_PACKAGE_NAME, "ReferenceQueue") && field.name == "head")
            }
            let types = custom.GetInstantiatedMemberTys(irBuilder.GetCGContext().GetCHIRBuilder())
            if (index >= UInt64(types.size)) { return false }
            current = types[Int64(index)].StripAllRefs()
        } else {
            let types = CGType.GetOrCreate(irBuilder.GetCGModule(), current).GetContainedTypes()
            let typeIndex = if (current.IsRawArray() || current.IsVArray()) { 0u64 } else { index }
            if (typeIndex >= UInt64(types.size)) { return false }
            current = types[Int64(typeIndex)].GetOriginal().StripAllRefs()
        }
    }
    return false
}
