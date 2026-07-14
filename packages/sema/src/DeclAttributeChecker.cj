package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::option.GlobalOptions as OptionGlobalOptions

public enum DeclAttributeIssueKind {
    | SEALED_NON_ABSTRACT_CLASS
    | INVALID_ABSTRACT_MEMBER
    | INVALID_ABSTRACT_MEMBER_VISIBILITY
    | INVALID_OPEN_MEMBER
    | INVALID_OPEN_MEMBER_VISIBILITY
    | FINALIZER_IN_INHERITABLE_CLASS
    | PROP_MISSING_ACCESSOR
    | IMMUTABLE_PROP_WITH_SETTER
    | GENERIC_OPERATOR_FUNCTION
    | CJMP_ABSTRACT_MEMBER_WITH_BODY
    | CJMP_ABSTRACT_MEMBER_WITHOUT_EXPLICIT_MODIFIER
    | INVALID_MUT_EXTEND_MEMBER
}

private func DeclAttributeIssueKindIndex(kind: DeclAttributeIssueKind): Int64 {
    return match (kind) {
        case DeclAttributeIssueKind.SEALED_NON_ABSTRACT_CLASS => 0
        case DeclAttributeIssueKind.INVALID_ABSTRACT_MEMBER => 1
        case DeclAttributeIssueKind.INVALID_ABSTRACT_MEMBER_VISIBILITY => 2
        case DeclAttributeIssueKind.INVALID_OPEN_MEMBER => 3
        case DeclAttributeIssueKind.INVALID_OPEN_MEMBER_VISIBILITY => 4
        case DeclAttributeIssueKind.FINALIZER_IN_INHERITABLE_CLASS => 5
        case DeclAttributeIssueKind.PROP_MISSING_ACCESSOR => 6
        case DeclAttributeIssueKind.IMMUTABLE_PROP_WITH_SETTER => 7
        case DeclAttributeIssueKind.GENERIC_OPERATOR_FUNCTION => 8
        case DeclAttributeIssueKind.CJMP_ABSTRACT_MEMBER_WITH_BODY => 9
        case DeclAttributeIssueKind.CJMP_ABSTRACT_MEMBER_WITHOUT_EXPLICIT_MODIFIER => 10
        case DeclAttributeIssueKind.INVALID_MUT_EXTEND_MEMBER => 11
    }
}

extend DeclAttributeIssueKind <: Equatable<DeclAttributeIssueKind> {
    public operator func ==(right: DeclAttributeIssueKind): Bool {
        return DeclAttributeIssueKindIndex(this) == DeclAttributeIssueKindIndex(right)
    }

    public operator func !=(right: DeclAttributeIssueKind): Bool {
        return !(this == right)
    }
}

public class DeclAttributeIssue {
    public var kind: DeclAttributeIssueKind
    public var decl: Decl
    public var message: String

    public init(kind: DeclAttributeIssueKind, decl: Decl, message: String) {
        this.kind = kind
        this.decl = decl
        this.message = message
    }
}

private class DeclAttributeCheckerImpl {
    private var opts: OptionGlobalOptions
    private let diag: BasicDiagnosticEngine
    private var rootDecl: Decl
    private let issues: ArrayList<DeclAttributeIssue>

    public init(
        opts: OptionGlobalOptions,
        diag: BasicDiagnosticEngine,
        decl: Decl,
        issues: ArrayList<DeclAttributeIssue>
    ) {
        this.opts = opts
        this.diag = diag
        rootDecl = decl
        this.issues = issues
    }

    public func Check(): Unit {
        if (let Some(classDecl) <- (rootDecl as ClassDecl)) {
            CheckClassAttribute(classDecl)
        } else if (let Some(interfaceDecl) <- (rootDecl as InterfaceDecl)) {
            CheckInterfaceAttribute(interfaceDecl)
        } else if (let Some(enumDecl) <- (rootDecl as EnumDecl)) {
            CheckEnumAttribute(enumDecl)
        } else if (let Some(structDecl) <- (rootDecl as StructDecl)) {
            CheckStructAttribute(structDecl)
        } else if (let Some(extendDecl) <- (rootDecl as ExtendDecl)) {
            CheckExtendAttribute(extendDecl)
        } else if (let Some(propDecl) <- (rootDecl as PropDecl)) {
            CheckPropDeclAttributes(propDecl)
        } else if (let Some(funcDecl) <- (rootDecl as FuncDecl)) {
            CheckGenericFuncDeclAttributes(funcDecl)
        }
        if (rootDecl.TestAttr(Attribute.GLOBAL)) {
            SetDeclInternal(rootDecl)
        }
    }

    private func SetCommonAttributes(decl: Decl): Unit {
        SetDeclInternal(decl)
        for (memberDecl in decl.GetMemberDecls()) {
            if (decl.TestAttr(Attribute.FOREIGN)) {
                memberDecl.EnableAttr(Attribute.FOREIGN)
            }
            SetDeclInternal(memberDecl)
            SetContextDecl(decl, memberDecl)
            SetContextAttribute(decl, memberDecl)
            InheritMemberAttrRecursively(memberDecl, memberDecl.TestAttr(Attribute.STATIC))
        }
    }

    private func CheckInterfaceAttribute(interfaceDecl: InterfaceDecl): Unit {
        if (interfaceDecl.TestAttr(Attribute.SEALED)) {
            interfaceDecl.EnableAttr(Attribute.OPEN)
            interfaceDecl.EnableAttr(Attribute.PUBLIC)
        }
        if (let Some(body) <- interfaceDecl.body) {
            for (member in body.decls) {
                member.EnableAttr(Attribute.PUBLIC)
                if (!member.TestAttr(Attribute.STATIC)) {
                    member.EnableAttr(Attribute.OPEN)
                }
                if (let Some(propDecl) <- (member as PropDecl)) {
                    for (setter in propDecl.setters) {
                        if (!setter.TestAttr(Attribute.STATIC)) {
                            setter.EnableAttr(Attribute.MUT)
                        }
                    }
                }
            }
        }
        SetCommonAttributes(interfaceDecl)
    }

    private func CheckEnumAttribute(enumDecl: EnumDecl): Unit {
        for (constructor in enumDecl.constructors) {
            constructor.EnableAttr(Attribute.PUBLIC)
        }
        SetCommonAttributes(enumDecl)
    }

    private func CheckStructAttribute(structDecl: StructDecl): Unit {
        if (let None <- structDecl.body) {
            return
        }
        SetCommonAttributes(structDecl)
        if (let Some(body) <- structDecl.body) {
            for (member in body.decls) {
                if (member.astKind == ASTKind.PRIMARY_CTOR_DECL) {
                    continue
                }
                if (let Some(propDecl) <- (member as PropDecl)) {
                    for (setter in propDecl.setters) {
                        if (!setter.TestAttr(Attribute.STATIC)) {
                            setter.EnableAttr(Attribute.MUT)
                        }
                    }
                }
            }
        }
    }

    private func CheckExtendAttribute(extendDecl: ExtendDecl): Unit {
        SetCommonAttributes(extendDecl)
        for (member in extendDecl.members) {
            if (member.TestAttr(Attribute.MUT) && HasExplicitMutModifier(member)) {
                if (!IsExtendMutAllowed(extendDecl, member)) {
                    AddIssue(
                        DeclAttributeIssueKind.INVALID_MUT_EXTEND_MEMBER,
                        member,
                        "'mut' extend members are only valid for struct extensions or properties"
                    )
                }
            }
            if (let Some(propDecl) <- (member as PropDecl)) {
                let needMut = !propDecl.TestAttr(Attribute.STATIC) && IsExtendTargetStruct(extendDecl)
                if (needMut) {
                    for (setter in propDecl.setters) {
                        setter.EnableAttr(Attribute.MUT)
                    }
                }
            }
        }
    }

    private func CheckClassAttribute(classDecl: ClassDecl): Unit {
        if (classDecl.TestAttr(Attribute.SEALED)) {
            classDecl.EnableAttr(Attribute.OPEN)
            classDecl.EnableAttr(Attribute.PUBLIC)
            if (!classDecl.TestAttr(Attribute.ABSTRACT)) {
                DiagnoseRefactor(diag,
                    BasicDiagKindRefactor.sema_non_abstract_class_cannot_be_sealed,
                    classDecl,
                    MakeRange(classDecl.identifier.Begin(), classDecl.identifier.End())
                ).Emit()
            }
        }
        SetCommonAttributes(classDecl)
        let body = classDecl.body.getOrThrow()
        for (member in body.decls) {
            if (member.IsFuncOrProp()) {
                CheckAttributesForPropAndFuncDeclInClass(classDecl, member)
            }
        }
    }

    private func CheckAttributesForPropAndFuncDeclInClass(classDecl: ClassDecl, member: Decl): Unit {
        if (member.astKind != ASTKind.PROP_DECL && member.astKind != ASTKind.FUNC_DECL) {
            return
        }
        if (opts.compileCjd) {
            return
        }
        let memberKind = if (member.astKind == ASTKind.PROP_DECL) { "property" } else { "function" }
        let invalidAbstract = member.TestAttr(Attribute.ABSTRACT) &&
            ((member.TestAttr(Attribute.STATIC) && !member.TestAttr(Attribute.FOREIGN)) ||
                (!classDecl.TestAttr(Attribute.ABSTRACT) && !classDecl.TestAttr(Attribute.FOREIGN))) &&
            !classDecl.TestAttr(Attribute.OBJ_C_MIRROR)
        if (invalidAbstract && !member.TestAttr(Attribute.COMMON_WITH_DEFAULT)) {
            Diagnose(diag, member, BasicDiagKind.sema_missing_func_body,
                args: [BasicDiagArgument(memberKind), BasicDiagArgument(member.identifier.Val())]).Emit()
        }
        if (member.TestAttr(Attribute.ABSTRACT) && classDecl.TestAttr(Attribute.ABSTRACT)) {
            if (!member.TestAttr(Attribute.PUBLIC) && !member.TestAttr(Attribute.PROTECTED)) {
                diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_invalid_member_visibility_in_class,
                    MakeRange(member.identifier.Begin(), member.identifier.End()),
                    arguments: ["abstract", memberKind]
                ).Emit()
            }
        }
        CheckCJMPAttributesForPropAndFuncDeclInClass(classDecl, member)

        let isInheritableClass = classDecl.TestAttr(Attribute.OPEN) || classDecl.TestAttr(Attribute.ABSTRACT)
        if (member.TestAttr(Attribute.OPEN)) {
            if (!isInheritableClass) {
                Diagnose(diag, member, BasicDiagKind.sema_ignore_open).Emit()
            } else if (!member.TestAttr(Attribute.PUBLIC) && !member.TestAttr(Attribute.PROTECTED)) {
                DiagnoseRefactor(
                    diag,
                    BasicDiagKindRefactor.sema_invalid_member_visibility_in_class,
                    member,
                    MakeRange(member.identifier.Begin(), member.identifier.End()),
                    arguments: ["open", memberKind]
                ).Emit()
            } else if (let Some(propDecl) <- (member as PropDecl)) {
                for (setter in propDecl.setters) {
                    setter.EnableAttr(Attribute.OPEN)
                }
                for (getter in propDecl.getters) {
                    getter.EnableAttr(Attribute.OPEN)
                }
            }
        }
        if (let Some(funcDecl) <- (member as FuncDecl)) {
            if (funcDecl.IsFinalizer() && isInheritableClass) {
                AddIssue(
                    DeclAttributeIssueKind.FINALIZER_IN_INHERITABLE_CLASS,
                    funcDecl,
                    "finalizers are forbidden in open or abstract classes"
                )
            }
        }
    }

    private func CheckCJMPAttributesForPropAndFuncDeclInClass(classDecl: ClassDecl, member: Decl): Unit {
        let inCJMP = classDecl.TestAttr(Attribute.COMMON) || classDecl.TestAttr(Attribute.SPECIFIC)
        let inAbstractCJMP = classDecl.TestAttr(Attribute.ABSTRACT) && inCJMP
        let isCJMP = member.TestAttr(Attribute.COMMON) || member.TestAttr(Attribute.SPECIFIC)
        let isAbstract = member.TestAttr(Attribute.ABSTRACT)
        let compilerAddedOrConstructor = member.TestAttr(Attribute.COMPILER_ADD) ||
            member.TestAttr(Attribute.CONSTRUCTOR)
        let hasBody = MemberHasBody(member)
        let memberKind = if (member.astKind == ASTKind.PROP_DECL) { "property" } else { "function" }
        if (hasBody && inCJMP && isAbstract) {
            AddIssue(
                DeclAttributeIssueKind.CJMP_ABSTRACT_MEMBER_WITH_BODY,
                member,
                "abstract ${memberKind} in a CJMP class cannot have a body"
            )
        }
        let checkedBefore = member.TestAttr(Attribute.FROM_COMMON_PART)
        if (inAbstractCJMP && !isCJMP && !isAbstract && !compilerAddedOrConstructor && !hasBody && !checkedBefore) {
            AddIssue(
                DeclAttributeIssueKind.CJMP_ABSTRACT_MEMBER_WITHOUT_EXPLICIT_MODIFIER,
                member,
                "member in common/specific abstract class needs an explicit modifier or body"
            )
        }
    }

    private func CheckPropDeclAttributes(propDecl: PropDecl): Unit {
        if (let Some(outer) <- propDecl.outerDecl) {
            if (outer.TestAttr(Attribute.OBJ_C_MIRROR)) {
                return
            }
        }
        if (propDecl.TestAnyAttr(Attribute.ABSTRACT, Attribute.JAVA_MIRROR) || opts.compileCjd) {
            return
        }
        if (IsCommonWithoutDefault(propDecl)) {
            return
        }
        if (propDecl.isVar) {
            let staticNeedsRedef = propDecl.TestAttr(Attribute.STATIC) && !propDecl.TestAttr(Attribute.REDEF)
            let instNeedsOverride = !propDecl.TestAttr(Attribute.STATIC) && !propDecl.TestAttr(Attribute.OVERRIDE)
            if (((instNeedsOverride || staticNeedsRedef) &&
                (propDecl.setters.isEmpty() || propDecl.getters.isEmpty())) ||
                (!propDecl.TestAttr(Attribute.ABSTRACT) && propDecl.setters.isEmpty() && propDecl.getters.isEmpty())) {
                DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_property_must_have_accessors, propDecl).Emit()
            }
        } else {
            if (!propDecl.setters.isEmpty()) {
                AddIssue(
                    DeclAttributeIssueKind.IMMUTABLE_PROP_WITH_SETTER,
                    propDecl,
                    "immutable property cannot define a setter"
                )
            }
            if (propDecl.getters.isEmpty()) {
                DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_property_must_have_accessors, propDecl).Emit()
            }
        }
    }

    private func CheckGenericFuncDeclAttributes(funcDecl: FuncDecl): Unit {
        if (let Some(body) <- funcDecl.funcBody) {
            if (let Some(_) <- body.generic) {
                if (funcDecl.TestAttr(Attribute.OPERATOR)) {
                    AddIssue(
                        DeclAttributeIssueKind.GENERIC_OPERATOR_FUNCTION,
                        funcDecl,
                        "generic operator overload functions are not supported"
                    )
                }
            }
        }
    }

    private func AddIssue(kind: DeclAttributeIssueKind, decl: Decl, message: String): Unit {
        issues.add(DeclAttributeIssue(kind, decl, message))
    }
}

private func SetDeclInternal(decl: Decl): Unit {
    if (decl.TestAnyAttr(Attribute.PROTECTED, Attribute.PRIVATE, Attribute.PUBLIC) ||
        decl.astKind == ASTKind.EXTEND_DECL) {
        return
    }
    decl.EnableAttr(Attribute.INTERNAL)
}

private func SetContextAttribute(parent: Decl, memberDecl: Decl): Unit {
    if (parent.astKind == ASTKind.INTERFACE_DECL || parent.astKind == ASTKind.CLASS_DECL) {
        memberDecl.EnableAttr(Attribute.IN_CLASSLIKE)
    } else if (parent.astKind == ASTKind.ENUM_DECL) {
        memberDecl.EnableAttr(Attribute.IN_ENUM)
    } else if (parent.astKind == ASTKind.STRUCT_DECL) {
        memberDecl.EnableAttr(Attribute.IN_STRUCT)
    } else if (parent.astKind == ASTKind.EXTEND_DECL) {
        memberDecl.EnableAttr(Attribute.IN_EXTEND)
    }
}

private func SetContextDecl(parent: Decl, member: Decl): Unit {
    member.outerDecl = Some(parent)
    if (let Some(propDecl) <- (member as PropDecl)) {
        for (getter in propDecl.getters) {
            getter.outerDecl = Some(parent)
            SetParentDecl(parent, getter)
        }
        for (setter in propDecl.setters) {
            setter.outerDecl = Some(parent)
            SetParentDecl(parent, setter)
        }
    } else if (let Some(funcDecl) <- (member as FuncDecl)) {
        SetParentDecl(parent, funcDecl)
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                for (param in body.paramLists[0].params) {
                    if (let Some(desugarDecl) <- param.desugarDecl) {
                        SetParentDecl(parent, desugarDecl)
                    }
                }
            }
        }
    }
}

private func SetParentDecl(parent: Decl, funcDecl: FuncDecl): Unit {
    if (let None <- funcDecl.funcBody) {
        return
    }
    let body = funcDecl.funcBody.getOrThrow()
    if (let Some(classLikeDecl) <- (ResolveContextDecl(parent) as ClassLikeDecl)) {
        body.parentClassLike = Some(classLikeDecl)
    } else if (let Some(structDecl) <- (ResolveContextDecl(parent) as StructDecl)) {
        body.parentStruct = Some(structDecl)
    } else if (let Some(enumDecl) <- (ResolveContextDecl(parent) as EnumDecl)) {
        body.parentEnum = Some(enumDecl)
    }
}

private func ResolveContextDecl(parent: Decl): Decl {
    if (let Some(extendDecl) <- (parent as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(target) <- extendedType.GetTarget()) {
                return target
            }
        }
    }
    return parent
}

private func InheritMemberAttrRecursively(memberDecl: Decl, isStatic: Bool): Unit {
    let walker = Walker(memberDecl, visitPre: { node: Node =>
        if (node.IsNominalDecl()) {
            if (node.astKind != memberDecl.astKind || node.begin != memberDecl.begin || node.end != memberDecl.end) {
                return VisitAction.SKIP_CHILDREN
            }
        }
        if (let Some(funcBody) <- (node as FuncBody)) {
            if (isStatic) {
                funcBody.EnableAttr(Attribute.STATIC)
            }
        } else if (let Some(funcDecl) <- (node as FuncDecl)) {
            if (isStatic) {
                funcDecl.EnableAttr(Attribute.STATIC)
            }
            if (let Some(propDecl) <- funcDecl.propDecl) {
                if (!funcDecl.TestAttr(Attribute.IMPLICIT_ADD)) {
                    funcDecl.CloneAttrs(propDecl)
                    funcDecl.DisableAttr(Attribute.MUT)
                }
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func MemberHasBody(member: Decl): Bool {
    if (let Some(funcDecl) <- (member as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            if (let Some(_) <- body.body) {
                return true
            }
        }
        return false
    }
    if (let Some(propDecl) <- (member as PropDecl)) {
        if (!propDecl.getters.isEmpty() && !propDecl.getters[0].TestAttr(Attribute.COMPILER_ADD)) {
            return true
        }
    }
    return false
}

private func IsCommonWithoutDefault(decl: Decl): Bool {
    return decl.TestAttr(Attribute.COMMON) && !decl.TestAttr(Attribute.COMMON_WITH_DEFAULT)
}

private func HasExplicitMutModifier(decl: Decl): Bool {
    for (modifier in decl.modifiers) {
        if (modifier.modifier == TokenKind.MUT) {
            return true
        }
    }
    return false
}

private func IsExtendMutAllowed(extendDecl: ExtendDecl, member: Decl): Bool {
    if (member.astKind == ASTKind.PROP_DECL) {
        return true
    }
    return IsExtendTargetStruct(extendDecl)
}

private func IsExtendTargetStruct(extendDecl: ExtendDecl): Bool {
    if (let Some(extendedType) <- extendDecl.extendedType) {
        if (let Some(target) <- extendedType.GetTarget()) {
            return target.astKind == ASTKind.STRUCT_DECL
        }
        if (let Some(ty) <- extendedType.GetTy()) {
            if (let Some(_) <- (ty as StructTy)) {
                return true
            }
        }
    }
    return false
}

private func CloneDeclAttributeIssues(values: ArrayList<DeclAttributeIssue>): ArrayList<DeclAttributeIssue> {
    let out = ArrayList<DeclAttributeIssue>()
    for (value in values) {
        out.add(value)
    }
    return out
}

private func WalkDeclAttributes(
    root: Node,
    opts: OptionGlobalOptions,
    diag: BasicDiagnosticEngine,
    issues: ArrayList<DeclAttributeIssue>
): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (node.TestAnyAttr(Attribute.IMPORTED, Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(decl) <- (node as Decl)) {
            DeclAttributeCheckerImpl(opts, diag, decl, issues).Check()
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func CheckDeclAttributesForPackage(
    pkg: Package,
    diag: BasicDiagnosticEngine,
    opts!: OptionGlobalOptions = OptionGlobalOptions()
): ArrayList<DeclAttributeIssue> {
    let issues = ArrayList<DeclAttributeIssue>()
    WalkDeclAttributes(pkg, opts, diag, issues)
    return CloneDeclAttributeIssues(issues)
}

public func CheckDeclAttributesForDecl(
    decl: Decl,
    diag: BasicDiagnosticEngine,
    opts!: OptionGlobalOptions = OptionGlobalOptions()
): ArrayList<DeclAttributeIssue> {
    let issues = ArrayList<DeclAttributeIssue>()
    DeclAttributeCheckerImpl(opts, diag, decl, issues).Check()
    return CloneDeclAttributeIssues(issues)
}
