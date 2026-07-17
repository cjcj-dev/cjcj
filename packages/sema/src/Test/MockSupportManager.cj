package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::sema.GetUsableGetterForProperty
import cjcj::sema.GetUsableSetterForProperty
import cjcj::sema.TypeManager

public class DeclsToPrepare {
    public let functions: ArrayList<FuncDecl> = ArrayList<FuncDecl>()
    public let properties: ArrayList<PropDecl> = ArrayList<PropDecl>()
    public let interfacesWithDefaults: ArrayList<InterfaceDecl> = ArrayList<InterfaceDecl>()
    public let classWithInterfaceDefaults: ArrayList<(ClassLikeDecl, InterfaceDecl, Option<ExtendDecl>)> =
        ArrayList<(ClassLikeDecl, InterfaceDecl, Option<ExtendDecl>)>()

    public init() {}
}

private func IsMemberOfGenericDecl(decl: Decl): Bool {
    if (let Some(outer) <- decl.outerDecl) {
        if (outer.TestAttr(Attribute.GENERIC)) {
            return true
        }
        if (let Some(_) <- outer.genericDecl) {
            return true
        }
    }
    return false
}

private func MarkFuncMockSupportedIfNeeded(decl: FuncDecl): Unit {
    if (decl.IsStaticOrGlobal() && decl.TestAttr(Attribute.GENERIC)) {
        if (!IsMemberOfGenericDecl(decl)) {
            decl.EnableAttr(Attribute.MOCK_SUPPORTED)
        }
    } else if (decl.TestAttr(Attribute.IN_EXTEND) && decl.TestAttr(Attribute.GENERIC)) {
        if (!IsMemberOfGenericDecl(decl)) {
            decl.EnableAttr(Attribute.MOCK_SUPPORTED)
        }
    }
}

private func MakeOpenToMockIfNeeded(decl: Decl): Unit {
    if (let Some(outer) <- decl.outerDecl) {
        if (!outer.IsClassLikeDecl()) {
            return
        }
    }
    if (!decl.TestAttr(Attribute.OPEN) && !decl.TestAttr(Attribute.ABSTRACT)) {
        decl.EnableAttr(Attribute.OPEN)
        decl.EnableAttr(Attribute.OPEN_TO_MOCK)
    }
}

private func HasDefaults(interfaceDecl: InterfaceDecl): Bool {
    for (memberDecl in interfaceDecl.GetMemberDecls()) {
        if (memberDecl.astKind == ASTKind.FUNC_DECL && memberDecl.TestAttr(Attribute.DEFAULT)) {
            return true
        }
    }
    return false
}

private func FindInterfacesWithDefaults(decl: InheritableDecl): ArrayList<InterfaceDecl> {
    let result = ArrayList<InterfaceDecl>()
    for (inherited in decl.inheritedTypes) {
        if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(inherited.GetTy())) {
            if (let Some(interfaceDecl) <- (typeDecl as InterfaceDecl)) {
                if (HasDefaults(interfaceDecl)) {
                    result.add(interfaceDecl)
                }
            }
        }
    }
    return result
}

private func GetExtendedClassDecl(extendDecl: ExtendDecl): Option<ClassLikeDecl> {
    if (let Some(extendedType) <- extendDecl.extendedType) {
        if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(extendedType.GetTy())) {
            return typeDecl as ClassLikeDecl
        }
    }
    return None
}

public func CreateThisRefForMockSupport(targetClass: ClassLikeDecl): RefExpr {
    let thisRef = CreateRefExpr(SrcIdentifier("this"), targetClass.GetTy(), INVALID_POSITION, ArrayList<Type>())
    thisRef.ref.target = targetClass
    return thisRef
}

// C++: Sema/Test/MockSupportManager.cpp:949-965.
public func CreateRefForFieldAccess(outerDecl: Decl, kind: AccessorKind): RefExpr {
    let outerClassDecl = (outerDecl as ClassDecl).getOrThrow()
    if (kind == AccessorKind.STATIC_FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_SETTER) {
        let refExpr = CreateRefExpr(outerClassDecl)
        if (let Some(generic) <- outerDecl.generic) {
            for (param in generic.typeParameters) {
                refExpr.instTys.add(param.GetTy().getOrThrow())
            }
        }
        return refExpr
    }
    return CreateThisRefForMockSupport(outerClassDecl)
}

public func IsFieldOrVariable(kind: AccessorKind): Bool {
    return kind == AccessorKind.FIELD_GETTER || kind == AccessorKind.FIELD_SETTER ||
        kind == AccessorKind.STATIC_FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_SETTER ||
        kind == AccessorKind.TOP_LEVEL_VARIABLE_GETTER || kind == AccessorKind.TOP_LEVEL_VARIABLE_SETTER
}

public func IsStaticField(kind: AccessorKind): Bool {
    return kind == AccessorKind.STATIC_FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_SETTER
}

public func IsTopLevelField(kind: AccessorKind): Bool {
    return kind == AccessorKind.TOP_LEVEL_VARIABLE_GETTER || kind == AccessorKind.TOP_LEVEL_VARIABLE_SETTER
}

public func ExtractLastDesugaredExpr(expr: Expr): Expr {
    var lastDesugaredExpr = expr
    while (let Some(desugared) <- lastDesugaredExpr.desugarExpr) {
        lastDesugaredExpr = desugared
    }
    return lastDesugaredExpr
}

public func IsStaticClassMember(decl: Option<Decl>): Bool {
    if (let Some(value) <- decl) {
        if (!value.TestAttr(Attribute.STATIC)) {
            return false
        }
        if (let Some(outer) <- value.outerDecl) {
            return outer.astKind == ASTKind.CLASS_DECL
        }
    }
    return false
}

public func IsClassLikeOrGeneric(ty: Ty): Bool {
    return ty.IsClassLike() || ty.IsGeneric()
}

private func ContainsDecl(decls: ArrayList<Decl>, target: Decl): Bool {
    for (decl in decls) {
        if (SameDecl(decl, target)) {
            return true
        }
    }
    return false
}

public class MockSupportManager {
    private let typeManager: TypeManager
    private let mockUtils: MockUtils
    private let usedInternalDecls: ArrayList<Decl> = ArrayList<Decl>()

    // C++: Sema/Test/MockSupportManager.cpp:49-53.
    public init(typeManager: TypeManager, mockUtils: MockUtils) {
        this.typeManager = typeManager
        this.mockUtils = mockUtils
    }

    public static func IsDeclOpenToMock(decl: Decl): Bool {
        return decl.TestAttr(Attribute.OPEN) && decl.TestAttr(Attribute.OPEN_TO_MOCK)
    }

    public static func DoesClassLikeSupportMocking(classLikeToCheck: ClassLikeDecl): Bool {
        if (classLikeToCheck.astKind == ASTKind.INTERFACE_DECL || classLikeToCheck.TestAttr(Attribute.MOCK_SUPPORTED)) {
            return true
        }
        if (!classLikeToCheck.TestAttr(Attribute.OPEN) && !classLikeToCheck.TestAttr(Attribute.ABSTRACT)) {
            return false
        }
        for (superDecl in classLikeToCheck.GetAllSuperDecls()) {
            for (member in superDecl.GetMemberDecls()) {
                if (member.TestAttr(Attribute.CONSTRUCTOR)) {
                    continue
                }
                if (!member.TestAttr(Attribute.OPEN) && !member.TestAttr(Attribute.ABSTRACT)) {
                    return false
                }
            }
        }
        return true
    }

    public static func NeedEraseAccessorTypes(decl: Decl): Bool {
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.linkage == Linkage.INTERNAL) {
                return false
            }
            if (decl.TestAttr(Attribute.HAS_INITIAL)) {
                return false
            }
        }
        return MockUtils.MayContainInternalTypes(decl.GetTy())
    }

    public func WriteUsedInternalDecl(decl: Decl): Unit {
        if (!ContainsDecl(usedInternalDecls, decl)) {
            usedInternalDecls.add(decl)
        }
    }

    public func IsUsedInternalDecl(decl: Decl): Bool {
        return ContainsDecl(usedInternalDecls, decl)
    }

    public func UsedInternalDecls(): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        for (decl in usedInternalDecls) {
            out.add(decl)
        }
        return out
    }

    public static func NeedToSearchCallsToReplaceWithAccessors(node: Node): Bool {
        if (let Some(decl) <- (node as Decl)) {
            if (MockUtils.IsMockAccessor(decl)) {
                return false
            }
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(outer) <- funcDecl.outerDecl) {
                    if (outer.TestAttr(Attribute.GENERIC) && IsStaticInitializer(funcDecl)) {
                        return false
                    }
                }
            }
        }
        return true
    }

    // C++: Sema/Test/MockSupportManager.cpp:1167-1180.
    public func IsMemberAccessOnThis(memberAccess: MemberAccess): Bool {
        if (let None <- memberAccess.baseExpr) {
            return false
        }
        if (let Some(refBaseExpr) <- (memberAccess.baseExpr.getOrThrow() as RefExpr)) {
            return refBaseExpr.isThis
        }
        return false
    }

    public static func MarkNodeMockSupportedIfNeeded(node: Node): Unit {
        if (let Some(decl) <- (node as Decl)) {
            if (!MockUtils.CanMock(node)) {
                return
            }
            if (let Some(_) <- (decl as ClassDecl)) {
                decl.EnableAttr(Attribute.MOCK_SUPPORTED)
                MakeOpenToMockIfNeeded(decl)
                return
            }
            let isFunctionOrProperty = decl.astKind == ASTKind.FUNC_DECL || decl.astKind == ASTKind.PROP_DECL
            if (isFunctionOrProperty && !MockUtils.IsMockAccessorRequired(decl) &&
                !decl.IsStaticOrGlobal() && !decl.TestAttr(Attribute.CONSTRUCTOR)) {
                decl.EnableAttr(Attribute.MOCK_SUPPORTED)
                MakeOpenToMockIfNeeded(decl)
                if (let Some(propMember) <- (decl as PropDecl)) {
                    if (let Some(getter) <- GetUsableGetterForProperty(propMember)) {
                        MakeOpenToMockIfNeeded(getter)
                    }
                    if (propMember.isVar) {
                        if (let Some(setter) <- GetUsableSetterForProperty(propMember)) {
                            MakeOpenToMockIfNeeded(setter)
                        }
                    }
                }
                return
            }
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                MarkFuncMockSupportedIfNeeded(funcDecl)
            }
        }
    }

    public static func MarkMockAccessorWithAttributes(decl: Decl, accessLevel: AccessLevel): Unit {
        decl.DisableAttr(Attribute.GENERIC_INSTANTIATED)
        decl.EnableAttr(Attribute.OPEN)
        decl.DisableAttr(Attribute.PRIVATE)
        decl.DisableAttr(Attribute.PROTECTED)
        decl.DisableAttr(Attribute.PUBLIC)
        decl.DisableAttr(Attribute.INTERNAL)
        decl.EnableAttr(GetAttrByAccessLevel(accessLevel))
        decl.EnableAttr(Attribute.GENERATED_TO_MOCK)
        decl.EnableAttr(Attribute.COMPILER_ADD)
        decl.EnableAttr(Attribute.IN_CLASSLIKE)
    }

    public func CollectDeclsToPrepare(decl: Decl, decls: DeclsToPrepare): Unit {
        for (member in decl.GetMemberDecls()) {
            if (let Some(propDecl) <- (member as PropDecl)) {
                decls.properties.add(propDecl)
            } else {
                CollectDeclsToPrepare(member, decls)
            }
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            if (HasDefaults(interfaceDecl)) {
                decls.interfacesWithDefaults.add(interfaceDecl)
                decls.classWithInterfaceDefaults.add((interfaceDecl, interfaceDecl, None))
            }
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            for (interfaceDecl in FindInterfacesWithDefaults(classDecl)) {
                decls.classWithInterfaceDefaults.add((classDecl, interfaceDecl, None))
            }
            return
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(classDecl) <- GetExtendedClassDecl(extendDecl)) {
                for (interfaceDecl in FindInterfacesWithDefaults(extendDecl)) {
                    decls.classWithInterfaceDefaults.add((classDecl, interfaceDecl, Some(extendDecl)))
                }
            }
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (!decl.IsStaticOrGlobal() && !funcDecl.TestAttr(Attribute.IN_EXTEND)) {
                return
            }
            if (decl.IsConst()) {
                return
            }
            if (decl.TestAnyAttr(Attribute.PRIVATE, Attribute.MAIN_ENTRY)) {
                return
            }
            decls.functions.add(funcDecl)
        }
    }
}
