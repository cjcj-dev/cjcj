package cangjie_compiler::chir

import std.collection.*

import cangjie_compiler::ast.ASTKind
import cangjie_compiler::ast.ASTKindName
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.BinaryExpr as AstBinaryExpr
import cangjie_compiler::ast.Block as AstBlock
import cangjie_compiler::ast.CallExpr as AstCallExpr
import cangjie_compiler::ast.ClassDecl as AstClassDecl
import cangjie_compiler::ast.ClassLikeDecl as AstClassLikeDecl
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.FuncTy as AstFuncTy
import cangjie_compiler::ast.IfExpr as AstIfExpr
import cangjie_compiler::ast.InterfaceDecl as AstInterfaceDecl
import cangjie_compiler::ast.LitConstExpr as AstLitConstExpr
import cangjie_compiler::ast.LitConstKind as AstLitConstKind
import cangjie_compiler::ast.Node as AstNode
import cangjie_compiler::ast.RefExpr as AstRefExpr
import cangjie_compiler::ast.ReturnExpr as AstReturnExpr
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.TokenKind as AstTokenKind
import cangjie_compiler::ast.TokenKindValue as AstTokenKindValue
import cangjie_compiler::ast.Ty as AstTy
import cangjie_compiler::ast.UnaryExpr as AstUnaryExpr
import cangjie_compiler::ast.VarDecl as AstVarDecl

public class Translator {
    private let builder: CHIRBuilder
    private let chirTy: CHIRType
    private let globalSymbolTable: FaithfulAST2CHIRNodeMap
    private let localValSymbolTable: FaithfulAST2CHIRNodeMap = FaithfulAST2CHIRNodeMap()
    private var currentBlock: Option<Block> = None
    private var currentFunc: Option<Function> = None
    private let blockGroupStack: ArrayList<BlockGroup> = ArrayList<BlockGroup>()

    public init(builder: CHIRBuilder, chirTy: CHIRType, globalSymbolTable: FaithfulAST2CHIRNodeMap) {
        this.builder = builder
        this.chirTy = chirTy
        this.globalSymbolTable = globalSymbolTable
    }

    public static func TranslateASTNode(node: AstNode, trans: Translator): Option<Value> {
        let nodePtr = GetDesugaredExpr(node)
        return match (nodePtr.astKind) {
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
        var lastValue: Option<Value> = None
        for (node in block.body) {
            lastValue = Translator.TranslateASTNode(node, this)
        }
        return lastValue
    }

    public func Visit(expr: AstLitConstExpr): Option<Value> {
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let literal = TranslateLitConstant(expr)
        return RequireResult(builder.CreateConstant(resultTy, literal, CurrentBlock()))
    }

    public func Visit(expr: AstRefExpr): Option<Value> {
        if (let Some(target) <- expr.ref.target) {
            let value = GetSymbolTable(target)
            return GetDerefedValue(value)
        }
        throw IllegalStateException("faithful AST2CHIR RefExpr has no Sema target: ${expr.ref.identifier.Val()}")
    }

    public func Visit(expr: AstReturnExpr): Option<Value> {
        if (let Some(retExpr) <- expr.expr) {
            let value = Translator.TranslateASTNode(retExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR return expression produced no value")
            builder.CreateExit(value, CurrentBlock())
            return value
        }
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
            for (param in body.paramLists[0].params) {
                if (idx < fn.GetNumOfParams()) {
                    localValSymbolTable.Set(param, fn.GetParam(idx))
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

    private func EmitImplicitFunctionExit(fn: Function, value: Option<Value>): Unit {
        if (let Some(retTy) <- fn.GetReturnType()) {
            if (!retTy.IsUnit() && !retTy.IsNothing()) {
                if (let Some(retValue) <- value) {
                    builder.CreateExit(retValue, CurrentBlock())
                    return
                }
            }
        }
        builder.CreateExit(None, CurrentBlock())
    }

    private func StoreIfResult(location: Option<Value>, value: Option<Value>): Unit {
        if (let Some(loc) <- location) {
            if (let Some(result) <- value) {
                builder.CreateStore(result, loc, CurrentBlock())
            }
        }
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

    private func ResolveCalleeFromBase(expr: AstCallExpr): AstFuncDecl {
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(ref) <- (base as AstRefExpr)) {
                if (let Some(target) <- ref.ref.target) {
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

    private static func RequireNodeAsFuncDecl(node: AstNode): AstFuncDecl {
        return (node as AstFuncDecl) ?? throw IllegalArgumentException("ASTKind cast failed: FUNC_DECL")
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
}
