package cjcj::sema.NativeFFI.Java

import cjcj::ast.*
import cjcj::basic.{DiagnosticEngine, DiagKindRefactor}
import cjcj::sema.NativeFFI.IsJArray
import cjcj::utils.INTEROPLIB_CFFI_JAVA_ENTITY

private enum JavaTypePosition { | IN | OUT | BOTH }

// canonical 41b TypeCheckJavaInterop.cpp:61-231. Check position before recursive wrappers.
class JavaInteropTypeChecker {
    private let isImpl: Bool
    private let diag: DiagnosticEngine

    init(isImpl: Bool, diag: DiagnosticEngine) {
        this.isImpl = isImpl
        this.diag = diag
    }

    private func GetJavaClassKind(): String {
        return if (isImpl) { "exported '@Java'" } else { "'@Java' foreign" }
    }

    private func IsSupported(ty: Ty, pos: JavaTypePosition): Bool {
        match (ty.kind) {
            case TypeKind.TYPE_UNIT => return match (pos) { case JavaTypePosition.OUT => true; case _ => false }
            case TypeKind.TYPE_BOOLEAN | TypeKind.TYPE_INT8 | TypeKind.TYPE_UINT16 |
                TypeKind.TYPE_INT16 | TypeKind.TYPE_INT32 | TypeKind.TYPE_INT64 |
                TypeKind.TYPE_FLOAT32 | TypeKind.TYPE_FLOAT64 => return true
            case TypeKind.TYPE_ENUM =>
                if (!ty.IsCoreOptionType() || ty.typeArgs[0].IsCoreOptionType() ||
                    ty.typeArgs[0].IsPrimitive()) { return false }
                for (arg in ty.typeArgs) {
                    if (!IsSupported(arg, pos)) { return false }
                }
                return true
            case TypeKind.TYPE_CLASS | TypeKind.TYPE_INTERFACE =>
                if (ty.IsObject()) { return true }
                return (ty as ClassLikeTy).getOrThrow().commonDecl.getOrThrow().IsJavaForeign()
            case TypeKind.TYPE_STRUCT => return ty.name == INTEROPLIB_CFFI_JAVA_ENTITY || ty.IsString()
            case _ => return false
        }
    }

    private func IsJavaCompatible(ty: Ty): Bool {
        return IsJavaCompatible(ty, JavaTypePosition.BOTH)
    }

    private func IsJavaCompatible(ty: Ty, pos: JavaTypePosition): Bool {
        if (IsSupported(ty, pos)) {
            if ((ty as ClassLikeTy).isSome() && IsJArray(ty)) {
                return IsJavaCompatible(ty.typeArgs[0])
            }
            return true
        }
        if (ty.IsCoreOptionType() && !ty.typeArgs[0].IsCoreOptionType() && !ty.typeArgs[0].IsPrimitive()) {
            return IsJavaCompatible(ty.typeArgs[0], pos)
        }
        if (let Some(classLike) <- (ty as ClassLikeTy)) { return IsImpl(classLike) }
        return false
    }

    private func CheckParamTypes(fd: FuncDecl, kind: DiagKindRefactor): Unit {
        let body = fd.funcBody ?? return
        let outer = fd.outerDecl.getOrThrow()
        let isJavaArray = IsJArray(outer)
        for (params in body.paramLists) {
            for (param in params.params) {
                if (!IsJavaCompatible(param.GetTy().getOrThrow(), JavaTypePosition.IN) && !isJavaArray) {
                    let builder = DiagnoseRefactor(diag, kind, param, arguments: [GetJavaClassKind()])
                    builder.AddMainHintArguments(Ty.ToString(param.GetTy()))
                    builder.Emit()
                    fd.EnableAttr(Attribute.IS_BROKEN)
                    outer.EnableAttr(Attribute.HAS_BROKEN)
                    outer.EnableAttr(Attribute.IS_BROKEN)
                }
            }
        }
    }

    private func CheckMethodTypes(fd: FuncDecl): Unit {
        if (let Some(body) <- fd.funcBody) {
            if (let Some(retType) <- body.retType) {
                let retTy = retType.GetTy().getOrThrow()
                if (!IsJavaCompatible(retTy, JavaTypePosition.OUT) &&
                    (!IsJArray(fd.outerDecl.getOrThrow()) || !retTy.IsGeneric())) {
                    let node: Node = if (!retType.begin.IsZero()) { retType } else { fd }
                    let builder = DiagnoseRefactor(diag, DiagKindRefactor.sema_java_mirror_method_ret_unsupported,
                        node, arguments: [GetJavaClassKind()])
                    builder.AddMainHintArguments(Ty.ToString(retType.GetTy()))
                    builder.Emit()
                    fd.EnableAttr(Attribute.IS_BROKEN)
                }
            }
        }
        CheckParamTypes(fd, DiagKindRefactor.sema_java_mirror_method_arg_must_be_java_mirror)
    }

    private func CheckPropType(property: PropDecl): Unit {
        if (!IsJavaCompatible(property.GetTy().getOrThrow())) {
            let kind = if (isImpl) { DiagKindRefactor.sema_java_impl_prop_must_be_java_compatible }
                else { DiagKindRefactor.sema_java_mirror_prop_must_be_java_mirror }
            let builder = DiagnoseRefactor(diag, kind, property.typeNode.getOrThrow())
            builder.AddMainHintArguments(Ty.ToString(property.GetTy()))
            builder.Emit()
            property.EnableAttr(Attribute.IS_BROKEN)
        }
    }

    func CheckJavaCompatibleDeclSignature(decl: ClassLikeDecl): Unit {
        for (member in decl.GetMemberDecls()) {
            if (isImpl && member.TestAttr(Attribute.PRIVATE)) { continue }
            if (let Some(fd) <- (member as FuncDecl)) {
                if (fd.TestAttr(Attribute.CONSTRUCTOR)) {
                    CheckParamTypes(fd, DiagKindRefactor.sema_java_mirror_ctor_arg_must_be_java_mirror)
                } else { CheckMethodTypes(fd) }
            } else if (let Some(property) <- (member as PropDecl)) { CheckPropType(property) }
        }
    }
}
