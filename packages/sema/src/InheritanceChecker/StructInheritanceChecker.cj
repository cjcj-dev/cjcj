package cjcj::sema.InheritanceChecker

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.{DiagnosticEngine, DiagArgument, DiagKind, DiagKindRefactor, MakeRange, SubDiagnostic}
import cjcj::basic.Range as BasicRange
import cjcj::modules.{GetPackageRelation, PackageRelation, SemaImportManager}
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::sema.*
import cjcj::sema.NativeFFI.{GetAnnotation, GetForeignNameAnnotation}
import cjcj::sema.Test.TestManager

private func DeclRange(decl: Decl): BasicRange {
    return MakeRange(decl.begin, decl.end)
}

private func DeclIdentifierRange(decl: Decl): BasicRange {
    if (!decl.identifier.Empty() && !decl.identifier.ZeroPos()) {
        return MakeRange(decl.identifier.Begin(), decl.identifier.End())
    }
    return DeclRange(decl)
}

private func NodeConflictRange(node: Node): BasicRange {
    if (let Some(decl) <- (node as Decl)) {
        return DeclIdentifierRange(decl)
    }
    return MakeRange(node.begin, node.end)
}

private func DeclKindText(decl: Decl): String {
    return DeclKindToString(decl)
}

private func HasExtend(values: ArrayList<ExtendDecl>, decl: ExtendDecl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func AddExtendUniqueByPosition(values: ArrayList<ExtendDecl>, decl: ExtendDecl): Unit {
    if (HasExtend(values, decl)) {
        return
    }
    var idx: Int64 = 0
    while (idx < values.size) {
        if (InheritanceDeclLessByPosition(decl, values[idx])) {
            values.add(decl, at: idx)
            return
        }
        idx++
    }
    values.add(decl)
}

private func AddInheritableUniqueByPosition(values: ArrayList<InheritableDecl>, decl: InheritableDecl): Unit {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return
        }
    }
    var idx: Int64 = 0
    while (idx < values.size) {
        if (InheritanceDeclLessByPosition(decl, values[idx])) {
            values.add(decl, at: idx)
            return
        }
        idx++
    }
    values.add(decl)
}

private func AddTyUniqueByName(values: ArrayList<Ty>, ty: Ty): Unit {
    for (value in values) {
        if (SameTy(value, ty)) {
            return
        }
    }
    var idx: Int64 = 0
    while (idx < values.size) {
        if (CompTyByNames(Some(ty), Some(values[idx]))) {
            values.add(ty, at: idx)
            return
        }
        idx++
    }
    values.add(ty)
}

private func AddTyUniqueByNameSkipping(values: ArrayList<Ty>, ty: Ty, skipTy: Option<Ty>): Unit {
    if (SameTy(Some(ty), skipTy)) {
        return
    }
    AddTyUniqueByName(values, ty)
}

private func StringifyInconsistentTypes(inconsistentTypes: TySet, childTy!: Option<Ty> = None): String {
    let sortedTys = ArrayList<Ty>()
    for (ty in inconsistentTypes.values) {
        AddTyUniqueByNameSkipping(sortedTys, ty, childTy)
    }
    return "'" + Ty.GetTypesToStableStr(sortedTys, "', '") + "'"
}

private func IsAstVisibleInRelation(node: Node, relation: PackageRelation): Bool {
    return node.TestAttr(Attribute.PUBLIC) || relation == PackageRelation.SAME_PACKAGE ||
        (node.TestAttr(Attribute.PROTECTED) && relation != PackageRelation.NONE) ||
        (node.TestAttr(Attribute.INTERNAL) &&
            (relation == PackageRelation.CHILD || relation == PackageRelation.SAME_PACKAGE))
}

private func IsInvisibleMember(member: Decl, currentPkg: String): Bool {
    if (member.TestAttr(Attribute.PRIVATE)) {
        return true
    }
    let relation = GetPackageRelation(currentPkg, member.fullPackageName)
    return !IsAstVisibleInRelation(member, relation) && !member.TestAttr(Attribute.PROTECTED)
}

private func RemoveMembersShouldNotInherit(members: MemberMap): Unit {
    var idx: Int64 = 0
    while (idx < members.entries.size) {
        if (let Some(decl) <- members.entries[idx].signature.decl) {
            if (decl.TestAttr(Attribute.PRIVATE)) {
                members.Remove(idx)
                continue
            }
        }
        idx++
    }
}

private func RemoveInvisibleMember(members: MemberMap, currentPkg: String): Unit {
    var idx: Int64 = 0
    while (idx < members.entries.size) {
        if (let Some(decl) <- members.entries[idx].signature.decl) {
            if (IsInvisibleMember(decl, currentPkg)) {
                members.Remove(idx)
                continue
            }
        }
        idx++
    }
}

private func AreFuncParameterNameIdentical(parent: FuncDecl, child: FuncDecl): Bool {
    if (let Some(parentBody) <- parent.funcBody) {
        if (let Some(childBody) <- child.funcBody) {
            if (parentBody.paramLists.isEmpty() || childBody.paramLists.isEmpty()) {
                return true
            }
            let parentParams = parentBody.paramLists[0].params
            let childParams = childBody.paramLists[0].params
            if (parentParams.size != childParams.size) {
                return false
            }
            for (idx in 0..parentParams.size) {
                if (parentParams[idx].isNamedParam != childParams[idx].isNamedParam) {
                    return false
                }
                if (parentParams[idx].isNamedParam && parentParams[idx].identifier != childParams[idx].identifier) {
                    return false
                }
            }
        }
    }
    return true
}

private func HasParamListForParameterNameCheck(funcDecl: FuncDecl): Bool {
    if (let Some(body) <- funcDecl.funcBody) {
        return !body.paramLists.isEmpty()
    }
    return false
}

private func ParamIdentifierRange(param: FuncParam): BasicRange {
    return MakeRange(param.GetIdentifierPos(), param.identifier.Val())
}

private func DiagnoseParameterName(diag: DiagnosticEngine, parent: FuncDecl, child: FuncDecl): Unit {
    // C++: StructInheritanceChecker.cpp:97-123 uses the node-and-range diagnostic overload.
    let builder = DiagnoseRefactor(
        diag,
        DiagKindRefactor.sema_param_named_mismatched,
        child,
        DeclIdentifierRange(child)
    )
    if (let Some(parentBody) <- parent.funcBody) {
        if (let Some(childBody) <- child.funcBody) {
            if (!parentBody.paramLists.isEmpty() && !childBody.paramLists.isEmpty()) {
                let parentParams = parentBody.paramLists[0].params
                let childParams = childBody.paramLists[0].params
                if (parentParams.size == childParams.size) {
                    for (idx in 0..parentParams.size) {
                        let parentParam = parentParams[idx]
                        let childParam = childParams[idx]
                        if (!parentParam.isNamedParam && childParam.isNamedParam) {
                            builder.AddHint(
                                ParamIdentifierRange(childParam),
                                arguments: [
                                    "this named parameter conflicts with the corresponding positional parameter in the supertype"
                                ]
                            )
                        } else if (parentParam.isNamedParam && !childParam.isNamedParam) {
                            builder.AddHint(
                                ParamIdentifierRange(childParam),
                                arguments: [
                                    "this positional parameter conflicts with the corresponding named parameter in the supertype"
                                ]
                            )
                        } else if (parentParam.isNamedParam && childParam.isNamedParam &&
                            parentParam.identifier != childParam.identifier) {
                            builder.AddHint(
                                ParamIdentifierRange(childParam),
                                arguments: [
                                    "the corresponding parameter in the supertype is named '" +
                                        parentParam.identifier.Val() + "'"
                                ]
                            )
                        }
                    }
                }
            }
        }
    }
    builder.AddNote(DeclIdentifierRange(parent), "the corresponding function of the supertype is")
    // C++: DiagnosticEngine.cpp:314-338 emits DiagnosticBuilder on destruction.
    builder.Emit()
}

private func VisibilityToString(decl: Decl): String {
    if (decl.TestAttr(Attribute.PUBLIC)) {
        return "public"
    }
    if (decl.TestAttr(Attribute.PROTECTED)) {
        return "protected"
    }
    if (decl.TestAttr(Attribute.PRIVATE)) {
        return "private"
    }
    return "internal"
}

private func DiagnoseWeakVisibility(
    diag: DiagnosticEngine,
    parent: Decl,
    child: Decl,
    diagNode: Decl
): Unit {
    let parentRange = DeclIdentifierRange(parent)
    let childRange = DeclIdentifierRange(child)
    let range = MakeRangeForDeclIdentifier(diagNode)
    let childHint = "the visibility of the deriving '" + child.identifier.Val() + "' is '" + VisibilityToString(child) + "'"
    let builder = diag.DiagnoseRefactor(DiagKindRefactor.sema_weak_visibility, range)
    if (let Some(macroCall) <- diagNode.curMacroCall) {
        if (let Some(invocation) <- macroCall.GetConstInvocation()) {
            diag.AddMacroCallNote(builder.diagnostic, invocation.macroCallDiagInfo, range.begin)
        }
    }
    if (SameDecl(child, diagNode)) {
        builder.AddMainHintArguments([childHint])
    } else {
        builder.AddMainHintArguments(["'" + child.identifier.Val() + "' is inherited"])
        let childNote = SubDiagnostic(childRange, "the deriving '" + child.identifier.Val() + "' is defined here")
        childNote.AddMainHint(childRange, childHint)
        builder.AddNote(childNote)
    }
    let parentNote = SubDiagnostic(
        parentRange,
        "the visibility of the base '" + parent.identifier.Val() + "' is '" + VisibilityToString(parent) + "'"
    )
    if (let Some(parentOuter) <- parent.outerDecl) {
        if (parentOuter.astKind == ASTKind.INTERFACE_DECL) {
            parentNote.AddMainHint(parentRange, "the base '" + parent.identifier.Val() + "' is in 'interface'")
        }
    }
    builder.AddNote(parentNote)
    builder.Emit()
}

private func HasCommonDecl(decls: ArrayList<ClassLikeDecl>): Bool {
    for (decl in decls) {
        if (decl.TestAttr(Attribute.COMMON)) {
            return true
        }
    }
    return false
}

private func NeedRecheck(decl: InheritableDecl): Bool {
    let superDecls = decl.GetAllSuperDecls()
    let extendedSuperDecls = ArrayList<ClassLikeDecl>()
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(extendedTarget) <- extendedType.GetTarget()) {
                let realTarget = GetRealTarget(extendedTarget)
                if (realTarget.TestAttr(Attribute.SPECIFIC)) {
                    return true
                }
                if (let Some(targetInheritable) <- (realTarget as InheritableDecl)) {
                    for (superDecl in targetInheritable.GetAllSuperDecls()) {
                        extendedSuperDecls.add(superDecl)
                    }
                }
            }
        }
    }
    return HasCommonDecl(superDecls) || HasCommonDecl(extendedSuperDecls)
}

private func NeedCheck(node: Node): Bool {
    if (!node.IsNominalDecl()) {
        return false
    }
    if (node.TestAttr(Attribute.IMPORTED)) {
        return false
    }
    if (node.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
        return false
    }
    if (node.TestAttr(Attribute.FROM_COMMON_PART)) {
        if (node.TestAttr(Attribute.COMMON)) {
            return false
        }
        if (let Some(inheritable) <- (node as InheritableDecl)) {
            return NeedRecheck(inheritable)
        }
        return false
    }
    return true
}

private func InheritedDisplayName(decl: Decl): String {
    if (let Some(ty) <- decl.GetTy()) {
        if (ty.IsNominal()) {
            return ty.name
        }
        return ty.String()
    }
    return decl.identifier.Val()
}

private func InheritedTypeString(decl: Decl): String {
    if (let Some(ty) <- decl.GetTy()) {
        return ty.String()
    }
    return InheritedDisplayName(decl)
}

private func CountByDecl(members: ArrayList<MemberSignature>, decl: Decl): Int64 {
    var count: Int64 = 0
    for (member in members) {
        if (let Some(memberDecl) <- member.decl) {
            if (SameDecl(memberDecl, decl)) {
                count++
            }
        }
    }
    return count
}

private func UnimplementedIdentifier(member: MemberSignature): String {
    if (let Some(memberDecl) <- member.decl) {
        let name = "'" + memberDecl.identifier.Val() + "'"
        if (let Some(memberTy) <- member.ty) {
            return name + ", of type: " + memberTy.String()
        }
        return name
    }
    return "''"
}

private func GetAnnoValue(annotation: Annotation): String {
    let expr = annotation.args[0].expr.getOrThrow()
    return (expr as LitConstExpr).getOrThrow().stringValue
}

private func DiagConflictingForeignName(
    diag: DiagnosticEngine,
    declWithAnno: Decl,
    otherDecl: Decl,
    checkingDecl: Decl
): Unit {
    let annotation = GetForeignNameAnnotation(declWithAnno).getOrThrow()
    let builder = if (!annotation.TestAttr(Attribute.COMPILER_ADD)) {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_conflicting_annotation,
            MakeRange(annotation.GetBegin(), declWithAnno.identifier.End()),
            arguments: [declWithAnno.identifier.Val(), annotation.identifier.Val()]
        )
    } else {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_conflicting_derived_annotation,
            DeclIdentifierRange(declWithAnno),
            arguments: [declWithAnno.identifier.Val(), annotation.identifier.Val(), GetAnnoValue(annotation)]
        )
    }

    let otherAnnotation = GetForeignNameAnnotation(otherDecl)
    if (let Some(otherValue) <- otherAnnotation) {
        if (!otherValue.TestAttr(Attribute.COMPILER_ADD)) {
            builder.AddNote(
                MakeRange(otherValue.GetBegin(), otherDecl.identifier.End()),
                "Other declaration '" + otherDecl.identifier.Val() + "' has a different @ForeignName"
            )
        } else {
            builder.AddNote(
                DeclIdentifierRange(otherDecl),
                "Other declaration '" + otherDecl.identifier.Val() +
                    "' has a different derived @ForeignName '" + GetAnnoValue(otherValue) + "'"
            )
        }
    } else {
        builder.AddNote(
            DeclIdentifierRange(otherDecl),
            "Other declaration '" + otherDecl.identifier.Val() + "' doesn't have a @ForeignName"
        )
    }

    builder.AddNote(
        DeclIdentifierRange(checkingDecl),
        "While checking declaration '" + checkingDecl.identifier.Val() + "'"
    )
}

private func NeedCheck(parent: MemberSignature, child: MemberSignature): Bool {
    let parentDecl = parent.decl.getOrThrow()
    let childDecl = child.decl.getOrThrow()
    if (childDecl.outerDecl.getOrThrow().TestAttr(Attribute.IMPORTED)) {
        return false
    }
    if (!parentDecl.IsFuncOrProp()) {
        return false
    }
    if (!parentDecl.outerDecl.getOrThrow().TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
        return false
    }
    if (!childDecl.outerDecl.getOrThrow().TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
        return false
    }
    if (SameDecl(parentDecl.outerDecl.getOrThrow(), childDecl.outerDecl.getOrThrow())) {
        return false
    }
    return true
}

private func DiagConflictingAnnotation(
    diag: DiagnosticEngine,
    declWithAnno: Decl,
    otherDecl: Decl,
    checkingDecl: Decl,
    annotationKind: AstAnnotationKind
): Unit {
    let annotation = GetAnnotation(declWithAnno, annotationKind).getOrThrow()
    let builder = if (!annotation.TestAttr(Attribute.COMPILER_ADD)) {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_conflicting_annotation,
            MakeRange(annotation.GetBegin(), declWithAnno.identifier.End()),
            arguments: [declWithAnno.identifier.Val(), annotation.identifier.Val()]
        )
    } else {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_conflicting_derived_annotation,
            DeclIdentifierRange(declWithAnno),
            arguments: [declWithAnno.identifier.Val(), annotation.identifier.Val(), GetAnnoValue(annotation)]
        )
    }

    let otherAnnotation = GetForeignNameAnnotation(otherDecl)
    if (let Some(otherValue) <- otherAnnotation) {
        if (!otherValue.TestAttr(Attribute.COMPILER_ADD)) {
            builder.AddNote(
                MakeRange(otherValue.GetBegin(), otherDecl.identifier.End()),
                "Other declaration '" + otherDecl.identifier.Val() + "' has a different @" +
                    annotation.identifier.Val()
            )
        } else {
            builder.AddNote(
                DeclIdentifierRange(otherDecl),
                "Other declaration '" + otherDecl.identifier.Val() + "' has a different derived @" +
                    annotation.identifier.Val() + " '" + GetAnnoValue(otherValue) + "'"
            )
        }
    } else {
        builder.AddNote(
            DeclIdentifierRange(otherDecl),
            "Other declaration '" + otherDecl.identifier.Val() + "' doesn't have a @" + annotation.identifier.Val()
        )
    }

    builder.AddNote(
        DeclIdentifierRange(checkingDecl),
        "While checking declaration '" + checkingDecl.identifier.Val() + "'"
    )
}

private func NeedCheckForeignName(parent: MemberSignature, child: MemberSignature): Bool {
    let parentDecl = parent.decl.getOrThrow()
    let childDecl = child.decl.getOrThrow()
    if (childDecl.outerDecl.getOrThrow().TestAttr(Attribute.IMPORTED)) {
        return false
    }
    if (!parentDecl.IsFuncOrProp()) {
        return false
    }
    if (!parentDecl.outerDecl.getOrThrow().TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SUBTYPE)) {
        return false
    }
    if (!childDecl.outerDecl.getOrThrow().TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SUBTYPE)) {
        return false
    }
    if (SameDecl(parentDecl.outerDecl.getOrThrow(), childDecl.outerDecl.getOrThrow())) {
        return false
    }
    return true
}

private func IsForeignNameLikeAnnotation(annotationKind: AstAnnotationKind): Bool {
    return annotationKind == AstAnnotationKind.FOREIGN_NAME ||
        annotationKind == AstAnnotationKind.FOREIGN_GETTER_NAME ||
        annotationKind == AstAnnotationKind.FOREIGN_SETTER_NAME
}

public class StructInheritanceChecker {
    public let diag: DiagnosticEngine
    public let typeManager: TypeManager
    public let pkg: Package
    public let importManager: SemaImportManager
    public let opts: OptionGlobalOptions

    private let structInheritedMembers: HashMap<Node, MemberMap> = HashMap<Node, MemberMap>()
    private let checkingDecls: ArrayList<InheritableDecl> = ArrayList<InheritableDecl>()
    private let instantiatedKeys: HashSet<String> = HashSet<String>()
    private let instantiatedMemberDiagnostics: ArrayList<InstantiatedMemberDiagnosticRecord> =
        ArrayList<InstantiatedMemberDiagnosticRecord>()
    private let instantiatedTyCaches: ArrayList<InstantiatedTyCacheRecord> = ArrayList<InstantiatedTyCacheRecord>()
    private let instantiationTriggers: ArrayList<InstantiationTriggerInfo> = ArrayList<InstantiationTriggerInfo>()
    private let instantiationTypeMaps: ArrayList<TypeSubst> = ArrayList<TypeSubst>()
    private var infiniteInstantiationOccurred: Bool = false

    public init(
        diag: DiagnosticEngine,
        typeManager: TypeManager,
        pkg: Package,
        importManager: SemaImportManager,
        opts!: OptionGlobalOptions
    ) {
        this.diag = diag
        this.typeManager = typeManager
        this.pkg = pkg
        this.importManager = importManager
        this.opts = opts
    }

    public func IsExtendVisibleInCurpkg(extendDecl: ExtendDecl): Bool {
        if (pkg.files.isEmpty()) {
            return false
        }
        return importManager.IsExtendAccessible(pkg.files[0], extendDecl, None)
    }

    @When[backend == "cjnative"]
    public func Check(): Unit {
        if (pkg.TestAnyAttr(Attribute.IMPORTED, Attribute.TOOL_ADD)) {
            return
        }
        let nominalDecls = ArrayList<InheritableDecl>()
        let extendDecls = ArrayList<ExtendDecl>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!NeedCheck(node)) {
                return VisitAction.WALK_CHILDREN
            }
            if (node.TestAttr(Attribute.IS_BROKEN) || !Ty.IsTyCorrect(node.GetTy())) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(inheritable) <- (node as InheritableDecl)) {
                if (let Some(extendDecl) <- (node as ExtendDecl)) {
                    if (IsExtendVisibleInCurpkg(extendDecl)) {
                        extendDecls.add(extendDecl)
                    }
                } else {
                    nominalDecls.add(inheritable)
                }
            }
            return VisitAction.SKIP_CHILDREN
        })
        walker.Walk()
        for (decl in GetAllNeedCheckExtended()) {
            if (!decl.TestAttr(Attribute.IS_BROKEN) && Ty.IsTyCorrect(decl.GetTy()) && IsExtendVisibleInCurpkg(decl)) {
                extendDecls.add(decl)
            }
        }
        for (decl in nominalDecls) {
            CheckMembersWithInheritedDecls(decl)
        }
        for (decl in extendDecls) {
            CheckMembersWithInheritedDecls(decl)
        }
        CheckAllUpperBoundsConfliction()
        CheckInstDupFuncsInNominalDecls(this)
    }

    @When[backend != "cjnative"]
    public func Check(): Unit {
        if (pkg.TestAnyAttr(Attribute.IMPORTED, Attribute.TOOL_ADD)) {
            return
        }
        let nominalDecls = ArrayList<InheritableDecl>()
        let extendDecls = ArrayList<ExtendDecl>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!NeedCheck(node)) {
                return VisitAction.WALK_CHILDREN
            }
            if (node.TestAttr(Attribute.IS_BROKEN) || !Ty.IsTyCorrect(node.GetTy())) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(inheritable) <- (node as InheritableDecl)) {
                if (let Some(extendDecl) <- (node as ExtendDecl)) {
                    if (IsExtendVisibleInCurpkg(extendDecl)) {
                        extendDecls.add(extendDecl)
                    }
                } else {
                    nominalDecls.add(inheritable)
                }
            }
            return VisitAction.SKIP_CHILDREN
        })
        walker.Walk()
        for (decl in nominalDecls) {
            CheckMembersWithInheritedDecls(decl)
        }
        for (decl in extendDecls) {
            CheckMembersWithInheritedDecls(decl)
        }
        CheckAllUpperBoundsConfliction()
        CheckInstDupFuncsInNominalDecls(this)
    }

    public func MoveStructInheritedMembers(): HashMap<Node, MemberMap> {
        let out = HashMap<Node, MemberMap>()
        for (decl in structInheritedMembers.keys()) {
            if (let Some(members) <- structInheritedMembers.get(decl)) {
                out[decl] = members.Clone()
            }
        }
        structInheritedMembers.clear()
        return out
    }

    public func HasInstantiatedKey(key: String): Bool {
        return instantiatedKeys.contains(key)
    }

    public func AddInstantiatedKey(key: String): Unit {
        instantiatedKeys.add(key)
    }

    private func FindInstantiatedMemberDiagnosticRecord(key: String): Option<InstantiatedMemberDiagnosticRecord> {
        for (record in instantiatedMemberDiagnostics) {
            if (record.key == key) {
                return record
            }
        }
        return None
    }

    public func ReplayInstantiatedMemberDiagnostics(key: String): Unit {
        if (let Some(record) <- FindInstantiatedMemberDiagnosticRecord(key)) {
            for (pair in record.pairs) {
                DiagnoseForInstantiatedMember(pair.parent, pair.child)
            }
        }
    }

    public func RecordInstantiatedMemberDiagnostic(
        key: String,
        parent: MemberSignature,
        child: MemberSignature
    ): Unit {
        if (let Some(record) <- FindInstantiatedMemberDiagnosticRecord(key)) {
            record.pairs.add(InstantiatedMemberDiagnosticPair(parent, child))
            return
        }
        let record = InstantiatedMemberDiagnosticRecord(key)
        record.pairs.add(InstantiatedMemberDiagnosticPair(parent, child))
        instantiatedMemberDiagnostics.add(record)
    }

    private func FindInstantiatedTyCacheRecord(key: String): Option<InstantiatedTyCacheRecord> {
        for (record in instantiatedTyCaches) {
            if (record.key == key) {
                return record
            }
        }
        return None
    }

    public func GetCachedInstantiatedTy(key: String, ty: Ty, typeMapping: TypeSubst): Ty {
        if (let Some(record) <- FindInstantiatedTyCacheRecord(key)) {
            for (entry in record.entries) {
                if (SameTy(entry.source, ty)) {
                    return entry.instantiated
                }
            }
            let instantiatedTy = typeManager.GetInstantiatedTy(ty, typeMapping)
            record.entries.add(InstantiatedTyCacheEntry(ty, instantiatedTy))
            return instantiatedTy
        }
        let record = InstantiatedTyCacheRecord(key)
        let instantiatedTy = typeManager.GetInstantiatedTy(ty, typeMapping)
        record.entries.add(InstantiatedTyCacheEntry(ty, instantiatedTy))
        instantiatedTyCaches.add(record)
        return instantiatedTy
    }

    public func HasInstantiationTrigger(): Bool {
        return !instantiationTriggers.isEmpty()
    }

    public func PushInstantiationTrigger(node: Node, decl: Decl, instTys: ArrayList<Ty>): Unit {
        instantiationTriggers.add(InstantiationTriggerInfo(node, decl, instTys))
    }

    public func PopInstantiationTrigger(): Unit {
        if (!instantiationTriggers.isEmpty()) {
            instantiationTriggers.remove(at: instantiationTriggers.size - 1)
        }
    }

    public func CurrentInstantiationTrigger(): Option<InstantiationTriggerInfo> {
        if (instantiationTriggers.isEmpty()) {
            return None
        }
        return instantiationTriggers[instantiationTriggers.size - 1]
    }

    public func HasInstantiationTypeMap(): Bool {
        return !instantiationTypeMaps.isEmpty()
    }

    public func PushInstantiationTypeMap(typeMapping: TypeSubst): Unit {
        instantiationTypeMaps.add(typeMapping.Clone())
    }

    public func PopInstantiationTypeMap(): Unit {
        if (!instantiationTypeMaps.isEmpty()) {
            instantiationTypeMaps.remove(at: instantiationTypeMaps.size - 1)
        }
    }

    public func CurrentInstantiationTypeMap(): Option<TypeSubst> {
        if (instantiationTypeMaps.isEmpty()) {
            return None
        }
        return instantiationTypeMaps[instantiationTypeMaps.size - 1]
    }

    public func HasInfiniteInstantiationOccurred(): Bool {
        return infiniteInstantiationOccurred
    }

    public func MarkInfiniteInstantiationOccurred(): Unit {
        infiniteInstantiationOccurred = true
    }

    public func CheckInstWithCStructTypeArg(node: Node): Unit {
        CheckInstWithCStructTypeArgImpl(this, node)
    }

    public func DiagnoseForInstantiatedMember(parent: MemberSignature, child: MemberSignature): Unit {
        DiagnoseForInstantiatedMemberImpl(this, parent, child)
    }

    public func GetStoredMembersForDecl(decl: InheritableDecl): MemberMap {
        if (let Some(members) <- structInheritedMembers.get(decl)) {
            return members
        }
        return MemberMap()
    }

    public func CheckMembersWithInheritedDecls(decl: InheritableDecl): Unit {
        if (structInheritedMembers.contains(decl)) {
            return
        }
        checkingDecls.add(decl)
        let interfaceMembers = GetAndCheckInheritedInterfaces(decl)
        let instanceMembers = GetAndCheckInheritedMembers(decl)
        let visiblePair = GetVisibleExtendMembersForExtend(decl)
        let visibleExtendMembers = visiblePair[0]
        let invisibleMembers = visiblePair[1]
        if (let Some(declTy) <- decl.GetTy()) {
            MergeInheritedMembers(visibleExtendMembers, instanceMembers, declTy)
        }
        for (entry in interfaceMembers.entries) {
            CheckExtendExportDependence(decl, entry.signature, visibleExtendMembers)
        }
        for (member in decl.GetMemberDecls()) {
            if (!Ty.IsTyCorrect(member.GetTy()) || (let None <- member.outerDecl) ||
                member.TestAttr(Attribute.CONSTRUCTOR)) {
                continue
            }
            let memberSig = MemberSignature(
                decl: member,
                ty: member.GetTy(),
                structTy: decl.GetTy(),
                extendDecl: None
            )
            for (bounds in GetAllGenericUpperBounds(typeManager, member)) {
                memberSig.upperBounds.add(bounds)
            }
            for (parent in visibleExtendMembers.Get(member.identifier.Val())) {
                DiagnoseForInheritedMember(parent, memberSig)
            }
            for (parent in invisibleMembers.Get(member.identifier.Val())) {
                DiagnoseForInheritedMember(parent, memberSig)
            }
            let updatedSig = UpdateInheritedMemberIfNeeded(visibleExtendMembers, memberSig)
            let _ = updatedSig
        }
        for (entry in interfaceMembers.entries) {
            entry.signature.isInheritedInterface = true
            DiagnoseForInheritedInterfaces(entry.signature, visibleExtendMembers)
        }
        if (let Some(declTy) <- decl.GetTy()) {
            MergeInheritedMembers(interfaceMembers, visibleExtendMembers, declTy)
        }
        for (entry in interfaceMembers.entries) {
            DiagnoseForOverriddenMember(entry.signature)
        }
        DiagnoseForUnimplementedInterfaces(interfaceMembers, decl)
        RemoveMembersShouldNotInherit(interfaceMembers)
        checkingDecls.remove(at: checkingDecls.size - 1)
        for (entry in interfaceMembers.entries) {
            entry.signature.isInheritedInterface = false
            entry.signature.extendDecl = None
        }
        structInheritedMembers[decl] = interfaceMembers
    }

    private func GetAndCheckInheritedInterfaces(decl: InheritableDecl): MemberMap {
        let interfaceTys = ArrayList<Ty>()
        for (typeNode in decl.inheritedTypes) {
            if (let Some(inheritedTy) <- typeNode.GetTy()) {
                if (let Some(baseDecl) <- Ty.GetInheritableDeclPtrOfTy(inheritedTy)) {
                    if (baseDecl.astKind == ASTKind.INTERFACE_DECL && !baseDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                        CheckMembersWithInheritedDecls(baseDecl)
                        AddTyUniqueByName(interfaceTys, inheritedTy)
                    }
                }
            }
        }
        let members = MemberMap()
        for (interfaceTy in interfaceTys) {
            if (let Some(interfaceDecl) <- Ty.GetInheritableDeclPtrOfTy(interfaceTy)) {
                MergeInheritedMembers(members, GetStoredMembersForDecl(interfaceDecl), interfaceTy, inheritedInterfaces: true)
            }
        }
        DiagnoseForConflictInheritance(decl, members)
        return members
    }

    private func GetInheritedSuperMembers(
        decl: InheritableDecl,
        baseTy: Ty,
        curFile: File,
        ignoreExtends!: Bool = false
    ): MemberMap {
        let members = MemberMap()
        MergeInheritedMembers(members, GetStoredMembersForDecl(decl), baseTy)
        if (let Some(currentPkg) <- curFile.curPackage) {
            RemoveInvisibleMember(members, currentPkg.fullPackageName)
        }
        if (ignoreExtends) {
            return members
        }
        for (extendDecl in CollectExtendsForDecl(decl, baseTy)) {
            if ((let None <- extendDecl.extendedType) || !Ty.IsTyCorrect(extendDecl.extendedType.getOrThrow().GetTy())) {
                continue
            }
            if (!importManager.IsExtendAccessible(curFile, extendDecl, None)) {
                continue
            }
            CheckMembersWithInheritedDecls(extendDecl)
            let extendMembers = GetStoredMembersForDecl(extendDecl)
            if (let Some(currentPkg) <- curFile.curPackage) {
                RemoveInvisibleMember(members, currentPkg.fullPackageName)
            }
            MergeInheritedMembers(members, extendMembers, baseTy)
        }
        return members
    }

    private func GetAndCheckInheritedMembers(decl: InheritableDecl): MemberMap {
        if (!Ty.IsTyCorrect(decl.GetTy())) {
            return MemberMap()
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(superDecl) <- classDecl.GetSuperClassDecl()) {
                if (let Some(declTy) <- classDecl.GetTy()) {
                    if (let Some(classTy) <- (declTy as ClassTy)) {
                        if (let Some(superTy) <- classTy.GetSuperClassTy()) {
                            return GetInheritedMembersFromBase(decl, superDecl, superTy)
                        }
                    }
                }
            }
        } else if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    if (let Some(baseDecl) <- Ty.GetInheritableDeclPtrOfTy(extendedTy)) {
                        return GetInheritedMembersFromBase(decl, baseDecl, extendedTy)
                    }
                }
            }
        }
        return MemberMap()
    }

    private func GetInheritedMembersFromBase(
        decl: InheritableDecl,
        baseDecl: InheritableDecl,
        baseTy: Ty
    ): MemberMap {
        var effectiveBaseDecl = baseDecl
        if (let Some(specificDecl) <- baseDecl.specificImplementation) {
            if (let Some(specificInheritable) <- (specificDecl as InheritableDecl)) {
                effectiveBaseDecl = specificInheritable
            }
        }
        if (effectiveBaseDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
            return MemberMap()
        }
        CheckMembersWithInheritedDecls(effectiveBaseDecl)
        if (let Some(curFile) <- decl.curFile) {
            return GetInheritedSuperMembers(
                effectiveBaseDecl,
                baseTy,
                curFile,
                ignoreExtends: decl.astKind == ASTKind.EXTEND_DECL
            )
        }
        return MemberMap()
    }

    private func CollectExtendsForDecl(decl: InheritableDecl, baseTy: Ty): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        for (extendDecl in typeManager.GetDeclExtends(decl)) {
            AddExtendUniqueByPosition(out, extendDecl)
        }
        for (extendDecl in typeManager.GetAllExtendsByTy(baseTy)) {
            AddExtendUniqueByPosition(out, extendDecl)
        }
        return out
    }

    private func AllExtendsImportedFromSamePackage(extends: ArrayList<ExtendDecl>): Bool {
        if (extends.isEmpty()) {
            return true
        }
        var packageName: Option<String> = None
        for (extendDecl in extends) {
            if (!extendDecl.TestAttr(Attribute.IMPORTED)) {
                return false
            }
            if (let Some(existing) <- packageName) {
                if (existing != extendDecl.fullPackageName) {
                    return false
                }
            } else {
                packageName = extendDecl.fullPackageName
            }
        }
        return true
    }

    private func CollectPublicNeedCheckExtends(extends: ArrayList<ExtendDecl>, out: ArrayList<ExtendDecl>): Unit {
        if (AllExtendsImportedFromSamePackage(extends)) {
            return
        }
        for (extendDecl in extends) {
            if (extendDecl.TestAttr(Attribute.PUBLIC)) {
                AddExtendUniqueByPosition(out, extendDecl)
            }
        }
    }

    @When[backend == "cjnative"]
    private func GetAllNeedCheckExtended(): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        let extendedDecls = ArrayList<InheritableDecl>()
        for (decl in typeManager.GetAllExtendedDecls()) {
            AddInheritableUniqueByPosition(extendedDecls, decl)
        }
        for (decl in extendedDecls) {
            if (decl.TestAttr(Attribute.IMPORTED) && decl.TestAttr(Attribute.PUBLIC)) {
                CollectPublicNeedCheckExtends(typeManager.GetDeclExtends(decl), out)
            }
        }

        let extendedBuiltInTys = ArrayList<Ty>()
        for (ty in typeManager.GetAllExtendedBuiltIn().values) {
            AddTyUniqueByName(extendedBuiltInTys, ty)
        }
        for (ty in extendedBuiltInTys) {
            CollectPublicNeedCheckExtends(typeManager.GetBuiltinTyExtends(ty), out)
        }
        return out
    }

    private func CollectExtendByInterfaceInherit(
        otherExtends: ArrayList<ExtendDecl>,
        curDecl: ExtendDecl
    ): ArrayList<ExtendDecl> {
        let ordered = ArrayList<ExtendDecl>()
        let extendedDecl = GetOrderingExtendedDecl(curDecl)
        for (otherExtend in otherExtends) {
            if (SameDecl(otherExtend, curDecl)) {
                continue
            }
            let areAllFromOtherPkg = otherExtend.fullPackageName != pkg.fullPackageName &&
                curDecl.fullPackageName != pkg.fullPackageName && IsExtendVisibleInCurpkg(otherExtend)
            if (otherExtend.fullPackageName != curDecl.fullPackageName && !areAllFromOtherPkg) {
                if (let Some(curFile) <- curDecl.curFile) {
                    if (importManager.IsExtendAccessible(curFile, otherExtend, None)) {
                        AddExtendUniqueByPosition(ordered, otherExtend)
                    }
                }
                continue
            }
            let skipExtend = DeterminingSkipExtendByInheritanceRelationship(curDecl, otherExtend, extendedDecl)
            if ((let None <- skipExtend) || !skipExtend.getOrThrow()) {
                AddExtendUniqueByPosition(ordered, otherExtend)
            }
        }
        return ordered
    }

    private func GetOrderingExtendedDecl(curDecl: ExtendDecl): Option<Decl> {
        if (let Some(curTy) <- curDecl.GetTy()) {
            if (let Some(decl) <- Ty.GetDeclPtrOfTy(curTy)) {
                return Some(decl)
            }
        }
        if (let Some(extendedType) <- curDecl.extendedType) {
            if (let Some(refType) <- (extendedType as RefType)) {
                if (let Some(target) <- refType.GetTarget()) {
                    return Some(GetRealTarget(target))
                }
            }
        }
        return None
    }

    private func MergeTypeSubstForExtendOrdering(target: TypeSubst, source: TypeSubst): Unit {
        for ((tyVar, ty) in source.entries) {
            target.Put(tyVar.value, ty)
        }
    }

    private func BuildCurrentToOtherExtendTypeMapping(
        curDecl: ExtendDecl,
        otherExtend: ExtendDecl,
        extendedDecl: Option<Decl>
    ): TypeSubst {
        let out = TypeSubst()
        if (let None <- extendedDecl) {
            return out
        }
        let realExtendedDecl = extendedDecl.getOrThrow()
        if (let None <- curDecl.extendedType) {
            return out
        }
        if (let None <- otherExtend.extendedType) {
            return out
        }
        let curExtendedType = curDecl.extendedType.getOrThrow()
        let otherExtendedType = otherExtend.extendedType.getOrThrow()
        if (let None <- curExtendedType.GetTy()) {
            return out
        }
        if (let None <- otherExtendedType.GetTy()) {
            return out
        }
        let curExtendedTy = curExtendedType.GetTy().getOrThrow()
        let otherExtendedTy = otherExtendedType.GetTy().getOrThrow()
        let mappingOfExtendedToCur = GenerateTypeMapping(realExtendedDecl, curExtendedTy.typeArgs)
        let mappingOfExtendedToOther = GenerateTypeMapping(realExtendedDecl, otherExtendedTy.typeArgs)
        if (let Some(originalTy) <- realExtendedDecl.GetTy()) {
            for (typeArg in originalTy.typeArgs) {
                if (let Some(genericTy) <- (typeArg as GenericsTy)) {
                    let mapping = GenerateTypeMappingByTy(
                        mappingOfExtendedToCur.Get(genericTy),
                        mappingOfExtendedToOther.Get(genericTy)
                    )
                    MergeTypeSubstForExtendOrdering(out, mapping)
                }
            }
        }
        return out
    }

    private func DeterminingSkipExtendByInheritanceRelationship(
        curDecl: ExtendDecl,
        otherExtend: ExtendDecl,
        extendedDecl: Option<Decl>
    ): Option<Bool> {
        var skipExtend: Option<Bool> = None
        var lastLeft: Option<Ty> = None
        var lastRight: Option<Ty> = None
        let curToOtherMapping = BuildCurrentToOtherExtendTypeMapping(curDecl, otherExtend, extendedDecl)
        for (curDeclSuper in curDecl.inheritedTypes) {
            if (let None <- curDeclSuper.GetTy()) {
                continue
            }
            var curDeclSuperTy = curDeclSuper.GetTy().getOrThrow()
            if (!curToOtherMapping.IsEmpty()) {
                curDeclSuperTy = typeManager.GetInstantiatedTy(curDeclSuperTy, curToOtherMapping)
            }
            var hasSubImpl: Option<Ty> = None
            var hasSuperImpl: Option<Ty> = None
            for (otherSuper in otherExtend.inheritedTypes) {
                if (let None <- otherSuper.GetTy()) {
                    continue
                }
                let otherSuperTy = otherSuper.GetTy().getOrThrow()
                if (SameTy(otherSuperTy, curDeclSuperTy)) {
                    continue
                }
                if (typeManager.IsSubtype(otherSuperTy, curDeclSuperTy)) {
                    hasSubImpl = otherSuperTy
                }
                if (typeManager.IsSubtype(curDeclSuperTy, otherSuperTy)) {
                    hasSuperImpl = otherSuperTy
                }
            }
            if (let Some(subTy) <- hasSubImpl) {
                if (let Some(superTy) <- hasSuperImpl) {
                    let builder = diag.DiagnoseRefactor(
                        DiagKindRefactor.sema_extend_check_sequence_cannot_decide,
                        DeclRange(curDecl)
                    )
                    let inherChain = subTy.String() + " <: " + curDeclSuperTy.String() + " <: " + superTy.String()
                    builder.AddNote(
                        DeclIdentifierRange(otherExtend),
                        "conflict with this extension, beacase of '" + inherChain + "'"
                    )
                    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                    return None
                }
            }
            var noRelatedImpl = false
            if (let None <- hasSubImpl) {
                noRelatedImpl = true
            }
            if (let Some(_) <- hasSuperImpl) {
                noRelatedImpl = false
            }
            if (noRelatedImpl) {
                continue
            }
            let nextSkip = if (let Some(_) <- hasSubImpl) { true } else { false }
            if (let Some(previousSkip) <- skipExtend) {
                if (previousSkip != nextSkip) {
                    let builder = diag.DiagnoseRefactor(
                        DiagKindRefactor.sema_extend_check_sequence_cannot_decide,
                        DeclRange(curDecl)
                    )
                    let lastInherit = if ((let Some(leftTy) <- lastLeft) && (let Some(rightTy) <- lastRight)) {
                        leftTy.String() + " <: " + rightTy.String()
                    } else {
                        ""
                    }
                    let currentInherit = if (let Some(subTy) <- hasSubImpl) {
                        subTy.String() + " <: " + curDeclSuperTy.String()
                    } else if (let Some(superTy) <- hasSuperImpl) {
                        curDeclSuperTy.String() + " <: " + superTy.String()
                    } else {
                        ""
                    }
                    builder.AddNote(
                        DeclIdentifierRange(otherExtend),
                        "conflict with this extension, beacase of '" + lastInherit + "' and '" + currentInherit + "'"
                    )
                    // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                    return None
                }
            }
            skipExtend = nextSkip
            if (nextSkip) {
                if (let Some(subTy) <- hasSubImpl) {
                    lastLeft = subTy
                    lastRight = curDeclSuperTy
                }
            } else if (let Some(superTy) <- hasSuperImpl) {
                lastLeft = curDeclSuperTy
                lastRight = superTy
            }
        }
        return skipExtend
    }

    private func GetVisibleExtendMembersForExtend(decl: InheritableDecl): (MemberMap, MemberMap) {
        let interfaceMembers = MemberMap()
        let extendMembers = MemberMap()
        let invisibleInterfaceMembers = MemberMap()
        let invisibleExtendMembers = MemberMap()
        if (let Some(ed) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- ed.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    let allExtends = CollectExtendByInterfaceInherit(CollectExtendsForTy(extendedTy), ed)
                    let mts = MultiTypeSubst()
                    typeManager.GenerateGenericMapping(mts, extendedTy)
                    for (otherExtend in allExtends) {
                        if (SameDecl(otherExtend, ed) || (let None <- otherExtend.extendedType)) {
                            continue
                        }
                        if (decl.fullPackageName != otherExtend.fullPackageName && !otherExtend.TestAttr(Attribute.PUBLIC)) {
                            continue
                        }
                        let visible = typeManager.CheckGenericDeclInstantiation(otherExtend, extendedTy.typeArgs)
                        if (!visible) {
                            typeManager.GenerateStructDeclGenericMapping(mts, otherExtend, extendedTy)
                        }
                        let targetInterfaceMap = if (visible) { interfaceMembers } else { invisibleInterfaceMembers }
                        let targetExtendMap = if (visible) { extendMembers } else { invisibleExtendMembers }
                        let curInterfaceMap = GetAndCheckInheritedInterfaces(otherExtend)
                        for (entry in curInterfaceMap.entries) {
                            entry.signature.extendDecl = otherExtend
                        }
                        MergeInheritedMembers(targetInterfaceMap, curInterfaceMap, extendedTy)
                        let typeMapping = MultiTypeSubstToTypeSubst(mts)
                        for (edMember in otherExtend.GetMemberDecls()) {
                            if (!Ty.IsTyCorrect(edMember.GetTy()) || IsInvisibleMember(edMember, decl.fullPackageName)) {
                                continue
                            }
                            let memberTy: Option<Ty> = if (let Some(ty) <- edMember.GetTy()) {
                                Some(typeManager.GetInstantiatedTy(ty, typeMapping))
                            } else {
                                None
                            }
                            let structTy: Option<Ty> = if (let Some(ty) <- otherExtend.GetTy()) {
                                Some(typeManager.GetInstantiatedTy(ty, typeMapping))
                            } else {
                                None
                            }
                            let sig = MemberSignature(
                                decl: edMember,
                                ty: memberTy,
                                structTy: structTy,
                                extendDecl: otherExtend
                            )
                            for (bounds in GetAllGenericUpperBounds(typeManager, edMember)) {
                                sig.upperBounds.add(bounds)
                            }
                            let _ = UpdateInheritedMemberIfNeeded(targetExtendMap, sig)
                        }
                    }
                    MergeInheritedMembers(interfaceMembers, extendMembers, extendedTy)
                    MergeInheritedMembers(invisibleInterfaceMembers, invisibleExtendMembers, extendedTy)
                    RemoveAbstractMembers(interfaceMembers)
                    RemoveAbstractMembers(invisibleInterfaceMembers)
                }
            }
        }
        return (interfaceMembers, invisibleInterfaceMembers)
    }

    private func CheckExtendExportDependence(
        curDecl: InheritableDecl,
        interfaceSig: MemberSignature,
        implDecls: MemberMap
    ): Unit {
        if ((let None <- (curDecl as ExtendDecl)) || !curDecl.IsExportedDecl()) {
            return
        }
        if (let None <- interfaceSig.decl) {
            return
        }
        let interfaceDecl = interfaceSig.decl.getOrThrow()
        for (child in implDecls.Get(interfaceDecl.identifier.Val())) {
            if (let None <- child.decl) {
                continue
            }
            let childDecl = child.decl.getOrThrow()
            if (childDecl.astKind != interfaceDecl.astKind) {
                continue
            }
            var implemented = interfaceDecl.astKind == ASTKind.PROP_DECL
            if (!implemented && interfaceDecl.IsFunc()) {
                implemented = CheckImplementationRelation(interfaceSig, child)
            }
            if (!implemented) {
                continue
            }
            if (let Some(parentOuter) <- interfaceDecl.outerDecl) {
                if (let Some(childOuter) <- childDecl.outerDecl) {
                    if (parentOuter.IsExportedDecl() && !childOuter.IsExportedDecl()) {
                        let builder = diag.DiagnoseRefactor(
                            DiagKindRefactor.sema_export_extend_depend_non_export_extend,
                            DeclRange(curDecl),
                            arguments: [interfaceDecl.identifier.Val()]
                        )
                        builder.AddNote(DeclRange(childOuter), "following extension cannot be exported")
                        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                    }
                }
            }
        }
    }

    private func CollectExtendsForTy(ty: Ty): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        for (extendDecl in typeManager.GetAllExtendsByTy(ty)) {
            AddExtendUniqueByPosition(out, extendDecl)
        }
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(ty)) {
            for (extendDecl in typeManager.GetDeclExtends(decl)) {
                AddExtendUniqueByPosition(out, extendDecl)
            }
        }
        return out
    }

    private func RemoveAbstractMembers(members: MemberMap): Unit {
        var idx: Int64 = 0
        while (idx < members.entries.size) {
            if (let Some(decl) <- members.entries[idx].signature.decl) {
                if (decl.TestAttr(Attribute.ABSTRACT)) {
                    members.Remove(idx)
                    continue
                }
            }
            idx++
        }
    }

    public func ComputeInconsistentTypes(
        child: MemberSignature,
        parent: MemberSignature,
        updated: MemberSignature,
        status: (Bool, Bool),
        inconsistentTypes: TySet
    ): Bool {
        let parentTy = FuncTyFromOption(parent.ty)
        let childTy = FuncTyFromOption(child.ty)
        if (let Some(parentFuncTy) <- parentTy) {
            if (let Some(childFuncTy) <- childTy) {
                var hasConsistentReturnTy = true
                if (status[0]) {
                    var parentAbstract = false
                    if (let Some(parentDecl) <- parent.decl) {
                        parentAbstract = parentDecl.TestAttr(Attribute.ABSTRACT)
                    }
                    var childAbstract = false
                    if (let Some(childDecl) <- child.decl) {
                        childAbstract = childDecl.TestAttr(Attribute.ABSTRACT)
                    }
                    let isValidOverride = parentAbstract || !childAbstract
                    hasConsistentReturnTy = isValidOverride && AreReturnTypesCompatible(parentFuncTy, childFuncTy)
                    var bothInterfaceMember = false
                    if (status[1]) {
                        if (let Some(childDecl) <- child.decl) {
                            if (let Some(parentDecl) <- parent.decl) {
                                if (let Some(childOuter) <- childDecl.outerDecl) {
                                    if (let Some(parentOuter) <- parentDecl.outerDecl) {
                                        bothInterfaceMember = childOuter.astKind == ASTKind.INTERFACE_DECL &&
                                            parentOuter.astKind == ASTKind.INTERFACE_DECL
                                    }
                                }
                            }
                        }
                    }
                    let needUpdateTy = bothInterfaceMember && AreReturnTypesCompatible(childFuncTy, parentFuncTy)
                    hasConsistentReturnTy = hasConsistentReturnTy || needUpdateTy
                    if (needUpdateTy) {
                        updated.ty = parentFuncTy
                    }
                }
                if (!hasConsistentReturnTy) {
                    AddPossibleInconsistentTypes(parent, child, inconsistentTypes)
                }
                return hasConsistentReturnTy
            }
        }
        return true
    }

    public func UpdateInheritedMemberIfNeeded(
        inheritedMembers: MemberMap,
        child: MemberSignature,
        inheritedInterfaces!: Bool = false
    ): MemberSignature {
        if (let None <- child.decl) {
            return child
        }
        let childDecl = child.decl.getOrThrow()
        let updated = child.Clone()
        var needImplement = inheritedInterfaces
        if (let Some(outer) <- childDecl.outerDecl) {
            needImplement = needImplement || outer.astKind == ASTKind.INTERFACE_DECL
        }
        let inconsistentTypes = TySet()
        for (entry in inheritedMembers.entries) {
            if (entry.name != childDecl.identifier.Val()) {
                continue
            }
            let parent = entry.signature.Clone()
            if (let None <- parent.decl) {
                continue
            }
            let parentDecl = parent.decl.getOrThrow()
            if (parentDecl.astKind != childDecl.astKind) {
                continue
            }
            var shouldUpdate = true
            var inconsistentType = needImplement && TyOptionsDiffer(parent.ty, child.ty)
            if (parentDecl.IsFunc()) {
                if (childDecl.TestAttr(Attribute.GENERIC) && parentDecl.TestAttr(Attribute.GENERIC)) {
                    let typeMapping = typeManager.GenerateGenericMappingFromGeneric(parentDecl, childDecl)
                    if (let Some(parentTy) <- parent.ty) {
                        parent.ty = typeManager.GetInstantiatedTy(parentTy, typeMapping)
                    }
                }
                let parentFuncTy = FuncTyFromOption(parent.ty)
                let childFuncTy = FuncTyFromOption(child.ty)
                let sameStatus = parentDecl.TestAttr(Attribute.STATIC) == childDecl.TestAttr(Attribute.STATIC) &&
                    childDecl.TestAttr(Attribute.GENERIC) == parentDecl.TestAttr(Attribute.GENERIC)
                shouldUpdate = false
                if (let Some(parentFt) <- parentFuncTy) {
                    if (let Some(childFt) <- childFuncTy) {
                        shouldUpdate = sameStatus && typeManager.IsFuncParameterTypesIdentical(parentFt, childFt)
                    }
                }
                let consistent = ComputeInconsistentTypes(
                    child,
                    parent,
                    updated,
                    (shouldUpdate, inheritedInterfaces),
                    inconsistentTypes
                )
                inconsistentType = inconsistentType && !consistent
            } else if (inconsistentType) {
                AddPossibleInconsistentTypes(parent, child, inconsistentTypes)
            }
            if (shouldUpdate) {
                if (parentDecl.TestAttr(Attribute.ABSTRACT) || !childDecl.TestAttr(Attribute.ABSTRACT)) {
                    UpdateOverriddenFuncDeclCache(childDecl, parentDecl)
                    entry.signature = updated.Clone()
                }
                entry.signature.replaceOther = true
                if (needImplement && (!parent.inconsistentTypes.IsEmpty() || inconsistentType)) {
                    UpdateInconsistentTypesForInheritance(entry.signature, parent, inconsistentTypes)
                }
                MergeUpperBoundsForInheritance(typeManager, entry.signature, parent, inheritedInterfaces)
                MergeUpperBoundsForInheritance(typeManager, entry.signature, child, inheritedInterfaces)
                if ((let None <- parent.extendDecl) || (let None <- child.extendDecl)) {
                    entry.signature.extendDecl = None
                }
                entry.signature.isInheritedInterface = child.isInheritedInterface && inheritedInterfaces
                let relationExtend = IsRelationExtend(child)
                entry.signature.shouldBeImplemented = (entry.signature.isInheritedInterface || !relationExtend) &&
                    childDecl.TestAttr(Attribute.DEFAULT) && parentDecl.TestAttr(Attribute.DEFAULT)
                return entry.signature
            }
        }
        inheritedMembers.Add(childDecl.identifier.Val(), updated)
        return updated
    }

    private func IsRelationExtend(child: MemberSignature): Bool {
        if (checkingDecls.isEmpty()) {
            return true
        }
        if (checkingDecls[0].astKind != ASTKind.EXTEND_DECL) {
            return true
        }
        if (let Some(childExtend) <- child.extendDecl) {
            if (let Some(curExtend) <- (checkingDecls[0] as ExtendDecl)) {
                return typeManager.IsExtendInheritRelation(curExtend, childExtend)[0]
            }
        }
        return true
    }

    public func MergeInheritedMembers(
        members: MemberMap,
        otherMembers: MemberMap,
        structTy: Ty,
        inheritedInterfaces!: Bool = false
    ): Unit {
        if (otherMembers.IsEmpty()) {
            return
        }
        let mts = MultiTypeSubst()
        typeManager.GenerateGenericMapping(mts, structTy)
        let typeMapping = MultiTypeSubstToTypeSubst(mts)
        for (entry in otherMembers.entries) {
            if (typeMapping.IsEmpty() && !inheritedInterfaces) {
                let _ = UpdateInheritedMemberIfNeeded(members, entry.signature, inheritedInterfaces: false)
                continue
            }
            let memberSig = entry.signature.Clone()
            if (inheritedInterfaces) {
                memberSig.isInheritedInterface = true
            }
            if (!typeMapping.IsEmpty()) {
                if (let Some(ty) <- memberSig.ty) {
                    memberSig.ty = typeManager.GetInstantiatedTy(ty, typeMapping)
                }
                if (let Some(sigStructTy) <- memberSig.structTy) {
                    memberSig.structTy = typeManager.GetInstantiatedTy(sigStructTy, typeMapping)
                }
                UpdateUpperBoundsSetForInheritance(typeManager, memberSig.upperBounds, typeMapping)
            }
            let _ = UpdateInheritedMemberIfNeeded(members, memberSig, inheritedInterfaces: inheritedInterfaces)
        }
    }

    private func UpdateOverriddenFuncDeclCache(child: Decl, parent: Decl): Unit {
        if (checkingDecls.isEmpty()) {
            return
        }
        if (let Some(outer) <- child.outerDecl) {
            if (SameDecl(outer, checkingDecls[checkingDecls.size - 1])) {
                typeManager.UpdateTopOverriddenFuncDeclMap(child, parent)
            }
        }
    }

    private func AreReturnTypesCompatible(parentTy: FuncTy, childTy: FuncTy, inconsistentTypes!: TySet = TySet()): Bool {
        for (ty in inconsistentTypes.values) {
            if (!typeManager.IsSubtype(childTy.retTy, ty, implicitBoxed: false)) {
                return false
            }
        }
        if (!CheckReturnOverrideByGeneric(parentTy, childTy)) {
            return false
        }
        return typeManager.IsSubtype(childTy.retTy, parentTy.retTy, implicitBoxed: false)
    }

    private func CheckReturnOverrideByGeneric(parentTy: FuncTy, childTy: FuncTy): Bool {
        if (!Ty.IsTyCorrect(childTy.retTy) || !Ty.IsTyCorrect(parentTy.retTy)) {
            return true
        }
        if (!childTy.retTy.IsGeneric() || SameTy(parentTy.retTy, childTy.retTy)) {
            return true
        }
        if (let Some(genericTy) <- (childTy.retTy as GenericsTy)) {
            if (genericTy.upperBounds.isEmpty()) {
                return false
            }
            for (upper in genericTy.upperBounds) {
                if (!upper.IsInterface() && !upper.IsGeneric()) {
                    return true
                }
            }
        }
        return false
    }

    @When[backend == "cjnative"]
    private func CheckNativeFFI(parent: MemberSignature, child: MemberSignature): Unit {
        if (!checkingDecls.isEmpty()) {
            let checkingDecl = checkingDecls[checkingDecls.size - 1]
            CheckForeignName(diag, typeManager, parent, child, checkingDecl)
            CheckForeignAnnotations(diag, typeManager, parent, child, checkingDecl)
        }
    }

    @When[backend != "cjnative"]
    private func CheckNativeFFI(parent: MemberSignature, child: MemberSignature): Unit {
        let _ = parent
        let _ = child
    }

    private func DiagnoseForInheritedMember(parent: MemberSignature, child: MemberSignature): Unit {
        if (let Some(parentDecl) <- parent.decl) {
            if (let Some(childDecl) <- child.decl) {
                if (parentDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR) && childDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    return
                }
                if (let Some(parentOuter) <- parentDecl.outerDecl) {
                    if (let Some(childOuter) <- childDecl.outerDecl) {
                        if (SameDecl(parentOuter, childOuter)) {
                            return
                        }
                    }
                }
                CheckSameNameInheritanceInfo(parent, childDecl)
                if (childDecl.astKind != parentDecl.astKind) {
                    return
                }
                if (parentDecl.astKind == ASTKind.PROP_DECL) {
                    CheckInheritanceAttributes(parent, childDecl)
                    CheckPropertyInheritance(parent, childDecl)
                } else if (parentDecl.IsFunc()) {
                    if (CheckImplementationRelation(parent, child)) {
                        CheckInheritanceAttributes(parent, childDecl)
                    }
                }
                CheckNativeFFI(parent, child)
            }
        }
    }

    @When[backend == "cjnative"]
    private func DiagnoseForInheritedInterfaces(interfaceSig: MemberSignature, implDecls: MemberMap): Unit {
        if (let Some(interfaceDecl) <- interfaceSig.decl) {
            for (child in implDecls.Get(interfaceDecl.identifier.Val())) {
                if (let Some(childDecl) <- child.decl) {
                    CheckSameNameInheritanceInfo(interfaceSig, childDecl)
                    if (childDecl.astKind != interfaceDecl.astKind) {
                        continue
                    }
                    if (interfaceDecl.astKind == ASTKind.PROP_DECL) {
                        CheckInheritanceForInterface(interfaceSig, child)
                        CheckPropertyInheritance(interfaceSig, childDecl)
                    } else if (interfaceDecl.IsFunc()) {
                        if (CheckImplementationRelation(interfaceSig, child)) {
                            CheckIncompleteOverrideOrImplOfExtend(interfaceSig, child)
                            CheckInheritanceForInterface(interfaceSig, child)
                            CheckMutModifierCompatible(interfaceSig, childDecl)
                        }
                    }
                    CheckNativeFFI(interfaceSig, child)
                }
            }
            if (interfaceDecl.TestAttr(Attribute.DEFAULT)) {
                interfaceDecl.EnableAttr(Attribute.INTERFACE_IMPL)
            }
        }
    }

    @When[backend != "cjnative"]
    private func DiagnoseForInheritedInterfaces(interfaceSig: MemberSignature, implDecls: MemberMap): Unit {
        if (let Some(interfaceDecl) <- interfaceSig.decl) {
            for (child in implDecls.Get(interfaceDecl.identifier.Val())) {
                if (let Some(childDecl) <- child.decl) {
                    CheckSameNameInheritanceInfo(interfaceSig, childDecl)
                    if (childDecl.astKind != interfaceDecl.astKind) {
                        continue
                    }
                    if (interfaceDecl.astKind == ASTKind.PROP_DECL) {
                        CheckInheritanceForInterface(interfaceSig, child)
                        CheckPropertyInheritance(interfaceSig, childDecl)
                    } else if (interfaceDecl.IsFunc()) {
                        if (CheckImplementationRelation(interfaceSig, child)) {
                            CheckInheritanceForInterface(interfaceSig, child)
                            CheckMutModifierCompatible(interfaceSig, childDecl)
                        }
                    }
                    CheckNativeFFI(interfaceSig, child)
                }
            }
            if (interfaceDecl.TestAttr(Attribute.DEFAULT)) {
                interfaceDecl.EnableAttr(Attribute.INTERFACE_IMPL)
            }
        }
    }

    private func CheckIncompleteOverrideOrImplOfExtend(interfaceSig: MemberSignature, child: MemberSignature): Unit {
        if (checkingDecls.isEmpty()) {
            return
        }
        if (let None <- interfaceSig.decl) {
            return
        }
        if (let None <- child.decl) {
            return
        }
        let interfaceDecl = interfaceSig.decl.getOrThrow()
        let childDecl = child.decl.getOrThrow()
        if (let None <- childDecl.outerDecl) {
            return
        }
        let childOuter = childDecl.outerDecl.getOrThrow()
        if (let None <- (childOuter as ExtendDecl)) {
            return
        }
        let childOuterExtend = (childOuter as ExtendDecl).getOrThrow()
        if (let None <- childOuterExtend.extendedType) {
            return
        }
        let extendedType = childOuterExtend.extendedType.getOrThrow()
        if (let None <- extendedType.GetTarget()) {
            return
        }
        let childOuterDecl = extendedType.GetTarget().getOrThrow()
        if (IsExtendImplementationInCurrentCheck(childOuterDecl)) {
            return
        }
        if (let None <- childOuterDecl.GetTy()) {
            return
        }
        let childOuterTy = childOuterDecl.GetTy().getOrThrow()
        if (!childOuterTy.HasGeneric()) {
            return
        }
        if (childOuterDecl.astKind != ASTKind.CLASS_DECL) {
            return
        }
        let checkingDecl = checkingDecls[0]
        if (let None <- checkingDecl.GetTy()) {
            return
        }
        if (let None <- (checkingDecl.GetTy().getOrThrow() as ClassTy)) {
            return
        }
        let currentClassTy = (checkingDecl.GetTy().getOrThrow() as ClassTy).getOrThrow()
        let mapping = MultiTypeSubst()
        typeManager.GenerateGenericMapping(mapping, currentClassTy)
        let instantiatedSupers = typeManager.GetInstantiatedTys(childOuterTy, mapping)
        for (instTy in instantiatedSupers.values) {
            if (!typeManager.CheckGenericDeclInstantiation(Some(childOuterExtend), instTy.typeArgs)) {
                DiagnoseIncompleteOverrideOrImpl(interfaceDecl, childDecl, childOuterDecl)
                return
            }
        }
    }

    private func IsExtendImplementationInCurrentCheck(childOuterDecl: Decl): Bool {
        if (checkingDecls.isEmpty()) {
            return false
        }
        let checkingDecl = checkingDecls[0]
        if (SameDecl(checkingDecl, childOuterDecl)) {
            return true
        }
        if (let Some(childOuterTy) <- childOuterDecl.GetTy()) {
            for (extendDecl in typeManager.GetAllExtendsByTy(childOuterTy)) {
                if (SameDecl(extendDecl, checkingDecl)) {
                    return true
                }
            }
        }
        return false
    }

    private func DiagnoseIncompleteOverrideOrImpl(interfaceDecl: Decl, childDecl: Decl, childOuterDecl: Decl): Unit {
        if (checkingDecls.isEmpty()) {
            return
        }
        let checkingDecl = checkingDecls[0]
        let funcOrProp = if (childDecl.astKind == ASTKind.FUNC_DECL) { "function" } else { "prop" }
        let memberStr = funcOrProp + " '" + childDecl.identifier.Val() + "' in '" +
            childOuterDecl.identifier.Val() + "''s extension"
        let interfaceName = if (let Some(interfaceOuter) <- interfaceDecl.outerDecl) {
            interfaceOuter.identifier.Val()
        } else {
            ""
        }
        let interfaceBeOverridden = "interface '" + interfaceName + "'"
        if (interfaceDecl.TestAttr(Attribute.DEFAULT)) {
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.sema_cannot_override,
                DeclRange(checkingDecl),
                arguments: [funcOrProp, childDecl.identifier.Val()]
            )
            builder.AddNote(
                DeclIdentifierRange(childDecl),
                "member " + memberStr + " conflict with that in " + interfaceBeOverridden
            )
            // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
        } else {
            let prefix = if (checkingDecl.astKind == ASTKind.EXTEND_DECL) { "extend " } else { "" }
            let classNameOverride = prefix + InheritedDisplayName(checkingDecl)
            let builder = diag.Diagnose(
                checkingDecl.begin,
                checkingDecl.end,
                DiagKind.sema_interface_member_must_be_implemented_in_struct,
                args: [
                    DiagArgument(funcOrProp),
                    DiagArgument(childDecl.identifier.Val()),
                    DiagArgument(classNameOverride)
                ]
            )
            builder.AddNote(
                DeclIdentifierRange(childDecl),
                "member " + memberStr + " may not be visible to '" + classNameOverride + "'"
            )
            // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
        }
    }

    private func DiagnoseForUnimplementedInterfaces(members: MemberMap, structDecl: Decl): Unit {
        if (structDecl.TestAnyAttr(Attribute.FOREIGN, Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER)) {
            return
        }
        let prefix = if (structDecl.astKind == ASTKind.EXTEND_DECL) { "extend " } else { "" }
        let structName = prefix + InheritedDisplayName(structDecl)
        let unimplementedMembers = ArrayList<MemberSignature>()
        for (entry in members.entries) {
            let member = entry.signature
            if (let None <- member.decl) {
                continue
            }
            let memberDecl = member.decl.getOrThrow()
            let notInheritable = memberDecl.astKind != ASTKind.PROP_DECL && !memberDecl.IsFunc()
            if (notInheritable || (let Some(_) <- member.extendDecl) || opts.compileCjd) {
                continue
            }
            if (IsBuiltInOperatorFuncInExtend(diag, typeManager, member, structDecl)) {
                continue
            }
            if (structDecl.TestAttr(Attribute.COMMON) && member.isInheritedInterface &&
                IsCommonWithoutDefault(memberDecl) && (if (let Some(outer) <- memberDecl.outerDecl) { SameDecl(outer, structDecl) } else { false })) {
                continue
            }
            var skip = false
            if (let Some(outer) <- memberDecl.outerDecl) {
                skip = outer.TestAttr(Attribute.FOREIGN)
                skip = skip || (outer.TestAttr(Attribute.ABSTRACT) && memberDecl.TestAttr(Attribute.ABSTRACT) &&
                    structDecl.astKind == ASTKind.EXTEND_DECL)
            }
            skip = skip || (structDecl.astKind == ASTKind.EXTEND_DECL &&
                memberDecl.TestAttr(Attribute.ABSTRACT) && !member.isInheritedInterface)
            if (skip) {
                continue
            }
            let isAbstractClass = structDecl.TestAttr(Attribute.ABSTRACT) && structDecl.astKind == ASTKind.CLASS_DECL
            let isAbstractDecl = isAbstractClass || structDecl.astKind == ASTKind.INTERFACE_DECL
            let isStaticAbsMember = memberDecl.TestAttr(Attribute.STATIC) && memberDecl.TestAttr(Attribute.ABSTRACT)
            if (memberDecl.TestAttr(Attribute.ABSTRACT) && !isAbstractDecl) {
                unimplementedMembers.add(member.Clone())
            } else if (member.shouldBeImplemented) {
                Diagnose(
                    diag,
                    structDecl,
                    DiagKind.sema_interface_member_must_be_implemented,
                    args: [DiagArgument(DeclKindText(memberDecl)), DiagArgument(entry.name), DiagArgument(structName)]
                ).Emit()
            } else if (let Some(outer) <- memberDecl.outerDecl) {
                if (!SameDecl(outer, structDecl)) {
                    if (isStaticAbsMember && isAbstractClass) {
                        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                        diag.DiagnoseRefactor(
                            DiagKindRefactor.sema_inherit_abstract_class_static_unimplement_func,
                            DeclRange(structDecl),
                            arguments: [structName, DeclKindText(memberDecl), entry.name]
                        )
                    } else if (!member.inconsistentTypes.IsEmpty()) {
                        DiagnoseInheritedInsconsistType(member, structDecl)
                    }
                }
            }
        }
        if (!unimplementedMembers.isEmpty()) {
            let kind = if (structDecl.IsClassLikeDecl()) {
                DiagKindRefactor.sema_class_need_abstract_modifier_or_func_need_impl
            } else {
                DiagKindRefactor.sema_need_member_implementation
            }
            let builder = diag.DiagnoseRefactor(kind, DeclRange(structDecl), arguments: [structName])
            let orderedUnimplementedMembers = ArrayList<MemberSignature>()
            for (member in unimplementedMembers) {
                AddInheritanceMemberSignatureByDeclAndTy(orderedUnimplementedMembers, member)
            }
            for (member in orderedUnimplementedMembers) {
                if (let Some(memberDecl) <- member.decl) {
                    let abstractType = if (if (let Some(outer) <- memberDecl.outerDecl) {
                        outer.astKind == ASTKind.CLASS_DECL
                    } else { false }) { "abstract" } else { "interface" }
                    let identifierName = if (CountByDecl(unimplementedMembers, memberDecl) > 1) {
                        UnimplementedIdentifier(member)
                    } else {
                        "'" + memberDecl.identifier.Val() + "'"
                    }
                    builder.AddNote(
                        DeclRange(memberDecl),
                        "unimplemented ${abstractType} ${DeclKindText(memberDecl)} ${identifierName}"
                    )
                }
            }
            builder.Emit()
        }
    }

    private func DiagnoseForConflictInheritance(decl: InheritableDecl, members: MemberMap): Unit {
        for (name in members.Names()) {
            let found = members.Get(name)
            var allFunc = true
            for (member in found) {
                if (!member.IsFunc()) {
                    allFunc = false
                    break
                }
            }
            if (found.size > 1 && !allFunc) {
                let builder = DiagnoseRefactor(
                    diag,
                    DiagKindRefactor.sema_inherit_super_member_kind_inconsistent,
                    decl,
                    DeclIdentifierRange(decl),
                    arguments: [name]
                )
                let sortedDecls = ArrayList<Decl>()
                for (member in found) {
                    if (let Some(memberDecl) <- member.decl) {
                        AddInheritanceDeclUniqueByPosition(sortedDecls, memberDecl)
                    }
                }
                for (memberDecl in sortedDecls) {
                    AddNote(builder, memberDecl, DeclIdentifierRange(memberDecl),
                        DeclKindText(memberDecl) + " member")
                }
                builder.Emit()
            } else {
                for (member in found) {
                    if (!member.inconsistentTypes.IsEmpty() && member.IsProp()) {
                        DiagnoseInheritedInsconsistType(member, decl)
                    }
                }
            }
        }
    }

    private func DiagnoseInheritedInsconsistType(member: MemberSignature, node: Node): Unit {
        if (let Some(memberDecl) <- member.decl) {
            let typeName = if (memberDecl.astKind == ASTKind.PROP_DECL) { "type" } else { "return type" }
            let builder = DiagnoseRefactor(
                diag,
                DiagKindRefactor.sema_inherit_member_type_inconsistent,
                node,
                NodeConflictRange(node),
                arguments: [typeName, DeclKindText(memberDecl), memberDecl.identifier.Val()]
            )
            builder.AddNote("conflict types are " + StringifyInconsistentTypes(member.inconsistentTypes))
            // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
        }
    }

    private func CheckSameNameInheritanceInfo(parent: MemberSignature, child: Decl): Unit {
        if (let None <- parent.decl) {
            return
        }
        let parentDecl = parent.decl.getOrThrow()
        let name = child.identifier.Val()
        let childStatic = if (child.TestAttr(Attribute.STATIC)) { "static" } else { "non-static" }
        let parentStatic = if (parentDecl.TestAttr(Attribute.STATIC)) { "static" } else { "non-static" }
        let inheritance = if (!checkingDecls.isEmpty() && checkingDecls[0].astKind == ASTKind.EXTEND_DECL) {
            "extended type"
        } else {
            "parent class or interfaces"
        }
        if (child.TestAttr(Attribute.STATIC) != parentDecl.TestAttr(Attribute.STATIC)) {
            Diagnose(
                diag,
                child,
                DiagKind.sema_static_and_non_static_member_cannot_have_same_name,
                args: [DiagArgument(childStatic), DiagArgument(name), DiagArgument(parentStatic), DiagArgument(inheritance)]
            ).Emit()
            return
        }
        if (child.astKind != parentDecl.astKind) {
            if ((let Some(_) <- parent.extendDecl) || parent.isInheritedInterface || CheckExtendMemberValid(parent, child)) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.sema_inherit_member_kind_inconsistent,
                    DeclIdentifierRange(child),
                    arguments: [DeclKindText(child), name, DeclKindText(parentDecl), inheritance]
                )
                builder.AddNote(DeclIdentifierRange(parentDecl), "found conflict here")
                builder.Emit()
            }
        } else if (parentDecl.astKind == ASTKind.VAR_DECL) {
            Diagnose(
                diag,
                child,
                DiagKind.sema_member_variable_can_not_shadow,
                args: [DiagArgument(name)]
            ).Emit()
        }
    }

    private func CheckInheritanceAttributes(parent: MemberSignature, child: Decl): Unit {
        if (let None <- parent.decl) {
            return
        }
        let parentDecl = parent.decl.getOrThrow()
        if (child.astKind != parentDecl.astKind || (parentDecl.astKind != ASTKind.PROP_DECL && !parentDecl.IsFunc())) {
            return
        }
        let typeText = DeclKindText(parentDecl)
        let name = child.identifier.Val()
        if (!CheckExtendMemberValid(parent, child) || (!checkingDecls.isEmpty() && checkingDecls[0].astKind == ASTKind.EXTEND_DECL)) {
            return
        }
        if (!parentDecl.TestAttr(Attribute.STATIC) && child.TestAttr(Attribute.REDEF)) {
            diag.Diagnose(
                child.begin,
                child.end,
                DiagKind.sema_func_no_override_or_redefine_modifier,
                args: [DiagArgument("redef"), DiagArgument(typeText), DiagArgument(name)]
            ).Emit()
        } else if (!parentDecl.TestAttr(Attribute.ABSTRACT) && !parentDecl.TestAttr(Attribute.STATIC)) {
            let notInInterface = if (let Some(parentOuter) <- parentDecl.outerDecl) {
                parentOuter.astKind != ASTKind.INTERFACE_DECL
            } else {
                true
            }
            if ((!parentDecl.TestAttr(Attribute.OPEN) && notInInterface) || TestManager.IsDeclOpenToMock(parentDecl)) {
                DiagCannotOverride(diag, child, parentDecl)
            } else if (child.TestAttr(Attribute.ABSTRACT) && notInInterface) {
                diag.Diagnose(
                    child.begin,
                    child.end,
                    DiagKind.sema_invalid_override_member_in_class,
                    args: [DiagArgument(typeText), DiagArgument(name), DiagArgument(typeText)]
                ).Emit()
            }
        }
    }

    private func CheckPropertyInheritance(parent: MemberSignature, child: Decl): Unit {
        if (let None <- parent.decl) {
            return
        }
        let parentDecl = parent.decl.getOrThrow()
        if (parentDecl.astKind != ASTKind.PROP_DECL) {
            return
        }
        if (TyOptionsDiffer(parent.ty, child.GetTy()) || !parent.inconsistentTypes.IsEmpty()) {
            Diagnose(diag, child, DiagKind.sema_property_override_implement_type_diff).Emit()
        }
        if (let Some(parentProp) <- (parentDecl as PropDecl)) {
            if (let Some(childProp) <- (child as PropDecl)) {
                if (childProp.isVar != parentProp.isVar) {
                    let kind = if (parentProp.isVar) {
                        DiagKindRefactor.sema_property_have_same_declaration_in_inherit_mut
                    } else {
                        DiagKindRefactor.sema_property_have_same_declaration_in_inherit_immut
                    }
                    DiagnoseRefactor(diag, kind, childProp,
                        arguments: [childProp.identifier.Val()]).Emit()
                } else if (childProp.isVar && (childProp.getters.isEmpty() || childProp.setters.isEmpty()) &&
                    parentProp.TestAnyAttr(Attribute.DEFAULT, Attribute.ABSTRACT)) {
                    DiagnoseRefactor(diag, DiagKindRefactor.sema_property_must_implement_both, childProp,
                        arguments: [childProp.identifier.Val()]).Emit()
                }
            }
        }
        CheckAccessVisibility(parentDecl, child, child)
    }

    private func CheckGenericTypeArgInfo(parent: MemberSignature, child: MemberSignature): Unit {
        if (let Some(parentDecl) <- parent.decl) {
            if (let Some(childDecl) <- child.decl) {
                let diffStatus = parentDecl.TestAttr(Attribute.STATIC) != childDecl.TestAttr(Attribute.STATIC)
                if ((let Some(_) <- parentDecl.GetGeneric()) && (let Some(_) <- childDecl.GetGeneric()) && !diffStatus) {
                    CheckGenericTypeBoundsMapped(parentDecl, childDecl, parent.upperBounds, child.upperBounds, diag, typeManager)
                }
            }
        }
    }

    private func CheckInheritanceForInterface(interfaceSig: MemberSignature, child: MemberSignature): Unit {
        if (let Some(interfaceMember) <- interfaceSig.decl) {
            if (let Some(childDecl) <- child.decl) {
                if (childDecl.astKind != interfaceMember.astKind ||
                    (interfaceMember.astKind != ASTKind.PROP_DECL && !interfaceMember.IsFunc())) {
                    return
                }
                let typeText = DeclKindText(interfaceMember)
                if (childDecl.TestAttr(Attribute.ABSTRACT) && !interfaceMember.TestAttr(Attribute.ABSTRACT)) {
                    diag.Diagnose(
                        childDecl.begin,
                        childDecl.end,
                        DiagKind.sema_invalid_override_or_redefine_member_in_interface,
                        args: [DiagArgument(typeText), DiagArgument(childDecl.identifier.Val()), DiagArgument(typeText)]
                    ).Emit()
                }
                childDecl.EnableAttr(Attribute.INTERFACE_IMPL)
                if (let Some(propDecl) <- (childDecl as PropDecl)) {
                    for (getter in propDecl.getters) {
                        getter.EnableAttr(Attribute.INTERFACE_IMPL)
                    }
                    for (setter in propDecl.setters) {
                        setter.EnableAttr(Attribute.INTERFACE_IMPL)
                    }
                }
            }
        }
    }

    private func CheckImplementationRelation(parent: MemberSignature, child: MemberSignature): Bool {
        if (let None <- parent.decl) {
            return false
        }
        if (let None <- child.decl) {
            return false
        }
        let parentDecl = parent.decl.getOrThrow()
        let childDecl = child.decl.getOrThrow()
        if (!parentDecl.IsFunc()) {
            return false
        }
        var parentTy = parent.ty
        if (let Some(parentFunc) <- (parentDecl as FuncDecl)) {
            if (let Some(childFunc) <- (childDecl as FuncDecl)) {
                if (childFunc.TestAttr(Attribute.GENERIC) && parentDecl.TestAttr(Attribute.GENERIC)) {
                    let typeMapping = typeManager.GenerateGenericMappingFromGeneric(parentDecl, childDecl)
                    if (let Some(parentTyValue) <- parentTy) {
                        parentTy = typeManager.GetInstantiatedTy(parentTyValue, typeMapping)
                    }
                }
                if (let Some(parentFuncTy) <- FuncTyFromOption(parentTy)) {
                    if (let Some(childFuncTy) <- FuncTyFromOption(child.ty)) {
                        let sameSignature = typeManager.IsFuncParameterTypesIdentical(parentFuncTy, childFuncTy)
                        if (sameSignature) {
                            let inheritedByExtension = typeManager.HasExtensionRelation(childFuncTy.retTy, parentFuncTy.retTy)
                            let isParamListCorrect = HasParamListForParameterNameCheck(parentFunc) &&
                                HasParamListForParameterNameCheck(childFunc)
                            if (isParamListCorrect && !AreFuncParameterNameIdentical(parentFunc, childFunc)) {
                                DiagnoseParameterName(diag, parentFunc, childFunc)
                            } else if (!CheckThisTypeCompatibility(parentFunc, childFunc)) {
                                let builder = diag.DiagnoseRefactor(
                                    DiagKindRefactor.sema_inherit_not_return_this,
                                    DeclIdentifierRange(childFunc)
                                )
                                builder.AddNote(DeclIdentifierRange(parentFunc), "the overriden function")
                                builder.Emit()
                            } else if (AreReturnTypesCompatible(parentFuncTy, childFuncTy, inconsistentTypes: parent.inconsistentTypes)) {
                                var diagNode: Decl = childFunc
                                if (!checkingDecls.isEmpty()) {
                                    if (let Some(childOuter) <- childFunc.outerDecl) {
                                        if (!SameDecl(childOuter, checkingDecls[0])) {
                                            diagNode = checkingDecls[0]
                                        }
                                    }
                                }
                                CheckAccessVisibility(parentFunc, childFunc, diagNode)
                                CheckGenericTypeArgInfo(parent, child)
                            } else if (inheritedByExtension || !CheckReturnOverrideByGeneric(parentFuncTy, childFuncTy)) {
                                let builder = diag.Diagnose(
                                    childFunc.begin,
                                    childFunc.end,
                                    DiagKind.sema_return_type_invariance,
                                    args: [DiagArgument(childFunc.identifier.Val()), DiagArgument(parentFuncTy.retTy.String())]
                                )
                                builder.AddNote(DeclRange(parentFunc), "cannot override/implement the following function")
                                // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
                            } else {
                                var targetFunc: FuncDecl = parentFunc
                                var inconsistentTypesText = "'" + parentFuncTy.retTy.String() + "'"
                                if (!parent.inconsistentTypes.IsEmpty()) {
                                    targetFunc = childFunc
                                    inconsistentTypesText = StringifyInconsistentTypes(
                                        parent.inconsistentTypes,
                                        childTy: Some(childFuncTy.retTy)
                                    )
                                }
                                let builder = diag.DiagnoseRefactor(
                                    DiagKindRefactor.sema_return_type_incompatible,
                                    DeclIdentifierRange(childFunc),
                                    arguments: [childFunc.identifier.Val()]
                                )
                                builder.AddNote(
                                    DeclIdentifierRange(targetFunc),
                                    "'" + childFuncTy.retTy.String() + "' is not a subtype of " + inconsistentTypesText
                                )
                                builder.Emit()
                            }
                            if (!childFunc.IsConst() && parentDecl.IsConst()) {
                                let inheritance = if (!checkingDecls.isEmpty() && checkingDecls[0].astKind == ASTKind.EXTEND_DECL) {
                                    "extended type"
                                } else {
                                    "parent class or interfaces"
                                }
                                let builder = diag.DiagnoseRefactor(
                                    DiagKindRefactor.sema_inherit_member_kind_inconsistent,
                                    DeclIdentifierRange(childFunc),
                                    arguments: ["non-constant function", childFunc.identifier.Val(), "'const' function", inheritance]
                                )
                                builder.AddNote(DeclIdentifierRange(parentDecl), "found 'const' function here")
                                builder.Emit()
                            }
                        }
                        return sameSignature
                    }
                }
            }
        }
        return false
    }

    private func CheckMutModifierCompatible(parent: MemberSignature, child: Decl): Unit {
        if (let None <- parent.decl) {
            return
        }
        let parentDecl = parent.decl.getOrThrow()
        if (!parentDecl.IsFunc()) {
            return
        }
        if (let Some(parentOuter) <- parentDecl.outerDecl) {
            if (parentOuter.astKind != ASTKind.INTERFACE_DECL) {
                return
            }
        } else {
            return
        }
        var needsCheck = false
        if (let Some(outer) <- child.outerDecl) {
            if (let Some(extendDecl) <- (outer as ExtendDecl)) {
                if (let Some(ty) <- extendDecl.GetTy()) {
                    needsCheck = ty.IsStruct()
                }
            } else {
                needsCheck = outer.astKind == ASTKind.STRUCT_DECL
            }
        }
        if (!needsCheck) {
            return
        }
        if (parentDecl.TestAttr(Attribute.MUT) != child.TestAttr(Attribute.MUT)) {
            var diagDecl: Decl = child
            if (!checkingDecls.isEmpty()) {
                if (let Some(childOuter) <- child.outerDecl) {
                    if (!SameDecl(childOuter, checkingDecls[0])) {
                        diagDecl = checkingDecls[0]
                    }
                }
            }
            let interfaceName = if (let Some(outer) <- parentDecl.outerDecl) { outer.identifier.Val() } else { "" }
            Diagnose(
                diag,
                diagDecl,
                DiagKind.sema_incompatible_mut_modifier_between_struct_and_interface,
                args: [DiagArgument(child.identifier.Val()), DiagArgument(interfaceName)]
            ).Emit()
        }
    }

    private func CheckAccessVisibility(parent: Decl, child: Decl, diagNode: Decl): Unit {
        var canBeImplemented = parent.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN, Attribute.STATIC)
        if (let Some(parentOuter) <- parent.outerDecl) {
            canBeImplemented = canBeImplemented || parentOuter.astKind == ASTKind.INTERFACE_DECL
        }
        if (!canBeImplemented) {
            return
        }
        let weakVisibility =
            (parent.TestAttr(Attribute.PUBLIC) && !child.TestAttr(Attribute.PUBLIC)) ||
            (parent.TestAttr(Attribute.PROTECTED) && !child.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)) ||
            (!parent.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED, Attribute.PRIVATE) && child.TestAttr(Attribute.PRIVATE))
        if (weakVisibility) {
            DiagnoseWeakVisibility(diag, parent, child, diagNode)
        }
    }

    private func IsExtendedDefaultImpl(parent: MemberSignature, child: Decl): Bool {
        if (let Some(parentDecl) <- parent.decl) {
            if ((parentDecl.astKind != ASTKind.FUNC_DECL && parentDecl.astKind != ASTKind.PROP_DECL) ||
                !parentDecl.TestAttr(Attribute.DEFAULT)) {
                return false
            }
            if (let Some(parentOuter) <- parentDecl.outerDecl) {
                if (parentOuter.astKind != ASTKind.INTERFACE_DECL) {
                    return false
                }
                if (let Some(childOuter) <- child.outerDecl) {
                    if (childOuter.astKind == ASTKind.EXTEND_DECL) {
                        return false
                    }
                    if (let Some(childTy) <- childOuter.GetTy()) {
                        if (let Some(parentTy) <- parentOuter.GetTy()) {
                            return typeManager.HasExtensionRelation(childTy, parentTy)
                        }
                    }
                }
            }
        }
        return false
    }

    private func CheckExtendMemberValid(parent: MemberSignature, child: Decl): Bool {
        if (let Some(parentDecl) <- parent.decl) {
            if (let Some(_) <- parent.extendDecl) {
                if (!parentDecl.TestAnyAttr(Attribute.DEFAULT, Attribute.IN_EXTEND) && child.TestAttr(Attribute.IN_EXTEND)) {
                    return true
                }
                let typeName = if (let Some(outer) <- child.outerDecl) {
                    "extend " + InheritedDisplayName(outer)
                } else {
                    "extend"
                }
                DiagnoseRefactor(
                    diag,
                    DiagKindRefactor.sema_extend_member_cannot_shadow,
                    child,
                    DeclIdentifierRange(child),
                    arguments: [child.identifier.Val(), typeName]
                ).Emit()
            } else {
                let isExtendedDefault = IsExtendedDefaultImpl(parent, child)
                let parentOuterIsExtend = if (let Some(outer) <- parentDecl.outerDecl) {
                    outer.astKind == ASTKind.EXTEND_DECL
                } else {
                    false
                }
                if (isExtendedDefault || parentOuterIsExtend) {
                    let builder = DiagnoseRefactor(
                        diag,
                        DiagKindRefactor.sema_extend_function_cannot_overridden,
                        child,
                        DeclIdentifierRange(child),
                        arguments: [DeclKindText(parentDecl), child.identifier.Val()]
                    )
                    if (!isExtendedDefault) {
                        AddNote(
                            builder,
                            parentDecl,
                            DeclIdentifierRange(parentDecl),
                            "overridden definition of '" + child.identifier.Val() + "' is here"
                        )
                    }
                    builder.Emit()
                } else if (if (let Some(outer) <- child.outerDecl) { outer.astKind == ASTKind.EXTEND_DECL } else { false }) {
                    let typeName = if (let Some(outer) <- child.outerDecl) {
                        InheritedTypeString(outer)
                    } else {
                        ""
                    }
                    let builder = DiagnoseRefactor(
                        diag,
                        DiagKindRefactor.sema_extend_member_cannot_shadow,
                        child,
                        DeclIdentifierRange(child),
                        arguments: [child.identifier.Val(), typeName]
                    )
                    AddNote(
                        builder,
                        parentDecl,
                        DeclIdentifierRange(parentDecl),
                        "shadowed definition of '" + child.identifier.Val() + "' is here"
                    )
                    builder.Emit()
                } else {
                    return true
                }
            }
            return false
        }
        return true
    }

    private func DiagnoseForOverriddenMember(child: MemberSignature): Unit {
        if (child.replaceOther) {
            return
        }
        if (let Some(childDecl) <- child.decl) {
            let typeText = DeclKindText(childDecl)
            if (childDecl.TestAttr(Attribute.OVERRIDE)) {
                Diagnose(
                    diag,
                    childDecl,
                    DiagKind.sema_missing_overridden_func,
                    args: [DiagArgument(typeText), DiagArgument(childDecl.identifier.Val()), DiagArgument(typeText)]
                ).Emit()
            } else if (childDecl.TestAttr(Attribute.REDEF) && childDecl.TestAttr(Attribute.STATIC)) {
                Diagnose(
                    diag,
                    childDecl,
                    DiagKind.sema_missing_redefined_func,
                    args: [DiagArgument(typeText), DiagArgument(childDecl.identifier.Val()), DiagArgument(typeText)]
                ).Emit()
            }
        }
    }

    private func CheckAllUpperBoundsConfliction(): Unit {
        let genericsWithConstraint = ArrayList<Generic>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (node.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(generic) <- (node as Generic)) {
                if (!generic.genericConstraints.isEmpty()) {
                    genericsWithConstraint.add(generic)
                    return VisitAction.SKIP_CHILDREN
                }
            }
            return VisitAction.WALK_CHILDREN
        })
        walker.Walk()
        for (generic in genericsWithConstraint) {
            CheckUpperBoundsConfliction(generic)
        }
    }

    private func CheckUpperBoundsConfliction(generic: Generic): Unit {
        for (gc in generic.genericConstraints) {
            if (let None <- gc.refType) {
                continue
            }
            if (let Some(typeNode) <- gc.refType) {
                if (let Some(gTy) <- typeNode.GetTy()) {
                if (let Some(genericTy) <- (gTy as GenericsTy)) {
                    if (let Some(genericDecl) <- genericTy.decl) {
                        if (genericDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                            continue
                        }
                    }
                    if (genericTy.upperBounds.isEmpty()) {
                        continue
                    }
                    var classTy: Option<Ty> = None
                    for (upper in genericTy.upperBounds) {
                        if (upper.IsClass()) {
                            if (let Some(existing) <- classTy) {
                                if (typeManager.IsSubtype(upper, existing)) {
                                    classTy = upper
                                }
                            } else {
                                classTy = upper
                            }
                        }
                    }
                    let inheritedMembers = MemberMap()
                    for (upper in genericTy.upperBounds) {
                        if (!upper.IsInterface()) {
                            continue
                        }
                        if (let Some(interfaceDecl) <- Ty.GetInheritableDeclPtrOfTy(upper)) {
                            if (structInheritedMembers.contains(interfaceDecl)) {
                                MergeInheritedMembers(inheritedMembers, GetStoredMembersForDecl(interfaceDecl), upper, inheritedInterfaces: true)
                            }
                        }
                    }
                    if (let Some(realClassTy) <- classTy) {
                        if (let Some(classDecl) <- Ty.GetInheritableDeclPtrOfTy(realClassTy)) {
                            if (let Some(curFile) <- generic.curFile) {
                                let classMembers = GetInheritedSuperMembers(classDecl, realClassTy, curFile)
                                MergeInheritedMembers(inheritedMembers, classMembers, realClassTy, inheritedInterfaces: true)
                            }
                        }
                    }
                    for (entry in inheritedMembers.entries) {
                        if (!entry.signature.inconsistentTypes.IsEmpty()) {
                            DiagnoseInheritedInsconsistType(entry.signature, gc)
                        }
                    }
                }
                }
            }
        }
    }
}

public func SelfhostPortStatus_InheritanceChecker_StructInheritanceChecker(): Bool {
    return true
}
