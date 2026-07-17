package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.{DiagnosticEngine, DiagKindRefactor, MakeRange}
import cjcj::option.GlobalOptions as OptionGlobalOptions

private let CORE_PACKAGE_NAME: String = "std.core"
private let AST_PACKAGE_NAME: String = "std.ast"
private let GET_COMMAND_LINE_ARGS: String = "getCommandLineArgs"
private let TO_ANY: String = "toAny"
private let MAIN_INVOKE: String = "$mainInvoke"

private func IsSpecialFunction(fd: FuncDecl): Bool {
    if (fd.TestAnyAttr(Attribute.IMPORTED, Attribute.FOREIGN)) {
        return true
    }
    let rawName = fd.identifier.Val()
    let packageName = fd.fullPackageName
    let isGetCommandLineArgsFunc = packageName == CORE_PACKAGE_NAME && rawName == GET_COMMAND_LINE_ARGS
    let isImplicitUsed = (packageName == CORE_PACKAGE_NAME || packageName == AST_PACKAGE_NAME) &&
        fd.TestAttr(Attribute.IMPLICIT_USED)
    let isToAny = rawName == TO_ANY
    let isMainInvoke = rawName == MAIN_INVOKE
    return isGetCommandLineArgsFunc || isImplicitUsed || isToAny || isMainInvoke
}

private func MarkFunctionLinkage(fd: FuncDecl, linkage: Linkage): Unit {
    fd.linkage = linkage
    if (let Some(body) <- fd.funcBody) {
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                if (let Some(desugarDecl) <- param.desugarDecl) {
                    desugarDecl.linkage = linkage
                }
            }
        }
    }
    if (let Some(propDecl) <- fd.propDecl) {
        propDecl.linkage = linkage
    }
}

private func MarkFunctionAsInternalLinkage(fd: FuncDecl): Unit {
    MarkFunctionLinkage(fd, Linkage.INTERNAL)
}

private func MarkFunctionAsExternalLinkage(fd: FuncDecl): Unit {
    if (let Some(outer) <- fd.outerDecl) {
        if (let Some(inheritable) <- (outer as InheritableDecl)) {
            if (inheritable.linkage != Linkage.EXTERNAL) {
                inheritable.linkage = Linkage.EXTERNAL
            }
        }
        if (outer.IsFunc()) {
            return
        }
    } else if (!fd.TestAttr(Attribute.GLOBAL)) {
        return
    }
    MarkFunctionLinkage(fd, Linkage.EXTERNAL)
}

private func MarkVarDeclAbstractLinkage(vda: VarDeclAbstract): Unit {
    if (vda.IsExportedDecl() || vda.TestAttr(Attribute.IMPLICIT_USED)) {
        vda.linkage = Linkage.EXTERNAL
    } else {
        vda.linkage = Linkage.INTERNAL
    }
}

private func MarkTypeAliasDeclLinkage(tad: TypeAliasDecl): Unit {
    if (tad.IsExportedDecl() || tad.TestAttr(Attribute.IMPLICIT_USED)) {
        tad.linkage = Linkage.EXTERNAL
    } else {
        tad.linkage = Linkage.INTERNAL
    }
}

private func IsIntrinsicFile(file: File): Bool {
    if (let Some(pkg) <- file.curPackage) {
        if (pkg.fullPackageName != CORE_PACKAGE_NAME) {
            return false
        }
    } else {
        return false
    }
    return file.fileName == "future.cj" || file.fileName == "runtime_call_throw_exception.cj"
}

private func IsInternalSrcExportedFunction(fd: FuncDecl): Bool {
    return !fd.IsExportedDecl() && CanBeSrcExported(fd)
}

private func IterateAllFunctionInStruct(inheritableDecl: InheritableDecl, action: (FuncDecl) -> Unit): Unit {
    for (decl in inheritableDecl.GetMemberDecls()) {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            action(funcDecl)
        } else if (let Some(propDecl) <- (decl as PropDecl)) {
            for (getter in propDecl.getters) {
                action(getter)
            }
            for (setter in propDecl.setters) {
                action(setter)
            }
        }
    }
}

private func IterateAllVariableInStruct(inheritableDecl: InheritableDecl, action: (VarDecl) -> Unit): Unit {
    for (decl in inheritableDecl.GetMemberDecls()) {
        if (let Some(varDecl) <- (decl as VarDecl)) {
            action(varDecl)
        }
    }
}

private func IterateAllMembersInStruct(inheritableDecl: InheritableDecl, action: (Decl) -> Unit): Unit {
    for (decl in inheritableDecl.GetMemberDecls()) {
        if (let Some(propDecl) <- (decl as PropDecl)) {
            for (getter in propDecl.getters) {
                action(getter)
            }
            for (setter in propDecl.setters) {
                action(setter)
            }
        } else if (decl.astKind != ASTKind.PRIMARY_CTOR_DECL) {
            action(decl)
        }
    }
}

private func AnalyzeMemberDeclAsInternalLinkageInStruct(inheritable: InheritableDecl): Unit {
    if (!inheritable.IsExportedDecl() && !inheritable.TestAttr(Attribute.C)) {
        inheritable.linkage = Linkage.INTERNAL
    }
    IterateAllFunctionInStruct(inheritable, { fd: FuncDecl =>
        if (!IsSpecialFunction(fd) && !fd.IsExportedDecl()) {
            MarkFunctionAsInternalLinkage(fd)
        }
    })
    IterateAllVariableInStruct(inheritable, { vd: VarDecl => MarkVarDeclAbstractLinkage(vd) })
}

private func AnalyzeFunctionAsInternalLinkageInExtend(ed: ExtendDecl, exportForTest: Bool): Unit {
    let isExportedExtend = exportForTest || ed.IsExportedDecl()
    ed.linkage = if (isExportedExtend) { Linkage.EXTERNAL } else { Linkage.INTERNAL }
    IterateAllFunctionInStruct(ed, { fd: FuncDecl =>
        let publicInstance = fd.TestAttr(Attribute.PUBLIC) && !fd.TestAttr(Attribute.STATIC)
        if (!IsSpecialFunction(fd) && (!fd.IsExportedDecl() || (!isExportedExtend && !publicInstance))) {
            MarkFunctionAsInternalLinkage(fd)
        }
    })
}

public func AnalyzeLinkageBasedOnModifier(pkg: Package, opt: OptionGlobalOptions): Unit {
    for (file in pkg.files) {
        if (IsIntrinsicFile(file)) {
            continue
        }
        for (decl in file.decls) {
            if (let Some(vda) <- (decl as VarDeclAbstract)) {
                MarkVarDeclAbstractLinkage(vda)
            } else if (let Some(fd) <- (decl as FuncDecl)) {
                if (!IsSpecialFunction(fd) && !fd.IsExportedDecl()) {
                    MarkFunctionAsInternalLinkage(fd)
                }
            } else if (let Some(ed) <- (decl as ExtendDecl)) {
                AnalyzeFunctionAsInternalLinkageInExtend(ed, opt.exportForTest)
            } else if (let Some(inheritable) <- (decl as InheritableDecl)) {
                AnalyzeMemberDeclAsInternalLinkageInStruct(inheritable)
            } else if (let Some(tad) <- (decl as TypeAliasDecl)) {
                MarkTypeAliasDeclLinkage(tad)
            }
        }
    }
}

private func DeclKey(decl: Decl): String {
    return "${ASTKindIndex(decl.astKind)}:${decl.fullPackageName}:${decl.identifier.Val()}:" +
        "${decl.begin.ToString()}:${decl.end.ToString()}"
}

private func TyKey(ty: Ty): String {
    return "${TypeKindIndex(ty.kind)}:${ty.String()}:${ty.Hash()}"
}

private func ExprKey(expr: Expr): String {
    if (let Some(target) <- expr.GetTarget()) {
        return "target:" + DeclKey(target)
    }
    return "${ASTKindIndex(expr.astKind)}:${expr.begin.ToString()}:${expr.end.ToString()}"
}

private func DeclOfTy(ty: Ty): Option<Decl> {
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(decl) <- classTy.declPtr) {
            return decl
        }
    }
    if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(decl) <- interfaceTy.declPtr) {
            return decl
        }
    }
    if (let Some(structTy) <- (ty as StructTy)) {
        if (let Some(decl) <- structTy.declPtr) {
            return decl
        }
    }
    if (let Some(enumTy) <- (ty as EnumTy)) {
        if (let Some(decl) <- enumTy.declPtr) {
            return decl
        }
    }
    if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
        if (let Some(decl) <- aliasTy.declPtr) {
            return decl
        }
    }
    return None
}

private func IsMemberInMemLayout(member: Decl): Bool {
    if (let Some(outer) <- member.outerDecl) {
        return (outer.IsStructOrClassDecl() && member.astKind == ASTKind.VAR_DECL &&
            !member.TestAttr(Attribute.STATIC)) || member.TestAttr(Attribute.ENUM_CONSTRUCTOR)
    }
    return false
}

private class ExternalLinkageAnalyzer {
    private let pkg: Package
    private let srcExportedDecls: ArrayList<Decl> = ArrayList<Decl>()
    private let exportedTys: ArrayList<Ty> = ArrayList<Ty>()
    private let srcExportedExprs: ArrayList<Expr> = ArrayList<Expr>()
    private let queuedSrcDeclKeys: HashSet<String> = HashSet<String>()
    private let visitedSrcDeclKeys: HashSet<String> = HashSet<String>()
    private let queuedTyKeys: HashSet<String> = HashSet<String>()
    private let visitedTyKeys: HashSet<String> = HashSet<String>()
    private let queuedExprKeys: HashSet<String> = HashSet<String>()

    public init(pkg: Package) {
        this.pkg = pkg
    }

    public func Run(): Unit {
        IterateToplevelDecls(pkg, { decl: Decl => PerformPublicType(decl) })
        while (!srcExportedDecls.isEmpty() || !exportedTys.isEmpty() || !srcExportedExprs.isEmpty()) {
            AnalyzeExternalLinkageBySrcExportedDecl()
            AnalyzeExternalLinkageByExportedTy()
            AnalyzeExternalLinkageBySrcExportedExpr()
        }
    }

    private func AddSrcExportedDecl(decl: Decl): Unit {
        let key = DeclKey(decl)
        if (visitedSrcDeclKeys.contains(key) || queuedSrcDeclKeys.contains(key)) {
            return
        }
        queuedSrcDeclKeys.add(key)
        srcExportedDecls.add(decl)
    }

    private func AddSrcExportedExpr(expr: Expr): Unit {
        let key = ExprKey(expr)
        if (queuedExprKeys.contains(key)) {
            return
        }
        queuedExprKeys.add(key)
        srcExportedExprs.add(expr)
    }

    private func AddExportedTy(ty: Ty): Unit {
        let key = TyKey(ty)
        if (visitedTyKeys.contains(key) || queuedTyKeys.contains(key)) {
            return
        }
        queuedTyKeys.add(key)
        exportedTys.add(ty)
    }

    private func AddExportedTy(ty: Option<Ty>): Unit {
        if (let Some(value) <- ty) {
            AddExportedTy(value)
        }
    }

    private func AddInheritedTypes(outer: Decl): Unit {
        if (let Some(inheritable) <- (outer as InheritableDecl)) {
            for (typeNode in inheritable.inheritedTypes) {
                AddExportedTy(typeNode.GetTy())
            }
        }
    }

    private func AddAnnotationTargetExpr(classDecl: ClassDecl): Unit {
        for (anno in classDecl.annotations) {
            if (anno.kind == AstAnnotationKind.ANNOTATION) {
                for (arg in anno.args) {
                    if (let Some(expr) <- arg.expr) {
                        AddSrcExportedExpr(expr)
                    }
                }
            }
        }
    }

    private func SetTargetLinkage(target: Decl): Unit {
        if (target.TestAttr(Attribute.IMPORTED)) {
            return
        }
        if (let Some(fd) <- (target as FuncDecl)) {
            SetFuncTargetLinkage(fd)
        } else if (let Some(vd) <- (target as VarDecl)) {
            SetVarTargetLinkage(vd)
        } else if (let Some(tad) <- (target as TypeAliasDecl)) {
            tad.linkage = Linkage.EXTERNAL
        } else {
            AddExportedTy(target.GetTy())
        }
    }

    private func PerformPublicType(decl: Decl): Unit {
        if (decl.linkage == Linkage.INTERNAL || (decl.astKind == ASTKind.FUNC_DECL &&
            decl.TestAttr(Attribute.FOREIGN))) {
            return
        }
        if (let Some(vd) <- (decl as VarDecl)) {
            if (vd.isConst) {
                AddSrcExportedDecl(vd)
                return
            }
        }
        if (let Some(fd) <- (decl as FuncDecl)) {
            if (CanBeSrcExported(fd)) {
                AddSrcExportedDecl(fd)
                return
            }
        }
        if (let Some(inheritable) <- (decl as InheritableDecl)) {
            for (superDecl in inheritable.GetAllSuperDecls()) {
                if (!superDecl.TestAttr(Attribute.IMPORTED)) {
                    AddExportedTy(superDecl.GetTy())
                }
            }
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                AddAnnotationTargetExpr(classDecl)
            }
            IterateAllMembersInStruct(inheritable, { member: Decl => HandleMemberDeclInTopLevelDecl(member) })
        }
    }

    private func HandleMemberDeclInTopLevelDecl(decl: Decl): Unit {
        if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL) {
            return
        }
        if (let Some(fd) <- (decl as FuncDecl)) {
            if (fd.TestAttr(Attribute.FINALIZER)) {
                MarkFunctionAsExternalLinkage(fd)
                return
            }
            if (fd.IsExportedDecl()) {
                AddExportedTy(fd.GetTy())
                if (CanBeSrcExported(fd)) {
                    AddSrcExportedDecl(fd)
                }
            }
            return
        }
        if (let Some(vd) <- (decl as VarDecl)) {
            if (IsMemberInMemLayout(vd)) {
                AddExportedTy(vd.GetTy())
            }
            if (IsInstMemberVarInGenericDecl(vd)) {
                AddSrcExportedDecl(vd)
            }
            if (!vd.IsExportedDecl()) {
                return
            }
            AddExportedTy(vd.GetTy())
            if (let Some(pd) <- (vd as PropDecl)) {
                if (pd.isConst || pd.HasAnno(AstAnnotationKind.FROZEN)) {
                    for (getter in pd.getters) {
                        AddSrcExportedDecl(getter)
                    }
                    for (setter in pd.setters) {
                        AddSrcExportedDecl(setter)
                    }
                }
            }
        }
    }

    private func VisitSrcExportedNode(curNode: Node): VisitAction {
        if (let Some(fd) <- (curNode as FuncDecl)) {
            if (!IsInternalSrcExportedFunction(fd)) {
                MarkFunctionAsExternalLinkage(fd)
            }
            if (CanBeSrcExported(fd)) {
                AddSrcExportedDecl(fd)
            }
            return VisitAction.WALK_CHILDREN
        }
        let target = curNode.GetTarget()
        let realTarget = GetRealTarget(target)
        if (let None <- realTarget) {
            return VisitAction.WALK_CHILDREN
        }
        SetTargetLinkage(target.getOrThrow())
        SetTargetLinkage(realTarget.getOrThrow())
        return VisitAction.WALK_CHILDREN
    }

    private func AnalyzeExternalLinkageBySrcExportedDecl(): Unit {
        while (!srcExportedDecls.isEmpty()) {
            let decl = srcExportedDecls[0]
            srcExportedDecls.remove(at: 0)
            let key = DeclKey(decl)
            queuedSrcDeclKeys.remove(key)
            visitedSrcDeclKeys.add(key)
            let walker = Walker(decl, visitPre: { curNode: Node => VisitSrcExportedNode(curNode) })
            let _ = walker.Walk()
        }
    }

    private func AnalyzeExternalLinkageBySrcExportedExpr(): Unit {
        while (!srcExportedExprs.isEmpty()) {
            let expr = srcExportedExprs[0]
            srcExportedExprs.remove(at: 0)
            queuedExprKeys.remove(ExprKey(expr))
            let walker = Walker(expr, visitPre: { curNode: Node => VisitSrcExportedNode(curNode) })
            let _ = walker.Walk()
        }
    }

    private func AnalyzeExternalLinkageByExportedTy(): Unit {
        while (!exportedTys.isEmpty()) {
            let ty = exportedTys[0]
            exportedTys.remove(at: 0)
            let key = TyKey(ty)
            queuedTyKeys.remove(key)
            visitedTyKeys.add(key)
            if (!Ty.IsTyCorrect(ty)) {
                continue
            }
            if (let Some(funcTy) <- (ty as FuncTy)) {
                for (paramTy in funcTy.paramTys) {
                    AddExportedTy(paramTy)
                }
                AddExportedTy(funcTy.retTy)
            } else if (let Some(genTy) <- (ty as GenericsTy)) {
                for (upper in genTy.upperBounds) {
                    AddExportedTy(upper)
                }
            } else {
                for (arg in ty.typeArgs) {
                    AddExportedTy(arg)
                }
            }
            if (let Some(decl) <- DeclOfTy(ty)) {
                if (decl.TestAttr(Attribute.IMPORTED)) {
                    continue
                }
                decl.linkage = Linkage.EXTERNAL
                if (let Some(inheritable) <- (decl as InheritableDecl)) {
                    HandleMemberDeclsByTy(inheritable)
                }
                if (let Some(enumDecl) <- (decl as EnumDecl)) {
                    for (ctor in enumDecl.constructors) {
                        if (let Some(fd) <- (ctor as FuncDecl)) {
                            SetFuncTargetLinkage(fd)
                        } else if (let Some(vd) <- (ctor as VarDecl)) {
                            SetVarTargetLinkage(vd, byTy: true)
                        }
                    }
                }
            }
        }
    }

    private func HandleMemberDeclsByTy(inheritable: InheritableDecl): Unit {
        for (member in inheritable.GetMemberDecls()) {
            let isFuncOrProp = member.astKind == ASTKind.FUNC_DECL || member.astKind == ASTKind.PROP_DECL
            let isInstMemberInVTable = isFuncOrProp && member.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)
            let isStaticMemberInVTable = isFuncOrProp && !member.TestAttr(Attribute.PRIVATE) &&
                member.TestAttr(Attribute.STATIC)
            let isMemberInLayout = IsMemberInMemLayout(member)
            let isConstInCJMP = inheritable.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC) && member.IsConst()
            if (!isInstMemberInVTable && !isStaticMemberInVTable && !isMemberInLayout &&
                !member.IsExportedDecl() && !isConstInCJMP) {
                continue
            }
            if (let Some(fd) <- (member as FuncDecl)) {
                if (fd.TestAttr(Attribute.FINALIZER)) {
                    MarkFunctionAsExternalLinkage(fd)
                } else {
                    SetFuncTargetLinkage(fd, byTy: true)
                }
            } else if (let Some(pd) <- (member as PropDecl)) {
                SetPropTargetLinkage(pd, byTy: true)
            } else if (let Some(vd) <- (member as VarDecl)) {
                SetVarTargetLinkage(vd, byTy: true, isConstInCJMP: isConstInCJMP)
            }
        }
    }

    private func SetFuncTargetLinkage(fd: FuncDecl, byTy!: Bool = false): Unit {
        let _ = byTy // maybe_unused: kept for API parity with SetProp/SetVarTargetLinkage
        if (!IsGlobalOrMember(fd)) {
            return
        }
        MarkFunctionLinkage(fd, Linkage.EXTERNAL)
        if (CanBeSrcExported(fd)) {
            AddSrcExportedDecl(fd)
        }
        AddExportedTy(fd.GetTy())
        if (let Some(outer) <- fd.outerDecl) {
            outer.linkage = Linkage.EXTERNAL
            AddInheritedTypes(outer)
        }
        if (let Some(propDecl) <- fd.propDecl) {
            SetPropTargetLinkage(propDecl)
        }
    }

    private func SetPropTargetLinkage(pd: PropDecl, byTy!: Bool = false): Unit {
        SetVarTargetLinkage(pd, byTy: byTy)
        let canBeSrcExported = pd.isConst || pd.HasAnno(AstAnnotationKind.FROZEN) ||
            IsInDeclWithAttribute(pd, Attribute.GENERIC)
        for (getter in pd.getters) {
            MarkFunctionLinkage(getter, Linkage.EXTERNAL)
            if (canBeSrcExported) {
                AddSrcExportedDecl(getter)
            }
        }
        for (setter in pd.setters) {
            MarkFunctionLinkage(setter, Linkage.EXTERNAL)
            if (canBeSrcExported) {
                AddSrcExportedDecl(setter)
            }
        }
    }

    private func SetVarTargetLinkage(vd: VarDecl, byTy!: Bool = false, isConstInCJMP!: Bool = false): Unit {
        let isPrivateStatic = vd.TestAttr(Attribute.PRIVATE) && vd.TestAttr(Attribute.STATIC)
        if (!IsGlobalOrMember(vd) || (byTy && vd.astKind == ASTKind.VAR_DECL && isPrivateStatic && !isConstInCJMP)) {
            return
        }
        vd.linkage = Linkage.EXTERNAL
        if (vd.isConst || vd.HasAnno(AstAnnotationKind.FROZEN) || IsInstMemberVarInGenericDecl(vd) ||
            IsMemberVarShouldBeSrcExported(vd)) {
            AddSrcExportedDecl(vd)
        }
        AddExportedTy(vd.GetTy())
        if (let Some(outer) <- vd.outerDecl) {
            outer.linkage = Linkage.EXTERNAL
            AddInheritedTypes(outer)
        }
    }
}

private func FinalizeInternalNominalMembers(pkg: Package): Unit {
    IterateToplevelDecls(pkg, { decl: Decl =>
        if (let Some(inheritable) <- (decl as InheritableDecl)) {
            if (inheritable.linkage == Linkage.INTERNAL) {
                IterateAllFunctionInStruct(inheritable, { fd: FuncDecl => MarkFunctionAsInternalLinkage(fd) })
                IterateAllMembersInStruct(inheritable, { member: Decl =>
                    if (let Some(vd) <- (member as VarDecl)) {
                        vd.linkage = Linkage.INTERNAL
                    }
                })
            }
        }
    })
}

public func AnalyzeFunctionLinkage(pkg: Package, opt: OptionGlobalOptions, diag: DiagnosticEngine): Unit {
    AnalyzeLinkageBasedOnModifier(pkg, opt)
    ExternalLinkageAnalyzer(pkg).Run()
    FinalizeInternalNominalMembers(pkg)
    let privateDeclMap = HashMap<String, Decl>()
    IterateToplevelDecls(pkg, { decl: Decl =>
        if (decl.IsNominalDecl() && decl.TestAttr(Attribute.PRIVATE) && decl.linkage != Linkage.INTERNAL) {
            let name = decl.identifier.Val()
            if (let Some(previous) <- privateDeclMap.get(name)) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.sema_export_same_private_decl,
                    MakeRange(previous.identifier.Begin(), previous.identifier.Val())
                )
                builder.AddNote(MakeRange(decl.identifier.Begin(), decl.identifier.Val()),
                    "same with private declaration")
                builder.Emit()
            } else {
                privateDeclMap[name] = decl
            }
        }
    })
}
