package cangjie_compiler::macro_pkg

import cangjie_compiler::ast.{
    AnnotationKindIndex, AssignExpr, ASTKindName, FeatureId, FeaturesDirective, FeaturesSet, GenericConstraint,
    MainDecl, OverflowStrategyName, PackageSpec, PrimaryCtorDecl, PropDecl, SortModifierByPos, StringKindIndex,
    TypeAliasDecl
}
import cangjie_compiler::basic.Errorln
import cangjie_compiler::modules.{FlatBufferBuilder, FlatBufferOffset}
import std.collection.*

public let INITIAL_FILE_SIZE: Int64 = 65536

private func appendU32LE(out: ArrayList<UInt8>, value: UInt32): Unit {
    out.add(UInt8(UInt64(value) & 0xff))
    out.add(UInt8((UInt64(value) >> 8) & 0xff))
    out.add(UInt8((UInt64(value) >> 16) & 0xff))
    out.add(UInt8((UInt64(value) >> 24) & 0xff))
}

public class NodeWriter {
    let builder: FlatBufferBuilder = FlatBufferBuilder()
    let bufferData: ArrayList<UInt8> = ArrayList<UInt8>()
    let nodePtr: Node

    public init(nodePtr: Node) {
        this.nodePtr = nodePtr
    }

    @OverflowWrapping
    public func FlatPosCreateHelper(pos: Position): ArrayList<UInt8> {
        let out = ArrayList<UInt8>()
        appendU32LE(out, UInt32(pos.fileID))
        appendU32LE(out, UInt32(Int32(pos.line)))
        appendU32LE(out, UInt32(Int32(pos.column)))
        return out
    }

    public func CreatePositionVector(positions: ArrayList<Position>): FlatBufferOffset {
        let values = ArrayList<ArrayList<UInt8>>()
        for (position in positions) {
            values.add(FlatPosCreateHelper(position))
        }
        return builder.CreateVectorOfStructs(values, elementSize: 12, alignment: 4)
    }

    public func FlatVectorCreateHelper<T>(input: ArrayList<T>, funcPtr: (T) -> FlatBufferOffset): FlatBufferOffset {
        let offsets = ArrayList<FlatBufferOffset>()
        for (element in input) {
            offsets.add(funcPtr(element))
        }
        return builder.CreateVectorOffsets(offsets)
    }

    public func SerializeNodeBase(node: Node): FlatBufferOffset {
        let beginPos = FlatPosCreateHelper(node.begin)
        let endPos = FlatPosCreateHelper(node.end)
        let astKind = builder.CreateString(ASTKindName(node.astKind))
        return CreateNodeBase(builder, beginPos, endPos, astKind)
    }

    public func SerializeFeaturesDirective(ftrDirective: Option<FeaturesDirective>): FlatBufferOffset {
        if (let Some(value) <- ftrDirective) {
            return SerializeFeaturesDirective(value)
        }
        return 0u32
    }

    public func SerializeFeaturesDirective(ftrDirective: FeaturesDirective): FlatBufferOffset {
        let ftrNodeBase = SerializeNodeBase(ftrDirective)
        let featuresPos = FlatPosCreateHelper(ftrDirective.featuresPos)
        let annos = FlatVectorCreateHelper(ftrDirective.annotations, { item: Annotation => SerializeAnnotation(item) })
        let featuresSet = SerializeFeaturesSet(ftrDirective.featuresSet)
        return CreateFeaturesDirective(builder, ftrNodeBase, annos, featuresSet, featuresPos)
    }

    public func SerializeFeaturesSet(fSet: Option<FeaturesSet>): FlatBufferOffset {
        if (let Some(value) <- fSet) {
            return SerializeFeaturesSet(value)
        }
        return 0u32
    }

    public func SerializeFeaturesSet(fSet: FeaturesSet): FlatBufferOffset {
        let ftrSetBase = SerializeNodeBase(fSet)
        let lCurlPos = FlatPosCreateHelper(fSet.lCurlPos)
        let items = FlatVectorCreateHelper(fSet.content, { item: FeatureId => SerializeFeatureId(item) })
        let rCurlPos = FlatPosCreateHelper(fSet.rCurlPos)
        let commas = CreatePositionVector(fSet.commaPoses)
        return CreateFeaturesSet(builder, ftrSetBase, lCurlPos, items, commas, rCurlPos)
    }

    public func SerializeFeatureId(ftrId: FeatureId): FlatBufferOffset {
        let nodeBase = SerializeNodeBase(ftrId)
        let idents = ArrayList<String>()
        let poses = ArrayList<Position>()
        for (ident in ftrId.identifiers) {
            idents.add(ident.Val())
            poses.add(ident.Begin())
        }
        let identifiers = builder.CreateVectorOfStrings(idents)
        let identPoses = CreatePositionVector(poses)
        let dotPoses = CreatePositionVector(ftrId.dotPoses)
        return CreateFeatureId(builder, nodeBase, identifiers, identPoses, dotPoses)
    }

    public func SerializePackageSpec(packageSpec: Option<PackageSpec>): FlatBufferOffset {
        if (let Some(value) <- packageSpec) {
            return SerializePackageSpec(value)
        }
        return 0u32
    }

    public func SerializePackageSpec(packageSpec: PackageSpec): FlatBufferOffset {
        let paNodeBase = SerializeNodeBase(packageSpec)
        let macroPos = FlatPosCreateHelper(packageSpec.macroPos)
        let packagePos = FlatPosCreateHelper(packageSpec.packagePos)
        let prefixPaths = builder.CreateVectorOfStrings(packageSpec.prefixPaths)
        let prefixPoses = CreatePositionVector(packageSpec.prefixPoses)
        let prefixDotPoses = CreatePositionVector(packageSpec.prefixDotPoses)
        let packageName = builder.CreateString(packageSpec.packageName.Val())
        let packageNamePos = FlatPosCreateHelper(packageSpec.packageName.Begin())
        var accessible = AccessibleKind_ACCESSIBLE_PUBLIC
        if (let Some(modifier) <- packageSpec.modifier) {
            if (modifier.modifier == TokenKind.INTERNAL) {
                accessible = AccessibleKind_ACCESSIBLE_INTERNAL
            } else if (modifier.modifier == TokenKind.PROTECTED) {
                accessible = AccessibleKind_ACCESSIBLE_PROTECTED
            }
        }
        return CreatePackageSpec(builder, paNodeBase, macroPos, packagePos, prefixPaths, prefixPoses, prefixDotPoses,
            packageName, packageNamePos, accessible, packageSpec.hasMacro, packageSpec.hasDoubleColon)
    }

    public func SerializeImportContent(content: ImportContent): FlatBufferOffset {
        let icNodeBase = SerializeNodeBase(content)
        var kind = ImportKind_IMPORT_SINGLE
        if (content.kind == ImportKind.IMPORT_ALIAS) {
            kind = ImportKind_IMPORT_ALIAS
        } else if (content.kind == ImportKind.IMPORT_ALL) {
            kind = ImportKind_IMPORT_ALL
        } else if (content.kind == ImportKind.IMPORT_MULTI) {
            kind = ImportKind_IMPORT_MULTI
        }
        let prefixPaths = builder.CreateVectorOfStrings(content.prefixPaths)
        let prefixPoses = CreatePositionVector(content.prefixPoses)
        let prefixDotPoses = CreatePositionVector(content.prefixDotPoses)
        let ident = builder.CreateString(content.identifier.Val())
        let identPos = FlatPosCreateHelper(content.identifier.Begin())
        let asPos = FlatPosCreateHelper(content.asPos)
        let asIdent = builder.CreateString(content.aliasName.Val())
        let asIdentPos = FlatPosCreateHelper(content.aliasName.Begin())
        let leftCurlPos = FlatPosCreateHelper(content.leftCurlPos)
        let items = FlatVectorCreateHelper(content.items, { item: ImportContent => SerializeImportContent(item) })
        let commaPoses = CreatePositionVector(content.commaPoses)
        let rightCurlPos = FlatPosCreateHelper(content.rightCurlPos)
        return CreateImportContent(builder, icNodeBase, kind, prefixPaths, prefixPoses, prefixDotPoses, ident, identPos,
            asPos, asIdent, asIdentPos, leftCurlPos, items, commaPoses, rightCurlPos, content.hasDoubleColon)
    }

    public func SerializeImportSpec(importSpec: Option<ImportSpec>): FlatBufferOffset {
        if (let Some(value) <- importSpec) {
            return SerializeImportSpec(value)
        }
        return 0u32
    }

    public func SerializeImportSpec(importSpec: ImportSpec): FlatBufferOffset {
        let imNodeBase = SerializeNodeBase(importSpec)
        var reExport = ReExportKind_REEXPORT_PRIVATE
        if (let Some(modifier) <- importSpec.modifier) {
            if (modifier.modifier == TokenKind.PUBLIC) {
                reExport = ReExportKind_REEXPORT_PUBLIC
            } else if (modifier.modifier == TokenKind.PROTECTED) {
                reExport = ReExportKind_REEXPORT_PROTECTED
            } else if (modifier.modifier == TokenKind.INTERNAL) {
                reExport = ReExportKind_REEXPORT_INTERNAL
            }
        }
        let importPos = FlatPosCreateHelper(importSpec.importPos)
        let content = SerializeImportContent(importSpec.content)
        return CreateImportSpec(builder, imNodeBase, reExport, importPos, content)
    }

    public func SerializeFile(file: File): FlatBufferOffset {
        let fNodeBase = SerializeNodeBase(file)
        let fileName = builder.CreateString(file.fileName)
        let filePath = builder.CreateString(file.filePath)
        let feature = SerializeFeaturesDirective(file.feature)
        let packageValue = SerializePackageSpec(file.packageSpec)
        let importsVec = ArrayList<FlatBufferOffset>()
        for (importSpec in file.imports) {
            if (importSpec.TestAttr(Attribute.COMPILER_ADD)) {
                continue
            }
            importsVec.add(SerializeImportSpec(importSpec))
        }
        let imports = builder.CreateVectorOffsets(importsVec)
        let decls = FlatVectorCreateHelper(file.decls, { declItem: Decl => SerializeDecl(declItem) })
        return CreateFile(builder, fNodeBase, fileName, filePath, packageValue, imports, decls, feature)
    }

    public func SerializeMatchCase(matchcase: Option<MatchCase>): FlatBufferOffset {
        if (let Some(value) <- matchcase) {
            return SerializeMatchCase(value)
        }
        return 0u32
    }

    public func SerializeMatchCase(matchcase: MatchCase): FlatBufferOffset {
        let mcNodeBase = SerializeNodeBase(matchcase)
        let fbPatterns = FlatVectorCreateHelper(matchcase.patterns, { patternItem: Pattern =>
            SerializePattern(patternItem)
        })
        let bitOrPosVector = CreatePositionVector(matchcase.bitOrPosVector)
        let fbPatternGuard = SerializeExpr(matchcase.patternGuard)
        let ifPos = FlatPosCreateHelper(matchcase.wherePos)
        let arrowPos = FlatPosCreateHelper(matchcase.arrowPos)
        let fbExprOrDecls = SerializeBlock(matchcase.exprOrDecls)
        return CreateMatchCase(builder, mcNodeBase, fbPatterns, fbPatternGuard, ifPos, arrowPos, fbExprOrDecls,
            bitOrPosVector)
    }

    public func SerializeMatchCaseOther(matchcaseother: Option<MatchCaseOther>): FlatBufferOffset {
        if (let Some(value) <- matchcaseother) {
            return SerializeMatchCaseOther(value)
        }
        return 0u32
    }

    public func SerializeMatchCaseOther(matchcaseother: MatchCaseOther): FlatBufferOffset {
        let mcNodeBase = SerializeNodeBase(matchcaseother)
        let fbExpr = SerializeExpr(matchcaseother.matchExpr)
        let arrowPos = FlatPosCreateHelper(matchcaseother.arrowPos)
        let fbExprOrDecls = SerializeBlock(matchcaseother.exprOrDecls)
        return CreateMatchCaseOther(builder, mcNodeBase, fbExpr, arrowPos, fbExprOrDecls)
    }

    public func SerializePattern(pattern: Option<Pattern>): FlatBufferOffset {
        if (let Some(value) <- pattern) {
            return SerializePattern(value)
        }
        return 0u32
    }

    public func SerializePattern(pattern: Pattern): FlatBufferOffset {
        if (ASTKindEquals(pattern.astKind, ASTKind.CONST_PATTERN)) {
            return SerializeConstPattern(pattern)
        } else if (ASTKindEquals(pattern.astKind, ASTKind.VAR_PATTERN)) {
            return SerializeVarPattern(pattern)
        } else if (ASTKindEquals(pattern.astKind, ASTKind.TUPLE_PATTERN)) {
            return SerializeTuplePattern(pattern)
        } else if (ASTKindEquals(pattern.astKind, ASTKind.TYPE_PATTERN)) {
            return SerializeTypePattern(pattern)
        } else if (ASTKindEquals(pattern.astKind, ASTKind.ENUM_PATTERN)) {
            return SerializeEnumPattern(pattern)
        } else if (ASTKindEquals(pattern.astKind, ASTKind.VAR_OR_ENUM_PATTERN)) {
            return SerializeVarOrEnumPattern(pattern)
        } else if (ASTKindEquals(pattern.astKind, ASTKind.EXCEPT_TYPE_PATTERN)) {
            return SerializeExceptTypePattern(pattern)
        } else if (ASTKindEquals(pattern.astKind, ASTKind.COMMAND_TYPE_PATTERN)) {
            return SerializeCommandTypePattern(pattern)
        } else if (ASTKindEquals(pattern.astKind, ASTKind.WILDCARD_PATTERN)) {
            return SerializeWildcardPattern(pattern)
        }
        Errorln("Unkown Pattern in libast Serialization.")
        return 0u32
    }

    public func SerializeConstPattern(pattern: Pattern): FlatBufferOffset {
        let constPattern = (pattern as ConstPattern).getOrThrow()
        let fbNodeBase = SerializeNodeBase(constPattern)
        let fbLiteral = SerializeExpr(constPattern.literal)
        let fbCallExpr = SerializeCallExpr(constPattern.operatorCallExpr)
        let fbConstPattern = CreateConstPattern(builder, fbNodeBase, fbLiteral, fbCallExpr)
        return CreatePattern(builder, fbNodeBase, AnyPattern_CONST_PATTERN, fbConstPattern)
    }

    public func SerializeWildcardPattern(pattern: Pattern): FlatBufferOffset {
        let wildcardPattern = (pattern as WildcardPattern).getOrThrow()
        let fbNodeBase = SerializeNodeBase(wildcardPattern)
        let fbWildcardPattern = CreateWildcardPattern(builder, fbNodeBase)
        return CreatePattern(builder, fbNodeBase, AnyPattern_WILDCARD_PATTERN, fbWildcardPattern)
    }

    public func SerializeVarPattern(pattern: Pattern): FlatBufferOffset {
        let varPattern = (pattern as VarPattern).getOrThrow()
        let fbNodeBase = SerializeNodeBase(varPattern)
        let fbVarDecl = SerializeVarDecl(varPattern.varDecl)
        let fbVarPattern = CreateVarPattern(builder, fbNodeBase, fbVarDecl)
        return CreatePattern(builder, fbNodeBase, AnyPattern_VAR_PATTERN, fbVarPattern)
    }

    public func SerializeTypePattern(pattern: Pattern): FlatBufferOffset {
        let typePattern = (pattern as TypePattern).getOrThrow()
        let fbNodeBase = SerializeNodeBase(typePattern)
        let fbPattern = SerializePattern(typePattern.pattern)
        let colonPos = FlatPosCreateHelper(typePattern.colonPos)
        let fbType = SerializeType(typePattern.typeNode)
        let fbTypePattern = CreateTypePattern(builder, fbNodeBase, fbPattern, colonPos, fbType)
        return CreatePattern(builder, fbNodeBase, AnyPattern_TYPE_PATTERN, fbTypePattern)
    }

    public func SerializeEnumPattern(enumPattern: Option<EnumPattern>): FlatBufferOffset {
        if (let Some(value) <- enumPattern) {
            return SerializeEnumPattern(value)
        }
        return 0u32
    }

    public func SerializeEnumPattern(enumPattern: EnumPattern): FlatBufferOffset {
        let fbNodeBase = SerializeNodeBase(enumPattern)
        let fbConstructor = SerializeExpr(enumPattern.constructor)
        let leftParenPos = FlatPosCreateHelper(enumPattern.leftParenPos)
        let fbPatterns = FlatVectorCreateHelper(enumPattern.patterns, { patternItem: Pattern =>
            SerializePattern(patternItem)
        })
        let commaPosVector = CreatePositionVector(enumPattern.commaPosVector)
        let rightParenPos = FlatPosCreateHelper(enumPattern.rightParenPos)
        return CreateEnumPattern(builder, fbNodeBase, fbConstructor, leftParenPos, fbPatterns, rightParenPos,
            commaPosVector)
    }

    public func SerializeEnumPattern(pattern: Pattern): FlatBufferOffset {
        let enumPattern = (pattern as EnumPattern).getOrThrow()
        let fbEnumPattern = SerializeEnumPattern(enumPattern)
        return CreatePattern(builder, SerializeNodeBase(enumPattern), AnyPattern_ENUM_PATTERN, fbEnumPattern)
    }

    public func SerializeVarOrEnumPattern(pattern: Pattern): FlatBufferOffset {
        let varOrEnumPattern = (pattern as VarOrEnumPattern).getOrThrow()
        let fbNodeBase = SerializeNodeBase(varOrEnumPattern)
        let fbIdentifier = builder.CreateString(varOrEnumPattern.identifier.GetRawText())
        let fbPattern = SerializePattern(varOrEnumPattern.pattern)
        let fbVarOrEnumPattern = CreateVarOrEnumPattern(builder, fbNodeBase, fbIdentifier, fbPattern)
        return CreatePattern(builder, fbNodeBase, AnyPattern_VAR_OR_ENUM_PATTERN, fbVarOrEnumPattern)
    }

    public func SerializeTuplePattern(pattern: Pattern): FlatBufferOffset {
        let tuplePattern = (pattern as TuplePattern).getOrThrow()
        let fbNodeBase = SerializeNodeBase(tuplePattern)
        let leftParenPos = FlatPosCreateHelper(tuplePattern.leftBracePos)
        let fbPatterns = FlatVectorCreateHelper(tuplePattern.patterns, { patternItem: Pattern =>
            SerializePattern(patternItem)
        })
        let commaPosVector = CreatePositionVector(tuplePattern.commaPosVector)
        let rightParenPos = FlatPosCreateHelper(tuplePattern.rightBracePos)
        let fbTuplePattern = CreateTuplePattern(builder, fbNodeBase, leftParenPos, fbPatterns, rightParenPos,
            commaPosVector)
        return CreatePattern(builder, fbNodeBase, AnyPattern_TUPLE_PATTERN, fbTuplePattern)
    }

    public func SerializeExceptTypePattern(pattern: Pattern): FlatBufferOffset {
        let exceptTypePattern = (pattern as ExceptTypePattern).getOrThrow()
        let fbNodeBase = SerializeNodeBase(exceptTypePattern)
        let fbPattern = SerializePattern(exceptTypePattern.pattern)
        let patternPos = FlatPosCreateHelper(exceptTypePattern.patternPos)
        let colonPos = FlatPosCreateHelper(exceptTypePattern.colonPos)
        let fbTypes = FlatVectorCreateHelper(exceptTypePattern.types, { typeItem: Type => SerializeType(typeItem) })
        let bitOrPosVector = CreatePositionVector(exceptTypePattern.bitOrPosVector)
        let fbExceptTypePattern = CreateExceptTypePattern(builder, fbNodeBase, fbPattern, patternPos, colonPos,
            fbTypes, bitOrPosVector)
        return CreatePattern(builder, fbNodeBase, AnyPattern_EXCEPT_TYPE_PATTERN, fbExceptTypePattern)
    }

    public func SerializeCommandTypePattern(pattern: Pattern): FlatBufferOffset {
        let effectTypePattern = (pattern as CommandTypePattern).getOrThrow()
        let fbNodeBase = SerializeNodeBase(effectTypePattern)
        let fbPattern = SerializePattern(effectTypePattern.pattern)
        let patternPos = FlatPosCreateHelper(effectTypePattern.patternPos)
        let colonPos = FlatPosCreateHelper(effectTypePattern.colonPos)
        let fbTypes = FlatVectorCreateHelper(effectTypePattern.types, { typeItem: Type => SerializeType(typeItem) })
        let bitOrPosVector = CreatePositionVector(effectTypePattern.bitOrPosVector)
        let fbCommandTypePattern = CreateCommandTypePattern(builder, fbNodeBase, fbPattern, patternPos, colonPos,
            fbTypes, bitOrPosVector)
        return CreatePattern(builder, fbNodeBase, AnyPattern_COMMAND_TYPE_PATTERN, fbCommandTypePattern)
    }

    public func SerializeFuncParam(funcParam: Option<FuncParam>): FlatBufferOffset {
        if (let Some(value) <- funcParam) {
            return SerializeFuncParam(value)
        }
        return 0u32
    }

    public func SerializeFuncParam(funcParam: FuncParam): FlatBufferOffset {
        let fbNodeBase = SerializeNodeBase(funcParam)
        let fbVarDeclBase = SerializeVarDecl(funcParam)
        let colonPos = FlatPosCreateHelper(funcParam.colonPos)
        let fbExpr = SerializeExpr(funcParam.assignment)
        let commaPos = FlatPosCreateHelper(funcParam.commaPos)
        let notMarkPos = FlatPosCreateHelper(funcParam.notMarkPos)
        return CreateFuncParam(builder, fbNodeBase, fbVarDeclBase, colonPos, fbExpr, commaPos, funcParam.isNamedParam,
            funcParam.isMemberParam, notMarkPos, funcParam.hasLetOrVar, MacroParam_NONE, 0u32)
    }

    public func SerializeDeclOfFuncParam(decl: FuncParam): FlatBufferOffset {
        let fbFuncParam = SerializeFuncParam(decl)
        return CreateDecl(builder, SerializeDeclBase(decl), AnyDecl_FUNC_PARAM, fbFuncParam)
    }

    public func SerializeDeclOfMacroExpandParam(decl: MacroExpandParam): FlatBufferOffset {
        let base = SerializeFuncParam(decl)
        let invocation = MacroInvocationCreateHelper(decl.invocation)
        let mepNode = CreateMacroExpandParam(builder, base, invocation)
        return CreateDecl(builder, SerializeDeclBase(decl), AnyDecl_MACRO_EXPAND_PARAM, mepNode)
    }

    public func SerializeBlock(block: Option<Block>): FlatBufferOffset {
        if (let Some(value) <- block) {
            return SerializeBlock(value)
        }
        return 0u32
    }

    public func SerializeBlock(block: Block): FlatBufferOffset {
        let fbNodeBase = SerializeNodeBase(block)
        let leftCurPos = FlatPosCreateHelper(block.leftCurlPos)
        let rightCurPos = FlatPosCreateHelper(block.rightCurlPos)
        let unsafePos = FlatPosCreateHelper(block.unsafePos)
        let vecNode = ArrayList<FlatBufferOffset>()
        for (node in block.body) {
            if (let Some(expr) <- (node as Expr)) {
                let fbExpr = SerializeExpr(expr)
                let nodeBase = SerializeNodeBase(expr)
                vecNode.add(CreateNode(builder, nodeBase, AnyNode_EXPR, fbExpr))
            } else if (let Some(decl) <- (node as Decl)) {
                let fbDecl = SerializeDecl(decl)
                let nodeBase = SerializeNodeBase(decl)
                vecNode.add(CreateNode(builder, nodeBase, AnyNode_DECL, fbDecl))
            } else {
                Errorln("Match Nothing in Block!")
            }
        }
        let fbBody = builder.CreateVectorOffsets(vecNode)
        return CreateBlock(builder, fbNodeBase, leftCurPos, fbBody, rightCurPos, block.TestAttr(Attribute.UNSAFE),
            unsafePos)
    }

    public func SerializeFuncBody(funcBody: Option<FuncBody>): FlatBufferOffset {
        if (let Some(value) <- funcBody) {
            return SerializeFuncBody(value)
        }
        return 0u32
    }

    public func SerializeFuncBody(funcBody: FuncBody): FlatBufferOffset {
        let fbNodeBaseFnBody = SerializeNodeBase(funcBody)
        let paramList = funcBody.paramLists[0]
        let fbNodeBasePaList = SerializeNodeBase(paramList)
        let leftParenPos = FlatPosCreateHelper(paramList.leftParenPos)
        let rightParenPos = FlatPosCreateHelper(paramList.rightParenPos)
        let vecNode = ArrayList<FlatBufferOffset>()
        for (param in paramList.params) {
            if (let Some(mep) <- (param as MacroExpandParam)) {
                vecNode.add(SerializeMacroExpandParam(mep))
            } else {
                vecNode.add(SerializeFuncParam(param))
            }
        }
        let fbParamList = CreateFuncParamList(builder, fbNodeBasePaList, leftParenPos, builder.CreateVectorOffsets(vecNode),
            rightParenPos)
        let arrowPos = FlatPosCreateHelper(funcBody.doubleArrowPos)
        let colonPos = FlatPosCreateHelper(funcBody.colonPos)
        let fbRetType = SerializeType(funcBody.retType)
        let hasBody = funcBody.body.isSome()
        let fbBody = SerializeBlock(funcBody.body)
        let fbGeneric = SerializeGeneric(funcBody.generic)
        return CreateFuncBody(builder, fbNodeBaseFnBody, fbParamList, arrowPos, colonPos, fbRetType, hasBody, fbBody,
            fbGeneric)
    }

    public func SerializeDeclBase(decl: Decl): FlatBufferOffset {
        let fbNodeBase = SerializeNodeBase(decl)
        let identifier = builder.CreateString(decl.identifier.GetRawText())
        let identifierPos = FlatPosCreateHelper(decl.identifier.GetRawPos())
        let keywordPos = FlatPosCreateHelper(decl.keywordPos)
        let fbAnnVec = FlatVectorCreateHelper(decl.annotations, { annotationItem: Annotation =>
            SerializeAnnotation(annotationItem)
        })
        let vecMod = ArrayList<FlatBufferOffset>()
        let modifiersVec = SortModifierByPos(decl.modifiers)
        for (mod in modifiersVec) {
            vecMod.add(SerializeModifier(mod))
        }
        let fbModVec = builder.CreateVectorOffsets(vecMod)
        let generic = SerializeGeneric(decl.generic)
        let isConst = decl.IsConst()
        return CreateDeclBase(builder, fbNodeBase, identifier, identifierPos, keywordPos, fbAnnVec, fbModVec, generic,
            isConst)
    }

    public func SerializeTypeBase(typeNode: Type): FlatBufferOffset {
        let fbBase = SerializeNodeBase(typeNode)
        let commaPos = FlatPosCreateHelper(typeNode.commaPos)
        let bitAndPos = FlatPosCreateHelper(typeNode.bitAndPos)
        let typeParameterName = builder.CreateString(typeNode.GetTypeParameterNameRawText())
        let colonPos = FlatPosCreateHelper(typeNode.colonPos)
        let typePos = FlatPosCreateHelper(typeNode.typePos)
        return CreateTypeBase(builder, fbBase, commaPos, typeParameterName, colonPos, typePos, bitAndPos)
    }

    public func SerializeRefType(refType: Option<RefType>): FlatBufferOffset {
        if (let Some(value) <- refType) {
            return SerializeRefType(value)
        }
        return 0u32
    }

    public func SerializeRefType(refType: RefType): FlatBufferOffset {
        let fbTypeBase = SerializeTypeBase(refType)
        let refValue = refType.ref
        let identifier = builder.CreateString(refValue.identifier.GetRawText())
        let identifierPos = FlatPosCreateHelper(refValue.identifier.GetRawPos())
        let fbRef = CreateReference(builder, identifier, identifierPos)
        let leftAnglePos = FlatPosCreateHelper(refType.leftAnglePos)
        let fbTypeVec = FlatVectorCreateHelper(refType.typeArguments, { typeItem: Type => SerializeType(typeItem) })
        let rightAnglePos = FlatPosCreateHelper(refType.rightAnglePos)
        return CreateRefType(builder, fbTypeBase, fbRef, leftAnglePos, fbTypeVec, rightAnglePos)
    }

    public func SerializeRefType(typeNode: Type): FlatBufferOffset {
        let refType = (typeNode as RefType).getOrThrow()
        let fbRefType = SerializeRefType(refType)
        return CreateType(builder, SerializeTypeBase(refType), AnyType_REF_TYPE, fbRefType)
    }

    public func SerializePrimitiveType(primitiveType: Option<PrimitiveType>): FlatBufferOffset {
        if (let Some(value) <- primitiveType) {
            return SerializePrimitiveType(value)
        }
        return 0u32
    }

    public func SerializePrimitiveType(primitiveType: PrimitiveType): FlatBufferOffset {
        let fbTypeBase = SerializeTypeBase(primitiveType)
        let fbTypeStr = builder.CreateString(primitiveType.str)
        let typeKind = UInt16(TypeKindIndex(primitiveType.kind))
        return CreatePrimitiveType(builder, fbTypeBase, fbTypeStr, typeKind)
    }

    public func SerializePrimitiveType(typeNode: Type): FlatBufferOffset {
        let primitiveType = (typeNode as PrimitiveType).getOrThrow()
        let fbPrimType = SerializePrimitiveType(primitiveType)
        return CreateType(builder, SerializeTypeBase(primitiveType), AnyType_PRIMITIVE_TYPE, fbPrimType)
    }

    public func SerializeThisType(typeNode: Type): FlatBufferOffset {
        let thisType = (typeNode as ThisType).getOrThrow()
        let fbTypeBase = SerializeTypeBase(thisType)
        let fbThisType = CreateThisType(builder, fbTypeBase)
        return CreateType(builder, fbTypeBase, AnyType_THIS_TYPE, fbThisType)
    }

    public func SerializeParenType(typeNode: Type): FlatBufferOffset {
        let parenType = (typeNode as ParenType).getOrThrow()
        let fbTypeBase = SerializeTypeBase(parenType)
        let leftParenPos = FlatPosCreateHelper(parenType.leftParenPos)
        let ptype = SerializeType(parenType.innerType)
        let rightParenPos = FlatPosCreateHelper(parenType.rightParenPos)
        let fbParenType = CreateParenType(builder, fbTypeBase, leftParenPos, ptype, rightParenPos)
        return CreateType(builder, fbTypeBase, AnyType_PAREN_TYPE, fbParenType)
    }

    public func SerializeQualifiedType(typeNode: Type): FlatBufferOffset {
        let qualifiedType = (typeNode as QualifiedType).getOrThrow()
        let fbTypeBase = SerializeTypeBase(qualifiedType)
        let baseType = SerializeType(qualifiedType.baseType)
        let dotPos = FlatPosCreateHelper(qualifiedType.dotPos)
        let fieldStr = builder.CreateString(qualifiedType.field.GetRawText())
        let fieldPos = FlatPosCreateHelper(qualifiedType.field.GetRawPos())
        let leftAnglePos = FlatPosCreateHelper(qualifiedType.leftAnglePos)
        let typeArguments = FlatVectorCreateHelper(qualifiedType.typeArguments, { typeItem: Type =>
            SerializeType(typeItem)
        })
        let rightAnglePos = FlatPosCreateHelper(qualifiedType.rightAnglePos)
        let fbQualifiedType = CreateQualifiedType(builder, fbTypeBase, baseType, dotPos, fieldStr, fieldPos,
            leftAnglePos, typeArguments, rightAnglePos)
        return CreateType(builder, fbTypeBase, AnyType_QUALIFIED_TYPE, fbQualifiedType)
    }

    public func SerializeOptionType(typeNode: Type): FlatBufferOffset {
        let optionType = (typeNode as OptionType).getOrThrow()
        let fbTypeBase = SerializeTypeBase(optionType)
        let componentType = SerializeType(optionType.componentType)
        let questVector = CreatePositionVector(optionType.questVector)
        let fbOptionType = CreateOptionType(builder, fbTypeBase, componentType, Int64(optionType.questNum), questVector)
        return CreateType(builder, fbTypeBase, AnyType_OPTION_TYPE, fbOptionType)
    }

    public func SerializeTupleType(typeNode: Type): FlatBufferOffset {
        let tupleType = (typeNode as TupleType).getOrThrow()
        let fbTypeBase = SerializeTypeBase(tupleType)
        let fieldTypes = FlatVectorCreateHelper(tupleType.fieldTypes, { typeItem: Type => SerializeType(typeItem) })
        let leftParenPos = FlatPosCreateHelper(tupleType.leftParenPos)
        let rightParenPos = FlatPosCreateHelper(tupleType.rightParenPos)
        let commaPosVector = CreatePositionVector(tupleType.commaPosVector)
        if (tupleType.commaPosVector.size == 0) {
            Errorln("Legacy tuple type syntax no longer allowed after version 0.28.4, use ',' instead.")
        }
        let fbTupleType = CreateTupleType(builder, fbTypeBase, fieldTypes, leftParenPos, rightParenPos,
            commaPosVector)
        return CreateType(builder, fbTypeBase, AnyType_TUPLE_TYPE, fbTupleType)
    }

    public func SerializeFuncType(typeNode: Type): FlatBufferOffset {
        let funcType = (typeNode as FuncType).getOrThrow()
        let fbTypeBase = SerializeTypeBase(funcType)
        let leftParenPos = FlatPosCreateHelper(funcType.leftParenPos)
        let fbTypeVec = FlatVectorCreateHelper(funcType.paramTypes, { typeItem: Type => SerializeType(typeItem) })
        let rightParenPos = FlatPosCreateHelper(funcType.rightParenPos)
        let arrowPos = FlatPosCreateHelper(funcType.arrowPos)
        let fbRetType = SerializeType(funcType.retType)
        let fbFuncType = CreateFuncType(builder, fbTypeBase, leftParenPos, fbTypeVec, rightParenPos, arrowPos,
            fbRetType, funcType.isC)
        return CreateType(builder, fbTypeBase, AnyType_FUNC_TYPE, fbFuncType)
    }

    public func SerializeVArrayType(typeNode: Type): FlatBufferOffset {
        let vArrayType = (typeNode as VArrayType).getOrThrow()
        let fbTypeBase = SerializeTypeBase(vArrayType)
        let varrayPos = FlatPosCreateHelper(vArrayType.varrayPos)
        let leftAnglePos = FlatPosCreateHelper(vArrayType.leftAnglePos)
        let typeArgument = SerializeType(vArrayType.typeArgument)
        let constantType = SerializeType(vArrayType.constantType)
        let rightAnglePos = FlatPosCreateHelper(vArrayType.rightAnglePos)
        let fbVArrayType = CreateVArrayType(builder, fbTypeBase, varrayPos, leftAnglePos, typeArgument, constantType,
            rightAnglePos)
        return CreateType(builder, fbTypeBase, AnyType_VARRAY_TYPE, fbVArrayType)
    }

    public func SerializeConstantType(typeNode: Type): FlatBufferOffset {
        let constantType = (typeNode as ConstantType).getOrThrow()
        let fbTypeBase = SerializeTypeBase(constantType)
        let constantExpr = SerializeExpr(constantType.constantExpr)
        let dollarPos = FlatPosCreateHelper(constantType.dollarPos)
        let fbConstantType = CreateConstantType(builder, fbTypeBase, constantExpr, dollarPos)
        return CreateType(builder, fbTypeBase, AnyType_CONSTANT_TYPE, fbConstantType)
    }

    public func SerializeType(typeNode: Option<Type>): FlatBufferOffset {
        if (let Some(value) <- typeNode) {
            return SerializeType(value)
        }
        return 0u32
    }

    public func SerializeType(typeNode: Type): FlatBufferOffset {
        if (ASTKindEquals(typeNode.astKind, ASTKind.REF_TYPE)) {
            return SerializeRefType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.PRIMITIVE_TYPE)) {
            return SerializePrimitiveType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.FUNC_TYPE)) {
            return SerializeFuncType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.THIS_TYPE)) {
            return SerializeThisType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.PAREN_TYPE)) {
            return SerializeParenType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.QUALIFIED_TYPE)) {
            return SerializeQualifiedType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.OPTION_TYPE)) {
            return SerializeOptionType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.TUPLE_TYPE)) {
            return SerializeTupleType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.VARRAY_TYPE)) {
            return SerializeVArrayType(typeNode)
        } else if (ASTKindEquals(typeNode.astKind, ASTKind.CONSTANT_TYPE)) {
            return SerializeConstantType(typeNode)
        }
        Errorln("Type Not Supported in Libast Yet\n")
        return 0u32
    }

    public func SerializeVarDecl(varDecl: Option<VarDecl>): FlatBufferOffset {
        if (let Some(value) <- varDecl) {
            return SerializeVarDecl(value)
        }
        return 0u32
    }

    public func SerializeVarDecl(varDecl: VarDecl): FlatBufferOffset {
        let fbDeclBase = SerializeDeclBase(varDecl)
        let fbType = SerializeType(varDecl.typeNode)
        let colonPos = FlatPosCreateHelper(varDecl.colonPos)
        let initializer = SerializeExpr(varDecl.initializer)
        let assignPos = FlatPosCreateHelper(varDecl.assignPos)
        let isEnumConstruct = varDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
        var emptyKeyword = varDecl.parentPattern.isSome()
        if (varDecl.parentPattern.isNone()) {
            emptyKeyword = varDecl.isResourceVar
        }
        return CreateVarDecl(builder, fbDeclBase, fbType, colonPos, initializer, assignPos, varDecl.isVar,
            isEnumConstruct, emptyKeyword)
    }

    public func SerializeFuncDecl(funcDecl: Option<FuncDecl>): FlatBufferOffset {
        if (let Some(value) <- funcDecl) {
            return SerializeFuncDecl(value)
        }
        return 0u32
    }

    public func SerializeFuncDecl(funcDecl: FuncDecl): FlatBufferOffset {
        let fbDeclBase = SerializeDeclBase(funcDecl)
        let leftParenPos = FlatPosCreateHelper(funcDecl.leftParenPos)
        let rightParenPos = FlatPosCreateHelper(funcDecl.rightParenPos)
        let fbFuncBody = SerializeFuncBody(funcDecl.funcBody)
        let isEnumConstruct = funcDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
        return CreateFuncDecl(builder, fbDeclBase, leftParenPos, rightParenPos, fbFuncBody, funcDecl.isSetter,
            funcDecl.isGetter, TokenKindIndex(funcDecl.op), isEnumConstruct)
    }

    public func SerializeMainDecl(mainDecl: MainDecl): FlatBufferOffset {
        let fbDeclBase = SerializeDeclBase(mainDecl)
        let fbFuncBody = SerializeFuncBody(mainDecl.funcBody)
        return CreateMainDecl(builder, fbDeclBase, fbFuncBody)
    }

    public func SerializeMacroDecl(macroDecl: MacroDecl): FlatBufferOffset {
        let fbDeclBase = SerializeDeclBase(macroDecl)
        let leftParenPos = FlatPosCreateHelper(Position(0u64, 0, 0))
        let rightParenPos = FlatPosCreateHelper(Position(0u64, 0, 0))
        let fbFuncBody = SerializeFuncBody(macroDecl.funcBody)
        return CreateMacroDecl(builder, fbDeclBase, leftParenPos, rightParenPos, fbFuncBody)
    }

    public func SerializeGenericParamDecl(genericParamDecl: Option<GenericParamDecl>): FlatBufferOffset {
        if (let Some(value) <- genericParamDecl) {
            return SerializeGenericParamDecl(value)
        }
        return 0u32
    }

    public func SerializeGenericParamDecl(genericParamDecl: GenericParamDecl): FlatBufferOffset {
        let fbBase = SerializeDeclBase(genericParamDecl)
        let commaPos = FlatPosCreateHelper(genericParamDecl.commaPos)
        return CreateGenericParamDecl(builder, fbBase, commaPos)
    }

    public func SerializeGenericConstraint(genericConstraint: Option<GenericConstraint>): FlatBufferOffset {
        if (let Some(value) <- genericConstraint) {
            return SerializeGenericConstraint(value)
        }
        return 0u32
    }

    public func SerializeGenericConstraint(genericConstraint: GenericConstraint): FlatBufferOffset {
        let fbBase = SerializeNodeBase(genericConstraint)
        let wherePos = FlatPosCreateHelper(genericConstraint.wherePos)
        let fbRefType = SerializeRefType(genericConstraint.refType)
        let operatorPos = FlatPosCreateHelper(genericConstraint.operatorPos)
        let fbUpperBounds = FlatVectorCreateHelper(genericConstraint.upperBounds, { typeItem: Type =>
            SerializeType(typeItem)
        })
        let bitAndPos = CreatePositionVector(genericConstraint.bitAndPos)
        let commaPos = FlatPosCreateHelper(genericConstraint.commaPos)
        return CreateGenericConstraint(builder, fbBase, wherePos, fbRefType, operatorPos, fbUpperBounds, bitAndPos,
            commaPos)
    }

    public func SerializeGeneric(generic: Option<Generic>): FlatBufferOffset {
        if (let Some(value) <- generic) {
            return SerializeGeneric(value)
        }
        return 0u32
    }

    public func SerializeGeneric(generic: Generic): FlatBufferOffset {
        let leftAnglePos = FlatPosCreateHelper(generic.leftAnglePos)
        let fbTypeParameters = FlatVectorCreateHelper(generic.typeParameters, { param: GenericParamDecl =>
            SerializeGenericParamDecl(param)
        })
        let rightAnglePos = FlatPosCreateHelper(generic.rightAnglePos)
        let fbGenericConstraints = FlatVectorCreateHelper(generic.genericConstraints, { constraint: GenericConstraint =>
            SerializeGenericConstraint(constraint)
        })
        return CreateGeneric(builder, leftAnglePos, fbTypeParameters, rightAnglePos, fbGenericConstraints, 0u32)
    }

    public func SerializeClassBody(classBody: Option<ClassBody>): FlatBufferOffset {
        if (let Some(value) <- classBody) {
            return SerializeClassBody(value)
        }
        return 0u32
    }

    public func SerializeClassBody(classBody: ClassBody): FlatBufferOffset {
        let fbBase = SerializeNodeBase(classBody)
        let leftCurlPos = FlatPosCreateHelper(classBody.leftCurlPos)
        let fbDecls = FlatVectorCreateHelper(classBody.decls, { declItem: Decl => SerializeDecl(declItem) })
        let rightCurlPos = FlatPosCreateHelper(classBody.rightCurlPos)
        return CreateClassBody(builder, fbBase, leftCurlPos, fbDecls, rightCurlPos)
    }

    public func SerializeClassDecl(decl: Decl): FlatBufferOffset {
        let classDecl = (decl as ClassDecl).getOrThrow()
        let fbBase = SerializeDeclBase(classDecl)
        let upperBoundPos = FlatPosCreateHelper(classDecl.upperBoundPos)
        let fbSuperTypes = FlatVectorCreateHelper(classDecl.inheritedTypes, { typeItem: Type => SerializeType(typeItem) })
        let fbBody = SerializeClassBody(classDecl.body)
        let fbClassDecl = CreateClassDecl(builder, fbBase, upperBoundPos, fbSuperTypes, fbBody, 0u32)
        return CreateDecl(builder, fbBase, AnyDecl_CLASS_DECL, fbClassDecl)
    }

    public func SerializeInterfaceBody(interfaceBody: Option<InterfaceBody>): FlatBufferOffset {
        if (let Some(value) <- interfaceBody) {
            return SerializeInterfaceBody(value)
        }
        return 0u32
    }

    public func SerializeInterfaceBody(interfaceBody: InterfaceBody): FlatBufferOffset {
        let fbBase = SerializeNodeBase(interfaceBody)
        let leftCurlPos = FlatPosCreateHelper(interfaceBody.leftCurlPos)
        let fbDecls = FlatVectorCreateHelper(interfaceBody.decls, { declItem: Decl => SerializeDecl(declItem) })
        let rightCurlPos = FlatPosCreateHelper(interfaceBody.rightCurlPos)
        return CreateInterfaceBody(builder, fbBase, leftCurlPos, fbDecls, rightCurlPos)
    }

    public func SerializeInterfaceDecl(decl: Decl): FlatBufferOffset {
        let interfaceDecl = (decl as InterfaceDecl).getOrThrow()
        let fbBase = SerializeDeclBase(interfaceDecl)
        let upperBoundPos = FlatPosCreateHelper(interfaceDecl.upperBoundPos)
        let fbSuperTypes = FlatVectorCreateHelper(interfaceDecl.inheritedTypes, { typeItem: Type =>
            SerializeType(typeItem)
        })
        let fbBody = SerializeInterfaceBody(interfaceDecl.body)
        let fbInterfaceDecl = CreateInterfaceDecl(builder, fbBase, upperBoundPos, fbSuperTypes, fbBody, 0u32)
        return CreateDecl(builder, fbBase, AnyDecl_INTERFACE_DECL, fbInterfaceDecl)
    }

    public func SerializePrimaryCtorDecl(decl: Decl): FlatBufferOffset {
        let primaryCtorDecl = (decl as PrimaryCtorDecl).getOrThrow()
        let fbBase = SerializeDeclBase(primaryCtorDecl)
        let fbFuncBody = SerializeFuncBody(primaryCtorDecl.funcBody)
        let fbPrimaryCtorDecl = CreatePrimaryCtorDecl(builder, fbBase, fbFuncBody)
        return CreateDecl(builder, fbBase, AnyDecl_PRIMARY_CTOR_DECL, fbPrimaryCtorDecl)
    }

    public func SerializeDecl(decl: Option<Decl>): FlatBufferOffset {
        if (let Some(value) <- decl) {
            return SerializeDecl(value)
        }
        return 0u32
    }

    public func SerializeDecl(decl: Decl): FlatBufferOffset {
        if (ASTKindEquals(decl.astKind, ASTKind.VAR_DECL)) {
            let varDecl = (decl as VarDecl).getOrThrow()
            let fbVarDecl = SerializeVarDecl(varDecl)
            let fbDeclBase = SerializeDeclBase(varDecl)
            return CreateDecl(builder, fbDeclBase, AnyDecl_VAR_DECL, fbVarDecl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.FUNC_DECL)) {
            let funcDecl = (decl as FuncDecl).getOrThrow()
            let fbFuncDecl = SerializeFuncDecl(funcDecl)
            let fbDeclBase = SerializeDeclBase(funcDecl)
            return CreateDecl(builder, fbDeclBase, AnyDecl_FUNC_DECL, fbFuncDecl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.MAIN_DECL)) {
            let mainDecl = (decl as MainDecl).getOrThrow()
            let fbMainDecl = SerializeMainDecl(mainDecl)
            let fbDeclBase = SerializeDeclBase(mainDecl)
            return CreateDecl(builder, fbDeclBase, AnyDecl_MAIN_DECL, fbMainDecl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.STRUCT_DECL)) {
            return SerializeStructDecl(decl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.CLASS_DECL)) {
            return SerializeClassDecl(decl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.INTERFACE_DECL)) {
            return SerializeInterfaceDecl(decl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.PRIMARY_CTOR_DECL)) {
            return SerializePrimaryCtorDecl(decl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.PROP_DECL)) {
            return SerializePropDecl(decl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.ENUM_DECL)) {
            return SerializeEnumDecl(decl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.TYPE_ALIAS_DECL)) {
            return SerializeTypeAliasDecl(decl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.EXTEND_DECL)) {
            return SerializeExtendDecl(decl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.MACRO_DECL)) {
            let macroDecl = (decl as MacroDecl).getOrThrow()
            let fbMacroDecl = SerializeMacroDecl(macroDecl)
            let fbDeclBase = SerializeDeclBase(macroDecl)
            return CreateDecl(builder, fbDeclBase, AnyDecl_MACRO_DECL, fbMacroDecl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.MACRO_EXPAND_DECL)) {
            let macroExpandDecl = (decl as MacroExpandDecl).getOrThrow()
            let fbMacroExpandDecl = SerializeMacroExpandDecl(macroExpandDecl)
            return CreateDecl(builder, SerializeDeclBase(macroExpandDecl), AnyDecl_MACRO_EXPAND_DECL,
                fbMacroExpandDecl)
        } else if (ASTKindEquals(decl.astKind, ASTKind.FUNC_PARAM)) {
            return SerializeDeclOfFuncParam((decl as FuncParam).getOrThrow())
        } else if (ASTKindEquals(decl.astKind, ASTKind.MACRO_EXPAND_PARAM)) {
            return SerializeDeclOfMacroExpandParam((decl as MacroExpandParam).getOrThrow())
        } else if (ASTKindEquals(decl.astKind, ASTKind.VAR_WITH_PATTERN_DECL)) {
            return SerializeVarWithPatternDecl(decl)
        }
        Errorln("Decl Not Supported in Libast Yet\n")
        return 0u32
    }

    public func SerializeStructBody(structBody: Option<StructBody>): FlatBufferOffset {
        if (let Some(value) <- structBody) {
            return SerializeStructBody(value)
        }
        return 0u32
    }

    public func SerializeStructBody(structBody: StructBody): FlatBufferOffset {
        let fbNodeBase = SerializeNodeBase(structBody)
        let leftCurlPos = FlatPosCreateHelper(structBody.leftCurlPos)
        let fbDecls = FlatVectorCreateHelper(structBody.decls, { declItem: Decl => SerializeDecl(declItem) })
        let rightCurlPos = FlatPosCreateHelper(structBody.rightCurlPos)
        return CreateStructBody(builder, fbNodeBase, leftCurlPos, fbDecls, rightCurlPos)
    }

    public func SerializeStructDecl(decl: Decl): FlatBufferOffset {
        let structDecl = (decl as StructDecl).getOrThrow()
        let fbDeclBase = SerializeDeclBase(structDecl)
        let fbStructBody = SerializeStructBody(structDecl.body)
        let upperBoundPos = FlatPosCreateHelper(structDecl.upperBoundPos)
        let fbSuperTypes = FlatVectorCreateHelper(structDecl.inheritedTypes, { typeItem: Type => SerializeType(typeItem) })
        let fbStructDecl = CreateStructDecl(builder, fbDeclBase, fbStructBody, upperBoundPos, fbSuperTypes, 0u32)
        return CreateDecl(builder, fbDeclBase, AnyDecl_STRUCT_DECL, fbStructDecl)
    }

    public func SerializeVarWithPatternDecl(decl: Decl): FlatBufferOffset {
        let varWithPatternDecl = (decl as VarWithPatternDecl).getOrThrow()
        let fbDeclBase = SerializeDeclBase(varWithPatternDecl)
        let typeValue = SerializeType(varWithPatternDecl.typeNode)
        let colonPos = FlatPosCreateHelper(varWithPatternDecl.colonPos)
        let initializer = SerializeExpr(varWithPatternDecl.initializer)
        let pattern = SerializePattern(varWithPatternDecl.irrefutablePattern)
        let assignPos = FlatPosCreateHelper(varWithPatternDecl.assignPos)
        let fbVarWithPatternDecl = CreateVarWithPatternDecl(builder, fbDeclBase, typeValue, colonPos, initializer,
            pattern, assignPos, varWithPatternDecl.isVar)
        return CreateDecl(builder, fbDeclBase, AnyDecl_VAR_WITH_PATTERN_DECL, fbVarWithPatternDecl)
    }

    public func SerializeEnumDecl(decl: Decl): FlatBufferOffset {
        let enumDecl = (decl as EnumDecl).getOrThrow()
        let fbDeclBase = SerializeDeclBase(enumDecl)
        let leftCurlPos = FlatPosCreateHelper(enumDecl.leftCurlPos)
        let constructors = FlatVectorCreateHelper(enumDecl.constructors, { declItem: Decl => SerializeDecl(declItem) })
        let bitOrPosVector = CreatePositionVector(enumDecl.bitOrPosVector)
        let members = FlatVectorCreateHelper(enumDecl.members, { declItem: Decl => SerializeDecl(declItem) })
        let rightCurlPos = FlatPosCreateHelper(enumDecl.rightCurlPos)
        let upperBoundPos = FlatPosCreateHelper(enumDecl.upperBoundPos)
        let ellipsisPos = FlatPosCreateHelper(enumDecl.ellipsisPos)
        let fbSuperTypes = FlatVectorCreateHelper(enumDecl.inheritedTypes, { typeItem: Type => SerializeType(typeItem) })
        let fbEnumDecl = CreateEnumDecl(builder, fbDeclBase, enumDecl.hasArguments, leftCurlPos, constructors,
            bitOrPosVector, members, rightCurlPos, upperBoundPos, fbSuperTypes, enumDecl.hasEllipsis, ellipsisPos)
        return CreateDecl(builder, fbDeclBase, AnyDecl_ENUM_DECL, fbEnumDecl)
    }

    public func SerializePropDecl(decl: Decl): FlatBufferOffset {
        let propDecl = (decl as PropDecl).getOrThrow()
        let fbVarDecl = SerializeVarDecl(propDecl)
        let fbDeclBase = SerializeDeclBase(propDecl)
        let colonPos = FlatPosCreateHelper(propDecl.colonPos)
        let leftCurlPos = FlatPosCreateHelper(propDecl.leftCurlPos)
        let fbGetters = FlatVectorCreateHelper(propDecl.getters, { getter: FuncDecl => SerializeFuncDecl(getter) })
        let fbSetters = FlatVectorCreateHelper(propDecl.setters, { setter: FuncDecl => SerializeFuncDecl(setter) })
        let rightCurlPos = FlatPosCreateHelper(propDecl.rightCurlPos)
        let fbPropDecl = CreatePropDecl(builder, fbVarDecl, colonPos, leftCurlPos, fbGetters, fbSetters, rightCurlPos)
        return CreateDecl(builder, fbDeclBase, AnyDecl_PROP_DECL, fbPropDecl)
    }

    public func SerializeTypeAliasDecl(decl: Decl): FlatBufferOffset {
        let typeAliasDecl = (decl as TypeAliasDecl).getOrThrow()
        let fbDeclBase = SerializeDeclBase(typeAliasDecl)
        let assignPos = FlatPosCreateHelper(typeAliasDecl.assignPos)
        let typeValue = SerializeType(typeAliasDecl.typeNode)
        let fbTypeAliasDecl = CreateTypeAliasDecl(builder, fbDeclBase, assignPos, typeValue, 0u32)
        return CreateDecl(builder, fbDeclBase, AnyDecl_TYPE_ALIAS_DECL, fbTypeAliasDecl)
    }

    public func SerializeExtendDecl(decl: Decl): FlatBufferOffset {
        let extendDecl = (decl as ExtendDecl).getOrThrow()
        let fbDeclBase = SerializeDeclBase(extendDecl)
        let extendedType = SerializeType(extendDecl.extendedType)
        let upperBoundPos = FlatPosCreateHelper(extendDecl.upperBoundPos)
        let interfaces = FlatVectorCreateHelper(extendDecl.inheritedTypes, { typeItem: Type => SerializeType(typeItem) })
        let wherePos = FlatPosCreateHelper(extendDecl.wherePos)
        let leftCurlPos = FlatPosCreateHelper(extendDecl.leftCurlPos)
        let members = FlatVectorCreateHelper(extendDecl.members, { declItem: Decl => SerializeDecl(declItem) })
        let rightCurlPos = FlatPosCreateHelper(extendDecl.rightCurlPos)
        let fbExtendDecl = CreateExtendDecl(builder, fbDeclBase, extendedType, upperBoundPos, interfaces, wherePos,
            leftCurlPos, members, rightCurlPos)
        return CreateDecl(builder, fbDeclBase, AnyDecl_EXTEND_DECL, fbExtendDecl)
    }

    public func SerializeMacroExpandDecl(macroExpandDecl: Option<MacroExpandDecl>): FlatBufferOffset {
        if (let Some(value) <- macroExpandDecl) {
            return SerializeMacroExpandDecl(value)
        }
        return 0u32
    }

    public func SerializeMacroExpandDecl(macroExpandDecl: MacroExpandDecl): FlatBufferOffset {
        let base = SerializeDeclBase(macroExpandDecl)
        let invocation = MacroInvocationCreateHelper(macroExpandDecl.invocation)
        return CreateMacroExpandDecl(builder, base, invocation)
    }

    public func SerializeMacroExpandParam(mep: MacroExpandParam): FlatBufferOffset {
        let base = SerializeFuncParam(mep)
        let fbNodeBase = SerializeNodeBase(mep)
        let fbVarDeclBase = SerializeVarDecl(mep)
        let colonPos = FlatPosCreateHelper(mep.colonPos)
        let fbExpr = SerializeExpr(mep.assignment)
        let commaPos = FlatPosCreateHelper(mep.commaPos)
        let notMarkPos = FlatPosCreateHelper(mep.notMarkPos)
        let invocation = MacroInvocationCreateHelper(mep.invocation)
        let mepNode = CreateMacroExpandParam(builder, base, invocation)
        return CreateFuncParam(builder, fbNodeBase, fbVarDeclBase, colonPos, fbExpr, commaPos, mep.isNamedParam,
            mep.isMemberParam, notMarkPos, mep.hasLetOrVar, MacroParam_MACRO_EXPAND_PARAM, mepNode)
    }

    public func SerializeAnnotation(annotation: Option<Annotation>): FlatBufferOffset {
        if (let Some(value) <- annotation) {
            return SerializeAnnotation(value)
        }
        return 0u32
    }

    public func SerializeAnnotation(annotation: Annotation): FlatBufferOffset {
        let base = SerializeNodeBase(annotation)
        let kind = UInt16(AnnotationKindIndex(annotation.kind))
        let identPos = FlatPosCreateHelper(annotation.identifier.Begin())
        let identifier = builder.CreateString(annotation.identifier.Val())
        let lsquarePos = FlatPosCreateHelper(annotation.lsquarePos)
        let fbArgs = FlatVectorCreateHelper(annotation.args, { arg: FuncArg => SerializeFuncArg(arg) })
        let rsquarePos = FlatPosCreateHelper(annotation.rsquarePos)
        let overflowStrategy = builder.CreateString(OverflowStrategyName(annotation.overflowStrategy))
        let attrValues = ArrayList<String>()
        for (item in annotation.attrs) {
            attrValues.add(item.Value())
        }
        let fbAttrs = builder.CreateVectorOfStrings(attrValues)
        let condExpr = SerializeExpr(annotation.condExpr)
        return CreateAnnotation(builder, base, kind, identPos, identifier, fbArgs, overflowStrategy, fbAttrs, condExpr,
            lsquarePos, rsquarePos, annotation.isCompileTimeVisible)
    }

    public func SerializeModifier(modifier: Modifier): FlatBufferOffset {
        let base = SerializeNodeBase(modifier)
        let kind = UInt16(TokenKindIndex(modifier.modifier))
        return CreateModifier(builder, base, kind, modifier.isExplicit)
    }

    public func TokensVectorCreateHelper(tokenVector: ArrayList<Token>): ArrayList<FlatBufferOffset> {
        let vecToken = ArrayList<FlatBufferOffset>()
        let escapes = GetEscapeTokenKinds()
        for (token in tokenVector) {
            let kind = UInt16(TokenKindIndex(token.kind))
            let value = builder.CreateString(token.Value())
            var pos = FlatPosCreateHelper(token.Begin())
            var hasEscape = false
            if (ContainsTokenKind(escapes, token.kind) && token.Begin() + token.Value().size + 1 == token.End()) {
                pos = FlatPosCreateHelper(token.Begin() + 1)
                hasEscape = true
            }
            vecToken.add(CreateToken(builder, kind, value, pos, token.delimiterNum, token.isSingleQuote, hasEscape))
        }
        return vecToken
    }

    public func MacroInvocationCreateHelper(macroInvocation: MacroInvocation): FlatBufferOffset {
        let fullName = builder.CreateString(macroInvocation.macroCallDiagInfo.fullName)
        let identifier = builder.CreateString(macroInvocation.macroCallDiagInfo.identifier)
        let identifierPos = FlatPosCreateHelper(macroInvocation.macroCallDiagInfo.identifierPos)
        let leftSquarePos = FlatPosCreateHelper(macroInvocation.leftSquarePos)
        let rightSquarePos = FlatPosCreateHelper(macroInvocation.rightSquarePos)
        let leftParenPos = FlatPosCreateHelper(macroInvocation.leftParenPos)
        let rightParenPos = FlatPosCreateHelper(macroInvocation.rightParenPos)
        let atPos = FlatPosCreateHelper(macroInvocation.atPos)
        let attrsTokens = TokensVectorCreateHelper(macroInvocation.attrs)
        let attrs = builder.CreateVectorOffsets(attrsTokens)
        let argsTokens = TokensVectorCreateHelper(macroInvocation.args)
        let args = builder.CreateVectorOffsets(argsTokens)
        let decl = SerializeDecl(macroInvocation.decl)
        return CreateMacroInvocation(builder, fullName, identifier, identifierPos, leftSquarePos, rightSquarePos,
            leftParenPos, rightParenPos, atPos, attrs, args, decl, macroInvocation.hasParenthesis,
            macroInvocation.isCompileTimeVisible)
    }

    @OverflowWrapping
    public func ExportNode(): CPointer<UInt8> {
        bufferData.clear()
        var fbNode: FlatBufferOffset = 0u32
        var isSupportedNode = true
        if (let Some(expr) <- (nodePtr as Expr)) {
            let fbExpr = SerializeExpr(expr)
            let nodeBase = SerializeNodeBase(expr)
            fbNode = CreateNode(builder, nodeBase, AnyNode_EXPR, fbExpr)
        } else if (let Some(pattern) <- (nodePtr as Pattern)) {
            let fbPattern = SerializePattern(pattern)
            let nodeBase = SerializeNodeBase(pattern)
            fbNode = CreateNode(builder, nodeBase, AnyNode_PATTERN, fbPattern)
        } else if (let Some(decl) <- (nodePtr as Decl)) {
            let fbDecl = SerializeDecl(decl)
            let nodeBase = SerializeNodeBase(decl)
            fbNode = CreateNode(builder, nodeBase, AnyNode_DECL, fbDecl)
        } else if (let Some(typeNode) <- (nodePtr as Type)) {
            let fbType = SerializeType(typeNode)
            let nodeBase = SerializeNodeBase(typeNode)
            fbNode = CreateNode(builder, nodeBase, AnyNode_TYPE, fbType)
        } else if (let Some(file) <- (nodePtr as File)) {
            let fbFile = SerializeFile(file)
            let nodeBase = SerializeNodeBase(file)
            fbNode = CreateNode(builder, nodeBase, AnyNode_FILE, fbFile)
        } else if (let Some(annotation) <- (nodePtr as Annotation)) {
            let anno = SerializeAnnotation(annotation)
            let nodeBase = SerializeNodeBase(annotation)
            fbNode = CreateNode(builder, nodeBase, AnyNode_ANNOTATION, anno)
        } else {
            Errorln("nodePtr not supported type")
            isSupportedNode = false
        }
        if (isSupportedNode) {
            let payload = builder.Finish(fbNode)
            appendU32LE(bufferData, UInt32(payload.size + 4))
            for (byte in payload) {
                bufferData.add(byte)
            }
        }
        let rawPtr = unsafe { LibC.malloc<UInt8>(count: bufferData.size) }
        if (rawPtr.isNull()) {
            Errorln("Memory Allocation Failed.")
            return rawPtr
        }
        var idx: Int64 = 0
        unsafe {
            while (idx < bufferData.size) {
                rawPtr.write(idx, bufferData[idx])
                idx++
            }
        }
        return rawPtr
    }

    public func SerializeExpr(expr: Option<Expr>): FlatBufferOffset {
        if (let Some(value) <- expr) {
            return SerializeExpr(value)
        }
        return 0u32
    }

    public func SerializeWildcardExpr(expr: Expr): FlatBufferOffset {
        let wildcardExpr = (expr as WildcardExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(wildcardExpr)
        let fbWildcardExpr = CreateWildcardExpr(builder, fbNodeBase)
        return CreateExpr(builder, fbNodeBase, AnyExpr_WILDCARD_EXPR, fbWildcardExpr)
    }

    public func SerializeBinaryExpr(expr: Expr): FlatBufferOffset {
        let binaryExpr = (expr as BinaryExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(binaryExpr)
        let leftExpr = SerializeExpr(binaryExpr.leftExpr)
        let rightExpr = SerializeExpr(binaryExpr.rightExpr)
        let operatorPos = FlatPosCreateHelper(binaryExpr.operatorPos)
        let fbBinaryExpr = CreateBinaryExpr(builder, fbNodeBase, leftExpr, rightExpr, UInt16(TokenKindIndex(binaryExpr.op)),
            operatorPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_BINARY_EXPR, fbBinaryExpr)
    }

    public func SerializeIsExpr(expr: Expr): FlatBufferOffset {
        let isExpr = (expr as IsExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(isExpr)
        let leftExpr = SerializeExpr(isExpr.leftExpr)
        let isType = SerializeType(isExpr.isType)
        let isPos = FlatPosCreateHelper(isExpr.isPos)
        let fbIsExpr = CreateIsExpr(builder, fbNodeBase, leftExpr, isType, isPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_IS_EXPR, fbIsExpr)
    }

    public func SerializeAsExpr(expr: Expr): FlatBufferOffset {
        let asExpr = (expr as AsExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(asExpr)
        let leftExpr = SerializeExpr(asExpr.leftExpr)
        let asType = SerializeType(asExpr.asType)
        let asPos = FlatPosCreateHelper(asExpr.asPos)
        let fbAsExpr = CreateAsExpr(builder, fbNodeBase, leftExpr, asType, asPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_AS_EXPR, fbAsExpr)
    }

    public func SerializeLitConstExpr(expr: Expr): FlatBufferOffset {
        let litConstExpr = (expr as LitConstExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(litConstExpr)
        let value = builder.CreateString(litConstExpr.rawString)
        let fbLitConstExpr = CreateLitConstExpr(builder, fbNodeBase, value,
            UInt16(LitConstKindIndex(litConstExpr.kind)), UInt16(litConstExpr.delimiterNum),
            UInt16(StringKindIndex(litConstExpr.stringKind)), litConstExpr.isSingleQuote)
        return CreateExpr(builder, fbNodeBase, AnyExpr_LIT_CONST_EXPR, fbLitConstExpr)
    }

    public func SerializeUnaryExpr(expr: Expr): FlatBufferOffset {
        let unaryExpr = (expr as UnaryExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(unaryExpr)
        let onlyExpr = SerializeExpr(unaryExpr.expr)
        let op = UInt16(TokenKindIndex(unaryExpr.op))
        let operatorPos = FlatPosCreateHelper(unaryExpr.operatorPos)
        let fbUnaryExpr = CreateUnaryExpr(builder, fbNodeBase, onlyExpr, op, operatorPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_UNARY_EXPR, fbUnaryExpr)
    }

    public func SerializeParenExpr(expr: Expr): FlatBufferOffset {
        let parenExpr = (expr as ParenExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(parenExpr)
        let onlyExpr = SerializeExpr(parenExpr.expr)
        let leftParenPos = FlatPosCreateHelper(parenExpr.leftParenPos)
        let rightParenPos = FlatPosCreateHelper(parenExpr.rightParenPos)
        let fbParenExpr = CreateParenExpr(builder, fbNodeBase, leftParenPos, onlyExpr, rightParenPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_PAREN_EXPR, fbParenExpr)
    }

    public func SerializeFuncArg(funcArg: Option<FuncArg>): FlatBufferOffset {
        if (let Some(value) <- funcArg) {
            return SerializeFuncArg(value)
        }
        return 0u32
    }

    public func SerializeFuncArg(funcArg: FuncArg): FlatBufferOffset {
        let base = SerializeNodeBase(funcArg)
        let name = builder.CreateString(funcArg.name.GetRawText())
        let namePos = FlatPosCreateHelper(funcArg.name.GetRawPos())
        let colonPos = FlatPosCreateHelper(funcArg.colonPos)
        let fbExpr = SerializeExpr(funcArg.expr)
        let commaPos = FlatPosCreateHelper(funcArg.commaPos)
        return CreateFuncArg(builder, base, name, namePos, colonPos, fbExpr, commaPos, funcArg.withInout)
    }

    public func SerializeCallExpr(callExpr: Option<CallExpr>): FlatBufferOffset {
        if (let Some(value) <- callExpr) {
            return SerializeCallExpr(value)
        }
        return 0u32
    }

    public func SerializeCallExpr(callExpr: CallExpr): FlatBufferOffset {
        let fbNodeBase = SerializeNodeBase(callExpr)
        let fbBaseFunc = SerializeExpr(callExpr.baseFunc)
        let leftParenPos = FlatPosCreateHelper(callExpr.leftParenPos)
        let rightParenPos = FlatPosCreateHelper(callExpr.rightParenPos)
        let fbArgs = FlatVectorCreateHelper(callExpr.args, { arg: FuncArg => SerializeFuncArg(arg) })
        return CreateCallExpr(builder, fbNodeBase, fbBaseFunc, leftParenPos, fbArgs, rightParenPos)
    }

    public func SerializeCallExpr(expr: Expr): FlatBufferOffset {
        let callExpr = (expr as CallExpr).getOrThrow()
        let fbCallExpr = SerializeCallExpr(callExpr)
        return CreateExpr(builder, SerializeNodeBase(callExpr), AnyExpr_CALL_EXPR, fbCallExpr)
    }

    public func SerializeRefExpr(refExpr: Option<RefExpr>): FlatBufferOffset {
        if (let Some(value) <- refExpr) {
            return SerializeRefExpr(value)
        }
        return 0u32
    }

    public func SerializeRefExpr(refExpr: RefExpr): FlatBufferOffset {
        let fbNodeBase = SerializeNodeBase(refExpr)
        let refValue = refExpr.ref
        let identifier = builder.CreateString(refValue.identifier.GetRawText())
        let identifierPos = FlatPosCreateHelper(refValue.identifier.GetRawPos())
        let fbRef = CreateReference(builder, identifier, identifierPos)
        let leftAnglePos = FlatPosCreateHelper(refExpr.leftAnglePos)
        let fbTypeVec = FlatVectorCreateHelper(refExpr.typeArguments, { typeItem: Type => SerializeType(typeItem) })
        let rightAnglePos = FlatPosCreateHelper(refExpr.rightAnglePos)
        return CreateRefExpr(builder, fbNodeBase, fbRef, leftAnglePos, fbTypeVec, rightAnglePos, refExpr.isThis,
            refExpr.isSuper, refExpr.isQuoteDollar)
    }

    public func SerializeRefExpr(expr: Expr): FlatBufferOffset {
        let refExpr = (expr as RefExpr).getOrThrow()
        let fbRefExpr = SerializeRefExpr(refExpr)
        return CreateExpr(builder, SerializeNodeBase(refExpr), AnyExpr_REF_EXPR, fbRefExpr)
    }

    public func SerializeBlockExpr(expr: Expr): FlatBufferOffset {
        let block = (expr as Block).getOrThrow()
        let fbBlock = SerializeBlock(block)
        return CreateExpr(builder, SerializeNodeBase(block), AnyExpr_BLOCK, fbBlock)
    }

    public func SerializeReturnExpr(expr: Expr): FlatBufferOffset {
        let returnExpr = (expr as ReturnExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(returnExpr)
        let returnPos = FlatPosCreateHelper(returnExpr.returnPos)
        var fbExpr = SerializeExpr(returnExpr.expr)
        if (let Some(retExpr) <- returnExpr.expr) {
            if (retExpr.TestAttr(Attribute.COMPILER_ADD)) {
                fbExpr = 0u32
            }
        }
        let fbReturnExpr = CreateReturnExpr(builder, fbNodeBase, returnPos, fbExpr)
        return CreateExpr(builder, fbNodeBase, AnyExpr_RETURN_EXPR, fbReturnExpr)
    }

    public func SerializeDoWhileExpr(expr: Expr): FlatBufferOffset {
        let doWhileExpr = (expr as DoWhileExpr).getOrThrow()
        let base = SerializeNodeBase(doWhileExpr)
        let doPos = FlatPosCreateHelper(doWhileExpr.doPos)
        let body = SerializeBlock(doWhileExpr.body)
        let whilePos = FlatPosCreateHelper(doWhileExpr.whilePos)
        let leftParenPos = FlatPosCreateHelper(doWhileExpr.leftParenPos)
        let condExpr = SerializeExpr(doWhileExpr.condExpr)
        let rightParenPos = FlatPosCreateHelper(doWhileExpr.rightParenPos)
        let fbDoWhileExpr = CreateDoWhileExpr(builder, base, doPos, body, whilePos, leftParenPos, condExpr,
            rightParenPos)
        return CreateExpr(builder, base, AnyExpr_DO_WHILE_EXPR, fbDoWhileExpr)
    }

    public func SerializeAssignExpr(expr: Expr): FlatBufferOffset {
        let assignExpr = (expr as AssignExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(assignExpr)
        let fbLeftValue = SerializeExpr(assignExpr.leftValue)
        let assignOp = UInt16(TokenKindIndex(assignExpr.op))
        let assignPos = FlatPosCreateHelper(assignExpr.assignPos)
        let fbRightExpr = SerializeExpr(assignExpr.rightExpr)
        let fbAssignExpr = CreateAssignExpr(builder, fbNodeBase, fbLeftValue, assignOp, assignPos, fbRightExpr)
        return CreateExpr(builder, fbNodeBase, AnyExpr_ASSIGN_EXPR, fbAssignExpr)
    }

    public func SerializeMemberAccess(expr: Expr): FlatBufferOffset {
        let memberAccess = (expr as MemberAccess).getOrThrow()
        let fbNodeBase = SerializeNodeBase(memberAccess)
        let fbBaseExpr = SerializeExpr(memberAccess.baseExpr)
        let dotPos = FlatPosCreateHelper(memberAccess.dotPos)
        let field = builder.CreateString(memberAccess.field.GetRawText())
        let fieldPos = FlatPosCreateHelper(memberAccess.field.GetRawPos())
        let fbTypeArguments = FlatVectorCreateHelper(memberAccess.typeArguments, { typeItem: Type =>
            SerializeType(typeItem)
        })
        let leftAnglePos = FlatPosCreateHelper(memberAccess.leftAnglePos)
        let rightAnglePos = FlatPosCreateHelper(memberAccess.rightAnglePos)
        let fbMemberAccess = CreateMemberAccess(builder, fbNodeBase, fbBaseExpr, dotPos, field, fieldPos, leftAnglePos,
            fbTypeArguments, rightAnglePos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_MEMBER_ACCESS, fbMemberAccess)
    }

    public func SerializeLetPatternDestructor(expr: Expr): FlatBufferOffset {
        let letExpr = (expr as LetPatternDestructor).getOrThrow()
        let fbNodeBase = SerializeNodeBase(letExpr)
        let fbPatterns = FlatVectorCreateHelper(letExpr.patterns, { patternItem: Pattern =>
            SerializePattern(patternItem)
        })
        let backarrowPos = FlatPosCreateHelper(letExpr.backarrowPos)
        let initializer = SerializeExpr(letExpr.initializer)
        let bitOrPosVector = CreatePositionVector(letExpr.orPos)
        let fbLetExpr = CreateLetPatternDestructor(builder, fbNodeBase, fbPatterns, bitOrPosVector, backarrowPos,
            initializer)
        return CreateExpr(builder, fbNodeBase, AnyExpr_LET_PATTERN_DESTRUCTOR, fbLetExpr)
    }

    public func SerializeIfExpr(expr: Expr): FlatBufferOffset {
        let ifExpr = (expr as IfExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(ifExpr)
        let ifPos = FlatPosCreateHelper(ifExpr.ifPos)
        let leftParenPos = FlatPosCreateHelper(ifExpr.leftParenPos)
        let fbCondExpr = SerializeExpr(ifExpr.condExpr)
        let rightParenPos = FlatPosCreateHelper(ifExpr.rightParenPos)
        let fbBody = SerializeBlock(ifExpr.thenBody)
        let elsePos = FlatPosCreateHelper(ifExpr.elsePos)
        var fbElseBody: FlatBufferOffset = 0u32
        if (ifExpr.hasElse) {
            fbElseBody = SerializeExpr(ifExpr.elseBody)
        }
        let fbIfExpr = CreateIfExpr(builder, fbNodeBase, ifPos, fbCondExpr, fbBody, ifExpr.hasElse, elsePos,
            fbElseBody, ifExpr.isElseIf, leftParenPos, rightParenPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_IF_EXPR, fbIfExpr)
    }

    public func SerializeMatchExpr(expr: Expr): FlatBufferOffset {
        let matchExpr = (expr as MatchExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(matchExpr)
        let leftParenPos = FlatPosCreateHelper(matchExpr.leftParenPos)
        let fbSelector = SerializeExpr(matchExpr.selector)
        let rightParenPos = FlatPosCreateHelper(matchExpr.rightParenPos)
        let leftCurlPos = FlatPosCreateHelper(matchExpr.leftCurlPos)
        let fbMatchcases = FlatVectorCreateHelper(matchExpr.matchCases, { matchCase: MatchCase =>
            SerializeMatchCase(matchCase)
        })
        let fbMatchcaseother = FlatVectorCreateHelper(matchExpr.matchCaseOthers, { matchCaseOther: MatchCaseOther =>
            SerializeMatchCaseOther(matchCaseOther)
        })
        let rightCurlPos = FlatPosCreateHelper(matchExpr.rightCurlPos)
        let fbMatchExpr = CreateMatchExpr(builder, fbNodeBase, matchExpr.matchMode, leftParenPos, fbSelector,
            rightParenPos, leftCurlPos, fbMatchcases, fbMatchcaseother, rightCurlPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_MATCH_EXPR, fbMatchExpr)
    }

    public func SerializeWhileExpr(expr: Expr): FlatBufferOffset {
        let whileExpr = (expr as WhileExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(whileExpr)
        let whilePos = FlatPosCreateHelper(whileExpr.whilePos)
        let leftParenPos = FlatPosCreateHelper(whileExpr.leftParenPos)
        let fbCondExpr = SerializeExpr(whileExpr.condExpr)
        let rightParenPos = FlatPosCreateHelper(whileExpr.rightParenPos)
        let fbBody = SerializeBlock(whileExpr.body)
        let fbWhileExpr = CreateWhileExpr(builder, fbNodeBase, whilePos, leftParenPos, fbCondExpr, rightParenPos,
            fbBody)
        return CreateExpr(builder, fbNodeBase, AnyExpr_WHILE_EXPR, fbWhileExpr)
    }

    public func SerializeArrayLit(expr: Expr): FlatBufferOffset {
        let arrayLit = (expr as ArrayLit).getOrThrow()
        let fbNodeBase = SerializeNodeBase(arrayLit)
        let leftCurlPos = FlatPosCreateHelper(arrayLit.leftSquarePos)
        let fbExs = FlatVectorCreateHelper(arrayLit.children, { child: Expr => SerializeExpr(child) })
        let commaPosVector = CreatePositionVector(arrayLit.commaPosVector)
        let rightCurlPos = FlatPosCreateHelper(arrayLit.rightSquarePos)
        let fbArrayLit = CreateArrayLit(builder, fbNodeBase, leftCurlPos, fbExs, commaPosVector, rightCurlPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_ARRAY_LIT, fbArrayLit)
    }

    public func SerializeTupleLit(expr: Expr): FlatBufferOffset {
        let tupleLit = (expr as TupleLit).getOrThrow()
        let fbNodeBase = SerializeNodeBase(tupleLit)
        let leftParenPos = FlatPosCreateHelper(tupleLit.leftParenPos)
        let fbExs = FlatVectorCreateHelper(tupleLit.children, { child: Expr => SerializeExpr(child) })
        let commaPositions = CreatePositionVector(tupleLit.commaPosVector)
        let rightParenPos = FlatPosCreateHelper(tupleLit.rightParenPos)
        let fbTupleLit = CreateTupleLit(builder, fbNodeBase, leftParenPos, fbExs, commaPositions, rightParenPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_TUPLE_LIT, fbTupleLit)
    }

    public func SerializeSubscriptExpr(expr: Expr): FlatBufferOffset {
        let subscriptExpr = (expr as SubscriptExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(subscriptExpr)
        let fbBaseExpr = SerializeExpr(subscriptExpr.baseExpr)
        let leftSquarePos = FlatPosCreateHelper(subscriptExpr.leftParenPos)
        let fbIndexExprs = FlatVectorCreateHelper(subscriptExpr.indexExprs, { child: Expr => SerializeExpr(child) })
        let rightSquarePos = FlatPosCreateHelper(subscriptExpr.rightParenPos)
        let fbSubscriptExpr = CreateSubscriptExpr(builder, fbNodeBase, fbBaseExpr, leftSquarePos, fbIndexExprs,
            rightSquarePos, subscriptExpr.isTupleAccess)
        return CreateExpr(builder, fbNodeBase, AnyExpr_SUBSCRIPT_EXPR, fbSubscriptExpr)
    }

    public func SerializeRangeExpr(expr: Expr): FlatBufferOffset {
        let rangeExpr = (expr as RangeExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(rangeExpr)
        let fbStartExpr = SerializeExpr(rangeExpr.startExpr)
        let rangePos = FlatPosCreateHelper(rangeExpr.rangePos)
        let fbStopExpr = SerializeExpr(rangeExpr.stopExpr)
        let colonPos = FlatPosCreateHelper(rangeExpr.colonPos)
        let fbStepExpr = SerializeExpr(rangeExpr.stepExpr)
        let fbRangeExpr = CreateRangeExpr(builder, fbNodeBase, fbStartExpr, rangePos, fbStopExpr, colonPos, fbStepExpr,
            rangeExpr.isClosed)
        return CreateExpr(builder, fbNodeBase, AnyExpr_RANGE_EXPR, fbRangeExpr)
    }

    public func SerializeLambdaExpr(lambdaExpr: Option<LambdaExpr>): FlatBufferOffset {
        if (let Some(value) <- lambdaExpr) {
            return SerializeLambdaExpr(value)
        }
        return 0u32
    }

    public func SerializeLambdaExpr(lambdaExpr: LambdaExpr): FlatBufferOffset {
        let fbNodeBase = SerializeNodeBase(lambdaExpr)
        let fbBody = SerializeFuncBody(lambdaExpr.funcBody)
        let mockSupported = lambdaExpr.TestAttr(Attribute.MOCK_SUPPORTED)
        return CreateLambdaExpr(builder, fbNodeBase, fbBody, mockSupported)
    }

    public func SerializeLambdaExpr(expr: Expr): FlatBufferOffset {
        let lambdaExpr = (expr as LambdaExpr).getOrThrow()
        let fbLambdaExpr = SerializeLambdaExpr(lambdaExpr)
        return CreateExpr(builder, SerializeNodeBase(lambdaExpr), AnyExpr_LAMBDA_EXPR, fbLambdaExpr)
    }

    public func SerializeSpawnExpr(expr: Expr): FlatBufferOffset {
        let spawnExpr = (expr as SpawnExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(spawnExpr)
        let spawnPos = FlatPosCreateHelper(spawnExpr.spawnPos)
        let taskExpr = SerializeExpr(spawnExpr.task)
        let hasArg = spawnExpr.arg.isSome()
        let spawnArgExpr = SerializeExpr(spawnExpr.arg)
        let leftParenPos = FlatPosCreateHelper(spawnExpr.leftParenPos)
        let rightParenPos = FlatPosCreateHelper(spawnExpr.rightParenPos)
        let fbSpawnExpr = CreateSpawnExpr(builder, fbNodeBase, spawnPos, taskExpr, hasArg, spawnArgExpr, leftParenPos,
            rightParenPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_SPAWN_EXPR, fbSpawnExpr)
    }

    public func SerializeSynchronizedExpr(expr: Expr): FlatBufferOffset {
        let synchronizedExpr = (expr as SynchronizedExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(synchronizedExpr)
        let syncPos = FlatPosCreateHelper(synchronizedExpr.syncPos)
        let leftParenPos = FlatPosCreateHelper(synchronizedExpr.leftParenPos)
        let mutexExpr = SerializeExpr(synchronizedExpr.mutex)
        let rightParenPos = FlatPosCreateHelper(synchronizedExpr.rightParenPos)
        let body = SerializeBlock(synchronizedExpr.body)
        let fbSynchronizedExpr = CreateSynchronizedExpr(builder, fbNodeBase, syncPos, leftParenPos, mutexExpr,
            rightParenPos, body)
        return CreateExpr(builder, fbNodeBase, AnyExpr_SYNCHRONIZED_EXPR, fbSynchronizedExpr)
    }

    public func SerializeTrailingClosureExpr(expr: Expr): FlatBufferOffset {
        let trailingClosureExpr = (expr as TrailingClosureExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(trailingClosureExpr)
        let leftLambdaPos = FlatPosCreateHelper(trailingClosureExpr.leftLambda)
        let fbExpr = SerializeExpr(trailingClosureExpr.expr)
        let fbLambdaExpr = SerializeLambdaExpr(trailingClosureExpr.lambda)
        let rightLambdaPos = FlatPosCreateHelper(trailingClosureExpr.rightLambda)
        let fbTrailingClosureExpr = CreateTrailingClosureExpr(builder, fbNodeBase, leftLambdaPos, fbExpr, fbLambdaExpr,
            rightLambdaPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_TRAILING_CLOSURE_EXPR, fbTrailingClosureExpr)
    }

    public func SerializeTypeConvExpr(expr: Expr): FlatBufferOffset {
        let typeConvExpr = (expr as TypeConvExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(typeConvExpr)
        let fbPrimitiveType = SerializeType(typeConvExpr.typeNode)
        let leftParenPos = FlatPosCreateHelper(typeConvExpr.leftParenPos)
        let fbExpr = SerializeExpr(typeConvExpr.expr)
        let rightParenPos = FlatPosCreateHelper(typeConvExpr.rightParenPos)
        let fbTypeConvExpr = CreateTypeConvExpr(builder, fbNodeBase, fbPrimitiveType, leftParenPos, fbExpr,
            rightParenPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_TYPE_CONV_EXPR, fbTypeConvExpr)
    }

    public func SerializeTryExpr(expr: Expr): FlatBufferOffset {
        let tryExpr = (expr as TryExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(tryExpr)
        let fbLParenPos = FlatPosCreateHelper(tryExpr.lParen)
        let fbResource = FlatVectorCreateHelper(tryExpr.resourceSpec, { resource: VarDecl => SerializeVarDecl(resource) })
        let fbRParenPos = FlatPosCreateHelper(tryExpr.rParen)
        let fbCommaPos = CreatePositionVector(tryExpr.resourceSpecCommaPos)
        let fbTryBlock = SerializeBlock(tryExpr.tryBlock)
        let fbCatchPos = CreatePositionVector(tryExpr.catchPosVector)
        let fbCatchLParenPos = CreatePositionVector(tryExpr.catchLParenPosVector)
        let fbCatchRParenPos = CreatePositionVector(tryExpr.catchRParenPosVector)
        let fbCatchBlocks = FlatVectorCreateHelper(tryExpr.catchBlocks, { block: Block => SerializeBlock(block) })
        let fbCatchPatterns = FlatVectorCreateHelper(tryExpr.catchPatterns, { pattern: Pattern =>
            SerializePattern(pattern)
        })
        let vecHandlers = ArrayList<FlatBufferOffset>()
        for (handler in tryExpr.handlers) {
            let fbPos = FlatPosCreateHelper(handler.pos)
            let fbCommandPattern = SerializePattern(handler.commandPattern)
            let fbHandleBlock = SerializeBlock(handler.block)
            let fbHandler = CreateHandler(builder, fbPos, fbCommandPattern, fbHandleBlock)
            vecHandlers.add(fbHandler)
        }
        let fbHandlers = builder.CreateVectorOffsets(vecHandlers)
        let finallyPos = FlatPosCreateHelper(tryExpr.finallyPos)
        let fbFinallyBlock = SerializeBlock(tryExpr.finallyBlock)
        let fbTryExpr = CreateTryExpr(builder, fbNodeBase, fbResource, tryExpr.isDesugaredFromTryWithResources,
            fbTryBlock, fbCatchBlocks, fbCatchPatterns, finallyPos, fbFinallyBlock, fbLParenPos, fbRParenPos,
            fbCommaPos, fbCatchPos, fbCatchLParenPos, fbCatchRParenPos, fbHandlers)
        return CreateExpr(builder, fbNodeBase, AnyExpr_TRY_EXPR, fbTryExpr)
    }

    public func SerializeThrowExpr(expr: Expr): FlatBufferOffset {
        let throwExpr = (expr as ThrowExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(throwExpr)
        let fbExpr = SerializeExpr(throwExpr.expr)
        let fbThrowExpr = CreateThrowExpr(builder, fbNodeBase, fbExpr)
        return CreateExpr(builder, fbNodeBase, AnyExpr_THROW_EXPR, fbThrowExpr)
    }

    public func SerializePerformExpr(expr: Expr): FlatBufferOffset {
        let performExpr = (expr as PerformExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(performExpr)
        let fbExpr = SerializeExpr(performExpr.expr)
        let fbPerformExpr = CreatePerformExpr(builder, fbNodeBase, fbExpr)
        return CreateExpr(builder, fbNodeBase, AnyExpr_PERFORM_EXPR, fbPerformExpr)
    }

    public func SerializeResumeExpr(expr: Expr): FlatBufferOffset {
        let resumeExpr = (expr as ResumeExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(resumeExpr)
        let withPos = FlatPosCreateHelper(resumeExpr.withPos)
        let withExpr = SerializeExpr(resumeExpr.withExpr)
        let throwingPos = FlatPosCreateHelper(resumeExpr.throwingPos)
        let throwingExpr = SerializeExpr(resumeExpr.throwingExpr)
        let fbResumeExpr = CreateResumeExpr(builder, fbNodeBase, withPos, withExpr, throwingPos, throwingExpr)
        return CreateExpr(builder, fbNodeBase, AnyExpr_RESUME_EXPR, fbResumeExpr)
    }

    public func SerializePrimitiveTypeExpr(expr: Expr): FlatBufferOffset {
        let primitiveTypeExpr = (expr as PrimitiveTypeExpr).getOrThrow()
        let fbTypeBase = SerializeNodeBase(primitiveTypeExpr)
        let typeKind = UInt16(TypeKindIndex(primitiveTypeExpr.typeKind))
        let fbPrimTypeExpr = CreatePrimitiveTypeExpr(builder, fbTypeBase, typeKind)
        return CreateExpr(builder, fbTypeBase, AnyExpr_PRIMITIVE_TYPE_EXPR, fbPrimTypeExpr)
    }

    public func SerializeForInExpr(expr: Expr): FlatBufferOffset {
        let forinExpr = (expr as ForInExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(forinExpr)
        let leftParenPos = FlatPosCreateHelper(forinExpr.leftParenPos)
        let fbPattern = SerializePattern(forinExpr.pattern)
        let inPos = FlatPosCreateHelper(forinExpr.inPos)
        let fbInExpr = SerializeExpr(forinExpr.inExpression)
        let rightParenPos = FlatPosCreateHelper(forinExpr.rightParenPos)
        let ifPos = FlatPosCreateHelper(forinExpr.wherePos)
        let fbPatternGuard = SerializeExpr(forinExpr.patternGuard)
        let fbBody = SerializeBlock(forinExpr.body)
        let fbForInExpr = CreateForInExpr(builder, fbNodeBase, leftParenPos, fbPattern, inPos, fbInExpr,
            rightParenPos, ifPos, fbPatternGuard, fbBody)
        return CreateExpr(builder, fbNodeBase, AnyExpr_FOR_IN_EXPR, fbForInExpr)
    }

    public func SerializeJumpExpr(expr: Expr): FlatBufferOffset {
        let jumpExpr = (expr as JumpExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(jumpExpr)
        let fbJumpExpr = CreateJumpExpr(builder, fbNodeBase, jumpExpr.isBreak)
        return CreateExpr(builder, fbNodeBase, AnyExpr_JUMP_EXPR, fbJumpExpr)
    }

    public func SerializeIncOrDecExpr(expr: Expr): FlatBufferOffset {
        let incOrDecExpr = (expr as IncOrDecExpr).getOrThrow()
        let base = SerializeNodeBase(incOrDecExpr)
        let op = UInt16(TokenKindIndex(incOrDecExpr.op))
        let operatorPos = FlatPosCreateHelper(incOrDecExpr.operatorPos)
        let expr0 = SerializeExpr(incOrDecExpr.expr)
        let fbIncOrDecExpr = CreateIncOrDecExpr(builder, base, op, operatorPos, expr0)
        return CreateExpr(builder, base, AnyExpr_INC_OR_DEC_EXPR, fbIncOrDecExpr)
    }

    public func SerializeOptionalExpr(expr: Expr): FlatBufferOffset {
        let optionalExpr = (expr as OptionalExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(optionalExpr)
        let baseExpr = SerializeExpr(optionalExpr.baseExpr)
        let questPos = FlatPosCreateHelper(optionalExpr.questPos)
        let fbOptionalExpr = CreateOptionalExpr(builder, fbNodeBase, baseExpr, questPos)
        return CreateExpr(builder, fbNodeBase, AnyExpr_OPTIONAL_EXPR, fbOptionalExpr)
    }

    public func SerializeOptionalChainExpr(expr: Expr): FlatBufferOffset {
        let optionalChainExpr = (expr as OptionalChainExpr).getOrThrow()
        let fbNodeBase = SerializeNodeBase(optionalChainExpr)
        let optexpr = SerializeExpr(optionalChainExpr.expr)
        let fbOptionalChainExpr = CreateOptionalChainExpr(builder, fbNodeBase, optexpr)
        return CreateExpr(builder, fbNodeBase, AnyExpr_OPTIONAL_CHAIN_EXPR, fbOptionalChainExpr)
    }

    public func SerializeTokenPart(expr: Expr): FlatBufferOffset {
        let tokenPart = (expr as TokenPart).getOrThrow()
        let vecToken = TokensVectorCreateHelper(tokenPart.tokens)
        let fbTokens = builder.CreateVectorOffsets(vecToken)
        let fbTokenPart = CreateTokenPart(builder, fbTokens)
        return CreateExpr(builder, SerializeNodeBase(tokenPart), AnyExpr_TOKEN_PART, fbTokenPart)
    }

    public func SerializeQuoteExpr(expr: Expr): FlatBufferOffset {
        let quoteExpr = (expr as QuoteExpr).getOrThrow()
        let base = SerializeNodeBase(quoteExpr)
        let leftParenPos = FlatPosCreateHelper(quoteExpr.leftParenPos)
        let rightParenPos = FlatPosCreateHelper(quoteExpr.rightParenPos)
        let vecExpr = ArrayList<FlatBufferOffset>()
        for (child in quoteExpr.exprs) {
            vecExpr.add(SerializeExpr(child))
        }
        let fbExprs = builder.CreateVectorOffsets(vecExpr)
        let fbQuoteExpr = CreateQuoteExpr(builder, base, leftParenPos, fbExprs, rightParenPos)
        return CreateExpr(builder, base, AnyExpr_QUOTE_EXPR, fbQuoteExpr)
    }

    public func SerializeMacroExpandExpr(expr: Expr): FlatBufferOffset {
        let macroExpandExpr = (expr as MacroExpandExpr).getOrThrow()
        let base = SerializeNodeBase(macroExpandExpr)
        let invocation = MacroInvocationCreateHelper(macroExpandExpr.invocation)
        let identifier = builder.CreateString(macroExpandExpr.identifier.Val())
        let identifierPos = FlatPosCreateHelper(macroExpandExpr.identifier.Begin())
        let annotationVec = FlatVectorCreateHelper(macroExpandExpr.annotations, { annotationItem: Annotation =>
            SerializeAnnotation(annotationItem)
        })
        let vecModifier = ArrayList<FlatBufferOffset>()
        let modifiersVec = SortModifierByPos(macroExpandExpr.modifiers)
        for (mod in modifiersVec) {
            vecModifier.add(SerializeModifier(mod))
        }
        let fbModVec = builder.CreateVectorOffsets(vecModifier)
        let fbMacroExpandExpr = CreateMacroExpandExpr(builder, base, invocation, identifier, identifierPos,
            annotationVec, fbModVec)
        return CreateExpr(builder, base, AnyExpr_MACRO_EXPAND_EXPR, fbMacroExpandExpr)
    }

    public func SerializeArrayExpr(expr: Expr): FlatBufferOffset {
        let arrayExpr = (expr as ArrayExpr).getOrThrow()
        let base = SerializeNodeBase(arrayExpr)
        let typeValue = SerializeType(arrayExpr.typeNode)
        let leftParenPos = FlatPosCreateHelper(arrayExpr.leftParenPos)
        let args = FlatVectorCreateHelper(arrayExpr.args, { arg: FuncArg => SerializeFuncArg(arg) })
        let rightParenPos = FlatPosCreateHelper(arrayExpr.rightParenPos)
        let fbArrayExpr = CreateArrayExpr(builder, base, typeValue, leftParenPos, args, rightParenPos,
            arrayExpr.isValueArray)
        return CreateExpr(builder, base, AnyExpr_ARRAY_EXPR, fbArrayExpr)
    }

    public func SerializeExpr(expr: Expr): FlatBufferOffset {
        if (ASTKindEquals(expr.astKind, ASTKind.WILDCARD_EXPR)) {
            return SerializeWildcardExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.BINARY_EXPR)) {
            return SerializeBinaryExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.LIT_CONST_EXPR)) {
            return SerializeLitConstExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.UNARY_EXPR)) {
            return SerializeUnaryExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.PAREN_EXPR)) {
            return SerializeParenExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.CALL_EXPR)) {
            return SerializeCallExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.REF_EXPR)) {
            return SerializeRefExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.RETURN_EXPR)) {
            return SerializeReturnExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.ASSIGN_EXPR)) {
            return SerializeAssignExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.MEMBER_ACCESS)) {
            return SerializeMemberAccess(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.IF_EXPR)) {
            return SerializeIfExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.BLOCK)) {
            return SerializeBlockExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.LAMBDA_EXPR)) {
            return SerializeLambdaExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.TYPE_CONV_EXPR)) {
            return SerializeTypeConvExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.FOR_IN_EXPR)) {
            return SerializeForInExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.ARRAY_LIT)) {
            return SerializeArrayLit(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.TUPLE_LIT)) {
            return SerializeTupleLit(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.SUBSCRIPT_EXPR)) {
            return SerializeSubscriptExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.RANGE_EXPR)) {
            return SerializeRangeExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.MATCH_EXPR)) {
            return SerializeMatchExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.TRY_EXPR)) {
            return SerializeTryExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.THROW_EXPR)) {
            return SerializeThrowExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.PERFORM_EXPR)) {
            return SerializePerformExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.RESUME_EXPR)) {
            return SerializeResumeExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.JUMP_EXPR)) {
            return SerializeJumpExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.WHILE_EXPR)) {
            return SerializeWhileExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.DO_WHILE_EXPR)) {
            return SerializeDoWhileExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.INC_OR_DEC_EXPR)) {
            return SerializeIncOrDecExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.TOKEN_PART)) {
            return SerializeTokenPart(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.QUOTE_EXPR)) {
            return SerializeQuoteExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.IS_EXPR)) {
            return SerializeIsExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.AS_EXPR)) {
            return SerializeAsExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.SPAWN_EXPR)) {
            return SerializeSpawnExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.SYNCHRONIZED_EXPR)) {
            return SerializeSynchronizedExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.OPTIONAL_EXPR)) {
            return SerializeOptionalExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.OPTIONAL_CHAIN_EXPR)) {
            return SerializeOptionalChainExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.TRAIL_CLOSURE_EXPR)) {
            return SerializeTrailingClosureExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.PRIMITIVE_TYPE_EXPR)) {
            return SerializePrimitiveTypeExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.LET_PATTERN_DESTRUCTOR)) {
            return SerializeLetPatternDestructor(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.MACRO_EXPAND_EXPR)) {
            return SerializeMacroExpandExpr(expr)
        } else if (ASTKindEquals(expr.astKind, ASTKind.ARRAY_EXPR)) {
            return SerializeArrayExpr(expr)
        }
        Errorln("Expr Not Supported in Libast Yet\n")
        return 0u32
    }
}
