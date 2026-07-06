package cangjie_compiler::ast

import cangjie_compiler::basic.StringConvertor
import std.collection.*

public func PrintNode(node: Node, indent!: UInt64 = 0, addition!: String = ""): String {
    let state = PrintState()
    state.PrintAstNode(node, indent, addition)
    return state.Result()
}

private class PrintState {
    private let builder: StringBuilder = StringBuilder()

    public init() {}

    public func Result(): String {
        return builder.toString()
    }

    public func PrintAstNode(node: Node, indent: UInt64, addition: String): Unit {
        if (!addition.isEmpty()) {
            printLine(indent, "// " + addition)
        }
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                PrintAstNode(desugar, indent, addition)
                return
            }
        }

        if (let Some(pkg) <- (node as Package)) { printPackage(pkg, indent); return }
        if (let Some(file) <- (node as File)) { printFile(file, indent); return }

        if (let Some(gpd) <- (node as GenericParamDecl)) { printGenericParamDecl(gpd, indent); return }
        if (let Some(param) <- (node as FuncParam)) { printFuncParam(param, indent); return }
        if (let Some(macroParam) <- (node as MacroExpandParam)) { printMacroExpandParam(macroParam, indent); return }
        if (let Some(paramList) <- (node as FuncParamList)) { printFuncParamList(paramList, indent); return }
        if (let Some(mainDecl) <- (node as MainDecl)) { printMainDecl(mainDecl, indent); return }
        if (let Some(funcDecl) <- (node as FuncDecl)) { printFuncDecl(funcDecl, indent); return }
        if (let Some(macroDecl) <- (node as MacroDecl)) { printMacroDecl(macroDecl, indent); return }
        if (let Some(body) <- (node as FuncBody)) { printFuncBody(body, indent); return }
        if (let Some(propDecl) <- (node as PropDecl)) { printPropDecl(propDecl, indent); return }
        if (let Some(macroDecl) <- (node as MacroExpandDecl)) { printMacroExpandDecl(macroDecl, indent); return }
        if (let Some(vwpd) <- (node as VarWithPatternDecl)) { printVarWithPatternDecl(vwpd, indent); return }
        if (let Some(varDecl) <- (node as VarDecl)) { printVarDecl(varDecl, indent); return }
        if (let Some(alias) <- (node as TypeAliasDecl)) { printTypeAliasDecl(alias, indent); return }
        if (let Some(classDecl) <- (node as ClassDecl)) { printClassDecl(classDecl, indent); return }
        if (let Some(interfaceDecl) <- (node as InterfaceDecl)) { printInterfaceDecl(interfaceDecl, indent); return }
        if (let Some(enumDecl) <- (node as EnumDecl)) { printEnumDecl(enumDecl, indent); return }
        if (let Some(structDecl) <- (node as StructDecl)) { printStructDecl(structDecl, indent); return }
        if (let Some(extendDecl) <- (node as ExtendDecl)) { printExtendDecl(extendDecl, indent); return }
        if (let Some(primaryCtor) <- (node as PrimaryCtorDecl)) { printPrimaryCtorDecl(primaryCtor, indent); return }
        if (let Some(invalidDecl) <- (node as InvalidDecl)) { printInvalidDecl(invalidDecl, indent); return }
        if (let Some(builtin) <- (node as BuiltInDecl)) { printBuiltInDecl(builtin, indent); return }

        if (let Some(ifAvailable) <- (node as IfAvailableExpr)) { printIfAvailableExpr(ifAvailable, indent); return }
        if (let Some(macroExpr) <- (node as MacroExpandExpr)) { printMacroExpandExpr(macroExpr, indent); return }
        if (let Some(ifExpr) <- (node as IfExpr)) { printIfExpr(ifExpr, indent); return }
        if (let Some(matchCase) <- (node as MatchCase)) { printMatchCase(matchCase, indent); return }
        if (let Some(matchOther) <- (node as MatchCaseOther)) { printMatchCaseOther(matchOther, indent); return }
        if (let Some(matchExpr) <- (node as MatchExpr)) { printMatchExpr(matchExpr, indent); return }
        if (let Some(tryExpr) <- (node as TryExpr)) { printTryExpr(tryExpr, indent); return }
        if (let Some(throwExpr) <- (node as ThrowExpr)) { printThrowExpr(throwExpr, indent); return }
        if (let Some(performExpr) <- (node as PerformExpr)) { printPerformExpr(performExpr, indent); return }
        if (let Some(resumeExpr) <- (node as ResumeExpr)) { printResumeExpr(resumeExpr, indent); return }
        if (let Some(returnExpr) <- (node as ReturnExpr)) { printReturnExpr(returnExpr, indent); return }
        if (let Some(jumpExpr) <- (node as JumpExpr)) { printJumpExpr(jumpExpr, indent); return }
        if (let Some(forIn) <- (node as ForInExpr)) { printForInExpr(forIn, indent); return }
        if (let Some(whileExpr) <- (node as WhileExpr)) { printWhileExpr(whileExpr, indent); return }
        if (let Some(doWhile) <- (node as DoWhileExpr)) { printDoWhileExpr(doWhile, indent); return }
        if (let Some(assign) <- (node as AssignExpr)) { printAssignExpr(assign, indent); return }
        if (let Some(incOrDec) <- (node as IncOrDecExpr)) { printIncOrDecExpr(incOrDec, indent); return }
        if (let Some(unary) <- (node as UnaryExpr)) { printUnaryExpr(unary, indent); return }
        if (let Some(binary) <- (node as BinaryExpr)) { printBinaryExpr(binary, indent); return }
        if (let Some(rangeExpr) <- (node as RangeExpr)) { printRangeExpr(rangeExpr, indent); return }
        if (let Some(subscript) <- (node as SubscriptExpr)) { printSubscriptExpr(subscript, indent); return }
        if (let Some(member) <- (node as MemberAccess)) { printMemberAccess(member, indent); return }
        if (let Some(arg) <- (node as FuncArg)) { printFuncArg(arg, indent); return }
        if (let Some(call) <- (node as CallExpr)) { printCallExpr(call, indent); return }
        if (let Some(parenExpr) <- (node as ParenExpr)) { printParenExpr(parenExpr, indent); return }
        if (let Some(lambda) <- (node as LambdaExpr)) { printLambdaExpr(lambda, indent); return }
        if (let Some(lit) <- (node as LitConstExpr)) { printLitConstExpr(lit, indent); return }
        if (let Some(interpolation) <- (node as InterpolationExpr)) { printInterpolationExpr(interpolation, indent); return }
        if (let Some(strInterpolation) <- (node as StrInterpolationExpr)) {
            printStrInterpolationExpr(strInterpolation, indent)
            return
        }
        if (let Some(arrayLit) <- (node as ArrayLit)) { printArrayLit(arrayLit, indent); return }
        if (let Some(arrayExpr) <- (node as ArrayExpr)) { printArrayExpr(arrayExpr, indent); return }
        if (let Some(pointerExpr) <- (node as PointerExpr)) { printPointerExpr(pointerExpr, indent); return }
        if (let Some(tupleLit) <- (node as TupleLit)) { printTupleLit(tupleLit, indent); return }
        if (let Some(typeConv) <- (node as TypeConvExpr)) { printTypeConvExpr(typeConv, indent); return }
        if (let Some(refExpr) <- (node as RefExpr)) { printRefExpr(refExpr, indent); return }
        if (let Some(optional) <- (node as OptionalExpr)) { printOptionalExpr(optional, indent); return }
        if (let Some(chain) <- (node as OptionalChainExpr)) { printOptionalChainExpr(chain, indent); return }
        if (let Some(letPattern) <- (node as LetPatternDestructor)) { printLetPatternDestructor(letPattern, indent); return }
        if (let Some(primitiveTypeExpr) <- (node as PrimitiveTypeExpr)) {
            printPrimitiveTypeExpr(primitiveTypeExpr, indent)
            return
        }
        if (let Some(spawnExpr) <- (node as SpawnExpr)) { printSpawnExpr(spawnExpr, indent); return }
        if (let Some(syncExpr) <- (node as SynchronizedExpr)) { printSynchronizedExpr(syncExpr, indent); return }
        if (let Some(invalidExpr) <- (node as InvalidExpr)) { printInvalidExpr(invalidExpr, indent); return }
        if (let Some(wildcardExpr) <- (node as WildcardExpr)) { printLine(indent, "WildcardExpr: _"); return }
        if (let Some(block) <- (node as Block)) { printBlock(block, indent); return }

        if (let Some(interfaceBody) <- (node as InterfaceBody)) { printInterfaceBody(interfaceBody, indent); return }
        if (let Some(classBody) <- (node as ClassBody)) { printClassBody(classBody, indent); return }
        if (let Some(structBody) <- (node as StructBody)) { printStructBody(structBody, indent); return }

        if (let Some(isExpr) <- (node as IsExpr)) { printIsExpr(isExpr, indent); return }
        if (let Some(asExpr) <- (node as AsExpr)) { printAsExpr(asExpr, indent); return }
        if (let Some(tokenPart) <- (node as TokenPart)) { printTokenPart(tokenPart, indent); return }
        if (let Some(quoteExpr) <- (node as QuoteExpr)) { printQuoteExpr(quoteExpr, indent); return }

        if (let Some(refType) <- (node as RefType)) { printRefType(refType, indent); return }
        if (let Some(parenType) <- (node as ParenType)) { printParenType(parenType, indent); return }
        if (let Some(funcType) <- (node as FuncType)) { printFuncType(funcType, indent); return }
        if (let Some(tupleType) <- (node as TupleType)) { printTupleType(tupleType, indent); return }
        if (let Some(thisType) <- (node as ThisType)) { printThisType(thisType, indent); return }
        if (let Some(primitiveType) <- (node as PrimitiveType)) { printPrimitiveType(primitiveType, indent); return }
        if (let Some(optionType) <- (node as OptionType)) { printOptionType(optionType, indent); return }
        if (let Some(varrayType) <- (node as VArrayType)) { printVArrayType(varrayType, indent); return }
        if (let Some(qualifiedType) <- (node as QualifiedType)) { printQualifiedType(qualifiedType, indent); return }
        if (let Some(genericConstraint) <- (node as GenericConstraint)) {
            printGenericConstraint(genericConstraint, indent)
            return
        }
        if (let Some(generic) <- (node as Generic)) { printGenericNode(generic, indent); return }
        if (let Some(invalidType) <- (node as InvalidType)) { printInvalidType(invalidType, indent); return }

        if (let Some(constPattern) <- (node as ConstPattern)) { printConstPattern(constPattern, indent); return }
        if (let Some(wildcardPattern) <- (node as WildcardPattern)) {
            printLine(indent, "WildcardPattern: " + wildcardPattern.ToString())
            return
        }
        if (let Some(varPattern) <- (node as VarPattern)) { printVarPattern(varPattern, indent); return }
        if (let Some(tuplePattern) <- (node as TuplePattern)) { printTuplePattern(tuplePattern, indent); return }
        if (let Some(typePattern) <- (node as TypePattern)) { printTypePattern(typePattern, indent); return }
        if (let Some(enumPattern) <- (node as EnumPattern)) { printEnumPattern(enumPattern, indent); return }
        if (let Some(exceptPattern) <- (node as ExceptTypePattern)) { printExceptTypePattern(exceptPattern, indent); return }
        if (let Some(commandPattern) <- (node as CommandTypePattern)) {
            printCommandTypePattern(commandPattern, indent)
            return
        }
        if (let Some(varOrEnum) <- (node as VarOrEnumPattern)) { printVarOrEnumPattern(varOrEnum, indent); return }
        if (let Some(invalidPattern) <- (node as InvalidPattern)) { printInvalidPattern(invalidPattern, indent); return }

        if (let Some(featureId) <- (node as FeatureId)) { printFeatureId(featureId, indent); return }
        if (let Some(featuresSet) <- (node as FeaturesSet)) { printFeaturesSet(featuresSet, indent); return }
        if (let Some(featuresDirective) <- (node as FeaturesDirective)) {
            printFeaturesDirective(featuresDirective, indent)
            return
        }
        if (let Some(packageSpec) <- (node as PackageSpec)) { printPackageSpec(packageSpec, indent); return }
        if (let Some(importSpec) <- (node as ImportSpec)) {
            if (importSpec.content.kind == ImportKind.IMPORT_MULTI) {
                return
            }
            printImportSpec(importSpec, indent)
            return
        }
        if (let Some(importContent) <- (node as ImportContent)) { printImportContent(importContent, indent); return }
        if (let Some(annotation) <- (node as Annotation)) { printAnnotation(annotation, indent); return }
        if (let Some(modifier) <- (node as Modifier)) { printModifier(modifier, indent); return }
        if (let Some(dummyBody) <- (node as DummyBody)) { printDefaultNode(dummyBody, indent); return }

        printDefaultNode(node, indent)
    }

    private func printLine(indent: UInt64, text: String): Unit {
        appendIndent(builder, indent)
        builder.append(text)
        builder.append("\n")
    }

    private func open(indent: UInt64, text: String): Unit {
        printLine(indent, text + " {")
    }

    private func close(indent: UInt64): Unit {
        printLine(indent, "}")
    }

    private func boolText(value: Bool): String {
        return if (value) { "true" } else { "false" }
    }

    private func streamBoolText(value: Bool): String {
        return if (value) { "1" } else { "0" }
    }

    private func objectIdPtrText(objectId: Int64): String {
        var value = UInt64(objectId)
        if (value == 0u64) {
            return "0x0"
        }
        let digits = "0123456789abcdef"
        var out = ""
        while (value != 0u64) {
            let idx = Int64(value % 16u64)
            out = digits[idx..idx + 1] + out
            value = value / 16u64
        }
        return "0x" + out
    }

    private func nodePtrText(node: Node): String {
        return objectIdPtrText(node.objectId)
    }

    private func nodePtrText(node: Option<Pattern>): String {
        if (let Some(value) <- node) {
            return objectIdPtrText(value.objectId)
        }
        return "0x0"
    }

    private func printExprOpt(node: Option<Expr>, indent: UInt64, addition: String): Unit {
        if (let Some(value) <- node) {
            PrintAstNode(value, indent, addition)
        } else if (!addition.isEmpty()) {
            printLine(indent, "// " + addition + " nullptr")
        }
    }

    private func printBlockOpt(node: Option<Block>, indent: UInt64, addition: String): Unit {
        if (let Some(value) <- node) {
            PrintAstNode(value, indent, addition)
        } else if (!addition.isEmpty()) {
            printLine(indent, "// " + addition + " nullptr")
        }
    }

    private func printTypeOpt(node: Option<Type>, indent: UInt64, addition: String): Unit {
        if (let Some(value) <- node) {
            PrintAstNode(value, indent, addition)
        } else if (!addition.isEmpty()) {
            printLine(indent, "// " + addition + " nullptr")
        }
    }

    private func printPatternOpt(node: Option<Pattern>, indent: UInt64, addition: String): Unit {
        if (let Some(value) <- node) {
            PrintAstNode(value, indent, addition)
        } else if (!addition.isEmpty()) {
            printLine(indent, "// " + addition + " nullptr")
        }
    }

    private func printFuncBodyOpt(node: Option<FuncBody>, indent: UInt64, addition: String): Unit {
        if (let Some(value) <- node) {
            PrintAstNode(value, indent, addition)
        } else if (!addition.isEmpty()) {
            printLine(indent, "// " + addition + " nullptr")
        }
    }

    private func printLambdaOpt(node: Option<LambdaExpr>, indent: UInt64, addition: String): Unit {
        if (let Some(value) <- node) {
            PrintAstNode(value, indent, addition)
        } else if (!addition.isEmpty()) {
            printLine(indent, "// " + addition + " nullptr")
        }
    }

    private func printBasic(node: Node, indent: UInt64): Unit {
        let filePath = if (let Some(file) <- node.curFile) {
            file.filePath
        } else {
            "not in file"
        }
        printLine(indent, "curFile: " + filePath)
        printLine(indent, "position: " + node.begin.ToString() + " " + node.end.ToString())
        if (!node.scopeName.isEmpty()) {
            printLine(indent, "scopeName: " + quoteText(node.scopeName))
        }
        if (node.TyKind() != TypeKind.TYPE_INITIAL) {
            printLine(indent, "ty: " + node.GetTy().getOrThrow().String())
        }
        // GAP_TODO(ptr-print-parity): 值域为 objectId 代理非进程地址，因 Cangjie 无原始对象地址。
        printLine(indent, "ptr: " + nodePtrText(node))
        let fullPackageName = node.GetFullPackageName()
        if (!fullPackageName.isEmpty() && fullPackageName != "default") {
            printLine(indent, "fullPackageName: " + fullPackageName)
        }
        printLine(indent, "attributes: " + node.GetAttrs().ToString())
        if (!node.exportId.isEmpty()) {
            printLine(indent, "exportId: " + quoteText(node.exportId))
        }
        if (let Some(decl) <- (node as Decl)) {
            if (decl.linkage != Linkage.EXTERNAL) {
                printLine(indent, "linkage: " + linkageName(decl.linkage))
            }
            if (decl.IsConst()) {
                printLine(indent, "isConst: true")
            }
            if (!decl.mangledName.isEmpty()) {
                printLine(indent, "mangledName: " + quoteText(decl.mangledName))
            }
            if (let Some(array) <- decl.annotationsArray) {
                PrintAstNode(array, indent, "annotationsArray")
            }
            if (let Some(outer) <- decl.outerDecl) {
                printTarget(indent, outer, "outerDecl")
            }
        } else if (let Some(typeNode) <- (node as Type)) {
            if (let Some(aliasTy) <- typeNode.aliasTy) {
                if (aliasTy.kind != TypeKind.TYPE_INITIAL) {
                    printLine(indent, "aliasTy: " + aliasTy.String())
                }
            }
        }
        if (!node.comments.IsEmpty()) {
            printLine(indent, "comments: " + node.comments.ToString())
        }
    }

    private func printTarget(indent: UInt64, target: Decl, addition: String): Unit {
        if (target.mangledName.isEmpty()) {
            // GAP_TODO(ptr-print-parity): 值域为 objectId 代理非进程地址，因 Cangjie 无原始对象地址。
            printLine(indent, addition + " ptr: " + nodePtrText(target))
        } else {
            printLine(indent, addition + " mangledName: " + quoteText(target.mangledName))
        }
    }

    private func printTargets(indent: UInt64, values: ArrayList<Decl>): Unit {
        printLine(indent, "targets [")
        for (target in values) {
            printTarget(indent + 1u64, target, "target")
        }
        printLine(indent, "]")
    }

    private func printModifiers(decl: Decl, indent: UInt64): Unit {
        if (decl.modifiers.isEmpty()) {
            return
        }
        let parts = ArrayList<String>()
        for (modifier in decl.modifiers) {
            let text = modifier.ToString()
            if (!text.isEmpty()) {
                parts.add(text)
            }
        }
        if (!parts.isEmpty()) {
            printLine(indent + 1u64, "Modifiers: " + JoinStrings(parts, " "))
        }
    }

    private func printAnnotations(decl: Decl, indent: UInt64): Unit {
        printLine(indent, "annotations [")
        for (annotation in decl.annotations) {
            printAnnotation(annotation, indent + 1u64)
        }
        printLine(indent, "]")
    }

    private func printGeneric(generic: Generic, indent: UInt64): Unit {
        printLine(indent, "typeParameters {")
        for (param in generic.typeParameters) {
            PrintAstNode(param, indent + 1u64, "")
        }
        printLine(indent, "}")
        printLine(indent, "genericConstraints {")
        for (constraint in generic.genericConstraints) {
            PrintAstNode(constraint, indent + 1u64, "")
        }
        printLine(indent, "}")
    }

    private func printMacroInvocation(invocation: MacroInvocation, indent: UInt64): Unit {
        if (invocation.attrs.isEmpty()) {
            printLine(indent + 1u64, "// no attributes")
        } else {
            printLine(indent + 1u64, "attrs {")
            printTokens(indent + 2u64, invocation.attrs)
            printLine(indent + 1u64, "}")
        }
        if (invocation.args.isEmpty()) {
            printLine(indent + 1u64, "// no arguments")
        } else {
            printLine(indent + 1u64, "args {")
            printTokens(indent + 2u64, invocation.args)
            printLine(indent + 1u64, "}")
        }
        if (let Some(decl) <- invocation.decl) {
            PrintAstNode(decl, indent + 1u64, "decl")
        }
    }

    private func printTokens(indent: UInt64, tokens: ArrayList<Token>): Unit {
        if (tokens.isEmpty()) {
            return
        }
        printLine(indent, "pos:  " + tokens[0].Begin().ToString() + " " + tokens[tokens.size - 1].End().ToString())
        var text = ""
        for (token in tokens) {
            if (token.kind == TokenKind.NL) {
                text += ";"
            } else {
                text += token.Value()
            }
        }
        printLine(indent, quoteText(text))
    }

    private func printPackage(pkg: Package, indent: UInt64): Unit {
        open(indent, "Package: " + pkg.fullPackageName)
        printLine(indent + 1u64, "noSubPkg: " + streamBoolText(pkg.noSubPkg))
        for (file in pkg.files) {
            PrintAstNode(file, indent + 1u64, "")
        }
        printLine(indent + 1u64, "genericInstantiatedDecls {")
        for (decl in pkg.genericInstantiatedDecls) {
            PrintAstNode(decl, indent + 2u64, "")
        }
        printLine(indent + 1u64, "}")
        printLine(indent + 1u64, "srcImportedNonGenericDecls {")
        for (decl in pkg.srcImportedNonGenericDecls) {
            PrintAstNode(decl, indent + 2u64, "")
        }
        printLine(indent + 1u64, "}")
        printLine(indent + 1u64, "inlineFuncDecls {")
        for (decl in pkg.inlineFuncDecls) {
            PrintAstNode(decl, indent + 2u64, "")
        }
        printLine(indent + 1u64, "}")
        close(indent)
    }

    private func printFile(file: File, indent: UInt64): Unit {
        open(indent, "File: " + file.fileName)
        printBasic(file, indent + 1u64)
        if (let Some(feature) <- file.feature) {
            PrintAstNode(feature, indent + 1u64, "features")
        } else {
            printLine(indent + 1u64, "// features nullptr")
        }
        if (let Some(packageSpec) <- file.packageSpec) {
            PrintAstNode(packageSpec, indent + 1u64, "package")
        } else {
            printLine(indent + 1u64, "// package nullptr")
        }
        for (importSpec in file.imports) {
            PrintAstNode(importSpec, indent + 1u64, "")
        }
        for (decl in file.decls) {
            if (decl.identifier == "main.invoke") {
                continue
            }
            PrintAstNode(decl, indent + 1u64, "")
        }
        for (decl in file.exportedInternalDecls) {
            PrintAstNode(decl, indent + 1u64, "exportedInternalDecls")
        }
        printLine(indent + 1u64, "originalMacroCallNodes [")
        for (macroNode in file.originalMacroCallNodes) {
            PrintAstNode(macroNode, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printGenericParamDecl(gpd: GenericParamDecl, indent: UInt64): Unit {
        open(indent, "GenericParamDecl: " + gpd.identifier.Val())
        printBasic(gpd, indent + 1u64)
        close(indent)
    }

    private func printFuncParam(param: FuncParam, indent: UInt64): Unit {
        open(indent, "FuncParam: " + param.identifier.Val())
        printBasic(param, indent + 1u64)
        printAnnotations(param, indent + 1u64)
        printTypeOpt(param.typeNode, indent + 1u64, "type")
        printExprOpt(param.assignment, indent + 1u64, "assignment")
        printLine(indent + 1u64, "isMemberParam: " + streamBoolText(param.isMemberParam))
        if (let Some(desugarDecl) <- param.desugarDecl) {
            PrintAstNode(desugarDecl, indent + 1u64, "desugarDecl")
        }
        close(indent)
    }

    private func printFuncParamList(paramList: FuncParamList, indent: UInt64): Unit {
        open(indent, "FuncParamList")
        if (paramList.params.isEmpty()) {
            printLine(indent + 1u64, "// no Params")
        } else {
            for (param in paramList.params) {
                PrintAstNode(param, indent + 1u64, "")
            }
        }
        close(indent)
    }

    private func printMacroDecl(macroDecl: MacroDecl, indent: UInt64): Unit {
        open(indent, "MacroDecl: " + macroDecl.identifier.Val())
        printBasic(macroDecl, indent + 1u64)
        printModifiers(macroDecl, indent)
        if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
            printLine(indent + 1u64, "// desugar decl")
            PrintAstNode(desugarDecl, indent + 1u64, "")
        } else {
            printLine(indent + 1u64, "// macro body")
            printFuncBodyOpt(macroDecl.funcBody, indent + 1u64, "")
        }
        close(indent)
    }

    private func printFuncDecl(funcDecl: FuncDecl, indent: UInt64): Unit {
        open(indent, "FuncDecl: " + funcDecl.identifier.Val() + " " + funcDecl.identifier.Begin().ToString() + " " + funcDecl.identifier.End().ToString())
        printBasic(funcDecl, indent + 1u64)
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            match (funcDecl.constructorCall) {
                case ConstructorCall.SUPER => if (let Some(callExpr) <-
                    (funcDecl.funcBody.getOrThrow().body.getOrThrow().body[0] as CallExpr)) {
                    if (callExpr.TestAttr(Attribute.COMPILER_ADD)) {
                        printLine(indent + 1u64, "super: implicitSuper")
                    } else {
                        printLine(indent + 1u64, "super: explicitSuper")
                    }
                }
                case _ => ()
            }
        }
        printAnnotations(funcDecl, indent + 1u64)
        printModifiers(funcDecl, indent)
        printFuncBodyOpt(funcDecl.funcBody, indent + 1u64, "")
        close(indent)
    }

    private func printPrimaryCtorDecl(primaryCtor: PrimaryCtorDecl, indent: UInt64): Unit {
        open(indent, "PrimaryCtorDecl: " + primaryCtor.identifier.Val())
        printBasic(primaryCtor, indent + 1u64)
        printAnnotations(primaryCtor, indent + 1u64)
        printModifiers(primaryCtor, indent)
        printFuncBodyOpt(primaryCtor.funcBody, indent + 1u64, "")
        close(indent)
    }

    private func printMainDecl(mainDecl: MainDecl, indent: UInt64): Unit {
        open(indent, "MainDecl: " + mainDecl.identifier.Val())
        printBasic(mainDecl, indent + 1u64)
        if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
            PrintAstNode(desugarDecl, indent + 1u64, "desugarDecl")
        } else {
            printFuncBodyOpt(mainDecl.funcBody, indent + 1u64, "funcBody")
        }
        close(indent)
    }

    private func printFuncBody(body: FuncBody, indent: UInt64): Unit {
        open(indent, "FuncBody")
        printBasic(body, indent + 1u64)
        if (let Some(generic) <- body.generic) {
            printGeneric(generic, indent + 1u64)
        }
        for (paramList in body.paramLists) {
            PrintAstNode(paramList, indent + 1u64, "")
        }
        if (let Some(retType) <- body.retType) {
            printLine(indent + 1u64, "// return type")
            PrintAstNode(retType, indent + 1u64, "")
        } else {
            printLine(indent + 1u64, "// no return type")
        }
        printBlockOpt(body.body, indent + 1u64, "body")
        close(indent)
    }

    private func printPropDecl(propDecl: PropDecl, indent: UInt64): Unit {
        open(indent, "PropDecl: " + propDecl.identifier.Val())
        printBasic(propDecl, indent + 1u64)
        printModifiers(propDecl, indent)
        printTypeOpt(propDecl.typeNode, indent + 1u64, "type")
        for (setter in propDecl.setters) {
            PrintAstNode(setter, indent + 1u64, "")
        }
        for (getter in propDecl.getters) {
            PrintAstNode(getter, indent + 1u64, "")
        }
        close(indent)
    }

    private func printMacroExpandDecl(macroExpand: MacroExpandDecl, indent: UInt64): Unit {
        open(indent, "MacroExpand: " + macroExpand.invocation.macroCallDiagInfo.fullName)
        printBasic(macroExpand, indent + 1u64)
        printMacroInvocation(macroExpand.invocation, indent)
        close(indent)
    }

    private func printMacroExpandParam(macroExpand: MacroExpandParam, indent: UInt64): Unit {
        open(indent, "MacroExpandParam: " + macroExpand.invocation.macroCallDiagInfo.fullName)
        printBasic(macroExpand, indent + 1u64)
        printMacroInvocation(macroExpand.invocation, indent)
        close(indent)
    }

    private func printVarWithPatternDecl(varWithPatternDecl: VarWithPatternDecl, indent: UInt64): Unit {
        open(indent, "VarWithPatternDecl")
        printBasic(varWithPatternDecl, indent + 1u64)
        printLine(indent + 1u64, if (varWithPatternDecl.isConst) { "Const" } else if (varWithPatternDecl.isVar) { "Var" } else { "Let" })
        printPatternOpt(varWithPatternDecl.irrefutablePattern, indent + 1u64, "")
        printTypeOpt(varWithPatternDecl.typeNode, indent + 1u64, "type")
        printExprOpt(varWithPatternDecl.initializer, indent + 1u64, "initializer")
        close(indent)
    }

    private func printVarDecl(varDecl: VarDecl, indent: UInt64): Unit {
        let key = if (varDecl.isConst) { "const " } else if (varDecl.isVar) { "var " } else { "let " }
        open(indent, "VarDecl: " + key + varDecl.identifier.Val())
        printBasic(varDecl, indent + 1u64)
        printAnnotations(varDecl, indent + 1u64)
        printModifiers(varDecl, indent)
        printTypeOpt(varDecl.typeNode, indent + 1u64, "type")
        printExprOpt(varDecl.initializer, indent + 1u64, "initializer")
        printLine(indent + 1u64, "parentPattern: " + nodePtrText(varDecl.parentPattern))
        close(indent)
    }

    private func printTypeAliasDecl(alias: TypeAliasDecl, indent: UInt64): Unit {
        open(indent, "TypeAliasDecl: " + alias.identifier.Val())
        printBasic(alias, indent + 1u64)
        if (let Some(generic) <- alias.generic) {
            printGeneric(generic, indent + 1u64)
        }
        printTypeOpt(alias.typeNode, indent + 1u64, "type")
        close(indent)
    }

    private func printClassDecl(classDecl: ClassDecl, indent: UInt64): Unit {
        if (let Some(attr) <- HasJavaAttr(classDecl)) {
            let argStr = if (attr == Attribute.JAVA_APP) { "app" } else { "ext" }
            printLine(indent, "@Java[\"" + argStr + "\"]")
        }
        open(indent, "ClassDecl: " + classDecl.identifier.Val())
        printBasic(classDecl, indent + 1u64)
        printAnnotations(classDecl, indent + 1u64)
        printModifiers(classDecl, indent)
        if (let Some(generic) <- classDecl.generic) {
            printGeneric(generic, indent + 1u64)
        }
        printInheritedTypes(classDecl.inheritedTypes, indent + 1u64)
        if (let Some(body) <- classDecl.body) {
            PrintAstNode(body, indent + 1u64, "")
        }
        close(indent)
    }

    private func printInterfaceDecl(interfaceDecl: InterfaceDecl, indent: UInt64): Unit {
        if (let Some(attr) <- HasJavaAttr(interfaceDecl)) {
            let argStr = if (attr == Attribute.JAVA_APP) { "app" } else { "ext" }
            printLine(indent, "@Java[\" " + argStr + " \"]")
        }
        open(indent, "InterfaceDecl: " + interfaceDecl.identifier.Val())
        printBasic(interfaceDecl, indent + 1u64)
        printModifiers(interfaceDecl, indent)
        if (let Some(generic) <- interfaceDecl.generic) {
            printGeneric(generic, indent + 1u64)
        }
        printInheritedTypes(interfaceDecl.inheritedTypes, indent + 1u64)
        if (let Some(body) <- interfaceDecl.body) {
            PrintAstNode(body, indent + 1u64, "")
        }
        close(indent)
    }

    private func printEnumDecl(enumDecl: EnumDecl, indent: UInt64): Unit {
        open(indent, "EnumDecl: " + enumDecl.identifier.Val())
        printBasic(enumDecl, indent + 1u64)
        printModifiers(enumDecl, indent)
        printLine(indent + 1u64, "hasEllipsis: " + boolText(enumDecl.hasEllipsis))
        if (let Some(generic) <- enumDecl.generic) {
            printGeneric(generic, indent + 1u64)
        }
        printInheritedTypes(enumDecl.inheritedTypes, indent + 1u64)
        printLine(indent + 1u64, "constructors [")
        for (constructor in enumDecl.constructors) {
            PrintAstNode(constructor, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        printLine(indent + 1u64, "members [")
        for (member in enumDecl.members) {
            PrintAstNode(member, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printStructDecl(decl: StructDecl, indent: UInt64): Unit {
        if (decl.TestAttr(Attribute.C)) {
            printLine(indent, "@C")
        }
        open(indent, "StructDecl: " + decl.identifier.Val())
        printBasic(decl, indent + 1u64)
        printAnnotations(decl, indent + 1u64)
        printModifiers(decl, indent)
        if (let Some(generic) <- decl.generic) {
            printGeneric(generic, indent + 1u64)
        }
        printInheritedTypes(decl.inheritedTypes, indent + 1u64)
        printLine(indent + 1u64, "StructBody {")
        if (let Some(body) <- decl.body) {
            PrintAstNode(body, indent + 2u64, "")
        }
        printLine(indent + 1u64, "}")
        close(indent)
    }

    private func printExtendDecl(ed: ExtendDecl, indent: UInt64): Unit {
        open(indent, "ExtendDecl")
        printBasic(ed, indent + 1u64)
        printTypeOpt(ed.extendedType, indent + 1u64, "extendedType")
        printLine(indent + 1u64, "inheritedTypes [")
        for (interfaceType in ed.inheritedTypes) {
            PrintAstNode(interfaceType, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        if (let Some(generic) <- ed.generic) {
            printGeneric(generic, indent + 1u64)
        }
        printLine(indent + 1u64, "extendMembers [")
        for (member in ed.members) {
            PrintAstNode(member, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printInheritedTypes(values: ArrayList<Type>, indent: UInt64): Unit {
        if (values.isEmpty()) {
            return
        }
        printLine(indent, "inheritedTypes [")
        for (typeNode in values) {
            PrintAstNode(typeNode, indent + 1u64, "")
        }
        printLine(indent, "]")
    }

    private func printBuiltInDecl(decl: BuiltInDecl, indent: UInt64): Unit {
        open(indent, "BuiltInDecl: " + decl.ToString())
        printBasic(decl, indent + 1u64)
        close(indent)
    }

    private func printInvalidDecl(decl: InvalidDecl, indent: UInt64): Unit {
        open(indent, "InvalidDecl: Need to be fixed!")
        printBasic(decl, indent + 1u64)
        close(indent)
    }

    private func printIfExpr(expr: IfExpr, indent: UInt64): Unit {
        open(indent, "IfExpr")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.condExpr, indent + 1u64, "condExpr")
        printBlockOpt(expr.thenBody, indent + 1u64, "thenBody")
        if (expr.hasElse) {
            printExprOpt(expr.elseBody, indent + 1u64, "elseBody")
        }
        close(indent)
    }

    private func printMatchCase(mc: MatchCase, indent: UInt64): Unit {
        open(indent, "MatchCase:")
        printBasic(mc, indent + 1u64)
        printLine(indent + 1u64, "patterns {")
        for (pattern in mc.patterns) {
            PrintAstNode(pattern, indent + 2u64, "")
        }
        printLine(indent + 1u64, "}")
        printExprOpt(mc.patternGuard, indent + 1u64, "patternGuard")
        printLine(indent + 1u64, "exprOrDecls [")
        if (let Some(block) <- mc.exprOrDecls) {
            for (item in block.body) {
                PrintAstNode(item, indent + 2u64, "")
            }
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printMatchCaseOther(mc: MatchCaseOther, indent: UInt64): Unit {
        open(indent, "MatchCaseOther")
        printBasic(mc, indent + 1u64)
        printExprOpt(mc.matchExpr, indent + 1u64, "matchExpr")
        printBlockOpt(mc.exprOrDecls, indent + 1u64, "exprOrDecls")
        close(indent)
    }

    private func printMatchExpr(expr: MatchExpr, indent: UInt64): Unit {
        open(indent, "MatchExpr:")
        printBasic(expr, indent + 1u64)
        if (expr.matchMode) {
            printLine(indent + 1u64, "selector: {")
            printExprOpt(expr.selector, indent + 2u64, "")
            printLine(indent + 1u64, "}")
            printLine(indent + 1u64, "matchCases: [")
            for (matchCase in expr.matchCases) {
                printMatchCase(matchCase, indent + 2u64)
            }
            printLine(indent + 1u64, "]")
        } else {
            for (matchCaseOther in expr.matchCaseOthers) {
                printLine(indent + 1u64, "matchCases: {")
                printExprOpt(matchCaseOther.matchExpr, indent + 2u64, "")
                printLine(indent + 1u64, "}")
                printLine(indent + 1u64, "exprOrDecls: [")
                if (let Some(block) <- matchCaseOther.exprOrDecls) {
                    for (item in block.body) {
                        PrintAstNode(item, indent + 1u64, "")
                    }
                }
                printLine(indent + 1u64, "]")
            }
        }
        close(indent)
    }

    private func printTryExpr(expr: TryExpr, indent: UInt64): Unit {
        open(indent, "TryExpr")
        printBasic(expr, indent + 1u64)
        if (!expr.resourceSpec.isEmpty()) {
            printLine(indent + 1u64, "ResourceSpec {")
            for (resource in expr.resourceSpec) {
                PrintAstNode(resource, indent + 2u64, "")
            }
            printLine(indent + 1u64, "}")
        }
        printLine(indent + 1u64, "TryBlock {")
        printBlockOpt(expr.tryBlock, indent + 2u64, "")
        printLine(indent + 1u64, "}")
        var idx: Int64 = 0
        while (idx < expr.catchBlocks.size) {
            printLine(indent + 1u64, "Catch {")
            printLine(indent + 2u64, "CatchPattern {")
            if (idx < expr.catchPatterns.size) {
                PrintAstNode(expr.catchPatterns[idx], indent + 3u64, "")
            }
            printLine(indent + 2u64, "}")
            printLine(indent + 2u64, "CatchBlock {")
            PrintAstNode(expr.catchBlocks[idx], indent + 3u64, "")
            printLine(indent + 2u64, "}")
            printLine(indent + 1u64, "}")
            idx++
        }
        for (handler in expr.handlers) {
            printLine(indent + 1u64, "Handle {")
            printLine(indent + 2u64, "HandlePattern {")
            printLine(indent + 3u64, "CommandTypePattern:")
            printPatternOpt(handler.commandPattern, indent + 3u64, "")
            printLine(indent + 2u64, "}")
            printLine(indent + 2u64, "HandleBlock {")
            printBlockOpt(handler.block, indent + 3u64, "")
            printLine(indent + 2u64, "}")
            printLine(indent + 2u64, "DesugaredLambda {")
            printLambdaOpt(handler.desugaredLambda, indent + 3u64, "")
            printLine(indent + 2u64, "}")
            printLine(indent + 1u64, "}")
        }
        printLine(indent + 1u64, "FinallyBlock {")
        printBlockOpt(expr.finallyBlock, indent + 2u64, "")
        printLine(indent + 1u64, "}")
        if (!expr.handlers.isEmpty()) {
            printLine(indent + 1u64, "TryLambda {")
            printLambdaOpt(expr.tryLambda, indent + 2u64, "")
            printLine(indent + 1u64, "}")
            printLine(indent + 1u64, "FinallyLambda {")
            printLambdaOpt(expr.finallyLambda, indent + 2u64, "")
            printLine(indent + 1u64, "}")
        }
        close(indent)
    }

    private func printThrowExpr(expr: ThrowExpr, indent: UInt64): Unit {
        open(indent, "ThrowExpr")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.expr, indent + 1u64, "expr")
        close(indent)
    }

    private func printPerformExpr(expr: PerformExpr, indent: UInt64): Unit {
        open(indent, "PerformExpr")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.expr, indent + 1u64, "PerformExpr")
        close(indent)
    }

    private func printResumeExpr(expr: ResumeExpr, indent: UInt64): Unit {
        open(indent, "ResumeExpr")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.withExpr, indent + 1u64, "WithExpr")
        printExprOpt(expr.throwingExpr, indent + 1u64, "ThrowingExpr")
        close(indent)
    }

    private func printReturnExpr(expr: ReturnExpr, indent: UInt64): Unit {
        open(indent, "ReturnExpr")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.expr, indent + 1u64, "expr")
        close(indent)
    }

    private func printJumpExpr(expr: JumpExpr, indent: UInt64): Unit {
        printLine(indent, "JumpExpr: " + if (expr.isBreak) { "Break" } else { "Continue" })
        printBasic(expr, indent + 1u64)
    }

    private func printForInExpr(expr: ForInExpr, indent: UInt64): Unit {
        open(indent, "ForInExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "pattern :")
        printPatternOpt(expr.pattern, indent + 2u64, "")
        printLine(indent + 1u64, "inExpression :")
        printExprOpt(expr.inExpression, indent + 2u64, "")
        printLine(indent + 1u64, "patternGuard :")
        printExprOpt(expr.patternGuard, indent + 2u64, "")
        printBlockOpt(expr.body, indent + 1u64, "body")
        close(indent)
    }

    private func printWhileExpr(expr: WhileExpr, indent: UInt64): Unit {
        open(indent, "WhileExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "condExpr {")
        printExprOpt(expr.condExpr, indent + 2u64, "condition expr")
        printLine(indent + 1u64, "}")
        printBlockOpt(expr.body, indent + 1u64, "While-Body")
        close(indent)
    }

    private func printDoWhileExpr(expr: DoWhileExpr, indent: UInt64): Unit {
        open(indent, "DoWhileExpr")
        printBasic(expr, indent + 1u64)
        printBlockOpt(expr.body, indent + 1u64, "DoWhile-Body")
        printLine(indent + 1u64, "condExpr {")
        printExprOpt(expr.condExpr, indent + 2u64, "")
        printLine(indent + 1u64, "}")
        close(indent)
    }

    private func printAssignExpr(expr: AssignExpr, indent: UInt64): Unit {
        open(indent, "AssignExpr")
        printBasic(expr, indent + 1u64)
        let opText = assignOpText(expr.op)
        printLine(indent + 1u64, opText)
        printExprOpt(expr.leftValue, indent + 1u64, "leftValue")
        printExprOpt(expr.rightExpr, indent + 1u64, "rightExpr")
        printOverflow(expr, indent + 1u64)
        close(indent)
    }

    private func printIncOrDecExpr(expr: IncOrDecExpr, indent: UInt64): Unit {
        open(indent, "IncOrDecExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, if (expr.op == TokenKind.INCR) { "++" } else { "--" })
        printExprOpt(expr.expr, indent + 1u64, "")
        printOverflow(expr, indent + 1u64)
        close(indent)
    }

    private func printUnaryExpr(expr: UnaryExpr, indent: UInt64): Unit {
        printLine(indent, "UnaryExpr { " + TokenKindText(expr.op))
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.expr, indent + 1u64, "")
        printOverflow(expr, indent + 1u64)
        close(indent)
    }

    private func printBinaryExpr(expr: BinaryExpr, indent: UInt64): Unit {
        printLine(indent, "BinaryExpr  " + TokenKindText(expr.op) + " {")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.leftExpr, indent + 1u64, "leftExpr:")
        printExprOpt(expr.rightExpr, indent + 1u64, "rightExpr:")
        printOverflow(expr, indent + 1u64)
        close(indent)
    }

    private func printOverflow(expr: Expr, indent: UInt64): Unit {
        if (expr.overflowStrategy != OverflowStrategy.NA) {
            printLine(indent, "overflowStrategy: " + OverflowStrategyName(expr.overflowStrategy))
        }
    }

    private func printRangeExpr(expr: RangeExpr, indent: UInt64): Unit {
        open(indent, "RangeExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "Start:")
        printExprOpt(expr.startExpr, indent + 2u64, "")
        printLine(indent + 1u64, "Stop:")
        printExprOpt(expr.stopExpr, indent + 2u64, "")
        printLine(indent + 1u64, "Step:")
        printExprOpt(expr.stepExpr, indent + 2u64, "")
        close(indent)
    }

    private func printSubscriptExpr(expr: SubscriptExpr, indent: UInt64): Unit {
        open(indent, "SubscriptExpr")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.baseExpr, indent + 1u64, "baseExpr")
        printLine(indent + 1u64, "indexExprs [")
        for (indexExpr in expr.indexExprs) {
            PrintAstNode(indexExpr, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printMemberAccess(expr: MemberAccess, indent: UInt64): Unit {
        open(indent, "MemberAccess")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.baseExpr, indent + 1u64, "baseExpr")
        printLine(indent + 1u64, "field: " + expr.field.Val())
        printTypeArguments(expr.typeArguments, indent + 1u64)
        if (let Some(target) <- expr.target) {
            printTarget(indent + 1u64, target, "target")
        }
        printTargets(indent + 1u64, expr.targets)
        close(indent)
    }

    private func printFuncArg(expr: FuncArg, indent: UInt64): Unit {
        open(indent, "FuncArg")
        printBasic(expr, indent + 1u64)
        if (!expr.name.Empty()) {
            printLine(indent + 1u64, "ArgName: " + expr.name.Val())
        }
        if (expr.withInout) {
            printLine(indent + 1u64, "inout")
        }
        printExprOpt(expr.expr, indent + 1u64, "")
        close(indent)
    }

    private func printCallExpr(expr: CallExpr, indent: UInt64): Unit {
        open(indent, "CallExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "BaseFunc {")
        printExprOpt(expr.baseFunc, indent + 2u64, "")
        printLine(indent + 1u64, "}")
        if (expr.args.isEmpty()) {
            printLine(indent + 1u64, "// no arguments")
        } else {
            printLine(indent + 1u64, "arguments [")
            for (arg in expr.args) {
                PrintAstNode(arg, indent + 2u64, "")
            }
            printLine(indent + 1u64, "]")
        }
        if (let Some(resolved) <- expr.resolvedFunction) {
            printTarget(indent + 1u64, resolved, "resolvedFunction")
        }
        close(indent)
    }

    private func printParenExpr(expr: ParenExpr, indent: UInt64): Unit {
        open(indent, "ParenExpr")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.expr, indent + 1u64, "")
        close(indent)
    }

    private func printLambdaExpr(expr: LambdaExpr, indent: UInt64): Unit {
        open(indent, "LambdaExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "mangledName: " + expr.mangledName)
        printFuncBodyOpt(expr.funcBody, indent + 1u64, "LambdaExpr-Body")
        close(indent)
    }

    private func printLitConstExpr(expr: LitConstExpr, indent: UInt64): Unit {
        open(indent, "LitConstExpr: " + expr.LitKindToString() + " " + quoteText(StringConvertor.Recover(expr.stringValue)))
        printBasic(expr, indent + 1u64)
        if (let Some(siExpr) <- expr.siExpr) {
            PrintAstNode(siExpr, indent + 1u64, "siExpr")
        }
        close(indent)
    }

    private func printInterpolationExpr(expr: InterpolationExpr, indent: UInt64): Unit {
        open(indent, "InterpolationExpr: " + quoteText(expr.rawString))
        printBasic(expr, indent + 1u64)
        printBlockOpt(expr.block, indent + 1u64, "block")
        close(indent)
    }

    private func printStrInterpolationExpr(expr: StrInterpolationExpr, indent: UInt64): Unit {
        open(indent, "StrInterpolationExpr: " + quoteText(expr.rawString))
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "strPartExprs [")
        for (partExpr in expr.strPartExprs) {
            PrintAstNode(partExpr, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printArrayLit(expr: ArrayLit, indent: UInt64): Unit {
        open(indent, "ArrayLiteral")
        printBasic(expr, indent + 1u64)
        if (expr.children.isEmpty()) {
            printLine(indent + 1u64, "// no members")
        }
        printLine(indent + 1u64, "children [")
        for (child in expr.children) {
            PrintAstNode(child, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printArrayExpr(expr: ArrayExpr, indent: UInt64): Unit {
        open(indent, if (expr.isValueArray) { "VArrayExpr" } else { "ArrayExpr" })
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "args [")
        for (arg in expr.args) {
            PrintAstNode(arg, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printPointerExpr(expr: PointerExpr, indent: UInt64): Unit {
        open(indent, "PointerExpr")
        printBasic(expr, indent + 1u64)
        printTypeOpt(expr.typeNode, indent + 1u64, "type")
        if (let Some(arg) <- expr.arg) {
            PrintAstNode(arg, indent + 1u64, "arg")
        }
        close(indent)
    }

    private func printTupleLit(expr: TupleLit, indent: UInt64): Unit {
        open(indent, "TupleLiteral")
        printBasic(expr, indent + 1u64)
        for (child in expr.children) {
            PrintAstNode(child, indent + 1u64, "")
        }
        close(indent)
    }

    private func printTypeConvExpr(expr: TypeConvExpr, indent: UInt64): Unit {
        open(indent, "TypeConvExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "// Convert Type:")
        printTypeOpt(expr.typeNode, indent + 2u64, "")
        printLine(indent + 1u64, "// Expr:")
        printExprOpt(expr.expr, indent + 2u64, "")
        close(indent)
    }

    private func printRefExpr(expr: RefExpr, indent: UInt64): Unit {
        open(indent, "RefExpr: " + expr.ref.identifier.Val())
        printBasic(expr, indent + 1u64)
        printTypeArguments(expr.typeArguments, indent + 1u64)
        if (let Some(target) <- expr.ref.target) {
            printTarget(indent + 1u64, target, "target")
        }
        printTargets(indent + 1u64, expr.ref.targets)
        close(indent)
    }

    private func printOptionalExpr(expr: OptionalExpr, indent: UInt64): Unit {
        open(indent, "OptionalExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "BaseExpr:")
        printExprOpt(expr.baseExpr, indent + 1u64, "")
        close(indent)
    }

    private func printOptionalChainExpr(expr: OptionalChainExpr, indent: UInt64): Unit {
        open(indent, "OptionalChainExpr")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "Expr:")
        printExprOpt(expr.expr, indent + 1u64, "")
        close(indent)
    }

    private func printLetPatternDestructor(expr: LetPatternDestructor, indent: UInt64): Unit {
        open(indent, "LetPattern")
        printBasic(expr, indent + 1u64)
        printLine(indent + 1u64, "patterns [")
        for (pattern in expr.patterns) {
            open(indent + 2u64, "|")
            PrintAstNode(pattern, indent + 3u64, "")
            close(indent + 2u64)
        }
        printLine(indent + 1u64, "]")
        open(indent + 1u64, "Initializer:")
        printExprOpt(expr.initializer, indent + 2u64, "")
        close(indent + 1u64)
        close(indent)
    }

    private func printPrimitiveTypeExpr(expr: PrimitiveTypeExpr, indent: UInt64): Unit {
        printLine(indent, "PrimitiveTypeExpr: " + expr.GetTy().getOrThrow().String())
    }

    private func printSpawnExpr(expr: SpawnExpr, indent: UInt64): Unit {
        open(indent, "SpawnExpr")
        printBasic(expr, indent + 1u64)
        if (let Some(futureObj) <- expr.futureObj) {
            PrintAstNode(futureObj, indent + 1u64, "")
        }
        printExprOpt(expr.arg, indent + 1u64, "")
        printExprOpt(expr.task, indent + 1u64, "")
        close(indent)
    }

    private func printSynchronizedExpr(expr: SynchronizedExpr, indent: UInt64): Unit {
        open(indent, "SynchronizedExpr")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.mutex, indent + 2u64, "mutex")
        printBlockOpt(expr.body, indent + 2u64, "body")
        close(indent)
    }

    private func printIfAvailableExpr(expr: IfAvailableExpr, indent: UInt64): Unit {
        open(indent, "IfAvailableExpr")
        printBasic(expr, indent + 1u64)
        if (let Some(arg) <- expr.GetArg()) {
            PrintAstNode(arg, indent + 2u64, "arg")
        } else {
            printLine(indent + 2u64, "// arg nullptr")
        }
        printLambdaOpt(expr.GetLambda1(), indent + 2u64, "lambda1")
        printLambdaOpt(expr.GetLambda2(), indent + 2u64, "lamdba2")
        close(indent)
    }

    private func printInvalidExpr(_: InvalidExpr, indent: UInt64): Unit {
        printLine(indent, "InvalidExpr: Need to be fixed!")
    }

    private func printBlock(block: Block, indent: UInt64): Unit {
        open(indent, "Block:")
        printBasic(block, indent + 1u64)
        if (block.body.isEmpty()) {
            printLine(indent + 1u64, "// no block")
        } else {
            for (item in block.body) {
                PrintAstNode(item, indent + 1u64, "")
            }
        }
        close(indent)
    }

    private func printInterfaceBody(body: InterfaceBody, indent: UInt64): Unit {
        open(indent, "InterfaceBody")
        for (decl in body.decls) {
            PrintAstNode(decl, indent + 1u64, "")
        }
        close(indent)
    }

    private func printClassBody(body: ClassBody, indent: UInt64): Unit {
        open(indent, "ClassBody")
        for (decl in body.decls) {
            PrintAstNode(decl, indent + 1u64, "")
        }
        close(indent)
    }

    private func printStructBody(body: StructBody, indent: UInt64): Unit {
        for (decl in body.decls) {
            PrintAstNode(decl, indent, "")
        }
    }

    private func printIsExpr(expr: IsExpr, indent: UInt64): Unit {
        printLine(indent, "IsExpr :  {")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.leftExpr, indent + 1u64, "leftExpr")
        printTypeOpt(expr.isType, indent + 1u64, "isType")
        close(indent)
    }

    private func printAsExpr(expr: AsExpr, indent: UInt64): Unit {
        open(indent, "AsExpr:")
        printBasic(expr, indent + 1u64)
        printExprOpt(expr.leftExpr, indent + 1u64, "leftExpr")
        printTypeOpt(expr.asType, indent + 1u64, "asType")
        close(indent)
    }

    private func printTokenPart(tokenPart: TokenPart, indent: UInt64): Unit {
        printTokens(indent + 1u64, tokenPart.tokens)
    }

    private func printQuoteExpr(expr: QuoteExpr, indent: UInt64): Unit {
        open(indent, "QuoteExpr")
        for (item in expr.exprs) {
            printLine(indent + 1u64, if (item.astKind == ASTKind.TOKEN_PART) { "TokenPart (" } else { "DollarExpr (" })
            PrintAstNode(item, indent + 2u64, "")
            printLine(indent + 1u64, ")")
        }
        close(indent)
    }

    private func printMacroExpandExpr(expr: MacroExpandExpr, indent: UInt64): Unit {
        open(indent, "MacroExpand: " + expr.invocation.macroCallDiagInfo.fullName)
        printBasic(expr, indent + 1u64)
        printMacroInvocation(expr.invocation, indent)
        close(indent)
    }

    private func printRefType(typeNode: RefType, indent: UInt64): Unit {
        open(indent, "RefType: " + typeNode.ref.identifier.Val())
        printBasic(typeNode, indent + 1u64)
        printTypeArguments(typeNode.typeArguments, indent + 1u64)
        if (let Some(target) <- typeNode.ref.target) {
            printTarget(indent + 1u64, target, "target")
        }
        printTargets(indent + 1u64, typeNode.ref.targets)
        close(indent)
    }

    private func printTypeArguments(values: ArrayList<Type>, indent: UInt64): Unit {
        if (values.isEmpty()) {
            printLine(indent, "// no type arguments")
        } else {
            printLine(indent, "typeArguments [")
            for (typeArg in values) {
                PrintAstNode(typeArg, indent + 1u64, "")
            }
            printLine(indent, "]")
        }
    }

    private func printParenType(typeNode: ParenType, indent: UInt64): Unit {
        open(indent, "ParenType")
        printBasic(typeNode, indent + 1u64)
        printTypeOpt(typeNode.innerType, indent + 1u64, "")
        close(indent)
    }

    private func printFuncType(typeNode: FuncType, indent: UInt64): Unit {
        open(indent, "FuncType")
        printBasic(typeNode, indent + 1u64)
        printLine(indent + 1u64, "paramTypes [")
        for (paramType in typeNode.paramTypes) {
            PrintAstNode(paramType, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        printTypeOpt(typeNode.retType, indent + 1u64, "retType")
        printLine(indent + 1u64, "IsCFuncType: " + streamBoolText(typeNode.isC))
        close(indent)
    }

    private func printTupleType(typeNode: TupleType, indent: UInt64): Unit {
        open(indent, "TupleType")
        printBasic(typeNode, indent + 1u64)
        printLine(indent + 1u64, "fieldTypes [")
        for (fieldType in typeNode.fieldTypes) {
            PrintAstNode(fieldType, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printThisType(typeNode: ThisType, indent: UInt64): Unit {
        open(indent, "ThisType")
        printBasic(typeNode, indent + 1u64)
        close(indent)
    }

    private func printPrimitiveType(typeNode: PrimitiveType, indent: UInt64): Unit {
        open(indent, "PrimitiveType: " + typeNode.str)
        printBasic(typeNode, indent + 1u64)
        close(indent)
    }

    private func printOptionType(typeNode: OptionType, indent: UInt64): Unit {
        open(indent, "OptionType")
        printBasic(typeNode, indent + 1u64)
        printLine(indent + 1u64, "BaseType:")
        printTypeOpt(typeNode.componentType, indent + 2u64, "")
        printLine(indent + 1u64, "QuestNums: ${typeNode.questNum}")
        close(indent)
    }

    private func printVArrayType(typeNode: VArrayType, indent: UInt64): Unit {
        open(indent, "VArrayType")
        printBasic(typeNode, indent + 1u64)
        printLine(indent + 1u64, "typeArguments:")
        printTypeOpt(typeNode.typeArgument, indent + 2u64, "")
        close(indent)
    }

    private func printQualifiedType(typeNode: QualifiedType, indent: UInt64): Unit {
        open(indent, "QualifiedType")
        printBasic(typeNode, indent + 1u64)
        printTypeOpt(typeNode.baseType, indent + 1u64, "baseType")
        printLine(indent + 1u64, "field: " + typeNode.field.Val())
        if (let Some(target) <- typeNode.target) {
            printTarget(indent + 1u64, target, "target")
        }
        close(indent)
    }

    private func printGenericConstraint(generic: GenericConstraint, indent: UInt64): Unit {
        open(indent, "GenericConstraint")
        if (let Some(refType) <- generic.refType) {
            PrintAstNode(refType, indent + 1u64, "")
        }
        printLine(indent + 1u64, "upperBounds {")
        for (upperBound in generic.upperBounds) {
            PrintAstNode(upperBound, indent + 2u64, "")
        }
        printLine(indent + 1u64, "}")
        close(indent)
    }

    private func printGenericNode(generic: Generic, indent: UInt64): Unit {
        open(indent, "Generic")
        printBasic(generic, indent + 1u64)
        printGeneric(generic, indent + 1u64)
        close(indent)
    }

    private func printInvalidType(_: InvalidType, indent: UInt64): Unit {
        printLine(indent, "InvalidType: Need to be fixed!")
    }

    private func printConstPattern(pattern: ConstPattern, indent: UInt64): Unit {
        open(indent, "ConstPattern")
        printExprOpt(pattern.literal, indent + 1u64, "")
        close(indent)
    }

    private func printTuplePattern(pattern: TuplePattern, indent: UInt64): Unit {
        open(indent, "TuplePattern")
        printLine(indent + 1u64, "patterns [")
        for (subpattern in pattern.patterns) {
            PrintAstNode(subpattern, indent + 1u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printTypePattern(pattern: TypePattern, indent: UInt64): Unit {
        open(indent, "TypePattern")
        printBasic(pattern, indent + 1u64)
        printPatternOpt(pattern.pattern, indent + 1u64, "pattern")
        printTypeOpt(pattern.typeNode, indent + 1u64, "type")
        if (let Some(desugarVarPattern) <- pattern.desugarVarPattern) {
            PrintAstNode(desugarVarPattern, indent + 1u64, "// desugarVarPattern")
        }
        close(indent)
    }

    private func printVarPattern(pattern: VarPattern, indent: UInt64): Unit {
        let name = if (let Some(varDecl) <- pattern.varDecl) { varDecl.identifier.Val() } else { "" }
        open(indent, "VarPattern: " + name)
        printBasic(pattern, indent + 1u64)
        if (let Some(varDecl) <- pattern.varDecl) {
            PrintAstNode(varDecl, indent + 1u64, "varDecl")
        }
        close(indent)
    }

    private func printEnumPattern(pattern: EnumPattern, indent: UInt64): Unit {
        open(indent, "EnumPattern")
        printExprOpt(pattern.constructor, indent + 1u64, "")
        for (subpattern in pattern.patterns) {
            PrintAstNode(subpattern, indent + 1u64, "")
        }
        close(indent)
    }

    private func printExceptTypePattern(pattern: ExceptTypePattern, indent: UInt64): Unit {
        open(indent, "ExceptTypePattern")
        printPatternOpt(pattern.pattern, indent + 1u64, "")
        for (typeNode in pattern.types) {
            PrintAstNode(typeNode, indent + 1u64, "")
        }
        close(indent)
    }

    private func printVarOrEnumPattern(pattern: VarOrEnumPattern, indent: UInt64): Unit {
        open(indent, "VarOrEnumPattern")
        printLine(indent + 1u64, pattern.identifier.Val())
        if (let Some(subpattern) <- pattern.pattern) {
            open(indent + 1u64, "Subpatterns")
            PrintAstNode(subpattern, indent + 2u64, "")
            close(indent + 1u64)
        }
        close(indent)
    }

    private func printCommandTypePattern(pattern: CommandTypePattern, indent: UInt64): Unit {
        printPatternOpt(pattern.pattern, indent + 1u64, "")
        for (typeNode in pattern.types) {
            PrintAstNode(typeNode, indent + 1u64, "")
        }
    }

    private func printInvalidPattern(pattern: InvalidPattern, indent: UInt64): Unit {
        open(indent, "InvalidPattern: Need to be fixed!")
        printBasic(pattern, indent + 1u64)
        close(indent)
    }

    private func printFeatureId(featureId: FeatureId, indent: UInt64): Unit {
        printLine(indent, "FeatureId  " + featureId.ToString() + "  {")
        printBasic(featureId, indent + 1u64)
        close(indent)
    }

    private func printFeaturesSet(featuresSet: FeaturesSet, indent: UInt64): Unit {
        open(indent, "FeaturesSet")
        printBasic(featuresSet, indent + 1u64)
        printLine(indent + 1u64, "featureIds:  [")
        for (featureId in featuresSet.content) {
            PrintAstNode(featureId, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        close(indent)
    }

    private func printFeaturesDirective(featuresDirective: FeaturesDirective, indent: UInt64): Unit {
        open(indent, "FeaturesDirective: features")
        printBasic(featuresDirective, indent + 1u64)
        printLine(indent + 1u64, "annotations: [")
        for (annotation in featuresDirective.annotations) {
            printAnnotation(annotation, indent + 2u64)
        }
        printLine(indent + 1u64, "]")
        if (let Some(set) <- featuresDirective.featuresSet) {
            PrintAstNode(set, indent + 1u64, "")
        }
        close(indent)
    }

    private func printPackageSpec(packageSpec: PackageSpec, indent: UInt64): Unit {
        open(indent, "PackageSpec: " + packageSpec.packageName.Val())
        printLine(indent + 1u64, packageSpec.GetPackageName())
        if (!packageSpec.prefixPaths.isEmpty()) {
            printLine(indent + 1u64, "prefixPath: " + JoinStrings(packageSpec.prefixPaths, "."))
        }
        if (let Some(modifier) <- packageSpec.modifier) {
            printLine(indent + 1u64, "modifier: " + TokenKindText(modifier.modifier))
        }
        close(indent)
    }

    private func printImportSpec(importSpec: ImportSpec, indent: UInt64): Unit {
        if (importSpec.content.kind == ImportKind.IMPORT_MULTI) {
            for (item in importSpec.content.items) {
                open(indent, "ImportSpec: " + item.identifier.Val())
                if (item.kind == ImportKind.IMPORT_ALIAS) {
                    printLine(indent + 1u64, "aliasName: " + item.aliasName.Val())
                }
                printLine(indent + 1u64, "prefixPaths: " + item.GetPrefixPath())
                if (let Some(value) <- importSpec.modifier) {
                    printLine(indent + 1u64, "modifier: " + TokenKindText(value.modifier))
                }
                close(indent)
            }
            return
        }
        printImportContentWithModifier(importSpec.content, importSpec.modifier, indent)
    }

    private func printImportContent(content: ImportContent, indent: UInt64): Unit {
        printImportContentWithModifier(content, None, indent)
    }

    private func printImportContentWithModifier(content: ImportContent, modifier: Option<Modifier>, indent: UInt64): Unit {
        open(indent, "ImportSpec: " + content.identifier.Val())
        if (content.kind == ImportKind.IMPORT_ALIAS) {
            printLine(indent + 1u64, "aliasName: " + content.aliasName.Val())
        }
        if (!content.prefixPaths.isEmpty()) {
            printLine(indent + 1u64, "prefixPaths: " + content.GetPrefixPath())
        }
        if (let Some(value) <- modifier) {
            printLine(indent + 1u64, "modifier: " + TokenKindText(value.modifier))
        }
        printLine(indent + 1u64, "isDecl: " + streamBoolText(content.isDecl))
        close(indent)
    }

    private func printAnnotation(annotation: Annotation, indent: UInt64): Unit {
        open(indent, "Annotation: " + annotation.identifier.Val())
        printBasic(annotation, indent + 1u64)
        printLine(indent + 1u64, "isCompileTimeVisible: " + streamBoolText(annotation.isCompileTimeVisible))
        printLine(indent + 1u64, "args [")
        for (arg in annotation.args) {
            PrintAstNode(arg, indent + 2u64, "")
        }
        printLine(indent + 1u64, "]")
        printExprOpt(annotation.condExpr, indent + 1u64, "condExpr")
        printLine(indent + 1u64, "target: ${annotation.target}")
        printExprOpt(annotation.baseExpr, indent + 1u64, "baseExpr")
        close(indent)
    }

    private func printModifier(modifier: Modifier, indent: UInt64): Unit {
        open(indent, "Modifier: " + modifier.ToString())
        printBasic(modifier, indent + 1u64)
        close(indent)
    }

    private func printDefaultNode(node: Node, indent: UInt64): Unit {
        open(indent, "UnknowNode: " + ASTKindName(node.astKind))
        printBasic(node, indent + 1u64)
        close(indent)
    }

    private func assignOpText(kind: TokenKind): String {
        return match (kind) {
            case TokenKind.ASSIGN => "'='"
            case TokenKind.ADD_ASSIGN => "'+='"
            case TokenKind.SUB_ASSIGN => "'-='"
            case TokenKind.MUL_ASSIGN => "'*='"
            case TokenKind.EXP_ASSIGN => "'**='"
            case TokenKind.DIV_ASSIGN => "'/='"
            case TokenKind.MOD_ASSIGN => "'%%='"
            case TokenKind.AND_ASSIGN => "'&&='"
            case TokenKind.OR_ASSIGN => "'||='"
            case TokenKind.BITAND_ASSIGN => "'&='"
            case TokenKind.BITOR_ASSIGN => "'|='"
            case TokenKind.BITXOR_ASSIGN => "'^='"
            case TokenKind.LSHIFT_ASSIGN => "'<<='"
            case TokenKind.RSHIFT_ASSIGN => "'>>='"
            case _ => ""
        }
    }

    private func linkageName(linkage: Linkage): String {
        return match (linkage) {
            case Linkage.WEAK_ODR => "WEAK_ODR"
            case Linkage.EXTERNAL => "EXTERNAL"
            case Linkage.INTERNAL => "INTERNAL"
            case Linkage.LINKONCE_ODR => "LINKONCE_ODR"
            case Linkage.EXTERNAL_WEAK => "EXTERNAL_WEAK"
        }
    }

    private func quoteText(value: String): String {
        return "\"" + value + "\""
    }
}

private func appendIndent(builder: StringBuilder, depth: UInt64): Unit {
    for (_ in 0..depth) {
        builder.append("  ")
    }
}
