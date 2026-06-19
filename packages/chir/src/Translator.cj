package cangjie_compiler::chir

import std.collection.*

import cangjie_compiler::ast.ASTKind
import cangjie_compiler::ast.ASTKindIndex
import cangjie_compiler::ast.ASTKindName
import cangjie_compiler::ast.ArrayExpr as AstArrayExpr
import cangjie_compiler::ast.ArrayLit as AstArrayLit
import cangjie_compiler::ast.AssignExpr as AstAssignExpr
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.BinaryExpr as AstBinaryExpr
import cangjie_compiler::ast.Block as AstBlock
import cangjie_compiler::ast.CallExpr as AstCallExpr
import cangjie_compiler::ast.ClassDecl as AstClassDecl
import cangjie_compiler::ast.ClassLikeDecl as AstClassLikeDecl
import cangjie_compiler::ast.ClassTy as AstClassTy
import cangjie_compiler::ast.ConstPattern as AstConstPattern
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.DoWhileExpr as AstDoWhileExpr
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.EnumPattern as AstEnumPattern
import cangjie_compiler::ast.EnumTy as AstEnumTy
import cangjie_compiler::ast.ExtendDecl as AstExtendDecl
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.ExceptTypePattern as AstExceptTypePattern
import cangjie_compiler::ast.ForInExpr as AstForInExpr
import cangjie_compiler::ast.ForInKind as AstForInKind
import cangjie_compiler::ast.FuncArg as AstFuncArg
import cangjie_compiler::ast.FuncBody as AstFuncBody
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.FuncTy as AstFuncTy
import cangjie_compiler::ast.GenericsTy as AstGenericsTy
import cangjie_compiler::ast.IfExpr as AstIfExpr
import cangjie_compiler::ast.InterfaceTy as AstInterfaceTy
import cangjie_compiler::ast.InterfaceDecl as AstInterfaceDecl
import cangjie_compiler::ast.JumpExpr as AstJumpExpr
import cangjie_compiler::ast.LambdaExpr as AstLambdaExpr
import cangjie_compiler::ast.LitConstExpr as AstLitConstExpr
import cangjie_compiler::ast.LitConstKind as AstLitConstKind
import cangjie_compiler::ast.MainDecl as AstMainDecl
import cangjie_compiler::ast.MatchExpr as AstMatchExpr
import cangjie_compiler::ast.MemberAccess as AstMemberAccess
import cangjie_compiler::ast.NameReferenceExpr as AstNameReferenceExpr
import cangjie_compiler::ast.Node as AstNode
import cangjie_compiler::ast.Pattern as AstPattern
import cangjie_compiler::ast.PropDecl as AstPropDecl
import cangjie_compiler::ast.RefExpr as AstRefExpr
import cangjie_compiler::ast.ReturnExpr as AstReturnExpr
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.StructTy as AstStructTy
import cangjie_compiler::ast.SubscriptExpr as AstSubscriptExpr
import cangjie_compiler::ast.TokenKind as AstTokenKind
import cangjie_compiler::ast.TokenKindValue as AstTokenKindValue
import cangjie_compiler::ast.Ty as AstTy
import cangjie_compiler::ast.TupleLit as AstTupleLit
import cangjie_compiler::ast.TuplePattern as AstTuplePattern
import cangjie_compiler::ast.TryExpr as AstTryExpr
import cangjie_compiler::ast.TypePattern as AstTypePattern
import cangjie_compiler::ast.TypeConvExpr as AstTypeConvExpr
import cangjie_compiler::ast.ThrowExpr as AstThrowExpr
import cangjie_compiler::ast.UnaryExpr as AstUnaryExpr
import cangjie_compiler::ast.VarDecl as AstVarDecl
import cangjie_compiler::ast.VarWithPatternDecl as AstVarWithPatternDecl
import cangjie_compiler::ast.VarOrEnumPattern as AstVarOrEnumPattern
import cangjie_compiler::ast.VarPattern as AstVarPattern
import cangjie_compiler::ast.WildcardPattern as AstWildcardPattern
import cangjie_compiler::ast.WhileExpr as AstWhileExpr

private class FaithfulLeftValueInfo {
    public let base: Value
    public let path: ArrayList<String> = ArrayList<String>()

    public init(base: Value, path: ArrayList<String>) {
        this.base = base
        for (item in path) {
            this.path.add(item)
        }
    }
}

private class FaithfulLoopTarget {
    public let continueBlock: Block
    public let breakBlock: Block

    public init(continueBlock: Block, breakBlock: Block) {
        this.continueBlock = continueBlock
        this.breakBlock = breakBlock
    }
}

public class Translator {
    private let builder: CHIRBuilder
    private let chirTy: CHIRType
    private let globalSymbolTable: FaithfulAST2CHIRNodeMap
    private let localValSymbolTable: FaithfulAST2CHIRNodeMap = FaithfulAST2CHIRNodeMap()
    private var currentBlock: Option<Block> = None
    private var currentFunc: Option<Function> = None
    private var currentLambda: Option<Lambda> = None
    private var currentAstFuncDecl: Option<AstFuncDecl> = None
    private var lambdaCounter: UInt64 = 0u64
    private var delayExitSignal: Option<Value> = None
    private let blockGroupStack: ArrayList<BlockGroup> = ArrayList<BlockGroup>()
    private let loopTargetStack: ArrayList<FaithfulLoopTarget> = ArrayList<FaithfulLoopTarget>()
    private let tryCatchContext: ArrayList<Block> = ArrayList<Block>()
    private let tryBodyContext: ArrayList<AstTryExpr> = ArrayList<AstTryExpr>()

    public init(builder: CHIRBuilder, chirTy: CHIRType, globalSymbolTable: FaithfulAST2CHIRNodeMap) {
        this.builder = builder
        this.chirTy = chirTy
        this.globalSymbolTable = globalSymbolTable
    }

    public func TranslateGlobalVarInitializer(fn: Function, decl: AstVarDecl, globalVar: GlobalVar): Unit {
        let body = fn.GetBody() ??
            throw IllegalStateException("faithful AST2CHIR global initializer function has no body")
        let entry = body.GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR global initializer function has no entry block")
        let savedFunc = currentFunc
        let savedBlock = currentBlock
        currentFunc = fn
        currentBlock = entry
        blockGroupStack.add(body)
        let initExpr = RequireExpr(decl.initializer, "global variable initializer")
        let initValue = Translator.TranslateASTNode(initExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR global variable initializer produced no value")
        builder.CreateStore(initValue, globalVar, CurrentBlock())
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateExit(None, CurrentBlock())
        }
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        currentFunc = savedFunc
        currentBlock = savedBlock
    }

    public static func TranslateASTNode(node: AstNode, trans: Translator): Option<Value> {
        let nodePtr = GetDesugaredExpr(node)
        return match (nodePtr.astKind) {
            case ASTKind.MAIN_DECL => trans.Visit(RequireNodeAsMainDecl(nodePtr))
            case ASTKind.FUNC_DECL => trans.Visit(RequireNodeAsFuncDecl(nodePtr))
            case ASTKind.STRUCT_DECL => trans.Visit(RequireNodeAsStructDecl(nodePtr))
            case ASTKind.CLASS_DECL => trans.Visit(RequireNodeAsClassDecl(nodePtr))
            case ASTKind.INTERFACE_DECL => trans.Visit(RequireNodeAsInterfaceDecl(nodePtr))
            case ASTKind.ENUM_DECL => trans.Visit(RequireNodeAsEnumDecl(nodePtr))
            case ASTKind.EXTEND_DECL => trans.Visit(RequireNodeAsExtendDecl(nodePtr))
            case ASTKind.VAR_DECL => trans.Visit(RequireNodeAsVarDecl(nodePtr))
            case ASTKind.BLOCK => trans.Visit(RequireNodeAsBlock(nodePtr))
            case ASTKind.LIT_CONST_EXPR => trans.Visit(RequireNodeAsLitConstExpr(nodePtr))
            case ASTKind.REF_EXPR => trans.Visit(RequireNodeAsRefExpr(nodePtr))
            case ASTKind.RETURN_EXPR => trans.Visit(RequireNodeAsReturnExpr(nodePtr))
            case ASTKind.BINARY_EXPR => trans.Visit(RequireNodeAsBinaryExpr(nodePtr))
            case ASTKind.UNARY_EXPR => trans.Visit(RequireNodeAsUnaryExpr(nodePtr))
            case ASTKind.CALL_EXPR => trans.Visit(RequireNodeAsCallExpr(nodePtr))
            case ASTKind.IF_EXPR => trans.Visit(RequireNodeAsIfExpr(nodePtr))
            case ASTKind.ASSIGN_EXPR => trans.Visit(RequireNodeAsAssignExpr(nodePtr))
            case ASTKind.MEMBER_ACCESS => trans.Visit(RequireNodeAsMemberAccess(nodePtr))
            case ASTKind.WHILE_EXPR => trans.Visit(RequireNodeAsWhileExpr(nodePtr))
            case ASTKind.DO_WHILE_EXPR => trans.Visit(RequireNodeAsDoWhileExpr(nodePtr))
            case ASTKind.FOR_IN_EXPR => trans.Visit(RequireNodeAsForInExpr(nodePtr))
            case ASTKind.JUMP_EXPR => trans.Visit(RequireNodeAsJumpExpr(nodePtr))
            case ASTKind.LAMBDA_EXPR => trans.Visit(RequireNodeAsLambdaExpr(nodePtr))
            case ASTKind.MATCH_EXPR => trans.Visit(RequireNodeAsMatchExpr(nodePtr))
            case ASTKind.TRY_EXPR => trans.Visit(RequireNodeAsTryExpr(nodePtr))
            case ASTKind.THROW_EXPR => trans.Visit(RequireNodeAsThrowExpr(nodePtr))
            case ASTKind.ARRAY_LIT => trans.Visit(RequireNodeAsArrayLit(nodePtr))
            case ASTKind.ARRAY_EXPR => trans.Visit(RequireNodeAsArrayExpr(nodePtr))
            case ASTKind.TUPLE_LIT => trans.Visit(RequireNodeAsTupleLit(nodePtr))
            case ASTKind.SUBSCRIPT_EXPR => trans.Visit(RequireNodeAsSubscriptExpr(nodePtr))
            case ASTKind.TYPE_CONV_EXPR => trans.Visit(RequireNodeAsTypeConvExpr(nodePtr))
            case ASTKind.VAR_WITH_PATTERN_DECL => trans.Visit(RequireNodeAsVarWithPatternDecl(nodePtr))
            case _ => throw IllegalArgumentException(
                "not yet ported in faithful AST2CHIR: ${ASTKindName(nodePtr.astKind)}")
        }
    }

    public static func GetDesugaredExpr(node: AstNode): AstNode {
        var nodePtr = node
        var keepGoing = true
        while (keepGoing) {
            keepGoing = false
            if (let Some(expr) <- (nodePtr as AstExpr)) {
                if (let Some(desugar) <- expr.desugarExpr) {
                    nodePtr = desugar
                    keepGoing = true
                }
            }
        }
        return nodePtr
    }

    public func TranslateType(ty: AstTy): Type {
        return chirTy.TranslateType(ty)
    }

    public func Visit(funcDecl: AstFuncDecl): Option<Value> {
        let value = globalSymbolTable.Get(funcDecl)
        let fn = (value as Function) ??
            throw IllegalStateException("faithful AST2CHIR function cache is not a Function: ${funcDecl.identifier.Val()}")
        if (let None <- funcDecl.funcBody) {
            return fn
        }
        let body = EnsureFuncBody(fn)
        blockGroupStack.add(body)
        let savedAstFuncDecl = currentAstFuncDecl
        currentFunc = fn
        currentAstFuncDecl = funcDecl
        let savedBlock = currentBlock
        let entry = body.GetEntryBlock() ?? builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        currentBlock = entry
        BindFuncParams(funcDecl, fn)
        if (let Some(funcBody) <- funcDecl.funcBody) {
            if (let Some(astBody) <- funcBody.body) {
                let result = Translator.TranslateASTNode(astBody, this)
                if (CurrentBlock().GetTerminator().isNone()) {
                    EmitImplicitFunctionExit(fn, result)
                }
            } else if (CurrentBlock().GetTerminator().isNone()) {
                builder.CreateExit(None, CurrentBlock())
            }
        }
        currentBlock = savedBlock
        currentFunc = None
        currentAstFuncDecl = savedAstFuncDecl
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        return fn
    }

    public func Visit(mainDecl: AstMainDecl): Option<Value> {
        let value = globalSymbolTable.Get(mainDecl)
        let fn = (value as Function) ??
            throw IllegalStateException("faithful AST2CHIR main cache is not a Function")
        let funcBody = match (mainDecl.funcBody) {
            case Some(value) => value
            case None =>
                if (let Some(desugared) <- mainDecl.GetDesugarDecl()) {
                    match (desugared.funcBody) {
                        case Some(value) => value
                        case None => return fn
                    }
                } else {
                    return fn
                }
        }
        let body = EnsureFuncBody(fn)
        blockGroupStack.add(body)
        let savedAstFuncDecl = currentAstFuncDecl
        currentFunc = fn
        currentAstFuncDecl = None
        let savedBlock = currentBlock
        let entry = body.GetEntryBlock() ?? builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        currentBlock = entry
        if (let Some(astBody) <- funcBody.body) {
            let result = Translator.TranslateASTNode(astBody, this)
            if (CurrentBlock().GetTerminator().isNone()) {
                EmitImplicitFunctionExit(fn, result)
            }
        } else if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateExit(None, CurrentBlock())
        }
        currentBlock = savedBlock
        currentFunc = None
        currentAstFuncDecl = savedAstFuncDecl
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        return fn
    }

    public func Visit(structDecl: AstStructDecl): Option<Value> {
        let def = RequireStructDef(chirTy.GetGlobalNominalCache(structDecl))
        if (let Some(astTy) <- structDecl.GetTy()) {
            def.SetType(RequireStructType(chirTy.TranslateType(astTy)))
        }
        for (member in structDecl.GetMemberDeclPtrs()) {
            TranslateMemberDecl(def, member)
        }
        return None
    }

    public func Visit(classDecl: AstClassDecl): Option<Value> {
        let def = RequireClassDef(chirTy.GetGlobalNominalCache(classDecl))
        TranslateClassLikeDecl(def, classDecl)
        return None
    }

    public func Visit(interfaceDecl: AstInterfaceDecl): Option<Value> {
        let def = RequireClassDef(chirTy.GetGlobalNominalCache(interfaceDecl))
        def.EnableAttr(Attribute.ABSTRACT)
        TranslateClassLikeDecl(def, interfaceDecl)
        return None
    }

    public func Visit(enumDecl: AstEnumDecl): Option<Value> {
        let def = RequireEnumDef(chirTy.GetGlobalNominalCache(enumDecl))
        if (let Some(astTy) <- enumDecl.GetTy()) {
            def.SetType(RequireEnumType(chirTy.TranslateType(astTy)))
        }
        for (ctor in enumDecl.constructors) {
            let payloadTypes = ArrayList<Type>()
            if (let Some(funcCtor) <- (ctor as AstFuncDecl)) {
                if (let Some(ctorTy) <- funcCtor.GetTy()) {
                    if (let Some(funcTy) <- (ctorTy as AstFuncTy)) {
                        for (paramTy in funcTy.paramTys) {
                            payloadTypes.add(chirTy.TranslateType(paramTy))
                        }
                    }
                }
            }
            def.AddCtor(EnumCtorInfo(ctor.identifier.Val(), payloadTypes))
        }
        for (member in enumDecl.members) {
            TranslateMemberDecl(def, member)
        }
        return None
    }

    public func Visit(extendDecl: AstExtendDecl): Option<Value> {
        let def = RequireExtendDef(chirTy.GetGlobalNominalCache(extendDecl))
        if (let Some(astTy) <- extendDecl.GetTy()) {
            def.SetExtendedType(chirTy.TranslateType(astTy))
        }
        for (member in extendDecl.members) {
            TranslateMemberDecl(def, member)
        }
        return None
    }

    public func Visit(varDecl: AstVarDecl): Option<Value> {
        if (currentBlock.isNone()) {
            return globalSymbolTable.TryGet(varDecl)
        }
        let valueTy = chirTy.TranslateType(RequireAstTy(varDecl))
        let slotTy = builder.context.GetRefTy(valueTy)
        let slot = builder.CreateAllocate(slotTy, valueTy, CurrentBlock())
        let slotValue = RequireResult(slot)
        slotValue.SetSrcCodeIdentifier(varDecl.identifier.Val())
        localValSymbolTable.Set(varDecl, slotValue)
        if (let Some(initializerExpr) <- varDecl.initializer) {
            if (let Some(initValue) <- Translator.TranslateASTNode(initializerExpr, this)) {
                builder.CreateStore(initValue, slotValue, CurrentBlock())
            }
        }
        return slotValue
    }

    public func Visit(block: AstBlock): Option<Value> {
        if (block.body.isEmpty()) {
            return None
        }
        var idx: Int64 = 0
        while (idx + 1 < block.body.size) {
            TranslateBlockNodeToDiscarded(block.body[idx])
            idx++
        }
        return TranslateBlockNodeAsValue(block.body[idx])
    }

    public func Visit(expr: AstLitConstExpr): Option<Value> {
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let literal = TranslateLitConstant(expr)
        return RequireResult(builder.CreateConstant(resultTy, literal, CurrentBlock()))
    }

    public func Visit(expr: AstRefExpr): Option<Value> {
        if (expr.isThis || expr.isSuper) {
            return GetCurrentThisObject()
        }
        if (let Some(target) <- expr.ref.target) {
            if (target.TestAttr(AstAttribute.ENUM_CONSTRUCTOR)) {
                return TranslateEnumCtorRef(target, RequireAstTy(expr))
            }
            if (let Some(varDecl) <- (target as AstVarDecl)) {
                if (IsInstanceMember(varDecl)) {
                    let leftValueInfo = TranslateInstanceFieldRefAsLeftValue(varDecl)
                    return LoadLeftValue(leftValueInfo, chirTy.TranslateType(RequireAstTy(expr)))
                }
            }
            let value = GetSymbolTable(target)
            return GetDerefedValue(value)
        }
        throw IllegalStateException("faithful AST2CHIR RefExpr has no Sema target: ${expr.ref.identifier.Val()}")
    }

    public func Visit(expr: AstReturnExpr): Option<Value> {
        if (let Some(retExpr) <- expr.expr) {
            let value = Translator.TranslateASTNode(retExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR return expression produced no value")
            if (currentLambda.isSome()) {
                EmitLambdaReturn(Some(value))
                return None
            }
            StoreReturnValueIfNeeded(CurrentFunction(), value)
            UpdateDelayExitSignalForReturnIfNeeded()
            builder.CreateExit(None, CurrentBlock())
            return None
        }
        if (currentLambda.isSome()) {
            EmitLambdaReturn(None)
            return None
        }
        UpdateDelayExitSignalForReturnIfNeeded()
        builder.CreateExit(None, CurrentBlock())
        return None
    }

    public func Visit(expr: AstBinaryExpr): Option<Value> {
        let lhs = Translator.TranslateASTNode(RequireExpr(expr.leftExpr, "binary lhs"), this) ??
            throw IllegalStateException("faithful AST2CHIR binary lhs produced no value")
        if (expr.op == AstTokenKind.AND) {
            return TransShortCircuitAnd(lhs, RequireExpr(expr.rightExpr, "binary rhs"))
        }
        if (expr.op == AstTokenKind.OR) {
            return TransShortCircuitOr(lhs, RequireExpr(expr.rightExpr, "binary rhs"))
        }
        let rhs = Translator.TranslateASTNode(RequireExpr(expr.rightExpr, "binary rhs"), this) ??
            throw IllegalStateException("faithful AST2CHIR binary rhs produced no value")
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let binary = builder.CreateBinaryExpression(ToCHIRBinaryOp(expr.op), resultTy, lhs, rhs, CurrentBlock())
        return RequireResult(binary)
    }

    public func Visit(expr: AstUnaryExpr): Option<Value> {
        let operand = Translator.TranslateASTNode(RequireExpr(expr.expr, "unary operand"), this) ??
            throw IllegalStateException("faithful AST2CHIR unary operand produced no value")
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let unary = builder.CreateUnaryExpression(ToCHIRUnaryOp(expr.op), resultTy, operand, CurrentBlock())
        return RequireResult(unary)
    }

    public func Visit(expr: AstCallExpr): Option<Value> {
        if (IsFunctionValueCall(expr)) {
            return Some(TranslateFunctionValueCall(expr))
        }
        let calleeDecl = expr.resolvedFunction ?? ResolveCalleeFromBase(expr)
        if (calleeDecl.TestAttr(AstAttribute.ENUM_CONSTRUCTOR)) {
            return TranslateEnumCtorCall(expr, calleeDecl)
        }
        if (IsStructOrClassCtorCall(expr, calleeDecl)) {
            return TranslateStructOrClassCtorCall(expr, calleeDecl)
        }
        if (calleeDecl.IsMemberDecl() && !calleeDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            return TranslateMemberFuncCall(expr, calleeDecl)
        }
        let callee = globalSymbolTable.Get(calleeDecl)
        let argValues = ArrayList<Value>()
        let expectedParamTys = FuncParamTypes(expr, calleeDecl)
        var idx: Int64 = 0
        for (arg in expr.args) {
            if (let Some(argExpr) <- arg.expr) {
                var value = Translator.TranslateASTNode(argExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR call arg produced no value")
                if (idx < expectedParamTys.size) {
                    value = CoerceValueForExpectedType(value, expectedParamTys[idx])
                }
                argValues.add(value)
            }
            idx++
        }
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        return CreateApplyMaybeWithException(resultTy, callee, FuncCallContext(args: argValues,
            instTypeArgs: TranslateFuncInstArgs(expr, calleeDecl)))
    }

    public func Visit(expr: AstLambdaExpr): Option<Value> {
        let funcBody = expr.funcBody ??
            throw IllegalStateException("faithful AST2CHIR LambdaExpr has no FuncBody")
        let funcTy = RequireFuncType(chirTy.TranslateType(RequireAstTy(expr)))
        let parentFunc = CurrentFunction()
        let body = builder.CreateBlockGroup(parentFunc)
        let lambda = builder.CreateLambda(funcTy, funcTy, CurrentBlock(), isLocalFunc: true,
            identifier: LambdaIdentifier(expr), srcCodeIdentifier: "$lambda")
        lambda.InitBody(body)
        BindLambdaParams(funcBody, lambda, funcTy)

        let savedBlock = currentBlock
        let savedLambda = currentLambda
        blockGroupStack.add(body)
        currentLambda = lambda
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        currentBlock = entry
        let retSlot = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(funcTy.GetReturnType()),
            funcTy.GetReturnType(), entry))
        lambda.SetReturnValue(retSlot)
        if (let Some(astBody) <- funcBody.body) {
            let result = Translator.TranslateASTNode(astBody, this)
            if (CurrentBlock().GetTerminator().isNone()) {
                EmitImplicitLambdaExit(lambda, result)
            }
        } else if (CurrentBlock().GetTerminator().isNone()) {
            EmitImplicitLambdaExit(lambda, None)
        }
        currentBlock = savedBlock
        currentLambda = savedLambda
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        if (let Some(result) <- lambda.GetResult()) {
            return Some(result)
        }
        return None
    }

    public func Visit(expr: AstIfExpr): Option<Value> {
        let cond = Translator.TranslateASTNode(RequireExpr(expr.condExpr, "if condition"), this) ??
            throw IllegalStateException("faithful AST2CHIR if condition produced no value")
        let parentBlock = CurrentBlock()
        let group = parentBlock.GetParentBlockGroup() ??
            throw IllegalStateException("faithful AST2CHIR if requires parent block group")
        let thenBlock = builder.CreateBlock(group)
        let elseBlock = builder.CreateBlock(group)
        let joinBlock = builder.CreateBlock(group)
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let resultLoc: Option<Value> = if (resultTy.IsUnit() || resultTy.IsNothing()) {
            None
        } else {
            RequireResult(builder.CreateAllocate(builder.context.GetRefTy(resultTy), resultTy, parentBlock))
        }
        builder.CreateBranch(cond, thenBlock, elseBlock, parentBlock)

        currentBlock = thenBlock
        let thenValue = Translator.TranslateASTNode(RequireBlock(expr.thenBody, "if then body"), this)
        StoreIfResult(resultLoc, thenValue)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(joinBlock, CurrentBlock())
        }

        currentBlock = elseBlock
        let elseValue: Option<Value> = if (let Some(elseExpr) <- expr.elseBody) {
            Translator.TranslateASTNode(elseExpr, this)
        } else {
            None
        }
        StoreIfResult(resultLoc, elseValue)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(joinBlock, CurrentBlock())
        }

        currentBlock = joinBlock
        if (let Some(location) <- resultLoc) {
            return RequireResult(builder.CreateLoad(resultTy, location, joinBlock))
        }
        return None
    }

    public func Visit(expr: AstAssignExpr): Option<Value> {
        let leftExpr = RequireExpr(expr.leftValue, "assign left value")
        let rightExpr = RequireExpr(expr.rightExpr, "assign right expression")
        if (leftExpr.astKind == ASTKind.WILDCARD_EXPR) {
            let _ = Translator.TranslateASTNode(rightExpr, this)
            return None
        }
        if (let Some(subscriptExpr) <- (leftExpr as AstSubscriptExpr)) {
            if (!subscriptExpr.isTupleAccess) {
                if (subscriptExpr.IsVArrayAccess()) {
                    TranslateVArrayAssign(expr, subscriptExpr, rightExpr)
                    return None
                }
                if (TranslateSubscriptSetterAssign(expr, subscriptExpr, rightExpr)) {
                    return None
                }
            }
        }
        if (IsCompoundAssignOp(expr.op)) {
            return TranslateCompoundAssign(expr, leftExpr, rightExpr)
        }
        return TranslateTrivialAssign(expr, leftExpr, rightExpr)
    }

    public func Visit(expr: AstMemberAccess): Option<Value> {
        let target = ResolveMemberAccessTarget(expr, "faithful AST2CHIR MemberAccess")
        if (target.TestAttr(AstAttribute.ENUM_CONSTRUCTOR)) {
            return TranslateEnumCtorRef(target, RequireAstTy(expr))
        }
        if (target.TestAttr(AstAttribute.STATIC) || IsPackageMemberAccess(expr)) {
            return TranslateStaticTargetOrPackageMemberAccess(expr, target)
        }
        if (IsInstanceMember(target)) {
            if (let Some(propDecl) <- (target as AstPropDecl)) {
                return TranslatePropertyGetter(expr, propDecl)
            }
            if (let Some(_) <- (target as AstVarDecl)) {
                let leftValueInfo = TranslateMemberAccessAsLeftValue(expr)
                return LoadLeftValue(leftValueInfo, MemberAccessValueType(expr, target))
            }
            if (let Some(_) <- (target as AstFuncDecl)) {
                throw IllegalArgumentException(
                    "not yet ported in faithful AST2CHIR: member method reference lambda wrapper")
            }
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: unsupported member access")
    }

    private func TranslatePropertyGetter(expr: AstMemberAccess, propDecl: AstPropDecl): Value {
        if (propDecl.getters.isEmpty()) {
            throw IllegalStateException("faithful AST2CHIR property has no getter: ${propDecl.identifier.Val()}")
        }
        let getter = propDecl.getters[0]
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let callee = GetSymbolTable(getter)
        let thisObj = TranslatePropertyGetterThisObject(expr, getter, callee)
        let args = ArrayList<Value>()
        args.add(thisObj)
        return CreateApplyMaybeWithException(resultTy, callee, FuncCallContext(args: args, thisType: thisObj.GetType()))
    }

    private func TranslatePropertyGetterThisObject(expr: AstMemberAccess, getter: AstFuncDecl, callee: Value): Value {
        if (let Some(baseExpr) <- expr.baseExpr) {
            let baseTy = chirTy.TranslateType(RequireAstTy(baseExpr))
            if (PropertyGetterNeedsAddress(callee)) {
                return AddressOfLeftValue(TranslateExprAsLeftValue(baseExpr), baseTy)
            }
            return Translator.TranslateASTNode(baseExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR property getter base produced no value")
        }
        if (let Some(_) <- getter.outerDecl) {
            return GetCurrentThisObject()
        }
        throw IllegalStateException("faithful AST2CHIR property getter has no receiver")
    }

    private func PropertyGetterNeedsAddress(callee: Value): Bool {
        if (let Some(calleeTy) <- callee.GetType()) {
            if (let Some(funcTy) <- (calleeTy as FuncType)) {
                return funcTy.GetNumOfParams() > 0 && funcTy.GetParamType(0).IsRef()
            }
        }
        return false
    }

    public func Visit(expr: AstWhileExpr): Option<Value> {
        let parentBlock = CurrentBlock()
        let group = RequireParentBlockGroup(parentBlock, "while")
        let conditionBlock = builder.CreateBlock(group)
        let bodyBlock = builder.CreateBlock(group)
        let endBlock = builder.CreateBlock(group)
        builder.CreateGoTo(conditionBlock, parentBlock)

        loopTargetStack.add(FaithfulLoopTarget(conditionBlock, endBlock))
        currentBlock = conditionBlock
        let condValue = Translator.TranslateASTNode(RequireExpr(expr.condExpr, "while condition"), this) ??
            throw IllegalStateException("faithful AST2CHIR while condition produced no value")
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateBranch(condValue, bodyBlock, endBlock, CurrentBlock())
        }

        currentBlock = bodyBlock
        let _ = Translator.TranslateASTNode(RequireBlock(expr.body, "while body"), this)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(conditionBlock, CurrentBlock())
        }
        loopTargetStack.remove(at: loopTargetStack.size - 1)
        currentBlock = endBlock
        return None
    }

    public func Visit(expr: AstDoWhileExpr): Option<Value> {
        let parentBlock = CurrentBlock()
        let group = RequireParentBlockGroup(parentBlock, "do-while")
        let bodyBlock = builder.CreateBlock(group)
        let conditionBlock = builder.CreateBlock(group)
        let endBlock = builder.CreateBlock(group)
        builder.CreateGoTo(bodyBlock, parentBlock)

        loopTargetStack.add(FaithfulLoopTarget(conditionBlock, endBlock))
        currentBlock = bodyBlock
        let _ = Translator.TranslateASTNode(RequireBlock(expr.body, "do-while body"), this)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(conditionBlock, CurrentBlock())
        }

        currentBlock = conditionBlock
        let condValue = Translator.TranslateASTNode(RequireExpr(expr.condExpr, "do-while condition"), this) ??
            throw IllegalStateException("faithful AST2CHIR do-while condition produced no value")
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateBranch(condValue, bodyBlock, endBlock, CurrentBlock())
        }
        loopTargetStack.remove(at: loopTargetStack.size - 1)
        currentBlock = endBlock
        return None
    }

    public func Visit(expr: AstForInExpr): Option<Value> {
        return match (expr.forInKind) {
            case AstForInKind.FORIN_RANGE => TranslateForInRange(expr)
            case AstForInKind.FORIN_ITER => TranslateForInIter(expr)
            case AstForInKind.FORIN_STRING =>
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: ForInExpr string desugar")
            case AstForInKind.FORIN_INVALID =>
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: ForInExpr invalid/closed-range-one")
        }
    }

    public func Visit(expr: AstJumpExpr): Option<Value> {
        if (let Some(refLoop) <- expr.refLoop) {
            if (refLoop.astKind == ASTKind.FOR_IN_EXPR && delayExitSignal.isSome()) {
                UpdateDelayExitSignal(if (expr.isBreak) {
                    CalculateDelayExitLevelForBreak()
                } else {
                    CalculateDelayExitLevelForContinue()
                })
                builder.CreateExit(None, CurrentBlock())
                let group = RequireParentBlockGroup(CurrentBlock(), "jump continuation")
                currentBlock = builder.CreateBlock(group)
                return None
            }
        }
        if (loopTargetStack.isEmpty()) {
            throw IllegalStateException("faithful AST2CHIR JumpExpr outside loop")
        }
        let target = loopTargetStack[loopTargetStack.size - 1]
        let destination = if (expr.isBreak) { target.breakBlock } else { target.continueBlock }
        builder.CreateGoTo(destination, CurrentBlock())
        let group = RequireParentBlockGroup(CurrentBlock(), "jump continuation")
        currentBlock = builder.CreateBlock(group)
        return None
    }

    public func Visit(expr: AstMatchExpr): Option<Value> {
        let matchTy = chirTy.TranslateType(RequireAstTy(expr))
        let resultLoc: Option<Value> = if (matchTy.IsUnit() || matchTy.IsNothing()) {
            None
        } else {
            RequireResult(builder.CreateAllocate(builder.context.GetRefTy(matchTy), matchTy, CurrentBlock()))
        }
        if (expr.matchMode) {
            TranslateMatchWithSelector(expr, resultLoc)
        } else {
            TranslateConditionMatches(expr, resultLoc)
        }
        if (let Some(loc) <- resultLoc) {
            return RequireResult(builder.CreateLoad(matchTy, loc, CurrentBlock()))
        }
        return None
    }

    public func Visit(expr: AstTryExpr): Option<Value> {
        if (!expr.resourceSpec.isEmpty() || !expr.handlers.isEmpty()) {
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: try-with-resources/try-handle")
        }
        if (expr.catchBlocks.isEmpty() && expr.finallyBlock.isNone()) {
            throw IllegalStateException("faithful AST2CHIR TryExpr has neither catch nor finally")
        }
        let group = RequireParentBlockGroup(CurrentBlock(), "try")
        let tryTy = chirTy.TranslateType(RequireAstTy(expr))
        let resultLoc: Option<Value> = if (tryTy.IsUnit() || tryTy.IsNothing()) {
            None
        } else {
            RequireResult(builder.CreateAllocate(builder.context.GetRefTy(tryTy), tryTy, CurrentBlock()))
        }
        let hasFinally = expr.finallyBlock.isSome()
        let finalEndBlock = builder.CreateBlock(group)
        let normalEndBlock = if (hasFinally) { builder.CreateBlock(group) } else { finalEndBlock }
        let exceptionBlock = builder.CreateBlock(group)

        tryBodyContext.add(expr)
        tryCatchContext.add(exceptionBlock)
        let tryValue = Translator.TranslateASTNode(RequireBlock(expr.tryBlock, "try block"), this)
        StoreTryResult(resultLoc, tryValue)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(normalEndBlock, CurrentBlock())
        }
        tryCatchContext.remove(at: tryCatchContext.size - 1)

        var pendingExceptionBlock: Option<Block> = exceptionBlock
        if (!expr.catchBlocks.isEmpty()) {
            currentBlock = exceptionBlock
            exceptionBlock.SetExceptions(GetExceptionsForTry(expr))
            pendingExceptionBlock = TranslateCatchBlocks(expr, resultLoc, normalEndBlock)
        } else {
            exceptionBlock.SetExceptions(ArrayList<ClassType>())
        }

        if (hasFinally) {
            let finallyBlock = expr.finallyBlock.getOrThrow()
            TranslateFinally(finallyBlock, pendingExceptionBlock ?? exceptionBlock, normalEndBlock, finalEndBlock)
        }

        tryBodyContext.remove(at: tryBodyContext.size - 1)
        currentBlock = finalEndBlock
        if (HasTypeOfNothing(expr)) {
            return None
        }
        if (let Some(loc) <- resultLoc) {
            return RequireResult(builder.CreateLoad(tryTy, loc, CurrentBlock()))
        }
        return None
    }

    public func Visit(expr: AstThrowExpr): Option<Value> {
        let thrownExpr = RequireExpr(expr.expr, "throw operand")
        let thrownValue = Translator.TranslateASTNode(thrownExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR throw operand produced no value")
        if (let Some(exceptionBlock) <- CurrentTryCatchBlock()) {
            builder.CreateRaiseException(thrownValue, exceptionBlock, CurrentBlock())
        } else {
            builder.CreateRaiseException(thrownValue, CurrentBlock())
        }
        let group = RequireParentBlockGroup(CurrentBlock(), "throw continuation")
        currentBlock = builder.CreateBlock(group)
        return None
    }

    public func Visit(expr: AstArrayLit): Option<Value> {
        let arrayTy = chirTy.TranslateType(RequireAstTy(expr))
        if (arrayTy.IsVArray()) {
            let elements = ArrayList<Value>()
            for (child in expr.children) {
                let element = Translator.TranslateASTNode(child, this) ??
                    throw IllegalStateException("faithful AST2CHIR ArrayLit element produced no value")
                elements.add(element)
            }
            return RequireResult(builder.CreateVArray(arrayTy, elements, CurrentBlock()))
        }
        if (arrayTy.IsStructArray()) {
            return TranslateStructArrayLit(expr, RequireStructType(arrayTy))
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: unsupported ArrayLit type")
    }

    public func Visit(expr: AstArrayExpr): Option<Value> {
        let arrayTy = chirTy.TranslateType(RequireAstTy(expr))
        if (expr.isValueArray || arrayTy.IsVArray()) {
            return TranslateVArrayExpr(expr, RequireVArrayType(arrayTy))
        }
        let rawArrayTy = RequireRawArrayType(arrayTy.StripAllRefs())
        if (expr.args.isEmpty()) {
            let sizeValue = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(0),
                CurrentBlock()))
            let rawArrayRef = RequireResult(builder.CreateRawArrayAllocate(arrayTy, rawArrayTy.GetElementType(),
                sizeValue, CurrentBlock()))
            builder.CreateRawArrayLiteralInit(builder.context.GetUnitTy(), rawArrayRef, ArrayList<Value>(),
                CurrentBlock())
            return rawArrayRef
        }
        if (expr.args.size == 1) {
            return TranslateRawArrayByCollection(expr, arrayTy, rawArrayTy)
        }
        if (expr.args.size == 2 && expr.initFunc.isNone()) {
            let sizeValue = Translator.TranslateASTNode(RequireFuncArgExpr(expr.args[0], "RawArray size"), this) ??
                throw IllegalStateException("faithful AST2CHIR RawArray size produced no value")
            let initValue = Translator.TranslateASTNode(RequireFuncArgExpr(expr.args[1], "RawArray init value"), this) ??
                throw IllegalStateException("faithful AST2CHIR RawArray init value produced no value")
            let rawArrayRef = RequireResult(builder.CreateRawArrayAllocate(arrayTy, rawArrayTy.GetElementType(),
                sizeValue, CurrentBlock()))
            builder.CreateRawArrayInitByValue(builder.context.GetUnitTy(), rawArrayRef, sizeValue, initValue,
                CurrentBlock())
            return rawArrayRef
        }
        if (expr.args.size == 2) {
            return TranslateRawArrayByLambda(expr, arrayTy, rawArrayTy)
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: unsupported RawArray ArrayExpr arity")
    }

    public func Visit(expr: AstTupleLit): Option<Value> {
        let values = ArrayList<Value>()
        for (child in expr.children) {
            let value = Translator.TranslateASTNode(child, this) ??
                throw IllegalStateException("faithful AST2CHIR TupleLit element produced no value")
            values.add(value)
        }
        return RequireResult(builder.CreateTuple(chirTy.TranslateType(RequireAstTy(expr)), values, CurrentBlock()))
    }

    public func Visit(expr: AstSubscriptExpr): Option<Value> {
        if (expr.indexExprs.size != 1) {
            throw IllegalArgumentException("faithful AST2CHIR SubscriptExpr expects exactly one index")
        }
        if (expr.isTupleAccess) {
            return TranslateTupleAccess(expr)
        }
        if (expr.IsVArrayAccess()) {
            return TranslateVArrayAccess(expr)
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: non-tuple/non-VArray subscript")
    }

    public func Visit(expr: AstTypeConvExpr): Option<Value> {
        let operand = Translator.TranslateASTNode(RequireExpr(expr.expr, "type conversion operand"), this) ??
            throw IllegalStateException("faithful AST2CHIR type conversion operand produced no value")
        return RequireResult(builder.CreateTypeCast(chirTy.TranslateType(RequireAstTy(expr)), operand, CurrentBlock()))
    }

    public func Visit(decl: AstVarWithPatternDecl): Option<Value> {
        if (currentBlock.isNone()) {
            return globalSymbolTable.TryGet(decl)
        }
        let initValue: Option<Value> = if (let Some(initializer) <- decl.initializer) {
            Translator.TranslateASTNode(initializer, this)
        } else {
            None
        }
        FlattenVarWithPatternDecl(RequirePattern(decl.irrefutablePattern, "var-with-pattern pattern"), initValue)
        return None
    }

    private func TranslateClassLikeDecl(def: ClassDef, decl: AstClassLikeDecl): Unit {
        if (let Some(astTy) <- decl.GetTy()) {
            let classTy = UnwrapClassType(chirTy.TranslateType(astTy))
            def.SetType(classTy)
        }
        for (member in decl.GetMemberDeclPtrs()) {
            TranslateMemberDecl(def, member)
        }
    }

    private func TranslateMemberDecl(def: CustomTypeDef, member: AstDecl): Unit {
        if (let Some(propDecl) <- (member as AstPropDecl)) {
            AddPropertyAccessors(def, propDecl)
        } else if (let Some(varDecl) <- (member as AstVarDecl)) {
            AddMemberVarDecl(def, varDecl)
        } else if (let Some(funcDecl) <- (member as AstFuncDecl)) {
            if (let Some(value) <- globalSymbolTable.TryGet(funcDecl)) {
                if (let Some(fn) <- (value as Function)) {
                    def.AddMethod(fn)
                }
            }
        }
    }

    private func AddPropertyAccessors(def: CustomTypeDef, propDecl: AstPropDecl): Unit {
        for (getter in propDecl.getters) {
            if (let Some(value) <- globalSymbolTable.TryGet(getter)) {
                if (let Some(fn) <- (value as Function)) {
                    def.AddMethod(fn)
                }
            }
        }
        for (setter in propDecl.setters) {
            if (let Some(value2) <- globalSymbolTable.TryGet(setter)) {
                if (let Some(fn2) <- (value2 as Function)) {
                    def.AddMethod(fn2)
                }
            }
        }
    }

    private func AddMemberVarDecl(def: CustomTypeDef, decl: AstVarDecl): Unit {
        if (decl.TestAttr(AstAttribute.SPECIFIC) && !def.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            return
        }
        if (decl.TestAttr(AstAttribute.STATIC)) {
            if (let Some(value) <- globalSymbolTable.TryGet(decl)) {
                if (let Some(globalVar) <- (value as GlobalVar)) {
                    def.AddStaticMemberVar(globalVar)
                }
            }
            return
        }
        let memberTy = chirTy.TranslateType(RequireAstTy(decl))
        for (existing in def.GetDirectInstanceVars()) {
            if (existing.name == decl.identifier.Val()) {
                return
            }
        }
        let memberInfo = MemberVarInfo(decl.identifier.Val(), memberTy, isStatic: false,
            isReadOnly: decl.IsConst(), rawMangledName: decl.rawMangleName)
        ApplyMemberVarDeclAttrs(memberInfo, decl)
        def.AddInstanceVar(memberInfo)
    }

    private func ApplyMemberVarDeclAttrs(memberInfo: MemberVarInfo, decl: AstVarDecl): Unit {
        if (decl.TestAttr(AstAttribute.PUBLIC)) { memberInfo.attributeInfo.Enable(Attribute.PUBLIC) }
        if (decl.TestAttr(AstAttribute.PROTECTED)) { memberInfo.attributeInfo.Enable(Attribute.PROTECTED) }
        if (decl.TestAttr(AstAttribute.PRIVATE)) { memberInfo.attributeInfo.Enable(Attribute.PRIVATE) }
        if (decl.TestAttr(AstAttribute.STATIC)) { memberInfo.attributeInfo.Enable(Attribute.STATIC) }
        if (decl.TestAttr(AstAttribute.MUT)) { memberInfo.attributeInfo.Enable(Attribute.MUT) }
        if (decl.TestAttr(AstAttribute.FOREIGN)) { memberInfo.attributeInfo.Enable(Attribute.FOREIGN) }
        if (decl.TestAttr(AstAttribute.IMPORTED)) { memberInfo.attributeInfo.Enable(Attribute.IMPORTED) }
        if (decl.TestAttr(AstAttribute.SRC_IMPORTED)) { memberInfo.attributeInfo.Enable(Attribute.SRC_CODE_IMPORTED) }
        if (decl.TestAttr(AstAttribute.C)) { memberInfo.attributeInfo.Enable(Attribute.C) }
        if (decl.TestAttr(AstAttribute.IMPLICIT_ADD)) { memberInfo.attributeInfo.Enable(Attribute.IMPLICIT_ADD) }
    }

    private func BindFuncParams(funcDecl: AstFuncDecl, fn: Function): Unit {
        if (let Some(body) <- funcDecl.funcBody) {
            if (body.paramLists.isEmpty()) {
                return
            }
            var idx: Int64 = 0
            let params = body.paramLists[0].params
            let offset: Int64 = if (params.size < fn.GetNumOfParams()) { 1 } else { 0 }
            for (param in params) {
                if (idx + offset < fn.GetNumOfParams()) {
                    localValSymbolTable.Set(param, fn.GetParam(idx + offset))
                }
                idx++
            }
        }
    }

    private func BindLambdaParams(funcBody: AstFuncBody, lambda: Lambda, funcTy: FuncType): Unit {
        if (funcBody.paramLists.isEmpty()) {
            return
        }
        let params = funcBody.paramLists[0].params
        let paramTys = funcTy.GetParamTypes()
        var idx: Int64 = 0
        for (param in params) {
            if (idx < paramTys.size) {
                let chirParam = builder.CreateParameter(paramTys[idx], "%arg${idx}", lambda)
                chirParam.SetSrcCodeIdentifier(param.identifier.Val())
                localValSymbolTable.Set(param, chirParam)
            }
            idx++
        }
    }

    private func LambdaIdentifier(expr: AstLambdaExpr): String {
        if (!expr.mangledName.isEmpty()) {
            return expr.mangledName
        }
        let owner = CurrentFunction().GetIdentifierWithoutPrefix()
        let id = lambdaCounter
        lambdaCounter++
        return owner + "$lambda$" + id.toString()
    }

    private func EnsureFuncBody(fn: Function): BlockGroup {
        if (let Some(body) <- fn.GetBody()) {
            return body
        }
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        return body
    }

    private func TransShortCircuitAnd(leftValue: Value, rightExpr: AstExpr): Option<Value> {
        let boolTy = builder.context.GetBoolTy()
        let resultLoc = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(boolTy), boolTy,
            CurrentBlock()))
        let parentGroup = RequireParentBlockGroup(CurrentBlock(), "short-circuit and")
        let thenBlock = builder.CreateBlock(parentGroup)
        let elseBlock = builder.CreateBlock(parentGroup)
        let endBlock = builder.CreateBlock(parentGroup)
        builder.CreateBranch(leftValue, thenBlock, elseBlock, CurrentBlock())

        currentBlock = thenBlock
        let rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR short-circuit and rhs produced no value")
        builder.CreateStore(CastValueIfNeeded(rhsValue, boolTy), resultLoc, CurrentBlock())
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(endBlock, CurrentBlock())
        }

        currentBlock = elseBlock
        let constantFalse = RequireResult(builder.CreateConstant(boolTy, BoolLiteral(false), CurrentBlock()))
        builder.CreateStore(constantFalse, resultLoc, CurrentBlock())
        builder.CreateGoTo(endBlock, CurrentBlock())

        currentBlock = endBlock
        return RequireResult(builder.CreateLoad(boolTy, resultLoc, CurrentBlock()))
    }

    private func TransShortCircuitOr(leftValue: Value, rightExpr: AstExpr): Option<Value> {
        let boolTy = builder.context.GetBoolTy()
        let resultLoc = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(boolTy), boolTy,
            CurrentBlock()))
        let parentGroup = RequireParentBlockGroup(CurrentBlock(), "short-circuit or")
        let thenBlock = builder.CreateBlock(parentGroup)
        let elseBlock = builder.CreateBlock(parentGroup)
        let endBlock = builder.CreateBlock(parentGroup)
        builder.CreateBranch(leftValue, thenBlock, elseBlock, CurrentBlock())

        currentBlock = thenBlock
        let constantTrue = RequireResult(builder.CreateConstant(boolTy, BoolLiteral(true), CurrentBlock()))
        builder.CreateStore(constantTrue, resultLoc, CurrentBlock())
        builder.CreateGoTo(endBlock, CurrentBlock())

        currentBlock = elseBlock
        let rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR short-circuit or rhs produced no value")
        builder.CreateStore(CastValueIfNeeded(rhsValue, boolTy), resultLoc, CurrentBlock())
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(endBlock, CurrentBlock())
        }

        currentBlock = endBlock
        return RequireResult(builder.CreateLoad(boolTy, resultLoc, CurrentBlock()))
    }

    private func TranslateForInRange(expr: AstForInExpr): Option<Value> {
        let inExpression = RequireBlockExpr(expr.inExpression, "for-in range inExpression")
        if (inExpression.body.size < 4) {
            throw IllegalStateException("faithful AST2CHIR range ForInExpr expects desugared block with 4 nodes")
        }
        let inductiveVar = Translator.TranslateASTNode(inExpression.body[0], this) ??
            throw IllegalStateException("faithful AST2CHIR for-in range induction var produced no value")
        let stopExprVar = Translator.TranslateASTNode(inExpression.body[1], this) ??
            throw IllegalStateException("faithful AST2CHIR for-in range stop var produced no value")
        let condition = Translator.TranslateASTNode(inExpression.body[3], this) ??
            throw IllegalStateException("faithful AST2CHIR for-in range condition produced no value")
        let recordBlock = CurrentBlock()
        let parentGroup = RequireParentBlockGroup(recordBlock, "for-in range")
        let forInEntryBlock = builder.CreateBlock(parentGroup)
        currentBlock = forInEntryBlock
        let condVar = InitializeForInCondVar()
        InitializeDelayExitSignal()
        let forIn = InitForInExprSkeleton(expr, inductiveVar, condVar, isIter: false)

        TranslateForInRangeBody(expr, forIn)
        TranslateForInRangeLatch(inExpression.body[2], forIn)
        TranslateForInRangeCond(inExpression.body[3], inductiveVar, stopExprVar, condVar, forIn)

        let endBlock = builder.CreateBlock(parentGroup)
        builder.CreateGoTo(endBlock, forInEntryBlock)
        currentBlock = endBlock
        UpdateDelayExitSignalInForInEnd()
        builder.CreateBranch(condition, forInEntryBlock, CurrentBlock(), recordBlock)
        return None
    }

    private func TranslateForInIter(expr: AstForInExpr): Option<Value> {
        let inExpression = RequireBlockExpr(expr.inExpression, "for-in iterator inExpression")
        if (inExpression.body.size < 2) {
            throw IllegalStateException("faithful AST2CHIR iterator ForInExpr expects desugared block with 2 nodes")
        }
        let inductiveVar = Translator.TranslateASTNode(inExpression.body[0], this) ??
            throw IllegalStateException("faithful AST2CHIR for-in iterator induction var produced no value")
        let matchExpr = (inExpression.body[1] as AstMatchExpr) ??
            throw IllegalStateException("faithful AST2CHIR iterator ForInExpr expects MatchExpr as second node")
        let matchTy = chirTy.TranslateType(RequireAstTy(matchExpr))
        let iterNextLocation = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(matchTy), matchTy,
            CurrentBlock()))
        builder.CreateStore(MakeForInIterNoneValue(matchTy), iterNextLocation, CurrentBlock())

        let recordBlock = CurrentBlock()
        let parentGroup = RequireParentBlockGroup(recordBlock, "for-in iterator")
        let forInEntryBlock = builder.CreateBlock(parentGroup)
        currentBlock = forInEntryBlock
        let condVar = InitializeForInCondVar()
        InitializeDelayExitSignal()
        let forIn = InitForInExprSkeleton(expr, inductiveVar, condVar, isIter: true)

        TranslateForInIterBody(expr, iterNextLocation, forIn)
        TranslateForInIterLatch(matchExpr, iterNextLocation, forIn)
        TranslateForInIterCond(matchExpr, iterNextLocation, condVar, forIn)

        let endBlock = builder.CreateBlock(parentGroup)
        builder.CreateGoTo(endBlock, forInEntryBlock)
        currentBlock = endBlock
        UpdateDelayExitSignalInForInEnd()
        builder.CreateGoTo(forInEntryBlock, recordBlock)
        return None
    }

    private func InitForInExprSkeleton(expr: AstForInExpr, inductiveVar: Value, condVar: Value,
        isIter!: Bool): ForIn {
        let parentFunc = CurrentFunction()
        let bodyBlockGroup = builder.CreateBlockGroup(parentFunc)
        let latchBlockGroup = builder.CreateBlockGroup(parentFunc)
        let condBlockGroup = builder.CreateBlockGroup(parentFunc)
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let forIn = if (isIter) {
            builder.CreateForInIter(resultTy, inductiveVar, condVar, CurrentBlock())
        } else {
            builder.CreateForInRange(resultTy, inductiveVar, condVar, CurrentBlock())
        }
        forIn.InitBlockGroups(bodyBlockGroup, latchBlockGroup, condBlockGroup)
        bodyBlockGroup.SetEntryBlock(builder.CreateBlock(bodyBlockGroup))
        latchBlockGroup.SetEntryBlock(builder.CreateBlock(latchBlockGroup))
        condBlockGroup.SetEntryBlock(builder.CreateBlock(condBlockGroup))
        return forIn
    }

    private func TranslateForInRangePatternDecl(pattern: AstPattern): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                let _ = Translator.TranslateASTNode(varDecl, this)
            }
            return
        }
        if (let Some(varOrEnum) <- (pattern as AstVarOrEnumPattern)) {
            if (let Some(realPattern) <- varOrEnum.pattern) {
                TranslateForInRangePatternDecl(realPattern)
                return
            }
            throw IllegalStateException("faithful AST2CHIR unresolved VarOrEnumPattern in range ForInExpr")
        }
        if (let Some(_) <- (pattern as AstWildcardPattern)) {
            return
        }
        throw IllegalArgumentException(
            "not yet ported in faithful AST2CHIR: non-var range ForInExpr pattern")
    }

    private func TranslateForInRangeBody(expr: AstForInExpr, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetBody())
        currentBlock = forIn.GetBody().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in body has no entry block")
        if (let Some(pattern) <- expr.pattern) {
            TranslateForInRangePatternDecl(pattern)
        }
        TranslateForInBodyBlockGroup(expr)
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInIterBody(expr: AstForInExpr, iterNextLocation: Value, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetBody())
        currentBlock = forIn.GetBody().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in iterator body has no entry block")
        if (let Some(pattern) <- expr.pattern) {
            let iterNextValue = GetDerefedValue(iterNextLocation)
            BindPatternValues(pattern, iterNextValue)
        }
        TranslateForInBodyBlockGroup(expr)
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInBodyBlockGroup(expr: AstForInExpr): Unit {
        if (let Some(guardExpr) <- expr.patternGuard) {
            let parentGroup = RequireParentBlockGroup(CurrentBlock(), "for-in guard")
            let bodyBlock = builder.CreateBlock(parentGroup)
            let continueBlock = builder.CreateBlock(parentGroup)
            let guardValue = Translator.TranslateASTNode(guardExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR for-in guard produced no value")
            builder.CreateBranch(guardValue, bodyBlock, continueBlock, CurrentBlock())
            currentBlock = continueBlock
            builder.CreateExit(None, CurrentBlock())
            currentBlock = bodyBlock
        }
        if (let Some(body) <- expr.body) {
            let _ = Translator.TranslateASTNode(body, this)
        }
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateExit(None, CurrentBlock())
        }
    }

    private func TranslateForInRangeLatch(updateNode: AstNode, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetLatch())
        currentBlock = forIn.GetLatch().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in latch has no entry block")
        let trueBlock = builder.CreateBlock(forIn.GetLatch())
        let falseBlock = builder.CreateBlock(forIn.GetLatch())
        builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock, CurrentBlock())
        currentBlock = trueBlock
        builder.CreateExit(None, CurrentBlock())
        currentBlock = falseBlock
        let _ = Translator.TranslateASTNode(updateNode, this)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateExit(None, CurrentBlock())
        }
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInIterLatch(matchExpr: AstMatchExpr, iterNextLocation: Value, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetLatch())
        currentBlock = forIn.GetLatch().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in iterator latch has no entry block")
        let trueBlock = builder.CreateBlock(forIn.GetLatch())
        let falseBlock = builder.CreateBlock(forIn.GetLatch())
        builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock, CurrentBlock())
        currentBlock = trueBlock
        builder.CreateExit(None, CurrentBlock())
        currentBlock = falseBlock
        let selector = Translator.TranslateASTNode(RequireExpr(matchExpr.selector, "iterator next selector"), this) ??
            throw IllegalStateException("faithful AST2CHIR iterator next selector produced no value")
        builder.CreateStore(selector, iterNextLocation, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInRangeCond(conditionNode: AstNode, inductiveVar: Value, stopExprVar: Value,
        condVar: Value, forIn: ForIn): Unit {
        let _ = inductiveVar
        let _ = stopExprVar
        blockGroupStack.add(forIn.GetCond())
        currentBlock = forIn.GetCond().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in cond has no entry block")
        TranslateForInCondControlFlow(condVar)
        let condition = Translator.TranslateASTNode(conditionNode, this) ??
            throw IllegalStateException("faithful AST2CHIR range condition in cond group produced no value")
        builder.CreateStore(condition, condVar, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInIterCond(matchExpr: AstMatchExpr, iterNextLocation: Value, condVar: Value,
        forIn: ForIn): Unit {
        let _ = matchExpr
        blockGroupStack.add(forIn.GetCond())
        currentBlock = forIn.GetCond().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in iterator cond has no entry block")
        TranslateForInCondControlFlow(condVar)
        let tag = GetEnumTagValueFromValue(GetDerefedValue(iterNextLocation))
        let hasValue = RequireResult(builder.CreateUnaryExpression(ExprKind.NOT, builder.context.GetBoolTy(), tag,
            CurrentBlock()))
        builder.CreateStore(hasValue, condVar, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInCondControlFlow(condVar: Value): Unit {
        let trueBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "for-in cond control"))
        let falseBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "for-in cond control"))
        builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock, CurrentBlock())
        currentBlock = trueBlock
        DecreaseDelayExitSignal()
        let constantFalse = RequireResult(builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(false),
            CurrentBlock()))
        builder.CreateStore(constantFalse, condVar, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        currentBlock = falseBlock
    }

    private func UpdateDelayExitSignalInForInEnd(): Unit {
        let parentGroup = RequireParentBlockGroup(CurrentBlock(), "for-in end")
        let trueBlock = builder.CreateBlock(parentGroup)
        let falseBlock = builder.CreateBlock(parentGroup)
        builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock, CurrentBlock())
        currentBlock = trueBlock
        DecreaseDelayExitSignal()
        builder.CreateExit(None, CurrentBlock())
        currentBlock = falseBlock
    }

    private func InitializeForInCondVar(): Value {
        let condVar = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(builder.context.GetBoolTy()),
            builder.context.GetBoolTy(), CurrentBlock()))
        let constantTrue = RequireResult(builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(true),
            CurrentBlock()))
        builder.CreateStore(constantTrue, condVar, CurrentBlock())
        return condVar
    }

    private func InitializeDelayExitSignal(): Unit {
        if (delayExitSignal.isSome()) {
            return
        }
        let signal = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(builder.context.GetInt64Ty()),
            builder.context.GetInt64Ty(), CurrentBlock()))
        delayExitSignal = signal
        let zero = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(0), CurrentBlock()))
        builder.CreateStore(zero, signal, CurrentBlock())
    }

    private func DelayExitSignalGreaterThanZero(): Value {
        let signalValue = RequireResult(builder.CreateLoad(builder.context.GetInt64Ty(), RequireDelayExitSignal(),
            CurrentBlock()))
        let zero = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(0), CurrentBlock()))
        return RequireResult(builder.CreateBinaryExpression(ExprKind.GT, builder.context.GetBoolTy(), signalValue,
            zero, CurrentBlock()))
    }

    private func DecreaseDelayExitSignal(): Unit {
        let signal = RequireDelayExitSignal()
        let signalValue = RequireResult(builder.CreateLoad(builder.context.GetInt64Ty(), signal, CurrentBlock()))
        let one = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(1), CurrentBlock()))
        let decreased = RequireResult(builder.CreateBinaryExpression(ExprKind.SUB, builder.context.GetInt64Ty(),
            signalValue, one, CurrentBlock()))
        builder.CreateStore(decreased, signal, CurrentBlock())
    }

    private func UpdateDelayExitSignal(level: Int64): Unit {
        let levelValue = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(level),
            CurrentBlock()))
        builder.CreateStore(levelValue, RequireDelayExitSignal(), CurrentBlock())
    }

    private func UpdateDelayExitSignalForReturnIfNeeded(): Unit {
        let level = CalculateDelayExitLevelForReturn()
        if (level > 0 && delayExitSignal.isSome()) {
            UpdateDelayExitSignal(level)
        }
    }

    private func CalculateDelayExitLevelForBreak(): Int64 {
        var level: Int64 = 0
        var idx = blockGroupStack.size - 1
        while (idx >= 0) {
            let group = blockGroupStack[idx]
            if (let Some(owner) <- group.GetOwnerExpression()) {
                if ((owner as ForIn).isSome()) {
                    level++
                    break
                }
            }
            idx--
        }
        return level
    }

    private func CalculateDelayExitLevelForContinue(): Int64 {
        return CalculateDelayExitLevelForBreak() - 1
    }

    private func CalculateDelayExitLevelForReturn(): Int64 {
        var level: Int64 = 0
        var idx = blockGroupStack.size - 1
        while (idx >= 0) {
            let group = blockGroupStack[idx]
            if (let Some(fn) <- currentFunc) {
                if (let Some(body) <- fn.GetBody()) {
                    if (body.nodeId == group.nodeId) {
                        break
                    }
                }
            }
            if (let Some(owner) <- group.GetOwnerExpression()) {
                if ((owner as ForIn).isSome()) {
                    level += 2
                }
            }
            idx--
        }
        return level
    }

    private func RequireDelayExitSignal(): Value {
        return delayExitSignal ?? throw IllegalStateException("faithful AST2CHIR ForIn delay-exit signal missing")
    }

    private func MakeForInIterNoneValue(optionTy: Type): Value {
        let noneTag = CreateEnumSelectorConstantForName(optionTy, "None")
        let values = ArrayList<Value>()
        values.add(noneTag)
        return RequireResult(builder.CreateTuple(optionTy, values, CurrentBlock()))
    }

    private func GetEnumTagValueFromValue(value: Value): Value {
        let path = ArrayList<UInt64>()
        path.add(0u64)
        let selectorTy = if (let Some(valueTy) <- value.GetType()) {
            GetEnumSelectorType(valueTy)
        } else {
            builder.context.GetUInt32Ty()
        }
        return RequireResult(builder.CreateField(selectorTy, value, path, CurrentBlock()))
    }

    private func TranslateBlockNodeToDiscarded(node: AstNode): Unit {
        let _ = Translator.TranslateASTNode(node, this)
    }

    private func TranslateBlockNodeAsValue(node: AstNode): Option<Value> {
        let value = Translator.TranslateASTNode(node, this)
        let nodePtr = Translator.GetDesugaredExpr(node)
        return match (nodePtr.astKind) {
            case ASTKind.VAR_DECL => None
            case ASTKind.VAR_WITH_PATTERN_DECL => None
            case ASTKind.ASSIGN_EXPR => None
            case ASTKind.RETURN_EXPR => None
            case _ => value
        }
    }

    private func CurrentFunction(): Function {
        return currentFunc ?? throw IllegalStateException("faithful AST2CHIR has no current function")
    }

    private func EmitImplicitFunctionExit(fn: Function, value: Option<Value>): Unit {
        if (let Some(retValue) <- value) {
            StoreReturnValueIfNeeded(fn, retValue)
        }
        builder.CreateExit(None, CurrentBlock())
    }

    private func EmitImplicitLambdaExit(lambda: Lambda, value: Option<Value>): Unit {
        if (let Some(retTy) <- lambda.GetReturnType()) {
            if (retTy.IsUnit() || retTy.IsNothing() || retTy.IsVoid()) {
                builder.CreateExit(None, CurrentBlock())
                return
            }
            if (let Some(retValue) <- value) {
                StoreLambdaReturnValueIfNeeded(lambda, retValue)
            }
        }
        builder.CreateExit(None, CurrentBlock())
    }

    private func EmitLambdaReturn(value: Option<Value>): Unit {
        let lambda = currentLambda ??
            throw IllegalStateException("faithful AST2CHIR lambda return has no current lambda")
        if (let Some(retValue) <- value) {
            if (let Some(retTy) <- lambda.GetReturnType()) {
                if (retTy.IsUnit() || retTy.IsNothing() || retTy.IsVoid()) {
                    builder.CreateExit(None, CurrentBlock())
                } else {
                    StoreLambdaReturnValueIfNeeded(lambda, retValue)
                    builder.CreateExit(None, CurrentBlock())
                }
                return
            }
            builder.CreateExit(Some(retValue), CurrentBlock())
            return
        }
        builder.CreateExit(None, CurrentBlock())
    }

    private func StoreLambdaReturnValueIfNeeded(lambda: Lambda, value: Value): Unit {
        if (let Some(returnLocation) <- lambda.GetReturnValue()) {
            builder.CreateStore(CastValueIfNeeded(value, RequireRefBaseType(returnLocation)), returnLocation,
                CurrentBlock())
        }
    }

    private func StoreReturnValueIfNeeded(fn: Function, value: Value): Unit {
        if (let Some(returnLocation) <- fn.GetReturnValue()) {
            builder.CreateStore(CastValueIfNeeded(value, RequireRefBaseType(returnLocation)), returnLocation,
                CurrentBlock())
        }
    }

    private func StoreIfResult(location: Option<Value>, value: Option<Value>): Unit {
        if (let Some(loc) <- location) {
            if (let Some(result) <- value) {
                builder.CreateStore(result, loc, CurrentBlock())
            }
        }
    }

    private func StoreTryResult(location: Option<Value>, value: Option<Value>): Unit {
        if (let Some(loc) <- location) {
            if (let Some(result) <- value) {
                builder.CreateStore(CastValueIfNeeded(result, RequireRefBaseType(loc)), loc, CurrentBlock())
            }
        }
    }

    private func HasTypeOfNothing(expr: AstTryExpr): Bool {
        if (let Some(tryBlock) <- expr.tryBlock) {
            if (let Some(tryTy) <- tryBlock.GetTy()) {
                if (!tryTy.IsNothing()) {
                    return false
                }
            } else {
                return false
            }
        }
        for (catchBlock in expr.catchBlocks) {
            if (let Some(catchTy) <- catchBlock.GetTy()) {
                if (!catchTy.IsNothing()) {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }

    private func CurrentTryCatchBlock(): Option<Block> {
        if (tryCatchContext.isEmpty()) {
            return None
        }
        return tryCatchContext[tryCatchContext.size - 1]
    }

    private func ExceptionValueTypeForTry(expr: AstTryExpr): Type {
        let _ = expr
        return BaseExceptionObjectType()
    }

    private func BaseExceptionObjectType(): Type {
        if (let Some(objectTy) <- builder.context.GetObjectTy()) {
            return builder.context.GetRefTy(objectTy)
        }
        if (let Some(anyTy) <- builder.context.GetAnyTy()) {
            return builder.context.GetRefTy(anyTy)
        }
        if (let Some(pkg) <- builder.context.GetCurPackage()) {
            for (classDef in pkg.GetAllClassDef()) {
                if (classDef.GetPackageName() == "std.core" && classDef.GetSrcCodeIdentifier() == "Object") {
                    return builder.context.GetRefTy(builder.context.GetClassTy(classDef, ArrayList<Type>()))
                }
            }
            for (classDef0 in pkg.GetAllClassDef()) {
                if (classDef0.GetSrcCodeIdentifier() == "Object") {
                    return builder.context.GetRefTy(builder.context.GetClassTy(classDef0, ArrayList<Type>()))
                }
            }
        }
        throw IllegalStateException("faithful AST2CHIR cannot determine base exception object type")
    }

    private func GetExceptionsForTry(expr: AstTryExpr): ArrayList<ClassType> {
        let allTryExprs = ArrayList<AstTryExpr>()
        for (tryExpr in tryBodyContext) {
            allTryExprs.add(tryExpr)
        }
        allTryExprs.add(expr)
        for (tryExpr in allTryExprs) {
            if (tryExpr.finallyBlock.isSome()) {
                return ArrayList<ClassType>()
            }
        }
        let exceptions = ArrayList<ClassType>()
        var tryIdx = allTryExprs.size - 1
        while (tryIdx >= 0) {
            let tryExpr2 = allTryExprs[tryIdx]
            for (pattern in tryExpr2.catchPatterns) {
                if (let Some(exceptPattern) <- (pattern as AstExceptTypePattern)) {
                    for (typeNode in exceptPattern.types) {
                        if (let Some(typeTy) <- typeNode.GetTy()) {
                            AddExceptionClassType(exceptions, typeTy)
                        }
                    }
                } else if (let Some(patternTy) <- pattern.GetTy()) {
                    AddExceptionClassType(exceptions, patternTy)
                }
            }
            tryIdx--
        }
        SortExceptionClassTypes(exceptions)
        return exceptions
    }

    private func AddExceptionClassType(exceptions: ArrayList<ClassType>, astTy: AstTy): Unit {
        if (let Some(genericTy) <- (astTy as AstGenericsTy)) {
            for (upperTy in genericTy.upperBounds) {
                if (upperTy.IsClass()) {
                    AddExceptionClassType(exceptions, upperTy)
                }
            }
            return
        }
        let translated = chirTy.TranslateType(astTy).StripAllRefs()
        if (let Some(classTy) <- (translated as ClassType)) {
            for (existing in exceptions) {
                if (existing.IsEqual(classTy)) {
                    return
                }
            }
            exceptions.add(classTy)
        }
    }

    private func SortExceptionClassTypes(exceptions: ArrayList<ClassType>): Unit {
        var idx: Int64 = 1
        while (idx < exceptions.size) {
            let value = exceptions[idx]
            var insertIdx = idx - 1
            while (insertIdx >= 0 && exceptions[insertIdx].ToString() > value.ToString()) {
                exceptions[insertIdx + 1] = exceptions[insertIdx]
                insertIdx--
            }
            exceptions[insertIdx + 1] = value
            idx++
        }
    }

    private func TranslateCatchBlocks(expr: AstTryExpr, resultLoc: Option<Value>, endBlock: Block): Option<Block> {
        let group = RequireParentBlockGroup(CurrentBlock(), "catch")
        let hasFinally = expr.finallyBlock.isSome()
        let rethrowBlock: Option<Block> = if (hasFinally) { builder.CreateBlock(group) } else { None }
        if (let Some(block) <- rethrowBlock) {
            tryCatchContext.add(block)
        }
        let exceptionValueTy = ExceptionValueTypeForTry(expr)
        let exception = RequireResult(builder.CreateGetException(exceptionValueTy, CurrentBlock()))
        let beginCatchArgs = ArrayList<Value>()
        beginCatchArgs.add(exception)
        let beginCatch = RequireResult(builder.CreateIntrinsic(exceptionValueTy,
            IntrisicCallContext(kind: IntrinsicKind.BEGIN_CATCH, args: beginCatchArgs), CurrentBlock()))
        var idx: Int64 = 0
        while (idx < expr.catchPatterns.size && idx < expr.catchBlocks.size) {
            let (falseBlock, trueBlock) = TranslateExceptionPattern(expr.catchPatterns[idx], beginCatch)
            currentBlock = trueBlock
            BindExceptionPatternValues(expr.catchPatterns[idx], beginCatch)
            let catchValue = Translator.TranslateASTNode(expr.catchBlocks[idx], this)
            StoreTryResult(resultLoc, catchValue)
            if (CurrentBlock().GetTerminator().isNone()) {
                builder.CreateGoTo(endBlock, CurrentBlock())
            }
            currentBlock = falseBlock
            idx++
        }
        if (CurrentBlock().GetTerminator().isNone()) {
            if (let Some(block2) <- rethrowBlock) {
                builder.CreateRaiseException(beginCatch, block2, CurrentBlock())
            } else if (let Some(outerBlock) <- CurrentTryCatchBlock()) {
                builder.CreateRaiseException(beginCatch, outerBlock, CurrentBlock())
            } else {
                builder.CreateRaiseException(beginCatch, CurrentBlock())
            }
        }
        if (rethrowBlock.isSome()) {
            tryCatchContext.remove(at: tryCatchContext.size - 1)
        }
        return rethrowBlock
    }

    private func TranslateExceptionPattern(pattern: AstPattern, exceptionValue: Value): (Block, Block) {
        let group = RequireParentBlockGroup(CurrentBlock(), "catch pattern")
        let trueBlock = builder.CreateBlock(group)
        if (let Some(_) <- (pattern as AstWildcardPattern)) {
            let falseBlock = builder.CreateBlock(group)
            let targetTy = if (let Some(patternTy) <- pattern.GetTy()) {
                chirTy.TranslateType(patternTy)
            } else {
                ExceptionValueTypeFromValue(exceptionValue)
            }
            let cond = RequireResult(builder.CreateInstanceOf(builder.context.GetBoolTy(), exceptionValue, targetTy,
                CurrentBlock()))
            builder.CreateBranch(cond, trueBlock, falseBlock, CurrentBlock())
            return (falseBlock, trueBlock)
        }
        if (let Some(exceptPattern) <- (pattern as AstExceptTypePattern)) {
            for (typeNode in exceptPattern.types) {
                let falseBlock = builder.CreateBlock(group)
                let targetTy = chirTy.TranslateType(typeNode.GetTy() ??
                    throw IllegalStateException("faithful AST2CHIR catch type has no Sema type"))
                let cond = RequireResult(builder.CreateInstanceOf(builder.context.GetBoolTy(), exceptionValue, targetTy,
                    CurrentBlock()))
                builder.CreateBranch(cond, trueBlock, falseBlock, CurrentBlock())
                currentBlock = falseBlock
            }
            return (CurrentBlock(), trueBlock)
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR catch pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func BindExceptionPatternValues(pattern: AstPattern, exceptionValue: Value): Unit {
        if (let Some(exceptPattern) <- (pattern as AstExceptTypePattern)) {
            if (let Some(inner) <- exceptPattern.pattern) {
                BindExceptionInnerPatternValues(inner, exceptionValue)
            }
            return
        }
        BindExceptionInnerPatternValues(pattern, exceptionValue)
    }

    private func BindExceptionInnerPatternValues(pattern: AstPattern, exceptionValue: Value): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            let varDecl = varPattern.varDecl ??
                throw IllegalStateException("faithful AST2CHIR catch VarPattern has no VarDecl")
            localValSymbolTable.Set(varDecl, CastValueIfNeeded(exceptionValue, chirTy.TranslateType(RequireAstTy(
                varPattern))))
            return
        }
        if (let Some(varOrEnum) <- (pattern as AstVarOrEnumPattern)) {
            if (let Some(realPattern) <- varOrEnum.pattern) {
                BindExceptionInnerPatternValues(realPattern, exceptionValue)
            }
            return
        }
        BindPatternValues(pattern, exceptionValue)
    }

    private func ExceptionValueTypeFromValue(value: Value): Type {
        return value.GetType() ??
            throw IllegalStateException("faithful AST2CHIR exception value has no type")
    }

    private func TranslateFinally(finallyBlock: AstBlock, exceptionBlock: Block, normalEntryBlock: Block,
        finalEndBlock: Block): Unit {
        TranslateFinallyRethrowFlow(finallyBlock, exceptionBlock)
        currentBlock = normalEntryBlock
        let _ = Translator.TranslateASTNode(finallyBlock, this)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(finalEndBlock, CurrentBlock())
        }
    }

    private func TranslateFinallyRethrowFlow(finallyBlock: AstBlock, exceptionBlock: Block): Unit {
        currentBlock = exceptionBlock
        exceptionBlock.SetExceptions(ArrayList<ClassType>())
        let exceptionTy = ExceptionValueTypeFromFinallyContext()
        let exception = RequireResult(builder.CreateGetException(exceptionTy, CurrentBlock()))
        let beginCatchArgs = ArrayList<Value>()
        beginCatchArgs.add(exception)
        let beginCatch = RequireResult(builder.CreateIntrinsic(exceptionTy,
            IntrisicCallContext(kind: IntrinsicKind.BEGIN_CATCH, args: beginCatchArgs), CurrentBlock()))
        let _ = Translator.TranslateASTNode(finallyBlock, this)
        if (CurrentBlock().GetTerminator().isNone()) {
            if (let Some(outerBlock) <- CurrentTryCatchBlock()) {
                builder.CreateRaiseException(beginCatch, outerBlock, CurrentBlock())
            } else {
                builder.CreateRaiseException(beginCatch, CurrentBlock())
            }
        }
    }

    private func ExceptionValueTypeFromFinallyContext(): Type {
        return BaseExceptionObjectType()
    }

    private func TranslateMatchWithSelector(expr: AstMatchExpr, resultLoc: Option<Value>): Unit {
        let selector = Translator.TranslateASTNode(RequireExpr(expr.selector, "match selector"), this) ??
            throw IllegalStateException("faithful AST2CHIR match selector produced no value")
        let group = RequireParentBlockGroup(CurrentBlock(), "match")
        let endBlock = builder.CreateBlock(group)
        var caseIndex: Int64 = 0
        while (caseIndex < expr.matchCases.size) {
            let matchCase = expr.matchCases[caseIndex]
            let bodyBlock = builder.CreateBlock(group)
            let nextBlock = builder.CreateBlock(group)
            let matchedBlock = if (matchCase.patternGuard.isSome()) { builder.CreateBlock(group) } else { bodyBlock }
            if (matchCase.patterns.size == 1) {
                TranslateSinglePatternBranch(matchCase.patterns[0], selector, matchedBlock, nextBlock)
                currentBlock = matchedBlock
                BindPatternValues(matchCase.patterns[0], selector)
            } else {
                var patternIndex: Int64 = 0
                while (patternIndex < matchCase.patterns.size) {
                    let afterPattern = if (patternIndex == matchCase.patterns.size - 1) {
                        nextBlock
                    } else {
                        builder.CreateBlock(group)
                    }
                    TranslateSinglePatternBranch(matchCase.patterns[patternIndex], selector, matchedBlock, afterPattern)
                    currentBlock = afterPattern
                    patternIndex++
                }
                currentBlock = matchedBlock
            }
            if (let Some(guardExpr) <- matchCase.patternGuard) {
                let guardValue = Translator.TranslateASTNode(guardExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR match pattern guard produced no value")
                builder.CreateBranch(guardValue, bodyBlock, nextBlock, CurrentBlock())
            }

            currentBlock = bodyBlock
            let bodyValue = Translator.TranslateASTNode(RequireBlock(matchCase.exprOrDecls, "match case body"), this)
            StoreIfResult(resultLoc, bodyValue)
            if (CurrentBlock().GetTerminator().isNone()) {
                builder.CreateGoTo(endBlock, CurrentBlock())
            }

            currentBlock = nextBlock
            caseIndex++
        }
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(endBlock, CurrentBlock())
        }
        currentBlock = endBlock
    }

    private func TranslateConditionMatches(expr: AstMatchExpr, resultLoc: Option<Value>): Unit {
        let group = RequireParentBlockGroup(CurrentBlock(), "condition match")
        let endBlock = builder.CreateBlock(group)
        var caseIndex: Int64 = 0
        while (caseIndex < expr.matchCaseOthers.size) {
            let matchCase = expr.matchCaseOthers[caseIndex]
            let bodyBlock = builder.CreateBlock(group)
            let nextBlock = builder.CreateBlock(group)
            if (let Some(condExpr) <- matchCase.matchExpr) {
                if (condExpr.astKind == ASTKind.WILDCARD_EXPR) {
                    builder.CreateGoTo(bodyBlock, CurrentBlock())
                } else {
                    let condValue = Translator.TranslateASTNode(condExpr, this) ??
                        throw IllegalStateException("faithful AST2CHIR condition match case produced no value")
                    builder.CreateBranch(condValue, bodyBlock, nextBlock, CurrentBlock())
                }
            } else {
                builder.CreateGoTo(bodyBlock, CurrentBlock())
            }

            currentBlock = bodyBlock
            let bodyValue = Translator.TranslateASTNode(RequireBlock(matchCase.exprOrDecls, "condition match body"),
                this)
            StoreIfResult(resultLoc, bodyValue)
            if (CurrentBlock().GetTerminator().isNone()) {
                builder.CreateGoTo(endBlock, CurrentBlock())
            }
            currentBlock = nextBlock
            caseIndex++
        }
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(endBlock, CurrentBlock())
        }
        currentBlock = endBlock
    }

    private func TranslateSinglePatternBranch(pattern: AstPattern, selector: Value, trueBlock: Block,
        falseBlock: Block): Unit {
        if (let Some(_) <- (pattern as AstWildcardPattern)) {
            builder.CreateGoTo(trueBlock, CurrentBlock())
            return
        }
        if (let Some(_) <- (pattern as AstVarPattern)) {
            builder.CreateGoTo(trueBlock, CurrentBlock())
            return
        }
        if (let Some(varOrEnum) <- (pattern as AstVarOrEnumPattern)) {
            if (let Some(realPattern) <- varOrEnum.pattern) {
                TranslateSinglePatternBranch(realPattern, selector, trueBlock, falseBlock)
                return
            }
            builder.CreateGoTo(trueBlock, CurrentBlock())
            return
        }
        if (let Some(constPattern) <- (pattern as AstConstPattern)) {
            let litValue = Translator.TranslateASTNode(RequireExpr(constPattern.literal, "const pattern literal"),
                this) ?? throw IllegalStateException("faithful AST2CHIR const pattern literal produced no value")
            let cond = RequireResult(builder.CreateBinaryExpression(ExprKind.EQUAL, builder.context.GetBoolTy(),
                selector, litValue, CurrentBlock()))
            builder.CreateBranch(cond, trueBlock, falseBlock, CurrentBlock())
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            TranslateEnumPatternBranch(enumPattern, selector, trueBlock, falseBlock)
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            TranslateTuplePatternBranch(tuplePattern, selector, trueBlock, falseBlock)
            return
        }
        if (let Some(typePattern) <- (pattern as AstTypePattern)) {
            TranslateTypePatternBranch(typePattern, selector, trueBlock, falseBlock)
            return
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR match pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func BindPatternValues(pattern: AstPattern, selector: Value): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                localValSymbolTable.Set(varDecl, selector)
            }
            return
        }
        if (let Some(varOrEnum) <- (pattern as AstVarOrEnumPattern)) {
            if (let Some(realPattern) <- varOrEnum.pattern) {
                BindPatternValues(realPattern, selector)
            }
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            var idx: Int64 = 0
            for (subPattern in tuplePattern.patterns) {
                let fieldValue = ExtractPatternField(selector, idx, chirTy.TranslateType(RequireAstTy(subPattern)))
                BindPatternValues(subPattern, fieldValue)
                idx++
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            let payloadTypes = EnumPatternPayloadTypes(enumPattern)
            var idx: Int64 = 0
            for (subPattern in enumPattern.patterns) {
                let fieldTy = if (idx < payloadTypes.size) {
                    payloadTypes[idx]
                } else {
                    chirTy.TranslateType(RequireAstTy(subPattern))
                }
                let payloadValue = ExtractPatternField(selector, idx + 1, fieldTy)
                BindPatternValues(subPattern, payloadValue)
                idx++
            }
            return
        }
        if (let Some(typePattern) <- (pattern as AstTypePattern)) {
            if (let Some(inner) <- typePattern.pattern) {
                BindPatternValues(inner, selector)
            }
            return
        }
    }

    private func TranslateEnumPatternCondition(pattern: AstEnumPattern, selector: Value): Value {
        let tagValue = GetEnumTagValue(pattern, selector)
        let tagConst = CreateEnumSelectorConstant(RequireEnumPatternConstructor(pattern))
        return RequireResult(builder.CreateBinaryExpression(ExprKind.EQUAL, builder.context.GetBoolTy(), tagValue,
            tagConst, CurrentBlock()))
    }

    private func TranslateEnumPatternBranch(pattern: AstEnumPattern, selector: Value, trueBlock: Block,
        falseBlock: Block): Unit {
        let cond = TranslateEnumPatternCondition(pattern, selector)
        if (pattern.patterns.isEmpty()) {
            builder.CreateBranch(cond, trueBlock, falseBlock, CurrentBlock())
            return
        }
        let payloadBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "enum pattern payload"))
        builder.CreateBranch(cond, payloadBlock, falseBlock, CurrentBlock())
        currentBlock = payloadBlock
        TranslatePatternSequenceWithTypes(pattern.patterns, EnumPatternPayloadTypes(pattern), selector, 1,
            trueBlock, falseBlock)
    }

    private func TranslateTuplePatternBranch(pattern: AstTuplePattern, selector: Value, trueBlock: Block,
        falseBlock: Block): Unit {
        TranslatePatternSequence(pattern.patterns, selector, 0, trueBlock, falseBlock)
    }

    private func TranslateTypePatternBranch(pattern: AstTypePattern, selector: Value, trueBlock: Block,
        falseBlock: Block): Unit {
        if (pattern.matchBeforeRuntime) {
            if (let Some(inner) <- pattern.pattern) {
                TranslateSinglePatternBranch(inner, selector, trueBlock, falseBlock)
            } else {
                builder.CreateGoTo(trueBlock, CurrentBlock())
            }
            return
        }
        if (pattern.needRuntimeTypeCheck) {
            let typeCond = RequireResult(builder.CreateInstanceOf(builder.context.GetBoolTy(), selector,
                chirTy.TranslateType(RequireAstTy(pattern)), CurrentBlock()))
            if (let Some(inner) <- pattern.pattern) {
                let innerBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "type pattern"))
                builder.CreateBranch(typeCond, innerBlock, falseBlock, CurrentBlock())
                currentBlock = innerBlock
                TranslateSinglePatternBranch(inner, selector, trueBlock, falseBlock)
            } else {
                builder.CreateBranch(typeCond, trueBlock, falseBlock, CurrentBlock())
            }
            return
        }
        let constantFalse = RequireResult(builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(false),
            CurrentBlock()))
        builder.CreateBranch(constantFalse, trueBlock, falseBlock, CurrentBlock())
    }

    private func TranslatePatternSequence(patterns: ArrayList<AstPattern>, selector: Value, fieldOffset: Int64,
        trueBlock: Block, falseBlock: Block): Unit {
        TranslatePatternSequenceWithTypes(patterns, ArrayList<Type>(), selector, fieldOffset, trueBlock, falseBlock)
    }

    private func TranslatePatternSequenceWithTypes(patterns: ArrayList<AstPattern>, fieldTys: ArrayList<Type>,
        selector: Value, fieldOffset: Int64, trueBlock: Block, falseBlock: Block): Unit {
        if (patterns.isEmpty()) {
            builder.CreateGoTo(trueBlock, CurrentBlock())
            return
        }
        let group = RequireParentBlockGroup(CurrentBlock(), "nested pattern")
        var idx: Int64 = 0
        while (idx < patterns.size) {
            let subPattern = patterns[idx]
            let nextBlock = if (idx == patterns.size - 1) { trueBlock } else { builder.CreateBlock(group) }
            let fieldTy = if (idx < fieldTys.size) {
                fieldTys[idx]
            } else {
                chirTy.TranslateType(RequireAstTy(subPattern))
            }
            let fieldValue = ExtractPatternField(selector, idx + fieldOffset, fieldTy)
            TranslateSinglePatternBranch(subPattern, fieldValue, nextBlock, falseBlock)
            if (idx != patterns.size - 1) {
                currentBlock = nextBlock
            }
            idx++
        }
    }

    private func EnumPatternPayloadTypes(pattern: AstEnumPattern): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (let Some(constructorExpr) <- pattern.constructor) {
            if (let Some(constructorTy) <- constructorExpr.GetTy()) {
                if (let Some(funcTy) <- (constructorTy as AstFuncTy)) {
                    for (paramTy in funcTy.paramTys) {
                        out.add(TranslateEnumPatternPayloadType(pattern, paramTy))
                    }
                    return out
                }
            }
        }
        if (let Some(funcDecl) <- (RequireEnumPatternConstructor(pattern) as AstFuncDecl)) {
            if (let Some(ctorTy) <- funcDecl.GetTy()) {
                if (let Some(funcTy) <- (ctorTy as AstFuncTy)) {
                    for (paramTy in funcTy.paramTys) {
                        out.add(TranslateEnumPatternPayloadType(pattern, paramTy))
                    }
                }
            }
        }
        return out
    }

    private func TranslateEnumPatternPayloadType(pattern: AstEnumPattern, paramTy: AstTy): Type {
        let translated = chirTy.TranslateType(paramTy)
        if (let Some(enumTy) <- (chirTy.TranslateType(RequireAstTy(pattern)) as EnumType)) {
            return SubstituteGenericType(translated, enumTy.GetEnumDef().GetGenericTypeParams(),
                enumTy.GetGenericArgs())
        }
        return translated
    }

    private func ExtractPatternField(value: Value, index: Int64, fieldTy: Type): Value {
        let path = ArrayList<UInt64>()
        path.add(UInt64(index))
        return RequireResult(builder.CreateField(fieldTy, GetDerefedValue(value), path, CurrentBlock()))
    }

    private func GetEnumTagValue(pattern: AstEnumPattern, selector: Value): Value {
        let constructor = RequireEnumPatternConstructor(pattern)
        let path = ArrayList<UInt64>()
        path.add(0u64)
        return RequireResult(builder.CreateField(GetEnumSelectorType(constructor), GetDerefedValue(selector), path,
            CurrentBlock()))
    }

    private func RequireEnumPatternConstructor(pattern: AstEnumPattern): AstDecl {
        let constructorExpr = RequireExpr(pattern.constructor, "enum pattern constructor")
        if (let Some(refExpr) <- (constructorExpr as AstRefExpr)) {
            return refExpr.ref.target ??
                throw IllegalStateException("faithful AST2CHIR enum pattern RefExpr has no target")
        }
        if (let Some(member) <- (constructorExpr as AstMemberAccess)) {
            return ResolveMemberAccessTarget(member, "faithful AST2CHIR enum pattern MemberAccess")
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: enum pattern constructor expression")
    }

    private func SameTranslatorAstDecl(left: AstDecl, right: AstDecl): Bool {
        if (left.TestAttr(AstAttribute.IMPORTED) && right.TestAttr(AstAttribute.IMPORTED)) {
            if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
                return left.rawMangleName == right.rawMangleName
            }
            if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
                return left.mangledName == right.mangledName
            }
        }
        return ASTKindIndex(left.astKind) == ASTKindIndex(right.astKind) &&
            left.identifier.Val() == right.identifier.Val() && left.fullPackageName == right.fullPackageName &&
            left.begin.hashCode() == right.begin.hashCode() && left.end.hashCode() == right.end.hashCode()
    }

    private func TranslateVArrayExpr(expr: AstArrayExpr, arrayTy: VArrayType): Value {
        if (expr.args.size != 1) {
            throw IllegalArgumentException("faithful AST2CHIR VArray expression expects one argument")
        }
        let sizeValue = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(Int64(arrayTy.size)),
            CurrentBlock()))
        let argValue = Translator.TranslateASTNode(RequireFuncArgExpr(expr.args[0], "VArray init argument"), this) ??
            throw IllegalStateException("faithful AST2CHIR VArray init argument produced no value")
        let argTy = argValue.GetType() ??
            throw IllegalStateException("faithful AST2CHIR VArray init argument has no type")
        if (argTy.IsFunc()) {
            let nullItem = RequireResult(builder.CreateConstant(arrayTy.GetElementType(), NullLiteral(), CurrentBlock()))
            return RequireResult(builder.CreateVArrayBuilder(arrayTy, sizeValue, nullItem, argValue, CurrentBlock()))
        }
        let fnParamTys = ArrayList<Type>()
        fnParamTys.add(builder.context.GetInt64Ty())
        let nullFnTy = builder.context.GetFuncTy(fnParamTys, arrayTy.GetElementType())
        let nullFn = RequireResult(builder.CreateConstant(nullFnTy, NullLiteral(), CurrentBlock()))
        return RequireResult(builder.CreateVArrayBuilder(arrayTy, sizeValue, argValue, nullFn, CurrentBlock()))
    }

    private func TranslateStructArrayLit(expr: AstArrayLit, arrayTy: StructType): Value {
        let genericArgs = arrayTy.GetGenericArgs()
        if (genericArgs.isEmpty()) {
            throw IllegalStateException("faithful AST2CHIR std.core.Array type has no element type")
        }
        let elementTy = genericArgs[0]
        let elementSize = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(),
            IntLiteral(Int64(expr.children.size)), CurrentBlock()))
        let rawArrayTy = builder.context.GetRawArrayTy(elementTy)
        let rawArrayRefTy = builder.context.GetRefTy(rawArrayTy)
        let rawArrayRef = RequireResult(builder.CreateRawArrayAllocate(rawArrayRefTy, elementTy, elementSize,
            CurrentBlock()))
        if (IsArrayElementPrimitiveForLiteral(elementTy)) {
            let elements = ArrayList<Value>()
            for (child in expr.children) {
                elements.add(Translator.TranslateASTNode(child, this) ??
                    throw IllegalStateException("faithful AST2CHIR ArrayLit element produced no value"))
            }
            builder.CreateRawArrayLiteralInit(builder.context.GetUnitTy(), rawArrayRef, elements, CurrentBlock())
        } else {
            var idx: Int64 = 0
            for (child in expr.children) {
                let element = Translator.TranslateASTNode(child, this) ??
                    throw IllegalStateException("faithful AST2CHIR ArrayLit element produced no value")
                let path = ArrayList<UInt64>()
                path.add(UInt64(idx))
                builder.CreateStoreElementRef(element, rawArrayRef, path, CurrentBlock())
                idx++
            }
        }
        let initFunc = expr.initFunc ??
            throw IllegalStateException("faithful AST2CHIR std.core.Array literal missing initFunc")
        let resultRefTy = builder.context.GetRefTy(arrayTy)
        let result = RequireResult(builder.CreateAllocate(resultRefTy, arrayTy, CurrentBlock()))
        let startIndex = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(0),
            CurrentBlock()))
        let args = ArrayList<Value>()
        args.add(result)
        args.add(rawArrayRef)
        args.add(startIndex)
        args.add(elementSize)
        let initFnTy = builder.context.GetFuncTy(TypesFromValues(args), builder.context.GetUnitTy())
        let thisTy = result.GetType() ??
            throw IllegalStateException("faithful AST2CHIR std.core.Array literal result has no type")
        let _ = CreateApplyMaybeWithException(initFnTy.GetReturnType(), GetSymbolTable(initFunc),
            FuncCallContext(args: args, thisType: thisTy))
        return RequireResult(builder.CreateLoad(arrayTy, result, CurrentBlock()))
    }

    private func TranslateRawArrayByCollection(expr: AstArrayExpr, arrayTy: Type, rawArrayTy: RawArrayType): Value {
        let collection = Translator.TranslateASTNode(RequireFuncArgExpr(expr.args[0], "RawArray collection"), this) ??
            throw IllegalStateException("faithful AST2CHIR RawArray collection produced no value")
        let collectionTy = collection.GetType() ??
            throw IllegalStateException("faithful AST2CHIR RawArray collection has no type")
        let sizeTy = builder.context.GetInt64Ty()
        let originalObjType = ExactCollectionSizeReceiverType(collectionTy)
        let sizeFuncParamTys = ArrayList<Type>()
        sizeFuncParamTys.add(originalObjType)
        let sizeFuncTy = builder.context.GetFuncTy(sizeFuncParamTys, sizeTy)
        let invokeCtx = InvokeCallContext(collection, FuncCallContext(thisType: collectionTy.StripAllRefs()),
            FuncSigInfo(sizeFuncTy, funcName: "$sizeget"))
        let sizeValue = CreateInvokeMaybeWithException(sizeTy, invokeCtx)

        let rawArrayRef = RequireResult(builder.CreateRawArrayAllocate(arrayTy, rawArrayTy.GetElementType(),
            sizeValue, CurrentBlock()))
        let initFunc = expr.initFunc ??
            throw IllegalStateException("faithful AST2CHIR RawArray(collection) missing initFunc")
        let args = ArrayList<Value>()
        args.add(rawArrayRef)
        args.add(collection)
        let instTypeArgs = ArrayList<Type>()
        if (initFunc.TestAttr(AstAttribute.GENERIC)) {
            instTypeArgs.add(rawArrayTy.GetElementType())
        }
        let initFnTy = builder.context.GetFuncTy(TypesFromValues(args), arrayTy)
        let _ = CreateApplyMaybeWithException(initFnTy.GetReturnType(), GetSymbolTable(initFunc),
            FuncCallContext(args: args, instTypeArgs: instTypeArgs))
        return rawArrayRef
    }

    private func TranslateRawArrayByLambda(expr: AstArrayExpr, arrayTy: Type, rawArrayTy: RawArrayType): Value {
        let sizeValue = Translator.TranslateASTNode(RequireFuncArgExpr(expr.args[0], "RawArray lambda size"), this) ??
            throw IllegalStateException("faithful AST2CHIR RawArray lambda size produced no value")
        let rawArrayRef = RequireResult(builder.CreateRawArrayAllocate(arrayTy, rawArrayTy.GetElementType(),
            sizeValue, CurrentBlock()))
        let userInitFn = Translator.TranslateASTNode(RequireFuncArgExpr(expr.args[1], "RawArray lambda init"), this) ??
            throw IllegalStateException("faithful AST2CHIR RawArray lambda init produced no value")
        let initFunc = expr.initFunc ??
            throw IllegalStateException("faithful AST2CHIR RawArray(size, initFunc) missing initFunc")
        let args = ArrayList<Value>()
        args.add(rawArrayRef)
        args.add(userInitFn)
        let instTypeArgs = ArrayList<Type>()
        if (initFunc.TestAttr(AstAttribute.GENERIC)) {
            for (ty in rawArrayTy.GetTypeArgs()) {
                instTypeArgs.add(ty)
            }
        }
        let initFnTy = builder.context.GetFuncTy(TypesFromValues(args), arrayTy)
        let _ = CreateApplyMaybeWithException(initFnTy.GetReturnType(), GetSymbolTable(initFunc),
            FuncCallContext(args: args, instTypeArgs: instTypeArgs))
        return rawArrayRef
    }

    private func IsArrayElementPrimitiveForLiteral(ty: Type): Bool {
        if (ty.IsPrimitive() || ty.IsVArray()) {
            return true
        }
        if (ty.IsStructArray()) {
            let args = RequireStructType(ty).GetGenericArgs()
            return !args.isEmpty() && IsArrayElementPrimitiveForLiteral(args[0])
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            let elementTys = tupleTy.GetTypeArgs()
            if (elementTys.isEmpty()) {
                return false
            }
            for (elementTy in elementTys) {
                if (!IsArrayElementPrimitiveForLiteral(elementTy)) {
                    return false
                }
            }
            return true
        }
        return false
    }

    private func ExactCollectionSizeReceiverType(collectionTy: Type): Type {
        let strippedTy = collectionTy.StripAllRefs()
        if (let Some(customTy) <- (strippedTy as CustomType)) {
            if (let Some(defTy) <- customTy.GetCustomTypeDef().GetType()) {
                return builder.context.GetRefTy(defTy)
            }
        }
        return collectionTy
    }

    private func TypesFromValues(values: ArrayList<Value>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (value in values) {
            out.add(value.GetType() ??
                throw IllegalStateException("faithful AST2CHIR array init argument has no type"))
        }
        return out
    }

    private func TranslateTupleAccess(expr: AstSubscriptExpr): Value {
        let path = ArrayList<UInt64>()
        var baseExpr: Option<AstExpr> = None
        var current: Option<AstSubscriptExpr> = expr
        while (let Some(subscript) <- current) {
            if (!subscript.isTupleAccess) {
                break
            }
            if (subscript.indexExprs.size != 1) {
                throw IllegalArgumentException("faithful AST2CHIR tuple access expects one index")
            }
            path.add(subscript.indexExprs[0].constNumValue.asInt.Uint64(), at: 0)
            baseExpr = subscript.baseExpr
            current = if (let Some(base) <- subscript.baseExpr) { base as AstSubscriptExpr } else { None }
        }
        let base = Translator.TranslateASTNode(RequireExpr(baseExpr, "tuple access base"), this) ??
            throw IllegalStateException("faithful AST2CHIR tuple base produced no value")
        let baseValue = GetDerefedValue(base)
        return RequireResult(builder.CreateField(chirTy.TranslateType(RequireAstTy(expr)), baseValue, path,
            CurrentBlock()))
    }

    private func TranslateVArrayAccess(expr: AstSubscriptExpr): Value {
        let indexExprs = ArrayList<AstExpr>()
        var baseExpr: Option<AstExpr> = None
        var current: Option<AstSubscriptExpr> = expr
        while (let Some(subscript) <- current) {
            if (!subscript.IsVArrayAccess()) {
                break
            }
            if (subscript.indexExprs.size != 1) {
                throw IllegalArgumentException("faithful AST2CHIR VArray access expects one index")
            }
            indexExprs.add(subscript.indexExprs[0], at: 0)
            baseExpr = subscript.baseExpr
            current = if (let Some(base) <- subscript.baseExpr) { base as AstSubscriptExpr } else { None }
        }
        let args = ArrayList<Value>()
        let base = Translator.TranslateASTNode(RequireExpr(baseExpr, "VArray access base"), this) ??
            throw IllegalStateException("faithful AST2CHIR VArray base produced no value")
        args.add(base)
        for (indexExpr in indexExprs) {
            let indexValue = Translator.TranslateASTNode(indexExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR VArray index produced no value")
            args.add(GetDerefedValue(indexValue))
        }
        let callContext = IntrisicCallContext(kind: IntrinsicKind.VARRAY_GET, args: args)
        return RequireResult(builder.CreateIntrinsic(chirTy.TranslateType(RequireAstTy(expr)), callContext,
            CurrentBlock()))
    }

    private func TranslateEnumCtorCall(expr: AstCallExpr, calleeDecl: AstFuncDecl): Value {
        let args = ArrayList<Value>()
        args.add(CreateEnumSelectorConstant(calleeDecl))
        let expectedParamTys = FuncParamTypes(expr, calleeDecl)
        var idx: Int64 = 0
        for (arg in expr.args) {
            if (let Some(argExpr) <- arg.expr) {
                var value = Translator.TranslateASTNode(argExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR enum ctor arg produced no value")
                if (idx < expectedParamTys.size) {
                    value = BoxOrCastValueIfNeeded(value, expectedParamTys[idx])
                }
                args.add(value)
            }
            idx++
        }
        return RequireResult(builder.CreateTuple(chirTy.TranslateType(RequireAstTy(expr)), args, CurrentBlock()))
    }

    private func CallBaseFuncTy(expr: AstCallExpr, calleeDecl: AstFuncDecl): AstFuncTy {
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(baseTy) <- base.GetTy()) {
                if (let Some(funcTy) <- (baseTy as AstFuncTy)) {
                    return funcTy
                }
            }
        }
        if (let Some(declTy) <- calleeDecl.GetTy()) {
            if (let Some(funcTy) <- (declTy as AstFuncTy)) {
                return funcTy
            }
        }
        throw IllegalStateException("faithful AST2CHIR expected function type for call")
    }

    private func CreateApplyMaybeWithException(resultTy: Type, callee: Value, callContext: FuncCallContext): Value {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "apply-with-exception"))
            let term = builder.CreateApplyWithException(resultTy, callee, callContext, successBlock, errorBlock,
                CurrentBlock())
            let result = RequireResult(term)
            currentBlock = successBlock
            return result
        }
        return RequireResult(builder.CreateApply(resultTy, callee, callContext, CurrentBlock()))
    }

    private func IsFunctionValueCall(expr: AstCallExpr): Bool {
        if (expr.resolvedFunction.isSome()) {
            return false
        }
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(baseTy) <- base.GetTy()) {
                if ((baseTy as AstFuncTy).isSome()) {
                    if (let Some(refExpr) <- (base as AstRefExpr)) {
                        if (let Some(target) <- refExpr.ref.target) {
                            return (target as AstFuncDecl).isNone()
                        }
                    }
                    if (let Some(member) <- (base as AstMemberAccess)) {
                        if (let Some(target) <- member.target) {
                            return (target as AstFuncDecl).isNone()
                        }
                    }
                    return true
                }
            }
        }
        return false
    }

    private func TranslateFunctionValueCall(expr: AstCallExpr): Value {
        let base = RequireExpr(expr.baseFunc, "function-value call base")
        let baseTy = base.GetTy() ??
            throw IllegalStateException("faithful AST2CHIR function-value call base has no type")
        let baseFuncTy = (baseTy as AstFuncTy) ??
            throw IllegalStateException("faithful AST2CHIR function-value call base is not a function type")
        let callee = Translator.TranslateASTNode(base, this) ??
            throw IllegalStateException("faithful AST2CHIR function-value call base produced no value")
        let argValues = ArrayList<Value>()
        var idx: Int64 = 0
        for (arg in expr.args) {
            if (let Some(argExpr) <- arg.expr) {
                var value = Translator.TranslateASTNode(argExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR function-value call arg produced no value")
                if (idx < baseFuncTy.paramTys.size) {
                    value = CoerceValueForExpectedType(value, chirTy.TranslateType(baseFuncTy.paramTys[idx]))
                }
                argValues.add(value)
            }
            idx++
        }
        return CreateApplyMaybeWithException(chirTy.TranslateType(RequireAstTy(expr)), callee,
            FuncCallContext(args: argValues))
    }

    private func CreateInvokeMaybeWithException(resultTy: Type, callContext: InvokeCallContext): Value {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "invoke-with-exception"))
            let term = builder.CreateInvokeWithException(resultTy, callContext, successBlock, errorBlock, CurrentBlock())
            let result = RequireResult(term)
            currentBlock = successBlock
            return result
        }
        return RequireResult(builder.CreateInvoke(resultTy, callContext, CurrentBlock()))
    }

    private func CreateInvokeStaticMaybeWithException(resultTy: Type, callContext: InvokeCallContext): Value {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(),
                "invoke-static-with-exception"))
            let term = builder.CreateInvokeStaticWithException(resultTy, callContext, successBlock, errorBlock,
                CurrentBlock())
            let result = RequireResult(term)
            currentBlock = successBlock
            return result
        }
        return RequireResult(builder.CreateInvokeStatic(resultTy, callContext, CurrentBlock()))
    }

    private func FuncParamTypes(expr: AstCallExpr, calleeDecl: AstFuncDecl): ArrayList<Type> {
        let out = ArrayList<Type>()
        let funcTy = CallBaseFuncTy(expr, calleeDecl)
        let genericParams = TranslateFuncGenericParams(calleeDecl)
        let replacements = TranslateFuncInstArgs(expr, calleeDecl)
        for (paramTy in funcTy.paramTys) {
            out.add(SubstituteGenericType(chirTy.TranslateType(paramTy), genericParams, replacements))
        }
        return out
    }

    private func TranslateEnumCtorRef(constructor: AstDecl, astTy: AstTy): Value {
        let args = ArrayList<Value>()
        args.add(CreateEnumSelectorConstant(constructor))
        return RequireResult(builder.CreateTuple(chirTy.TranslateType(astTy), args, CurrentBlock()))
    }

    private func TranslateMemberFuncCall(expr: AstCallExpr, calleeDecl: AstFuncDecl): Value {
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let argValues = ArrayList<Value>()
        var thisType: Option<Type> = None
        var thisObj: Option<Value> = None
        if (!calleeDecl.TestAttr(AstAttribute.STATIC)) {
            let obj = TranslateThisObjectForMemberFuncCall(expr, calleeDecl)
            thisObj = obj
            thisType = obj.GetType()
        }
        let expectedParamTys = FuncParamTypes(expr, calleeDecl)
        var idx: Int64 = 0
        for (arg in expr.args) {
            if (let Some(argExpr) <- arg.expr) {
                var value = Translator.TranslateASTNode(argExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR member call arg produced no value")
                if (idx < expectedParamTys.size) {
                    value = CoerceValueForExpectedType(value, expectedParamTys[idx])
                }
                argValues.add(value)
            }
            idx++
        }
        if (ShouldUseVirtualMemberDispatch(calleeDecl)) {
            if (calleeDecl.TestAttr(AstAttribute.STATIC)) {
                let parentTy = TranslateMemberOwnerType(calleeDecl)
                let rtti = RequireResult(builder.CreateGetRTTIStatic(builder.context.GetUnitTy(),
                    parentTy.StripAllRefs(), CurrentBlock()))
                let invokeCtx = InvokeCallContext(rtti, FuncCallContext(args: argValues,
                    instTypeArgs: TranslateFuncInstArgs(expr, calleeDecl), thisType: parentTy),
                    FuncSigInfo(BuildMethodFuncType(expr, calleeDecl, parentTy), funcName: calleeDecl.identifier.Val()))
                return CreateInvokeStaticMaybeWithException(resultTy, invokeCtx)
            }
            let obj = thisObj ?? throw IllegalStateException("faithful AST2CHIR virtual member call has no this object")
            let objTy = thisType ?? throw IllegalStateException("faithful AST2CHIR virtual member call this has no type")
            let invokeCtx = InvokeCallContext(obj, FuncCallContext(args: argValues,
                instTypeArgs: TranslateFuncInstArgs(expr, calleeDecl), thisType: objTy),
                FuncSigInfo(BuildMethodFuncType(expr, calleeDecl, objTy), funcName: calleeDecl.identifier.Val()))
            return CreateInvokeMaybeWithException(resultTy, invokeCtx)
        }
        if (let Some(obj) <- thisObj) {
            argValues.add(obj, at: 0)
        }
        let callee = globalSymbolTable.Get(calleeDecl)
        return CreateApplyMaybeWithException(resultTy, callee, FuncCallContext(args: argValues,
            instTypeArgs: TranslateFuncInstArgs(expr, calleeDecl), thisType: thisType))
    }

    private func TranslateFuncInstArgs(expr: AstCallExpr, calleeDecl: AstFuncDecl): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (calleeDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            return out
        }
        if (calleeDecl.TestAttr(AstAttribute.ENUM_CONSTRUCTOR)) {
            let resultArgs = TranslateEnumCtorInstArgsFromResult(expr, calleeDecl)
            if (!resultArgs.isEmpty()) {
                return resultArgs
            }
        }
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(nameRef) <- (base as AstNameReferenceExpr)) {
                for (instTy in nameRef.instTys) {
                    out.add(chirTy.TranslateType(instTy))
                }
            }
        }
        return out
    }

    private func TranslateEnumCtorInstArgsFromResult(expr: AstCallExpr, calleeDecl: AstFuncDecl): ArrayList<Type> {
        let out = ArrayList<Type>()
        let outer = calleeDecl.outerDecl ?? return out
        let enumDecl = (outer as AstEnumDecl) ?? return out
        if (let Some(astEnumTy) <- ((expr.GetTy() ?? AstTy.GetInitialTy()) as AstEnumTy)) {
            if (let Some(tyDecl) <- astEnumTy.declPtr) {
                if (!SameTranslatorAstDecl(tyDecl, enumDecl)) {
                    return out
                }
            }
            for (argTy in astEnumTy.typeArgs) {
                out.add(chirTy.TranslateType(argTy))
            }
        }
        return out
    }

    private func TranslateFuncGenericParams(calleeDecl: AstFuncDecl): ArrayList<GenericType> {
        let out = ArrayList<GenericType>()
        if (let Some(generic) <- calleeDecl.GetGeneric()) {
            for (param in generic.typeParameters) {
                if (let Some(paramTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (chirTy.TranslateType(paramTy) as GenericType)) {
                        out.add(genericTy)
                    }
                }
            }
        }
        if (out.isEmpty() && calleeDecl.TestAttr(AstAttribute.ENUM_CONSTRUCTOR)) {
            if (let Some(outer) <- calleeDecl.outerDecl) {
                if (let Some(enumDecl) <- (outer as AstEnumDecl)) {
                    if (let Some(generic) <- enumDecl.generic) {
                        for (param in generic.typeParameters) {
                            if (let Some(paramTy) <- param.GetTy()) {
                                if (let Some(genericTy) <- (chirTy.TranslateType(paramTy) as GenericType)) {
                                    out.add(genericTy)
                                }
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    private func SubstituteGenericType(ty: Type, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): Type {
        if (genericParams.isEmpty() || replacements.isEmpty()) {
            return ty
        }
        if (let Some(genericTy) <- (ty as GenericType)) {
            if (let Some(replacement) <- FindGenericReplacement(genericTy, genericParams, replacements)) {
                return replacement
            }
            return ty
        }
        if (let Some(refTy) <- (ty as RefType)) {
            return RefType(SubstituteGenericType(refTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            return RawArrayType(SubstituteGenericType(rawArrayTy.GetElementType(), genericParams, replacements),
                dims: rawArrayTy.GetDims())
        }
        if (let Some(varrayTy) <- (ty as VArrayType)) {
            return VArrayType(SubstituteGenericType(varrayTy.GetElementType(), genericParams, replacements),
                varrayTy.size)
        }
        if (let Some(pointerTy) <- (ty as CPointerType)) {
            return CPointerType(SubstituteGenericType(pointerTy.GetElementType(), genericParams, replacements))
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return BoxType(SubstituteGenericType(boxTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            return TupleType(SubstituteGenericTypeArgs(tupleTy.GetTypeArgs(), genericParams, replacements))
        }
        if (let Some(funcTy) <- (ty as FuncType)) {
            let params = SubstituteGenericTypeArgs(funcTy.GetParamTypes(), genericParams, replacements)
            let retTy = SubstituteGenericType(funcTy.GetReturnType(), genericParams, replacements)
            return FuncType(params, retTy, hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
        }
        if (let Some(structTy) <- (ty as StructType)) {
            return StructType(structTy.GetStructDef(),
                SubstituteGenericTypeArgs(structTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            return ClassType(classTy.GetClassDef(),
                SubstituteGenericTypeArgs(classTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(enumTy) <- (ty as EnumType)) {
            return EnumType(enumTy.GetEnumDef(),
                SubstituteGenericTypeArgs(enumTy.GetGenericArgs(), genericParams, replacements))
        }
        return ty
    }

    private func SubstituteGenericTypeArgs(args: ArrayList<Type>, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (arg in args) {
            out.add(SubstituteGenericType(arg, genericParams, replacements))
        }
        return out
    }

    private func FindGenericReplacement(genericTy: GenericType, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): Option<Type> {
        var idx: Int64 = 0
        while (idx < genericParams.size && idx < replacements.size) {
            if (genericTy.IsEqual(genericParams[idx])) {
                return Some(replacements[idx])
            }
            idx++
        }
        return None
    }

    private func TranslateThisObjectForMemberFuncCall(expr: AstCallExpr, calleeDecl: AstFuncDecl): Value {
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(member) <- (base as AstMemberAccess)) {
                if (let Some(baseExpr) <- member.baseExpr) {
                    if (IsThisOrSuperRef(baseExpr)) {
                        return GetCurrentThisObjectForMember(calleeDecl)
                    }
                    if (calleeDecl.TestAttr(AstAttribute.MUT)) {
                        let leftValue = TranslateExprAsLeftValue(baseExpr)
                        if (leftValue.path.isEmpty()) {
                            return leftValue.base
                        }
                        return LoadLeftValue(leftValue, chirTy.TranslateType(RequireAstTy(baseExpr))) ??
                            throw IllegalStateException("faithful AST2CHIR mut member call base produced no value")
                    }
                    return Translator.TranslateASTNode(baseExpr, this) ??
                        throw IllegalStateException("faithful AST2CHIR member call base produced no value")
                }
            }
        }
        return GetCurrentThisObjectForMember(calleeDecl)
    }

    private func GetCurrentThisObjectForMember(calleeDecl: AstFuncDecl): Value {
        let _ = calleeDecl
        return GetCurrentThisObject()
    }

    private func GetCurrentThisObject(): Value {
        let fn = CurrentFunction()
        if (fn.GetNumOfParams() > 0) {
            return fn.GetParam(0)
        }
        throw IllegalStateException("faithful AST2CHIR member access requires current this object")
    }

    private func ShouldUseVirtualMemberDispatch(funcDecl: AstFuncDecl): Bool {
        if (funcDecl.TestAnyAttr(AstAttribute.GENERIC_INSTANTIATED, AstAttribute.PRIMARY_CONSTRUCTOR,
            AstAttribute.CONSTRUCTOR)) {
            return false
        }
        let outer = funcDecl.outerDecl
        let funcHasOpenFlag = funcDecl.TestAnyAttr(AstAttribute.OPEN, AstAttribute.ABSTRACT) ||
            if (let Some(parent) <- outer) { parent.astKind == ASTKind.INTERFACE_DECL } else { false }
        if (funcDecl.TestAttr(AstAttribute.STATIC)) {
            return if (let Some(parent) <- outer) {
                parent.IsClassLikeDecl() && !funcDecl.TestAttr(AstAttribute.PRIVATE)
            } else {
                false
            }
        }
        return funcHasOpenFlag && funcDecl.TestAnyAttr(AstAttribute.PUBLIC, AstAttribute.PROTECTED)
    }

    private func TranslateMemberOwnerType(funcDecl: AstFuncDecl): Type {
        let outer = funcDecl.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR member function has no owner decl")
        return chirTy.TranslateType(RequireAstTy(outer))
    }

    private func BuildMethodFuncType(expr: AstCallExpr, funcDecl: AstFuncDecl, thisTy: Type): FuncType {
        let baseFuncTy = RequireFuncType(chirTy.TranslateType(CallBaseFuncTy(expr, funcDecl)))
        let params = baseFuncTy.GetParamTypes()
        if (!funcDecl.TestAttr(AstAttribute.STATIC)) {
            params.add(thisTy, at: 0)
        }
        return builder.context.GetFuncTy(params, baseFuncTy.GetReturnType())
    }

    private func IsThisOrSuperRef(expr: AstExpr): Bool {
        if (let Some(refExpr) <- (expr as AstRefExpr)) {
            return refExpr.isThis || refExpr.isSuper
        }
        return false
    }

    private func TranslateStructOrClassCtorCall(expr: AstCallExpr, calleeDecl: AstFuncDecl): Value {
        if (IsSuperOrThisCtorCall(expr)) {
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: this/super constructor call")
        }
        let thisTy = chirTy.TranslateType(RequireAstTy(expr)).StripAllRefs()
        let thisRefTy = builder.context.GetRefTy(thisTy)
        let thisObj = RequireResult(builder.CreateAllocate(thisRefTy, thisTy, CurrentBlock()))
        let args = ArrayList<Value>()
        args.add(thisObj)
        for (arg in expr.args) {
            if (let Some(argExpr) <- arg.expr) {
                let value = Translator.TranslateASTNode(argExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR constructor arg produced no value")
                args.add(value)
            }
        }
        let callee = globalSymbolTable.Get(calleeDecl)
        let _ = CreateApplyMaybeWithException(builder.context.GetUnitTy(), callee,
            FuncCallContext(args: args, thisType: thisRefTy))
        if (let Some(outerDecl) <- calleeDecl.outerDecl) {
            if (outerDecl.astKind == ASTKind.STRUCT_DECL) {
                return RequireResult(builder.CreateLoad(thisTy, thisObj, CurrentBlock()))
            }
        }
        return thisObj
    }

    private func IsStructOrClassCtorCall(expr: AstCallExpr, calleeDecl: AstFuncDecl): Bool {
        let _ = expr
        if (!calleeDecl.TestAttr(AstAttribute.CONSTRUCTOR) || calleeDecl.TestAttr(AstAttribute.STATIC)) {
            return false
        }
        if (let Some(outerDecl) <- calleeDecl.outerDecl) {
            return outerDecl.astKind == ASTKind.STRUCT_DECL || outerDecl.astKind == ASTKind.CLASS_DECL
        }
        return false
    }

    private func IsSuperOrThisCtorCall(expr: AstCallExpr): Bool {
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(refExpr) <- (base as AstRefExpr)) {
                return refExpr.isThis || refExpr.isSuper
            }
        }
        return false
    }

    private func CreateEnumSelectorConstant(constructor: AstDecl): Value {
        return CreateEnumSelectorConstant(GetEnumSelectorType(constructor), GetEnumCtorId(constructor))
    }

    private func CreateEnumSelectorConstantForName(enumTy: Type, ctorName: String): Value {
        return CreateEnumSelectorConstant(GetEnumSelectorType(enumTy), GetEnumCtorIdByName(enumTy, ctorName))
    }

    private func CreateEnumSelectorConstant(selectorTy: Type, enumId: Int64): Value {
        if (selectorTy.IsBoolean()) {
            return RequireResult(builder.CreateConstant(selectorTy, BoolLiteral(enumId != 0), CurrentBlock()))
        }
        return RequireResult(builder.CreateConstant(selectorTy, IntLiteral(enumId), CurrentBlock()))
    }

    private func GetEnumSelectorType(constructor: AstDecl): Type {
        let outer = constructor.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR enum constructor has no outer enum")
        let enumDecl = (outer as AstEnumDecl) ??
            throw IllegalStateException("faithful AST2CHIR enum constructor outer is not enum")
        return if (IsOptionLikeEnumDecl(enumDecl)) {
            builder.context.GetBoolTy()
        } else {
            builder.context.GetUInt32Ty()
        }
    }

    private func GetEnumSelectorType(ty: Type): Type {
        if (let Some(enumTy) <- (ty.StripAllRefs() as EnumType)) {
            return if (enumTy.GetEnumDef().IsOptionLike()) {
                builder.context.GetBoolTy()
            } else {
                builder.context.GetUInt32Ty()
            }
        }
        return builder.context.GetUInt32Ty()
    }

    private func IsOptionLikeEnumDecl(enumDecl: AstEnumDecl): Bool {
        if (enumDecl.hasEllipsis || enumDecl.constructors.size != 2) {
            return false
        }
        let firstPayloads = EnumCtorPayloadCount(enumDecl.constructors[0])
        let secondPayloads = EnumCtorPayloadCount(enumDecl.constructors[1])
        return (firstPayloads == 0 && secondPayloads == 1) ||
            (firstPayloads == 1 && secondPayloads == 0)
    }

    private func EnumCtorPayloadCount(constructor: AstDecl): Int64 {
        if (let Some(funcDecl) <- (constructor as AstFuncDecl)) {
            if (let Some(ctorTy) <- funcDecl.GetTy()) {
                if (let Some(funcTy) <- (ctorTy as AstFuncTy)) {
                    return funcTy.paramTys.size
                }
            }
        }
        return 0
    }

    private func GetEnumCtorIdByName(enumTy: Type, ctorName: String): Int64 {
        if (let Some(chirEnumTy) <- (enumTy.StripAllRefs() as EnumType)) {
            let ctors = chirEnumTy.GetEnumDef().GetCtors()
            var idx: Int64 = 0
            for (ctor in ctors) {
                if (ctor.name == ctorName) {
                    return idx
                }
                idx++
            }
        }
        return 0
    }

    private func GetEnumCtorId(constructor: AstDecl): Int64 {
        let outer = constructor.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR enum constructor has no outer enum")
        let enumDecl = (outer as AstEnumDecl) ??
            throw IllegalStateException("faithful AST2CHIR enum constructor outer is not enum")
        var idx: Int64 = 0
        for (ctor in enumDecl.constructors) {
            if (SameTranslatorAstDecl(ctor, constructor)) {
                return idx
            }
            idx++
        }
        throw IllegalStateException("faithful AST2CHIR enum constructor not found: ${constructor.identifier.Val()}")
    }

    private func FlattenVarWithPatternDecl(pattern: AstPattern, initValue: Option<Value>): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            HandleVarPatternDecl(varPattern, initValue)
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            HandleTuplePatternDecl(tuplePattern, initValue)
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            if (!enumPattern.patterns.isEmpty()) {
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: enum var-with-pattern payload")
            }
            return
        }
        if (let Some(_) <- (pattern as AstWildcardPattern)) {
            return
        }
        throw IllegalArgumentException(
            "not yet ported in faithful AST2CHIR var-with-pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func HandleVarPatternDecl(pattern: AstVarPattern, initValue: Option<Value>): Unit {
        let varDecl = pattern.varDecl ??
            throw IllegalStateException("faithful AST2CHIR var pattern has no VarDecl")
        let valueTy = chirTy.TranslateType(RequireAstTy(varDecl))
        let slot = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(valueTy), valueTy, CurrentBlock()))
        slot.SetSrcCodeIdentifier(varDecl.identifier.Val())
        localValSymbolTable.Set(varDecl, slot)
        if (let Some(value) <- initValue) {
            builder.CreateStore(CastValueIfNeeded(value, valueTy), slot, CurrentBlock())
        }
    }

    private func HandleTuplePatternDecl(pattern: AstTuplePattern, initValue: Option<Value>): Unit {
        var idx: Int64 = 0
        for (subPattern in pattern.patterns) {
            var fieldValue: Option<Value> = None
            if (let Some(value) <- initValue) {
                let path = ArrayList<UInt64>()
                path.add(UInt64(idx))
                fieldValue = RequireResult(builder.CreateField(chirTy.TranslateType(RequireAstTy(subPattern)),
                    GetDerefedValue(value), path, CurrentBlock()))
            }
            FlattenVarWithPatternDecl(subPattern, fieldValue)
            idx++
        }
    }

    private func TranslateTrivialAssign(expr: AstAssignExpr, leftExpr: AstExpr, rightExpr: AstExpr): Option<Value> {
        let _ = expr
        var rhsValue: Value
        var leftValueInfo: FaithfulLeftValueInfo
        if (leftExpr.mapExpr.isSome()) {
            leftValueInfo = TranslateExprAsLeftValue(leftExpr)
            rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR assign rhs produced no value")
        } else {
            rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR assign rhs produced no value")
            leftValueInfo = TranslateExprAsLeftValue(leftExpr)
        }
        StoreToLeftValue(leftValueInfo, rhsValue)
        return None
    }

    private func TranslateCompoundAssign(expr: AstAssignExpr, leftExpr: AstExpr, rightExpr: AstExpr): Option<Value> {
        if (expr.op == AstTokenKind.AND_ASSIGN || expr.op == AstTokenKind.OR_ASSIGN) {
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: short-circuit compound assignment")
        }
        let leftValueInfo = TranslateExprAsLeftValue(leftExpr)
        let lhsValue = LoadLeftValue(leftValueInfo, chirTy.TranslateType(RequireAstTy(leftExpr))) ??
            throw IllegalStateException("faithful AST2CHIR compound lhs produced no value")
        let rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR compound rhs produced no value")
        let opResult = builder.CreateBinaryExpression(ToCHIRCompoundAssignOp(expr.op),
            lhsValue.GetType() ?? chirTy.TranslateType(RequireAstTy(leftExpr)), lhsValue, rhsValue, CurrentBlock())
        let compoundValue = RequireResult(opResult)
        StoreToLeftValue(leftValueInfo, compoundValue)
        return None
    }

    private func TranslateSubscriptSetterAssign(assign: AstAssignExpr, subscriptExpr: AstSubscriptExpr,
        rightExpr: AstExpr): Bool {
        if (IsCompoundAssignOp(assign.op)) {
            return false
        }
        if (let Some(setter) <- FindSubscriptSetter(subscriptExpr, rightExpr)) {
            let baseExpr = RequireExpr(subscriptExpr.baseExpr, "subscript setter base")
            let baseInfo = TranslateExprAsLeftValue(baseExpr)
            let baseTy = chirTy.TranslateType(RequireAstTy(baseExpr))
            let callee = GetSymbolTable(setter)
            let thisObj = TranslateSubscriptSetterThisObject(callee, baseInfo, baseTy)
            let thisTy = thisObj.GetType()
            let indexExprs = GetSubscriptIndexExprs(subscriptExpr)
            let args = ArrayList<Value>()
            args.add(thisObj)
            let expectedParamTys = FuncDeclParamTypes(setter)
            var idx: Int64 = 0
            for (indexExpr in indexExprs) {
                var indexValue = Translator.TranslateASTNode(indexExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR subscript setter index produced no value")
                if (idx < expectedParamTys.size && !expectedParamTys[idx].IsGeneric()) {
                    indexValue = CoerceValueForExpectedType(indexValue, expectedParamTys[idx])
                }
                args.add(indexValue)
                idx++
            }
            var rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR subscript setter rhs produced no value")
            if (idx < expectedParamTys.size && !expectedParamTys[idx].IsGeneric()) {
                rhsValue = CoerceValueForExpectedType(rhsValue, expectedParamTys[idx])
            }
            args.add(rhsValue)
            let _ = CreateApplyMaybeWithException(builder.context.GetUnitTy(), callee,
                FuncCallContext(args: args, thisType: thisTy))
            return true
        }
        return false
    }

    private func TranslateSubscriptSetterThisObject(callee: Value, baseInfo: FaithfulLeftValueInfo,
        baseTy: Type): Value {
        if (let Some(calleeTy) <- callee.GetType()) {
            if (let Some(funcTy) <- (calleeTy as FuncType)) {
                if (funcTy.GetNumOfParams() > 0 && !funcTy.GetParamType(0).IsRef()) {
                    return LoadLeftValue(baseInfo, baseTy) ??
                        throw IllegalStateException("faithful AST2CHIR subscript setter base produced no value")
                }
            }
        }
        return AddressOfLeftValue(baseInfo, baseTy)
    }

    private func GetSubscriptIndexExprs(subscriptExpr: AstSubscriptExpr): ArrayList<AstExpr> {
        let out = ArrayList<AstExpr>()
        for (indexExpr in subscriptExpr.indexExprs) {
            out.add(indexExpr)
        }
        if (!out.isEmpty()) {
            return out
        }
        if (let Some(desugar) <- subscriptExpr.desugarExpr) {
            if (let Some(callExpr) <- (desugar as AstCallExpr)) {
                for (arg in callExpr.args) {
                    if (let Some(argExpr) <- arg.expr) {
                        out.add(argExpr)
                    }
                }
            }
        }
        return out
    }

    private func FindSubscriptSetter(subscriptExpr: AstSubscriptExpr, rightExpr: AstExpr): Option<AstFuncDecl> {
        if (let Some(desugar) <- subscriptExpr.desugarExpr) {
            if (let Some(callExpr) <- (desugar as AstCallExpr)) {
                if (let Some(baseFunc) <- callExpr.baseFunc) {
                    for (target in baseFunc.GetTargets()) {
                        if (let Some(funcDecl) <- (target as AstFuncDecl)) {
                            if (IsSubscriptSetterCandidate(funcDecl, subscriptExpr, rightExpr)) {
                                return Some(funcDecl)
                            }
                        }
                    }
                    if (let Some(target) <- baseFunc.GetTarget()) {
                        if (let Some(funcDecl2) <- (target as AstFuncDecl)) {
                            if (IsSubscriptSetterCandidate(funcDecl2, subscriptExpr, rightExpr)) {
                                return Some(funcDecl2)
                            }
                        }
                        if (let Some(owner) <- target.outerDecl) {
                            if (let Some(ownerCandidate) <- FindSubscriptSetterInDecl(owner, subscriptExpr,
                                rightExpr)) {
                                return Some(ownerCandidate)
                            }
                        }
                    }
                }
            }
        }
        if (let Some(baseExpr) <- subscriptExpr.baseExpr) {
            if (let Some(baseDecl) <- AstTy.GetDeclPtrOfTy(baseExpr.GetTy())) {
                if (let Some(baseCandidate) <- FindSubscriptSetterInDecl(baseDecl, subscriptExpr, rightExpr)) {
                    return Some(baseCandidate)
                }
            }
        }
        return None
    }

    private func FindSubscriptSetterInDecl(owner: AstDecl, subscriptExpr: AstSubscriptExpr,
        rightExpr: AstExpr): Option<AstFuncDecl> {
        for (member in owner.GetMemberDecls()) {
            if (let Some(funcDecl) <- (member as AstFuncDecl)) {
                if (IsSubscriptSetterCandidate(funcDecl, subscriptExpr, rightExpr)) {
                    return Some(funcDecl)
                }
            }
        }
        return None
    }

    private func IsSubscriptSetterCandidate(funcDecl: AstFuncDecl, subscriptExpr: AstSubscriptExpr,
        rightExpr: AstExpr): Bool {
        if (funcDecl.identifier.Val() != "[]") {
            return false
        }
        let funcTy = FuncDeclAstFuncTy(funcDecl) ?? return false
        let indexExprs = GetSubscriptIndexExprs(subscriptExpr)
        if (!funcTy.retTy.IsUnit() || funcTy.paramTys.size != indexExprs.size + 1) {
            return false
        }
        var idx: Int64 = 0
        for (indexExpr in indexExprs) {
            let indexTy = indexExpr.GetTy() ?? return false
            if (!AstParamAcceptsArg(funcTy.paramTys[idx], indexTy)) {
                return false
            }
            idx++
        }
        let rhsTy = rightExpr.GetTy() ?? return false
        return AstParamAcceptsArg(funcTy.paramTys[idx], rhsTy)
    }

    private func AstParamAcceptsArg(paramTy: AstTy, argTy: AstTy): Bool {
        return paramTy.IsGeneric() || paramTy.String() == argTy.String()
    }

    private func FuncDeclParamTypes(funcDecl: AstFuncDecl): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (let Some(funcTy) <- FuncDeclAstFuncTy(funcDecl)) {
            for (paramTy in funcTy.paramTys) {
                out.add(chirTy.TranslateType(paramTy))
            }
        }
        return out
    }

    private func FuncDeclAstFuncTy(funcDecl: AstFuncDecl): Option<AstFuncTy> {
        if (let Some(declTy) <- funcDecl.GetTy()) {
            if (let Some(funcTy) <- (declTy as AstFuncTy)) {
                return Some(funcTy)
            }
        }
        return None
    }

    private func TranslateVArrayAssign(assign: AstAssignExpr, subscriptExpr: AstSubscriptExpr, rightExpr: AstExpr): Unit {
        if (IsCompoundAssignOp(assign.op)) {
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: compound VArray assignment")
        }
        if (subscriptExpr.indexExprs.size != 1) {
            throw IllegalArgumentException("faithful AST2CHIR VArray assignment expects exactly one index")
        }
        let baseExpr = RequireExpr(subscriptExpr.baseExpr, "VArray assign base")
        let baseLeftValueInfo = TranslateExprAsLeftValue(baseExpr)
        if (!baseLeftValueInfo.path.isEmpty()) {
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: nested VArray assignment base path")
        }
        let indexValue = Translator.TranslateASTNode(subscriptExpr.indexExprs[0], this) ??
            throw IllegalStateException("faithful AST2CHIR VArray assignment index produced no value")
        let rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR VArray assignment rhs produced no value")
        let args = ArrayList<Value>()
        args.add(baseLeftValueInfo.base)
        args.add(rhsValue)
        args.add(indexValue)
        let callContext = IntrisicCallContext(kind: IntrinsicKind.VARRAY_SET, args: args)
        builder.CreateIntrinsic(builder.context.GetUnitTy(), callContext, CurrentBlock())
    }

    private func TranslateExprAsLeftValue(expr: AstExpr): FaithfulLeftValueInfo {
        let nodePtr = Translator.GetDesugaredExpr(expr)
        if (let Some(refExpr) <- (nodePtr as AstRefExpr)) {
            let refName = refExpr.ref.identifier.Val()
            if (refExpr.isThis || refExpr.isSuper || refName == "this" || refName == "super") {
                return FaithfulLeftValueInfo(GetCurrentThisObject(), ArrayList<String>())
            }
            if (let Some(target) <- refExpr.ref.target) {
                if (let Some(varDecl) <- (target as AstVarDecl)) {
                    if (IsInstanceMember(varDecl)) {
                        return TranslateInstanceFieldRefAsLeftValue(varDecl)
                    }
                    return FaithfulLeftValueInfo(GetSymbolTable(target), ArrayList<String>())
                }
            }
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: non-variable RefExpr left value")
        }
        if (let Some(member) <- (nodePtr as AstMemberAccess)) {
            return TranslateMemberAccessAsLeftValue(member)
        }
        if (let Some(_) <- (nodePtr as AstSubscriptExpr)) {
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: tuple/subscript left value")
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR left value: ${ASTKindName(nodePtr.astKind)}")
    }

    private func TranslateMemberAccessAsLeftValue(member: AstMemberAccess): FaithfulLeftValueInfo {
        let target = ResolveMemberAccessTarget(member, "faithful AST2CHIR MemberAccess left value")
        if (target.TestAttr(AstAttribute.ENUM_CONSTRUCTOR)) {
            let value = Visit(member) ??
                throw IllegalStateException("faithful AST2CHIR enum member access produced no value")
            return FaithfulLeftValueInfo(value, ArrayList<String>())
        }
        if (target.TestAttr(AstAttribute.STATIC) || IsPackageMemberAccess(member)) {
            return FaithfulLeftValueInfo(GetSymbolTable(target), ArrayList<String>())
        }
        if (let Some(varDecl) <- (target as AstVarDecl)) {
            if (let Some(baseExpr) <- member.baseExpr) {
                let baseInfo = NormalizeMemberBaseLeftValue(TranslateExprAsLeftValue(baseExpr), baseExpr)
                let path = CopyStringList(baseInfo.path)
                path.add(varDecl.identifier.Val())
                return FaithfulLeftValueInfo(baseInfo.base, path)
            }
            return TranslateInstanceFieldRefAsLeftValue(varDecl)
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: member function left value")
    }

    private func TranslateInstanceFieldRefAsLeftValue(varDecl: AstVarDecl): FaithfulLeftValueInfo {
        let path = ArrayList<String>()
        path.add(varDecl.identifier.Val())
        return FaithfulLeftValueInfo(GetCurrentThisObject(), path)
    }

    private func NormalizeMemberBaseLeftValue(info: FaithfulLeftValueInfo, baseExpr: AstExpr): FaithfulLeftValueInfo {
        var base = info.base
        var path = CopyStringList(info.path)
        let baseTy = base.GetType() ??
            throw IllegalStateException("faithful AST2CHIR member base has no type: ${base.GetIdentifier()}")
        if (path.isEmpty()) {
            if (baseTy.IsReferenceTypeWithRefDims(CLASS_REF_DIM)) {
                let loadedTy = RequireRefBaseType(base)
                base = RequireResult(builder.CreateLoad(loadedTy, base, CurrentBlock()))
            }
            return FaithfulLeftValueInfo(base, path)
        }
        let loaded = LoadLeftValue(info, chirTy.TranslateType(RequireAstTy(baseExpr))) ??
            throw IllegalStateException("faithful AST2CHIR member base produced no value")
        path.clear()
        return FaithfulLeftValueInfo(loaded, path)
    }

    private func AddressOfLeftValue(info: FaithfulLeftValueInfo, expectedTy: Type): Value {
        if (info.path.isEmpty()) {
            return info.base
        }
        let refTy = builder.context.GetRefTy(expectedTy)
        return RequireResult(builder.CreateGetElementByName(refTy, info.base, info.path, CurrentBlock()))
    }

    private func LoadLeftValue(info: FaithfulLeftValueInfo, expectedTy: Type): Option<Value> {
        if (info.path.isEmpty()) {
            return GetDerefedValue(info.base)
        }
        let baseTy = info.base.GetType() ??
            throw IllegalStateException("faithful AST2CHIR left value base has no type: ${info.base.GetIdentifier()}")
        if (baseTy.IsReferenceTypeWithRefDims(1) || baseTy.IsValueOrGenericTypeWithRefDims(1)) {
            let refTy = builder.context.GetRefTy(expectedTy)
            let memberRef = RequireResult(builder.CreateGetElementByName(refTy, info.base, info.path, CurrentBlock()))
            return RequireResult(builder.CreateLoad(expectedTy, memberRef, CurrentBlock()))
        }
        if (baseTy.IsValueOrGenericTypeWithRefDims(0)) {
            return RequireResult(builder.CreateFieldByName(expectedTy, info.base, info.path, CurrentBlock()))
        }
        throw IllegalStateException("faithful AST2CHIR unsupported member left value base type: ${baseTy.ToString()}")
    }

    private func StoreToLeftValue(info: FaithfulLeftValueInfo, value: Value): Unit {
        if (info.path.isEmpty()) {
            builder.CreateStore(CastValueIfNeeded(value, RequireRefBaseType(info.base)), info.base, CurrentBlock())
            return
        }
        builder.CreateStoreElementByName(value, info.base, info.path, CurrentBlock())
    }

    private func TranslateStaticTargetOrPackageMemberAccess(expr: AstMemberAccess, target: AstDecl): Option<Value> {
        let targetNode = GetSymbolTable(target)
        if (let Some(_) <- (target as AstVarDecl)) {
            let targetTy = chirTy.TranslateType(RequireAstTy(target))
            let loaded = RequireResult(builder.CreateLoad(targetTy, targetNode, CurrentBlock()))
            return CastValueIfNeeded(loaded, chirTy.TranslateType(RequireAstTy(expr)))
        }
        if (let Some(_) <- (target as AstFuncDecl)) {
            if (target.outerDecl.isSome()) {
                throw IllegalArgumentException(
                    "not yet ported in faithful AST2CHIR: static member method reference lambda wrapper")
            }
            return targetNode
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: static/package member target")
    }

    private func IsPackageMemberAccess(expr: AstMemberAccess): Bool {
        let _ = expr
        if (let Some(target) <- expr.target) {
            return target.TestAttr(AstAttribute.GLOBAL)
        }
        return false
    }

    private func IsInstanceMember(decl: AstDecl): Bool {
        return decl.outerDecl.isSome() && !decl.TestAttr(AstAttribute.STATIC) && !decl.TestAttr(AstAttribute.GLOBAL)
    }

    private func RequireRefBaseType(value: Value): Type {
        let ty = value.GetType() ??
            throw IllegalStateException("faithful AST2CHIR value has no type: ${value.GetIdentifier()}")
        if (let Some(refTy) <- (ty as RefType)) {
            return refTy.GetBaseType()
        }
        throw IllegalStateException("faithful AST2CHIR expected ref left value, got ${ty.ToString()}")
    }

    private func CastValueIfNeeded(value: Value, expectedTy: Type): Value {
        let valueTy = value.GetType() ??
            throw IllegalStateException("faithful AST2CHIR value has no type: ${value.GetIdentifier()}")
        if (valueTy.IsEqual(expectedTy)) {
            return value
        }
        return RequireResult(builder.CreateTypeCast(expectedTy, value, CurrentBlock()))
    }

    private func BoxOrCastValueIfNeeded(value: Value, expectedTy: Type): Value {
        let valueTy = value.GetType() ??
            throw IllegalStateException("faithful AST2CHIR value has no type: ${value.GetIdentifier()}")
        if (valueTy.IsEqual(expectedTy)) {
            return value
        }
        if (let Some(refTy) <- (expectedTy as RefType)) {
            if (valueTy.IsEqual(refTy.GetBaseType())) {
                let slot = RequireResult(builder.CreateAllocate(expectedTy, valueTy, CurrentBlock()))
                builder.CreateStore(value, slot, CurrentBlock())
                return slot
            }
        }
        return RequireResult(builder.CreateTypeCast(expectedTy, value, CurrentBlock()))
    }

    private func CoerceValueForExpectedType(value: Value, expectedTy: Type): Value {
        let valueTy = value.GetType() ??
            throw IllegalStateException("faithful AST2CHIR value has no type: ${value.GetIdentifier()}")
        if (valueTy.IsEqual(expectedTy)) {
            return value
        }
        if (let Some(refTy) <- (valueTy as RefType)) {
            if (refTy.GetBaseType().IsEqual(expectedTy)) {
                return RequireResult(builder.CreateLoad(expectedTy, value, CurrentBlock()))
            }
        }
        if (let Some(expectedRefTy) <- (expectedTy as RefType)) {
            if (valueTy.IsEqual(expectedRefTy.GetBaseType())) {
                let slot = RequireResult(builder.CreateAllocate(expectedTy, valueTy, CurrentBlock()))
                builder.CreateStore(value, slot, CurrentBlock())
                return slot
            }
        }
        return RequireResult(builder.CreateTypeCast(expectedTy, value, CurrentBlock()))
    }

    private func CopyStringList(values: ArrayList<String>): ArrayList<String> {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(value)
        }
        return out
    }

    private func GetSymbolTable(decl: AstDecl): Value {
        if (let Some(value) <- localValSymbolTable.TryGet(decl)) {
            return value
        }
        return globalSymbolTable.Get(decl)
    }

    private func GetDerefedValue(value: Value): Value {
        if (let Some(ty) <- value.GetType()) {
            if (ty.IsReferenceTypeWithRefDims(1)) {
                return value
            }
            if (let Some(refTy) <- (ty as RefType)) {
                return RequireResult(builder.CreateLoad(refTy.GetBaseType(), value, CurrentBlock()))
            }
        }
        return value
    }

    private func CurrentBlock(): Block {
        return currentBlock ?? throw IllegalStateException("faithful AST2CHIR has no current block")
    }

    private func RequireParentBlockGroup(block: Block, context: String): BlockGroup {
        return block.GetParentBlockGroup() ??
            throw IllegalStateException("faithful AST2CHIR ${context} requires parent block group")
    }

    private func TranslateLitConstant(expr: AstLitConstExpr): LiteralValue {
        return match (expr.kind) {
            case AstLitConstKind.BOOL => BoolLiteral(expr.stringValue == "true")
            case AstLitConstKind.UNIT => UnitLiteral()
            case AstLitConstKind.INTEGER => IntLiteral(expr.constNumValue.asInt.`Int64`())
            case AstLitConstKind.RUNE_BYTE => IntLiteral(expr.constNumValue.asInt.`Int64`())
            case AstLitConstKind.FLOAT => FloatLiteral(expr.constNumValue.asFloat.value)
            case AstLitConstKind.RUNE =>
                let value = if (expr.codepoint.isEmpty()) { r'\0' } else { Rune(expr.codepoint[0]) }
                RuneLiteral(value)
            case AstLitConstKind.STRING => StringLiteral(expr.stringValue)
            case AstLitConstKind.JSTRING => StringLiteral(expr.stringValue)
            case AstLitConstKind.NONE =>
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: literal NONE")
        }
    }

    private func ToCHIRBinaryOp(op: AstTokenKind): ExprKind {
        return match (op) {
            case AstTokenKind.ADD => ExprKind.ADD
            case AstTokenKind.SUB => ExprKind.SUB
            case AstTokenKind.MUL => ExprKind.MUL
            case AstTokenKind.DIV => ExprKind.DIV
            case AstTokenKind.MOD => ExprKind.MOD
            case AstTokenKind.EXP => ExprKind.EXP
            case AstTokenKind.LSHIFT => ExprKind.LSHIFT
            case AstTokenKind.RSHIFT => ExprKind.RSHIFT
            case AstTokenKind.BITAND => ExprKind.BITAND
            case AstTokenKind.BITOR => ExprKind.BITOR
            case AstTokenKind.BITXOR => ExprKind.BITXOR
            case AstTokenKind.LT => ExprKind.LT
            case AstTokenKind.GT => ExprKind.GT
            case AstTokenKind.LE => ExprKind.LE
            case AstTokenKind.GE => ExprKind.GE
            case AstTokenKind.EQUAL => ExprKind.EQUAL
            case AstTokenKind.NOTEQ => ExprKind.NOTEQUAL
            case AstTokenKind.AND => ExprKind.AND
            case AstTokenKind.OR => ExprKind.OR
            case _ => throw IllegalArgumentException(
                "not yet ported in faithful AST2CHIR binary op: ${AstTokenKindValue(op)}")
        }
    }

    private func ToCHIRUnaryOp(op: AstTokenKind): ExprKind {
        return match (op) {
            case AstTokenKind.SUB => ExprKind.NEG
            case AstTokenKind.NOT => ExprKind.NOT
            case AstTokenKind.BITNOT => ExprKind.BITNOT
            case _ => throw IllegalArgumentException(
                "not yet ported in faithful AST2CHIR unary op: ${AstTokenKindValue(op)}")
        }
    }

    private func IsCompoundAssignOp(op: AstTokenKind): Bool {
        return match (op) {
            case AstTokenKind.ADD_ASSIGN => true
            case AstTokenKind.SUB_ASSIGN => true
            case AstTokenKind.MUL_ASSIGN => true
            case AstTokenKind.EXP_ASSIGN => true
            case AstTokenKind.DIV_ASSIGN => true
            case AstTokenKind.MOD_ASSIGN => true
            case AstTokenKind.AND_ASSIGN => true
            case AstTokenKind.OR_ASSIGN => true
            case AstTokenKind.BITAND_ASSIGN => true
            case AstTokenKind.BITOR_ASSIGN => true
            case AstTokenKind.BITXOR_ASSIGN => true
            case AstTokenKind.LSHIFT_ASSIGN => true
            case AstTokenKind.RSHIFT_ASSIGN => true
            case _ => false
        }
    }

    private func ToCHIRCompoundAssignOp(op: AstTokenKind): ExprKind {
        return match (op) {
            case AstTokenKind.ADD_ASSIGN => ExprKind.ADD
            case AstTokenKind.SUB_ASSIGN => ExprKind.SUB
            case AstTokenKind.MUL_ASSIGN => ExprKind.MUL
            case AstTokenKind.EXP_ASSIGN => ExprKind.EXP
            case AstTokenKind.DIV_ASSIGN => ExprKind.DIV
            case AstTokenKind.MOD_ASSIGN => ExprKind.MOD
            case AstTokenKind.BITAND_ASSIGN => ExprKind.BITAND
            case AstTokenKind.BITOR_ASSIGN => ExprKind.BITOR
            case AstTokenKind.BITXOR_ASSIGN => ExprKind.BITXOR
            case AstTokenKind.LSHIFT_ASSIGN => ExprKind.LSHIFT
            case AstTokenKind.RSHIFT_ASSIGN => ExprKind.RSHIFT
            case _ => throw IllegalArgumentException(
                "not yet ported in faithful AST2CHIR compound assign op: ${AstTokenKindValue(op)}")
        }
    }

    private func ResolveCalleeFromBase(expr: AstCallExpr): AstFuncDecl {
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(ref) <- (base as AstRefExpr)) {
                if (let Some(target) <- ref.ref.target) {
                    if (let Some(fn) <- (target as AstFuncDecl)) {
                        return fn
                    }
                }
            }
            if (let Some(member) <- (base as AstMemberAccess)) {
                let target = ResolveMemberAccessTarget(member, "faithful AST2CHIR CallExpr member callee")
                if (let Some(fn) <- (target as AstFuncDecl)) {
                    return fn
                }
            }
        }
        throw IllegalStateException("faithful AST2CHIR CallExpr has no resolvedFunction")
    }

    private func ResolveMemberAccessTarget(member: AstMemberAccess, context: String): AstDecl {
        if (let Some(target) <- member.target) {
            return target
        }
        if (member.targets.size == 1) {
            return member.targets[0]
        }
        if (let Some(target) <- ResolveMemberAccessTargetFromBase(member)) {
            return target
        }
        if (let Some(target) <- ResolveMemberTargetFromCurrentThis(member.field.Val(), false)) {
            return target
        }
        throw IllegalStateException(
            "${context} has no single Sema target: ${member.field.Val()} (${member.targets.size} candidates)")
    }

    private func MemberAccessValueType(member: AstMemberAccess, target: AstDecl): Type {
        if (let Some(memberTy) <- member.GetTy()) {
            if (AstTy.IsTyCorrect(memberTy)) {
                return chirTy.TranslateType(memberTy)
            }
        }
        return chirTy.TranslateType(RequireAstTy(target))
    }

    private func ResolveMemberAccessTargetFromBase(member: AstMemberAccess): Option<AstDecl> {
        if (let Some(baseExpr) <- member.baseExpr) {
            let baseNode = Translator.GetDesugaredExpr(baseExpr)
            if (let Some(refExpr) <- (baseNode as AstRefExpr)) {
                if (refExpr.isThis || refExpr.isSuper) {
                    return ResolveMemberTargetFromCurrentThis(member.field.Val(), refExpr.isSuper)
                }
            }
            if (let Some(desugaredBase) <- (baseNode as AstExpr)) {
                if (let Some(baseTy) <- desugaredBase.GetTy()) {
                    return ResolveMemberTargetFromAstTy(baseTy, member.field.Val())
                }
            }
        }
        return None
    }

    private func ResolveMemberTargetFromCurrentThis(fieldName: String, isSuper: Bool): Option<AstDecl> {
        if (let Some(funcDecl) <- currentAstFuncDecl) {
            if (let Some(owner) <- funcDecl.outerDecl) {
                if (isSuper) {
                    if (let Some(classDecl) <- (owner as AstClassDecl)) {
                        if (let Some(superDecl) <- classDecl.GetSuperClassDecl()) {
                            return FindClassMemberDecl(superDecl, fieldName)
                        }
                    }
                    return None
                }
                return FindMemberTargetInDecl(owner, fieldName)
            }
        }
        return None
    }

    private func FindMemberTargetInDecl(owner: AstDecl, fieldName: String): Option<AstDecl> {
        if (let Some(classDecl) <- (owner as AstClassDecl)) {
            return FindClassMemberDecl(classDecl, fieldName)
        }
        if (let Some(structDecl) <- (owner as AstStructDecl)) {
            return FindMemberDecl(structDecl.GetMemberDeclPtrs(), fieldName)
        }
        if (let Some(interfaceDecl) <- (owner as AstInterfaceDecl)) {
            return FindMemberDecl(interfaceDecl.GetMemberDeclPtrs(), fieldName)
        }
        if (let Some(enumDecl) <- (owner as AstEnumDecl)) {
            return FindMemberDecl(enumDecl.GetMemberDeclPtrs(), fieldName)
        }
        return None
    }

    private func ResolveMemberTargetFromAstTy(baseTy: AstTy, fieldName: String): Option<AstDecl> {
        if (let Some(classTy) <- (baseTy as AstClassTy)) {
            if (let Some(classDecl) <- classTy.decl) {
                return FindClassMemberDecl(classDecl, fieldName)
            }
            if (let Some(classDecl) <- classTy.declPtr) {
                return FindClassMemberDecl(classDecl, fieldName)
            }
        }
        if (let Some(structTy) <- (baseTy as AstStructTy)) {
            if (let Some(structDecl) <- structTy.decl) {
                return FindMemberDecl(structDecl.GetMemberDeclPtrs(), fieldName)
            }
            if (let Some(structDecl) <- structTy.declPtr) {
                return FindMemberDecl(structDecl.GetMemberDeclPtrs(), fieldName)
            }
        }
        if (let Some(interfaceTy) <- (baseTy as AstInterfaceTy)) {
            if (let Some(interfaceDecl) <- interfaceTy.decl) {
                return FindMemberDecl(interfaceDecl.GetMemberDeclPtrs(), fieldName)
            }
            if (let Some(interfaceDecl) <- interfaceTy.declPtr) {
                return FindMemberDecl(interfaceDecl.GetMemberDeclPtrs(), fieldName)
            }
        }
        if (let Some(enumTy) <- (baseTy as AstEnumTy)) {
            if (let Some(enumDecl) <- enumTy.decl) {
                return FindMemberDecl(enumDecl.GetMemberDeclPtrs(), fieldName)
            }
            if (let Some(enumDecl) <- enumTy.declPtr) {
                return FindMemberDecl(enumDecl.GetMemberDeclPtrs(), fieldName)
            }
        }
        return None
    }

    private func FindClassMemberDecl(classDecl: AstClassDecl, fieldName: String): Option<AstDecl> {
        var current: Option<AstClassDecl> = classDecl
        while (let Some(currentDecl) <- current) {
            if (let Some(found) <- FindMemberDecl(currentDecl.GetMemberDeclPtrs(), fieldName)) {
                return found
            }
            current = currentDecl.GetSuperClassDecl()
        }
        return None
    }

    private func FindMemberDecl(members: ArrayList<AstDecl>, fieldName: String): Option<AstDecl> {
        for (member in members) {
            if (member.identifier.Val() == fieldName) {
                return member
            }
        }
        return None
    }

    private func UnwrapClassType(ty: Type): ClassType {
        if (let Some(refTy) <- (ty as RefType)) {
            if (let Some(classTy) <- (refTy.GetBaseType() as ClassType)) {
                return classTy
            }
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            return classTy
        }
        throw IllegalStateException("faithful AST2CHIR expected class type, got ${ty.ToString()}")
    }

    private func RequireResult(expr: Expression): LocalVar {
        return expr.GetResult() ?? throw IllegalStateException("faithful AST2CHIR expression has no result")
    }

    private func RequireAstTy(node: AstNode): AstTy {
        return node.GetTy() ??
            throw IllegalStateException("faithful AST2CHIR requires Sema type for ${ASTKindName(node.astKind)}")
    }

    private func RequireExpr(value: Option<AstExpr>, name: String): AstExpr {
        return value ?? throw IllegalStateException("faithful AST2CHIR missing ${name}")
    }

    private func RequireBlock(value: Option<AstBlock>, name: String): AstBlock {
        return value ?? throw IllegalStateException("faithful AST2CHIR missing ${name}")
    }

    private func RequireBlockExpr(value: Option<AstExpr>, name: String): AstBlock {
        let expr = value ?? throw IllegalStateException("faithful AST2CHIR missing ${name}")
        return (expr as AstBlock) ?? throw IllegalStateException("faithful AST2CHIR ${name} is not a Block")
    }

    private func RequireFuncArgExpr(value: AstFuncArg, name: String): AstExpr {
        return value.expr ?? throw IllegalStateException("faithful AST2CHIR missing ${name}")
    }

    private func RequirePattern(value: Option<AstPattern>, name: String): AstPattern {
        return value ?? throw IllegalStateException("faithful AST2CHIR missing ${name}")
    }

    private func RequireStructDef(def: CustomTypeDef): StructDef {
        return (def as StructDef) ?? throw IllegalStateException("faithful AST2CHIR expected StructDef")
    }

    private func RequireClassDef(def: CustomTypeDef): ClassDef {
        return (def as ClassDef) ?? throw IllegalStateException("faithful AST2CHIR expected ClassDef")
    }

    private func RequireEnumDef(def: CustomTypeDef): EnumDef {
        return (def as EnumDef) ?? throw IllegalStateException("faithful AST2CHIR expected EnumDef")
    }

    private func RequireExtendDef(def: CustomTypeDef): ExtendDef {
        return (def as ExtendDef) ?? throw IllegalStateException("faithful AST2CHIR expected ExtendDef")
    }

    private func RequireStructType(ty: Type): StructType {
        return (ty as StructType) ?? throw IllegalStateException("faithful AST2CHIR expected StructType")
    }

    private func RequireEnumType(ty: Type): EnumType {
        return (ty as EnumType) ?? throw IllegalStateException("faithful AST2CHIR expected EnumType")
    }

    private func RequireVArrayType(ty: Type): VArrayType {
        return (ty as VArrayType) ?? throw IllegalStateException("faithful AST2CHIR expected VArrayType")
    }

    private func RequireRawArrayType(ty: Type): RawArrayType {
        return (ty as RawArrayType) ?? throw IllegalStateException("faithful AST2CHIR expected RawArrayType")
    }

    private func RequireFuncType(ty: Type): FuncType {
        return (ty as FuncType) ?? throw IllegalStateException("faithful AST2CHIR expected FuncType")
    }

    private static func RequireNodeAsFuncDecl(node: AstNode): AstFuncDecl {
        return (node as AstFuncDecl) ?? throw IllegalArgumentException("ASTKind cast failed: FUNC_DECL")
    }

    private static func RequireNodeAsMainDecl(node: AstNode): AstMainDecl {
        return (node as AstMainDecl) ?? throw IllegalArgumentException("ASTKind cast failed: MAIN_DECL")
    }

    private static func RequireNodeAsStructDecl(node: AstNode): AstStructDecl {
        return (node as AstStructDecl) ?? throw IllegalArgumentException("ASTKind cast failed: STRUCT_DECL")
    }

    private static func RequireNodeAsClassDecl(node: AstNode): AstClassDecl {
        return (node as AstClassDecl) ?? throw IllegalArgumentException("ASTKind cast failed: CLASS_DECL")
    }

    private static func RequireNodeAsInterfaceDecl(node: AstNode): AstInterfaceDecl {
        return (node as AstInterfaceDecl) ?? throw IllegalArgumentException("ASTKind cast failed: INTERFACE_DECL")
    }

    private static func RequireNodeAsEnumDecl(node: AstNode): AstEnumDecl {
        return (node as AstEnumDecl) ?? throw IllegalArgumentException("ASTKind cast failed: ENUM_DECL")
    }

    private static func RequireNodeAsExtendDecl(node: AstNode): AstExtendDecl {
        return (node as AstExtendDecl) ?? throw IllegalArgumentException("ASTKind cast failed: EXTEND_DECL")
    }

    private static func RequireNodeAsVarDecl(node: AstNode): AstVarDecl {
        return (node as AstVarDecl) ?? throw IllegalArgumentException("ASTKind cast failed: VAR_DECL")
    }

    private static func RequireNodeAsBlock(node: AstNode): AstBlock {
        return (node as AstBlock) ?? throw IllegalArgumentException("ASTKind cast failed: BLOCK")
    }

    private static func RequireNodeAsLitConstExpr(node: AstNode): AstLitConstExpr {
        return (node as AstLitConstExpr) ?? throw IllegalArgumentException("ASTKind cast failed: LIT_CONST_EXPR")
    }

    private static func RequireNodeAsRefExpr(node: AstNode): AstRefExpr {
        return (node as AstRefExpr) ?? throw IllegalArgumentException("ASTKind cast failed: REF_EXPR")
    }

    private static func RequireNodeAsReturnExpr(node: AstNode): AstReturnExpr {
        return (node as AstReturnExpr) ?? throw IllegalArgumentException("ASTKind cast failed: RETURN_EXPR")
    }

    private static func RequireNodeAsBinaryExpr(node: AstNode): AstBinaryExpr {
        return (node as AstBinaryExpr) ?? throw IllegalArgumentException("ASTKind cast failed: BINARY_EXPR")
    }

    private static func RequireNodeAsUnaryExpr(node: AstNode): AstUnaryExpr {
        return (node as AstUnaryExpr) ?? throw IllegalArgumentException("ASTKind cast failed: UNARY_EXPR")
    }

    private static func RequireNodeAsCallExpr(node: AstNode): AstCallExpr {
        return (node as AstCallExpr) ?? throw IllegalArgumentException("ASTKind cast failed: CALL_EXPR")
    }

    private static func RequireNodeAsIfExpr(node: AstNode): AstIfExpr {
        return (node as AstIfExpr) ??
            throw IllegalArgumentException("ASTKind cast failed: IF_EXPR")
    }

    private static func RequireNodeAsAssignExpr(node: AstNode): AstAssignExpr {
        return (node as AstAssignExpr) ?? throw IllegalArgumentException("ASTKind cast failed: ASSIGN_EXPR")
    }

    private static func RequireNodeAsMemberAccess(node: AstNode): AstMemberAccess {
        return (node as AstMemberAccess) ?? throw IllegalArgumentException("ASTKind cast failed: MEMBER_ACCESS")
    }

    private static func RequireNodeAsWhileExpr(node: AstNode): AstWhileExpr {
        return (node as AstWhileExpr) ?? throw IllegalArgumentException("ASTKind cast failed: WHILE_EXPR")
    }

    private static func RequireNodeAsDoWhileExpr(node: AstNode): AstDoWhileExpr {
        return (node as AstDoWhileExpr) ?? throw IllegalArgumentException("ASTKind cast failed: DO_WHILE_EXPR")
    }

    private static func RequireNodeAsForInExpr(node: AstNode): AstForInExpr {
        return (node as AstForInExpr) ?? throw IllegalArgumentException("ASTKind cast failed: FOR_IN_EXPR")
    }

    private static func RequireNodeAsJumpExpr(node: AstNode): AstJumpExpr {
        return (node as AstJumpExpr) ?? throw IllegalArgumentException("ASTKind cast failed: JUMP_EXPR")
    }

    private static func RequireNodeAsLambdaExpr(node: AstNode): AstLambdaExpr {
        return (node as AstLambdaExpr) ?? throw IllegalArgumentException("ASTKind cast failed: LAMBDA_EXPR")
    }

    private static func RequireNodeAsMatchExpr(node: AstNode): AstMatchExpr {
        return (node as AstMatchExpr) ?? throw IllegalArgumentException("ASTKind cast failed: MATCH_EXPR")
    }

    private static func RequireNodeAsTryExpr(node: AstNode): AstTryExpr {
        return (node as AstTryExpr) ?? throw IllegalArgumentException("ASTKind cast failed: TRY_EXPR")
    }

    private static func RequireNodeAsThrowExpr(node: AstNode): AstThrowExpr {
        return (node as AstThrowExpr) ?? throw IllegalArgumentException("ASTKind cast failed: THROW_EXPR")
    }

    private static func RequireNodeAsArrayLit(node: AstNode): AstArrayLit {
        return (node as AstArrayLit) ?? throw IllegalArgumentException("ASTKind cast failed: ARRAY_LIT")
    }

    private static func RequireNodeAsArrayExpr(node: AstNode): AstArrayExpr {
        return (node as AstArrayExpr) ?? throw IllegalArgumentException("ASTKind cast failed: ARRAY_EXPR")
    }

    private static func RequireNodeAsTupleLit(node: AstNode): AstTupleLit {
        return (node as AstTupleLit) ?? throw IllegalArgumentException("ASTKind cast failed: TUPLE_LIT")
    }

    private static func RequireNodeAsSubscriptExpr(node: AstNode): AstSubscriptExpr {
        return (node as AstSubscriptExpr) ?? throw IllegalArgumentException("ASTKind cast failed: SUBSCRIPT_EXPR")
    }

    private static func RequireNodeAsTypeConvExpr(node: AstNode): AstTypeConvExpr {
        return (node as AstTypeConvExpr) ?? throw IllegalArgumentException("ASTKind cast failed: TYPE_CONV_EXPR")
    }

    private static func RequireNodeAsVarWithPatternDecl(node: AstNode): AstVarWithPatternDecl {
        return (node as AstVarWithPatternDecl) ??
            throw IllegalArgumentException("ASTKind cast failed: VAR_WITH_PATTERN_DECL")
    }
}
