package cangjie_compiler::macro_pkg

import std.collection.*

public let INITIAL_FILE_SIZE: Int64 = 65536

private func EscapeNodeText(value: String): String {
    return value.replace("\\", "\\\\").replace(";", "\\s").replace(",", "\\m").replace("|", "\\p")
        .replace("=", "\\e").replace("(", "\\l").replace(")", "\\r").replace("{", "\\b").replace("}", "\\c")
}

private func appendU32LE(out: ArrayList<UInt8>, value: UInt32): Unit {
    out.add(UInt8(UInt64(value) & 0xff))
    out.add(UInt8((UInt64(value) >> 8) & 0xff))
    out.add(UInt8((UInt64(value) >> 16) & 0xff))
    out.add(UInt8((UInt64(value) >> 24) & 0xff))
}

public class NodeWriter {
    private var nodePtr: Option<Node> = None
    private let bufferData: ArrayList<UInt8> = ArrayList<UInt8>()

    public init(nodePtr: Node) {
        this.nodePtr = Some(nodePtr)
    }

    public func ExportNode(): ArrayList<UInt8> {
        bufferData.clear()
        if (let Some(node) <- nodePtr) {
            let payload = SerializeNode(node)
            let payloadBytes = payload.toArray()
            appendU32LE(bufferData, UInt32(payloadBytes.size + 4))
            for (byte in payloadBytes) {
                bufferData.add(byte)
            }
        }
        return bufferData
    }

    public func SerializeNode(node: Node): String {
        let builder = StringBuilder()
        builder.append("format=NodeFormatTextV1\n")
        appendNodeBase(builder, node)
        if (let Some(expr) <- (node as Expr)) {
            builder.append("expr=" + SerializeExprForNodeWriter(this, expr) + "\n")
        } else if (let Some(pattern) <- (node as Pattern)) {
            builder.append("pattern=" + SerializePattern(pattern) + "\n")
        } else if (let Some(decl) <- (node as Decl)) {
            builder.append("decl=" + SerializeDecl(decl) + "\n")
        } else if (let Some(file) <- (node as File)) {
            builder.append("file=" + SerializeFile(file) + "\n")
        } else if (let Some(anno) <- (node as Annotation)) {
            builder.append("annotation=" + SerializeAnnotation(anno) + "\n")
        }
        return builder.toString()
    }

    private func appendNodeBase(builder: StringBuilder, node: Node): Unit {
        builder.append("kind=" + ASTKindIndex(node.astKind).toString() + "\n")
        builder.append("begin=" + node.begin.ToString() + "\n")
        builder.append("end=" + node.end.ToString() + "\n")
    }

    public func SerializePosition(pos: Position): String {
        return pos.fileID.toString() + ":" + pos.line.toString() + ":" + pos.column.toString()
    }

    public func EscapeText(value: String): String {
        return EscapeNodeText(value)
    }

    public func SerializeToken(token: Token): String {
        return TokenKindIndex(token.kind).toString() + ":" + token.Value().replace("\\", "\\\\").replace(":", "\\c") +
            ":" + SerializePosition(token.Begin()) + ":" + SerializePosition(token.End())
    }

    public func SerializeTokenVector(tokens: ArrayList<Token>): String {
        let builder = StringBuilder()
        var idx: Int64 = 0
        while (idx < tokens.size) {
            if (idx > 0) {
                builder.append(",")
            }
            builder.append(SerializeToken(tokens[idx]))
            idx++
        }
        return builder.toString()
    }

    public func SerializeMacroInvocation(invocation: MacroInvocation): String {
        let builder = StringBuilder()
        builder.append("full=" + invocation.macroCallDiagInfo.fullName + ";")
        builder.append("id=" + invocation.macroCallDiagInfo.identifier + ";")
        builder.append("idpos=" + SerializePosition(invocation.macroCallDiagInfo.identifierPos) + ";")
        builder.append("attrs=" + SerializeTokenVector(invocation.attrs) + ";")
        builder.append("args=" + SerializeTokenVector(invocation.args) + ";")
        builder.append("hasParen=" + invocation.hasParenthesis.toString() + ";")
        builder.append("compileTime=" + invocation.isCompileTimeVisible.toString())
        return builder.toString()
    }

    public func SerializePattern(pattern: Pattern): String {
        if (let Some(_) <- (pattern as WildcardPattern)) {
            return "wildcardPattern()"
        }
        if (let Some(constPattern) <- (pattern as ConstPattern)) {
            return "constPattern(lit=" + SerializeExprOptionForNodeWriter(this, constPattern.literal) + ")"
        }
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            return "varPattern(" + EscapeNodeText(varPattern.identifier) + ";isVar=" +
                varPattern.isVar.toString() + ")"
        }
        if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            return "tuplePattern(" + SerializePatternVector(tuplePattern.patterns) + ")"
        }
        if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            return "enumPattern(" + EscapeNodeText(enumPattern.constructor) + ";types=" +
                SerializeTypeVector(enumPattern.typeArguments) + ";patterns=" +
                SerializePatternVector(enumPattern.patterns) + ")"
        }
        if (let Some(varOrEnumPattern) <- (pattern as VarOrEnumPattern)) {
            return "varOrEnumPattern(" + EscapeNodeText(varOrEnumPattern.identifier) + ";pattern=" +
                SerializePatternOption(varOrEnumPattern.pattern) + ")"
        }
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            return "typePattern(pattern=" + SerializePatternOption(typePattern.pattern) + ";type=" +
                SerializeTypeOptionForNodeWriter(this, typePattern.typeNode) + ")"
        }
        if (let Some(exceptTypePattern) <- (pattern as ExceptTypePattern)) {
            return SerializeExceptTypePattern(exceptTypePattern)
        }
        if (let Some(commandTypePattern) <- (pattern as CommandTypePattern)) {
            return SerializeCommandTypePattern(commandTypePattern)
        }
        return "pattern(" + ASTKindIndex(pattern.astKind).toString() + ")"
    }

    private func SerializePatternOption(pattern: Option<Pattern>): String {
        if (let Some(value) <- pattern) {
            return SerializePattern(value)
        }
        return "none"
    }

    private func SerializePatternVector(patterns: ArrayList<Pattern>): String {
        let builder = StringBuilder()
        builder.append("[")
        var patternIdx: Int64 = 0
        while (patternIdx < patterns.size) {
            if (patternIdx > 0) {
                builder.append(",")
            }
            builder.append(SerializePattern(patterns[patternIdx]))
            patternIdx++
        }
        builder.append("]")
        return builder.toString()
    }

    private func SerializeTypeVector(types: ArrayList<Type>): String {
        let builder = StringBuilder()
        builder.append("[")
        var typeIdx: Int64 = 0
        while (typeIdx < types.size) {
            if (typeIdx > 0) {
                builder.append(",")
            }
            builder.append(SerializeType(types[typeIdx]))
            typeIdx++
        }
        builder.append("]")
        return builder.toString()
    }

    private func SerializeExceptTypePattern(pattern: ExceptTypePattern): String {
        return "exceptTypePattern(pattern=" + SerializePatternOption(pattern.pattern) + ";types=" +
            SerializeTypeVector(pattern.types) + ")"
    }

    private func SerializeCommandTypePattern(pattern: CommandTypePattern): String {
        return "commandTypePattern(pattern=" + SerializePatternOption(pattern.pattern) + ";types=" +
            SerializeTypeVector(pattern.types) + ")"
    }

    public func SerializeType(ty: Type): String {
        if (let Some(primitive) <- (ty as PrimitiveType)) {
            let kindName = TypeKindName(primitive.kind)
            return "primitiveType(" + kindName + ")"
        }
        if (let Some(refType) <- (ty as RefType)) {
            return "refType(" + EscapeNodeText(refType.name) + ";args=" + SerializeTypeVector(refType.typeArguments) +
                ")"
        }
        if (let Some(qualifiedType) <- (ty as QualifiedType)) {
            return "qualifiedType(base=" + SerializeTypeOptionForNodeWriter(this, qualifiedType.baseType) +
                ";field=" + EscapeNodeText(qualifiedType.field) + ";args=" +
                SerializeTypeVector(qualifiedType.typeArguments) + ")"
        }
        if (let Some(optionType) <- (ty as OptionType)) {
            return "optionType(component=" + SerializeTypeOptionForNodeWriter(this, optionType.componentType) +
                ";questNum=" + optionType.questNum.toString() + ")"
        }
        if (let Some(constantType) <- (ty as ConstantType)) {
            return "constantType(expr=" + SerializeExprOptionForNodeWriter(this, constantType.constantExpr) + ")"
        }
        if (let Some(vArrayType) <- (ty as VArrayType)) {
            return "vArrayType(arg=" + SerializeTypeOptionForNodeWriter(this, vArrayType.typeArgument) + ";size=" +
                SerializeTypeOptionForNodeWriter(this, vArrayType.constantType) + ")"
        }
        if (let Some(parenType) <- (ty as ParenType)) {
            return "parenType(" + SerializeTypeOptionForNodeWriter(this, parenType.innerType) + ")"
        }
        if (let Some(tupleType) <- (ty as TupleType)) {
            return "tupleType(" + SerializeTypeVector(tupleType.fieldTypes) + ")"
        }
        if (let Some(funcType) <- (ty as FuncType)) {
            return "funcType(params=" + SerializeTypeVector(funcType.paramTypes) + ";ret=" +
                SerializeTypeOptionForNodeWriter(this, funcType.retType) + ";isC=" + funcType.isC.toString() + ")"
        }
        if (let Some(_) <- (ty as ThisType)) {
            return "thisType()"
        }
        return "type(" + ASTKindIndex(ty.astKind).toString() + "," + EscapeNodeText(ty.name) + ")"
    }

    public func SerializeAnnotation(annotation: Annotation): String {
        let builder = StringBuilder()
        builder.append(annotation.identifier.Val())
        if (!annotation.attrs.isEmpty()) {
            builder.append("[")
            var idx: Int64 = 0
            while (idx < annotation.attrs.size) {
                if (idx > 0) {
                    builder.append(",")
                }
                builder.append(annotation.attrs[idx])
                idx++
            }
            builder.append("]")
        }
        return builder.toString()
    }

    public func SerializeModifier(modifier: Modifier): String {
        return TokenKindText(modifier.modifier)
    }

    public func SerializeDecl(decl: Decl): String {
        if (let Some(macroDecl) <- (decl as MacroExpandDecl)) {
            return "macroExpandDecl(" + SerializeMacroInvocation(macroDecl.invocation) + ")"
        }
        if (let Some(macroFunc) <- (decl as MacroDecl)) {
            return "macro(" + EscapeNodeText(macroFunc.identifier) + "," + SerializeFuncBody(macroFunc.funcBody) + ")"
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            return "func(" + EscapeNodeText(funcDecl.identifier) + "," + SerializeFuncBody(funcDecl.funcBody) + ")"
        }
        if (let Some(patternVarDecl) <- (decl as VarWithPatternDecl)) {
            return SerializeVarWithPatternDecl(patternVarDecl)
        }
        if (let Some(varDecl) <- (decl as VarDecl)) {
            return SerializeVarDecl(varDecl)
        }
        if (let Some(param) <- (decl as FuncParam)) {
            return SerializeFuncParam(param)
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            return SerializeMemberContainer("class", classDecl.identifier, classDecl.members)
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            return SerializeMemberContainer("struct", structDecl.identifier, structDecl.members)
        }
        if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
            return SerializeMemberContainer("interface", interfaceDecl.identifier, interfaceDecl.members)
        }
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            return SerializeEnumDecl(enumDecl)
        }
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            return SerializeMemberContainer("extend", extendDecl.identifier, extendDecl.members)
        }
        return "decl(" + ASTKindIndex(decl.astKind).toString() + "," + EscapeNodeText(decl.identifier) + ")"
    }

    private func SerializeEnumDecl(enumDecl: EnumDecl): String {
        let builder = StringBuilder()
        builder.append("enum(" + EscapeNodeText(enumDecl.identifier) + ";hasArguments=" +
            enumDecl.hasArguments.toString() + ";constructors=[")
        var ctorIdx: Int64 = 0
        while (ctorIdx < enumDecl.constructors.size) {
            if (ctorIdx > 0) {
                builder.append(",")
            }
            builder.append(SerializeDecl(enumDecl.constructors[ctorIdx]))
            ctorIdx++
        }
        builder.append("];members=[")
        var memberIdx: Int64 = 0
        while (memberIdx < enumDecl.members.size) {
            if (memberIdx > 0) {
                builder.append(",")
            }
            builder.append(SerializeDecl(enumDecl.members[memberIdx]))
            memberIdx++
        }
        builder.append("])")
        return builder.toString()
    }

    private func SerializeMemberContainer(kindName: String, identifier: String, members: ArrayList<Decl>): String {
        let builder = StringBuilder()
        builder.append(kindName + "(" + EscapeNodeText(identifier) + ";members=[")
        var idx: Int64 = 0
        while (idx < members.size) {
            if (idx > 0) {
                builder.append(",")
            }
            builder.append(SerializeDecl(members[idx]))
            idx++
        }
        builder.append("])")
        return builder.toString()
    }

    private func SerializeVarDecl(varDecl: VarDecl): String {
        let builder = StringBuilder()
        builder.append("var(" + EscapeNodeText(varDecl.identifier))
        if (let Some(declType) <- varDecl.declType) {
            builder.append(";type=" + SerializeType(declType))
        } else {
            builder.append(";type=none")
        }
        if (!varDecl.constructorTypes.isEmpty()) {
            builder.append(";constructorTypes=[")
            var typeIdx: Int64 = 0
            while (typeIdx < varDecl.constructorTypes.size) {
                if (typeIdx > 0) {
                    builder.append(",")
                }
                builder.append(SerializeType(varDecl.constructorTypes[typeIdx]))
                typeIdx++
            }
            builder.append("]")
        }
        if (let Some(initializer) <- varDecl.initializer) {
            builder.append(";init=" + SerializeExprForNodeWriter(this, initializer))
        } else {
            builder.append(";init=none")
        }
        builder.append(")")
        return builder.toString()
    }

    private func SerializeVarWithPatternDecl(patternVarDecl: VarWithPatternDecl): String {
        let builder = StringBuilder()
        builder.append("varPattern(" + EscapeNodeText(patternVarDecl.identifier))
        builder.append(";isVar=" + patternVarDecl.isVar.toString())
        if (let Some(pattern) <- patternVarDecl.irrefutablePattern) {
            builder.append(";pattern=" + SerializePattern(pattern))
        } else {
            builder.append(";pattern=none")
        }
        if (let Some(declType) <- patternVarDecl.declType) {
            builder.append(";type=" + SerializeType(declType))
        } else {
            builder.append(";type=none")
        }
        if (let Some(initializer) <- patternVarDecl.initializer) {
            builder.append(";init=" + SerializeExprForNodeWriter(this, initializer))
        } else {
            builder.append(";init=none")
        }
        builder.append(")")
        return builder.toString()
    }

    public func SerializeFuncBody(body: FuncBody): String {
        let builder = StringBuilder()
        builder.append("params=[")
        var listIdx: Int64 = 0
        while (listIdx < body.paramLists.size) {
            if (listIdx > 0) {
                builder.append(",")
            }
            let paramList = body.paramLists[listIdx]
            builder.append("(")
            var paramIdx: Int64 = 0
            while (paramIdx < paramList.params.size) {
                if (paramIdx > 0) {
                    builder.append(",")
                }
                builder.append(SerializeFuncParam(paramList.params[paramIdx]))
                paramIdx++
            }
            builder.append(")")
            listIdx++
        }
        builder.append("]")
        if (let Some(retType) <- body.retType) {
            builder.append(";ret=" + SerializeType(retType))
        } else {
            builder.append(";ret=none")
        }
        if (let Some(block) <- body.body) {
            builder.append(";hasBody=true;body=" + SerializeBlock(block))
        } else {
            builder.append(";hasBody=false")
        }
        return builder.toString()
    }

    public func SerializeFuncParam(param: FuncParam): String {
        if (let Some(macroParam) <- (param as MacroExpandParam)) {
            return "macroParam(" + SerializeFuncParamBase(macroParam) + ";invocation=" +
                SerializeMacroInvocation(macroParam.invocation) + ")"
        }
        return "param(" + SerializeFuncParamBase(param) + ")"
    }

    private func SerializeFuncParamBase(param: FuncParam): String {
        let builder = StringBuilder()
        builder.append(EscapeNodeText(param.identifier))
        builder.append(";named=" + param.isNamedParam.toString())
        builder.append(";member=" + param.isMemberParam.toString())
        if (let Some(assignment) <- param.assignment) {
            builder.append(";default=" + SerializeExprForNodeWriter(this, assignment))
        } else {
            builder.append(";default=none")
        }
        return builder.toString()
    }

    public func SerializeBlock(block: Block): String {
        let builder = StringBuilder()
        builder.append("{")
        var idx: Int64 = 0
        while (idx < block.body.size) {
            if (idx > 0) {
                builder.append(";")
            }
            builder.append(SerializeNodeInline(block.body[idx]))
            idx++
        }
        builder.append("}")
        return builder.toString()
    }

    public func SerializeNodeInline(node: Node): String {
        if (let Some(expr) <- (node as Expr)) {
            return "expr:" + SerializeExprForNodeWriter(this, expr)
        }
        if (let Some(pattern) <- (node as Pattern)) {
            return "pattern:" + SerializePattern(pattern)
        }
        if (let Some(decl) <- (node as Decl)) {
            return "decl:" + SerializeDecl(decl)
        }
        if (let Some(file) <- (node as File)) {
            return "file:" + SerializeFile(file)
        }
        if (let Some(annotation) <- (node as Annotation)) {
            return "annotation:" + SerializeAnnotation(annotation)
        }
        return "node:" + ASTKindIndex(node.astKind).toString()
    }

    public func SerializeFile(file: File): String {
        let builder = StringBuilder()
        builder.append(EscapeNodeText(file.fileName) + "|")
        var idx: Int64 = 0
        while (idx < file.decls.size) {
            if (idx > 0) {
                builder.append(";")
            }
            builder.append(SerializeDecl(file.decls[idx]))
            idx++
        }
        return builder.toString()
    }
}
