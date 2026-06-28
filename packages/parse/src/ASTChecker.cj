package cangjie_compiler::parse

import cangjie_compiler::ast.{ASTKindName, PointerExpr, VisitAction, Walker}
import cangjie_compiler::utils.CJC_ABORT
import std.collection.*

private func AST_NULLPTR_CHECK<T>(checker: ASTChecker, node: Node, value: Option<T>, subInfo: String): Unit {
    if (let None <- value) {
        checker.CollectInfo(node, subInfo)
    }
}

private func ATTR_NULLPTR_CHECK<T>(checker: ASTChecker, node: Node, value: Option<T>, subInfo: String): Unit {
    if (let None <- value) {
        checker.CollectInfo(node, subInfo)
    }
}

private func ZERO_POSITION_CHECK(node: Node, pos: Position, subInfo: String): Unit {
    let _ = node
    let _ = pos
    let _ = subInfo
}

private func VEC_AST_NULLPTR_CHECK<T>(node: Node, values: ArrayList<T>, subInfo: String): Unit {
    let _ = node
    let _ = values
    let _ = subInfo
}

private func VEC_ZERO_POS_CHECK(node: Node, values: ArrayList<Position>, subInfo: String): Unit {
    let _ = node
    let _ = values
    let _ = subInfo
}

private func VEC_EMPTY_STRING_CHECK(node: Node, values: ArrayList<String>, subInfo: String): Unit {
    let _ = node
    let _ = values
    let _ = subInfo
}

private func EMPTY_STRING_CHECK(node: Node, value: String, subInfo: String): Unit {
    let _ = node
    let _ = value
    let _ = subInfo
}

private func EMPTY_IDENTIFIER_CHECK(node: Node, value: Identifier, subInfo: String): Unit {
    let _ = node
    let _ = value
    let _ = subInfo
}

public class ASTChecker {
    private let checkFuncMap: ArrayList<(Node) -> Unit> = ArrayList<(Node) -> Unit>()
    private let checkInfoSet: TreeSet<String> = TreeSet<String>()

    public init() {
        checkFuncMap.add({ node: Node => CheckAnnotation(node) })
        checkFuncMap.add({ node: Node => CheckModifier(node) })
        checkFuncMap.add({ node: Node => CheckDecl(node) })
        checkFuncMap.add({ node: Node => CheckMainDecl(node) })
        checkFuncMap.add({ node: Node => CheckFuncDecl(node) })
        checkFuncMap.add({ node: Node => CheckMacroDecl(node) })
        checkFuncMap.add({ node: Node => CheckClassLikeDecl(node) })
        checkFuncMap.add({ node: Node => CheckClassDecl(node) })
        checkFuncMap.add({ node: Node => CheckInterfaceDecl(node) })
        checkFuncMap.add({ node: Node => CheckExtendDecl(node) })
        checkFuncMap.add({ node: Node => CheckEnumDecl(node) })
        checkFuncMap.add({ node: Node => CheckStructDecl(node) })
        checkFuncMap.add({ node: Node => CheckTypeAliasDecl(node) })
        checkFuncMap.add({ node: Node => CheckPrimaryCtorDecl(node) })
        checkFuncMap.add({ node: Node => CheckBuiltInDecl(node) })
        checkFuncMap.add({ node: Node => CheckVarDecl(node) })
        checkFuncMap.add({ node: Node => CheckPropDecl(node) })
        checkFuncMap.add({ node: Node => CheckMacroExpandParam(node) })
        checkFuncMap.add({ node: Node => CheckFuncParam(node) })
        checkFuncMap.add({ node: Node => CheckVarWithPatternDecl(node) })
        checkFuncMap.add({ node: Node => CheckGenericParamDecl(node) })
        checkFuncMap.add({ node: Node => CheckPackageDecl(node) })
        checkFuncMap.add({ node: Node => CheckMacroExpandDecl(node) })
        checkFuncMap.add({ node: Node => CheckInvalidDecl(node) })
        checkFuncMap.add({ node: Node => CheckPattern(node) })
        checkFuncMap.add({ node: Node => CheckVarPattern(node) })
        checkFuncMap.add({ node: Node => CheckConstPattern(node) })
        checkFuncMap.add({ node: Node => CheckTuplePattern(node) })
        checkFuncMap.add({ node: Node => CheckEnumPattern(node) })
        checkFuncMap.add({ node: Node => CheckVarOrEnumPattern(node) })
        checkFuncMap.add({ node: Node => CheckTypePattern(node) })
        checkFuncMap.add({ node: Node => CheckExceptTypePattern(node) })
        checkFuncMap.add({ node: Node => CheckCommandTypePattern(node) })
        checkFuncMap.add({ node: Node => CheckWildcardPattern(node) })
        checkFuncMap.add({ node: Node => CheckInvalidPattern(node) })
        checkFuncMap.add({ node: Node => CheckType(node) })
        checkFuncMap.add({ node: Node => CheckRefType(node) })
        checkFuncMap.add({ node: Node => CheckQualifiedType(node) })
        checkFuncMap.add({ node: Node => CheckOptionType(node) })
        checkFuncMap.add({ node: Node => CheckConstantType(node) })
        checkFuncMap.add({ node: Node => CheckVArrayType(node) })
        checkFuncMap.add({ node: Node => CheckPrimitiveType(node) })
        checkFuncMap.add({ node: Node => CheckParenType(node) })
        checkFuncMap.add({ node: Node => CheckFuncType(node) })
        checkFuncMap.add({ node: Node => CheckTupleType(node) })
        checkFuncMap.add({ node: Node => CheckThisType(node) })
        checkFuncMap.add({ node: Node => CheckInvalidType(node) })
        checkFuncMap.add({ node: Node => CheckExpr(node) })
        checkFuncMap.add({ node: Node => CheckWildcardExpr(node) })
        checkFuncMap.add({ node: Node => CheckCallExpr(node) })
        checkFuncMap.add({ node: Node => CheckParenExpr(node) })
        checkFuncMap.add({ node: Node => CheckMemberAccess(node) })
        checkFuncMap.add({ node: Node => CheckRefExpr(node) })
        checkFuncMap.add({ node: Node => CheckOptionalExpr(node) })
        checkFuncMap.add({ node: Node => CheckOptionalChainExpr(node) })
        checkFuncMap.add({ node: Node => CheckPrimitiveTypeExpr(node) })
        checkFuncMap.add({ node: Node => CheckReturnExpr(node) })
        checkFuncMap.add({ node: Node => CheckLitConstExpr(node) })
        checkFuncMap.add({ node: Node => CheckInterpolationExpr(node) })
        checkFuncMap.add({ node: Node => CheckStrInterpolationExpr(node) })
        checkFuncMap.add({ node: Node => CheckAssignExpr(node) })
        checkFuncMap.add({ node: Node => CheckUnaryExpr(node) })
        checkFuncMap.add({ node: Node => CheckBinaryExpr(node) })
        checkFuncMap.add({ node: Node => CheckIncOrDecExpr(node) })
        checkFuncMap.add({ node: Node => CheckSubscriptExpr(node) })
        checkFuncMap.add({ node: Node => CheckIsExpr(node) })
        checkFuncMap.add({ node: Node => CheckAsExpr(node) })
        checkFuncMap.add({ node: Node => CheckRangeExpr(node) })
        checkFuncMap.add({ node: Node => CheckArrayLit(node) })
        checkFuncMap.add({ node: Node => CheckArrayExpr(node) })
        checkFuncMap.add({ node: Node => CheckPointerExpr(node) })
        checkFuncMap.add({ node: Node => CheckTupleLit(node) })
        checkFuncMap.add({ node: Node => CheckMatchExpr(node) })
        checkFuncMap.add({ node: Node => CheckBlock(node) })
        checkFuncMap.add({ node: Node => CheckIfExpr(node) })
        checkFuncMap.add({ node: Node => CheckLetPatternDestructor(node) })
        checkFuncMap.add({ node: Node => CheckTokenPart(node) })
        checkFuncMap.add({ node: Node => CheckQuoteExpr(node) })
        checkFuncMap.add({ node: Node => CheckTryExpr(node) })
        checkFuncMap.add({ node: Node => CheckWhileExpr(node) })
        checkFuncMap.add({ node: Node => CheckJumpExpr(node) })
        checkFuncMap.add({ node: Node => CheckLambdaExpr(node) })
        checkFuncMap.add({ node: Node => CheckTrailingClosureExpr(node) })
        checkFuncMap.add({ node: Node => CheckForInExpr(node) })
        checkFuncMap.add({ node: Node => CheckDoWhileExpr(node) })
        checkFuncMap.add({ node: Node => CheckTypeConvExpr(node) })
        checkFuncMap.add({ node: Node => CheckThrowExpr(node) })
        checkFuncMap.add({ node: Node => CheckPerformExpr(node) })
        checkFuncMap.add({ node: Node => CheckResumeExpr(node) })
        checkFuncMap.add({ node: Node => CheckSpawnExpr(node) })
        checkFuncMap.add({ node: Node => CheckSynchronizedExpr(node) })
        checkFuncMap.add({ node: Node => CheckMacroExpandExpr(node) })
        checkFuncMap.add({ node: Node => CheckIfAvailableExpr(node) })
        checkFuncMap.add({ node: Node => CheckInvalidExpr(node) })
        checkFuncMap.add({ node: Node => CheckGeneric(node) })
        checkFuncMap.add({ node: Node => CheckGenericConstraint(node) })
        checkFuncMap.add({ node: Node => CheckMatchCase(node) })
        checkFuncMap.add({ node: Node => CheckMatchCaseOther(node) })
        checkFuncMap.add({ node: Node => CheckFuncArg(node) })
        checkFuncMap.add({ node: Node => CheckFuncParamList(node) })
        checkFuncMap.add({ node: Node => CheckFuncBody(node) })
        checkFuncMap.add({ node: Node => CheckStructBody(node) })
        checkFuncMap.add({ node: Node => CheckClassBody(node) })
        checkFuncMap.add({ node: Node => CheckInterfaceBody(node) })
        checkFuncMap.add({ node: Node => CheckDummyBody(node) })
        checkFuncMap.add({ node: Node => CheckImportContent(node) })
        checkFuncMap.add({ node: Node => CheckImportSpec(node) })
        checkFuncMap.add({ node: Node => CheckPackageSpec(node) })
        checkFuncMap.add({ node: Node => CheckPackage(node) })
        checkFuncMap.add({ node: Node => CheckFeatureId(node) })
        checkFuncMap.add({ node: Node => CheckFeaturesSet(node) })
        checkFuncMap.add({ node: Node => CheckFeaturesDirective(node) })
        checkFuncMap.add({ node: Node => CheckFile(node) })
        checkFuncMap.add({ node: Node => CheckNode(node) })
    }

    public func CheckAST(node: Node): Unit {
        let visitPre = { curNode: Node =>
            if (curNode.IsInvalid() || curNode.TestAttr(Attribute.IS_BROKEN)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (curNode.TestAttr(Attribute.FROM_COMMON_PART)) {
                return VisitAction.SKIP_CHILDREN
            }
            CheckNode(curNode)
            if (curNode.IsDecl()) {
                CheckDecl(curNode)
            } else if (curNode.IsExpr()) {
                CheckExpr(curNode)
            }
            let funcIndex = ASTKindIndex(curNode.astKind)
            if (funcIndex >= 0 && funcIndex < checkFuncMap.size) {
                let checkFunc = checkFuncMap[funcIndex]
                checkFunc(curNode)
            }
            VisitAction.WALK_CHILDREN
        }
        Walker(node, visitPre: visitPre).Walk()
    }

    public func CheckAST(pkgs: ArrayList<Package>): Unit {
        for (pkg in pkgs) {
            CheckAST(pkg)
        }
        if (!checkInfoSet.isEmpty()) {
            for (checkInfo in checkInfoSet) {
                eprintln(checkInfo)
            }
            CJC_ABORT()
        }
    }

    public func CheckBeginEnd(node: Node): Unit {
        let visitPre = { curNode: Node =>
            if (curNode.IsInvalid() || curNode.TestAttr(Attribute.IS_BROKEN)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (curNode.TestAttr(Attribute.FROM_COMMON_PART)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (curNode.astKind == ASTKind.PACKAGE || curNode.astKind == ASTKind.PACKAGE_DECL) {
                return VisitAction.WALK_CHILDREN
            }
            if (curNode.TestAttr(Attribute.COMPILER_ADD)) {
                return VisitAction.WALK_CHILDREN
            }
            if (curNode.begin.IsZero()) {
                CollectInfo(curNode, "curNode->begin")
            }
            if (curNode.end.IsZero()) {
                CollectInfo(curNode, "curNode->end")
            }
            VisitAction.WALK_CHILDREN
        }
        Walker(node, visitPre: visitPre).Walk()
    }

    public func CheckBeginEnd(pkgs: ArrayList<Package>): Unit {
        for (pkg in pkgs) {
            CheckBeginEnd(pkg)
        }
        if (!checkInfoSet.isEmpty()) {
            for (filePath in checkInfoSet) {
                eprintln(filePath)
            }
            CJC_ABORT()
        }
    }

    private func CheckNode(node: Node): Unit {
        ZERO_POSITION_CHECK(node, node.begin, "node->begin")
        ZERO_POSITION_CHECK(node, node.end, "node->end")
        if (node.astKind != ASTKind.PACKAGE && node.astKind != ASTKind.PACKAGE_SPEC) {
            ATTR_NULLPTR_CHECK(this, node, node.curFile, "node->curFile")
        }
    }

    private func CheckExpr(node: Node): Unit {
        if (let Some(expr) <- (node as Expr)) {
            if (expr.hasSemi) {
                ZERO_POSITION_CHECK(node, expr.semiPos, "expr->semiPos")
            }
        }
    }

    private func CheckIfExpr(node: Node): Unit {
        if (let Some(ifExpr) <- (node as IfExpr)) {
            ZERO_POSITION_CHECK(node, ifExpr.ifPos, "ifExpr->ifPos")
            ZERO_POSITION_CHECK(node, ifExpr.leftParenPos, "ifExpr->leftParenPos")
            ZERO_POSITION_CHECK(node, ifExpr.rightParenPos, "ifExpr->rightParenPos")
            AST_NULLPTR_CHECK(this, node, ifExpr.condExpr, "ifExpr->condExpr")
            AST_NULLPTR_CHECK(this, node, ifExpr.thenBody, "ifExpr->thenBody")
            if (ifExpr.hasElse) {
                ZERO_POSITION_CHECK(node, ifExpr.elsePos, "ifExpr->elsePos")
                AST_NULLPTR_CHECK(this, node, ifExpr.elseBody, "ifExpr->elseBody")
            }
        }
    }

    private func CheckAnnotation(node: Node): Unit {
        if (let Some(anno) <- (node as Annotation)) {
            EMPTY_STRING_CHECK(node, anno.identifier.Val(), "anno->identifier")
            VEC_AST_NULLPTR_CHECK(node, anno.args, "anno->args")
            match (anno.kind) {
                case AnnotationKind.JAVA =>
                    EMPTY_STRING_CHECK(node, anno.definedPackage, "anno->definedPackage")
                case AnnotationKind.WHEN =>
                    AST_NULLPTR_CHECK(this, node, anno.condExpr, "anno->condExpr")
                case AnnotationKind.ATTRIBUTE =>
                    VEC_ZERO_POS_CHECK(node, anno.attrCommas, "anno->attrCommas")
                case _ => ()
            }
        }
    }

    private func CheckClassBody(node: Node): Unit {
        if (let Some(cb) <- (node as ClassBody)) {
            ZERO_POSITION_CHECK(node, cb.leftCurlPos, "cb->leftCurlPos")
            VEC_AST_NULLPTR_CHECK(node, cb.decls, "cb->decls")
            ZERO_POSITION_CHECK(node, cb.rightCurlPos, "cb->rightCurlPos")
        }
    }

    private func CheckDecl(node: Node): Unit {
        if (let Some(decl) <- (node as Decl)) {
            VEC_AST_NULLPTR_CHECK(node, decl.annotations, "decl->annotations")
            EMPTY_IDENTIFIER_CHECK(node, decl.identifier, "decl->identifier")
            ZERO_POSITION_CHECK(node, decl.keywordPos, "decl->keywordPos")
            EMPTY_STRING_CHECK(node, decl.fullPackageName, "decl->fullPackageName")
        }
    }

    private func CheckFile(node: Node): Unit {
        if (let Some(file) <- (node as File)) {
            EMPTY_STRING_CHECK(node, file.fileName, "file->fileName")
            EMPTY_STRING_CHECK(node, file.filePath, "file->filePath")
            VEC_AST_NULLPTR_CHECK(node, file.imports, "file->imports")
            VEC_AST_NULLPTR_CHECK(node, file.decls, "file->decls")
            VEC_AST_NULLPTR_CHECK(node, file.trashBin, "file->trashBin")
            ATTR_NULLPTR_CHECK(this, node, file.curPackage, "file->curPackage")
        }
    }

    private func CheckFuncArg(node: Node): Unit {
        if (let Some(funcArg) <- (node as FuncArg)) {
            AST_NULLPTR_CHECK(this, node, funcArg.expr, "funcArg->expr")
        }
    }

    private func CheckFuncBody(node: Node): Unit {
        if (let Some(funcBody) <- (node as FuncBody)) {
            VEC_AST_NULLPTR_CHECK(node, funcBody.paramLists, "funcBody->paramLists")
        }
    }

    private func CheckFuncParamList(node: Node): Unit {
        if (let Some(fpl) <- (node as FuncParamList)) {
            ZERO_POSITION_CHECK(node, fpl.leftParenPos, "fpl->leftParenPos")
            ZERO_POSITION_CHECK(node, fpl.rightParenPos, "fpl->rightParenPos")
            VEC_AST_NULLPTR_CHECK(node, fpl.params, "fpl->params")
        }
    }

    private func CheckMacroExpandParam(node: Node): Unit {
        if (let Some(mp) <- (node as MacroExpandParam)) {
            EMPTY_STRING_CHECK(node, mp.invocation.macroCallDiagInfo.fullName, "mp->invocation.macroCallDiagInfo.fullName")
            VEC_ZERO_POS_CHECK(node, mp.invocation.fullNameDotPos, "mp->invocation.fullNameDotPos")
            EMPTY_STRING_CHECK(node, mp.invocation.macroCallDiagInfo.identifier, "mp->invocation.macroCallDiagInfo.identifier")
            ZERO_POSITION_CHECK(node, mp.invocation.macroCallDiagInfo.identifierPos,
                "mp->invocation.macroCallDiagInfo.identifierPos")
        }
    }

    private func CheckGeneric(node: Node): Unit {
        if (let Some(ge) <- (node as Generic)) {
            ZERO_POSITION_CHECK(node, ge.leftAnglePos, "ge->leftAnglePos")
            ZERO_POSITION_CHECK(node, ge.rightAnglePos, "ge->rightAnglePos")
            VEC_AST_NULLPTR_CHECK(node, ge.typeParameters, "ge->typeParameters")
            VEC_AST_NULLPTR_CHECK(node, ge.genericConstraints, "ge->genericConstraints")
        }
    }

    private func CheckGenericConstraint(node: Node): Unit {
        if (let Some(gc) <- (node as GenericConstraint)) {
            ZERO_POSITION_CHECK(node, gc.wherePos, "gc->wherePos")
            AST_NULLPTR_CHECK(this, node, gc.refType, "gc->type")
            ZERO_POSITION_CHECK(node, gc.operatorPos, "gc->operatorPos")
            VEC_ZERO_POS_CHECK(node, gc.bitAndPos, "gc->bitAndPos")
            VEC_AST_NULLPTR_CHECK(node, gc.upperBounds, "gc->upperBounds")
            ZERO_POSITION_CHECK(node, gc.commaPos, "gc->commaPos")
        }
    }

    private func CheckImportContent(node: Node): Unit {
        if (let Some(ic) <- (node as ImportContent)) {
            VEC_EMPTY_STRING_CHECK(node, ic.prefixPaths, "ic->prefixPaths")
            VEC_ZERO_POS_CHECK(node, ic.prefixPoses, "ic->prefixPoses")
            VEC_ZERO_POS_CHECK(node, ic.prefixDotPoses, "ic->prefixDotPoses")
            if (ic.kind != ImportKind.IMPORT_MULTI) {
                EMPTY_IDENTIFIER_CHECK(node, ic.identifier, "ic->identifier")
                if (ic.kind == ImportKind.IMPORT_ALIAS) {
                    EMPTY_IDENTIFIER_CHECK(node, ic.aliasName, "ic->aliasName")
                }
            } else {
                ZERO_POSITION_CHECK(node, ic.leftCurlPos, "ic->leftCurlPos")
                VEC_ZERO_POS_CHECK(node, ic.commaPoses, "ic->commaPoses")
                ZERO_POSITION_CHECK(node, ic.rightCurlPos, "ic->rightCurlPos")
                for (item in ic.items) {
                    CheckImportContent(item)
                }
            }
        }
    }

    private func CheckImportSpec(node: Node): Unit {
        if (let Some(isNode) <- (node as ImportSpec)) {
            ZERO_POSITION_CHECK(node, isNode.importPos, "is->importPos")
            VEC_AST_NULLPTR_CHECK(node, isNode.annotations, "is->annotations")
        }
    }

    private func CheckInterfaceBody(node: Node): Unit {
        if (let Some(ib) <- (node as InterfaceBody)) {
            ZERO_POSITION_CHECK(node, ib.leftCurlPos, "ib->leftCurlPos")
            ZERO_POSITION_CHECK(node, ib.rightCurlPos, "ib->rightCurlPos")
            VEC_AST_NULLPTR_CHECK(node, ib.decls, "ib->decls")
        }
    }

    private func CheckMatchCase(node: Node): Unit {
        if (let Some(mc) <- (node as MatchCase)) {
            VEC_AST_NULLPTR_CHECK(node, mc.patterns, "mc->patterns")
            ZERO_POSITION_CHECK(node, mc.arrowPos, "mc->arrowPos")
            AST_NULLPTR_CHECK(this, node, mc.exprOrDecls, "mc->exprOrDecls")
        }
    }

    private func CheckMatchCaseOther(node: Node): Unit {
        if (let Some(mco) <- (node as MatchCaseOther)) {
            AST_NULLPTR_CHECK(this, node, mco.matchExpr, "mco->matchExpr")
            ZERO_POSITION_CHECK(node, mco.arrowPos, "mco->arrowPos")
            AST_NULLPTR_CHECK(this, node, mco.exprOrDecls, "mco->exprOrDecls")
        }
    }

    private func CheckPackage(node: Node): Unit {
        if (let Some(p) <- (node as Package)) {
            VEC_AST_NULLPTR_CHECK(node, p.files, "p->files")
            VEC_AST_NULLPTR_CHECK(node, p.genericInstantiatedDecls, "p->genericInstantiatedDecls")
            VEC_AST_NULLPTR_CHECK(node, p.inlineFuncDecls, "p->inlineFuncDecls")
        }
    }

    private func CheckPackageSpec(node: Node): Unit {
        if (let Some(ps) <- (node as PackageSpec)) {
            EMPTY_IDENTIFIER_CHECK(node, ps.packageName, "ps->packageName")
            ZERO_POSITION_CHECK(node, ps.packagePos, "ps->packagePos")
            VEC_EMPTY_STRING_CHECK(node, ps.prefixPaths, "ps->prefixPaths")
            VEC_ZERO_POS_CHECK(node, ps.prefixPoses, "ps->prefixPoses")
            VEC_ZERO_POS_CHECK(node, ps.prefixDotPoses, "ps->prefixDotPoses")
            if (ps.hasMacro) {
                ZERO_POSITION_CHECK(node, ps.macroPos, "ps->macroPos")
            }
        }
    }

    private func CheckFeaturesDirective(node: Node): Unit {
        if (let Some(fd) <- (node as FeaturesDirective)) {
            ZERO_POSITION_CHECK(node, fd.featuresPos, "fd->featuresPos")
        }
    }

    private func CheckFeaturesSet(node: Node): Unit {
        if (let Some(fs) <- (node as FeaturesSet)) {
            ZERO_POSITION_CHECK(node, fs.lCurlPos, "fs->lCurlPos")
            VEC_ZERO_POS_CHECK(node, fs.commaPoses, "fs->commaPoses")
            ZERO_POSITION_CHECK(node, fs.rCurlPos, "fs->rCurlPos")
        }
    }

    private func CheckFeatureId(node: Node): Unit {
        if (let Some(fc) <- (node as FeatureId)) {
            for (ident in fc.identifiers) {
                EMPTY_IDENTIFIER_CHECK(node, ident, "ident")
            }
            VEC_ZERO_POS_CHECK(node, fc.dotPoses, "fc->dotPoses")
        }
    }

    private func CheckStructBody(node: Node): Unit {
        if (let Some(sb) <- (node as StructBody)) {
            ZERO_POSITION_CHECK(node, sb.leftCurlPos, "sb->leftCurlPos")
            ZERO_POSITION_CHECK(node, sb.rightCurlPos, "sb->rightCurlPos")
            VEC_AST_NULLPTR_CHECK(node, sb.decls, "sb->decls")
        }
    }

    private func CheckFuncDecl(node: Node): Unit {
        if (let Some(fd) <- (node as FuncDecl)) {
            ZERO_POSITION_CHECK(node, fd.leftParenPos, "fd->leftParenPos")
            ZERO_POSITION_CHECK(node, fd.rightParenPos, "fd->rightParenPos")
            AST_NULLPTR_CHECK(this, node, fd.funcBody, "fd->funcBody")
        }
    }

    private func CheckInheritableDecl(node: Node): Unit {
        if (let Some(id) <- (node as InheritableDecl)) {
            ZERO_POSITION_CHECK(node, id.upperBoundPos, "id->upperBoundPos")
            VEC_AST_NULLPTR_CHECK(node, id.inheritedTypes, "id->inheritedTypes")
        }
    }

    private func CheckMacroDecl(node: Node): Unit {
        if (let Some(md) <- (node as MacroDecl)) {
            AST_NULLPTR_CHECK(this, node, md.funcBody, "md->funcBody")
        }
    }

    private func CheckMacroExpandDecl(node: Node): Unit {
        if (let Some(me) <- (node as MacroExpandDecl)) {
            EMPTY_STRING_CHECK(node, me.invocation.macroCallDiagInfo.fullName, "me->invocation.macroCallDiagInfo.fullName")
            VEC_ZERO_POS_CHECK(node, me.invocation.fullNameDotPos, "me->invocation.fullNameDotPos")
            EMPTY_STRING_CHECK(node, me.invocation.macroCallDiagInfo.identifier, "me->invocation.macroCallDiagInfo.identifier")
            ZERO_POSITION_CHECK(node, me.invocation.macroCallDiagInfo.identifierPos,
                "me->invocation.macroCallDiagInfo.identifierPos")
        }
    }

    private func CheckMainDecl(node: Node): Unit {
        if (let Some(md) <- (node as MainDecl)) {
            AST_NULLPTR_CHECK(this, node, md.funcBody, "md->funcBody")
        }
    }

    private func CheckPackageDecl(node: Node): Unit {
        if (let Some(pd) <- (node as PackageDecl)) {
            let _ = pd.srcPackage
        }
    }

    private func CheckPrimaryCtorDecl(node: Node): Unit {
        if (let Some(pc) <- (node as PrimaryCtorDecl)) {
            AST_NULLPTR_CHECK(this, node, pc.funcBody, "pc->funcBody")
        }
    }

    private func CheckTypeAliasDecl(node: Node): Unit {
        if (let Some(ta) <- (node as TypeAliasDecl)) {
            ZERO_POSITION_CHECK(node, ta.assignPos, "ta->assignPos")
            AST_NULLPTR_CHECK(this, node, ta.typeNode, "ta->type")
        }
    }

    private func CheckVarWithPatternDecl(node: Node): Unit {
        if (let Some(vwp) <- (node as VarWithPatternDecl)) {
            AST_NULLPTR_CHECK(this, node, vwp.irrefutablePattern, "vwp->irrefutablePattern")
        }
    }

    private func CheckFuncParam(node: Node): Unit {
        if (let Some(fp) <- (node as FuncParam)) {
            ZERO_POSITION_CHECK(node, fp.colonPos, "fp->colonPos")
        }
    }

    private func CheckPropDecl(node: Node): Unit {
        if (let Some(pd) <- (node as PropDecl)) {
            ZERO_POSITION_CHECK(node, pd.colonPos, "pd->colonPos")
            AST_NULLPTR_CHECK(this, node, pd.typeNode, "pd->type")
            ZERO_POSITION_CHECK(node, pd.leftCurlPos, "pd->leftCurlPos")
            VEC_AST_NULLPTR_CHECK(node, pd.getters, "pd->getters")
            VEC_AST_NULLPTR_CHECK(node, pd.setters, "pd->setters")
            ZERO_POSITION_CHECK(node, pd.rightCurlPos, "pd->rightCurlPos")
        }
    }

    private func CheckClassLikeDecl(node: Node): Unit {
        CheckInheritableDecl(node)
    }

    private func CheckClassDecl(node: Node): Unit {
        CheckClassLikeDecl(node)
        if (let Some(cd) <- (node as ClassDecl)) {
            AST_NULLPTR_CHECK(this, node, cd.body, "cd->body")
        }
    }

    private func CheckInterfaceDecl(node: Node): Unit {
        CheckClassLikeDecl(node)
        if (let Some(id) <- (node as InterfaceDecl)) {
            AST_NULLPTR_CHECK(this, node, id.body, "id->body")
        }
    }

    private func CheckEnumDecl(node: Node): Unit {
        CheckInheritableDecl(node)
        if (let Some(ed) <- (node as EnumDecl)) {
            ZERO_POSITION_CHECK(node, ed.leftCurlPos, "ed->leftCurlPos")
            AST_NULLPTR_CHECK(this, node, ed.bodyScope, "ed->bodyScope")
            VEC_AST_NULLPTR_CHECK(node, ed.constructors, "ed->constructors")
            VEC_ZERO_POS_CHECK(node, ed.bitOrPosVector, "ed->bitOrPosVector")
            VEC_AST_NULLPTR_CHECK(node, ed.members, "ed->members")
        }
    }

    private func CheckExtendDecl(node: Node): Unit {
        CheckInheritableDecl(node)
        if (let Some(ed) <- (node as ExtendDecl)) {
            AST_NULLPTR_CHECK(this, node, ed.extendedType, "ed->extendedType")
            AST_NULLPTR_CHECK(this, node, ed.bodyScope, "ed->bodyScope")
            ZERO_POSITION_CHECK(node, ed.leftCurlPos, "ed->leftCurlPos")
            ZERO_POSITION_CHECK(node, ed.rightCurlPos, "ed->rightCurlPos")
            VEC_AST_NULLPTR_CHECK(node, ed.members, "ed->members")
        }
    }

    private func CheckStructDecl(node: Node): Unit {
        CheckInheritableDecl(node)
        if (let Some(sd) <- (node as StructDecl)) {
            AST_NULLPTR_CHECK(this, node, sd.body, "sd->body")
        }
    }

    private func CheckArrayExpr(node: Node): Unit {
        if (let Some(ae) <- (node as ArrayExpr)) {
            AST_NULLPTR_CHECK(this, node, ae.typeNode, "ae->type")
            ZERO_POSITION_CHECK(node, ae.leftParenPos, "ae->leftParenPos")
            VEC_AST_NULLPTR_CHECK(node, ae.args, "ae->args")
            VEC_ZERO_POS_CHECK(node, ae.commaPosVector, "ae->commaPosVector")
            ZERO_POSITION_CHECK(node, ae.rightParenPos, "ae->rightParenPos")
        }
    }

    private func CheckArrayLit(node: Node): Unit {
        if (let Some(al) <- (node as ArrayLit)) {
            ZERO_POSITION_CHECK(node, al.leftSquarePos, "al->leftSquarePos")
            VEC_AST_NULLPTR_CHECK(node, al.children, "al->children")
            VEC_ZERO_POS_CHECK(node, al.commaPosVector, "al->commaPosVector")
            ZERO_POSITION_CHECK(node, al.rightSquarePos, "al->rightSquarePos")
        }
    }

    private func CheckAsExpr(node: Node): Unit {
        if (let Some(ae) <- (node as AsExpr)) {
            AST_NULLPTR_CHECK(this, node, ae.leftExpr, "ae->leftExpr")
            AST_NULLPTR_CHECK(this, node, ae.asType, "ae->asType")
            ZERO_POSITION_CHECK(node, ae.asPos, "ae->asPos")
        }
    }

    private func CheckBlock(node: Node): Unit {
        if (let Some(ae) <- (node as Block)) {
            ZERO_POSITION_CHECK(node, ae.leftCurlPos, "ae->leftCurlPos")
            VEC_AST_NULLPTR_CHECK(node, ae.body, "ae->body")
            ZERO_POSITION_CHECK(node, ae.rightCurlPos, "ae->rightCurlPos")
        }
    }

    private func CheckCallExpr(node: Node): Unit {
        if (let Some(ce) <- (node as CallExpr)) {
            AST_NULLPTR_CHECK(this, node, ce.baseFunc, "ce->baseFunc")
            ZERO_POSITION_CHECK(node, ce.leftParenPos, "ce->leftParenPos")
            VEC_AST_NULLPTR_CHECK(node, ce.args, "ce->args")
            ZERO_POSITION_CHECK(node, ce.rightParenPos, "ce->rightParenPos")
        }
    }

    private func CheckDoWhileExpr(node: Node): Unit {
        if (let Some(dwe) <- (node as DoWhileExpr)) {
            ZERO_POSITION_CHECK(node, dwe.doPos, "dwe->doPos")
            AST_NULLPTR_CHECK(this, node, dwe.body, "dwe->body")
            ZERO_POSITION_CHECK(node, dwe.whilePos, "dwe->whilePos")
            ZERO_POSITION_CHECK(node, dwe.leftParenPos, "dwe->leftParenPos")
            AST_NULLPTR_CHECK(this, node, dwe.condExpr, "dwe->condExpr")
            ZERO_POSITION_CHECK(node, dwe.rightParenPos, "dwe->rightParenPos")
        }
    }

    private func CheckForInExpr(node: Node): Unit {
        if (let Some(fie) <- (node as ForInExpr)) {
            ZERO_POSITION_CHECK(node, fie.leftParenPos, "fie->leftParenPos")
            AST_NULLPTR_CHECK(this, node, fie.pattern, "fie->pattern")
            ZERO_POSITION_CHECK(node, fie.rightParenPos, "fie->rightParenPos")
            if (!fie.wherePos.IsZero()) {
                AST_NULLPTR_CHECK(this, node, fie.patternGuard, "fie->patternGuard")
            }
            AST_NULLPTR_CHECK(this, node, fie.body, "fie->body")
        }
    }

    private func CheckIsExpr(node: Node): Unit {
        if (let Some(ie) <- (node as IsExpr)) {
            AST_NULLPTR_CHECK(this, node, ie.leftExpr, "ie->leftExpr")
            AST_NULLPTR_CHECK(this, node, ie.isType, "ie->isType")
            ZERO_POSITION_CHECK(node, ie.isPos, "ie->isPos")
        }
    }

    private func CheckLambdaExpr(node: Node): Unit {
        if (let Some(le) <- (node as LambdaExpr)) {
            AST_NULLPTR_CHECK(this, node, le.funcBody, "le->funcBody")
        }
    }

    private func CheckLetPatternDestructor(node: Node): Unit {
        if (let Some(lpd) <- (node as LetPatternDestructor)) {
            for (pat in lpd.patterns) {
                let _ = pat
            }
            for (ors in lpd.orPos) {
                ZERO_POSITION_CHECK(node, ors, "lpd->orPos")
            }
            AST_NULLPTR_CHECK(this, node, lpd.initializer, "lpd->initializer")
            ZERO_POSITION_CHECK(node, lpd.backarrowPos, "lpd->backarrowPos")
        }
    }

    private func CheckLitConstExpr(node: Node): Unit {
        if (let Some(lce) <- (node as LitConstExpr)) {
            EMPTY_STRING_CHECK(node, lce.stringValue, "lce->stringValue")
        }
    }

    private func CheckMacroExpandExpr(node: Node): Unit {
        if (let Some(me) <- (node as MacroExpandExpr)) {
            EMPTY_STRING_CHECK(node, me.invocation.macroCallDiagInfo.fullName, "me->invocation.macroCallDiagInfo.fullName")
            VEC_ZERO_POS_CHECK(node, me.invocation.fullNameDotPos, "me->invocation.fullNameDotPos")
            EMPTY_STRING_CHECK(node, me.invocation.macroCallDiagInfo.identifier, "me->invocation.macroCallDiagInfo.identifier")
            ZERO_POSITION_CHECK(node, me.invocation.macroCallDiagInfo.identifierPos,
                "me->invocation.macroCallDiagInfo.identifierPos")
            VEC_AST_NULLPTR_CHECK(node, me.annotations, "me->annotations")
        }
    }

    private func CheckMatchExpr(node: Node): Unit {
        if (let Some(me) <- (node as MatchExpr)) {
            ZERO_POSITION_CHECK(node, me.leftCurlPos, "me->leftCurlPos")
            VEC_AST_NULLPTR_CHECK(node, me.matchCases, "me->matchCases")
            VEC_AST_NULLPTR_CHECK(node, me.matchCaseOthers, "me->matchCaseOthers")
            ZERO_POSITION_CHECK(node, me.rightCurlPos, "me->rightCurlPos")
            if (me.matchMode) {
                AST_NULLPTR_CHECK(this, node, me.selector, "me->selector")
                ZERO_POSITION_CHECK(node, me.leftParenPos, "me->leftParenPos")
                ZERO_POSITION_CHECK(node, me.rightParenPos, "me->rightParenPos")
            }
        }
    }

    private func CheckMemberAccess(node: Node): Unit {
        if (let Some(ma) <- (node as MemberAccess)) {
            AST_NULLPTR_CHECK(this, node, ma.baseExpr, "ma->baseExpr")
            ZERO_POSITION_CHECK(node, ma.dotPos, "ma->dotPos")
            EMPTY_IDENTIFIER_CHECK(node, ma.field, "ma->field")
        }
    }

    private func CheckTypeConvExpr(node: Node): Unit {
        if (let Some(ntc) <- (node as TypeConvExpr)) {
            AST_NULLPTR_CHECK(this, node, ntc.typeNode, "ntc->type")
            ZERO_POSITION_CHECK(node, ntc.leftParenPos, "ntc->leftParenPos")
            AST_NULLPTR_CHECK(this, node, ntc.expr, "ntc->expr")
            ZERO_POSITION_CHECK(node, ntc.rightParenPos, "ntc->rightParenPos")
        }
    }

    private func CheckIfAvailableExpr(node: Node): Unit {
        if (let Some(ie) <- (node as IfAvailableExpr)) {
            AST_NULLPTR_CHECK(this, node, ie.GetArg(), "ie->GetArg()")
            AST_NULLPTR_CHECK(this, node, ie.GetLambda1(), "ie->GetLambda1()")
            AST_NULLPTR_CHECK(this, node, ie.GetLambda2(), "ie->GetLambda2()")
        }
    }

    private func CheckParenExpr(node: Node): Unit {
        if (let Some(pe) <- (node as ParenExpr)) {
            ZERO_POSITION_CHECK(node, pe.leftParenPos, "pe->leftParenPos")
            AST_NULLPTR_CHECK(this, node, pe.expr, "pe->expr")
            ZERO_POSITION_CHECK(node, pe.rightParenPos, "pe->rightParenPos")
        }
    }

    private func CheckPointerExpr(node: Node): Unit {
        if (let Some(pe) <- (node as PointerExpr)) {
            AST_NULLPTR_CHECK(this, node, pe.typeNode, "pe->type")
            AST_NULLPTR_CHECK(this, node, pe.arg, "pe->arg")
        }
    }

    private func CheckQuoteExpr(node: Node): Unit {
        if (let Some(qe) <- (node as QuoteExpr)) {
            ZERO_POSITION_CHECK(node, qe.quotePos, "qe->quotePos")
            ZERO_POSITION_CHECK(node, qe.leftParenPos, "qe->leftParenPos")
            ZERO_POSITION_CHECK(node, qe.rightParenPos, "qe->rightParenPos")
        }
    }

    private func CheckRangeExpr(node: Node): Unit {
        if (let Some(re) <- (node as RangeExpr)) {
            ZERO_POSITION_CHECK(node, re.rangePos, "re->rangePos")
        }
    }

    private func CheckRefExpr(node: Node): Unit {
        if (let Some(re) <- (node as RefExpr)) {
            EMPTY_IDENTIFIER_CHECK(node, re.ref.identifier, "re->ref.identifier")
        }
    }

    private func CheckReturnExpr(node: Node): Unit {
        if (let Some(re) <- (node as ReturnExpr)) {
            ZERO_POSITION_CHECK(node, re.returnPos, "re->returnPos")
            AST_NULLPTR_CHECK(this, node, re.expr, "re->expr")
        }
    }

    private func CheckSpawnExpr(node: Node): Unit {
        if (let Some(se) <- (node as SpawnExpr)) {
            ZERO_POSITION_CHECK(node, se.spawnPos, "se->spawnPos")
            AST_NULLPTR_CHECK(this, node, se.task, "se->task")
        }
    }

    private func CheckSynchronizedExpr(node: Node): Unit {
        if (let Some(se) <- (node as SynchronizedExpr)) {
            ZERO_POSITION_CHECK(node, se.syncPos, "se->syncPos")
            ZERO_POSITION_CHECK(node, se.leftParenPos, "se->leftParenPos")
            AST_NULLPTR_CHECK(this, node, se.mutex, "se->mutex")
            ZERO_POSITION_CHECK(node, se.rightParenPos, "se->rightParenPos")
            AST_NULLPTR_CHECK(this, node, se.body, "se->body")
        }
    }

    private func CheckThrowExpr(node: Node): Unit {
        if (let Some(te) <- (node as ThrowExpr)) {
            ZERO_POSITION_CHECK(node, te.throwPos, "te->throwPos")
            AST_NULLPTR_CHECK(this, node, te.expr, "te->expr")
        }
    }

    private func CheckPerformExpr(node: Node): Unit {
        if (let Some(pe) <- (node as PerformExpr)) {
            ZERO_POSITION_CHECK(node, pe.performPos, "pe->performPos")
            AST_NULLPTR_CHECK(this, node, pe.expr, "pe->expr")
        }
    }

    private func CheckResumeExpr(node: Node): Unit {
        if (let Some(re) <- (node as ResumeExpr)) {
            ZERO_POSITION_CHECK(node, re.resumePos, "re->resumePos")
            if (let Some(_) <- re.withExpr) {
                ZERO_POSITION_CHECK(node, re.withPos, "re->withPos")
            }
            if (let Some(_) <- re.throwingExpr) {
                ZERO_POSITION_CHECK(node, re.throwingPos, "re->throwingPos")
            }
        }
    }

    private func CheckTrailingClosureExpr(node: Node): Unit {
        if (let Some(tce) <- (node as TrailingClosureExpr)) {
            ZERO_POSITION_CHECK(node, tce.leftLambda, "tce->leftLambda")
            AST_NULLPTR_CHECK(this, node, tce.expr, "tce->expr")
            AST_NULLPTR_CHECK(this, node, tce.lambda, "tce->lambda")
            ZERO_POSITION_CHECK(node, tce.rightLambda, "tce->rightLambda")
        }
    }

    private func CheckTryExpr(node: Node): Unit {
        if (let Some(te) <- (node as TryExpr)) {
            ZERO_POSITION_CHECK(node, te.tryPos, "te->tryPos")
            VEC_AST_NULLPTR_CHECK(node, te.resourceSpec, "te->resourceSpec")
            AST_NULLPTR_CHECK(this, node, te.tryBlock, "te->tryBlock")
            VEC_ZERO_POS_CHECK(node, te.catchPosVector, "te->catchPosVector")
            VEC_AST_NULLPTR_CHECK(node, te.catchBlocks, "te->catchBlocks")
            VEC_AST_NULLPTR_CHECK(node, te.catchPatterns, "te->catchPatterns")
            for (handler in te.handlers) {
                ZERO_POSITION_CHECK(node, handler.pos, "handler.pos")
                AST_NULLPTR_CHECK(this, node, handler.block, "handler.block")
                AST_NULLPTR_CHECK(this, node, handler.commandPattern, "handler.commandPattern")
            }
        }
    }

    private func CheckTupleLit(node: Node): Unit {
        if (let Some(te) <- (node as TupleLit)) {
            ZERO_POSITION_CHECK(node, te.leftParenPos, "te->leftParenPos")
            VEC_AST_NULLPTR_CHECK(node, te.children, "te->children")
            VEC_ZERO_POS_CHECK(node, te.commaPosVector, "te->commaPosVector")
            ZERO_POSITION_CHECK(node, te.rightParenPos, "te->rightParenPos")
        }
    }

    private func CheckWhileExpr(node: Node): Unit {
        if (let Some(we) <- (node as WhileExpr)) {
            ZERO_POSITION_CHECK(node, we.whilePos, "we->whilePos")
            ZERO_POSITION_CHECK(node, we.leftParenPos, "we->leftParenPos")
            AST_NULLPTR_CHECK(this, node, we.condExpr, "we->condExpr")
            ZERO_POSITION_CHECK(node, we.rightParenPos, "we->rightParenPos")
            AST_NULLPTR_CHECK(this, node, we.body, "we->body")
        }
    }

    private func CheckAssignExpr(node: Node): Unit {
        if (let Some(ae) <- (node as AssignExpr)) {
            AST_NULLPTR_CHECK(this, node, ae.leftValue, "ae->leftValue")
            AST_NULLPTR_CHECK(this, node, ae.rightExpr, "ae->rightExpr")
            ZERO_POSITION_CHECK(node, ae.assignPos, "ae->assignPos")
        }
    }

    private func CheckBinaryExpr(node: Node): Unit {
        if (let Some(be) <- (node as BinaryExpr)) {
            AST_NULLPTR_CHECK(this, node, be.leftExpr, "be->leftExpr")
            AST_NULLPTR_CHECK(this, node, be.rightExpr, "be->rightExpr")
            ZERO_POSITION_CHECK(node, be.operatorPos, "be->operatorPos")
        }
    }

    private func CheckIncOrDecExpr(node: Node): Unit {
        if (let Some(iod) <- (node as IncOrDecExpr)) {
            ZERO_POSITION_CHECK(node, iod.operatorPos, "iod->operatorPos")
            AST_NULLPTR_CHECK(this, node, iod.expr, "iod->expr")
        }
    }

    private func CheckSubscriptExpr(node: Node): Unit {
        if (let Some(se) <- (node as SubscriptExpr)) {
            AST_NULLPTR_CHECK(this, node, se.baseExpr, "se->baseExpr")
            ZERO_POSITION_CHECK(node, se.leftParenPos, "se->leftParenPos")
            VEC_AST_NULLPTR_CHECK(node, se.indexExprs, "se->indexExprs")
            VEC_ZERO_POS_CHECK(node, se.commaPos, "se->commaPos")
            ZERO_POSITION_CHECK(node, se.rightParenPos, "se->rightParenPos")
        }
    }

    private func CheckUnaryExpr(node: Node): Unit {
        if (let Some(ue) <- (node as UnaryExpr)) {
            AST_NULLPTR_CHECK(this, node, ue.expr, "ue->expr")
            ZERO_POSITION_CHECK(node, ue.operatorPos, "ue->operatorPos")
        }
    }

    private func CheckConstantType(node: Node): Unit {
        if (let Some(ct) <- (node as ConstantType)) {
            AST_NULLPTR_CHECK(this, node, ct.constantExpr, "ct->constantExpr")
            ZERO_POSITION_CHECK(node, ct.dollarPos, "ct->dollarPos")
        }
    }

    private func CheckConstPattern(node: Node): Unit {
        if (let Some(cp) <- (node as ConstPattern)) {
            AST_NULLPTR_CHECK(this, node, cp.literal, "cp->literal")
        }
    }

    private func CheckEnumPattern(node: Node): Unit {
        if (let Some(ep) <- (node as EnumPattern)) {
            AST_NULLPTR_CHECK(this, node, ep.constructor, "ep->constructor")
            VEC_AST_NULLPTR_CHECK(node, ep.patterns, "ep->patterns")
            ZERO_POSITION_CHECK(node, ep.leftParenPos, "ep->leftParenPos")
            ZERO_POSITION_CHECK(node, ep.rightParenPos, "ep->rightParenPos")
        }
    }

    private func CheckExceptTypePattern(node: Node): Unit {
        if (let Some(etp) <- (node as ExceptTypePattern)) {
            AST_NULLPTR_CHECK(this, node, etp.pattern, "etp->pattern")
            ZERO_POSITION_CHECK(node, etp.patternPos, "etp->patternPos")
            ZERO_POSITION_CHECK(node, etp.colonPos, "etp->colonPos")
            VEC_AST_NULLPTR_CHECK(node, etp.types, "etp->types")
            VEC_ZERO_POS_CHECK(node, etp.bitOrPosVector, "etp->bitOrPosVector")
        }
    }

    private func CheckCommandTypePattern(node: Node): Unit {
        if (let Some(etp) <- (node as CommandTypePattern)) {
            AST_NULLPTR_CHECK(this, node, etp.pattern, "etp->pattern")
            ZERO_POSITION_CHECK(node, etp.patternPos, "etp->patternPos")
            ZERO_POSITION_CHECK(node, etp.colonPos, "etp->colonPos")
            VEC_AST_NULLPTR_CHECK(node, etp.types, "etp->types")
            VEC_ZERO_POS_CHECK(node, etp.bitOrPosVector, "etp->bitOrPosVector")
        }
    }

    private func CheckTuplePattern(node: Node): Unit {
        if (let Some(tp) <- (node as TuplePattern)) {
            ZERO_POSITION_CHECK(node, tp.leftBracePos, "tp->leftBracePos")
            VEC_AST_NULLPTR_CHECK(node, tp.patterns, "tp->patterns")
            ZERO_POSITION_CHECK(node, tp.rightBracePos, "tp->rightBracePos")
        }
    }

    private func CheckTypePattern(node: Node): Unit {
        if (let Some(tp) <- (node as TypePattern)) {
            AST_NULLPTR_CHECK(this, node, tp.pattern, "tp->pattern")
            ZERO_POSITION_CHECK(node, tp.colonPos, "tp->colonPos")
            AST_NULLPTR_CHECK(this, node, tp.typeNode, "tp->type")
        }
    }

    private func CheckVarOrEnumPattern(node: Node): Unit {
        if (let Some(voe) <- (node as VarOrEnumPattern)) {
            EMPTY_STRING_CHECK(node, voe.identifier.Val(), "voe->identifier")
        }
    }

    private func CheckVarPattern(node: Node): Unit {
        if (let Some(vp) <- (node as VarPattern)) {
            AST_NULLPTR_CHECK(this, node, vp.varDecl, "vp->varDecl")
        }
    }

    private func CheckVArrayType(node: Node): Unit {
        if (let Some(vat) <- (node as VArrayType)) {
            AST_NULLPTR_CHECK(this, node, vat.typeArgument, "vat->typeArgument")
            AST_NULLPTR_CHECK(this, node, vat.constantType, "vat->constantType")
            ZERO_POSITION_CHECK(node, vat.leftAnglePos, "vat->leftAnglePos")
            ZERO_POSITION_CHECK(node, vat.rightAnglePos, "vat->rightAnglePos")
        }
    }

    private func CheckFuncType(node: Node): Unit {
        if (let Some(ft) <- (node as FuncType)) {
            ZERO_POSITION_CHECK(node, ft.leftParenPos, "ft->leftParenPos")
            VEC_AST_NULLPTR_CHECK(node, ft.paramTypes, "ft->paramTypes")
            ZERO_POSITION_CHECK(node, ft.rightParenPos, "ft->rightParenPos")
            ZERO_POSITION_CHECK(node, ft.arrowPos, "ft->arrowPos")
            AST_NULLPTR_CHECK(this, node, ft.retType, "ft->retType")
        }
    }

    private func CheckOptionType(node: Node): Unit {
        if (let Some(ot) <- (node as OptionType)) {
            if (ot.questNum > 0u64) {
                AST_NULLPTR_CHECK(this, node, ot.componentType, "ot->componentType")
            }
            VEC_ZERO_POS_CHECK(node, ot.questVector, "ot->questVector")
        }
    }

    private func CheckParenType(node: Node): Unit {
        if (let Some(pt) <- (node as ParenType)) {
            ZERO_POSITION_CHECK(node, pt.leftParenPos, "pt->leftParenPos")
            AST_NULLPTR_CHECK(this, node, pt.innerType, "pt->type")
            ZERO_POSITION_CHECK(node, pt.rightParenPos, "pt->rightParenPos")
        }
    }

    private func CheckPrimitiveType(node: Node): Unit {
        if (let Some(pt) <- (node as PrimitiveType)) {
            EMPTY_STRING_CHECK(node, pt.str, "pt->str")
        }
    }

    private func CheckQualifiedType(node: Node): Unit {
        if (let Some(qt) <- (node as QualifiedType)) {
            AST_NULLPTR_CHECK(this, node, qt.baseType, "qt->baseType")
            ZERO_POSITION_CHECK(node, qt.dotPos, "qt->dotPos")
            EMPTY_IDENTIFIER_CHECK(node, qt.field, "qt->field")
        }
    }

    private func CheckRefType(node: Node): Unit {
        if (let Some(rt) <- (node as RefType)) {
            EMPTY_IDENTIFIER_CHECK(node, rt.ref.identifier, "rt->ref.identifier")
        }
    }

    private func CheckTupleType(node: Node): Unit {
        if (let Some(tt) <- (node as TupleType)) {
            ZERO_POSITION_CHECK(node, tt.leftParenPos, "tt->leftParenPos")
            ZERO_POSITION_CHECK(node, tt.rightParenPos, "tt->rightParenPos")
            VEC_AST_NULLPTR_CHECK(node, tt.fieldTypes, "tt->fieldTypes")
            VEC_ZERO_POS_CHECK(node, tt.commaPosVector, "tt->commaPosVector")
        }
    }

    func CollectInfo(node: Node, subInfo: String): Unit {
        var info = subInfo
        if (let Some(pos) <- subInfo.lastIndexOf("->")) {
            info = subInfo[(pos + 2)..]
        } else if (!subInfo.isEmpty()) {
            info = subInfo[1..]
        }
        var item = "ASTChecker: " + ASTKindName(node.astKind) + "'s " + info + " is not initialized at "
        if (let Some(file) <- node.curFile) {
            item += file.filePath
        }
        if (!node.begin.IsZero()) {
            item += ":" + node.begin.line.toString() + ":" + node.begin.column.toString()
        } else if (!node.end.IsZero()) {
            item += ":" + node.end.line.toString() + ":" + node.end.column.toString()
        }
        checkInfoSet.add(item)
    }

    private func CheckModifier(node: Node): Unit { let _ = node }
    private func CheckBuiltInDecl(node: Node): Unit { let _ = node }
    private func CheckVarDecl(node: Node): Unit { let _ = node }
    private func CheckGenericParamDecl(node: Node): Unit { let _ = node }
    private func CheckInvalidDecl(node: Node): Unit { let _ = node }
    private func CheckPattern(node: Node): Unit { let _ = node }
    private func CheckWildcardPattern(node: Node): Unit { let _ = node }
    private func CheckInvalidPattern(node: Node): Unit { let _ = node }
    private func CheckType(node: Node): Unit { let _ = node }
    private func CheckThisType(node: Node): Unit { let _ = node }
    private func CheckInvalidType(node: Node): Unit { let _ = node }
    private func CheckOptionalExpr(node: Node): Unit { let _ = node }
    private func CheckOptionalChainExpr(node: Node): Unit { let _ = node }
    private func CheckPrimitiveTypeExpr(node: Node): Unit { let _ = node }
    private func CheckInterpolationExpr(node: Node): Unit { let _ = node }
    private func CheckStrInterpolationExpr(node: Node): Unit { let _ = node }
    private func CheckTokenPart(node: Node): Unit { let _ = node }
    private func CheckJumpExpr(node: Node): Unit { let _ = node }
    private func CheckInvalidExpr(node: Node): Unit { let _ = node }
    private func CheckDummyBody(node: Node): Unit { let _ = node }
    private func CheckWildcardExpr(node: Node): Unit { let _ = node }
}
