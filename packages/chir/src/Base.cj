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

    public func SetGeneratedFromForIn(value: Bool): Unit {
        let label = GeneratedFromForIn(value)
        if (GeneratedFromForIn.Extract(label)) {
            annotationMap.Set("GeneratedFromForIn", "true")
        }
    }

    public func SetSkipCheck(kind: SkipKind): Unit {
        let label = SkipCheck(kind)
        if (SkipCheck.Extract(label) == SkipKind.NO_SKIP) {
            annotationMap.Remove("SkipCheck")
        } else {
            annotationMap.Set("SkipCheck", SkipKindIndex(SkipCheck.Extract(label)).toString())
        }
    }

    public func RemoveAnnotation(key: String): Unit {
        annotationMap.Remove(key)
    }

    public func RemoveGeneratedFromForIn(): Unit {
        annotationMap.Remove("GeneratedFromForIn")
    }

    public func RemoveSkipCheck(): Unit {
        annotationMap.Remove("SkipCheck")
    }

    public func GetAnnotation(key: String): Option<String> {
        return annotationMap.Get(key)
    }

    public func GetGeneratedFromForIn(): Bool {
        if (annotationMap.Get("GeneratedFromForIn").isSome()) {
            return GeneratedFromForIn.Extract(GeneratedFromForIn(true))
        }
        return GeneratedFromForIn.Extract(GeneratedFromForIn())
    }

    public func GetSkipCheck(): SkipKind {
        if (let Some(value) <- annotationMap.Get("SkipCheck")) {
            return match (value) {
                case "1" => SkipKind.SKIP_DCE_WARNING
                case "2" => SkipKind.SKIP_FORIN_EXIT
                case "3" => SkipKind.SKIP_VIC
                case _ => SkipKind.NO_SKIP
            }
        }
        return SkipKind.NO_SKIP
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
