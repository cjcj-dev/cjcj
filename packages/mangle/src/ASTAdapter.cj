package cangjie_compiler::mangle

import std.collection.*
import cangjie_compiler::ast.*

private class AstDeclPair {
    public var source: Decl
    public var target: MangleDecl

    public init(source: Decl, target: MangleDecl) {
        this.source = source
        this.target = target
    }
}

private class AstLambdaPair {
    public var source: LambdaExpr
    public var target: MangleDecl

    public init(source: LambdaExpr, target: MangleDecl) {
        this.source = source
        this.target = target
    }
}

private func ConvertAstKind(kind: ASTKind): MangleAstKind {
    return match (kind) {
        case ASTKind.MAIN_DECL => MangleAstKind.MAIN_DECL
        case ASTKind.FUNC_DECL => MangleAstKind.FUNC_DECL
        case ASTKind.MACRO_DECL => MangleAstKind.MACRO_DECL
        case ASTKind.CLASS_DECL => MangleAstKind.CLASS_DECL
        case ASTKind.INTERFACE_DECL => MangleAstKind.INTERFACE_DECL
        case ASTKind.EXTEND_DECL => MangleAstKind.EXTEND_DECL
        case ASTKind.ENUM_DECL => MangleAstKind.ENUM_DECL
        case ASTKind.STRUCT_DECL => MangleAstKind.STRUCT_DECL
        case ASTKind.TYPE_ALIAS_DECL => MangleAstKind.TYPE_ALIAS_DECL
        case ASTKind.PRIMARY_CTOR_DECL => MangleAstKind.PRIMARY_CTOR_DECL
        case ASTKind.BUILTIN_DECL => MangleAstKind.BUILTIN_DECL
        case ASTKind.VAR_DECL => MangleAstKind.VAR_DECL
        case ASTKind.PROP_DECL => MangleAstKind.PROP_DECL
        case ASTKind.FUNC_PARAM => MangleAstKind.FUNC_PARAM
        case ASTKind.VAR_WITH_PATTERN_DECL => MangleAstKind.VAR_WITH_PATTERN_DECL
        case ASTKind.GENERIC_PARAM_DECL => MangleAstKind.GENERIC_PARAM_DECL
        case ASTKind.PACKAGE => MangleAstKind.PACKAGE
        case ASTKind.FILE => MangleAstKind.FILE
        case ASTKind.LAMBDA_EXPR => MangleAstKind.LAMBDA_EXPR
        case ASTKind.REF_TYPE => MangleAstKind.REF_TYPE
        case ASTKind.QUALIFIED_TYPE => MangleAstKind.QUALIFIED_TYPE
        case ASTKind.OPTION_TYPE => MangleAstKind.OPTION_TYPE
        case ASTKind.CONSTANT_TYPE => MangleAstKind.CONSTANT_TYPE
        case ASTKind.VARRAY_TYPE => MangleAstKind.VARRAY_TYPE
        case ASTKind.PRIMITIVE_TYPE => MangleAstKind.PRIMITIVE_TYPE
        case ASTKind.PAREN_TYPE => MangleAstKind.PAREN_TYPE
        case ASTKind.FUNC_TYPE => MangleAstKind.FUNC_TYPE
        case ASTKind.TUPLE_TYPE => MangleAstKind.TUPLE_TYPE
        case ASTKind.THIS_TYPE => MangleAstKind.THIS_TYPE
        case ASTKind.WILDCARD_PATTERN => MangleAstKind.WILDCARD_PATTERN
        case ASTKind.VAR_PATTERN => MangleAstKind.VAR_PATTERN
        case ASTKind.TUPLE_PATTERN => MangleAstKind.TUPLE_PATTERN
        case ASTKind.ENUM_PATTERN => MangleAstKind.ENUM_PATTERN
        case _ => MangleAstKind.INVALID
    }
}

private func ConvertTypeKind(kind: TypeKind): MangleTypeKind {
    return match (kind) {
        case TypeKind.TYPE_UNIT => MangleTypeKind.TYPE_UNIT
        case TypeKind.TYPE_INT8 => MangleTypeKind.TYPE_INT8
        case TypeKind.TYPE_INT16 => MangleTypeKind.TYPE_INT16
        case TypeKind.TYPE_INT32 => MangleTypeKind.TYPE_INT32
        case TypeKind.TYPE_INT64 => MangleTypeKind.TYPE_INT64
        case TypeKind.TYPE_INT_NATIVE => MangleTypeKind.TYPE_INT_NATIVE
        case TypeKind.TYPE_IDEAL_INT => MangleTypeKind.TYPE_IDEAL_INT
        case TypeKind.TYPE_UINT8 => MangleTypeKind.TYPE_UINT8
        case TypeKind.TYPE_UINT16 => MangleTypeKind.TYPE_UINT16
        case TypeKind.TYPE_UINT32 => MangleTypeKind.TYPE_UINT32
        case TypeKind.TYPE_UINT64 => MangleTypeKind.TYPE_UINT64
        case TypeKind.TYPE_UINT_NATIVE => MangleTypeKind.TYPE_UINT_NATIVE
        case TypeKind.TYPE_FLOAT16 => MangleTypeKind.TYPE_FLOAT16
        case TypeKind.TYPE_FLOAT32 => MangleTypeKind.TYPE_FLOAT32
        case TypeKind.TYPE_FLOAT64 => MangleTypeKind.TYPE_FLOAT64
        case TypeKind.TYPE_IDEAL_FLOAT => MangleTypeKind.TYPE_IDEAL_FLOAT
        case TypeKind.TYPE_RUNE => MangleTypeKind.TYPE_RUNE
        case TypeKind.TYPE_NOTHING => MangleTypeKind.TYPE_NOTHING
        case TypeKind.TYPE_BOOLEAN => MangleTypeKind.TYPE_BOOLEAN
        case TypeKind.TYPE_TUPLE => MangleTypeKind.TYPE_TUPLE
        case TypeKind.TYPE_ENUM => MangleTypeKind.TYPE_ENUM
        case TypeKind.TYPE_FUNC => MangleTypeKind.TYPE_FUNC
        case TypeKind.TYPE_STRUCT => MangleTypeKind.TYPE_STRUCT
        case TypeKind.TYPE_ARRAY => MangleTypeKind.TYPE_ARRAY
        case TypeKind.TYPE_VARRAY => MangleTypeKind.TYPE_VARRAY
        case TypeKind.TYPE_POINTER => MangleTypeKind.TYPE_POINTER
        case TypeKind.TYPE_CSTRING => MangleTypeKind.TYPE_CSTRING
        case TypeKind.TYPE_CLASS => MangleTypeKind.TYPE_CLASS
        case TypeKind.TYPE_INTERFACE => MangleTypeKind.TYPE_INTERFACE
        case TypeKind.TYPE_GENERICS => MangleTypeKind.TYPE_GENERICS
        case TypeKind.TYPE_ANY => MangleTypeKind.TYPE_ANY
        case TypeKind.TYPE_INTERSECTION => MangleTypeKind.TYPE_INTERSECTION
        case TypeKind.TYPE_UNION => MangleTypeKind.TYPE_UNION
        case TypeKind.TYPE_QUEST => MangleTypeKind.TYPE_QUEST
        case TypeKind.TYPE_INITIAL => MangleTypeKind.TYPE_INITIAL
        case _ => MangleTypeKind.TYPE_INVALID
    }
}

private func ConvertLinkage(linkage: Linkage): MangleLinkage {
    return match (linkage) {
        case Linkage.WEAK_ODR => MangleLinkage.WEAK_ODR
        case Linkage.EXTERNAL => MangleLinkage.EXTERNAL
        case Linkage.INTERNAL => MangleLinkage.INTERNAL
        case Linkage.LINKONCE_ODR => MangleLinkage.LINKONCE_ODR
        case Linkage.EXTERNAL_WEAK => MangleLinkage.EXTERNAL_WEAK
    }
}

private func AddAttrIf(target: MangleDecl, condition: Bool, attr: MangleAttribute): Unit {
    if (condition) {
        target.attrs.add(attr)
    }
}

private func AddParamAttrIf(target: MangleFuncParam, condition: Bool, attr: MangleAttribute): Unit {
    if (condition) {
        target.attrs.add(attr)
    }
}

private func CopyDeclAttributes(source: Decl, target: MangleDecl): Unit {
    AddAttrIf(target, source.TestAttr(Attribute.GLOBAL), MangleAttribute.GLOBAL)
    AddAttrIf(target, source.TestAttr(Attribute.STATIC), MangleAttribute.STATIC)
    AddAttrIf(target, source.TestAttr(Attribute.PUBLIC), MangleAttribute.PUBLIC)
    AddAttrIf(target, source.TestAttr(Attribute.PRIVATE), MangleAttribute.PRIVATE)
    AddAttrIf(target, source.TestAttr(Attribute.PROTECTED), MangleAttribute.PROTECTED)
    AddAttrIf(target, source.TestAttr(Attribute.INTERNAL), MangleAttribute.INTERNAL)
    AddAttrIf(target, source.TestAttr(Attribute.NO_MANGLE), MangleAttribute.NO_MANGLE)
    AddAttrIf(target, source.TestAttr(Attribute.GENERIC), MangleAttribute.GENERIC)
    AddAttrIf(target, source.TestAttr(Attribute.GENERIC_INSTANTIATED), MangleAttribute.GENERIC_INSTANTIATED)
    AddAttrIf(target, source.TestAttr(Attribute.HAS_INITIAL), MangleAttribute.HAS_INITIAL)
    AddAttrIf(target, source.TestAttr(Attribute.CONSTRUCTOR), MangleAttribute.CONSTRUCTOR)
    AddAttrIf(target, source.TestAttr(Attribute.MAIN_ENTRY), MangleAttribute.MAIN_ENTRY)
    AddAttrIf(target, source.TestAttr(Attribute.OPERATOR), MangleAttribute.OPERATOR)
    AddAttrIf(target, source.TestAttr(Attribute.DEFAULT), MangleAttribute.DEFAULT)
    AddAttrIf(target, source.TestAttr(Attribute.ABSTRACT), MangleAttribute.ABSTRACT)
    AddAttrIf(target, source.TestAttr(Attribute.COMMON), MangleAttribute.COMMON)
    AddAttrIf(target, source.TestAttr(Attribute.SPECIFIC), MangleAttribute.SPECIFIC)
    AddAttrIf(target, source.TestAttr(Attribute.FOR_TEST), MangleAttribute.FOR_TEST)
    for (modifier in source.modifiers) {
        if (modifier.modifier == TokenKind.PUBLIC) {
            AddAttrIf(target, true, MangleAttribute.PUBLIC)
        } else if (modifier.modifier == TokenKind.PRIVATE) {
            AddAttrIf(target, true, MangleAttribute.PRIVATE)
        } else if (modifier.modifier == TokenKind.PROTECTED) {
            AddAttrIf(target, true, MangleAttribute.PROTECTED)
        } else if (modifier.modifier == TokenKind.INTERNAL) {
            AddAttrIf(target, true, MangleAttribute.INTERNAL)
        }
    }
}

private func CopyParamAttributes(source: FuncParam, target: MangleFuncParam): Unit {
    AddParamAttrIf(target, source.TestAttr(Attribute.PUBLIC), MangleAttribute.PUBLIC)
    AddParamAttrIf(target, source.TestAttr(Attribute.PRIVATE), MangleAttribute.PRIVATE)
    AddParamAttrIf(target, source.TestAttr(Attribute.PROTECTED), MangleAttribute.PROTECTED)
    AddParamAttrIf(target, source.TestAttr(Attribute.INTERNAL), MangleAttribute.INTERNAL)
    for (modifier in source.modifiers) {
        if (modifier.modifier == TokenKind.PUBLIC) {
            AddParamAttrIf(target, true, MangleAttribute.PUBLIC)
        } else if (modifier.modifier == TokenKind.PRIVATE) {
            AddParamAttrIf(target, true, MangleAttribute.PRIVATE)
        } else if (modifier.modifier == TokenKind.PROTECTED) {
            AddParamAttrIf(target, true, MangleAttribute.PROTECTED)
        } else if (modifier.modifier == TokenKind.INTERNAL) {
            AddParamAttrIf(target, true, MangleAttribute.INTERNAL)
        }
    }
}

public class MangleAstAdapter {
    private let declPairs: ArrayList<AstDeclPair> = ArrayList<AstDeclPair>()
    private let lambdaPairs: ArrayList<AstLambdaPair> = ArrayList<AstLambdaPair>()

    public init() {}

    private func FindDecl(source: Decl): Option<MangleDecl> {
        for (pair in declPairs) {
            if (SameDecl(pair.source, source)) {
                return pair.target
            }
        }
        return None
    }

    private func StoreDecl(source: Decl, target: MangleDecl): Unit {
        declPairs.add(AstDeclPair(source, target))
    }

    private func FindLambda(source: LambdaExpr): Option<MangleDecl> {
        for (pair in lambdaPairs) {
            if (pair.source.begin == source.begin && pair.source.end == source.end &&
                pair.source.mangledName == source.mangledName) {
                return pair.target
            }
        }
        return None
    }

    private func StoreLambda(source: LambdaExpr, target: MangleDecl): Unit {
        lambdaPairs.add(AstLambdaPair(source, target))
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
        let target = MangleDecl(MangleAstKind.PACKAGE, pkg.fullPackageName, fullPackageName: pkg.fullPackageName)
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
        let target = MangleDecl(ConvertAstKind(source.astKind), source.identifier.Val(),
            fullPackageName: PackageNameOf(source))
        StoreDecl(source, target)

        target.rawMangleName = source.rawMangleName
        target.mangledName = source.mangledName
        target.exportId = source.exportId
        target.moduleName = source.moduleName
        target.linkage = ConvertLinkage(source.linkage)
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
        for (memberSource in source.GetMemberDecls()) {
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
        let target = MangleDecl(MangleAstKind.LAMBDA_EXPR, "", fullPackageName: PackageNameOf(source))
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

    private func FillDeclSubclassFields(source: Decl, target: MangleDecl): Unit {
        if (let Some(varDecl) <- (source as VarDeclAbstract)) {
            if (let Some(typeNode) <- varDecl.typeNode) {
                target.typeAnnotation = ConvertTypeAnnotation(typeNode)
            }
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
        let target = ManglePattern(ConvertAstKind(pattern.astKind))
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
        let target = MangleTypeAnnotation(ConvertAstKind(typeNode.astKind), typeNode.ToString())
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
                target.constantValue = expr.ToString()
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

        let target = MangleType(ConvertTypeKind(source.kind), source.name)
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
