package cangjie_compiler::macro_pkg

import std.collection.*

public let INITIAL_FILE_SIZE: Int64 = 65536

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
        return "pattern(" + ASTKindIndex(pattern.astKind).toString() + ")"
    }

    public func SerializeType(ty: Type): String {
        return "type(" + ty.name + ")"
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
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            return "func(" + funcDecl.identifier + "," + SerializeFuncBody(funcDecl.funcBody) + ")"
        }
        return "decl(" + ASTKindIndex(decl.astKind).toString() + "," + decl.identifier + ")"
    }

    public func SerializeFuncBody(body: FuncBody): String {
        let builder = StringBuilder()
        builder.append("params=" + body.paramLists.size.toString())
        if (let Some(block) <- body.body) {
            builder.append(";body=" + SerializeBlock(block))
        }
        return builder.toString()
    }

    public func SerializeFuncParam(param: FuncParam): String {
        if (let Some(macroParam) <- (param as MacroExpandParam)) {
            return "macroParam(" + SerializeMacroInvocation(macroParam.invocation) + ")"
        }
        return "param(" + param.identifier + ")"
    }

    public func SerializeBlock(block: Block): String {
        let builder = StringBuilder()
        builder.append("{")
        var idx: Int64 = 0
        while (idx < block.body.size) {
            if (idx > 0) {
                builder.append(";")
            }
            builder.append(ASTKindIndex(block.body[idx].astKind).toString())
            idx++
        }
        builder.append("}")
        return builder.toString()
    }

    public func SerializeFile(file: File): String {
        let builder = StringBuilder()
        builder.append(file.fileName + "|")
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
