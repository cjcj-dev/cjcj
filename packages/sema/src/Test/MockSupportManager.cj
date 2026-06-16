package cangjie_compiler::sema.Test

import std.collection.*
import cangjie_compiler::ast.*

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

public class MockSupportManager {
    public init() {}

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
                    if (!propMember.getters.isEmpty()) {
                        MakeOpenToMockIfNeeded(propMember.getters[0])
                    }
                    if (propMember.isVar && !propMember.setters.isEmpty()) {
                        MakeOpenToMockIfNeeded(propMember.setters[0])
                    }
                }
                return
            }
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                MarkFuncMockSupportedIfNeeded(funcDecl)
            }
        }
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

public func SelfhostPortStatus_Test_MockSupportManager(): Bool {
    return true
}
