package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::sema.GetUsableGetterForProperty
import cjcj::sema.GetUsableSetterForProperty
import cjcj::sema.SameTy
import cjcj::sema.TypeManager

foreign {
    func abort(): Unit
}

private let MOCKED_ACCESSOR_SUFFIX: String = "$ToMock"
private let GETTER_SUFFIX: String = "$get"
private let SETTER_SUFFIX: String = "$set"

public enum AccessorKind {
    | FIELD_GETTER
    | FIELD_SETTER
    | PROP
    | PROP_GETTER
    | PROP_SETTER
    | METHOD
    | TOP_LEVEL_FUNCTION
    | STATIC_METHOD
    | STATIC_PROP_GETTER
    | STATIC_PROP_SETTER
    | STATIC_FIELD_GETTER
    | STATIC_FIELD_SETTER
    | TOP_LEVEL_VARIABLE_GETTER
    | TOP_LEVEL_VARIABLE_SETTER
}

private func AccessorKindIndex(kind: AccessorKind): Int64 {
    return match (kind) {
        case AccessorKind.FIELD_GETTER => 0
        case AccessorKind.FIELD_SETTER => 1
        case AccessorKind.PROP => 2
        case AccessorKind.PROP_GETTER => 3
        case AccessorKind.PROP_SETTER => 4
        case AccessorKind.METHOD => 5
        case AccessorKind.TOP_LEVEL_FUNCTION => 6
        case AccessorKind.STATIC_METHOD => 7
        case AccessorKind.STATIC_PROP_GETTER => 8
        case AccessorKind.STATIC_PROP_SETTER => 9
        case AccessorKind.STATIC_FIELD_GETTER => 10
        case AccessorKind.STATIC_FIELD_SETTER => 11
        case AccessorKind.TOP_LEVEL_VARIABLE_GETTER => 12
        case AccessorKind.TOP_LEVEL_VARIABLE_SETTER => 13
    }
}

extend AccessorKind <: Equatable<AccessorKind> {
    public operator func ==(right: AccessorKind): Bool {
        return AccessorKindIndex(this) == AccessorKindIndex(right)
    }

    public operator func !=(right: AccessorKind): Bool {
        return !(this == right)
    }
}

private func AbortForInvalidMockAccessor(): Unit {
    unsafe {
        abort()
    }
}

public class MockUtils {
    public static let mockAccessorSuffix: String = MOCKED_ACCESSOR_SUFFIX
    public static let spyObjVarName: String = "spiedObjectRef"
    public static let spyCallMarkerVarName: String = "shouldReturnZeroForSpy"
    public static let defaultAccessorSuffix: String = "$Buddy"

    public init() {}

    public static func CanMock(node: Node): Bool {
        if (node.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC, Attribute.FROM_COMMON_PART)) {
            return false
        }
        if (let Some(decl) <- (node as Decl)) {
            if (let Some(genericDecl) <- decl.genericDecl) {
                if (!genericDecl.TestAttr(Attribute.MOCK_SUPPORTED)) {
                    return false
                }
            }
        }
        return true
    }

    public static func IsMockAccessor(decl: Decl): Bool {
        if (decl.astKind != ASTKind.FUNC_DECL && decl.astKind != ASTKind.PROP_DECL) {
            return false
        }
        if (decl.astKind == ASTKind.VAR_DECL) {
            if (let None <- decl.outerDecl) {
                return false
            }
        }
        return decl.TestAttr(Attribute.GENERATED_TO_MOCK)
    }

    public static func ListExistingMembers(decl: Decl): ArrayList<Decl> {
        let result = ArrayList<Decl>()
        for (member in decl.GetMemberDecls()) {
            result.add(member)
        }
        return result
    }

    public static func GetOuterDecl(decl: Decl): Option<Decl> {
        if (let Some(outer) <- decl.outerDecl) {
            if (let Some(extendDecl) <- (outer as ExtendDecl)) {
                if (let Some(extendedType) <- extendDecl.extendedType) {
                    return Ty.GetDeclOfTy(extendedType.GetTy())
                }
                return None
            }
            return outer
        }
        return None
    }

    public static func GetExtendedTypeDecl(decl: FuncDecl): Option<Decl> {
        if (!decl.TestAttr(Attribute.IN_EXTEND)) {
            return None
        }
        if (let Some(outer) <- decl.outerDecl) {
            if (let Some(extendDecl) <- (outer as ExtendDecl)) {
                if (let Some(extendedType) <- extendDecl.extendedType) {
                    return Ty.GetDeclOfTy(extendedType.GetTy())
                }
            }
        }
        return None
    }

    private static func HasVisitedTy(visited: ArrayList<Ty>, ty: Ty): Bool {
        for (value in visited) {
            if (SameTy(value, ty)) {
                return true
            }
        }
        return false
    }

    private static func ContainsInternalType(ty: Ty, visitedGenerics: ArrayList<Ty>): Bool {
        if (HasVisitedTy(visitedGenerics, ty)) {
            return false
        }
        if (let Some(decl) <- Ty.GetDeclOfTy(Some(ty))) {
            if (decl.linkage == Linkage.INTERNAL) {
                return true
            }
            if (let Some(outer) <- decl.outerDecl) {
                if (let Some(outerTy) <- outer.GetTy()) {
                    if (ContainsInternalType(outerTy, visitedGenerics)) {
                        return true
                    }
                }
            }
        }
        for (paramTy in ty.typeArgs) {
            if (ContainsInternalType(paramTy, visitedGenerics)) {
                return true
            }
        }
        if (let Some(genericTy) <- (ty as GenericsTy)) {
            visitedGenerics.add(ty)
            for (upperBound in genericTy.upperBounds) {
                if (ContainsInternalType(upperBound, visitedGenerics)) {
                    return true
                }
            }
        }
        return false
    }

    public static func MayContainInternalTypes(ty: Option<Ty>): Bool {
        if (let Some(value) <- ty) {
            return ContainsInternalType(value, ArrayList<Ty>())
        }
        return false
    }

    public static func MayContainInternalTypes(ty: Ty): Bool {
        return ContainsInternalType(ty, ArrayList<Ty>())
    }

    public static func CreateType(ty: Ty): Type {
        let typeNode = Type()
        typeNode.SetTy(ty)
        return typeNode
    }

    public static func CreateTypeCast(selector: Expr, castTy: Ty, createMatchedBranch: (VarDecl) -> Expr,
        otherwiseBranch: Expr, ty: Ty): Expr {
        let varPattern = CreateVarPattern("v-compiler", Some(castTy))
        let matchedBranch = createMatchedBranch(varPattern.varDecl.getOrThrow())
        let matchCases = ArrayList<MatchCase>()
        let typePattern = CreateTypePattern(varPattern, MockUtils.CreateType(castTy), selector)
        typePattern.matchBeforeRuntime = false
        matchCases.add(CreateMatchCase(typePattern, matchedBranch))
        matchCases.add(CreateMatchCase(WildcardPattern(), otherwiseBranch))
        return CreateMatchExpr(selector, matchCases, ty)
    }

    public static func EraseFuncTypes(funcTy: FuncTy, typeManager: TypeManager): FuncTy {
        let paramTys = ArrayList<Ty>()
        for (_ in funcTy.paramTys) {
            paramTys.add(typeManager.GetAnyTy())
        }
        return typeManager.GetFunctionTy(paramTys.toArray(), typeManager.GetAnyTy())
    }

    public static func IsMockAccessorRequired(decl: Decl): Bool {
        if (decl.astKind == ASTKind.VAR_DECL) {
            if (let Some(_) <- decl.outerDecl) {
                return true
            }
        }
        if (decl.astKind != ASTKind.FUNC_DECL && decl.astKind != ASTKind.PROP_DECL) {
            return false
        }
        if (decl.TestAttr(Attribute.OPEN) || decl.TestAttr(Attribute.ABSTRACT) ||
            decl.TestAttr(Attribute.CONSTRUCTOR) || decl.TestAttr(Attribute.STATIC)) {
            return false
        }
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.astKind == ASTKind.INTERFACE_DECL) {
                return false
            }
        }
        if (decl.TestAttr(Attribute.PUBLIC) || decl.TestAttr(Attribute.PROTECTED)) {
            return false
        }
        return true
    }

    public static func BuildArgumentList(decl: Decl): String {
        if (let Some(genericDecl) <- decl.genericDecl) {
            return BuildArgumentList(genericDecl)
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                if (!body.paramLists.isEmpty()) {
                    let parts = ArrayList<String>()
                    for (param in body.paramLists[0].params) {
                        if (let Some(paramTy) <- param.GetTy()) {
                            var argumentTy = paramTy
                            if (let Some(paramTyDecl) <- Ty.GetDeclOfTy(Some(paramTy))) {
                                if (let Some(genericDecl) <- paramTyDecl.genericDecl) {
                                    if (let Some(genericTy) <- genericDecl.GetTy()) {
                                        argumentTy = genericTy
                                    }
                                }
                            }
                            parts.add(argumentTy.String())
                        } else {
                            parts.add(TypeManager.GetInvalidTy().String())
                        }
                    }
                    return "(" + JoinStrings(parts, ",") + ")"
                }
            }
        }
        return ""
    }

    public static func BuildMockAccessorIdentifier(originalDecl: Decl, kind: AccessorKind,
        forErased!: Bool = false): String {
        let additionalSuffix = match (kind) {
            case AccessorKind.FIELD_GETTER => GETTER_SUFFIX
            case AccessorKind.STATIC_FIELD_GETTER => GETTER_SUFFIX
            case AccessorKind.TOP_LEVEL_VARIABLE_GETTER => GETTER_SUFFIX
            case AccessorKind.FIELD_SETTER => SETTER_SUFFIX
            case AccessorKind.STATIC_FIELD_SETTER => SETTER_SUFFIX
            case AccessorKind.TOP_LEVEL_VARIABLE_SETTER => SETTER_SUFFIX
            case _ => ""
        }
        let argumentsList = if (forErased) { BuildArgumentList(originalDecl) } else { "" }
        var out = originalDecl.identifier.Val() + argumentsList + additionalSuffix + MOCKED_ACCESSOR_SUFFIX
        if (let Some(outer) <- originalDecl.outerDecl) {
            out += "_" + outer.identifier.Val()
        }
        return out
    }

    public static func GetOriginalIdentifierOfMockAccessor(decl: Decl): String {
        if (!IsMockAccessor(decl)) {
            return decl.identifier.Val()
        }
        var suffixSize = MOCKED_ACCESSOR_SUFFIX.size
        if (let Some(outer) <- decl.outerDecl) {
            suffixSize += 1 + outer.identifier.Val().size
        }
        if (decl.identifier.Val().size <= suffixSize) {
            return decl.identifier.Val()
        }
        return decl.identifier.Val()[0..decl.identifier.Val().size - suffixSize]
    }

    public static func GetOriginalIdentifierOfAccessor(decl: FuncDecl): String {
        let accessorOwner = if (let Some(propDecl) <- decl.propDecl) { propDecl } else { decl }
        var originalId = GetOriginalIdentifierOfMockAccessor(accessorOwner)
        if (originalId.endsWith(GETTER_SUFFIX)) {
            originalId = originalId[0..originalId.size - GETTER_SUFFIX.size]
        } else if (originalId.endsWith(SETTER_SUFFIX)) {
            originalId = originalId[0..originalId.size - SETTER_SUFFIX.size]
        }
        return originalId
    }

    public static func ComputeAccessorKind(accessorDecl: FuncDecl): AccessorKind {
        if (let Some(propDecl) <- accessorDecl.propDecl) {
            if (let Some(getter) <- GetUsableGetterForProperty(propDecl)) {
                if (SameDecl(accessorDecl, getter)) {
                    return if (accessorDecl.TestAttr(Attribute.STATIC)) {
                        AccessorKind.STATIC_PROP_GETTER
                    } else {
                        AccessorKind.PROP_GETTER
                    }
                }
            }
            if (propDecl.isVar) {
                if (let Some(setter) <- GetUsableSetterForProperty(propDecl)) {
                    if (SameDecl(accessorDecl, setter)) {
                        return if (accessorDecl.TestAttr(Attribute.STATIC)) {
                            AccessorKind.STATIC_PROP_SETTER
                        } else {
                            AccessorKind.PROP_SETTER
                        }
                    }
                }
            }
            AbortForInvalidMockAccessor()
            return AccessorKind.PROP
        }
        let name = accessorDecl.identifier.Val()
        if (name.contains(GETTER_SUFFIX + MOCKED_ACCESSOR_SUFFIX)) {
            if (accessorDecl.TestAttr(Attribute.STATIC)) {
                return AccessorKind.STATIC_FIELD_GETTER
            }
            if (accessorDecl.TestAttr(Attribute.GLOBAL)) {
                return AccessorKind.TOP_LEVEL_VARIABLE_GETTER
            }
            return AccessorKind.FIELD_GETTER
        }
        if (name.contains(SETTER_SUFFIX + MOCKED_ACCESSOR_SUFFIX)) {
            if (accessorDecl.TestAttr(Attribute.STATIC)) {
                return AccessorKind.STATIC_FIELD_SETTER
            }
            if (accessorDecl.TestAttr(Attribute.GLOBAL)) {
                return AccessorKind.TOP_LEVEL_VARIABLE_SETTER
            }
            return AccessorKind.FIELD_SETTER
        }
        if (accessorDecl.TestAttr(Attribute.GLOBAL)) {
            return AccessorKind.TOP_LEVEL_FUNCTION
        }
        if (accessorDecl.TestAttr(Attribute.STATIC)) {
            return AccessorKind.STATIC_METHOD
        }
        return AccessorKind.METHOD
    }

    public static func IsGeneratedGetter(kind: AccessorKind): Bool {
        return kind == AccessorKind.FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_GETTER ||
            kind == AccessorKind.TOP_LEVEL_VARIABLE_GETTER
    }

    private static func FindMemberDeclByIdentifier(outerDecl: Decl, identifier: String): Option<Decl> {
        for (member in outerDecl.GetMemberDecls()) {
            if (member.identifier.Val() == identifier) {
                return Some(member)
            }
        }
        return None
    }

    private static func FindGlobalDeclByIdentifier(file: File, identifier: String): Option<Decl> {
        for (decl in file.decls) {
            if (decl.identifier.Val() == identifier) {
                return Some(decl)
            }
        }
        if (let Some(pkg) <- file.curPackage) {
            for (pkgFile in pkg.files) {
                for (decl in pkgFile.decls) {
                    if (decl.identifier.Val() == identifier) {
                        return Some(decl)
                    }
                }
            }
        }
        return None
    }

    public static func FindAccessor(outerClass: ClassDecl, member: Decl, kind: AccessorKind): Option<Decl> {
        if (member.TestAttr(Attribute.IN_EXTEND)) {
            return None
        }
        var accessorIdentifier = BuildMockAccessorIdentifier(member, kind)
        if (let Some(_) <- (member as FuncDecl)) {
            accessorIdentifier += BuildArgumentList(member)
        }
        for (superDecl in outerClass.GetAllSuperDecls()) {
            if (superDecl.astKind != ASTKind.CLASS_DECL) {
                continue
            }
            if (let Some(accessorDecl) <- FindMemberDeclByIdentifier(superDecl, accessorIdentifier)) {
                return accessorDecl
            }
        }
        return None
    }

    public static func FindAccessorForMemberAccess(ty: Option<Ty>, resolvedMember: Option<Decl>,
        kind: AccessorKind): Option<Decl> {
        if (let None <- resolvedMember) {
            return None
        }
        let member = resolvedMember.getOrThrow()
        if (!IsMockAccessorRequired(member)) {
            return None
        }
        if (let Some(baseDecl) <- Ty.GetDeclOfTy(ty)) {
            if (let Some(baseClass) <- (baseDecl as ClassDecl)) {
                if (!baseClass.TestAttr(Attribute.MOCK_SUPPORTED)) {
                    return None
                }
                var outerClass = baseClass
                if (!baseClass.TestAttr(Attribute.GENERIC)) {
                    if (let Some(genericDecl) <- baseClass.genericDecl) {
                        if (let Some(genericClass) <- (genericDecl as ClassDecl)) {
                            outerClass = genericClass
                        }
                    }
                }
                return FindAccessor(outerClass, member, kind)
            }
        }
        return None
    }

    public static func FindTopLevelAccessor(member: Decl, kind: AccessorKind): Option<FuncDecl> {
        if (let Some(file) <- member.curFile) {
            let accessorIdentifier = BuildMockAccessorIdentifier(member, kind)
            if (let Some(decl) <- FindGlobalDeclByIdentifier(file, accessorIdentifier)) {
                return decl as FuncDecl
            }
        }
        return None
    }

    public static func FindAccessor(memberAccess: Option<MemberAccess>, target: Option<Decl>,
        kind: AccessorKind): Option<FuncDecl> {
        if (kind == AccessorKind.FIELD_GETTER || kind == AccessorKind.FIELD_SETTER ||
            kind == AccessorKind.STATIC_FIELD_GETTER || kind == AccessorKind.STATIC_FIELD_SETTER) {
            if (let Some(ma) <- memberAccess) {
                if (let Some(baseExpr) <- ma.baseExpr) {
                    if (let Some(accessorDecl) <- FindAccessorForMemberAccess(baseExpr.GetTy(), target, kind)) {
                        return accessorDecl as FuncDecl
                    }
                }
            } else {
                AbortForInvalidMockAccessor()
            }
            return None
        }
        if (kind == AccessorKind.TOP_LEVEL_VARIABLE_GETTER || kind == AccessorKind.TOP_LEVEL_VARIABLE_SETTER) {
            if (let Some(member) <- target) {
                return FindTopLevelAccessor(member, kind)
            }
        }
        AbortForInvalidMockAccessor()
        return None
    }

    public static func IsGetterForMutField(accessorDecl: FuncDecl): Bool {
        let accessorKind = ComputeAccessorKind(accessorDecl)
        if (accessorKind != AccessorKind.FIELD_GETTER &&
            accessorKind != AccessorKind.STATIC_FIELD_GETTER &&
            accessorKind != AccessorKind.TOP_LEVEL_VARIABLE_GETTER) {
            return false
        }
        let getterDeclId = accessorDecl.identifier.Val()
        let setterDeclId = getterDeclId.replace(GETTER_SUFFIX + MOCKED_ACCESSOR_SUFFIX,
            SETTER_SUFFIX + MOCKED_ACCESSOR_SUFFIX)
        if (getterDeclId == setterDeclId) {
            return false
        }
        if (let Some(outer) <- accessorDecl.outerDecl) {
            return FindMemberDeclByIdentifier(outer, setterDeclId).isSome()
        }
        if (let Some(file) <- accessorDecl.curFile) {
            return FindGlobalDeclByIdentifier(file, setterDeclId).isSome()
        }
        return false
    }

    public static func FindMockGlobalDecl(decl: Decl, name: String): Option<Decl> {
        if (let Some(file) <- decl.curFile) {
            return FindGlobalDeclByIdentifier(file, name + MOCKED_ACCESSOR_SUFFIX)
        }
        return None
    }

    public static func GetForeignAccessorName(decl: FuncDecl): String {
        return decl.fullPackageName + "$" + decl.identifier.Val()
    }
}

private func GetVarDeclAccessorKinds(varDecl: Decl): (AccessorKind, AccessorKind) {
    if (varDecl.TestAttr(Attribute.STATIC)) {
        return (AccessorKind.STATIC_FIELD_GETTER, AccessorKind.STATIC_FIELD_SETTER)
    }
    if (varDecl.TestAttr(Attribute.GLOBAL)) {
        return (AccessorKind.TOP_LEVEL_VARIABLE_GETTER, AccessorKind.TOP_LEVEL_VARIABLE_SETTER)
    }
    return (AccessorKind.FIELD_GETTER, AccessorKind.FIELD_SETTER)
}

public func GetVarDeclSetterAccessorKind(varDecl: Decl): AccessorKind {
    return GetVarDeclAccessorKinds(varDecl)[1]
}

public func GetVarDeclGetterAccessorKind(varDecl: Decl): AccessorKind {
    return GetVarDeclAccessorKinds(varDecl)[0]
}
