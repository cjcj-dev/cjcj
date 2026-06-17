package cangjie_compiler::macro_pkg

import std.collection.*

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
    if (let Some(exprList) <- (expr as ExprListExpr)) {
        return SerializeExprVectorForNodeWriter(writer, "exprList:" + ASTKindIndex(exprList.astKind).toString(),
            exprList.children)
    }
    if (let Some(quoteExpr) <- (expr as QuoteExpr)) {
        return "quote(tokens=" + writer.SerializeTokenVector(quoteExpr.tokens) + ";exprs=" +
            SerializeExprVectorForNodeWriter(writer, "items", quoteExpr.exprs) + ")"
    }
    if (let Some(parenExpr) <- (expr as ParenExpr)) {
        return SerializeUnaryLikeExprForNodeWriter(writer, "paren", parenExpr.expr)
    }
    if (let Some(unaryExpr) <- (expr as UnaryExpr)) {
        return "unary(op=" + TokenKindIndex(unaryExpr.op).toString() + ";expr=" +
            SerializeExprOptionForNodeWriter(writer, unaryExpr.expr) + ")"
    }
    if (let Some(typeConvExpr) <- (expr as TypeConvExpr)) {
        return "typeConv(type=" + SerializeTypeOptionForNodeWriter(writer, typeConvExpr.typeNode) + ";expr=" +
            SerializeExprOptionForNodeWriter(writer, typeConvExpr.expr) + ")"
    }
    if (let Some(arrayExpr) <- (expr as ArrayExpr)) {
        return SerializeArrayExprForNodeWriter(writer, arrayExpr)
    }
    if (let Some(subscriptExpr) <- (expr as SubscriptExpr)) {
        return "subscript(base=" + SerializeExprOptionForNodeWriter(writer, subscriptExpr.baseExpr) + ";indices=" +
            SerializeExprVectorForNodeWriter(writer, "items", subscriptExpr.indexExprs) + ")"
    }
    if (let Some(optionalExpr) <- (expr as OptionalExpr)) {
        return SerializeUnaryLikeExprForNodeWriter(writer, "optional", optionalExpr.baseExpr)
    }
    if (let Some(optionalChainExpr) <- (expr as OptionalChainExpr)) {
        return SerializeUnaryLikeExprForNodeWriter(writer, "optionalChain", optionalChainExpr.expr)
    }
    if (let Some(letPatternExpr) <- (expr as LetPatternDestructor)) {
        return "letPattern(init=" + SerializeExprOptionForNodeWriter(writer, letPatternExpr.initializer) + ")"
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
    if (let Some(matchExpr) <- (expr as MatchExpr)) {
        return SerializeMatchExprForNodeWriter(writer, matchExpr)
    }
    if (let Some(tryExpr) <- (expr as TryExpr)) {
        return SerializeTryExprForNodeWriter(writer, tryExpr)
    }
    if (let Some(whileExpr) <- (expr as WhileExpr)) {
        return SerializeCondBodyExprForNodeWriter(writer, "while", whileExpr.condExpr, whileExpr.body)
    }
    if (let Some(doWhileExpr) <- (expr as DoWhileExpr)) {
        return SerializeCondBodyExprForNodeWriter(writer, "doWhile", doWhileExpr.condExpr, doWhileExpr.body)
    }
    if (let Some(forInExpr) <- (expr as ForInExpr)) {
        return SerializeForInExprForNodeWriter(writer, forInExpr)
    }
    if (let Some(lambdaExpr) <- (expr as LambdaExpr)) {
        if (let Some(lambdaBody) <- lambdaExpr.funcBody) {
            return "lambda(" + writer.SerializeFuncBody(lambdaBody) + ")"
        }
        return "lambda(none)"
    }
    if (let Some(throwExpr) <- (expr as ThrowExpr)) {
        return SerializeUnaryLikeExprForNodeWriter(writer, "throw", throwExpr.expr)
    }
    if (let Some(performExpr) <- (expr as PerformExpr)) {
        return SerializeUnaryLikeExprForNodeWriter(writer, "perform", performExpr.expr)
    }
    if (let Some(resumeExpr) <- (expr as ResumeExpr)) {
        return "resume(with=" + SerializeExprOptionForNodeWriter(writer, resumeExpr.withExpr) + ";throwing=" +
            SerializeExprOptionForNodeWriter(writer, resumeExpr.throwingExpr) + ")"
    }
    if (let Some(spawnExpr) <- (expr as SpawnExpr)) {
        return "spawn(arg=" + SerializeExprOptionForNodeWriter(writer, spawnExpr.arg) + ";task=" +
            SerializeExprOptionForNodeWriter(writer, spawnExpr.task) + ")"
    }
    if (let Some(syncExpr) <- (expr as SynchronizedExpr)) {
        return "synchronized(mutex=" + SerializeExprOptionForNodeWriter(writer, syncExpr.mutex) + ";body=" +
            SerializeBlockOptionForNodeWriter(writer, syncExpr.body) + ")"
    }
    if (let Some(trailingExpr) <- (expr as TrailingClosureExpr)) {
        let trailingBuilder = StringBuilder()
        trailingBuilder.append("trailing(base=" + SerializeExprOptionForNodeWriter(writer, trailingExpr.expr) +
            ";lambda=")
        if (let Some(lambdaExpr) <- trailingExpr.lambda) {
            trailingBuilder.append(SerializeExprForNodeWriter(writer, lambdaExpr))
        } else {
            trailingBuilder.append("none")
        }
        trailingBuilder.append(")")
        return trailingBuilder.toString()
    }
    if (let Some(interpolationExpr) <- (expr as InterpolationExpr)) {
        return "interpolation(" + SerializeBlockOptionForNodeWriter(writer, interpolationExpr.block) + ")"
    }
    if (let Some(strInterpolationExpr) <- (expr as StrInterpolationExpr)) {
        return SerializeExprVectorForNodeWriter(writer, "strInterpolation", strInterpolationExpr.strPartExprs)
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

public func SerializeExprOptionForNodeWriter(writer: NodeWriter, expr: Option<Expr>): String {
    if (let Some(value) <- expr) {
        return SerializeExprForNodeWriter(writer, value)
    }
    return "none"
}

public func SerializeTypeOptionForNodeWriter(writer: NodeWriter, ty: Option<Type>): String {
    if (let Some(value) <- ty) {
        return writer.SerializeType(value)
    }
    return "none"
}

public func SerializeBlockOptionForNodeWriter(writer: NodeWriter, block: Option<Block>): String {
    if (let Some(value) <- block) {
        return writer.SerializeBlock(value)
    }
    return "none"
}

public func SerializeUnaryLikeExprForNodeWriter(writer: NodeWriter, name: String, expr: Option<Expr>): String {
    return name + "(" + SerializeExprOptionForNodeWriter(writer, expr) + ")"
}

public func SerializeExprVectorForNodeWriter(writer: NodeWriter, name: String, exprs: ArrayList<Expr>): String {
    let builder = StringBuilder()
    builder.append(name + "=[")
    var idx: Int64 = 0
    while (idx < exprs.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(SerializeExprForNodeWriter(writer, exprs[idx]))
        idx++
    }
    builder.append("]")
    return builder.toString()
}

public func SerializeArrayExprForNodeWriter(writer: NodeWriter, arrayExpr: ArrayExpr): String {
    let builder = StringBuilder()
    builder.append("arrayExpr(type=" + SerializeTypeOptionForNodeWriter(writer, arrayExpr.typeNode) + ";args=[")
    var idx: Int64 = 0
    while (idx < arrayExpr.args.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(SerializeFuncArgForNodeWriter(writer, arrayExpr.args[idx]))
        idx++
    }
    builder.append("])")
    return builder.toString()
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

public func SerializeMatchExprForNodeWriter(writer: NodeWriter, matchExpr: MatchExpr): String {
    let builder = StringBuilder()
    builder.append("match(selector=" + SerializeExprOptionForNodeWriter(writer, matchExpr.selector) + ";cases=[")
    var caseIdx: Int64 = 0
    while (caseIdx < matchExpr.matchCases.size) {
        if (caseIdx > 0) {
            builder.append(",")
        }
        builder.append(SerializeMatchCaseForNodeWriter(writer, matchExpr.matchCases[caseIdx]))
        caseIdx++
    }
    builder.append("];others=[")
    var otherIdx: Int64 = 0
    while (otherIdx < matchExpr.matchCaseOthers.size) {
        if (otherIdx > 0) {
            builder.append(",")
        }
        builder.append(SerializeMatchCaseOtherForNodeWriter(writer, matchExpr.matchCaseOthers[otherIdx]))
        otherIdx++
    }
    builder.append("])")
    return builder.toString()
}

public func SerializeMatchCaseForNodeWriter(writer: NodeWriter, matchCase: MatchCase): String {
    return "case(guard=" + SerializeExprOptionForNodeWriter(writer, matchCase.patternGuard) + ";body=" +
        SerializeBlockOptionForNodeWriter(writer, matchCase.exprOrDecls) + ")"
}

public func SerializeMatchCaseOtherForNodeWriter(writer: NodeWriter, caseOther: MatchCaseOther): String {
    return "caseOther(expr=" + SerializeExprOptionForNodeWriter(writer, caseOther.matchExpr) + ";body=" +
        SerializeBlockOptionForNodeWriter(writer, caseOther.exprOrDecls) + ")"
}

public func SerializeTryExprForNodeWriter(writer: NodeWriter, tryExpr: TryExpr): String {
    let builder = StringBuilder()
    builder.append("try(resources=[")
    var resourceIdx: Int64 = 0
    while (resourceIdx < tryExpr.resourceSpec.size) {
        if (resourceIdx > 0) {
            builder.append(",")
        }
        builder.append(writer.SerializeDecl(tryExpr.resourceSpec[resourceIdx]))
        resourceIdx++
    }
    builder.append("];tryBlock=" + SerializeBlockOptionForNodeWriter(writer, tryExpr.tryBlock) + ";catchBlocks=[")
    var catchIdx: Int64 = 0
    while (catchIdx < tryExpr.catchBlocks.size) {
        if (catchIdx > 0) {
            builder.append(",")
        }
        builder.append(writer.SerializeBlock(tryExpr.catchBlocks[catchIdx]))
        catchIdx++
    }
    builder.append("];finally=" + SerializeBlockOptionForNodeWriter(writer, tryExpr.finallyBlock) + ")")
    return builder.toString()
}

public func SerializeCondBodyExprForNodeWriter(
    writer: NodeWriter,
    name: String,
    condExpr: Option<Expr>,
    body: Option<Block>
): String {
    return name + "(cond=" + SerializeExprOptionForNodeWriter(writer, condExpr) + ";body=" +
        SerializeBlockOptionForNodeWriter(writer, body) + ")"
}

public func SerializeForInExprForNodeWriter(writer: NodeWriter, forInExpr: ForInExpr): String {
    return "forIn(source=" + SerializeExprOptionForNodeWriter(writer, forInExpr.inExpr) + ";guard=" +
        SerializeExprOptionForNodeWriter(writer, forInExpr.patternGuard) + ";body=" +
        SerializeBlockOptionForNodeWriter(writer, forInExpr.body) + ")"
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
