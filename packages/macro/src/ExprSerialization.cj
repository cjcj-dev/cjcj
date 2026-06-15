package cangjie_compiler::macro_pkg

public func SerializeExprForNodeWriter(writer: NodeWriter, expr: Expr): String {
        if (let Some(tokenPart) <- (expr as TokenPart)) {
            return "tokenPart(" + writer.SerializeTokenVector(tokenPart.tokens) + ")"
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            return "ref(" + refExpr.refName + ")"
        }
        if (let Some(call) <- (expr as CallExpr)) {
            return SerializeCallExprForNodeWriter(writer, call)
        }
        if (let Some(member) <- (expr as MemberAccess)) {
            return SerializeMemberAccessForNodeWriter(writer, member)
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
            return "lit(" + lit.rawString + ")"
        }
        if (let Some(ret) <- (expr as ReturnExpr)) {
            if (let Some(inner) <- ret.expr) {
                return "return(" + SerializeExprForNodeWriter(writer, inner) + ")"
            }
            return "return()"
        }
        if (let Some(ifExpr) <- (expr as IfExpr)) {
            return SerializeIfExprForNodeWriter(writer, ifExpr)
        }
        if (let Some(binary) <- (expr as BinaryExpr)) {
            return SerializeBinaryExprForNodeWriter(writer, binary)
        }
        if (let Some(macroExpr) <- (expr as MacroExpandExpr)) {
            return "macroExpandExpr(" + writer.SerializeMacroInvocation(macroExpr.invocation) + ")"
        }
        if (let Some(block) <- (expr as Block)) {
            return writer.SerializeBlock(block)
        }
        return "expr(" + ASTKindIndex(expr.astKind).toString() + ")"
}

public func SerializeCallExprForNodeWriter(writer: NodeWriter, call: CallExpr): String {
        let builder = StringBuilder()
        builder.append("call(")
        if (let Some(baseFunc) <- call.baseFunc) {
            builder.append(SerializeExprForNodeWriter(writer, baseFunc))
        }
        builder.append(",args=")
        builder.append(call.args.size.toString())
        builder.append(")")
        return builder.toString()
}

public func SerializeMemberAccessForNodeWriter(writer: NodeWriter, member: MemberAccess): String {
        let builder = StringBuilder()
        builder.append("member(")
        if (let Some(baseExpr) <- member.baseExpr) {
            builder.append(SerializeExprForNodeWriter(writer, baseExpr))
        }
        builder.append("." + member.field + ")")
        return builder.toString()
}

public func SerializeIfExprForNodeWriter(writer: NodeWriter, ifExpr: IfExpr): String {
        let builder = StringBuilder()
        builder.append("if(")
        if (let Some(cond) <- ifExpr.condExpr) {
            builder.append(SerializeExprForNodeWriter(writer, cond))
        }
        builder.append(")")
        return builder.toString()
}

public func SerializeBinaryExprForNodeWriter(writer: NodeWriter, binary: BinaryExpr): String {
    let builder = StringBuilder()
    builder.append("binary(")
    if (let Some(left) <- binary.leftExpr) {
        builder.append(SerializeExprForNodeWriter(writer, left))
    }
    builder.append(TokenKindText(binary.op))
    if (let Some(right) <- binary.rightExpr) {
        builder.append(SerializeExprForNodeWriter(writer, right))
    }
    builder.append(")")
    return builder.toString()
}
