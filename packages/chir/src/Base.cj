package cjcj::chir

import std.sync.AtomicInt64

private class BaseIdAllocator {
    private static let nextId = AtomicInt64(1)

    public static func Next(): Int64 {
        return nextId.fetchAdd(1)
    }
}

public open class Base <: Hashable & Equatable<Base> {
    public let nodeId: Int64
    private let annotationMap: AnnotationMap = AnnotationMap()
    var loc: DebugLocation = DebugLocation()
    private let attributes: AttributeInfo = AttributeInfo()

    public init() {
        nodeId = BaseIdAllocator.Next()
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

    public func Set<T, R>(value: R): Unit where T <: Annotation<R> {
        annotationMap.Set<T, R>(value)
    }

    public func Remove<T>(): Unit {
        annotationMap.Remove<T>()
    }

    public func Get<T, R>(): R where T <: Annotation<R> {
        return annotationMap.Get<T, R>()
    }

    public func SetGeneratedFromForIn(value: Bool): Unit {
        annotationMap.Set<GeneratedFromForIn, Bool>(value)
    }

    public func SetSkipCheck(kind: SkipKind): Unit {
        annotationMap.Set<SkipCheck, SkipKind>(kind)
    }

    public func SetNeverOverflowInfo(value: Bool): Unit {
        annotationMap.Set<NeverOverflowInfo, Bool>(value)
    }

    public func SetNeedCheckCast(value: Bool): Unit {
        annotationMap.Set<NeedCheckCast, Bool>(value)
    }

    public func SetNeedCheckArrayBound(value: Bool): Unit {
        annotationMap.Set<NeedCheckArrayBound, Bool>(value)
    }

    public func SetEnumCaseIndex(value: Option<Int64>): Unit {
        annotationMap.Set<EnumCaseIndex, Option<Int64>>(value)
    }

    public func RemoveGeneratedFromForIn(): Unit {
        annotationMap.Remove<GeneratedFromForIn>()
    }

    public func RemoveSkipCheck(): Unit {
        annotationMap.Remove<SkipCheck>()
    }

    public func GetGeneratedFromForIn(): Bool {
        return annotationMap.Get<GeneratedFromForIn, Bool>()
    }

    public func GetSkipCheck(): SkipKind {
        return annotationMap.Get<SkipCheck, SkipKind>()
    }

    public func GetNeverOverflowInfo(): Bool {
        return annotationMap.Get<NeverOverflowInfo, Bool>()
    }

    public func GetNeedCheckCast(): Bool {
        return annotationMap.Get<NeedCheckCast, Bool>()
    }

    public func GetNeedCheckArrayBound(): Bool {
        return annotationMap.Get<NeedCheckArrayBound, Bool>()
    }

    public func GetEnumCaseIndex(): Option<Int64> {
        return annotationMap.Get<EnumCaseIndex, Option<Int64>>()
    }

    public func GetAnno(): AnnotationMap {
        return annotationMap
    }

    public open func GetDebugLocation(): DebugLocation {
        return loc
    }

    public func SetDebugLocation(newLoc: DebugLocation): Unit {
        loc = newLoc
    }

    public func SetDebugLocationInfoForWarning(newLoc: DebugLocation): Unit {
        annotationMap.Set<DebugLocationInfoForWarning, DebugLocation>(newLoc)
    }

    public func GetDebugLocationInfoForWarning(): DebugLocation {
        return annotationMap.Get<DebugLocationInfoForWarning, DebugLocation>()
    }

    public func GetAttributeInfo(): AttributeInfo {
        return AttributeInfo(attributes)
    }

    public func AppendAttributeInfo(info: AttributeInfo): Unit {
        attributes.Append(info)
    }

    public func DisableAttr(attr: Attribute): Unit {
        attributes.Disable(attr)
    }

    public func EnableAttr(attr: Attribute): Unit {
        attributes.Enable(attr)
    }

    public func TestAttr(attr: Attribute): Bool {
        return attributes.Test(attr)
    }

    public func CopyBaseInfoFrom(other: Base): Unit {
        annotationMap.CopyFrom(other.GetAnno())
        loc = other.GetDebugLocation()
    }

    public func BaseCommentToString(): String {
        let annotationText = annotationMap.ToString()
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
