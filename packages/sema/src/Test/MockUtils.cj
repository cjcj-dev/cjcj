package cjcj::sema.Test

import std.collection.*
import cjcj::ast.*
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::sema.AddArrayLitConstructor
import cjcj::sema.CreateThrowException
import cjcj::sema.GenerateGetTypeForTypeParamIntrinsic
import cjcj::sema.GetUsableGetterForProperty
import cjcj::sema.GetUsableSetterForProperty
import cjcj::sema.GenerateTypeMapping
import cjcj::sema.SameTy
import cjcj::sema.TypeSubst
import cjcj::sema.TypeManager
import cjcj::utils.{CLASS_EXCEPTION, CJC_ABORT, CJC_ASSERT, GET_TYPE_FOR_TYPE_PARAMETER_FUNC_NAME,
    GetRootPackageName, OBJECT_NAME, STD_LIB_ARRAY, STD_LIB_OPTION, STD_LIB_STRING, TOSTRING_NAME}
import cjcj::utils.DynamicCast

foreign {
    func abort(): Unit
}

private let MOCKED_ACCESSOR_SUFFIX: String = "$ToMock"
private let GETTER_SUFFIX: String = "$get"
private let SETTER_SUFFIX: String = "$set"
private let ZERO_VALUE_INTRINSIC_NAME: String = "zeroValue"

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
    // C++: Sema/Test/MockUtils.h:50.
    public var isWalking: Bool = false
    public static let mockAccessorSuffix: String = MOCKED_ACCESSOR_SUFFIX
    public static let spyObjVarName: String = "spiedObjectRef"
    public static let spyCallMarkerVarName: String = "shouldReturnZeroForSpy"
    public static let defaultAccessorSuffix: String = "$Buddy"

    // C++: Sema/Test/MockUtils.h:104-106.
    private let globalsByPackage: HashMap<Node, HashMap<String, Decl>> =
        HashMap<Node, HashMap<String, Decl>>()
    private let globalsByFile: HashMap<Node, HashMap<String, Decl>> =
        HashMap<Node, HashMap<String, Decl>>()
    private let localsByOuter: HashMap<Decl, HashMap<String, Decl>> =
        HashMap<Decl, HashMap<String, Decl>>()

    // C++: Sema/Test/MockUtils.h:163-175.
    private let importManager: SemaImportManager
    private let typeManager: TypeManager
    // C++ MockUtils.h:163,233-235: MockSupportManager has friend access.
    internal let mangler: BaseMangler
    // C++ MockUtils.h:163-175,233-235: these fields are private but MockManager,
    // MockSupportManager, and TestManager are friends.
    internal var getTypeForTypeParamDecl: Option<FuncDecl> = None
    internal var isSubtypeTypesDecl: Option<FuncDecl> = None
    internal var arrayDecl: Option<StructDecl> = None
    internal var stringDecl: Option<StructDecl> = None
    internal var optionDecl: Option<EnumDecl> = None
    internal var toStringDecl: Option<InheritableDecl> = None
    internal var objectDecl: Option<ClassDecl> = None
    internal var zeroValueDecl: Option<FuncDecl> = None
    internal var exceptionClassDecl: Option<ClassDecl> = None

    // C++: Sema/Test/MockUtils.cpp:43-46.
    public init(importManager: SemaImportManager, typeManager: TypeManager, mangler: BaseMangler) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.mangler = mangler
    }

    // C++: Sema/Test/MockUtils.cpp:48-57.
    public func LoadStdDecls(): Unit {
        arrayDecl = importManager.GetCoreDecl<StructDecl>(STD_LIB_ARRAY)
        stringDecl = importManager.GetCoreDecl<StructDecl>(STD_LIB_STRING)
        optionDecl = importManager.GetCoreDecl<EnumDecl>(STD_LIB_OPTION)
        toStringDecl = importManager.GetCoreDecl<InheritableDecl>(TOSTRING_NAME)
        objectDecl = importManager.GetCoreDecl<ClassDecl>(OBJECT_NAME)
        zeroValueDecl = importManager.GetCoreDecl<FuncDecl>(ZERO_VALUE_INTRINSIC_NAME)
        exceptionClassDecl = importManager.GetCoreDecl<ClassDecl>(CLASS_EXCEPTION)
    }

    // C++: Sema/Test/MockUtils.cpp:64-67.
    public func Mangle(decl: Decl): String {
        return mangler.Mangle(decl)
    }

    // C++: Sema/Test/MockUtils.h:214-222.
    public func GetGenericDecl(decl: Decl): Decl {
        if (let Some(genericDecl) <- decl.genericDecl) {
            return genericDecl
        }
        return decl
    }

    // C++: Sema/Test/MockUtils.h:61-66.
    public func WrapTy2CPointer(ty: Ty): PointerTy {
        return typeManager.GetPointerTy(ty)
    }

    // C++: Sema/Test/MockUtils.cpp:69-87.
    public func WrapCallArgsIntoArray(mockedFunc: FuncDecl): ArrayLit {
        let mockedMethodArgRefs = ArrayList<Expr>()
        for (param in mockedFunc.funcBody.getOrThrow().paramLists[0].params) {
            let paramRef = RefExpr()
            paramRef.ref.identifier = param.identifier
            paramRef.ref.target = param
            paramRef.SetTy(param.GetTy().getOrThrow())
            paramRef.curFile = mockedFunc.curFile
            mockedMethodArgRefs.add(paramRef)
        }
        let baseTy = typeManager.GetStructTy(arrayDecl.getOrThrow(), [typeManager.GetAnyTy()])
        let argRefsArray = CreateArrayLit(mockedMethodArgRefs, baseTy)
        AddArrayLitConstructor(argRefsArray)
        argRefsArray.curFile = mockedFunc.curFile
        return argRefsArray
    }

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

    // C++: Sema/Test/MockUtils.cpp:142-154.
    public func DemandIndex(pkg: Package): HashMap<String, Decl> {
        if (let Some(index) <- globalsByPackage.get(pkg)) {
            return index
        }
        let index = HashMap<String, Decl>()
        globalsByPackage[pkg] = index
        for (file in pkg.files) {
            for (decl in file.decls) {
                index[decl.identifier.Val()] = decl
            }
        }
        return index
    }

    // C++: Sema/Test/MockUtils.cpp:156-166.
    public func DemandIndex(file: File): HashMap<String, Decl> {
        if (let Some(index) <- globalsByFile.get(file)) {
            return index
        }
        let index = HashMap<String, Decl>()
        globalsByFile[file] = index
        for (decl in file.decls) {
            index[decl.identifier.Val()] = decl
        }
        return index
    }

    // C++: Sema/Test/MockUtils.cpp:168-181.
    public func DemandIndex(decl: Decl): HashMap<String, Decl> {
        if (let Some(index) <- localsByOuter.get(decl)) {
            return index
        }
        let index = HashMap<String, Decl>()
        localsByOuter[decl] = index
        for (memberDecl in decl.GetMemberDecls()) {
            index[memberDecl.identifier.Val()] = memberDecl
            if (let Some(funcDecl) <- (memberDecl as FuncDecl)) {
                index[memberDecl.identifier.Val() + BuildArgumentList(funcDecl)] = memberDecl
            }
        }
        return index
    }

    // C++: Sema/Test/MockUtils.h:83-95.
    public func FindGlobalDecl<T>(file: File, identifier: String): Option<T> where T <: Decl {
        if (let Some(decl) <- DemandIndex(file).get(identifier)) {
            return DynamicCast<T>(decl)
        }
        return None
    }

    // C++: Sema/Test/MockUtils.h:90-95.
    public func FindGlobalDecl<T>(pkg: Package, identifier: String): Option<T> where T <: Decl {
        if (let Some(decl) <- DemandIndex(pkg).get(identifier)) {
            return DynamicCast<T>(decl)
        }
        return None
    }

    // C++: Sema/Test/MockUtils.h:97-102.
    public func FindMemberDecl<T>(decl: Decl, identifier: String): Option<T> where T <: Decl {
        if (let Some(member) <- DemandIndex(decl).get(identifier)) {
            return DynamicCast<T>(member)
        }
        return None
    }

    // C++: Sema/Test/MockUtils.cpp:183-216.
    public func AttachGeneratedDecl(decl: Decl): Unit {
        CJC_ASSERT(!isWalking)
        decl.EnableAttr(Attribute.GENERATED_TO_MOCK)
        if (let Some(outerDecl) <- decl.outerDecl) {
            let index = DemandIndex(outerDecl)
            index[decl.identifier.Val()] = decl
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                index[decl.identifier.Val() + BuildArgumentList(funcDecl)] = decl
            }
            if (let Some(classDecl) <- (outerDecl as ClassDecl)) {
                classDecl.body.getOrThrow().decls.add(decl)
                return
            }
            if (let Some(interfaceDecl) <- (outerDecl as InterfaceDecl)) {
                interfaceDecl.body.getOrThrow().decls.add(decl)
                return
            }
            if (let Some(extendDecl) <- (outerDecl as ExtendDecl)) {
                extendDecl.members.add(decl)
                return
            }
            CJC_ABORT()
        }
        let curFile = decl.curFile.getOrThrow()
        if (!decl.TestAttr(Attribute.PRIVATE) && !decl.TestAttr(Attribute.INTERNAL) &&
            !decl.TestAttr(Attribute.PROTECTED) && !decl.TestAttr(Attribute.PUBLIC)) {
            decl.EnableAttr(Attribute.PUBLIC)
        }
        DemandIndex(curFile)[decl.identifier.Val()] = decl
        DemandIndex(curFile.curPackage.getOrThrow())[decl.identifier.Val()] = decl
        curFile.decls.add(decl)
    }

    // C++: Sema/Test/MockUtils.cpp:218-227.
    public func AttachGeneratedDecl(decl: Decl, originPackage: Package): Unit {
        let originFile = originPackage.files[0]
        decl.curFile = originFile
        decl.begin = originFile.GetBegin()
        decl.end = originFile.GetBegin()
        decl.fullPackageName = originPackage.fullPackageName
        decl.moduleName = GetRootPackageName(originPackage.fullPackageName)
        AttachGeneratedDecl(decl)
    }

    // C++: Sema/Test/MockUtils.cpp:229-238.
    public func AttachGeneratedDecl(decl: Decl, originDecl: Decl): Unit {
        decl.curFile = originDecl.curFile
        decl.fullPackageName = originDecl.fullPackageName
        decl.moduleName = originDecl.moduleName
        decl.begin = originDecl.begin
        decl.end = originDecl.end
        AttachGeneratedDecl(decl)
    }

    public func FindAccessor(outerClass: ClassDecl, member: Decl, kind: AccessorKind): Option<Decl> {
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
            if (let Some(accessorDecl) <- FindMemberDecl<Decl>(superDecl, accessorIdentifier)) {
                return accessorDecl
            }
        }
        return None
    }

    public func FindAccessorForMemberAccess(ty: Option<Ty>, resolvedMember: Option<Decl>,
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

    public func FindTopLevelAccessor(member: Decl, kind: AccessorKind): Option<FuncDecl> {
        if (let Some(file) <- member.curFile) {
            let accessorIdentifier = BuildMockAccessorIdentifier(member, kind)
            if (let Some(decl) <- FindGlobalDecl<FuncDecl>(file, accessorIdentifier)) {
                return decl as FuncDecl
            }
        }
        return None
    }

    public func FindAccessor(memberAccess: Option<MemberAccess>, target: Option<Decl>,
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

    public func IsGetterForMutField(accessorDecl: FuncDecl): Bool {
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
            return FindMemberDecl<Decl>(outer, setterDeclId).isSome()
        }
        if (let Some(file) <- accessorDecl.curFile) {
            return FindGlobalDecl<Decl>(file, setterDeclId).isSome()
        }
        return false
    }

    public func FindMockGlobalDecl(decl: Decl, name: String): Option<Decl> {
        if (let Some(file) <- decl.curFile) {
            return FindGlobalDecl<Decl>(file, name + MOCKED_ACCESSOR_SUFFIX)
        }
        return None
    }

    public static func GetForeignAccessorName(decl: FuncDecl): String {
        return decl.fullPackageName + "$" + decl.identifier.Val()
    }

    // C++: Sema/Test/MockUtils.cpp:757-766.
    public func CreateRefExprWithInstTys(target: Decl, instTys: ArrayList<Ty>, refName: String,
        curFile: File): RefExpr {
        let refExpr = CreateRefExpr(target)
        refExpr.ref.identifier = SrcIdentifier(refName)
        refExpr.curFile = curFile
        refExpr.SetTy(typeManager.GetInstantiatedTy(target.GetTy().getOrThrow(),
            GenerateTypeMapping(target, instTys)))
        for (instTy in instTys) {
            refExpr.instTys.add(instTy)
        }
        return refExpr
    }

    // C++: Sema/Test/MockUtils.cpp:768-787.
    public func CreateDeclBasedReferenceExpr(target: Decl, instTys: ArrayList<Ty>, refName: String,
        curFile: File): RefExpr {
        var ty: Option<Ty> = None
        if (target.astKind == ASTKind.FUNC_DECL || target.astKind == ASTKind.VAR_DECL) {
            let paramTys = ArrayList<Ty>()
            for (idx in 0..instTys.size - 1) {
                paramTys.add(instTys[idx])
            }
            ty = typeManager.GetFunctionTy(paramTys.toArray(), instTys[instTys.size - 1])
        } else if (target.astKind == ASTKind.CLASS_DECL) {
            ty = typeManager.GetClassTy((target as ClassDecl).getOrThrow(), instTys.toArray())
        }
        return CreateRefExprWithInstTys(target, ty.getOrThrow().typeArgs, refName, curFile)
    }

    // C++: Sema/Test/MockUtils.cpp:745-755.
    public func CreateZeroValue(ty: Ty, curFile: File): CallExpr {
        let zeroValueCall = CallExpr()
        let instTys = ArrayList<Ty>()
        instTys.add(ty)
        zeroValueCall.baseFunc = CreateDeclBasedReferenceExpr(zeroValueDecl.getOrThrow(), instTys,
            ZERO_VALUE_INTRINSIC_NAME, curFile)
        zeroValueCall.SetTy(ty)
        zeroValueCall.callKind = CallKind.CALL_INTRINSIC_FUNCTION
        zeroValueCall.resolvedFunction = zeroValueDecl
        zeroValueCall.curFile = curFile
        return zeroValueCall
    }

    // C++: Sema/Test/MockUtils.cpp:789-796.
    public func CreateThrowExpr(message: String, curFile: File): Expr {
        let exceptionCallArgs = ArrayList<Expr>()
        let messageExpr = CreateLitConstExpr(LitConstKind.STRING, message, stringDecl.getOrThrow().GetTy().getOrThrow())
        messageExpr.curFile = curFile
        exceptionCallArgs.add(messageExpr)
        return CreateThrowException(exceptionClassDecl.getOrThrow(), exceptionCallArgs, curFile, typeManager)
    }

    // C++: Sema/Test/MockUtils.cpp:820-828.
    public func CreateTypeCastOrThrow(selector: Expr, castTy: Ty, message: String): Expr {
        let createValueBranch = { varDecl: VarDecl => CreateRefExpr(varDecl) }
        let throwExpression = CreateThrowExpr(message, selector.curFile.getOrThrow())
        return CreateTypeCast(selector, castTy, createValueBranch, throwExpression, castTy)
    }

    // C++: Sema/Test/MockUtils.cpp:830-837.
    public func CreateTypeCastOrZeroValue(selector: Expr, castTy: Ty): Expr {
        let createValueBranch = { varDecl: VarDecl => CreateRefExpr(varDecl) }
        let zeroValueExpression = CreateZeroValue(castTy, selector.curFile.getOrThrow())
        return CreateTypeCast(selector, castTy, createValueBranch, zeroValueExpression, castTy)
    }

    // C++: Sema/Test/MockUtils.cpp:532-546.
    public func CreateGetTypeForTypeParameterCall(genericParam: GenericParamDecl): Expr {
        let funcDecl = getTypeForTypeParamDecl.getOrThrow()
        let funcTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let args = ArrayList<FuncArg>()
        let refExpr = CreateRefExpr(funcDecl)
        refExpr.instTys.add(genericParam.GetTy().getOrThrow())
        refExpr.curFile = genericParam.curFile
        let res = CreateCallExpr(refExpr, args, Some(funcDecl), Some(funcTy.retTy),
            CallKind.CALL_INTRINSIC_FUNCTION)
        res.curFile = genericParam.curFile
        return res
    }

    // C++: Sema/Test/MockUtils.cpp:548-572.
    public func WrapCallTypeArgsIntoArray(decl: Decl): Expr {
        let getTypeCalls = ArrayList<Expr>()
        if (let Some(outerDecl) <- decl.outerDecl) {
            if (let Some(generic) <- outerDecl.GetGeneric()) {
                for (genericParam in generic.typeParameters) {
                    getTypeCalls.add(CreateGetTypeForTypeParameterCall(genericParam))
                }
            }
        }
        if (let Some(generic) <- decl.GetGeneric()) {
            for (genericParam in generic.typeParameters) {
                getTypeCalls.add(CreateGetTypeForTypeParameterCall(genericParam))
            }
        }
        let baseTy = typeManager.GetStructTy(arrayDecl.getOrThrow(),
            [toStringDecl.getOrThrow().GetTy().getOrThrow()])
        let arrayLitOfGetTypeCalls = CreateArrayLit(getTypeCalls, baseTy)
        AddArrayLitConstructor(arrayLitOfGetTypeCalls)
        arrayLitOfGetTypeCalls.curFile = decl.curFile
        return arrayLitOfGetTypeCalls
    }

    // C++: Sema/Test/MockUtils.cpp:735-743.
    public func SetGetTypeForTypeParamDecl(pkg: Package): Unit {
        getTypeForTypeParamDecl = FindGlobalDecl<FuncDecl>(pkg.files[0], GET_TYPE_FOR_TYPE_PARAMETER_FUNC_NAME)
        if (getTypeForTypeParamDecl.isNone()) {
            let generatedDecl = GenerateGetTypeForTypeParamIntrinsic(pkg, typeManager)
            getTypeForTypeParamDecl = generatedDecl
            DemandIndex(pkg)[GET_TYPE_FOR_TYPE_PARAMETER_FUNC_NAME] = generatedDecl
            DemandIndex(pkg.files[0])[GET_TYPE_FOR_TYPE_PARAMETER_FUNC_NAME] = generatedDecl
        }
    }

    // C++: Sema/Test/MockUtils.cpp:691-733.
    public func AddGenericIfNeeded(originalDecl: Decl, mockedDecl: Decl): ArrayList<Ty> {
        let typeParamTys = ArrayList<Ty>()
        if (!originalDecl.TestAttr(Attribute.GENERIC)) {
            return typeParamTys
        }
        mockedDecl.EnableAttr(Attribute.GENERIC)
        let originalFuncDecl = originalDecl as FuncDecl
        let generic = if (let Some(funcDecl) <- originalFuncDecl) {
            funcDecl.funcBody.getOrThrow().generic.getOrThrow()
        } else {
            originalDecl.generic.getOrThrow()
        }
        let newGeneric = CloneGeneric(generic)
        for (typeParam in newGeneric.typeParameters) {
            typeParam.outerDecl = mockedDecl
            typeParam.SetTy(typeManager.GetGenericsTy(typeParam))
            typeParam.fullPackageName = mockedDecl.fullPackageName
            typeParam.curFile = mockedDecl.curFile
            typeParam.DisableAttr(Attribute.IMPORTED)
            typeParamTys.add(typeParam.GetTy().getOrThrow())
        }
        if (originalFuncDecl.isSome()) {
            let mockedFuncDecl = (mockedDecl as FuncDecl).getOrThrow()
            CJC_ASSERT(mockedFuncDecl.funcBody.isSome())
            let mockedFuncBody = mockedFuncDecl.funcBody.getOrThrow()
            if (let Some(retType) <- mockedFuncBody.retType) {
                UpdateRefTypesTarget(retType, generic, newGeneric)
            }
            mockedFuncBody.generic = newGeneric
        } else {
            mockedDecl.generic = newGeneric
            if (let Some(classDecl) <- (mockedDecl as ClassDecl)) {
                mockedDecl.SetTy(typeManager.GetClassTy(classDecl, typeParamTys.toArray()))
            } else if (let Some(interfaceDecl) <- (mockedDecl as InterfaceDecl)) {
                mockedDecl.SetTy(typeManager.GetInterfaceTy(interfaceDecl, typeParamTys.toArray()))
            }
        }
        return typeParamTys
    }

    public static func PrependFuncGenericSubst(originalGeneric: Option<Generic>, mockedGeneric: Option<Generic>,
        classSubsts: ArrayList<TypeSubst>): Unit {
        if (originalGeneric.isNone() || mockedGeneric.isNone()) {
            return
        }
        let original = originalGeneric.getOrThrow()
        let mocked = mockedGeneric.getOrThrow()
        CJC_ASSERT(original.typeParameters.size == mocked.typeParameters.size)
        if (original.typeParameters.isEmpty() && classSubsts.isEmpty()) {
            return
        }
        let subst = TypeSubst()
        for (idx in 0..original.typeParameters.size) {
            let originalTy = (original.typeParameters[idx].GetTy().getOrThrow() as GenericsTy).getOrThrow()
            subst.Put(originalTy, mocked.typeParameters[idx].GetTy().getOrThrow())
        }
        classSubsts.add(subst, at: 0)
    }

    // C++: Sema/Test/MockUtils.cpp:625-632.
    public func GetInstantiatedTy(ty: Ty, typeSubsts: ArrayList<TypeSubst>): Ty {
        var substitutedTy = ty
        for (typeSubst in typeSubsts) {
            substitutedTy = typeManager.GetInstantiatedTy(substitutedTy, typeSubst)
        }
        return substitutedTy
    }

    public static func BuildGenericSubsts(decl: InheritableDecl): ArrayList<TypeSubst> {
        let genericSubsts = ArrayList<TypeSubst>()
        let workList = ArrayList<InheritableDecl>()
        workList.add(decl)
        var workIdx: Int64 = 0
        while (workIdx < workList.size) {
            let curDecl = workList[workIdx]
            workIdx++
            for (inheritedType in curDecl.inheritedTypes) {
                let inheritedTy = inheritedType.GetTy().getOrThrow()
                if (refEq(inheritedTy, curDecl.GetTy().getOrThrow()) || !inheritedTy.HasGeneric()) {
                    continue
                }
                if (let Some(inheritedDecl) <- Ty.GetInheritableDeclPtrOfTy(Some(inheritedTy))) {
                    genericSubsts.add(GenerateTypeMapping(inheritedDecl, inheritedTy.typeArgs))
                    workList.add(inheritedDecl)
                }
            }
        }
        var left: Int64 = 0
        var right = genericSubsts.size - 1
        while (left < right) {
            let value = genericSubsts[left]
            genericSubsts[left] = genericSubsts[right]
            genericSubsts[right] = value
            left++
            right--
        }
        return genericSubsts
    }

    public static func GetIndexOfGenericTypeParam(ty: Ty, generic: Generic): Int64 {
        var idx: Int64 = 0
        for (typeParam in generic.typeParameters) {
            if (let Some(typeParamTy) <- typeParam.GetTy()) {
                if (refEq(typeParamTy, ty)) {
                    return idx
                }
            }
            idx++
        }
        return -1
    }

    public static func UpdateRefTypesTarget(typeNode: Type, oldGeneric: Generic, newGeneric: Generic): Unit {
        if (let None <- (typeNode as RefType)) {
            return
        }
        let refType = (typeNode as RefType).getOrThrow()
        if (let Some(typeTy) <- refType.GetTy()) {
            if (let Some(genericTy) <- (typeTy as GenericsTy)) {
                let typeParamIndex = GetIndexOfGenericTypeParam(genericTy, oldGeneric)
                if (typeParamIndex != -1) {
                    refType.ref.target = newGeneric.typeParameters[typeParamIndex]
                }
            }
        }
        for (typeArg in refType.typeArguments) {
            UpdateRefTypesTarget(typeArg, oldGeneric, newGeneric)
        }
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
