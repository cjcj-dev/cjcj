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
import cangjie_compiler::ast.ConstPattern as AstConstPattern
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.DoWhileExpr as AstDoWhileExpr
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.EnumPattern as AstEnumPattern
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.ForInExpr as AstForInExpr
import cangjie_compiler::ast.ForInKind as AstForInKind
import cangjie_compiler::ast.FuncArg as AstFuncArg
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.FuncTy as AstFuncTy
import cangjie_compiler::ast.IfExpr as AstIfExpr
import cangjie_compiler::ast.InterfaceDecl as AstInterfaceDecl
import cangjie_compiler::ast.JumpExpr as AstJumpExpr
import cangjie_compiler::ast.LitConstExpr as AstLitConstExpr
import cangjie_compiler::ast.LitConstKind as AstLitConstKind
import cangjie_compiler::ast.MainDecl as AstMainDecl
import cangjie_compiler::ast.MatchExpr as AstMatchExpr
import cangjie_compiler::ast.MemberAccess as AstMemberAccess
import cangjie_compiler::ast.Node as AstNode
import cangjie_compiler::ast.Pattern as AstPattern
import cangjie_compiler::ast.RefExpr as AstRefExpr
import cangjie_compiler::ast.ReturnExpr as AstReturnExpr
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.SubscriptExpr as AstSubscriptExpr
import cangjie_compiler::ast.TokenKind as AstTokenKind
import cangjie_compiler::ast.TokenKindValue as AstTokenKindValue
import cangjie_compiler::ast.Ty as AstTy
import cangjie_compiler::ast.TupleLit as AstTupleLit
import cangjie_compiler::ast.TuplePattern as AstTuplePattern
import cangjie_compiler::ast.TypePattern as AstTypePattern
import cangjie_compiler::ast.TypeConvExpr as AstTypeConvExpr
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
    private var delayExitSignal: Option<Value> = None
    private let blockGroupStack: ArrayList<BlockGroup> = ArrayList<BlockGroup>()
    private let loopTargetStack: ArrayList<FaithfulLoopTarget> = ArrayList<FaithfulLoopTarget>()

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
            case ASTKind.MATCH_EXPR => trans.Visit(RequireNodeAsMatchExpr(nodePtr))
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
        currentFunc = fn
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
        currentFunc = fn
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
            StoreReturnValueIfNeeded(CurrentFunction(), value)
            UpdateDelayExitSignalForReturnIfNeeded()
            builder.CreateExit(None, CurrentBlock())
            return None
        }
        UpdateDelayExitSignalForReturnIfNeeded()
        builder.CreateExit(None, CurrentBlock())
        return None
    }

    public func Visit(expr: AstBinaryExpr): Option<Value> {
        let lhs = Translator.TranslateASTNode(RequireExpr(expr.leftExpr, "binary lhs"), this) ??
            throw IllegalStateException("faithful AST2CHIR binary lhs produced no value")
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
        for (arg in expr.args) {
            if (let Some(argExpr) <- arg.expr) {
                let value = Translator.TranslateASTNode(argExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR call arg produced no value")
                argValues.add(value)
            }
        }
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let call = builder.CreateApply(resultTy, callee, FuncCallContext(args: argValues), CurrentBlock())
        return RequireResult(call)
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
                TranslateVArrayAssign(expr, subscriptExpr, rightExpr)
                return None
            }
        }
        if (IsCompoundAssignOp(expr.op)) {
            return TranslateCompoundAssign(expr, leftExpr, rightExpr)
        }
        return TranslateTrivialAssign(expr, leftExpr, rightExpr)
    }

    public func Visit(expr: AstMemberAccess): Option<Value> {
        let target = expr.target ??
            throw IllegalStateException("faithful AST2CHIR MemberAccess has no Sema target: ${expr.field.Val()}")
        if (target.TestAttr(AstAttribute.STATIC) || IsPackageMemberAccess(expr)) {
            return TranslateStaticTargetOrPackageMemberAccess(expr, target)
        }
        if (target.TestAttr(AstAttribute.ENUM_CONSTRUCTOR)) {
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: enum member access")
        }
        if (IsInstanceMember(target)) {
            if (let Some(_) <- (target as AstVarDecl)) {
                let leftValueInfo = TranslateMemberAccessAsLeftValue(expr)
                return LoadLeftValue(leftValueInfo, chirTy.TranslateType(RequireAstTy(expr)))
            }
            if (let Some(_) <- (target as AstFuncDecl)) {
                throw IllegalArgumentException(
                    "not yet ported in faithful AST2CHIR: member method reference lambda wrapper")
            }
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: unsupported member access")
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
        if (let Some(varDecl) <- (member as AstVarDecl)) {
            AddMemberVarDecl(def, varDecl)
        } else if (let Some(funcDecl) <- (member as AstFuncDecl)) {
            if (let Some(value) <- globalSymbolTable.TryGet(funcDecl)) {
                if (let Some(fn) <- (value as Function)) {
                    def.AddMethod(fn)
                }
            }
        }
    }

    private func AddMemberVarDecl(def: CustomTypeDef, decl: AstVarDecl): Unit {
        if (decl.TestAttr(AstAttribute.STATIC)) {
            if (let Some(value) <- globalSymbolTable.TryGet(decl)) {
                if (let Some(globalVar) <- (value as GlobalVar)) {
                    def.AddStaticMemberVar(globalVar)
                }
            }
            return
        }
        let memberTy = chirTy.TranslateType(RequireAstTy(decl))
        let memberInfo = MemberVarInfo(decl.identifier.Val(), memberTy, isStatic: false,
            isReadOnly: decl.IsConst(), rawMangledName: decl.rawMangleName)
        def.AddInstanceVar(memberInfo)
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

    private func TranslateForInRangeBody(expr: AstForInExpr, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetBody())
        currentBlock = forIn.GetBody().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in body has no entry block")
        if (let Some(pattern) <- expr.pattern) {
            if (let Some(varPattern) <- (pattern as AstVarPattern)) {
                if (let Some(varDecl) <- varPattern.varDecl) {
                    let _ = Translator.TranslateASTNode(varDecl, this)
                }
            } else if (let None <- (pattern as AstWildcardPattern)) {
                throw IllegalArgumentException(
                    "not yet ported in faithful AST2CHIR: non-var range ForInExpr pattern")
            }
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
        let noneTag = RequireResult(builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(0),
            CurrentBlock()))
        let values = ArrayList<Value>()
        values.add(noneTag)
        return RequireResult(builder.CreateTuple(optionTy, values, CurrentBlock()))
    }

    private func GetEnumTagValueFromValue(value: Value): Value {
        let path = ArrayList<UInt64>()
        path.add(0u64)
        return RequireResult(builder.CreateField(builder.context.GetUInt64Ty(), value, path, CurrentBlock()))
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
            var idx: Int64 = 0
            for (subPattern in enumPattern.patterns) {
                let payloadValue = ExtractPatternField(selector, idx + 1,
                    chirTy.TranslateType(RequireAstTy(subPattern)))
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
        let tagConst = RequireResult(builder.CreateConstant(builder.context.GetUInt64Ty(),
            IntLiteral(GetEnumPatternId(pattern)), CurrentBlock()))
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
        TranslatePatternSequence(pattern.patterns, selector, 1, trueBlock, falseBlock)
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
        if (patterns.isEmpty()) {
            builder.CreateGoTo(trueBlock, CurrentBlock())
            return
        }
        let group = RequireParentBlockGroup(CurrentBlock(), "nested pattern")
        var idx: Int64 = 0
        while (idx < patterns.size) {
            let subPattern = patterns[idx]
            let nextBlock = if (idx == patterns.size - 1) { trueBlock } else { builder.CreateBlock(group) }
            let fieldValue = ExtractPatternField(selector, idx + fieldOffset,
                chirTy.TranslateType(RequireAstTy(subPattern)))
            TranslateSinglePatternBranch(subPattern, fieldValue, nextBlock, falseBlock)
            if (idx != patterns.size - 1) {
                currentBlock = nextBlock
            }
            idx++
        }
    }

    private func ExtractPatternField(value: Value, index: Int64, fieldTy: Type): Value {
        let path = ArrayList<UInt64>()
        path.add(UInt64(index))
        return RequireResult(builder.CreateField(fieldTy, GetDerefedValue(value), path, CurrentBlock()))
    }

    private func GetEnumTagValue(pattern: AstEnumPattern, selector: Value): Value {
        let constructor = RequireEnumPatternConstructor(pattern)
        if (let Some(outerDecl) <- constructor.outerDecl) {
            if (let Some(enumDecl) <- (outerDecl as AstEnumDecl)) {
                if (!enumDecl.hasArguments) {
                    return RequireResult(builder.CreateTypeCast(builder.context.GetUInt64Ty(),
                        GetDerefedValue(selector), CurrentBlock()))
                }
            }
        }
        let path = ArrayList<UInt64>()
        path.add(0u64)
        return RequireResult(builder.CreateField(builder.context.GetUInt64Ty(), GetDerefedValue(selector), path,
            CurrentBlock()))
    }

    private func GetEnumPatternId(pattern: AstEnumPattern): Int64 {
        let constructor = RequireEnumPatternConstructor(pattern)
        let outer = constructor.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR enum pattern constructor has no outer enum")
        let enumDecl = (outer as AstEnumDecl) ??
            throw IllegalStateException("faithful AST2CHIR enum pattern constructor outer is not enum")
        var idx: Int64 = 0
        for (ctor in enumDecl.constructors) {
            if (SameTranslatorAstDecl(ctor, constructor)) {
                return idx
            }
            idx++
        }
        throw IllegalStateException("faithful AST2CHIR enum pattern constructor not found: ${constructor.identifier.Val()}")
    }

    private func RequireEnumPatternConstructor(pattern: AstEnumPattern): AstDecl {
        let constructorExpr = RequireExpr(pattern.constructor, "enum pattern constructor")
        if (let Some(refExpr) <- (constructorExpr as AstRefExpr)) {
            return refExpr.ref.target ??
                throw IllegalStateException("faithful AST2CHIR enum pattern RefExpr has no target")
        }
        if (let Some(member) <- (constructorExpr as AstMemberAccess)) {
            return member.target ??
                throw IllegalStateException("faithful AST2CHIR enum pattern MemberAccess has no target")
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: enum pattern constructor expression")
    }

    private func SameTranslatorAstDecl(left: AstDecl, right: AstDecl): Bool {
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
        builder.CreateApply(initFnTy.GetReturnType(), GetSymbolTable(initFunc),
            FuncCallContext(args: args, thisType: thisTy), CurrentBlock())
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
        let sizeValue = RequireResult(builder.CreateInvoke(sizeTy, invokeCtx, CurrentBlock()))

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
        builder.CreateApply(initFnTy.GetReturnType(), GetSymbolTable(initFunc),
            FuncCallContext(args: args, instTypeArgs: instTypeArgs), CurrentBlock())
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
        builder.CreateApply(initFnTy.GetReturnType(), GetSymbolTable(initFunc),
            FuncCallContext(args: args, instTypeArgs: instTypeArgs), CurrentBlock())
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
        let enumId = GetEnumCtorId(calleeDecl)
        let args = ArrayList<Value>()
        args.add(RequireResult(builder.CreateConstant(builder.context.GetUInt64Ty(), IntLiteral(enumId),
            CurrentBlock())))
        for (arg in expr.args) {
            if (let Some(argExpr) <- arg.expr) {
                let value = Translator.TranslateASTNode(argExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR enum ctor arg produced no value")
                args.add(value)
            }
        }
        return RequireResult(builder.CreateTuple(chirTy.TranslateType(RequireAstTy(expr)), args, CurrentBlock()))
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
        for (arg in expr.args) {
            if (let Some(argExpr) <- arg.expr) {
                let value = Translator.TranslateASTNode(argExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR member call arg produced no value")
                argValues.add(value)
            }
        }
        if (ShouldUseVirtualMemberDispatch(calleeDecl)) {
            if (calleeDecl.TestAttr(AstAttribute.STATIC)) {
                let parentTy = TranslateMemberOwnerType(calleeDecl)
                let rtti = RequireResult(builder.CreateGetRTTIStatic(builder.context.GetUnitTy(),
                    parentTy.StripAllRefs(), CurrentBlock()))
                let invokeCtx = InvokeCallContext(rtti, FuncCallContext(args: argValues, thisType: parentTy),
                    FuncSigInfo(BuildMethodFuncType(calleeDecl, parentTy), funcName: calleeDecl.identifier.Val()))
                return RequireResult(builder.CreateInvokeStatic(resultTy, invokeCtx, CurrentBlock()))
            }
            let obj = thisObj ?? throw IllegalStateException("faithful AST2CHIR virtual member call has no this object")
            let objTy = thisType ?? throw IllegalStateException("faithful AST2CHIR virtual member call this has no type")
            let invokeCtx = InvokeCallContext(obj, FuncCallContext(args: argValues, thisType: objTy),
                FuncSigInfo(BuildMethodFuncType(calleeDecl, objTy), funcName: calleeDecl.identifier.Val()))
            return RequireResult(builder.CreateInvoke(resultTy, invokeCtx, CurrentBlock()))
        }
        if (let Some(obj) <- thisObj) {
            argValues.add(obj, at: 0)
        }
        let callee = globalSymbolTable.Get(calleeDecl)
        return RequireResult(builder.CreateApply(resultTy, callee, FuncCallContext(args: argValues,
            thisType: thisType), CurrentBlock()))
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

    private func BuildMethodFuncType(funcDecl: AstFuncDecl, thisTy: Type): FuncType {
        let baseFuncTy = RequireFuncType(chirTy.TranslateType(RequireAstTy(funcDecl)))
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
        builder.CreateApply(builder.context.GetUnitTy(), callee, FuncCallContext(args: args, thisType: thisRefTy),
            CurrentBlock())
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
            if (refExpr.isThis || refExpr.isSuper) {
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
        let target = member.target ??
            throw IllegalStateException("faithful AST2CHIR MemberAccess left value has no Sema target")
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
                let baseInfo = TranslateExprAsLeftValue(baseExpr)
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
            case AstLitConstKind.BOOL => BoolLiteral(expr.constNumValue.asBoolean)
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
                if (let Some(target) <- member.target) {
                    if (let Some(fn) <- (target as AstFuncDecl)) {
                        return fn
                    }
                }
            }
        }
        throw IllegalStateException("faithful AST2CHIR CallExpr has no resolvedFunction")
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

    private static func RequireNodeAsMatchExpr(node: AstNode): AstMatchExpr {
        return (node as AstMatchExpr) ?? throw IllegalArgumentException("ASTKind cast failed: MATCH_EXPR")
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
