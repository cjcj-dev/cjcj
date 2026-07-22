package cjcj::chir

import cjcj::basic.Linkage as BasicLinkage
import std.collection.*
import std.sync.AtomicInt64

// C++ ConstAnalysis.h:242-247 producer is ported by ConstAnalysis.MarkExpressionAsMustNotOverflow.

private class TypeIndexIdAllocator {
    private static let nextId = AtomicInt64(1)

    public static func Next(): Int64 {
        return nextId.fetchAdd(1)
    }
}

// Mirrors std::type_index in Annotation.h:363-434 with one process-local token per annotation class.
public class TypeIndex <: Hashable & Equatable<TypeIndex> {
    private let objectId: Int64 = TypeIndexIdAllocator.Next()

    public init() {}

    public operator func ==(right: TypeIndex): Bool { return objectId == right.objectId }
    public operator func !=(right: TypeIndex): Bool { return objectId != right.objectId }
    public func hashCode(): Int64 { return objectId.hashCode() }
}

public interface AnnotationBase {
    func Clone(): AnnotationBase
    func ToString(): String
}

public interface Annotation<T> <: AnnotationBase {
    static func GetTypeIndex(): TypeIndex
    static func Create(): Annotation<T>
    static func Create(value: T): Annotation<T>
    static func Extract(annotation: Annotation<T>): T
}

public class AnnoFactoryInfo <: Annotation<ArrayList<GlobalVar>> {
    private static let typeIndex = TypeIndex()
    private let value: ArrayList<GlobalVar> = ArrayList<GlobalVar>()

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {}

    public init(values: ArrayList<GlobalVar>) {
        for (globalVar in values) { value.add(globalVar) }
    }

    public static func Create(): Annotation<ArrayList<GlobalVar>> {
        return AnnoFactoryInfo()
    }

    public static func Create(values: ArrayList<GlobalVar>): Annotation<ArrayList<GlobalVar>> {
        return AnnoFactoryInfo(values)
    }

    public static func Extract(annotation: Annotation<ArrayList<GlobalVar>>): ArrayList<GlobalVar> {
        let values = ArrayList<GlobalVar>()
        for (globalVar in (annotation as AnnoFactoryInfo).getOrThrow().value) { values.add(globalVar) }
        return values
    }

    public func Clone(): AnnotationBase {
        return AnnoFactoryInfo(value)
    }

    public func ToString(): String {
        var out = "annoGVs:"
        for (globalVar in value) { out += globalVar.GetIdentifier() + "," }
        return out
    }
}

public class NeedCheckArrayBound <: Annotation<Bool> {
    private static let typeIndex = TypeIndex()
    private let need: Bool

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        need = true
    }

    public init(input: Bool) {
        need = input
    }

    public static func Create(): Annotation<Bool> {
        return NeedCheckArrayBound()
    }

    public static func Create(input: Bool): Annotation<Bool> {
        return NeedCheckArrayBound(input)
    }

    public static func Extract(annotation: Annotation<Bool>): Bool {
        return (annotation as NeedCheckArrayBound).getOrThrow().need
    }

    public func Clone(): AnnotationBase {
        return NeedCheckArrayBound(need)
    }

    public func ToString(): String {
        return "checkArrayBound: " + if (need) { "true" } else { "false" }
    }
}

public class NeedCheckCast <: Annotation<Bool> {
    private static let typeIndex = TypeIndex()
    private let need: Bool

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        need = true
    }

    public init(input: Bool) {
        need = input
    }

    public static func Create(): Annotation<Bool> {
        return NeedCheckCast()
    }

    public static func Create(input: Bool): Annotation<Bool> {
        return NeedCheckCast(input)
    }

    public static func Extract(annotation: Annotation<Bool>): Bool {
        return (annotation as NeedCheckCast).getOrThrow().need
    }

    public func Clone(): AnnotationBase {
        return NeedCheckCast(need)
    }

    public func ToString(): String {
        return "checkTypeCast: " + if (need) { "true" } else { "false" }
    }
}

public class DebugLocationInfoForWarning <: Annotation<DebugLocation> {
    private static let typeIndex = TypeIndex()
    private let location: DebugLocation

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        location = DebugLocation()
    }

    public init(input: DebugLocation) {
        location = input
    }

    public static func Create(): Annotation<DebugLocation> {
        return DebugLocationInfoForWarning()
    }

    public static func Create(input: DebugLocation): Annotation<DebugLocation> {
        return DebugLocationInfoForWarning(input)
    }

    public static func Extract(annotation: Annotation<DebugLocation>): DebugLocation {
        return (annotation as DebugLocationInfoForWarning).getOrThrow().location
    }

    public func Clone(): AnnotationBase {
        return DebugLocationInfoForWarning(location)
    }

    public func ToString(): String {
        return "warning " + location.ToString()
    }
}

public class GeneratedFromForIn <: Annotation<Bool> {
    private static let typeIndex = TypeIndex()
    private let value: Bool

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        value = false
    }

    public init(input: Bool) {
        value = input || !input
    }

    public static func Create(): Annotation<Bool> {
        return GeneratedFromForIn()
    }

    public static func Create(value: Bool): Annotation<Bool> {
        return GeneratedFromForIn(value)
    }

    public func Clone(): AnnotationBase {
        return GeneratedFromForIn()
    }

    public func ToString(): String {
        return "// generated-from-forin "
    }

    public static func Extract(label: GeneratedFromForIn): Bool {
        return label.value
    }

    public static func Extract(annotation: Annotation<Bool>): Bool {
        return Extract((annotation as GeneratedFromForIn).getOrThrow())
    }
}

public class LinkTypeInfo <: Annotation<BasicLinkage> {
    private static let typeIndex = TypeIndex()
    private let linkType: BasicLinkage

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        linkType = BasicLinkage.EXTERNAL
    }

    public init(linkType: BasicLinkage) {
        this.linkType = linkType
    }

    public static func Extract(info: LinkTypeInfo): BasicLinkage {
        return info.linkType
    }

    public static func Extract(info: String): BasicLinkage {
        match (info) {
            case "linkType: external" => return BasicLinkage.EXTERNAL
            case "linkType: weak_odr" => return BasicLinkage.WEAK_ODR
            case "linkType: internal" => return BasicLinkage.INTERNAL
            case "linkType: linkonce_odr" => return BasicLinkage.LINKONCE_ODR
            case "linkType: external_weak" => return BasicLinkage.EXTERNAL_WEAK
            case _ => return BasicLinkage.EXTERNAL
        }
    }

    public static func Create(): Annotation<BasicLinkage> {
        return LinkTypeInfo()
    }

    public static func Create(linkType: BasicLinkage): Annotation<BasicLinkage> {
        return LinkTypeInfo(linkType)
    }

    public func Clone(): AnnotationBase {
        return LinkTypeInfo(linkType)
    }

    public func ToString(): String {
        let linkToString = match (linkType) {
            case BasicLinkage.EXTERNAL => "external"
            case BasicLinkage.WEAK_ODR => "weak_odr"
            case BasicLinkage.INTERNAL => "internal"
            case BasicLinkage.LINKONCE_ODR => "linkonce_odr"
            case BasicLinkage.EXTERNAL_WEAK => "external_weak"
        }
        return "linkType: " + linkToString
    }

    public static func Extract(annotation: Annotation<BasicLinkage>): BasicLinkage {
        return Extract((annotation as LinkTypeInfo).getOrThrow())
    }
}

public class WrappedRawMethod <: Annotation<Option<Function>> {
    private static let typeIndex = TypeIndex()
    private let rawMethod: Option<Function>

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        rawMethod = None
    }

    public init(input: Option<Function>) {
        rawMethod = input
    }

    public static func Create(): Annotation<Option<Function>> {
        return WrappedRawMethod()
    }

    public static func Create(input: Option<Function>): Annotation<Option<Function>> {
        return WrappedRawMethod(input)
    }

    public static func Extract(annotation: Annotation<Option<Function>>): Option<Function> {
        return (annotation as WrappedRawMethod).getOrThrow().rawMethod
    }

    public func Clone(): AnnotationBase {
        return WrappedRawMethod(rawMethod)
    }

    public func ToString(): String {
        if (let Some(method) <- rawMethod) {
            if (method.GetBody().isNone()) {
                return ""
            }
            return "wrapped raw method: " + method.GetIdentifier()
        }
        return ""
    }
}

public enum SkipKind {
    | NO_SKIP | SKIP_DCE_WARNING | SKIP_FORIN_EXIT | SKIP_VIC
}

public func SkipKindIndex(kind: SkipKind): Int64 {
    return match (kind) {
        case SkipKind.NO_SKIP => 0
        case SkipKind.SKIP_DCE_WARNING => 1
        case SkipKind.SKIP_FORIN_EXIT => 2
        case SkipKind.SKIP_VIC => 3
    }
}

extend SkipKind <: Equatable<SkipKind> {
    public operator func ==(right: SkipKind): Bool {
        return SkipKindIndex(this) == SkipKindIndex(right)
    }

    public operator func !=(right: SkipKind): Bool {
        return !(this == right)
    }
}

public class SkipCheck <: Annotation<SkipKind> {
    private static let typeIndex = TypeIndex()
    private let kind: SkipKind

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        kind = SkipKind.NO_SKIP
    }

    public init(kind: SkipKind) {
        this.kind = kind
    }

    public static func Create(): Annotation<SkipKind> {
        return SkipCheck()
    }

    public static func Create(kind: SkipKind): Annotation<SkipKind> {
        return SkipCheck(kind)
    }

    public func Clone(): AnnotationBase {
        return SkipCheck(kind)
    }

    public func ToString(): String {
        return match (kind) {
            case SkipKind.SKIP_DCE_WARNING => "skip: dce warning"
            case SkipKind.SKIP_FORIN_EXIT => "skip: for-in exit"
            case SkipKind.SKIP_VIC => "skip: vic"
            case SkipKind.NO_SKIP => ""
        }
    }

    public static func Extract(label: SkipCheck): SkipKind {
        return label.kind
    }

    public static func Extract(annotation: Annotation<SkipKind>): SkipKind {
        return Extract((annotation as SkipCheck).getOrThrow())
    }
}

public class NeverOverflowInfo <: Annotation<Bool> {
    private static let typeIndex = TypeIndex()
    private let neverOverflowInfo: Bool

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        neverOverflowInfo = false
    }

    public init(value: Bool) {
        neverOverflowInfo = value
    }

    public static func Create(): Annotation<Bool> {
        return NeverOverflowInfo()
    }

    public static func Create(value: Bool): Annotation<Bool> {
        return NeverOverflowInfo(value)
    }

    public func Clone(): AnnotationBase {
        return NeverOverflowInfo(neverOverflowInfo)
    }

    public func ToString(): String {
        let str = if (neverOverflowInfo) { "true" } else { "false" }
        return "NeverOverflowInfo: " + str
    }

    public static func Extract(info: NeverOverflowInfo): Bool {
        return info.neverOverflowInfo
    }

    public static func Extract(annotation: Annotation<Bool>): Bool {
        return Extract((annotation as NeverOverflowInfo).getOrThrow())
    }
}

public class IsAutoEnvClass <: Annotation<Bool> {
    private static let typeIndex = TypeIndex()
    private let isAutoEnv: Bool

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        isAutoEnv = false
    }

    public init(input: Bool) {
        isAutoEnv = input
    }

    public static func Create(): Annotation<Bool> {
        return IsAutoEnvClass()
    }

    public static func Create(input: Bool): Annotation<Bool> {
        return IsAutoEnvClass(input)
    }

    public static func Extract(annotation: Annotation<Bool>): Bool {
        return (annotation as IsAutoEnvClass).getOrThrow().isAutoEnv
    }

    public func Clone(): AnnotationBase {
        return IsAutoEnvClass(isAutoEnv)
    }

    public func ToString(): String {
        return "IsAutoEnvClass: " + if (isAutoEnv) { "true" } else { "false" }
    }
}

public class IsCapturedClassInCC <: Annotation<Bool> {
    private static let typeIndex = TypeIndex()
    private let flag: Bool

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        flag = false
    }

    public init(input: Bool) {
        flag = input
    }

    public static func Create(): Annotation<Bool> {
        return IsCapturedClassInCC()
    }

    public static func Create(input: Bool): Annotation<Bool> {
        return IsCapturedClassInCC(input)
    }

    public static func Extract(annotation: Annotation<Bool>): Bool {
        return (annotation as IsCapturedClassInCC).getOrThrow().flag
    }

    public func Clone(): AnnotationBase {
        return IsCapturedClassInCC(flag)
    }

    public func ToString(): String {
        return "IsCapturedClassInCC: " + if (flag) { "true" } else { "false" }
    }
}

public class EnumCaseIndex <: Annotation<Option<Int64>> {
    private static let typeIndex = TypeIndex()
    private let index: Option<Int64>

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        index = None
    }

    public init(input: Option<Int64>) {
        index = input
    }

    public static func Create(): Annotation<Option<Int64>> {
        return EnumCaseIndex()
    }

    public static func Create(input: Option<Int64>): Annotation<Option<Int64>> {
        return EnumCaseIndex(input)
    }

    public func Clone(): AnnotationBase {
        return EnumCaseIndex(index)
    }

    public func ToString(): String {
        if (let Some(value) <- index) {
            return "EnumCaseIndex: " + value.toString()
        }
        return ""
    }

    public static func Extract(label: EnumCaseIndex): Option<Int64> {
        return label.index
    }

    public static func Extract(annotation: Annotation<Option<Int64>>): Option<Int64> {
        return Extract((annotation as EnumCaseIndex).getOrThrow())
    }
}

public class VirMethodOffset <: Annotation<Option<Int64>> {
    private static let typeIndex = TypeIndex()
    private let offset: Option<Int64>

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        offset = None
    }

    public init(input: Option<Int64>) {
        offset = input
    }

    public static func Create(): Annotation<Option<Int64>> {
        return VirMethodOffset()
    }

    public static func Create(input: Option<Int64>): Annotation<Option<Int64>> {
        return VirMethodOffset(input)
    }

    public static func Extract(annotation: Annotation<Option<Int64>>): Option<Int64> {
        return (annotation as VirMethodOffset).getOrThrow().offset
    }

    public func Clone(): AnnotationBase {
        return VirMethodOffset(offset)
    }

    public func ToString(): String {
        if (let Some(value) <- offset) {
            return "VirMethodOffset: " + value.toString()
        }
        return ""
    }
}

public class OverrideSrcFuncType <: Annotation<Option<FuncType>> {
    private static let typeIndex = TypeIndex()
    private let ty: Option<FuncType>

    public static func GetTypeIndex(): TypeIndex { return typeIndex }

    public init() {
        ty = None
    }

    public init(input: Option<FuncType>) {
        ty = input
    }

    public static func Create(): Annotation<Option<FuncType>> {
        return OverrideSrcFuncType()
    }

    public static func Create(input: Option<FuncType>): Annotation<Option<FuncType>> {
        return OverrideSrcFuncType(input)
    }

    public static func Extract(annotation: Annotation<Option<FuncType>>): Option<FuncType> {
        return (annotation as OverrideSrcFuncType).getOrThrow().ty
    }

    public func Clone(): AnnotationBase {
        return OverrideSrcFuncType(ty)
    }

    public func ToString(): String {
        if (let Some(value) <- ty) {
            return "OverrideSrcFuncType: " + value.ToString()
        }
        return ""
    }
}

public class AnnotationMap {
    private let annotations: HashMap<TypeIndex, AnnotationBase> = HashMap<TypeIndex, AnnotationBase>(0)
    private let annotationOrder: ArrayList<TypeIndex> = ArrayList<TypeIndex>()

    public init() {}

    public init(other: AnnotationMap) {
        CopyFrom(other)
    }

    // Set annotation T for this node, updating its value if it already exists. Annotation.h:363.
    public func Set<T, R>(value: R): Unit where T <: Annotation<R> {
        let index = T.GetTypeIndex()
        if (!annotations.contains(index)) { annotationOrder.add(index) }
        annotations[index] = T.Create(value)
    }

    public func Remove<T>(): Unit {
        let index = T.GetTypeIndex()
        annotations.remove(index)
        annotationOrder.remove(element: index)
    }

    // Get the value of the annotation T, returning the default empty value when absent. Annotation.h:370.
    public func Get<T, R>(): R where T <: Annotation<R> {
        if (let Some(annotation) <- annotations.get(T.GetTypeIndex())) {
            return T.Extract((annotation as Annotation<R>).getOrThrow())
        }
        return T.Extract(T.Create())
    }

    public func GetAnno<T, R>(): T where T <: Annotation<R> {
        let index = T.GetTypeIndex()
        if (let Some(annotation) <- annotations.get(index)) {
            return (annotation as T).getOrThrow()
        }
        let annotation = T.Create()
        annotations[index] = annotation
        annotationOrder.add(index)
        return (annotation as T).getOrThrow()
    }

    // Annotation.h:432 GetAnnos().
    public func GetAnnos(): ArrayList<(TypeIndex, AnnotationBase)> {
        let result = ArrayList<(TypeIndex, AnnotationBase)>()
        for (index in annotationOrder) { result.add((index, annotations[index])) }
        return result
    }

    public func Clear(): Unit {
        annotations.clear()
        annotationOrder.clear()
    }

    // Annotation.h:407-425 copy semantics: deep-clone each annotation.
    public func CopyFrom(other: AnnotationMap): Unit {
        if (refEq(this, other)) {
            return
        }
        annotations.clear()
        annotationOrder.clear()
        for (index in other.annotationOrder) {
            let annotation = other.annotations[index]
            annotations[index] = annotation.Clone()
            annotationOrder.add(index)
        }
    }

    // Annotation.h:403 ToString().
    public func ToString(indent!: Int64 = 0): String {
        if (annotations.isEmpty()) {
            return ""
        }
        let annotationParts = ArrayList<String>()
        for (index in annotationOrder) {
            let annotation = annotations[index]
            let text = annotation.ToString()
            if (!text.isEmpty()) {
                annotationParts.add("${IndentToString(indent)}${text}")
            }
        }
        return JoinStrings(annotationParts, ", ")
    }
}

public class CustomAnnoInstance {
    private let annoClassName: String
    private let argValues: ArrayList<String> = ArrayList<String>()
    private let loc: DebugLocation

    public init(className: String, argValues: ArrayList<String>, loc: DebugLocation) {
        annoClassName = className
        for (argValue in argValues) {
            this.argValues.add(argValue)
        }
        this.loc = loc
    }

    public func ToString(indent: Int64): String {
        var out = IndentToString(indent) + "@" + annoClassName
        let argStr = JoinStrings(argValues, ", ")
        if (!argStr.isEmpty()) {
            out += "[" + argStr + "]"
        }
        out += CommentToString(loc.ToString())
        return out
    }

    public func Dump(): Unit {
        println(ToString(0))
    }

    public func GetAnnoClassName(): String {
        return annoClassName
    }

    public func GetArgValues(): ArrayList<String> {
        let out = ArrayList<String>()
        for (argValue in argValues) {
            out.add(argValue)
        }
        return out
    }

    public func GetDebugLocation(): DebugLocation {
        return loc
    }
}

public class AnnoInfo {
    var mangledName: String = "none"
    let annoInstances: ArrayList<CustomAnnoInstance> = ArrayList<CustomAnnoInstance>()

    public init() {}

    public init(funcName: String, instances: ArrayList<CustomAnnoInstance>) {
        mangledName = funcName
        for (instance in instances) {
            annoInstances.add(instance)
        }
    }

    public func Add(annotation: String): Unit {
        annoInstances.add(CustomAnnoInstance(annotation, ArrayList<String>(), DebugLocation()))
    }

    public func Clear(): Unit {
        mangledName = "none"
        annoInstances.clear()
    }

    public func IsAvailable(): Bool {
        return mangledName != "none"
    }

    public func GetAnnotations(): ArrayList<String> {
        let out = ArrayList<String>()
        for (instance in annoInstances) {
            out.add(instance.GetAnnoClassName())
        }
        return out
    }

    public func ToString(indent!: Int64 = 0): String {
        if (!IsAvailable()) {
            return ""
        }
        let lines = ArrayList<String>()
        lines.add("${IndentToString(indent)}@AnnoFactoryFunc: ${mangledName}")
        for (instance in annoInstances) {
            lines.add(instance.ToString(indent))
        }
        return JoinStrings(lines, "\n")
    }

    public func Dump(): Unit {
        println(ToString())
    }

    public func GetAnnoFactoryFuncMangledName(): String {
        return mangledName
    }

    public func GetCustomAnnoInstances(): ArrayList<CustomAnnoInstance> {
        let out = ArrayList<CustomAnnoInstance>()
        for (instance in annoInstances) {
            out.add(instance)
        }
        return out
    }
}
