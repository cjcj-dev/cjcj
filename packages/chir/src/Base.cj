package cjcj::chir

import std.sync.{AtomicInt64, Mutex}

private class BaseIdAllocator {
    private static let nextId = AtomicInt64(1)

    public static func Next(): Int64 {
        return nextId.fetchAdd(1)
    }
}

public open class Base <: Hashable & Equatable<Base> {
    public let nodeId: Int64
    private var annotationMap: Option<AnnotationMap> = None
    var loc: DebugLocation = DebugLocation()
    private var attributes: AttributeInfoBits = AttributeInfoBits(0u64)
    private let attributeMutex: Option<Mutex>

    public init(sharedAttributes!: Bool = false) {
        nodeId = BaseIdAllocator.Next()
        attributeMutex = if (sharedAttributes) { Some(Mutex()) } else { None }
    }

    public operator func ==(right: Base): Bool {
        return nodeId == right.nodeId
    }

    public operator func !=(right: Base): Bool {
        return nodeId != right.nodeId
    }

    public open func hashCode(): Int64 {
        return nodeId.hashCode()
    }

    // The caller holds attributeMutex on shared values.
    private func EnsureAnnotationMap(): AnnotationMap {
        if (let Some(map) <- annotationMap) {
            return map
        }
        let map = AnnotationMap()
        annotationMap = Some(map)
        return map
    }

    public func Set<T, R>(value: R): Unit where T <: Annotation<R> {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { EnsureAnnotationMap().Set<T, R>(value) }
        } else { EnsureAnnotationMap().Set<T, R>(value) }
    }

    public func Remove<T>(): Unit where T <: AnnotationBase {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { RemoveAnnotation<T>() }
        } else { RemoveAnnotation<T>() }
    }

    private func RemoveAnnotation<T>(): Unit where T <: AnnotationBase {
        if (let Some(map) <- annotationMap) { map.Remove<T>() }
    }

    public func Get<T, R>(): R where T <: Annotation<R> {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { return GetAnnotation<T, R>() }
        }
        return GetAnnotation<T, R>()
    }

    private func GetAnnotation<T, R>(): R where T <: Annotation<R> {
        if (let Some(map) <- annotationMap) { return map.Get<T, R>() }
        return T.DefaultValue()
    }

    public func SetGeneratedFromForIn(value: Bool): Unit {
        Set<GeneratedFromForIn, Bool>(value)
    }

    public func SetSkipCheck(kind: SkipKind): Unit {
        Set<SkipCheck, SkipKind>(kind)
    }

    public func SetNeverOverflowInfo(value: Bool): Unit {
        Set<NeverOverflowInfo, Bool>(value)
    }

    public func SetNeedCheckCast(value: Bool): Unit {
        Set<NeedCheckCast, Bool>(value)
    }

    public func SetNeedCheckArrayBound(value: Bool): Unit {
        Set<NeedCheckArrayBound, Bool>(value)
    }

    public func SetEnumCaseIndex(value: Option<Int64>): Unit {
        Set<EnumCaseIndex, Option<Int64>>(value)
    }

    public func RemoveGeneratedFromForIn(): Unit {
        Remove<GeneratedFromForIn>()
    }

    public func RemoveSkipCheck(): Unit {
        Remove<SkipCheck>()
    }

    public func GetGeneratedFromForIn(): Bool {
        return Get<GeneratedFromForIn, Bool>()
    }

    public func GetSkipCheck(): SkipKind {
        return Get<SkipCheck, SkipKind>()
    }

    public func GetNeverOverflowInfo(): Bool {
        return Get<NeverOverflowInfo, Bool>()
    }

    public func GetNeedCheckCast(): Bool {
        return Get<NeedCheckCast, Bool>()
    }

    public func GetNeedCheckArrayBound(): Bool {
        return Get<NeedCheckArrayBound, Bool>()
    }

    public func GetEnumCaseIndex(): Option<Int64> {
        return Get<EnumCaseIndex, Option<Int64>>()
    }

    func GetAnnotations(): Option<Array<(TypeIndex, AnnotationBase)>> {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { return SnapshotAnnotations() }
        }
        return SnapshotAnnotations()
    }

    private func SnapshotAnnotations(): Option<Array<(TypeIndex, AnnotationBase)>> {
        if (let Some(map) <- annotationMap) { return Some(map.Snapshot()) }
        return None
    }

    func ClearAnnotations(): Unit {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { ClearAnnotationMap() }
        } else { ClearAnnotationMap() }
    }

    private func ClearAnnotationMap(): Unit {
        if (let Some(map) <- annotationMap) { map.Clear() }
    }

    func AnnotationsToString(): String {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { return AnnotationMapToString() }
        }
        return AnnotationMapToString()
    }

    private func AnnotationMapToString(): String {
        if (let Some(map) <- annotationMap) { return map.ToString() }
        return ""
    }

    public open func GetDebugLocation(): DebugLocation {
        return loc
    }

    public func SetDebugLocation(newLoc: DebugLocation): Unit {
        loc = newLoc
    }

    public func SetDebugLocationInfoForWarning(newLoc: DebugLocation): Unit {
        Set<DebugLocationInfoForWarning, DebugLocation>(newLoc)
    }

    public func GetDebugLocationInfoForWarning(): DebugLocation {
        return Get<DebugLocationInfoForWarning, DebugLocation>()
    }

    public func GetAttributeInfo(): AttributeInfo {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { return AttributeInfo(attributes) }
        }
        return AttributeInfo(attributes)
    }

    public func AppendAttributeInfo(info: AttributeInfo): Unit {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { attributes.Append(info.GetBits()) }
        } else { attributes.Append(info.GetBits()) }
    }

    public func DisableAttr(attr: Attribute): Unit {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { attributes.Disable(attr) }
        } else { attributes.Disable(attr) }
    }

    public func EnableAttr(attr: Attribute): Unit {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { attributes.Enable(attr) }
        } else { attributes.Enable(attr) }
    }

    public func TestAttr(attr: Attribute): Bool {
        if (let Some(mutex) <- attributeMutex) {
            synchronized(mutex) { return attributes.Test(attr) }
        }
        return attributes.Test(attr)
    }

    public func CopyBaseInfoFrom(other: Base): Unit {
        if (!refEq(this, other)) {
            CopyAnnotationsFrom(other)
        }
        loc = other.GetDebugLocation()
    }

    private func CopyAnnotationsFrom(other: Base): Unit {
        // When both maps belong to shared values, acquire their locks in node ID order.
        let first = if (nodeId < other.nodeId) { attributeMutex } else { other.attributeMutex }
        let second = if (nodeId < other.nodeId) { other.attributeMutex } else { attributeMutex }
        if (let Some(mutex) <- first) {
            synchronized(mutex) { CopyAnnotationsUnderLock(other, second) }
        } else { CopyAnnotationsUnderLock(other, second) }
    }

    private func CopyAnnotationsUnderLock(other: Base, lock: Option<Mutex>): Unit {
        if (let Some(mutex) <- lock) {
            synchronized(mutex) { CopyAnnotationMap(other) }
        } else { CopyAnnotationMap(other) }
    }

    private func CopyAnnotationMap(other: Base): Unit {
        if ((let Some(source) <- other.annotationMap) && !source.IsEmpty()) {
            EnsureAnnotationMap().CopyFrom(source)
        } else {
            ClearAnnotationMap()
        }
    }

    public func BaseCommentToString(): String {
        let annotationText = AnnotationsToString()
        let locText = loc.ToString()
        if (annotationText.isEmpty() && locText.isEmpty()) {
            return ""
        }
        if (annotationText.isEmpty()) {
            return locText
        }
        if (locText.isEmpty()) {
            return annotationText
        }
        return locText + ", " + annotationText
    }
}

func GetDebugLocation(base: Base): DebugLocation {
    return base.loc
}
