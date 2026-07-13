package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::mangle.BaseMangler
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.GetSingleArgumentAnnotationValue
import cjcj::sema.NativeFFI.GetMangledMethodName
import cjcj::utils.CJC_ABORT
import cjcj::utils.CJC_ASSERT

// Mirrors Sema/NativeFFI/ObjC/Utils/NameGenerator.cpp:24-32.
private let WRAPPER_PREFIX: String = "CJImpl_ObjC_"
private let DELETE_CJ_OBJECT_SUFFIX: String = "_deleteCJObject"
private let LOCK_CJ_OBJECT_SUFFIX: String = "_lockCJObject"
private let UNLOCK_CJ_OBJECT_SUFFIX: String = "_unlockCJObject"
private let WRAPPER_GETTER_SUFFIX: String = "_get"
private let WRAPPER_GETTER_SUFFIX_INNER_GENERIC_PROP: String = "get"
private let WRAPPER_SETTER_SUFFIX: String = "_set"

public class NameGenerator {
    private let mangler: BaseMangler
    private let typeManager: TypeManager

    public init(mangler: BaseMangler, typeManager: TypeManager) {
        this.mangler = mangler
        this.typeManager = typeManager
    }

    // Mirrors NameGenerator::GenerateInitCjObjectName(VarDecl), NameGenerator.cpp:39-44.
    public func GenerateInitCjObjectName(target: VarDecl,
        genericActualName!: Option<String> = None): String {
        let outerDeclName = target.outerDecl.getOrThrow().identifier.Val()
        let name = if (let Some(actualName) <- genericActualName) {
            outerDeclName + "_" + actualName
        } else {
            outerDeclName + "_" + target.identifier.Val()
        }
        return WRAPPER_PREFIX + name
    }

    // Mirrors NameGenerator::GenerateInitCjObjectName(FuncDecl), NameGenerator.cpp:46-56.
    public func GenerateInitCjObjectName(target: FuncDecl,
        genericActualName!: Option<String> = None): String {
        let params = target.funcBody.getOrThrow().paramLists[0].params
        let ctorName = GetObjCDeclName(target)
        let mangledCtorName = GetMangledMethodName(mangler, params, ctorName, typeManager)
        var name = GetObjCFullDeclName(target.outerDecl.getOrThrow(),
            genericActualName: genericActualName) + "_" + mangledCtorName
        name = name.replace(".", "_").replace(":", "_")
        return WRAPPER_PREFIX + name
    }

    // Mirrors NameGenerator::GenerateInitCjObjectName(Decl), NameGenerator.cpp:58-67.
    public func GenerateInitCjObjectName(target: Decl,
        genericActualName!: Option<String> = None): String {
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            return GenerateInitCjObjectName(funcDecl, genericActualName: genericActualName)
        } else if (let Some(varDecl) <- (target as VarDecl)) {
            return GenerateInitCjObjectName(varDecl, genericActualName: genericActualName)
        }
        CJC_ABORT()
        return ""
    }

    // Mirrors NameGenerator::GenerateDeleteCjObjectName, NameGenerator.cpp:69-76.
    public func GenerateDeleteCjObjectName(target: Decl,
        genericActualName!: Option<String> = None): String {
        let name = GetObjCFullDeclName(target, genericActualName: genericActualName).
            replace(".", "_").replace(":", "_")
        return WRAPPER_PREFIX + name + DELETE_CJ_OBJECT_SUFFIX
    }

    // Mirrors NameGenerator::GenerateLockCjObjectName, NameGenerator.cpp:78-85.
    public func GenerateLockCjObjectName(target: Decl): String {
        let name = GetObjCFullDeclName(target).replace(".", "_").replace(":", "_")
        return WRAPPER_PREFIX + name + LOCK_CJ_OBJECT_SUFFIX
    }

    // Mirrors NameGenerator::GenerateUnlockCjObjectName, NameGenerator.cpp:87-94.
    public func GenerateUnlockCjObjectName(target: Decl): String {
        let name = GetObjCFullDeclName(target).replace(".", "_").replace(":", "_")
        return WRAPPER_PREFIX + name + UNLOCK_CJ_OBJECT_SUFFIX
    }

    // Mirrors NameGenerator::GenerateMethodWrapperName, NameGenerator.cpp:96-129.
    public func GenerateMethodWrapperName(target: FuncDecl,
        genericActualName!: Option<String> = None, isInnerGeneric!: Bool = false): String {
        let params = target.funcBody.getOrThrow().paramLists[0].params
        let methodName = GetObjCDeclName(target)
        let mangledMethodName = GetMangledMethodName(mangler, params, methodName, typeManager)
        let outerDeclName = GetObjCFullDeclName(target.outerDecl.getOrThrow(),
            genericActualName: genericActualName)
        var name = outerDeclName + "." + mangledMethodName
        if (isInnerGeneric) {
            name = name.replace("$", "")
        }
        name = name.replace(".", "_").replace(":", "_")
        return WRAPPER_PREFIX + name
    }

    // Mirrors NameGenerator::GeneratePropGetterWrapperName, NameGenerator.cpp:131-140.
    public func GeneratePropGetterWrapperName(target: PropDecl): String {
        let outerDeclName = GetObjCFullDeclName(target.outerDecl.getOrThrow())
        let name = (outerDeclName + "." + GetObjCDeclName(target)).replace(".", "_").replace(":", "_")
        return WRAPPER_PREFIX + name + WRAPPER_GETTER_SUFFIX
    }

    // Mirrors NameGenerator::GetFieldGetterWrapperName, NameGenerator.cpp:154-168.
    public func GetFieldGetterWrapperName(target: VarDecl,
        genericActualName!: Option<String> = None, isInnerGeneric!: Bool = false): String {
        let outerDeclName = GetObjCFullDeclName(target.outerDecl.getOrThrow(),
            genericActualName: genericActualName)
        let name = (outerDeclName + "." + GetObjCDeclName(target)).replace(".", "_").replace(":", "_")
        if (isInnerGeneric) {
            return WRAPPER_PREFIX + name + WRAPPER_GETTER_SUFFIX_INNER_GENERIC_PROP
        }
        return WRAPPER_PREFIX + name + WRAPPER_GETTER_SUFFIX
    }

    // Mirrors NameGenerator::GetFieldSetterWrapperName, NameGenerator.cpp:170-180.
    public func GetFieldSetterWrapperName(target: VarDecl): String {
        let outerDeclName = GetObjCFullDeclName(target.outerDecl.getOrThrow())
        let name = (outerDeclName + "." + GetObjCDeclName(target)).replace(".", "_").replace(":", "_")
        return WRAPPER_PREFIX + name + WRAPPER_SETTER_SUFFIX
    }

    public func GetUserDefinedObjCName(target: Decl): Option<String> {
        for (annotation in target.annotations) {
            if (annotation.kind != AstAnnotationKind.OBJ_C_MIRROR &&
                annotation.kind != AstAnnotationKind.OBJ_C_IMPL &&
                annotation.kind != AstAnnotationKind.FOREIGN_NAME) {
                continue
            }

            CJC_ASSERT(annotation.args.size < 2)
            if (annotation.args.isEmpty()) {
                break
            }

            let expr = annotation.args[0].expr.getOrThrow()
            CJC_ASSERT(expr.astKind == ASTKind.LIT_CONST_EXPR)
            let literal = (expr as LitConstExpr).getOrThrow()
            return Some(literal.stringValue)
        }

        return None
    }

    public func GetObjCDeclName(target: Decl, genericActualName!: Option<String> = None): String {
        if (let Some(foreignName) <- GetUserDefinedObjCName(target)) {
            return foreignName
        }

        if (let Some(funcDecl) <- (target as FuncDecl)) {
            if (let None <- funcDecl.funcBody) {
                if (target.GetTy().getOrThrow().HasGeneric() && !target.identifierForLsp.isEmpty()) {
                    var actualEnumName = target.identifier.Val().replace("$", "")
                    if (let Some(pos) <- actualEnumName.indexOf(target.identifierForLsp)) {
                        actualEnumName = actualEnumName[0..pos] + "_" + actualEnumName[pos..]
                    }
                    return actualEnumName
                }
                return target.identifier.Val()
            }
            let funcBody = funcDecl.funcBody.getOrThrow()
            if (funcBody.paramLists.isEmpty() || funcBody.paramLists[0].params.isEmpty()) {
                if (target.GetTy().getOrThrow().HasGeneric() && !target.identifierForLsp.isEmpty()) {
                    var actualEnumName = target.identifier.Val().replace("$", "")
                    if (let Some(pos) <- actualEnumName.indexOf(target.identifierForLsp)) {
                        actualEnumName = actualEnumName[0..pos] + "_" + actualEnumName[pos..]
                    }
                    return actualEnumName
                }
                return target.identifier.Val()
            }

            let paramSize = funcBody.paramLists[0].params.size
            if (paramSize == 1) {
                return target.identifier.Val() + ":"
            }

            if (paramSize > 1) {
                var colons = ""
                for (_ in 0..paramSize) {
                    colons += ":"
                }
                return target.identifier.Val() + colons
            }
        }

        if (let Some(actualName) <- genericActualName) {
            return actualName
        }
        return target.identifier.Val()
    }

    public func GetObjCGetterName(target: Decl): String {
        if (let Some(foreignName) <-
            GetSingleArgumentAnnotationValue(target, AstAnnotationKind.FOREIGN_GETTER_NAME)) {
            return foreignName
        }

        if (let Some(foreignName) <- GetUserDefinedObjCName(target)) {
            return foreignName
        }

        return target.identifier.Val()
    }

    public func GetObjCSetterName(target: Decl): String {
        if (let Some(foreignName) <-
            GetSingleArgumentAnnotationValue(target, AstAnnotationKind.FOREIGN_SETTER_NAME)) {
            return foreignName
        }

        if (let Some(foreignName) <- GetUserDefinedObjCName(target)) {
            return MakeSetterName(foreignName)
        }

        return MakeSetterName(target.identifier.Val())
    }

    public static func MakeSetterName(propName: String): String {
        return "set" + propName[0..1].toAsciiUpper() + propName[1..] + ":"
    }

    public func GetObjCDeclSelectorComponents(target: FuncDecl): ArrayList<String> {
        let fullName = GetObjCDeclName(target)
        let result = ArrayList<String>()
        var pos: Int64 = 0
        while (pos < fullName.size) {
            if (let Some(newPos) <- fullName.indexOf(":", pos)) {
                result.add(fullName[pos..newPos])
                pos = newPos + 1
            } else {
                result.add(fullName[pos..])
                break
            }
        }

        let funcBody = target.funcBody.getOrThrow()
        var actualArgumentSize: Int64 = 0
        for (paramList in funcBody.paramLists) {
            actualArgumentSize += paramList.params.size
        }
        if ((actualArgumentSize == 0 && result.size == 1) || actualArgumentSize == result.size) {
            return result
        }
        while (actualArgumentSize < result.size) {
            result.remove(at: result.size - 1)
        }
        if (actualArgumentSize > result.size) {
            let namedTail = ArrayList<String>()
            var paramListIndex = funcBody.paramLists.size - 1
            while (paramListIndex >= 0) {
                let params = funcBody.paramLists[paramListIndex].params
                var paramIndex = params.size - 1
                while (paramIndex >= 0) {
                    namedTail.add(params[paramIndex].identifier.Val())
                    if (namedTail.size + result.size == actualArgumentSize) {
                        var tailIndex = namedTail.size - 1
                        while (tailIndex >= 0) {
                            result.add(namedTail[tailIndex])
                            tailIndex--
                        }
                        return result
                    }
                    paramIndex--
                }
                paramListIndex--
            }
        }
        return result
    }

    public func GetObjCFullDeclName(target: Decl, genericActualName!: Option<String> = None): String {
        if (let Some(name) <- GetUserDefinedObjCName(target)) {
            return name
        }

        let actualName = genericActualName ?? target.identifier.Val()
        return target.fullPackageName + "." + actualName
    }

    public func GetPropSetterWrapperName(target: PropDecl): String {
        let outerDeclName = GetObjCFullDeclName(target.outerDecl.getOrThrow())
        let name = (outerDeclName + "." + GetObjCDeclName(target)).replace(".", "_").replace(":", "_")
        return WRAPPER_PREFIX + name + WRAPPER_SETTER_SUFFIX
    }
}
