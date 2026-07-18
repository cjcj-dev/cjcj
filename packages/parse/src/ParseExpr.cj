package cjcj::parse

import std.collection.*
import cjcj::ast.MacroExpandDecl as AstMacroExpandDecl
import cjcj::ast.ExprKind as AstExprKind
import cjcj::ast.FuncBody as AstFuncBody
import cjcj::ast.FuncParamList as AstFuncParamList
import cjcj::ast.MacroInvocation as AstMacroInvocation
import cjcj::ast.VarDecl as AstVarDecl
import cjcj::ast.{ASTCloner, CopyBasicInfo, CreateBlock, CreateFuncBody, CreateFuncParam, CreateLambdaExpr,
    SetIsClonedSourceCode}
import cjcj::utils.CJC_ASSERT
import cjcj::utils.IF_AVAILABLE

private let G_NO_NEED_SEMI_EXPR_LIST: Array<ASTKind> = [
    ASTKind.THROW_EXPR, ASTKind.RETURN_EXPR, ASTKind.ASSIGN_EXPR, ASTKind.UNARY_EXPR, ASTKind.SPAWN_EXPR,
    ASTKind.IF_EXPR, ASTKind.TRY_EXPR, ASTKind.FOR_IN_EXPR, ASTKind.WHILE_EXPR
]

private func CreateLambdaFromBlock(block: Block, expr: Expr, paramList: FuncParamList): LambdaExpr {
    let paramLists = ArrayList<FuncParamList>()
    paramList.begin = expr.begin
    paramList.end = expr.end
    paramLists.add(paramList)
    let funcBody = CreateFuncBody(paramLists, None, block, None)
    let lambda = CreateLambdaExpr(funcBody)
    lambda.begin = expr.begin
    lambda.end = expr.end
    return lambda
}

private func DesugarTry(expr: TryExpr): Unit {
    if (expr.handlers.isEmpty()) {
        return
    }
    var lambdaBlock: Block
    if (expr.catchBlocks.isEmpty()) {
        lambdaBlock = (ASTCloner.Clone(expr.tryBlock.getOrThrow(), SetIsClonedSourceCode) as Block).getOrThrow()
    } else {
        let tryWithoutHandle = (ASTCloner.Clone(expr, SetIsClonedSourceCode) as TryExpr).getOrThrow()
        tryWithoutHandle.handlers.clear()
        tryWithoutHandle.finallyBlock = None
        if (let Some(ty) <- expr.GetTy()) {
            tryWithoutHandle.SetTy(ty)
        }
        let lambdaBody = ArrayList<Node>()
        lambdaBody.add(tryWithoutHandle)
        lambdaBlock = CreateBlock(lambdaBody)
    }
    expr.tryLambda = CreateLambdaFromBlock(lambdaBlock, expr.tryBlock.getOrThrow(), FuncParamList())

    for (handler in expr.handlers) {
        let rawCommandPattern = handler.commandPattern.getOrThrow()
        if (expr.hasBroken || rawCommandPattern.isBroken) {
            expr.hasBroken = true
            return
        }
        let commandPattern = (rawCommandPattern as CommandTypePattern).getOrThrow()
        if (commandPattern.types[0].isBroken) {
            expr.hasBroken = true
            return
        }
        let paramList = FuncParamList()
        let originalCommandPatternType = commandPattern.types[0]
        let commandTy = originalCommandPatternType.GetTy()
        let clonedCommandPattern = (ASTCloner.Clone(originalCommandPatternType) as Type).getOrThrow()
        let command = if ((let Some(pattern) <- commandPattern.pattern) &&
            (let Some(varPattern) <- (pattern as VarPattern)) && (let Some(varDecl) <- varPattern.varDecl)) {
            CreateFuncParam(varDecl.identifier.Val(), clonedCommandPattern, None, commandTy)
        } else {
            CreateFuncParam("_", clonedCommandPattern, None, commandTy)
        }
        CopyBasicInfo(commandPattern.pattern.getOrThrow(), command)
        paramList.params.add(command)
        let handlerBlock = (ASTCloner.Clone(handler.block.getOrThrow(), SetIsClonedSourceCode) as Block).getOrThrow()
        handler.desugaredLambda = CreateLambdaFromBlock(handlerBlock, handler.block.getOrThrow(), paramList)
    }

    if (let Some(finallyBlock) <- expr.finallyBlock) {
        let clonedFinally = (ASTCloner.Clone(finallyBlock, SetIsClonedSourceCode) as Block).getOrThrow()
        expr.finallyLambda = CreateLambdaFromBlock(clonedFinally, finallyBlock, FuncParamList())
    }
}

extend ParserImpl {
    public func TypeArgsMaybeConfusedWithExprWithComma(typeArgs: ArrayList<Type>): Bool {
        if (typeArgs.size <= 1) {
            return false
        }
        return TypesMaybeConfusedWithExprWithComma(typeArgs)
    }

    public func TypesMaybeConfusedWithExprWithComma(types: ArrayList<Type>): Bool {
        var index = types.size - 1
        while (index >= 0) {
            let ty = types[index]
            if (let Some(tupleType) <- (ty as TupleType)) {
                if (!TypesMaybeConfusedWithExprWithComma(tupleType.fieldTypes)) {
                    return false
                }
            } else if (let Some(parenType) <- (ty as ParenType)) {
                let innerTypes = ArrayList<Type>()
                innerTypes.add(parenType.innerType.getOrThrow())
                if (!TypesMaybeConfusedWithExprWithComma(innerTypes)) {
                    return false
                }
            } else if (ty.astKind == ASTKind.REF_TYPE || ty.astKind == ASTKind.QUALIFIED_TYPE) {
                if (ty.GetTypeArgs().isEmpty()) {
                    index--
                    continue
                }
                if (!TypesMaybeConfusedWithExprWithComma(ty.GetTypeArgs())) {
                    return false
                }
            } else {
                return false
            }
            index--
        }
        return true
    }

    public func IsLegFollowForGenArgInExprWithComma(ek: ExprKind): Bool {
        CJC_ASSERT(IsExprFollowedComma(ek))
        let followedCommas = LookupExprsFollowedCommas(ek).getOrThrow()
        if (Seeing(followedCommas[1])) {
            return true
        }
        if (newlineSkipped && SeeingAny(
            [TokenKind.LCURL, TokenKind.QUEST, TokenKind.LPAREN, TokenKind.LSQUARE, TokenKind.SUB])) {
            return false
        }
        if (SeeingAny(
            [TokenKind.LPAREN, TokenKind.LSQUARE, TokenKind.COMMA, TokenKind.DOT, TokenKind.LCURL])) {
            return true
        }
        if (LookupSeenCombinator().isSome()) {
            return true
        }
        return Precedence(Peek().kind) != INVALID_PRECEDENCE
    }

    public func ParseExpr(): Expr {
        return ParseExpr(ExprKind.ALL)
    }

    public func ParseExpr(ek: ExprKind): Expr {
        if (ExprKindEquals(ek, ExprKind.UNKNOWN_EXPR) && Seeing(TokenKind.LET)) {
            return ParseLetPattern(ek)
        }
        let ret = if (ExprKindEquals(ek, ExprKind.INDEX_EXPR)) {
            ParseIndexAccess()
        } else if (enableCustomAnno && SeeingIfAvailable()) {
            ParseIfAvailable()
        } else if (ExprKindEquals(ek, ExprKind.VAR_INIT)) {
            let expr = ParseExpr(Token(TokenKind.DOT))
            if (expr.astKind == ASTKind.ASSIGN_EXPR) {
                DiagCannotHaveAssignmentInInit(expr)
            }
            expr
        } else {
            ParseExpr(Token(TokenKind.DOT), ek: ek)
        }
        if (!SeeingExprOperator() && !ExprKindEquals(ek, ExprKind.EXPR_IN_TUPLE) &&
            !ExprKindEquals(ek, ExprKind.EXPR_IN_IF_COND_TUPLE) &&
            !ExprKindEquals(ek, ExprKind.EXPR_IN_WHILE_COND_TUPLE)) {
            CheckWildcardInExpr(ret)
        }
        if (Seeing(TokenKind.SEMI) && !G_NO_NEED_SEMI_EXPR_LIST.contains(ret.astKind)) {
            ret.hasSemi = true
            ret.semiPos = Peek().Begin()
        }
        if (let Some(macroExpr) <- (ret as MacroExpandExpr)) {
            macroExpr.invocation.scopeKind = None
            macroExpr.invocation.exprKind = Some(match (ek) {
                case ExprKind.ALL => AstExprKind.ALL
                case ExprKind.VAR_INIT => AstExprKind.VAR_INIT
                case ExprKind.INDEX_EXPR => AstExprKind.INDEX_EXPR
                case ExprKind.IF_COND_EXPR => AstExprKind.IF_COND_EXPR
                case ExprKind.WHILE_COND_EXPR => AstExprKind.WHILE_COND_EXPR
                case ExprKind.LET_PATTERN => AstExprKind.LET_PATTERN
                case ExprKind.LEFT_EXPR => AstExprKind.LEFT_EXPR
                case ExprKind.EXPR_IN_TUPLE => AstExprKind.EXPR_IN_TUPLE
                case ExprKind.EXPR_IN_IF_COND_TUPLE => AstExprKind.EXPR_IN_IF_COND_TUPLE
                case ExprKind.EXPR_IN_WHILE_COND_TUPLE => AstExprKind.EXPR_IN_WHILE_COND_TUPLE
                case ExprKind.EXPR_IN_ARRAY => AstExprKind.EXPR_IN_ARRAY
                case ExprKind.EXPR_IN_CALLSUFFIX => AstExprKind.EXPR_IN_CALLSUFFIX
                case ExprKind.EXPR_IN_ANNOTATION => AstExprKind.EXPR_IN_ANNOTATION
                case ExprKind.UNKNOWN_EXPR => AstExprKind.UNKNOWN_EXPR
            })
        }
        if (SeeingFakeOperator()) {
            DiagExpecetedOpeOrEnd()
            ConsumeUntilAny([TokenKind.NL])
        }
        return ret
    }

    public func ParseUnaryExpr(): Expr {
        return ParseUnaryExpr(ExprKind.ALL)
    }

    public func ParseUnaryExpr(ek: ExprKind): Expr {
        if (Seeing([TokenKind.SUB, TokenKind.NL], skipNewline: false) ||
            Seeing([TokenKind.NOT, TokenKind.NL], skipNewline: false)) {
            DiagExpectedNoNewLine()
            return InvalidExpr(Peek().Begin())
        }
        if (Seeing(TokenKind.NOT) || Seeing(TokenKind.SUB)) {
            let op = Peek()
            Next()
            let unary = UnaryExpr()
            try (cs = ChainScope(this, unary)) {
                unary.op = op.kind
                unary.operatorPos = op.Begin()
                unary.begin = op.Begin()
                let child = ParseUnaryExpr(RemoveParsingIfCondExpr(ek))
                if (op.kind == TokenKind.SUB) {
                    if (let Some(lit) <- (child as LitConstExpr)) {
                        if ((lit.kind == LitConstKind.INTEGER || lit.kind == LitConstKind.FLOAT) &&
                            !lit.stringValue.isEmpty() && lit.stringValue[0] != b'-') {
                            lit.stringValue = "-" + lit.stringValue
                            lit.rawString = lit.stringValue
                            lit.begin = op.Begin()
                            return lit
                        }
                    }
                }
                unary.expr = child
                if (let Some(child) <- unary.expr) { unary.end = child.end }
            }
            return unary
        }
        return ParseBaseExpr(ParseAtom(ek), ek)
    }

    public func RemoveParsingIfCondExpr(ek: ExprKind): ExprKind {
        if (ExprKindEquals(ek, ExprKind.EXPR_IN_IF_COND_TUPLE) ||
            ExprKindEquals(ek, ExprKind.EXPR_IN_WHILE_COND_TUPLE) ||
            ExprKindEquals(ek, ExprKind.IF_COND_EXPR) ||
            ExprKindEquals(ek, ExprKind.WHILE_COND_EXPR)) {
            return ExprKind.ALL
        }
        return ek
    }

    private func IsCompoundAssign(token: TokenKind): Bool {
        return token != TokenKind.ASSIGN && IsAssignment(token)
    }

    private func IsNeedToCreateOptionalChain(token: TokenKind, expr: Expr): Bool {
        if (!IsCompoundAssign(token) && token != TokenKind.ASSIGN && expr.hasQuestSuffix) {
            return true
        }
        if (let Some(incDecl) <- (expr as IncOrDecExpr)) {
            if (let Some(innerExpr) <- incDecl.expr) {
                return innerExpr.hasQuestSuffix
            }
        }
        return false
    }

    private func GetExprOperator(): Token {
        var token = Peek()
        if (let Some(combInfo) <- LookupSeenCombinator()) {
            token.kind = combInfo.kind
            token.SetValuePos(combInfo.Value(), token.Begin(), token.Begin() + combInfo.Value().size)
        }
        return token
    }

    private func SkipExprOperator(): Unit {
        Peek()
        if (let Some(combInfo) <- LookupSeenCombinator()) {
            var skipCount = combInfo.Value().size
            var skippedToken = Peek()
            while (skipCount > 0) {
                Next()
                skipCount--
                if (skipCount > 0) {
                    skippedToken = lastToken
                }
            }
            lastToken = skippedToken
            lastToken.kind = TokenKind.SENTINEL
            return
        }
        Next()
    }

    // C++: Parse/ParseExpr.cpp:155-205 ParserImpl::MakeOperatorExpr.
    public func MakeOperatorExpr(leftExpr: Expr, operatorToken: Token): Expr {
        if (operatorToken.kind == TokenKind.IS) {
            let isExpr = IsExpr()
            SpreadAttrAndConsume(leftExpr, isExpr, [])
            if (leftExpr.astKind == ASTKind.IS_EXPR || leftExpr.astKind == ASTKind.AS_EXPR) {
                DiagChainedAsExpr(leftExpr, operatorToken)
            }
            isExpr.begin = leftExpr.begin
            isExpr.isPos = operatorToken.Begin()
            isExpr.leftExpr = leftExpr
            return isExpr
        } else if (operatorToken.kind == TokenKind.AS) {
            let asExpr = AsExpr()
            SpreadAttrAndConsume(leftExpr, asExpr, [])
            if (leftExpr.astKind == ASTKind.IS_EXPR || leftExpr.astKind == ASTKind.AS_EXPR) {
                DiagChainedAsExpr(leftExpr, operatorToken)
            }
            asExpr.begin = leftExpr.begin
            asExpr.asPos = operatorToken.Begin()
            asExpr.leftExpr = leftExpr
            return asExpr
        } else if (operatorToken.kind == TokenKind.RANGEOP || operatorToken.kind == TokenKind.CLOSEDRANGEOP) {
            let rangeExpr = RangeExpr()
            SpreadAttrAndConsume(leftExpr, rangeExpr, [])
            rangeExpr.begin = leftExpr.begin
            rangeExpr.isClosed = operatorToken.kind == TokenKind.CLOSEDRANGEOP
            rangeExpr.rangePos = operatorToken.Begin()
            rangeExpr.startExpr = leftExpr
            return rangeExpr
        } else if (IsAssignment(operatorToken.kind)) {
            let assignExpr = AssignExpr()
            SpreadAttrAndConsume(leftExpr, assignExpr, [])
            assignExpr.begin = leftExpr.begin
            assignExpr.hasQuestSuffix = leftExpr.hasQuestSuffix
            assignExpr.leftValue = leftExpr
            assignExpr.assignPos = operatorToken.Begin()
            assignExpr.op = operatorToken.kind
            assignExpr.isCompound = operatorToken.kind != TokenKind.ASSIGN
            return assignExpr
        }
        let binaryExpr = BinaryExpr()
        SpreadAttrAndConsume(leftExpr, binaryExpr, [])
        binaryExpr.begin = leftExpr.begin
        binaryExpr.op = operatorToken.kind
        binaryExpr.operatorPos = operatorToken.Begin()
        binaryExpr.leftExpr = leftExpr
        return binaryExpr
    }

    public func ParseBaseExpr(expr: Expr): Expr {
        return ParseBaseExpr(Some(expr), ExprKind.ALL)
    }

    public func ParseBaseExpr(expr: Expr, ek: ExprKind): Expr {
        return ParseBaseExpr(Some(expr), ek)
    }

    public func ParseBaseExpr(expr: Option<Expr>, ek: ExprKind): Expr {
        if (expr.isNone() && (Seeing(TokenKind.SUB) || Seeing(TokenKind.NOT))) {
            return ParseUnaryExpr(ek)
        }
        var base = if (let Some(initialExpr) <- expr) { initialExpr } else { ParseAtom(ek) }
        if (base.astKind == ASTKind.JUMP_EXPR) {
            return base
        }
        var hasQuestSuffix = false
        while (true) {
            if (newlineSkipped && !Seeing(TokenKind.DOT)) {
                break
            }
            if (!newlineSkipped && SeeingOptionalSuffix()) {
                base = ParseQuestSuffixExpr(base)
                hasQuestSuffix = true
            } else if (Seeing(TokenKind.QUEST) && !SeeingCombinator([TokenKind.QUEST, TokenKind.QUEST])) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character_after, Peek().Begin(),
                    "'.', '(', '[', '{' or '?'", Peek().Value()).Emit()
                break
            }
            if (!newlineSkipped && Skip(TokenKind.LPAREN)) {
                base = ParseCallExpr(base)
                continue
            }
            if (Skip(TokenKind.DOT)) {
                base = ParseMemberAccess(base, ek)
                continue
            }
            if (!newlineSkipped && Skip(TokenKind.LSQUARE)) {
                base = ParseSubscriptExpr(base)
                continue
            }
            if (!newlineSkipped && SeeingTrailingClosure(base)) {
                base = ParseTrailingClosureExpr(base)
                continue
            }
            break
        }
        if (hasQuestSuffix) {
            base.hasQuestSuffix = true
        }
        base = ParseIncOrDec(base)
        if (IsNeedToCreateOptionalChain(GetExprOperator().kind, base)) {
            let chain = OptionalChainExpr()
            chain.expr = base
            chain.begin = base.begin
            chain.end = base.end
            base = chain
        }
        return base
    }

    public func ParseCallExpr(baseExpr: Expr): Expr {
        let callExpr = CallExpr()
        try (cs = ChainScope(this, callExpr)) {
            callExpr.begin = baseExpr.begin
            callExpr.leftParenPos = lastToken.Begin()
            baseExpr.isBaseFunc = true
            callExpr.baseFunc = baseExpr
            ParseZeroOrMoreSepTrailing(
                { pos: Position => callExpr.args[callExpr.args.size - 1].commaPos = pos },
                { => callExpr.args.add(ParseFuncArg()) },
                TokenKind.RPAREN)
            if (!Skip(TokenKind.RPAREN) && !callExpr.TestAttr(Attribute.HAS_BROKEN)) {
                callExpr.EnableAttr(Attribute.HAS_BROKEN)
                DiagExpectedRightDelimiter("(", callExpr.leftParenPos)
            }
            callExpr.rightParenPos = lastToken.Begin()
            callExpr.end = lastToken.End()
        }
        return callExpr
    }

    public func ParseSubscriptExpr(baseExpr: Expr): Expr {
        let ret = SubscriptExpr()
        try (cs = ChainScope(this, ret)) {
            ret.begin = baseExpr.begin
            ret.leftParenPos = lastToken.Begin()
            ret.baseExpr = baseExpr
            do {
                if (lastToken.kind == TokenKind.COMMA) {
                    ret.commaPos.add(lastToken.Begin())
                }
                ret.indexExprs.add(ParseExpr(ExprKind.INDEX_EXPR))
            } while (Skip(TokenKind.COMMA))
            if (!Skip(TokenKind.RSQUARE)) {
                DiagExpectedRightDelimiter("[", ret.leftParenPos)
                ret.hasBroken = true
            }
            ret.rightParenPos = lastToken.Begin()
            ret.end = lastToken.End()
        }
        return ret
    }

    public func ParseMemberAccess(baseExpr: Expr, ek: ExprKind): MemberAccess {
        let ret = MemberAccess()
        try (cs = ChainScope(this, ret)) {
            ret.begin = baseExpr.begin
            ret.baseExpr = baseExpr
            ret.dotPos = lastToken.Begin()
            ret.field = ExpectIdentifierWithPos(ret)
            if (Seeing(TokenKind.LT)) {
                let leftAnglePos = Peek().Begin()
                let scope = ParserScope(this)
                Next()
                diag.Prepare()
                let parsed = ParseTypeArguments(ek)
                if (parsed[0]) {
                    for (ty in parsed[1]) { ret.typeArguments.add(ty) }
                    diag.Commit()
                } else {
                    diag.ClearTransaction()
                    scope.ResetParserScope()
                    ret.leftAnglePos = INVALID_POSITION
                    ret.rightAnglePos = INVALID_POSITION
                    GetMemberAccessEndPos(ret)
                    return ret
                }
                ret.leftAnglePos = leftAnglePos
                ret.rightAnglePos = lastToken.Begin()
            }
            GetMemberAccessEndPos(ret)
        }
        return ret
    }

    private func ParseIncOrDec(baseExpr: Expr): Expr {
        var base = baseExpr
        while (SeeingAny([TokenKind.INCR, TokenKind.DECR]) && !newlineSkipped) {
            let validSuffix = [ASTKind.REF_EXPR, ASTKind.MEMBER_ACCESS, ASTKind.SUBSCRIPT_EXPR]
            if (!validSuffix.contains(base.astKind) && !base.TestAttr(Attribute.HAS_BROKEN) &&
                !base.TestAttr(Attribute.IS_BROKEN)) {
                base.EnableAttr(Attribute.HAS_BROKEN)
                DiagInvalidIncreExpr(base)
            }
            let op = Peek()
            let incOrDec = IncOrDecExpr()
            SpreadAttrAndConsume(base, incOrDec, [])
            incOrDec.begin = base.begin
            incOrDec.expr = base
            incOrDec.op = op.kind
            Next()
            incOrDec.begin = base.begin
            incOrDec.operatorPos = op.Begin()
            incOrDec.end = op.End()
            base = incOrDec
        }
        return base
    }

    private func CheckBaseOfTrailingClosureExpr(baseExpr: Expr): Unit {
        if (baseExpr.TestAttr(Attribute.IS_BROKEN)) {
            return
        }
        if (![ASTKind.MACRO_EXPAND_EXPR, ASTKind.ARRAY_EXPR, ASTKind.OPTIONAL_EXPR, ASTKind.CALL_EXPR,
            ASTKind.REF_EXPR, ASTKind.MEMBER_ACCESS].contains(baseExpr.astKind)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_trailing_closure_only_follow_name, baseExpr).Emit()
        }
        if (baseExpr.astKind == ASTKind.CALL_EXPR) {
            let callExpr = (baseExpr as CallExpr).getOrThrow()
            let baseFunc = callExpr.baseFunc.getOrThrow()
            if (baseFunc.TestAttr(Attribute.IS_BROKEN)) {
                return
            }
            if (![ASTKind.MEMBER_ACCESS, ASTKind.REF_EXPR, ASTKind.OPTIONAL_EXPR].contains(baseFunc.astKind)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_trailing_closure_only_follow_name, baseExpr).Emit()
            }
        }
    }

    // C++: Parse/ParserImpl.h:154-165 ParserImpl::SeeingTrailingClosure.
    public func SeeingTrailingClosure(baseExpr: Expr): Bool {
        if (Seeing(TokenKind.LCURL)) {
            return true
        }
        if (baseExpr.astKind != ASTKind.CALL_EXPR && baseExpr.astKind != ASTKind.REF_EXPR &&
            baseExpr.astKind != ASTKind.ARRAY_EXPR) {
            return false
        }
        return SeeingAnnotationLambdaExpr() || SeeingAnnotationTrailingClosure([TokenKind.LSQUARE])
    }

    // C++: Parse/ParseExpr.cpp:786-809 ParserImpl::ParseTrailingClosureExpr.
    public func ParseTrailingClosureExpr(baseExpr: Expr): TrailingClosureExpr {
        let ret = TrailingClosureExpr()
        let annos = ArrayList<Annotation>()
        ParseAnnotations(annos)
        SetBeginToAnnotationsBegin(ret, annos)
        ret.leftLambda = lastToken.Begin()
        Next()
        let lambda = ParseLambdaExprWithTrailingClosure()
        ret.lambda = Some(lambda)
        ret.rightLambda = lastToken.Begin()
        for (anno in annos) {
            if (anno.kind == AnnotationKind.NUMERIC_OVERFLOW) {
                lambda.EnableAttr(Attribute.NUMERIC_OVERFLOW)
                lambda.overflowStrategy = anno.overflowStrategy
                break
            }
        }
        CheckBaseOfTrailingClosureExpr(baseExpr)
        ret.expr = Some(baseExpr)
        ret.begin = baseExpr.begin
        ret.end = lambda.end
        return ret
    }

    public func SeeingOptionalSuffix(): Bool {
        return Seeing([TokenKind.QUEST, TokenKind.DOT]) || Seeing([TokenKind.QUEST, TokenKind.LPAREN], skipNewline: false) ||
            Seeing([TokenKind.QUEST, TokenKind.LSQUARE], skipNewline: false) ||
            Seeing([TokenKind.QUEST, TokenKind.LCURL], skipNewline: false)
    }

    public func ParseQuestSuffixExpr(expr: Expr): OptionalExpr {
        let token = Expect(TokenKind.QUEST, "expected '?'")
        let ret = OptionalExpr()
        ret.baseExpr = expr
        ret.questPos = token.Begin()
        ret.begin = expr.begin
        ret.end = expr.end
        return ret
    }

    public func IsConditionExpr(ek: ExprKind): Bool {
        return ExprKindEquals(ek, ExprKind.IF_COND_EXPR) || ExprKindEquals(ek, ExprKind.WHILE_COND_EXPR) ||
            ExprKindEquals(ek, ExprKind.EXPR_IN_IF_COND_TUPLE) ||
            ExprKindEquals(ek, ExprKind.EXPR_IN_WHILE_COND_TUPLE)
    }

    public func ParseExpr(preT: Token, expr!: Option<Expr> = None, ek!: ExprKind = ExprKind.ALL): Expr {
        var base = if (IsConditionExpr(ek) && Seeing(TokenKind.LET)) {
            ParseLetPattern(ek)
        } else {
            ParseBaseExpr(expr, ek)
        }
        if (!SeeingExprOperator()) {
            return base
        }
        let preP = Precedence(preT.kind)
        while (SeeingExprOperator()) {
            let tok = GetExprOperator()
            if (newlineSkipped) {
                let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_nl_warning, firstNLPosition)
                builder.AddHint(MakeRange(lastNoneNLToken.Begin(), Peek().Begin() + 1),
                    arguments: [lastNoneNLToken.Value(), tok.Value()])
                builder.Emit()
            }
            let curP = Precedence(tok.kind)
            if (IsConditionExpr(ek) && base.astKind == ASTKind.LET_PATTERN_DESTRUCTOR &&
                curP < Precedence(TokenKind.RANGEOP) && tok.kind != TokenKind.AND && tok.kind != TokenKind.OR) {
                return base
            }
            if (ExprKindEquals(ek, ExprKind.LET_PATTERN) && curP < Precedence(TokenKind.RANGEOP)) {
                return base
            }
            if (preP > curP) {
                return base
            } else if (preP == curP) {
                CheckLeftExpression(preT, base, tok)
                if (tok.kind != TokenKind.COALESCING && tok.kind != TokenKind.EXP &&
                    !(preT.Begin().IsZero() && Precedence(tok.kind) == INVALID_PRECEDENCE)) {
                    return base
                }
            }
            let res = CheckMacroExprRules(preT, tok, base)
            base = MakeOperatorExpr(base, tok)
            if (!res && !base.hasBroken) {
                base.hasBroken = true
            }
            base = ParseExprWithRightExprOrType(base, tok, ek)
        }
        return base
    }

    private func CheckLeftExpression(preT: Token, base: Expr, tok: Token): Unit {
        if (preT.Begin().IsZero()) {
            if (!IsLeftValueExpression(base, tok) && !base.hasBroken &&
                Precedence(tok.kind) == INVALID_PRECEDENCE) {
                DiagInvalidLeftHandExpr(base, tok)
                base.hasBroken = true
                base.isBroken = true
            }
            if (base.astKind == ASTKind.TUPLE_LIT && tok.kind != TokenKind.ASSIGN) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_cannot_operator_a_tuple, tok, tok.Value()).Emit()
            }
        } else if (IsNoneAssociative(tok) && !base.hasBroken) {
            DiagNoneAssociativeOp(preT, tok)
            base.hasBroken = true
        }
    }

    private func ParseExprWithRightExprOrType(baseExpr: Expr, tok: Token, ek: ExprKind): Expr {
        var base = baseExpr
        try (cs = ChainScope(this, base)) {
            SkipExprOperator()
            if (base.astKind == ASTKind.IS_EXPR || base.astKind == ASTKind.AS_EXPR) {
                let typeNode = if (!SeeingAny(GetTypeFirst()) && !SeeingContextualKeyword()) {
                    DiagExpectedTypeNameAfterAs(tok)
                    let invalid = InvalidType(lastToken.End())
                    base.hasBroken = true
                    invalid
                } else {
                    ParseType()
                }
                base.end = typeNode.end
                if (let Some(isExpr) <- (base as IsExpr)) {
                    isExpr.isType = typeNode
                } else if (let Some(asExpr) <- (base as AsExpr)) {
                    asExpr.asType = typeNode
                }
            } else {
                let rightExpr = ParseExpr(tok, ek: ek)
                let res = CheckMacroExprRules(tok, Token(TokenKind.DOT), rightExpr)
                if (!res || rightExpr.hasBroken || rightExpr.isBroken) {
                    base.hasBroken = true
                }
                RegisterRightExpr(base, rightExpr)
                if ((IsCompoundAssign(tok.kind) || tok.kind == TokenKind.ASSIGN) && base.hasQuestSuffix) {
                    let optExpr = OptionalChainExpr()
                    optExpr.begin = base.begin
                    optExpr.end = base.end
                    optExpr.expr = base
                    base = optExpr
                }
            }
        }
        return base
    }

    private func RegisterRightExpr(expr: Expr, rightExpr: Expr): Unit {
        if (let Some(assign) <- (expr as AssignExpr)) {
            if (assign.op == TokenKind.ASSIGN) {
                CheckWildcardInExpr(rightExpr)
            }
        }
        expr.end = rightExpr.end
        if (let Some(binary) <- (expr as BinaryExpr)) {
            binary.rightExpr = rightExpr
            return
        }
        if (let Some(assign) <- (expr as AssignExpr)) {
            assign.rightExpr = rightExpr
            return
        }
        if (let Some(range) <- (expr as RangeExpr)) {
            range.end = rightExpr.end
            range.stopExpr = rightExpr
            if (Skip(TokenKind.COLON)) {
                range.colonPos = lastToken.Begin()
                let dot2 = ".."
                var previous = Token(TokenKind.RANGEOP, dot2, range.rangePos, range.rangePos + dot2.size)
                previous.kind = if (range.isClosed) { TokenKind.CLOSEDRANGEOP } else { previous.kind }
                let op = if (range.isClosed) { "..=" } else { previous.Value() }
                previous.SetValuePos(op, previous.Begin(), previous.Begin() + op.size)
                range.stepExpr = ParseExpr(previous)
                if (let Some(step) <- range.stepExpr) {
                    range.end = step.end
                }
            }
        }
    }

    private func ParseIndexAccess(): Expr {
        if (IsAssignment(Peek().kind)) {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_expected_expression, lastToken.End(), lastToken.Value(), Peek().Value()).Emit()
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RSQUARE], targetTokenConsumed: false)
            return InvalidExpr(Peek().Begin())
        }
        let ret = RangeExpr()
        ret.begin = Peek().Begin()
        var hasFirstExpr = false
        if (!Seeing(TokenKind.RANGEOP) && !Seeing(TokenKind.CLOSEDRANGEOP)) {
            ret.startExpr = ParseExpr(Token(TokenKind.RANGEOP), ek: ExprKind.INDEX_EXPR)
            hasFirstExpr = true
        }
        if (!Seeing(TokenKind.RANGEOP) && !Seeing(TokenKind.CLOSEDRANGEOP)) {
            if (let Some(first) <- ret.startExpr) {
                return ParseExpr(Token(TokenKind.DOT), expr: Some(first), ek: ExprKind.INDEX_EXPR)
            }
            return InvalidExpr(Peek().Begin())
        }
        ret.isClosed = Peek().kind == TokenKind.CLOSEDRANGEOP
        ret.rangePos = Peek().Begin()
        Next()
        ret.end = lastToken.End()
        if (!Seeing(TokenKind.RSQUARE) && !Seeing(TokenKind.COLON)) {
            ret.stopExpr = ParseExpr(Token(TokenKind.RANGEOP), ek: ExprKind.INDEX_EXPR)
            if (let Some(stop) <- ret.stopExpr) {
                ret.end = stop.end
            }
        }
        if (ret.isClosed && ret.stopExpr.isNone()) {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_expected_expression, lastToken.End(), lastToken.Value(), Peek().Value()).Emit()
            ret.isBroken = true
        }
        if (Seeing(TokenKind.COLON)) {
            if (!hasFirstExpr || ret.stopExpr.isNone()) {
                DiagUnexpectedColonInRange(ret)
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RSQUARE], targetTokenConsumed: false)
                return ret
            }
            Next()
            ret.colonPos = lastToken.Begin()
            ret.stepExpr = ParseExpr(Token(TokenKind.RANGEOP), ek: ExprKind.INDEX_EXPR)
            if (let Some(step) <- ret.stepExpr) {
                ret.end = step.end
            }
        }
        return ParseExpr(Token(TokenKind.DOT), expr: Some(ret), ek: ExprKind.INDEX_EXPR)
    }

    public func Precedence(kind: TokenKind): UInt8 {
        return TokenPrecedence(kind)
    }

    public func SeeingExprOperator(): Bool {
        let token = Peek()
        if (newlineSkipped && (token.kind == TokenKind.SUB || token.kind == TokenKind.QUEST)) {
            return false
        }
        if (let Some(_) <- LookupSeenCombinator()) {
            return true
        }
        return Precedence(token.kind) != INVALID_PRECEDENCE || IsCompoundAssign(token.kind) ||
            token.kind == TokenKind.ASSIGN
    }

    private func SeeingFakeOperator(): Bool {
        return Seeing(TokenKind.COLON)
    }

    func CheckMacroExprRules(preT: Token, tok: Token, expr: Expr): Bool {
        if (let Some(macroExpr) <- (expr as MacroExpandExpr)) {
            if (!MacroInvocationHasExpandedDecl(macroExpr.invocation)) {
                return true
            }
            if (!preT.Begin().IsZero() && !expr.isBroken) {
                DiagInvalidMacroExpandExpr(preT, macroExpr)
                return false
            }
            if (!expr.isBroken) {
                DiagUnrecognizedNodeAfterMacro(tok, macroExpr)
            }
            return false
        }
        return true
    }

    private func MacroInvocationHasExpandedDecl(invocation: AstMacroInvocation): Bool {
        if (let Some(decl) <- invocation.decl) {
            if (let Some(macroDecl) <- (decl as AstMacroExpandDecl)) {
                return MacroInvocationHasExpandedDecl(macroDecl.invocation)
            }
            return true
        }
        return false
    }

    public func IsAssignment(kind: TokenKind): Bool {
        return kind == TokenKind.ASSIGN || kind == TokenKind.ADD_ASSIGN || kind == TokenKind.SUB_ASSIGN ||
            kind == TokenKind.MUL_ASSIGN || kind == TokenKind.EXP_ASSIGN || kind == TokenKind.DIV_ASSIGN ||
            kind == TokenKind.MOD_ASSIGN || kind == TokenKind.AND_ASSIGN || kind == TokenKind.OR_ASSIGN ||
            kind == TokenKind.BITAND_ASSIGN || kind == TokenKind.BITOR_ASSIGN || kind == TokenKind.BITXOR_ASSIGN ||
            kind == TokenKind.LSHIFT_ASSIGN || kind == TokenKind.RSHIFT_ASSIGN
    }

    private func CheckWildcardInExpr(root: Expr): Unit {
        CheckWildcardInExprNode(root)
    }

    private func CheckWildcardInExprNode(node: Node): Unit {
        if (node.astKind == ASTKind.MATCH_CASE_OTHER) {
            return
        }
        if (let Some(assign) <- (node as AssignExpr)) {
            if (assign.op == TokenKind.ASSIGN) {
                return
            }
        }
        if (node.astKind == ASTKind.WILDCARD_EXPR) {
            if (node.begin.line == Peek().Begin().line && Peek().Begin().line == lastToken.Begin().line &&
                Peek().kind != TokenKind.SENTINEL) {
                ConsumeUntilAny(
                    [TokenKind.NL, TokenKind.RPAREN, TokenKind.COMMA, TokenKind.RCURL],
                    targetTokenConsumed: false)
            }
            let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_expected_found, node, "_ wildcard")
            builder.AddMainHintArguments("expression", "wildcard")
            builder.Emit()
            node.isBroken = true
            return
        }
        for (child in node.Children()) {
            CheckWildcardInExprNode(child)
        }
    }

    private func IsLeftValueExpression(expr: Expr, tok: Token): Bool {
        if (expr.astKind == ASTKind.REF_EXPR || expr.astKind == ASTKind.WILDCARD_EXPR ||
            expr.astKind == ASTKind.OPTIONAL_CHAIN_EXPR) {
            return true
        }
        if (expr.astKind == ASTKind.TUPLE_LIT) {
            if (let Some(tuple) <- (expr as TupleLit)) {
                for (child in tuple.children) {
                    if (!IsLeftValueExpression(child, tok) && !child.isBroken) {
                        DiagInvalidLeftHandExpr(child, tok)
                    }
                }
            }
            return true
        }
        if (expr.astKind == ASTKind.MEMBER_ACCESS) {
            if (let Some(member) <- (expr as MemberAccess)) {
                return IsLeftAuxExpressionOption(member.baseExpr, tok)
            }
            return false
        }
        if (expr.astKind == ASTKind.SUBSCRIPT_EXPR) {
            if (let Some(subscript) <- (expr as SubscriptExpr)) {
                return IsLeftAuxExpressionOption(subscript.baseExpr, tok)
            }
            return false
        }
        return false
    }

    private func IsLeftAuxExpressionOption(expr: Option<Expr>, tok: Token): Bool {
        if (let Some(base) <- expr) {
            return IsLeftAuxExpression(base, tok)
        }
        return false
    }

    private func IsLeftAuxExpression(expr: Expr, tok: Token): Bool {
        if (expr.astKind == ASTKind.REF_EXPR || expr.astKind == ASTKind.PRIMITIVE_TYPE_EXPR) {
            return true
        }
        if (expr.astKind == ASTKind.OPTIONAL_EXPR) {
            if (let Some(optional) <- (expr as OptionalExpr)) {
                return IsLeftAuxExpressionOption(optional.baseExpr, tok)
            }
            return false
        }
        if (expr.astKind == ASTKind.MEMBER_ACCESS) {
            if (let Some(member) <- (expr as MemberAccess)) {
                return IsLeftAuxExpressionOption(member.baseExpr, tok)
            }
            return false
        }
        if (expr.astKind == ASTKind.CALL_EXPR) {
            if (let Some(call) <- (expr as CallExpr)) {
                return IsLeftAuxExpressionOption(call.baseFunc, tok)
            }
            return false
        }
        if (expr.astKind == ASTKind.SUBSCRIPT_EXPR) {
            if (let Some(subscript) <- (expr as SubscriptExpr)) {
                return IsLeftAuxExpressionOption(subscript.baseExpr, tok)
            }
            return false
        }
        return false
    }

    public func ParseLetPattern(ek: ExprKind): LetPatternDestructor {
        let ret = LetPatternDestructor()
        let letToken = Expect(TokenKind.LET, "expected 'let'")
        let conditionName = if (ExprKindEquals(ek, ExprKind.WHILE_COND_EXPR)) { "while-let" } else { "if-let" }
        ret.begin = letToken.Begin()
        ret.patterns.add(ParsePattern())
        while (Skip(TokenKind.BITOR)) {
            ret.orPos.add(lastToken.Begin())
            ret.patterns.add(ParsePattern())
        }
        if (!SkipBackarrow()) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_backarrow_in_let_cond, Peek(), conditionName,
                ConvertToken(Peek())).Emit()
            ConsumeUntilAny([TokenKind.AND, TokenKind.OR, TokenKind.RPAREN, TokenKind.LET, TokenKind.BACKARROW], targetTokenConsumed: false)
            let invalid = InvalidExpr(Peek().Begin())
            ret.backarrowPos = Peek().Begin()
            ret.initializer = invalid
            ret.end = invalid.end
            ret.isBroken = true
            return ret
        }
        ret.backarrowPos = lastToken.Begin()
        if (AtTerminator()) {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_expected_expression, lastToken.End(), ConvertToken(lastToken),
                ConvertToken(Peek())).Emit()
            let invalid = InvalidExpr(Peek().Begin())
            ret.initializer = invalid
            ret.end = invalid.end
            ret.isBroken = true
            return ret
        }
        ret.initializer = ParseExpr(ExprKind.LET_PATTERN)
        if (let Some(expr) <- ret.initializer) {
            ret.end = expr.end
        }
        return ret
    }

    public func ParseFuncArg(): FuncArg {
        let arg = FuncArg()
        arg.begin = Peek().Begin()
        if (SeeingNamedFuncArgs()) {
            arg.name = ExpectIdentifierWithPos(arg)
            arg.colonPos = Expect(TokenKind.COLON, "expected ':' after argument name").Begin()
            lastToken.kind = TokenKind.SENTINEL
            lastNoneNLToken.kind = TokenKind.SENTINEL
        } else if (Skip(TokenKind.INOUT)) {
            arg.withInout = true
            arg.inoutPos = lastToken.Begin()
        }
        arg.expr = ParseExpr(ExprKind.EXPR_IN_CALLSUFFIX)
        if (let Some(expr) <- arg.expr) {
            arg.end = expr.end
        }
        return arg
    }

    public func ParseIfAvailable(): IfAvailableExpr {
        let _ = Skip(TokenKind.AT)
        let begin = lastToken.Begin()
        let _ = Skip(TokenKind.IDENTIFIER)

        var bad = false
        var lparenPos = INVALID_POSITION
        var lparenSkipped = false
        if (Skip(TokenKind.LPAREN)) {
            lparenPos = lastToken.Begin()
            lparenSkipped = true
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character, lookahead.Begin(), "(", lookahead.Value()).Emit()
            bad = true
        }
        let arg = ParseFuncArg()
        if (arg.name.Empty()) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_ifavailable_arg_no_name, lookahead).Emit()
            bad = true
        }
        if (!Skip(TokenKind.COMMA)) {
            Next()
            let firstCommaBuilder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character,
                lastToken.Begin(), "','", "'" + lastToken.Value() + "'")
            firstCommaBuilder.AddMainHintArguments("','")
            firstCommaBuilder.Emit()
            let missingFirstComma = IfAvailableExpr()
            missingFirstComma.SetArg(arg)
            missingFirstComma.begin = begin
            missingFirstComma.EnableAttr(Attribute.IS_BROKEN)
            missingFirstComma.end = lastToken.End()
            ConsumeUntil(TokenKind.RPAREN)
            return missingFirstComma
        }

        let firstLambdaExpr = ParseExpr()
        if (let Some(lambda) <- (firstLambdaExpr as LambdaExpr)) {
            let _ = lambda
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_ifavailable_not_lambda, firstLambdaExpr).Emit()
            bad = true
        }

        if (!Skip(TokenKind.COMMA)) {
            Next()
            let secondCommaBuilder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character,
                lastToken.Begin(), "','", "'" + lastToken.Value() + "'")
            secondCommaBuilder.AddMainHintArguments("','")
            secondCommaBuilder.Emit()
            let missingSecondComma = IfAvailableExpr()
            missingSecondComma.SetArg(arg)
            if (let Some(lambda) <- (firstLambdaExpr as LambdaExpr)) {
                missingSecondComma.SetLambda1(lambda)
            }
            missingSecondComma.begin = begin
            missingSecondComma.EnableAttr(Attribute.IS_BROKEN)
            missingSecondComma.end = lastToken.End()
            ConsumeUntil(TokenKind.RPAREN)
            return missingSecondComma
        }
        let secondLambdaExpr = ParseExpr()
        if (let Some(lambda) <- (secondLambdaExpr as LambdaExpr)) {
            let _ = lambda
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_ifavailable_not_lambda, secondLambdaExpr).Emit()
            bad = true
        }
        let parsedIfAvailable = IfAvailableExpr()
        parsedIfAvailable.SetArg(arg)
        if (let Some(lambda) <- (firstLambdaExpr as LambdaExpr)) {
            parsedIfAvailable.SetLambda1(lambda)
        }
        if (let Some(lambda) <- (secondLambdaExpr as LambdaExpr)) {
            parsedIfAvailable.SetLambda2(lambda)
        }
        parsedIfAvailable.begin = begin
        if (!Skip(TokenKind.RPAREN)) {
            if (lparenSkipped) {
                let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_right_delimiter,
                    lookahead.Begin(), "(")
                builder.AddMainHintArguments(")")
                builder.AddHint(lparenPos, arguments: ["("])
                builder.Emit()
            }
            bad = true
        }
        if (bad) {
            parsedIfAvailable.EnableAttr(Attribute.IS_BROKEN)
        }
        parsedIfAvailable.end = lastToken.End()
        return parsedIfAvailable
    }

    public func ParseUnsafeBlock(): Expr {
        let unsafeToken = Expect(TokenKind.UNSAFE, "expected 'unsafe'")
        if (!Seeing(TokenKind.LCURL)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, unsafeToken, ConvertToken(Peek())).Emit()
            return InvalidExpr(unsafeToken.Begin())
        }
        let block = ParseBlock(ScopeKind.FUNC_BODY)
        block.EnableAttr(Attribute.UNSAFE)
        SetUnsafe(block)
        block.unsafePos = unsafeToken.Begin()
        block.begin = unsafeToken.Begin()
        return block
    }

    public func ParseBlock(): Block {
        return ParseBlock(ScopeKind.UNKNOWN_SCOPE)
    }

    public func ParseExpressionOrDeclarations(scopeKind: ScopeKind): Block {
        let result = Block()
        result.begin = lastToken.Begin()
        result.leftCurlPos = lastToken.Begin()
        try (cs = ChainScope(this, result)) {
            SkipBlank(TokenKind.SEMI)
            while (true) {
                let hasNLorSEMI = SkipNLOrSemi()
                if (Skip(TokenKind.RCURL)) {
                    result.rightCurlPos = lastToken.Begin()
                    break
                }
                if (DetectPrematureEnd()) {
                    var resPos = result.begin
                    let toLambdaLen: Int64 = 3
                    if (chainedAST.size >= toLambdaLen &&
                        chainedAST[chainedAST.size - toLambdaLen].astKind == ASTKind.LAMBDA_EXPR) {
                        let le = (chainedAST[chainedAST.size - toLambdaLen] as LambdaExpr).getOrThrow()
                        resPos = le.begin
                    }
                    DiagExpectedRightDelimiter("{", resPos)
                    break
                }
                if (!result.body.isEmpty() && !hasNLorSEMI) {
                    if (DiagForBlock(result)) {
                        result.end = lookahead.End()
                        return result
                    }
                    ConsumeUntilDeclOrNL(TokenKind.RCURL)
                    SkipBlank(TokenKind.NL)
                }
                if (SeeingMacroCallDecl() || SeeingDecl() || SeeingExpr()) {
                    let node = ParseExprOrDecl(scopeKind)
                    result.body.add(node)
                } else {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expr_or_decl_in, lookahead,
                        ConvertToken(lookahead)).Emit()
                    ConsumeUntilAny([TokenKind.RCURL, TokenKind.NL], targetTokenConsumed: false)
                }
            }
            if (Seeing(TokenKind.SEMI)) {
                result.hasSemi = true
                result.semiPos = lookahead.Begin()
            }
            result.end = lastToken.End()
        }
        return result
    }

    public func DiagForBlock(block: Block): Bool {
        if (SeeingAny([TokenKind.RPAREN, TokenKind.RSQUARE, TokenKind.GT])) {
            if (CanMatchBracketInStack()) {
                DiagExpectedRightDelimiter("{", block.begin)
                return true
            } else {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_unmatched_right_delimiter, lookahead,
                    lookahead.Value()).Emit()
            }
        } else {
            DiagExpectSemiOrNewline()
        }
        return false
    }

    public func ParseBlock(scopeKind: ScopeKind): Block {
        if (!Skip(TokenKind.LCURL)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, lookahead,
                ConvertToken(lookahead)).Emit()
            let block = Block()
            block.begin = lookahead.Begin()
            block.end = lookahead.Begin()
            block.isBroken = true
            return block
        }
        return ParseExpressionOrDeclarations(scopeKind)
    }

    public func ParseExprOrDecl(scopeKind: ScopeKind): Node {
        if (SeeingKeywordAndOperater()) {
            return ParseExpr()
        }
        if (SeeingMacroCall()) {
            if (curMacroCall.isSome() || enableCustomAnno) {
                if (SeeingIfAvailable()) {
                    return ParseIfAvailable()
                }
                return ParseDecl(scopeKind)
            }
            let expr = MacroExpandExpr()
            try (cs = ChainScope(this, expr)) {
                if (let Some(file) <- currentFile) {
                    expr.curFile = file
                    file.hasMacro = true
                }
                expr.begin = Peek().Begin()
                if (!ParseMacroCallIdentifier(expr.invocation, expr)) {
                    expr.EnableAttr(Attribute.IS_BROKEN)
                    expr.end = lastToken.End()
                    return expr
                }
                expr.identifier = Identifier(
                    expr.invocation.macroCallDiagInfo.identifier,
                    expr.invocation.macroCallDiagInfo.identifierPos,
                    expr.invocation.macroCallDiagInfo.identifierPos + expr.invocation.macroCallDiagInfo.identifier.size)
                ParseMacroInvocation(scopeKind, ArrayList<Modifier>(), expr.invocation)
                expr.end = if (let Some(inputDecl) <- expr.invocation.decl) { inputDecl.end } else { lastToken.End() }
            }
            return ParseExpr(Token(TokenKind.DOT), expr: Some(ParseBaseExpr(expr, ExprKind.ALL)))
        } else if (SeeingMacroCallDecl()) {
            return ParseDecl(scopeKind)
        } else if (CheckIfSeeingDecl(scopeKind)) {
            return ParseDecl(scopeKind)
        } else if (SeeingExpr()) {
            return ParseExpr()
        }
        return InvalidExpr(Peek().Begin())
    }

    public func CheckIfSeeingDecl(scopeKind: ScopeKind): Bool {
        if (SeeingIfAvailable()) {
            return false
        }
        return SeeingDecl() || SeeingMacroCallDecl() || SeeingIllegalDeclInBlock() ||
            SeeingPrimaryCtorDecl(scopeKind) || SeeingEnumConstructor(scopeKind)
    }

    public func SeeingIfAvailable(): Bool {
        if (!Seeing(TokenKind.AT)) {
            return false
        }
        let tokens = lexer.LookAheadSkipNL(1)
        return !tokens.isEmpty() && tokens[0].kind == TokenKind.IDENTIFIER && tokens[0].Value() == IF_AVAILABLE
    }

    public func SeeingPrimaryCtorDecl(scopeKind: ScopeKind): Bool {
        if (!ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY) && !ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY)) {
            return false
        }
        return Seeing(TokenKind.INIT) || SeeingPrimaryIdentifier()
    }

    public func SeeingEnumConstructor(scopeKind: ScopeKind): Bool {
        return (Seeing(TokenKind.IDENTIFIER) || SeeingContextualKeyword()) &&
            (ScopeKindEquals(scopeKind, ScopeKind.ENUM_BODY) || ScopeKindEquals(scopeKind, ScopeKind.ENUM_CONSTRUCTOR))
    }

    public func SeeingIllegalDeclInBlock(): Bool {
        return SeeingAny([TokenKind.CLASS, TokenKind.INIT, TokenKind.INTERFACE, TokenKind.EXTEND, TokenKind.STRUCT,
            TokenKind.PROP]) || SeeingImport()
    }

    // C++: src/Parse/ParseAtom.cpp:404-409 ParserImpl::ConsumeUntilIfExprEnd.
    public func ConsumeUntilIfExprEnd(): Unit {
        ConsumeUntil(TokenKind.LCURL)
        ConsumeUntil(TokenKind.RCURL)
        SkipBlank(TokenKind.NL, blank1: TokenKind.SEMI)
    }

    public func ParseIfExpr(): Expr {
        let ret = IfExpr()
        let token = Expect(TokenKind.IF, "expected 'if'")
        ret.ifPos = token.Begin()
        ret.begin = token.Begin()
        if (!Skip(TokenKind.LPAREN)) {
            DiagExpectedLeftParenAfter(ret.begin, "if")
            ConsumeUntilIfExprEnd()
            ret.EnableAttr(Attribute.IS_BROKEN)
            return ParserImpl.MakeInvalid(InvalidExpr(), ret.begin)
        }
        ret.leftParenPos = lastToken.Begin()
        let cond = ParseExpr(ExprKind.IF_COND_EXPR)
        ret.condExpr = cond
        if (!cond.TestAttr(Attribute.IS_BROKEN)) {
            CheckCondition(cond)
        }

        if (!Skip(TokenKind.RPAREN)) {
            if ((let Some(_) <- (cond as LetPatternDestructor)) && Skip(TokenKind.WHERE)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_if_let_andand, lastToken).Emit()
            } else {
                DiagExpectedRightDelimiter("(", ret.leftParenPos)
            }
            ret.EnableAttr(Attribute.IS_BROKEN)
            ret.thenBody = ParserImpl.MakeInvalid(Block(), lookahead.Begin())
            ret.end = lookahead.Begin()
            ConsumeUntilIfExprEnd()
            if (lastToken.kind == TokenKind.RCURL && Skip(TokenKind.ELSE)) {
                ParseElse(ret)
            }
            return ret
        }
        ret.rightParenPos = lastToken.Begin()
        let thenBody = ParseBlock(ScopeKind.FUNC_BODY)
        ret.thenBody = thenBody
        ret.end = thenBody.end
        SkipBlank(TokenKind.NL)
        if (Skip(TokenKind.ELSE)) {
            ParseElse(ret)
        }
        return ret
    }

    // C++: src/Parse/ParseAtom.cpp:455-469 ParserImpl::ParseElse.
    public func ParseElse(ret: IfExpr): Unit {
        ret.hasElse = true
        ret.elsePos = lastToken.Begin()
        if (Seeing(TokenKind.IF)) {
            ret.isElseIf = true
            ret.elseBody = ParseIfExpr()
        } else {
            ret.elseBody = ParseBlock(ScopeKind.FUNC_BODY)
        }
        ret.end = lastToken.End()
    }

    public func ParseMatchExpr(): MatchExpr {
        let ret = MatchExpr()
        let token = Expect(TokenKind.MATCH, "expected 'match'")
        ret.begin = token.Begin()
        try (cs = ChainScope(this, ret)) {
            skipNL = true
            if (Seeing([TokenKind.LCURL, TokenKind.CASE])) {
                ParseMatchNoSelector(ret)
                if (ret.matchCaseOthers.isEmpty()) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_case, lookahead,
                        ConvertToken(lookahead)).Emit()
                }
            } else {
                ret.matchMode = true
                if (!Skip(TokenKind.LPAREN)) {
                    DiagExpectedSelectorOrMatchExprBody(ret.begin)
                    ret.selector = InvalidExpr(lookahead.Begin())
                    ret.EnableAttr(Attribute.HAS_BROKEN)
                    ConsumeUntilAny([TokenKind.LCURL, TokenKind.NL], targetTokenConsumed: false)
                } else {
                    ret.leftParenPos = lastToken.Begin()
                    ret.selector = ParseExpr()
                    if (!Skip(TokenKind.RPAREN)) {
                        DiagExpectedRightDelimiter("(", ret.leftParenPos)
                    }
                    ret.rightParenPos = lastToken.Begin()
                }
                if (!Skip(TokenKind.LCURL)) {
                    if (!ret.TestAttr(Attribute.HAS_BROKEN)) {
                        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, lookahead,
                            ConvertToken(lookahead)).Emit()
                        ret.EnableAttr(Attribute.HAS_BROKEN)
                    }
                } else {
                    ret.leftCurlPos = lastToken.Begin()
                }
                SkipSemi()
                if (!Seeing(TokenKind.CASE)) {
                    ConsumeUntil(TokenKind.RCURL, targetTokenConsumed: false)
                }
                ParseMatchCases(ret)
                if (ret.matchCases.isEmpty()) {
                    let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_case, lookahead,
                        ConvertToken(lookahead))
                    builder.AddHint(MakeRange(ret.begin, "match"))
                    builder.Emit()
                }
            }
            if (!Skip(TokenKind.RCURL) && !ret.leftCurlPos.IsZero()) {
                DiagExpectedRightDelimiter("{", ret.leftCurlPos)
            }
            ret.rightCurlPos = lastToken.Begin()
            ret.end = lastToken.End()
        }
        return ret
    }

    // C++: src/Parse/ParseAtom.cpp:764-775 ParserImpl::ParsePatternsInCase.
    public func ParsePatternsInCase(matchCase: MatchCase, matchExpr: MatchExpr): Unit {
        let first = ParsePattern()
        first.ctxExpr = matchExpr.selector
        matchCase.patterns.add(first)
        while (Skip(TokenKind.BITOR)) {
            matchCase.bitOrPosVector.add(lastToken.Begin())
            let pattern = ParsePattern()
            pattern.ctxExpr = matchExpr.selector
            matchCase.patterns.add(pattern)
        }
    }

    // C++: src/Parse/ParseAtom.cpp:777-817 ParserImpl::ParseMatchCases.
    public func ParseMatchCases(matchExpr: MatchExpr): Unit {
        let consumeTarget = { =>
            SeeingAny([TokenKind.CASE, TokenKind.RCURL, TokenKind.DOUBLE_ARROW]) ||
                SeeingCombinator([TokenKind.ASSIGN, TokenKind.GT])
        }
        while (Skip(TokenKind.CASE)) {
            let matchCase = MatchCase()
            try (cs = ChainScope(this, matchCase)) {
                matchCase.begin = lastToken.Begin()
                ParsePatternsInCase(matchCase, matchExpr)
                if (Skip(TokenKind.WHERE)) {
                    matchCase.wherePos = lastToken.Begin()
                    matchCase.patternGuard = ParseExpr()
                } else {
                    matchCase.patternGuard = None
                }
                if (!Skip(TokenKind.DOUBLE_ARROW) && !SkipCombinedDoubleArrow()) {
                    let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_double_arrow_in_case,
                        lookahead, ConvertToken(lookahead))
                    builder.AddHint(MakeRange(matchCase.begin, "case"))
                    builder.Emit()
                    ConsumeUntilAny(consumeTarget, targetTokenConsumed: false)
                    let invalidBlock = Block()
                    invalidBlock.EnableAttr(Attribute.IS_BROKEN)
                    invalidBlock.begin = lookahead.Begin()
                    invalidBlock.end = lookahead.Begin()
                    matchCase.exprOrDecls = invalidBlock
                    matchCase.end = invalidBlock.end
                    matchCase.EnableAttr(Attribute.HAS_BROKEN)
                    if (!Skip(TokenKind.DOUBLE_ARROW) && !SkipCombinedDoubleArrow()) {
                        matchExpr.matchCases.add(matchCase)
                        continue
                    }
                }
                matchCase.arrowPos = lastToken.Begin()
                let block = ParseExprOrDeclsInMatchCase()
                matchCase.exprOrDecls = block
                matchCase.end = block.end
                if (block.body.isEmpty() && !block.TestAttr(Attribute.HAS_BROKEN)) {
                    DiagMatchCaseBodyCannotBeEmpty(matchCase.arrowPos + "=>".size)
                    matchCase.EnableAttr(Attribute.HAS_BROKEN)
                }
                matchExpr.matchCases.add(matchCase)
                SkipBlank(TokenKind.SEMI)
            }
        }
    }

    public func ParseMatchNoSelector(ret: MatchExpr): Unit {
        ret.matchMode = false
        ret.leftCurlPos = Peek().Begin()
        Next()
        let consumeTarget = { =>
            SeeingAny([TokenKind.CASE, TokenKind.RCURL, TokenKind.DOUBLE_ARROW]) ||
                SeeingCombinator([TokenKind.ASSIGN, TokenKind.GT])
        }
        while (Skip(TokenKind.CASE)) {
            let matchCase = MatchCaseOther()
            matchCase.begin = lastToken.Begin()
            if (Skip(TokenKind.WILDCARD)) {
                matchCase.matchExpr = WildcardExpr(lastToken.Begin())
            } else {
                matchCase.matchExpr = ParseExpr()
            }
            if (!Skip(TokenKind.DOUBLE_ARROW) && !SkipCombinedDoubleArrow()) {
                let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_double_arrow_in_case,
                    lookahead, ConvertToken(lookahead))
                builder.AddHint(MakeRange(matchCase.begin, "case"))
                builder.Emit()
                ConsumeUntilAny(consumeTarget, targetTokenConsumed: false)
                let invalidBlock = Block()
                invalidBlock.EnableAttr(Attribute.IS_BROKEN)
                invalidBlock.begin = lookahead.Begin()
                invalidBlock.end = lookahead.Begin()
                matchCase.exprOrDecls = invalidBlock
                matchCase.EnableAttr(Attribute.HAS_BROKEN)
                if (!Skip(TokenKind.DOUBLE_ARROW) && !SkipCombinedDoubleArrow()) {
                    matchCase.end = lastToken.End()
                    ret.matchCaseOthers.add(matchCase)
                    continue
                }
            }
            matchCase.arrowPos = lastToken.Begin()
            let block = ParseExprOrDeclsInMatchCase()
            matchCase.exprOrDecls = block
            matchCase.end = lastToken.End()
            if (block.body.isEmpty() && !matchCase.TestAttr(Attribute.HAS_BROKEN)) {
                DiagMatchCaseBodyCannotBeEmpty(matchCase.arrowPos + "=>".size)
                matchCase.EnableAttr(Attribute.HAS_BROKEN)
            }
            ret.matchCaseOthers.add(matchCase)
        }
    }

    public func ParseExprOrDeclsInMatchCase(): Block {
        let exprOrDecls = Block()
        exprOrDecls.begin = lookahead.Begin()
        var flag = false
        var hasSemi = false
        while (!SeeingAny([TokenKind.CASE, TokenKind.RCURL])) {
            if (flag && !newlineSkipped && !hasSemi && !exprOrDecls.TestAttr(Attribute.HAS_BROKEN)) {
                DiagExpectSemiOrNewline()
            }
            flag = true
            SkipBlank(TokenKind.SEMI)
            if (DetectPrematureEnd()) {
                break
            }
            if (SeeingMacroCallDecl() || SeeingDecl() || SeeingExpr()) {
                let node = ParseExprOrDecl(ScopeKind.FUNC_BODY)
                if (exprOrDecls.body.isEmpty()) {
                    exprOrDecls.begin = node.begin
                }
                exprOrDecls.body.add(node)
            } else {
                DiagMatchCaseExpectedExprOrDecl()
                exprOrDecls.EnableAttr(Attribute.HAS_BROKEN)
                ConsumeUntilAny([TokenKind.CASE, TokenKind.RCURL, TokenKind.NL], targetTokenConsumed: false)
            }
            hasSemi = Seeing(TokenKind.SEMI)
            SkipBlank(TokenKind.SEMI)
        }
        exprOrDecls.end = lastToken.End()
        return exprOrDecls
    }

    public func ParseTryExpr(): TryExpr {
        let ret = TryExpr()
        let token = Expect(TokenKind.TRY, "expected 'try'")
        ret.tryPos = token.Begin()
        ret.begin = token.Begin()
        if (Seeing(TokenKind.LCURL)) {
            ret.tryBlock = ParseBlock(ScopeKind.FUNC_BODY)
        } else if (Seeing(TokenKind.LPAREN)) {
            ParseTryWithResource(ret, ScopeKind.FUNC_BODY)
        } else {
            DiagExpectCharacter("'{' or '('", noteStr: "try expression must have block or resources")
            ret.hasBroken = true
            ret.isBroken = true
        }
        while (Seeing(TokenKind.HANDLE) || Seeing(TokenKind.CATCH)) {
            if (Skip(TokenKind.HANDLE)) {
                ParseHandleBlock(ret)
            } else if (Skip(TokenKind.CATCH)) {
                ParseCatchBlock(ret)
            }
        }
        if (Skip(TokenKind.FINALLY)) {
            ret.finallyPos = lastToken.Begin()
            ret.finallyBlock = ParseBlock(ScopeKind.FUNC_BODY)
        } else {
            // C++: src/Parse/ParseAtom.cpp:647-651 ParserImpl::ParseTryExpr.
            if (ret.catchBlocks.isEmpty() && ret.handlers.isEmpty() && ret.resourceSpec.isEmpty() &&
                !ret.hasBroken) {
                DiagExpectedCatchOrHandleOrFinallyAfterTry(ret)
                ret.hasBroken = true
            }
        }
        if (let Some(finallyBlock) <- ret.finallyBlock) {
            ret.end = finallyBlock.end
        } else if (!ret.handlers.isEmpty()) {
            if (let Some(block) <- ret.handlers[ret.handlers.size - 1].block) {
                ret.end = block.end
            }
        } else if (!ret.catchBlocks.isEmpty()) {
            ret.end = ret.catchBlocks[ret.catchBlocks.size - 1].end
        } else if (let Some(tryBlock) <- ret.tryBlock) {
            ret.end = tryBlock.end
        } else {
            ret.end = token.End()
        }
        if (!ret.hasBroken) {
            DesugarTry(ret)
        }
        return ret
    }

    public func ParseTryWithResource(ret: TryExpr, scopeKind: ScopeKind): Unit {
        ret.lParen = Expect(TokenKind.LPAREN, "expected '(' after try").Begin()
        let resourceNames = ArrayList<(String, Position)>()
        do {
            if (lastToken.kind == TokenKind.COMMA) {
                ret.resourceSpecCommaPos.add(lastToken.Begin())
            }
            let decl = AstVarDecl()
            try (cs = ChainScope(this, decl)) {
                decl.isVar = false
                decl.isResourceVar = true
                decl.identifier = ExpectIdentifierWithPos(decl)
                decl.begin = lookahead.Begin()
                var duplicate: Option<(String, Position)> = None
                for (nameAndPos in resourceNames) {
                    if (nameAndPos[0] == decl.identifier.Val()) {
                        duplicate = Some(nameAndPos)
                        break
                    }
                }
                if (let Some(previous) <- duplicate) {
                    DiagRedefinedResourceName((decl.identifier.Val(), decl.identifier.Begin()), previous)
                } else {
                    resourceNames.add((decl.identifier.Val(), decl.identifier.Begin()))
                }
                if (Skip(TokenKind.COLON)) {
                    decl.colonPos = lastToken.Begin()
                    decl.typeNode = ParseRefType(false)
                }
                if (!Skip(TokenKind.ASSIGN)) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_assignment, Peek(),
                        ConvertToken(Peek())).Emit()
                } else {
                    decl.assignPos = lastToken.Begin()
                }
                decl.initializer = ParseExpr(ExprKind.VAR_INIT)
                decl.end = lastToken.End()
                ret.resourceSpec.add(decl)
            }
        } while (Skip(TokenKind.COMMA))
        if (!Skip(TokenKind.RPAREN)) {
            DiagExpectedRightDelimiter("(", ret.lParen)
        } else {
            ret.rParen = lastToken.Begin()
        }
        ret.isDesugaredFromTryWithResources = true
        ret.tryBlock = ParseBlock(scopeKind)
    }

    public func ParseCatchBlock(ret: TryExpr): Unit {
        ret.catchPosVector.add(lastToken.Begin())
        var leftParenPos = INVALID_POSITION
        if (Skip(TokenKind.LPAREN)) {
            leftParenPos = lastToken.Begin()
            ret.catchLParenPosVector.add(leftParenPos)
        } else if (!ret.hasBroken) {
            DiagExpectedLeftParenAfter(ret.catchPosVector[ret.catchPosVector.size - 1], "catch")
            ret.hasBroken = true
        }
        ret.catchPatterns.add(ParseExceptTypePattern())
        if (Skip(TokenKind.RPAREN)) {
            ret.catchRParenPosVector.add(lastToken.Begin())
        } else if (!leftParenPos.IsZero()) {
            DiagExpectedRightDelimiter("(", leftParenPos)
            ret.isBroken = true
        }
        ret.catchBlocks.add(ParseBlock(ScopeKind.FUNC_BODY))
    }

    public func ParseHandleBlock(ret: TryExpr): Unit {
        let handler = Handler()
        handler.pos = lastToken.Begin()
        var leftParenPos = INVALID_POSITION
        if (!Skip(TokenKind.LPAREN)) {
            DiagExpectedLeftParenAfter(handler.pos, "handle")
            ret.isBroken = true
        } else {
            leftParenPos = lastToken.Begin()
        }
        handler.commandPattern = ParseCommandTypePattern()
        if (!Skip(TokenKind.RPAREN) && !leftParenPos.IsZero()) {
            DiagExpectedRightDelimiter("(", leftParenPos)
            ret.isBroken = true
        }
        handler.block = ParseBlock(ScopeKind.FUNC_BODY)
        ret.handlers.add(handler)
    }

    public func ParseExceptTypePattern(): Pattern {
        if (Skip(TokenKind.WILDCARD)) {
            let wildcard = WildcardPattern(lastToken.Begin())
            if (!Skip(TokenKind.COLON)) {
                return wildcard
            }
            let pattern = ExceptTypePattern()
            pattern.pattern = wildcard
            pattern.patternPos = wildcard.begin
            pattern.colonPos = lastToken.Begin()
            pattern.begin = wildcard.begin
            do {
                if (lastToken.kind == TokenKind.BITOR) {
                    pattern.bitOrPosVector.add(lastToken.Begin())
                }
                pattern.types.add(ParseType())
            } while (Skip(TokenKind.BITOR))
            if (!pattern.types.isEmpty()) {
                pattern.end = pattern.types[pattern.types.size - 1].end
            }
            return pattern
        }
        if (SeeingIdentifierLike()) {
            let token = Peek()
            let identifier = ParseIdentifierFromToken(token)
            Next()
            let varPattern = VarPattern(identifier, false)
            let pattern = ExceptTypePattern()
            pattern.pattern = varPattern
            pattern.patternPos = token.Begin()
            pattern.begin = token.Begin()
            if (Skip(TokenKind.COLON)) {
                pattern.colonPos = lastToken.Begin()
            } else {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_colon_in_catch_pattern, Peek(),
                    ConvertToken(Peek())).Emit()
                pattern.isBroken = true
            }
            do {
                if (lastToken.kind == TokenKind.BITOR) {
                    pattern.bitOrPosVector.add(lastToken.Begin())
                }
                pattern.types.add(ParseType())
            } while (Skip(TokenKind.BITOR))
            if (!pattern.types.isEmpty()) {
                pattern.end = pattern.types[pattern.types.size - 1].end
            }
            return pattern
        }
        let token = Peek()
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_wildcard_or_exception_pattern, token,
            ConvertToken(token)).Emit()
        return InvalidPattern(token.Begin())
    }

    public func ParseCommandTypePattern(): Pattern {
        if (Skip(TokenKind.WILDCARD)) {
            let wildcard = WildcardPattern(lastToken.Begin())
            if (!Skip(TokenKind.COLON)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_colon_in_effect_pattern, Peek(),
                    ConvertToken(Peek())).Emit()
                return InvalidPattern(wildcard.begin)
            }
            let pattern = CommandTypePattern()
            pattern.pattern = wildcard
            pattern.patternPos = wildcard.begin
            pattern.colonPos = lastToken.Begin()
            pattern.begin = wildcard.begin
            do {
                if (lastToken.kind == TokenKind.BITOR) {
                    pattern.bitOrPosVector.add(lastToken.Begin())
                }
                pattern.types.add(ParseType())
            } while (Skip(TokenKind.BITOR))
            if (!pattern.types.isEmpty()) {
                pattern.end = pattern.types[pattern.types.size - 1].end
            }
            return pattern
        }
        if (SeeingIdentifierLike()) {
            let token = Peek()
            let identifier = ParseIdentifierFromToken(token)
            Next()
            let varPattern = VarPattern(identifier, false)
            let pattern = CommandTypePattern()
            pattern.pattern = varPattern
            pattern.patternPos = token.Begin()
            pattern.begin = token.Begin()
            if (Skip(TokenKind.COLON)) {
                pattern.colonPos = lastToken.Begin()
            } else {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_colon_in_effect_pattern, Peek(),
                    ConvertToken(Peek())).Emit()
                pattern.isBroken = true
            }
            do {
                if (lastToken.kind == TokenKind.BITOR) {
                    pattern.bitOrPosVector.add(lastToken.Begin())
                }
                pattern.types.add(ParseType())
            } while (Skip(TokenKind.BITOR))
            if (!pattern.types.isEmpty()) {
                pattern.end = pattern.types[pattern.types.size - 1].end
            }
            return pattern
        }
        let token = Peek()
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_wildcard_or_effect_pattern, token, ConvertToken(token)).Emit()
        Next()
        return InvalidPattern(token.Begin())
    }

    public func ParseWhileExpr(): WhileExpr {
        let ret = WhileExpr()
        let token = Expect(TokenKind.WHILE, "expected 'while'")
        ret.whilePos = token.Begin()
        ret.begin = token.Begin()
        if (!Skip(TokenKind.LPAREN)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren, lookahead,
                ConvertToken(lookahead)).Emit()
        } else {
            ret.leftParenPos = lastToken.Begin()
        }
        let cond = ParseExpr(ExprKind.WHILE_COND_EXPR)
        ret.condExpr = cond
        if (!cond.TestAttr(Attribute.HAS_BROKEN)) {
            CheckCondition(cond)
        }

        if (!Skip(TokenKind.RPAREN) && !ret.leftParenPos.IsZero()) {
            if ((let Some(_) <- (cond as LetPatternDestructor)) && Skip(TokenKind.WHERE)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_if_let_andand, lastToken).Emit()
            } else {
                DiagExpectedRightDelimiter("(", ret.leftParenPos)
            }
            ret.body = ParserImpl.MakeInvalid(Block(), lookahead.Begin())
            ret.end = lookahead.Begin()
            ConsumeUntilIfExprEnd()
            return ret
        }
        ret.rightParenPos = lastToken.Begin()
        let body = ParseBlock(ScopeKind.FUNC_BODY)
        ret.body = body
        if (body.TestAttr(Attribute.IS_BROKEN)) {
            ret.EnableAttr(Attribute.IS_BROKEN)
        }
        ret.end = body.end
        return ret
    }

    public func ParseDoWhileExpr(): DoWhileExpr {
        let ret = DoWhileExpr()
        let token = Expect(TokenKind.DO, "expected 'do'")
        ret.doPos = token.Begin()
        ret.begin = token.Begin()
        ret.body = ParseBlock(ScopeKind.FUNC_BODY)
        if (!Skip(TokenKind.WHILE)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_while_in_do_while, lookahead,
                ConvertToken(lookahead)).Emit()
            ConsumeUntilAny([TokenKind.NL, TokenKind.WHILE])
            if (!Skip(TokenKind.WHILE)) {
                ret.EnableAttr(Attribute.IS_BROKEN)
                ret.end = lastToken.End()
                return ret
            }
        }
        ret.whilePos = lookahead.Begin()
        if (!Skip(TokenKind.LPAREN)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren, lookahead,
                ConvertToken(lookahead)).Emit()
        } else {
            ret.leftParenPos = lastToken.Begin()
        }
        ret.condExpr = ParseExpr()
        if (!Skip(TokenKind.RPAREN)) {
            if (!ret.leftParenPos.IsZero()) {
                DiagExpectedRightDelimiter("(", ret.leftParenPos)
            }
            ConsumeUntil(TokenKind.NL)
        }
        ret.rightParenPos = lastToken.Begin()
        ret.end = lastToken.End()
        return ret
    }

    public func ParseForInExpr(): ForInExpr {
        let ret = ForInExpr()
        let token = Expect(TokenKind.FOR, "expected 'for'")
        ret.begin = token.Begin()
        if (!Skip(TokenKind.LPAREN)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren, lookahead,
                ConvertToken(lookahead)).Emit()
            ConsumeUntilIfExprEnd()
            ret.EnableAttr(Attribute.IS_BROKEN)
            ret.end = lastToken.End()
            return ret
        }
        ret.leftParenPos = lastToken.Begin()
        ret.pattern = ParsePattern(ArrayList<Attribute>(), false, true)
        if (!Skip(TokenKind.IN)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_in_forin_expression, lookahead,
                ConvertToken(lookahead)).Emit()
            ConsumeUntilIfExprEnd()
            ret.EnableAttr(Attribute.IS_BROKEN)
            ret.end = lastToken.End()
            return ret
        }
        ret.inPos = lookahead.Begin()
        ret.inExpression = ParseExpr()
        if (Skip(TokenKind.WHERE)) {
            ret.wherePos = lastToken.Begin()
            ret.patternGuard = ParseExpr()
        }
        if (!Skip(TokenKind.RPAREN)) {
            DiagExpectedRightDelimiter("(", ret.leftParenPos)
            ConsumeUntilIfExprEnd()
            ret.EnableAttr(Attribute.IS_BROKEN)
            ret.end = lastToken.End()
            return ret
        }
        ret.rightParenPos = lastToken.Begin()
        SkipBlank(TokenKind.NL)
        ret.body = ParseBlock(ScopeKind.FUNC_BODY)
        if (let Some(body) <- ret.body) { ret.end = body.end }
        return ret
    }

    public func ParseReturnExpr(): ReturnExpr {
        let ret = ReturnExpr()
        let token = Expect(TokenKind.RETURN, "expected 'return'")
        ret.returnPos = token.Begin()
        ret.begin = token.Begin()
        if ((SeeingDecl() && !SeeingContextualKeyword()) || AtTerminator() || Seeing(TokenKind.CASE) ||
            SeeingDoubleArrow()) {
            let unitLit = LitConstExpr(LitConstKind.UNIT, "()")
            unitLit.begin = lastToken.End()
            unitLit.end = unitLit.begin
            unitLit.EnableAttr(Attribute.COMPILER_ADD)
            ret.expr = unitLit
            if (Seeing(TokenKind.SEMI)) {
                ret.hasSemi = true
                ret.semiPos = Peek().Begin()
            }
        } else {
            if (newlineSkipped) {
                let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_nl_warning, firstNLPosition)
                let tokenValue = if (let Some(combInfo) <- LookupSeenCombinator()) {
                    combInfo.Value()
                } else {
                    Peek().Value()
                }
                builder.AddHint(MakeRange(lastNoneNLToken.Begin(), Peek().Begin() + 1),
                    arguments: [lastNoneNLToken.Value(), tokenValue])
                builder.Emit()
            }
            ret.expr = ParseExpr()
            if (ret.expr.getOrThrow().TestAttr(Attribute.IS_BROKEN)) {
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI])
            }
        }
        ret.end = ret.expr.getOrThrow().end
        return ret
    }

    public func ParseThrowExpr(): ThrowExpr {
        let ret = ThrowExpr()
        let token = Expect(TokenKind.THROW, "expected 'throw'")
        ret.throwPos = token.Begin()
        ret.begin = token.Begin()
        ret.expr = ParseExpr()
        if (let Some(expr) <- ret.expr) {
            ret.end = expr.end
        }
        return ret
    }

    public func ParsePerformExpr(): PerformExpr {
        let ret = PerformExpr()
        let token = Expect(TokenKind.PERFORM, "expected 'perform'")
        ret.performPos = token.Begin()
        ret.begin = token.Begin()
        ret.expr = ParseExpr()
        ret.end = if (let Some(expr) <- ret.expr) { expr.end } else { token.End() }
        return ret
    }

    public func ParseResumeExpr(): ResumeExpr {
        let ret = ResumeExpr()
        let token = Expect(TokenKind.RESUME, "expected 'resume'")
        ret.resumePos = token.Begin()
        ret.begin = token.Begin()
        ret.end = token.End()
        if (Skip(TokenKind.WITH)) {
            ret.withPos = lastToken.Begin()
            ret.withExpr = ParseExpr()
            if (let Some(expr) <- ret.withExpr) { ret.end = expr.end }
        } else if (Skip(TokenKind.THROWING)) {
            ret.throwingPos = lastToken.Begin()
            ret.throwingExpr = ParseExpr()
            if (let Some(expr) <- ret.throwingExpr) { ret.end = expr.end }
        }
        return ret
    }

    public func ParseSpawnExpr(): SpawnExpr {
        let ret = SpawnExpr()
        let token = Expect(TokenKind.SPAWN, "expected 'spawn'")
        ret.spawnPos = token.Begin()
        ret.begin = token.Begin()
        let firstTaskToken = lookahead
        if (Seeing(TokenKind.LPAREN)) {
            if (newlineSkipped) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_newline_not_allowed_between_spawn_and_argument,
                    firstNLPosition).Emit()
            }
            if (Skip(TokenKind.LPAREN)) {
                ret.leftParenPos = lastToken.Begin()
                ret.arg = ParseExpr()
            }
            if (!Skip(TokenKind.RPAREN) && !ret.TestAttr(Attribute.HAS_BROKEN)) {
                ret.EnableAttr(Attribute.HAS_BROKEN)
                DiagExpectedRightDelimiter("(", ret.leftParenPos)
            }
            ret.rightParenPos = lastToken.Begin()
        }
        if (SeeingAnnotationLambdaExpr()) {
            ret.task = ParseAnnotationLambdaExpr(true)
        } else if (Skip(TokenKind.LCURL)) {
            ret.task = ParseLambdaExprWithTrailingClosure()
        } else {
            DiagExpectedExpression()
            let invalid = InvalidExpr(Peek().Begin())
            ret.task = invalid
            ret.isBroken = true
        }
        if (let Some(task) <- ret.task) {
            if (task.astKind != ASTKind.LAMBDA_EXPR) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, firstTaskToken,
                    ConvertToken(lookahead)).Emit()
                ret.isBroken = true
            }
            if (let Some(lambda) <- (task as LambdaExpr)) {
                let body = lambda.funcBody.getOrThrow()
                if (!body.paramLists[0].params.isEmpty()) {
                    let params = body.paramLists[0].params
                    DiagExpectedNoArgumentsInSpawn(params, ret.begin)
                    ret.isBroken = true
                }
            }
            ret.end = task.end
        }
        return ret
    }

    public func ParseSynchronizedExpr(): SynchronizedExpr {
        let ret = SynchronizedExpr()
        let token = Expect(TokenKind.SYNCHRONIZED, "expected 'synchronized'")
        ret.syncPos = token.Begin()
        ret.begin = token.Begin()
        if (!Skip(TokenKind.LPAREN)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren, lookahead,
                ConvertToken(lookahead)).Emit()
            ret.EnableAttr(Attribute.HAS_BROKEN)
        }
        ret.leftParenPos = lastToken.Begin()
        ret.mutex = ParseExpr()
        if (!Skip(TokenKind.RPAREN) && !ret.TestAttr(Attribute.HAS_BROKEN)) {
            DiagExpectedRightDelimiter("(", ret.leftParenPos)
            ret.EnableAttr(Attribute.HAS_BROKEN)
        }
        ret.rightParenPos = lastToken.Begin()
        ret.body = ParseBlock(ScopeKind.FUNC_BODY)
        if (let Some(body) <- ret.body) { ret.end = body.end }
        return ret
    }

    public func ParseLambdaExprWithTrailingClosure(): LambdaExpr {
        // C++: Parse/ParseAtom.cpp:1613-1621 ParserImpl::ParseLambdaExprWithTrailingClosure.
        let ret = ParseBaseLambdaExpr()
        try (cs = ChainScope(this, ret)) {
            let funcBody = ParseFuncBodyInLambdaExpr(true)
            ret.funcBody = Some(funcBody)
            ret.end = funcBody.end
            let body = funcBody.body.getOrThrow()
            body.leftCurlPos = ret.begin
        }
        return ret
    }

    public func ParseLambdaExpr(): LambdaExpr {
        // C++: Parse/ParseAtom.cpp:1566-1574 ParserImpl::ParseLambdaExpr.
        let ret = ParseBaseLambdaExpr()
        try (cs = ChainScope(this, ret)) {
            let funcBody = ParseFuncBodyInLambdaExpr(false)
            ret.funcBody = Some(funcBody)
            ret.end = funcBody.end
            let body = funcBody.body.getOrThrow()
            body.leftCurlPos = ret.begin
        }
        return ret
    }

    // C++: Parse/ParseAtom.cpp:1492-1518 ParserImpl::ParseFuncParamListInLambdaExpr.
    private func ParseFuncParamListInLambdaExpr(): AstFuncParamList {
        let paramList = AstFuncParamList()
        try (cs = ChainScope(this, paramList)) {
            if (SeeingInvaildParamListInLambdaExpr()) {
                paramList.begin = Peek().Begin()
                paramList.end = Peek().Begin()
                return paramList
            }
            ParseZeroOrMoreSepTrailing(
                { pos: Position => paramList.params[paramList.params.size - 1].commaPos = pos },
                { =>
                    let param = ParseFuncParam()
                    if (param.TestAttr(Attribute.IS_BROKEN)) {
                        paramList.EnableAttr(Attribute.IS_BROKEN)
                    }
                    paramList.params.add(param)
                },
                TokenKind.DOUBLE_ARROW)
            if (!paramList.params.isEmpty()) {
                paramList.begin = paramList.params[0].begin
                paramList.end = paramList.params[paramList.params.size - 1].end
            }
        }
        return paramList
    }

    // C++: Parse/ParseAtom.cpp:1520-1564 ParserImpl::ParseFuncBodyInLambdaExpr.
    public func ParseFuncBodyInLambdaExpr(isTailClosure: Bool): AstFuncBody {
        let funcBody = AstFuncBody()
        try (cs = ChainScope(this, funcBody)) {
            let paramList = ParseFuncParamListInLambdaExpr()
            if (paramList.TestAttr(Attribute.IS_BROKEN)) {
                chainedAST[chainedAST.size - 1].EnableAttr(Attribute.HAS_BROKEN)
            }
            if (!paramList.params.isEmpty() && !Skip(TokenKind.DOUBLE_ARROW) && !SkipCombinedDoubleArrow()) {
                if (!chainedAST[chainedAST.size - 1].TestAttr(Attribute.HAS_BROKEN)) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_double_arrow_in_lambda, Peek(),
                        ConvertToken(Peek())).Emit()
                }
                ConsumeUntilAny({ =>
                    return SeeingAny([TokenKind.NL, TokenKind.SEMI, TokenKind.DOUBLE_ARROW, TokenKind.RCURL]) ||
                        SeeingCombinator(combinedDoubleArrow)
                }, targetTokenConsumed: false)
                if (!Skip(TokenKind.DOUBLE_ARROW)) {
                    let _ = SkipCombinedDoubleArrow()
                }
            } else {
                if (paramList.params.isEmpty() && !isTailClosure) {
                    let hasDoubleArrow = lastToken.kind == TokenKind.DOUBLE_ARROW ||
                        Skip(TokenKind.DOUBLE_ARROW) || SkipCombinedDoubleArrow()
                    let hasWildard = Seeing([TokenKind.WILDCARD, TokenKind.DOUBLE_ARROW]) ||
                        Seeing([TokenKind.WILDCARD, TokenKind.COMMA]) ||
                        SeeingTokenAndCombinator(TokenKind.WILDCARD, combinedDoubleArrow)
                    if (!hasDoubleArrow && !hasWildard) {
                        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_double_arrow_in_lambda, Peek(),
                            ConvertToken(Peek())).Emit()
                    }
                }
                if (lastToken.kind == TokenKind.DOUBLE_ARROW || Skip(TokenKind.DOUBLE_ARROW) ||
                    SkipCombinedDoubleArrow()) {
                    funcBody.doubleArrowPos = lastToken.Begin()
                }
            }
            funcBody.begin = lastToken.Begin()
            funcBody.paramLists.add(paramList)
            let block = ParseExpressionOrDeclarations(ScopeKind.FUNC_BODY)
            funcBody.body = Some(block)
            funcBody.end = block.end
        }
        return funcBody
    }

    // C++: Parse/ParseAtom.cpp:1623-1640 ParserImpl::ParseBaseLambdaExpr.
    public func ParseBaseLambdaExpr(): LambdaExpr {
        let ret = LambdaExpr()
        ret.begin = lastToken.Begin()
        if (SeeingInvaildOperaterInLambdaExpr()) {
            Skip(TokenKind.IDENTIFIER)
            SkipKeyWordIdentifier()
            Peek()
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_ccd_in_lambda, Peek(), ConvertToken(Peek())).Emit()
            ConsumeUntilAny({ =>
                return SeeingAny([TokenKind.NL, TokenKind.SEMI, TokenKind.DOUBLE_ARROW, TokenKind.RCURL]) ||
                    SeeingCombinator(combinedDoubleArrow)
            }, targetTokenConsumed: false)
        }
        return ret
    }

    public func CheckCondition(expr: Expr): Bool {
        if (let Some(paren) <- (expr as ParenExpr)) {
            if (let Some(child) <- paren.expr) {
                return CheckCondition(child)
            }
            return false
        }
        if (expr.astKind == ASTKind.LET_PATTERN_DESTRUCTOR) {
            return true
        }
        if (let Some(binary) <- (expr as BinaryExpr)) {
            var hasSubCondition = false
            if (let Some(left) <- binary.leftExpr) {
                hasSubCondition = CheckCondition(left)
            }
            if (let Some(right) <- binary.rightExpr) {
                hasSubCondition = CheckCondition(right) || hasSubCondition
            }
            if (hasSubCondition && binary.op != TokenKind.AND && binary.op != TokenKind.OR) {
                diag.DiagnoseRefactor(DiagKindRefactor.parse_expected_if_let_andand, binary.operatorPos).Emit()
                binary.isBroken = true
            }
            return hasSubCondition
        }
        return false
    }
}
