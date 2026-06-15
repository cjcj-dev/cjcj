package cangjie_compiler::macro_pkg

public func SerializeExprForNodeWriter(writer: NodeWriter, expr: Expr): String {
    if (let Some(tokenPart) <- (expr as TokenPart)) {
        return "tokenPart(" + writer.SerializeTokenVector(tokenPart.tokens) + ")"
    }
    if (let Some(refExpr) <- (expr as RefExpr)) {
        return "ref(" + writer.EscapeText(refExpr.refName) + ")"
    }
    if (let Some(call) <- (expr as CallExpr)) {
        return SerializeCallExprForNodeWriter(writer, call)
    }
    if (let Some(member) <- (expr as MemberAccess)) {
        return SerializeMemberAccessForNodeWriter(writer, member)
    }
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return "lit(" + TokenKindIndex(lit.kind).toString() + ":" + writer.EscapeText(lit.rawString) + ")"
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
    builder.append(",args=[")
    var idx: Int64 = 0
    while (idx < call.args.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(SerializeFuncArgForNodeWriter(writer, call.args[idx]))
        idx++
    }
    builder.append("])")
    return builder.toString()
}

public func SerializeFuncArgForNodeWriter(writer: NodeWriter, arg: FuncArg): String {
    let builder = StringBuilder()
    builder.append("arg(")
    let argName = arg.name.Val()
    if (!argName.isEmpty()) {
        builder.append("name=" + writer.EscapeText(argName) + ";")
    }
    if (let Some(expr) <- arg.expr) {
        builder.append("expr=" + SerializeExprForNodeWriter(writer, expr))
    } else {
        builder.append("expr=none")
    }
    builder.append(")")
    return builder.toString()
}

public func SerializeMemberAccessForNodeWriter(writer: NodeWriter, member: MemberAccess): String {
    let builder = StringBuilder()
    builder.append("member(")
    if (let Some(baseExpr) <- member.baseExpr) {
        builder.append(SerializeExprForNodeWriter(writer, baseExpr))
    }
    builder.append("." + writer.EscapeText(member.field) + ")")
    return builder.toString()
}

public func SerializeIfExprForNodeWriter(writer: NodeWriter, ifExpr: IfExpr): String {
    let builder = StringBuilder()
    builder.append("if(cond=")
    if (let Some(cond) <- ifExpr.condExpr) {
        builder.append(SerializeExprForNodeWriter(writer, cond))
    } else {
        builder.append("none")
    }
    builder.append(";then=")
    if (let Some(thenBody) <- ifExpr.thenBody) {
        builder.append(writer.SerializeBlock(thenBody))
    } else {
        builder.append("none")
    }
    builder.append(";hasElse=" + ifExpr.hasElse.toString() + ")")
    return builder.toString()
}

public func SerializeBinaryExprForNodeWriter(writer: NodeWriter, binary: BinaryExpr): String {
    let builder = StringBuilder()
    builder.append("binary(left=")
    if (let Some(left) <- binary.leftExpr) {
        builder.append(SerializeExprForNodeWriter(writer, left))
    } else {
        builder.append("none")
    }
    builder.append(";op=" + TokenKindIndex(binary.op).toString() + ";right=")
    if (let Some(right) <- binary.rightExpr) {
        builder.append(SerializeExprForNodeWriter(writer, right))
    } else {
        builder.append("none")
    }
    builder.append(")")
    return builder.toString()
}
