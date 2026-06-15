package cangjie_compiler::chir

private class BaseIdAllocator {
    private static var nextId: Int64 = 1

    public static func Next(): Int64 {
        let out = nextId
        nextId++
        return out
    }
}

public open class Base {
    public let nodeId: Int64
    private let annotationMap: AnnotationMap = AnnotationMap()
    private var loc: DebugLocation = DebugLocation()
    private let attributes: AttributeInfo = AttributeInfo()

    public init() {
        nodeId = BaseIdAllocator.Next()
    }

    public func SetAnnotation(key: String, value: String): Unit {
        annotationMap.Set(key, value)
    }

    public func RemoveAnnotation(key: String): Unit {
        annotationMap.Remove(key)
    }

    public func GetAnnotation(key: String): Option<String> {
        return annotationMap.Get(key)
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

    public func GetAttributeInfo(): AttributeInfo {
        return attributes
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
        attributes.CopyFrom(other.GetAttributeInfo())
    }

    public func BaseCommentToString(): String {
        let annotationText = annotationMap.ToString()
        let locText = loc.ToString()
        if (annotationText.isEmpty() && locText.isEmpty()) {
            return ""
        }
        if (annotationText.isEmpty()) {
            return "loc=${locText}"
        }
        if (locText.isEmpty()) {
            return annotationText
        }
        return annotationText + " loc=${locText}"
    }
}
