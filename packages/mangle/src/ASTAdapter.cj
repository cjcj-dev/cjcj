package cangjie_compiler::mangle

import std.collection.*
import cangjie_compiler::ast.*
import std.sync.AtomicInt64

private class AstDeclPair {
    public var source: Decl
    public var target: MangleDecl

    public init(source: Decl, target: MangleDecl) {
        this.source = source
        this.target = target
    }
}

private func AddAttrIf(target: MangleDecl, condition: Bool, attr: Attribute): Unit {
    if (condition) {
        target.attrs.add(attr)
    }
}

private func AddParamAttrIf(target: MangleFuncParam, condition: Bool, attr: Attribute): Unit {
    if (condition) {
        target.attrs.add(attr)
    }
}

private func CopyDeclAttributes(source: Decl, target: MangleDecl): Unit {
    AddAttrIf(target, source.TestAttr(Attribute.GLOBAL), Attribute.GLOBAL)
    AddAttrIf(target, source.TestAttr(Attribute.STATIC), Attribute.STATIC)
    AddAttrIf(target, source.TestAttr(Attribute.PUBLIC), Attribute.PUBLIC)
    AddAttrIf(target, source.TestAttr(Attribute.PRIVATE), Attribute.PRIVATE)
    AddAttrIf(target, source.TestAttr(Attribute.PROTECTED), Attribute.PROTECTED)
    AddAttrIf(target, source.TestAttr(Attribute.INTERNAL), Attribute.INTERNAL)
    AddAttrIf(target, source.TestAttr(Attribute.NO_MANGLE), Attribute.NO_MANGLE)
    AddAttrIf(target, source.TestAttr(Attribute.GENERIC), Attribute.GENERIC)
    AddAttrIf(target, source.TestAttr(Attribute.GENERIC_INSTANTIATED), Attribute.GENERIC_INSTANTIATED)
    AddAttrIf(target, source.TestAttr(Attribute.HAS_INITIAL), Attribute.HAS_INITIAL)
    AddAttrIf(target, source.TestAttr(Attribute.CONSTRUCTOR), Attribute.CONSTRUCTOR)
    AddAttrIf(target, source.TestAttr(Attribute.ENUM_CONSTRUCTOR), Attribute.ENUM_CONSTRUCTOR)
    AddAttrIf(target, source.TestAttr(Attribute.MAIN_ENTRY), Attribute.MAIN_ENTRY)
    AddAttrIf(target, source.TestAttr(Attribute.OPERATOR), Attribute.OPERATOR)
    AddAttrIf(target, source.TestAttr(Attribute.DEFAULT), Attribute.DEFAULT)
    AddAttrIf(target, source.TestAttr(Attribute.ABSTRACT), Attribute.ABSTRACT)
    AddAttrIf(target, source.TestAttr(Attribute.COMMON), Attribute.COMMON)
    AddAttrIf(target, source.TestAttr(Attribute.SPECIFIC), Attribute.SPECIFIC)
    AddAttrIf(target, source.TestAttr(Attribute.FOR_TEST), Attribute.FOR_TEST)
    for (modifier in source.modifiers) {
        if (modifier.modifier == TokenKind.PUBLIC) {
            AddAttrIf(target, true, Attribute.PUBLIC)
        } else if (modifier.modifier == TokenKind.PRIVATE) {
            AddAttrIf(target, true, Attribute.PRIVATE)
        } else if (modifier.modifier == TokenKind.PROTECTED) {
            AddAttrIf(target, true, Attribute.PROTECTED)
        } else if (modifier.modifier == TokenKind.INTERNAL) {
            AddAttrIf(target, true, Attribute.INTERNAL)
        }
    }
}

private func CopyParamAttributes(source: FuncParam, target: MangleFuncParam): Unit {
    AddParamAttrIf(target, source.TestAttr(Attribute.PUBLIC), Attribute.PUBLIC)
    AddParamAttrIf(target, source.TestAttr(Attribute.PRIVATE), Attribute.PRIVATE)
    AddParamAttrIf(target, source.TestAttr(Attribute.PROTECTED), Attribute.PROTECTED)
    AddParamAttrIf(target, source.TestAttr(Attribute.INTERNAL), Attribute.INTERNAL)
    target.hasAccessibilityModifiers = true
    for (modifier in source.modifiers) {
        if (modifier.modifier == TokenKind.PUBLIC) {
            target.accessibilityModifiers += MANGLE_PUBLIC_PREFIX
            AddParamAttrIf(target, true, Attribute.PUBLIC)
        } else if (modifier.modifier == TokenKind.PRIVATE) {
            target.accessibilityModifiers += MANGLE_PRIVATE_PREFIX
            AddParamAttrIf(target, true, Attribute.PRIVATE)
        } else if (modifier.modifier == TokenKind.PROTECTED) {
            target.accessibilityModifiers += MANGLE_PROTECTED_PREFIX
            AddParamAttrIf(target, true, Attribute.PROTECTED)
        } else if (modifier.modifier == TokenKind.INTERNAL) {
            AddParamAttrIf(target, true, Attribute.INTERNAL)
        }
    }
}

private class MangleAdapterIdAllocator {
    private static let nextId = AtomicInt64(0)

    public static func Next(): Int64 {
        return nextId.fetchAdd(1)
    }
}

public class MangleAstAdapter {
    private let declCache: HashMap<Int64, MangleDecl> = HashMap<Int64, MangleDecl>()
    private let lambdaCache: HashMap<Int64, MangleDecl> = HashMap<Int64, MangleDecl>()
    private let annotationArrayCache: HashMap<Int64, MangleDecl> = HashMap<Int64, MangleDecl>()
    private let tyCache: HashMap<Int64, MangleType> = HashMap<Int64, MangleType>()
    private let declPairs: ArrayList<AstDeclPair> = ArrayList<AstDeclPair>()

    public init() {}

    private func EnsureAdapterId(source: Node): Int64 {
        if (source.mangleAdapterId < 0) {
            source.mangleAdapterId = MangleAdapterIdAllocator.Next()
        }
        return source.mangleAdapterId
    }

    private func SameAdapterNode(left: Node, right: Node): Bool {
        return EnsureAdapterId(left) == EnsureAdapterId(right)
    }

    private func FindDecl(source: Decl): Option<MangleDecl> {
        if (source.mangleAdapterId < 0) {
            return None
        }
        return declCache.get(source.mangleAdapterId)
    }

    private func StoreDecl(source: Decl, target: MangleDecl): Unit {
        declCache[EnsureAdapterId(source)] = target
        declPairs.add(AstDeclPair(source, target))
    }

    private func FindLambda(source: LambdaExpr): Option<MangleDecl> {
        if (source.mangleAdapterId < 0) {
            return None
        }
        return lambdaCache.get(source.mangleAdapterId)
    }

    private func StoreLambda(source: LambdaExpr, target: MangleDecl): Unit {
        lambdaCache[EnsureAdapterId(source)] = target
    }

    private func FindAnnotationArray(source: ArrayLit): Option<MangleDecl> {
        if (source.mangleAdapterId < 0) {
            return None
        }
        return annotationArrayCache.get(source.mangleAdapterId)
    }

    private func StoreAnnotationArray(source: ArrayLit, target: MangleDecl): Unit {
        annotationArrayCache[EnsureAdapterId(source)] = target
    }

    private func EnsureTyAdapterId(source: Ty): Int64 {
        if (source.mangleAdapterId < 0) {
            source.mangleAdapterId = MangleAdapterIdAllocator.Next()
        }
        return source.mangleAdapterId
    }

    private func FindTy(source: Ty): Option<MangleType> {
        if (source.mangleAdapterId < 0) {
            return None
        }
        return tyCache.get(source.mangleAdapterId)
    }

    private func StoreTy(source: Ty, target: MangleType): Unit {
        tyCache[EnsureTyAdapterId(source)] = target
    }

    private func SameNode(left: Node, right: Node): Bool {
        return SameAdapterNode(left, right)
    }

    private func PackageNameOf(node: Node): String {
        if (let Some(decl) <- (node as Decl)) {
            if (!decl.fullPackageName.isEmpty()) {
                return decl.fullPackageName
            }
        }
        if (let Some(file) <- node.curFile) {
            if (let Some(pkg) <- file.curPackage) {
                return pkg.fullPackageName
            }
        }
        return ""
    }

    public func ConvertFile(file: File): MangleFile {
        return MangleFile(file.fileName, fileHash: file.fileHash)
    }

    public func ConvertPackage(pkg: Package): MangleDecl {
        let target = MangleDecl(ASTKind.PACKAGE, pkg.fullPackageName, fullPackageName: pkg.fullPackageName)
        for (file in pkg.files) {
            for (decl in file.decls) {
                let member = ConvertDecl(decl)
                if (let None <- member.curFile) {
                    member.curFile = ConvertFile(file)
                }
                target.members.add(member)
            }
            for (decl in file.exportedInternalDecls) {
                target.members.add(ConvertDecl(decl))
            }
        }
        for (decl in pkg.genericInstantiatedDecls) {
            target.members.add(ConvertDecl(decl))
        }
        for (decl in pkg.srcImportedNonGenericDecls) {
            target.members.add(ConvertDecl(decl))
        }
        for (decl in pkg.inlineFuncDecls) {
            target.members.add(ConvertDecl(decl))
        }
        return target
    }

    public func ConvertDecl(source: Decl): MangleDecl {
        if (let Some(cached) <- FindDecl(source)) {
            return cached
        }
        let target = MangleDecl(source.astKind, source.identifier.Val(),
            fullPackageName: PackageNameOf(source))
        StoreDecl(source, target)

        target.rawMangleName = source.rawMangleName
        target.mangledName = source.mangledName
        target.exportId = source.exportId
        target.moduleName = source.moduleName
        target.linkage = source.linkage
        if (let Some(file) <- source.curFile) {
            target.curFile = ConvertFile(file)
        }
        if (let Some(outer) <- source.outerDecl) {
            target.outerDecl = ConvertDecl(outer)
        }
        if (let Some(genericSource) <- source.genericDecl) {
            target.genericDecl = ConvertDecl(genericSource)
        }
        CopyDeclAttributes(source, target)
        if (let Some(generic) <- source.generic) {
            target.generic = ConvertGeneric(generic)
        }
        if (let Some(sourceTy) <- source.GetTy()) {
            target.semaTy = ConvertTy(sourceTy)
        }
        FillDeclSubclassFields(source, target)
        for (memberSource in source.GetMemberDeclPtrs()) {
            target.members.add(ConvertDecl(memberSource))
        }
        return target
    }

    public func ConvertNode(source: Node): Option<MangleDecl> {
        if (let Some(decl) <- (source as Decl)) {
            return ConvertDecl(decl)
        }
        if (let Some(lambda) <- (source as LambdaExpr)) {
            return ConvertLambdaExpr(lambda)
        }
        return None
    }

    public func ConvertLambdaExpr(source: LambdaExpr): MangleDecl {
        if (let Some(cached) <- FindLambda(source)) {
            return cached
        }
        let target = MangleDecl(ASTKind.LAMBDA_EXPR, "", fullPackageName: PackageNameOf(source))
        StoreLambda(source, target)
        target.mangledName = source.mangledName
        if (let Some(file) <- source.curFile) {
            target.curFile = ConvertFile(file)
        }
        if (let Some(lambdaTy) <- source.GetTy()) {
            target.semaTy = ConvertTy(lambdaTy)
        }
        if (let Some(body) <- source.funcBody) {
            target.funcBody = ConvertFuncBody(body)
        }
        return target
    }

    private func ConvertAnnotationArray(source: ArrayLit, owner: MangleDecl): MangleDecl {
        if (let Some(cached) <- FindAnnotationArray(source)) {
            return cached
        }
        let target = MangleDecl(ASTKind.NODE, "<annotations>", fullPackageName: owner.fullPackageName)
        target.outerDecl = owner
        target.curFile = owner.curFile
        StoreAnnotationArray(source, target)
        return target
    }

    private func AstScopeRoot(node: Node): Option<Node> {
        if (let Some(lambda) <- (node as LambdaExpr)) {
            if (let Some(body) <- lambda.funcBody) {
                return body
            }
            return None
        }
        if (let Some(function) <- (node as FuncDecl)) {
            if (let Some(body) <- function.funcBody) {
                return body
            }
            return None
        }
        if (let Some(primaryCtor) <- (node as PrimaryCtorDecl)) {
            if (let Some(body) <- primaryCtor.funcBody) {
                return body
            }
            return None
        }
        if (let Some(varDecl) <- (node as VarDeclAbstract)) {
            if (varDecl.TestAttr(Attribute.GLOBAL) || IsCompositeMemberVar(node)) {
                return node
            }
        }
        return None
    }

    private func AstDeclKey(node: Node): Option<MangleDecl> {
        if (let Some(lambda) <- (node as LambdaExpr)) {
            return ConvertLambdaExpr(lambda)
        }
        if (let Some(function) <- (node as FuncDecl)) {
            return ConvertDecl(function)
        }
        if (let Some(primaryCtor) <- (node as PrimaryCtorDecl)) {
            return ConvertDecl(primaryCtor)
        }
        if (let Some(varDecl) <- (node as VarDeclAbstract)) {
            return ConvertDecl(varDecl)
        }
        return None
    }

    private func IsCompositeMemberVar(node: Node): Bool {
        if (let Some(varDecl) <- (node as VarDeclAbstract)) {
            if (let Some(outer) <- varDecl.outerDecl) {
                // Faithful to BaseMangler.cpp:1397-1400 (vda->outerDecl->astKind == ASTKind::CLASS_DECL
                // || ... ). Matching on the constructor tag is an O(1) compare; the `ASTKind ==`
                // operator otherwise routes each comparison through the linear ASTKindIndex.
                return match (outer.astKind) {
                    case ASTKind.CLASS_DECL | ASTKind.INTERFACE_DECL | ASTKind.STRUCT_DECL | ASTKind.ENUM_DECL => true
                    case _ => false
                }
            }
        }
        return false
    }

    private func IsAnnotationArrayOfRoot(root: Node, node: Node): Bool {
        if (SameNode(root, node)) {
            return false
        }
        if (let Some(owner) <- (root as Decl)) {
            if (let Some(annotationArray) <- owner.annotationsArray) {
                return SameNode(annotationArray, node)
            }
        }
        return false
    }

    private func NeedCollectScope(node: Node): Bool {
        // Faithful to BaseMangler.cpp:948-955 (isFunc = astKind == FUNC_DECL; isLambda = astKind ==
        // LAMBDA_EXPR; ...). The constructor match is an O(1) tag compare; this runs once per node
        // in the CollectLocalDecls package walk, so routing it through the linear ASTKind ==
        // operator is the hot cost being removed.
        match (node.astKind) {
            case ASTKind.FUNC_DECL | ASTKind.LAMBDA_EXPR => return true
            case _ => ()
        }
        if (let Some(varDecl) <- (node as VarDeclAbstract)) {
            return varDecl.TestAttr(Attribute.GLOBAL) || IsCompositeMemberVar(node)
        }
        return false
    }

    private func ShouldSkipNestedFuncBody(root: Node, node: Node): Bool {
        if (SameNode(root, node)) {
            return false
        }
        if (let Some(_) <- (node as FuncBody)) {
            return true
        }
        return false
    }

    private func RegisterAstVarsInScope(ctx: ManglerContext, key: MangleDecl, root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (ShouldSkipNestedFuncBody(root, node)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (!SameNode(root, node)) {
                if (let Some(varDecl) <- (node as VarDeclAbstract)) {
                    ctx.RegisterLocalVar(key, ConvertDecl(varDecl))
                }
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func RegisterAstWildcardVarsInScope(ctx: ManglerContext, key: MangleDecl, root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (ShouldSkipNestedFuncBody(root, node)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (!SameNode(root, node)) {
                if (let Some(varWithPattern) <- (node as VarWithPatternDecl)) {
                    ctx.RegisterLocalWildcardVar(key, ConvertDecl(varWithPattern))
                }
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func RegisterAstFuncsInScope(ctx: ManglerContext, key: MangleDecl, root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (!SameNode(root, node)) {
                if (let Some(function) <- (node as FuncDecl)) {
                    ctx.RegisterLocalFunc(key, ConvertDecl(function))
                }
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func RegisterAstLambdasInScope(ctx: ManglerContext, key: MangleDecl, root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (IsAnnotationArrayOfRoot(root, node)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (ShouldSkipNestedFuncBody(root, node)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (!SameNode(root, node)) {
                if (let Some(lambda) <- (node as LambdaExpr)) {
                    ctx.RegisterLambda(key, ConvertLambdaExpr(lambda))
                }
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func RegisterAstLambdasInAnnotationArray(ctx: ManglerContext, key: MangleDecl, owner: Decl): Unit {
        if (let Some(annotationArray) <- owner.annotationsArray) {
            let annotationKey = ConvertAnnotationArray(annotationArray, key)
            ctx.RegisterLambdaAnnotationKey(key, annotationKey)
            RegisterAstLambdasInScope(ctx, annotationKey, annotationArray)
        }
    }

    private func RegisterGenericInstantiatedLocalFunction(ctx: ManglerContext, node: Node): Unit {
        if (let Some(function) <- (node as FuncDecl)) {
            if (function.TestAttr(Attribute.GENERIC_INSTANTIATED) && !function.TestAttr(Attribute.GLOBAL)) {
                if (let Some(outer) <- function.outerDecl) {
                    if (!outer.IsNominalDecl()) {
                        if (let Some(key) <- AstDeclKey(outer)) {
                            ctx.RegisterLocalFunc(key, ConvertDecl(function))
                        }
                    }
                }
            }
        }
    }

    private func CollectScope(ctx: ManglerContext, node: Node): Unit {
        if (let Some(key) <- AstDeclKey(node)) {
            RegisterGenericInstantiatedLocalFunction(ctx, node)
            if (let Some(root) <- AstScopeRoot(node)) {
                RegisterAstVarsInScope(ctx, key, root)
                RegisterAstLambdasInScope(ctx, key, root)
                RegisterAstWildcardVarsInScope(ctx, key, root)
                RegisterAstFuncsInScope(ctx, key, root)
            }
            if (let Some(owner) <- (node as Decl)) {
                RegisterAstLambdasInAnnotationArray(ctx, key, owner)
            }
        }
    }

    public func CollectLocalDecls(ctx: ManglerContext, pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(extendDecl) <- (node as ExtendDecl)) {
                if (let Some(file) <- extendDecl.curFile) {
                    ctx.SaveExtend2CurFile(ConvertFile(file), ConvertDecl(extendDecl))
                }
            }
            if (let Some(varWithPattern) <- (node as VarWithPatternDecl)) {
                if (varWithPattern.TestAttr(Attribute.GLOBAL)) {
                    if (let Some(file) <- varWithPattern.curFile) {
                        ctx.SaveGlobalWildcardVar(ConvertFile(file), ConvertDecl(varWithPattern))
                    }
                }
            }
            if (NeedCollectScope(node)) {
                CollectScope(ctx, node)
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }

    private func FillDeclSubclassFields(source: Decl, target: MangleDecl): Unit {
        if (let Some(varDecl) <- (source as VarDeclAbstract)) {
            if (let Some(typeNode) <- varDecl.typeNode) {
                target.typeAnnotation = ConvertTypeAnnotation(typeNode)
            }
        }
        if (let Some(funcParam) <- (source as FuncParam)) {
            target.isMemberParam = funcParam.isMemberParam
        }
        if (let Some(typeAlias) <- (source as TypeAliasDecl)) {
            if (let Some(typeNode) <- typeAlias.typeNode) {
                target.typeAnnotation = ConvertTypeAnnotation(typeNode)
            }
        }
        if (let Some(varWithPattern) <- (source as VarWithPatternDecl)) {
            if (let Some(pattern) <- varWithPattern.irrefutablePattern) {
                target.irrefutablePattern = ConvertPattern(pattern)
            }
        }
        if (let Some(funcDecl) <- (source as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                target.funcBody = ConvertFuncBody(body)
            }
            if (let Some(owner) <- funcDecl.ownerFunc) {
                target.ownerFunc = ConvertDecl(owner)
            }
        }
        if (let Some(macroDecl) <- (source as MacroDecl)) {
            if (let Some(body) <- macroDecl.funcBody) {
                target.funcBody = ConvertFuncBody(body)
            }
        }
        if (let Some(mainDecl) <- (source as MainDecl)) {
            if (let Some(body) <- mainDecl.funcBody) {
                target.funcBody = ConvertFuncBody(body)
            }
        }
        if (let Some(primaryCtor) <- (source as PrimaryCtorDecl)) {
            if (let Some(body) <- primaryCtor.funcBody) {
                target.funcBody = ConvertFuncBody(body)
            }
        }
        if (let Some(extendDecl) <- (source as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                target.extendedType = ConvertTypeAnnotation(extendedType)
            }
        }
        if (let Some(inheritable) <- (source as InheritableDecl)) {
            for (inheritedType in inheritable.inheritedTypes) {
                target.inheritedTypes.add(ConvertTypeAnnotation(inheritedType))
            }
        }
        if (let Some(propDecl) <- (source as PropDecl)) {
            for (getter in propDecl.getters) {
                target.getters.add(ConvertDecl(getter))
            }
            for (setter in propDecl.setters) {
                target.setters.add(ConvertDecl(setter))
            }
        }
    }

    public func ConvertFuncBody(body: FuncBody): MangleFuncBody {
        let target = MangleFuncBody()
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                target.params.add(ConvertFuncParam(param))
            }
        }
        if (let Some(retType) <- body.retType) {
            target.retType = ConvertTypeAnnotation(retType)
        }
        if (let Some(generic) <- body.generic) {
            target.generic = ConvertGeneric(generic)
        }
        if (let Some(parentClassLike) <- body.parentClassLike) {
            target.parentClassLike = ConvertDecl(parentClassLike)
        }
        if (let Some(parentStruct) <- body.parentStruct) {
            target.parentStruct = ConvertDecl(parentStruct)
        }
        if (let Some(parentEnum) <- body.parentEnum) {
            target.parentEnum = ConvertDecl(parentEnum)
        }
        return target
    }

    public func ConvertFuncParam(param: FuncParam): MangleFuncParam {
        let target = MangleFuncParam(param.identifier.Val())
        if (let Some(typeNode) <- param.typeNode) {
            target.typeAnnotation = ConvertTypeAnnotation(typeNode)
        }
        if (let Some(paramTy) <- param.GetTy()) {
            target.semaTy = ConvertTy(paramTy)
        }
        target.assignment = if (let Some(_) <- param.assignment) { true } else { false }
        target.isMemberParam = param.isMemberParam
        target.isNamedParam = param.isNamedParam
        target.hasLetOrVar = param.hasLetOrVar
        target.isVar = param.isVar
        CopyParamAttributes(param, target)
        return target
    }

    public func ConvertGeneric(generic: Generic): MangleGeneric {
        let target = MangleGeneric()
        for (param in generic.typeParameters) {
            target.typeParameters.add(ConvertDecl(param))
        }
        for (constraint in generic.genericConstraints) {
            target.genericConstraints.add(ConvertGenericConstraint(constraint))
        }
        return target
    }

    public func ConvertGenericConstraint(constraint: GenericConstraint): MangleGenericConstraint {
        let target = MangleGenericConstraint()
        if (let Some(refType) <- constraint.refType) {
            target.typeAnnotation = ConvertTypeAnnotation(refType)
        }
        for (upper in constraint.upperBounds) {
            target.upperBounds.add(ConvertTypeAnnotation(upper))
        }
        return target
    }

    public func ConvertPattern(pattern: Pattern): ManglePattern {
        let target = ManglePattern(pattern.astKind)
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                target.varDecl = ConvertDecl(varDecl)
            }
        }
        if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            for (child in tuplePattern.patterns) {
                target.patterns.add(ConvertPattern(child))
            }
        }
        if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            for (child in enumPattern.patterns) {
                target.patterns.add(ConvertPattern(child))
            }
        }
        return target
    }

    public func ConvertTypeAnnotation(typeNode: Type): MangleTypeAnnotation {
        let target = MangleTypeAnnotation(typeNode.astKind, typeNode.ToString())
        if (let Some(ty) <- typeNode.GetTy()) {
            target.ty = ConvertTy(ty)
        }
        if (let Some(refType) <- (typeNode as RefType)) {
            target.name = refType.ref.identifier.GetRawText()
            for (arg in refType.typeArguments) {
                target.typeArguments.add(ConvertTypeAnnotation(arg))
            }
        } else if (let Some(primitiveType) <- (typeNode as PrimitiveType)) {
            target.name = primitiveType.ToString()
        } else if (let Some(parenType) <- (typeNode as ParenType)) {
            if (let Some(inner) <- parenType.innerType) {
                target.innerType = ConvertTypeAnnotation(inner)
            }
        } else if (let Some(optionType) <- (typeNode as OptionType)) {
            target.questNum = optionType.questNum
            if (let Some(component) <- optionType.componentType) {
                target.componentType = ConvertTypeAnnotation(component)
            }
        } else if (let Some(constantType) <- (typeNode as ConstantType)) {
            if (let Some(expr) <- constantType.constantExpr) {
                if (let Some(literal) <- (expr as LitConstExpr)) {
                    target.constantValue = literal.stringValue
                } else {
                    throw IllegalArgumentException("Constant type annotation requires a literal constant expression.")
                }
            } else {
                throw IllegalArgumentException("Constant type annotation has no constant expression.")
            }
        } else if (let Some(varrayType) <- (typeNode as VArrayType)) {
            if (let Some(typeArg) <- varrayType.typeArgument) {
                target.typeArgument = ConvertTypeAnnotation(typeArg)
            }
            if (let Some(constantTypeArg) <- varrayType.constantType) {
                target.constantType = ConvertTypeAnnotation(constantTypeArg)
            }
        } else if (let Some(funcType) <- (typeNode as FuncType)) {
            target.isC = funcType.isC
            for (paramType in funcType.paramTypes) {
                target.paramTypes.add(ConvertTypeAnnotation(paramType))
            }
            if (let Some(retType) <- funcType.retType) {
                target.retType = ConvertTypeAnnotation(retType)
            }
        } else if (let Some(tupleType) <- (typeNode as TupleType)) {
            for (fieldType in tupleType.fieldTypes) {
                target.fieldTypes.add(ConvertTypeAnnotation(fieldType))
            }
        } else if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
            if (let Some(baseType) <- qualifiedType.baseType) {
                target.baseType = ConvertTypeAnnotation(baseType)
            }
            target.field = qualifiedType.field.GetRawText()
            for (arg in qualifiedType.typeArguments) {
                target.typeArguments.add(ConvertTypeAnnotation(arg))
            }
        }
        return target
    }

    public func ConvertTy(source: Ty): MangleType {
        if (let Some(aliasTy) <- (source as TypeAliasTy)) {
            if (let Some(aliasDecl) <- aliasTy.declPtr) {
                if (let Some(typeNode) <- aliasDecl.typeNode) {
                    if (let Some(targetTy) <- typeNode.GetTy()) {
                        return ConvertTy(targetTy)
                    }
                }
            }
        }

        if (let Some(cached) <- FindTy(source)) {
            return cached
        }
        let target = MangleType(source.kind, source.name)
        StoreTy(source, target)
        for (arg in source.typeArgs) {
            target.typeArgs.add(ConvertTy(arg))
        }
        if (let Some(arrayTy) <- (source as ArrayTy)) {
            target.dims = arrayTy.dims
        }
        if (let Some(varrayTy) <- (source as VArrayTy)) {
            target.size = varrayTy.size
        }
        if (let Some(funcTy) <- (source as FuncTy)) {
            target.isCFunc = funcTy.IsCFunc()
            target.retTy = ConvertTy(funcTy.retTy)
            for (paramTy in funcTy.paramTys) {
                target.paramTys.add(ConvertTy(paramTy))
            }
        }
        if (let Some(genericsTy) <- (source as GenericsTy)) {
            target.name = genericsTy.name
            if (let Some(decl) <- genericsTy.decl) {
                target.decl = ConvertDecl(decl)
            }
        } else if (let Some(classTy) <- (source as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                target.decl = ConvertDecl(decl)
            }
        } else if (let Some(interfaceTy) <- (source as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                target.decl = ConvertDecl(decl)
            }
        } else if (let Some(enumTy) <- (source as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                target.decl = ConvertDecl(decl)
            }
        } else if (let Some(structTy) <- (source as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                target.decl = ConvertDecl(decl)
            }
        }
        return target
    }

    public func CopyExportIdsToAst(): Unit {
        for (pair in declPairs) {
            pair.source.exportId = pair.target.exportId
        }
    }
}

public func ConvertAstDeclToMangle(decl: Decl): MangleDecl {
    let adapter = MangleAstAdapter()
    return adapter.ConvertDecl(decl)
}

public func ConvertAstTypeToMangle(ty: Ty): MangleType {
    let adapter = MangleAstAdapter()
    return adapter.ConvertTy(ty)
}

public func ConvertAstTypeAnnotationToMangle(typeNode: Type): MangleTypeAnnotation {
    let adapter = MangleAstAdapter()
    return adapter.ConvertTypeAnnotation(typeNode)
}
