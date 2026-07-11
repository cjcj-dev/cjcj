package cjcj::chir

import std.collection.*

import cjcj::utils.{CJC_ASSERT, STATIC_INIT_FUNC}
import cjcj::option.{GlobalOptions, OptimizationFlag}
import cjcj::basic.Linkage as BasicLinkage
import cjcj::ast.ASTKind
import cjcj::ast.IsInstanceConstructor as AstIsInstanceConstructor
import cjcj::ast.IsValidCFuncConstructorCall
import cjcj::ast.GetVarsInitializationOrderWithPositions as AstGetVarsInitializationOrderWithPositions
import cjcj::ast.BuiltInDecl
import cjcj::ast.BuiltInType
import cjcj::ast.ASTKindName
import cjcj::ast.ArrayExpr as AstArrayExpr
import cjcj::ast.ArrayLit as AstArrayLit
import cjcj::ast.AssignExpr as AstAssignExpr
import cjcj::ast.Attribute as AstAttribute
import cjcj::ast.BinaryExpr as AstBinaryExpr
import cjcj::ast.Block as AstBlock
import cjcj::ast.CallExpr as AstCallExpr
import cjcj::ast.CallKind as AstCallKind
import cjcj::ast.ClassDecl as AstClassDecl
import cjcj::ast.ClassLikeDecl as AstClassLikeDecl
import cjcj::ast.ClassTy as AstClassTy
import cjcj::ast.ConstPattern as AstConstPattern
import cjcj::ast.Decl as AstDecl
import cjcj::ast.DoWhileExpr as AstDoWhileExpr
import cjcj::ast.EnumDecl as AstEnumDecl
import cjcj::ast.EnumPattern as AstEnumPattern
import cjcj::ast.EnumTy as AstEnumTy
import cjcj::ast.ExtendDecl as AstExtendDecl
import cjcj::ast.Expr as AstExpr
import cjcj::ast.ExceptTypePattern as AstExceptTypePattern
import cjcj::ast.ForInExpr as AstForInExpr
import cjcj::ast.ForInKind as AstForInKind
import cjcj::ast.FuncArg as AstFuncArg
import cjcj::ast.FuncBody as AstFuncBody
import cjcj::ast.FuncDecl as AstFuncDecl
import cjcj::ast.FuncTy as AstFuncTy
import cjcj::ast.GenericsTy as AstGenericsTy
import cjcj::ast.IfExpr as AstIfExpr
import cjcj::ast.InterfaceTy as AstInterfaceTy
import cjcj::ast.InterfaceDecl as AstInterfaceDecl
import cjcj::ast.InheritableDecl as AstInheritableDecl
import cjcj::ast.JumpExpr as AstJumpExpr
import cjcj::ast.LambdaExpr as AstLambdaExpr
import cjcj::ast.LetPatternDestructor as AstLetPatternDestructor
import cjcj::ast.LitConstExpr as AstLitConstExpr
import cjcj::ast.MatchCase as AstMatchCase
import cjcj::ast.MainDecl as AstMainDecl
import cjcj::ast.MatchExpr as AstMatchExpr
import cjcj::ast.MemberAccess as AstMemberAccess
import cjcj::ast.NameReferenceExpr as AstNameReferenceExpr
import cjcj::ast.Node as AstNode
import cjcj::ast.ParenExpr as AstParenExpr
import cjcj::ast.Pattern as AstPattern
import cjcj::ast.PointerExpr as AstPointerExpr
import cjcj::ast.Position as AstPosition
import cjcj::ast.PositionStatus as AstPositionStatus
import cjcj::ast.PropDecl as AstPropDecl
import cjcj::ast.RangeExpr as AstRangeExpr
import cjcj::ast.RefExpr as AstRefExpr
import cjcj::ast.ReturnExpr as AstReturnExpr
import cjcj::ast.SpawnExpr as AstSpawnExpr
import cjcj::ast.StructDecl as AstStructDecl
import cjcj::ast.StructTy as AstStructTy
import cjcj::ast.SubscriptExpr as AstSubscriptExpr
import cjcj::ast.SugarKind as AstSugarKind
import cjcj::ast.TokenKind as AstTokenKind
import cjcj::ast.TokenKindValue as AstTokenKindValue
import cjcj::ast.Ty as AstTy
import cjcj::ast.TypeKind as AstTypeKind
import cjcj::ast.TypeKindInRange as AstTypeKindInRange
import cjcj::ast.TupleLit as AstTupleLit
import cjcj::ast.TuplePattern as AstTuplePattern
import cjcj::ast.TupleTy as AstTupleTy
import cjcj::ast.TryExpr as AstTryExpr
import cjcj::ast.TypePattern as AstTypePattern
import cjcj::ast.TypeConvExpr as AstTypeConvExpr
import cjcj::ast.ThrowExpr as AstThrowExpr
import cjcj::ast.UnaryExpr as AstUnaryExpr
import cjcj::ast.VarDecl as AstVarDecl
import cjcj::ast.VarWithPatternDecl as AstVarWithPatternDecl
import cjcj::ast.VarOrEnumPattern as AstVarOrEnumPattern
import cjcj::ast.VarPattern as AstVarPattern
import cjcj::ast.WildcardPattern as AstWildcardPattern
import cjcj::ast.WhileExpr as AstWhileExpr

private class FaithfulLeftValueInfo {
    public let base: Option<Value>
    public let path: ArrayList<String> = ArrayList<String>()

    public init(base: Option<Value>, path: ArrayList<String>) {
        this.base = base
        for (item in path) {
            this.path.add(item)
        }
    }
}

private class SecondSwitchInfo {
    public let ep: AstEnumPattern
    public let caseId: Int64

    public init(ep: AstEnumPattern, caseId: Int64) {
        this.ep = ep
        this.caseId = caseId
    }
}

private class EnumMatchInfo {
    public let indexToBodies: TreeMap<UInt64, TreeMap<UInt64, ArrayList<SecondSwitchInfo>>> =
        TreeMap<UInt64, TreeMap<UInt64, ArrayList<SecondSwitchInfo>>>()
    public let firstSwitchBlocks: TreeMap<UInt64, Block> = TreeMap<UInt64, Block>()
    public let innerDefaultInfos: TreeMap<UInt64, ArrayList<SecondSwitchInfo>> =
        TreeMap<UInt64, ArrayList<SecondSwitchInfo>>()
}

// Static member func and global func should create alloc node for print `unused variable` warning.
private func ShouldCreateAlloc(decl: AstVarDecl, opts: GlobalOptions, rValueIsEmpty: Bool): Bool {
    if (decl.isConst) {
        return !rValueIsEmpty
    }
    if (rValueIsEmpty || decl.isVar || opts.enableCompileDebug || opts.enableCoverage) {
        return true
    }
    if (let Some(initializerExpr) <- decl.initializer) {
        if (let Some(refExpr) <- (initializerExpr as AstRefExpr)) {
            if (let Some(target) <- refExpr.ref.target) {
                if (target.astKind == ASTKind.FUNC_DECL &&
                    target.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.STATIC)) {
                    return true
                }
            }
        }
        if (let Some(memberAccess) <- (initializerExpr as AstMemberAccess)) {
            if (let Some(target) <- memberAccess.target) {
                if (target.astKind == ASTKind.FUNC_DECL && target.TestAttr(AstAttribute.STATIC)) {
                    return true
                }
            }
        }
    }
    return false
}

private class FaithfulLoopTarget {
    public let continueBlock: Block
    public let breakBlock: Block

    public init(continueBlock: Block, breakBlock: Block) {
        this.continueBlock = continueBlock
        this.breakBlock = breakBlock
    }
}

private enum FaithfulFinallyControlType {
    | BREAK
    | CONTINUE
    | RETURN
    | NORMAL
}

private func FaithfulFinallyControlTypeIndex(kind: FaithfulFinallyControlType): Int64 {
    return match (kind) {
        case FaithfulFinallyControlType.BREAK => 0
        case FaithfulFinallyControlType.CONTINUE => 1
        case FaithfulFinallyControlType.RETURN => 2
        case FaithfulFinallyControlType.NORMAL => 3
    }
}

private func FaithfulFinallyControlTypeFromIndex(index: Int64): FaithfulFinallyControlType {
    return match (index) {
        case 0 => FaithfulFinallyControlType.BREAK
        case 1 => FaithfulFinallyControlType.CONTINUE
        case 2 => FaithfulFinallyControlType.RETURN
        case 3 => FaithfulFinallyControlType.NORMAL
        case _ => throw IllegalArgumentException("faithful AST2CHIR invalid finally control index ${index}")
    }
}

private func FaithfulFinallyControlTypeCount(): Int64 {
    return 4
}

private class FaithfulFinallyControlEdge {
    public let prevBlock: Block
    public let nextBlock: Block
    public let controlScopeLevel: UInt32

    public init(prevBlock: Block, nextBlock: Block, controlScopeLevel: UInt32) {
        this.prevBlock = prevBlock
        this.nextBlock = nextBlock
        this.controlScopeLevel = controlScopeLevel
    }
}

private class FaithfulFinallyControlContext {
    public let tryScopeLevel: UInt32
    public let controlFlowBlocks: ArrayList<ArrayList<FaithfulFinallyControlEdge>> =
        ArrayList<ArrayList<FaithfulFinallyControlEdge>>()

    public init(tryExpr: AstTryExpr) {
        tryScopeLevel = tryExpr.scopeLevel
        var idx: Int64 = 0
        while (idx < FaithfulFinallyControlTypeCount()) {
            controlFlowBlocks.add(ArrayList<FaithfulFinallyControlEdge>())
            idx++
        }
    }

    public func Add(kind: FaithfulFinallyControlType, prevBlock: Block, nextBlock: Block,
        controlScopeLevel: UInt32): Unit {
        controlFlowBlocks[FaithfulFinallyControlTypeIndex(kind)].add(FaithfulFinallyControlEdge(prevBlock, nextBlock,
            controlScopeLevel))
    }

    public func CloneControlFlowBlocks(): ArrayList<ArrayList<FaithfulFinallyControlEdge>> {
        let out = ArrayList<ArrayList<FaithfulFinallyControlEdge>>()
        for (edges in controlFlowBlocks) {
            let copied = ArrayList<FaithfulFinallyControlEdge>()
            for (edge in edges) {
                copied.add(edge)
            }
            out.add(copied)
        }
        return out
    }

    public func ClearControlFlowBlocks(): Unit {
        for (edges in controlFlowBlocks) {
            edges.clear()
        }
    }

    public func RestoreControlFlowBlocks(saved: ArrayList<ArrayList<FaithfulFinallyControlEdge>>): Unit {
        var idx: Int64 = 0
        while (idx < controlFlowBlocks.size && idx < saved.size) {
            controlFlowBlocks[idx].clear()
            for (edge in saved[idx]) {
                controlFlowBlocks[idx].add(edge)
            }
            idx++
        }
    }
}

private class FaithfulInstCalleeInfo {
    public let instParentCustomTy: Type
    public let thisType: Type
    public let instParamTys: ArrayList<Type> = ArrayList<Type>()
    public let instRetTy: Type
    public let instantiatedTypeArgs: ArrayList<Type> = ArrayList<Type>()
    public let isVirtualFuncCall: Bool

    public init(instParentCustomTy: Type, thisType: Type, instParamTys: ArrayList<Type>, instRetTy: Type,
        instantiatedTypeArgs: ArrayList<Type>, isVirtualFuncCall: Bool) {
        this.instParentCustomTy = instParentCustomTy
        this.thisType = thisType
        for (ty in instParamTys) {
            this.instParamTys.add(ty)
        }
        this.instRetTy = instRetTy
        for (ty in instantiatedTypeArgs) {
            this.instantiatedTypeArgs.add(ty)
        }
        this.isVirtualFuncCall = isVirtualFuncCall
    }
}

private let FAITHFUL_TRANSLATOR_MANGLE_CANGJIE_PREFIX: String = "_C"
private let FAITHFUL_TRANSLATOR_MANGLE_CHIR_LAMBDA_PREFIX: String = "_CL"
private let FAITHFUL_TRANSLATOR_MANGLE_DOLLAR_PREFIX: String = "$"
private let FAITHFUL_TRANSLATOR_MANGLE_WILDCARD_PREFIX: String = "_"

private func FaithfulTranslatorStartsWith(value: String, prefix: String): Bool {
    return value.size >= prefix.size && value[0..prefix.size] == prefix
}

private func FaithfulTranslatorReplaceManglePrefixWith(mangledName: String, newPrefix: String): String {
    if (FaithfulTranslatorStartsWith(mangledName, FAITHFUL_TRANSLATOR_MANGLE_CANGJIE_PREFIX)) {
        return newPrefix + mangledName[FAITHFUL_TRANSLATOR_MANGLE_CANGJIE_PREFIX.size..]
    }
    throw IllegalArgumentException("Mangle name has no _C prefix to be replaced: " + mangledName)
}

private func FaithfulTranslatorGenerateLambdaFuncMangleName(baseFunc: Function, counter: UInt64): String {
    return FaithfulTranslatorReplaceManglePrefixWith(baseFunc.GetIdentifierWithoutPrefix(),
        FAITHFUL_TRANSLATOR_MANGLE_CHIR_LAMBDA_PREFIX) +
        FAITHFUL_TRANSLATOR_MANGLE_DOLLAR_PREFIX + counter.toString() +
        FAITHFUL_TRANSLATOR_MANGLE_WILDCARD_PREFIX
}

public class Translator {
    private let builder: CHIRBuilder
    private let chirTy: CHIRType
    private let globalSymbolTable: FaithfulAST2CHIRNodeMap
    private let localConstVars: ElementList
    private let localConstFuncs: ElementList
    private let deserializedVals: HashMap<String, Value>
    private var astNodeSymbolTable: AST2CHIRNodeMap<Value> = AST2CHIRNodeMap<Value>()
    private var localValSymbolTable: AST2CHIRNodeMap<Value> = AST2CHIRNodeMap<Value>()
    private let exprValueTable: HashMap<Int64, Value> = HashMap<Int64, Value>()
    private var currentBlock: Option<Block> = None
    private var currentFunc: Option<Function> = None
    private var currentLambda: Option<Lambda> = None
    private var currentAstFuncDecl: Option<AstFuncDecl> = None
    private var topLevelDecl: Option<AstDecl> = None
    private var lambdaCounter: UInt64 = 0u64
    private var lambdaWrapperCounter: UInt64 = 0u64
    private var delayExitSignal: Option<Value> = None
    private let blockGroupStack: ArrayList<BlockGroup> = ArrayList<BlockGroup>()
    private let loopTargetStack: ArrayList<FaithfulLoopTarget> = ArrayList<FaithfulLoopTarget>()
    private let tryCatchContext: ArrayList<Block> = ArrayList<Block>()
    private let tryBodyContext: ArrayList<AstTryExpr> = ArrayList<AstTryExpr>()
    private let finallyContext: ArrayList<FaithfulFinallyControlContext> = ArrayList<FaithfulFinallyControlContext>()
    private let forInExprReturnMap: HashMap<Value, Value> = HashMap<Value, Value>()
    private let overrideSrcFuncResolver: Option<(AstFuncDecl) -> Option<AstFuncDecl>>
    private let scopeInfo: ArrayList<Int64> = ArrayList<Int64>([0])
    private let opts: GlobalOptions
    private let mergingSpecific: Bool
    private var genericFuncMap: GenericFuncMap = GenericFuncMap()
    private let annoFactoryFuncs: ArrayList<(AstDecl, Function)>
    private let isComputingAnnos: Bool
    private let initFuncsForAnnoFactory: ArrayList<Function>

    public init(builder: CHIRBuilder, chirTy: CHIRType, globalSymbolTable: FaithfulAST2CHIRNodeMap,
        localConstVars!: ElementList = ElementList(), localConstFuncs!: ElementList = ElementList(),
        deserializedVals!: HashMap<String, Value>,
        overrideSrcFuncResolver!: Option<(AstFuncDecl) -> Option<AstFuncDecl>> = None,
        opts!: GlobalOptions = GlobalOptions(),
        annoFactoryFuncs!: ArrayList<(AstDecl, Function)> = ArrayList<(AstDecl, Function)>(),
        isComputingAnnos!: Bool = false,
        initFuncsForAnnoFactory!: ArrayList<Function> = ArrayList<Function>()) {
        this.builder = builder
        this.chirTy = chirTy
        this.globalSymbolTable = globalSymbolTable
        this.localConstVars = localConstVars
        this.localConstFuncs = localConstFuncs
        this.deserializedVals = deserializedVals
        this.overrideSrcFuncResolver = overrideSrcFuncResolver
        this.opts = opts
        this.mergingSpecific = opts.IsCompilingCJMPSpecific()
        this.annoFactoryFuncs = annoFactoryFuncs
        this.isComputingAnnos = isComputingAnnos
        this.initFuncsForAnnoFactory = initFuncsForAnnoFactory
    }

    public func SetTopLevel(decl: AstDecl): Unit {
        topLevelDecl = decl
    }

    public func SetGenericFuncMap(funcMap: GenericFuncMap): Unit {
        genericFuncMap = GenericFuncMap(funcMap)
    }

    public func GetGenericFuncMap(): GenericFuncMap {
        return genericFuncMap
    }

    public func Copy(): Translator {
        return Translator(builder, chirTy, globalSymbolTable, localConstVars: localConstVars,
            localConstFuncs: localConstFuncs, deserializedVals: deserializedVals,
            overrideSrcFuncResolver: overrideSrcFuncResolver, opts: opts, annoFactoryFuncs: annoFactoryFuncs,
            isComputingAnnos: isComputingAnnos, initFuncsForAnnoFactory: initFuncsForAnnoFactory)
    }

    public func TranslateGlobalVarInitializer(fn: Function, decl: AstVarDecl, globalVar: GlobalVar): Unit {
        let body = fn.GetBody() ??
            throw IllegalStateException("faithful AST2CHIR global initializer function has no body")
        let entry = body.GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR global initializer function has no entry block")
        let savedFunc = currentFunc
        let savedBlock = currentBlock
        let savedDelayExitSignal = delayExitSignal
        delayExitSignal = None
        currentFunc = fn
        currentBlock = entry
        blockGroupStack.add(body)
        let initExpr = RequireExpr(decl.initializer, "global variable initializer")
        let initValue = Translator.TranslateASTNode(initExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR global variable initializer produced no value")
        builder.CreateStore(CastValueIfNeeded(initValue, RequireRefBaseType(globalVar)), globalVar, CurrentBlock())
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateExit(None, CurrentBlock())
        }
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        delayExitSignal = savedDelayExitSignal
        currentFunc = savedFunc
        currentBlock = savedBlock
    }

    public func TranslateAnnoFactoryFuncBody(decl: AstDecl, funcDef: Function): Unit {
        let body = builder.CreateBlockGroup(funcDef)
        blockGroupStack.add(body)
        funcDef.InitBody(body)
        funcDef.EnableAttr(Attribute.COMPILER_ADD)
        let bodyBlock = CreateBlock()
        body.SetEntryBlock(bodyBlock)
        currentBlock = bodyBlock
        TranslateAnnotationsArrayBody(decl, funcDef)
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    @When[backend != "cjnative"]
    private func TranslateAnnotationsArrayBody(decl: AstDecl, funcDef: Function): Unit {
        let _ = decl
        let _ = funcDef
    }

    @When[backend == "cjnative"]
    private func TranslateAnnotationsArrayBody(decl: AstDecl, funcDef: Function): Unit {
        let annoInsts = funcDef.Get<AnnoFactoryInfo, ArrayList<GlobalVar>>()
        let annoArrSize = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(),
            IntLiteral(Int64(annoInsts.size)), CurrentBlock()))
        let objectTy = builder.context.GetRefTy(builder.context.GetObjectTy().getOrThrow())
        let rawArrayTy = builder.context.GetRawArrayTy(objectTy)
        let rawArray = RequireResult(builder.CreateRawArrayAllocate(builder.context.GetRefTy(rawArrayTy), objectTy,
            annoArrSize, CurrentBlock()))
        let arrayGeneric = builder.GetStructType("std.core", "Array").getOrThrow()
        let genericType = (arrayGeneric.GetGenericArgs()[0] as GenericType).getOrThrow()
        let table = HashMap<Int64, Type>()
        table[genericType.objectId] = objectTy
        let arrayType = ReplaceRawGenericArgType(arrayGeneric, table, builder)
        let arrayValue = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(arrayType), arrayType,
            CurrentBlock()))
        let arrayMethods = arrayGeneric.GetStructDef().GetMethods()
        var arrayInit: Option<Function> = None
        for (method in arrayMethods) {
            if (method.IsConstructor() && method.GetNumOfParams() == 4) {
                arrayInit = method
                break
            }
        }
        let arrayInitFunc = arrayInit.getOrThrow()
        let zero = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(0), CurrentBlock()))
        let args = ArrayList<Value>()
        args.add(arrayValue)
        args.add(rawArray)
        args.add(zero)
        args.add(annoArrSize)
        let callContext = FuncCallContext(args: args, thisType: builder.context.GetRefTy(arrayType))
        let returnType = ReplaceRawGenericArgType(arrayInitFunc.GetFuncType().getOrThrow().GetReturnType(), table,
            builder)
        builder.CreateApply(returnType, arrayInitFunc, callContext, CurrentBlock())
        var annoInstIndex: Int64 = 0
        while (annoInstIndex < annoInsts.size) {
            let globalVar = annoInsts[annoInstIndex]
            let globalVarType = (globalVar.GetType().getOrThrow() as RefType).getOrThrow().GetBaseType()
            let load = RequireResult(builder.CreateLoad(globalVarType, globalVar, CurrentBlock()))
            let typecast = RequireResult(builder.CreateTypeCast(objectTy, load, CurrentBlock()))
            let path = ArrayList<UInt64>()
            path.add(UInt64(annoInstIndex))
            builder.CreateStoreElementRef(typecast, rawArray, path, CurrentBlock())
            annoInstIndex++
        }
        funcDef.SetReturnValue(arrayValue)
        builder.CreateExit(None, CurrentBlock())

        let annotationsArray = decl.annotationsArray.getOrThrow()
        var annoChildrenId: Int64 = 0
        annoInstIndex = 0
        while (annoInstIndex < annoInsts.size) {
            while (isComputingAnnos &&
                annotationsArray.children[annoChildrenId].TestAttr(AstAttribute.NO_REFLECT_INFO)) {
                annoChildrenId++
            }
            let globalVar = annoInsts[annoInstIndex]
            let globalVarInit = globalVar.GetInitFunc().getOrThrow()
            let globalVarInitBody = globalVarInit.GetBody().getOrThrow()
            blockGroupStack.add(globalVarInitBody)
            currentBlock = globalVarInit.GetEntryBlock().getOrThrow()
            TranslateSubExprToLoc(annotationsArray.children[annoChildrenId], Some(globalVar))
            annoChildrenId++
            builder.CreateExit(None, CurrentBlock())
            blockGroupStack.remove(at: blockGroupStack.size - 1)
            annoInstIndex++
        }
        @When[debug]
        let isDebugBuild = true
        @When[!debug]
        let isDebugBuild = false
        if (isDebugBuild) {
            while (isComputingAnnos && annoChildrenId < annotationsArray.children.size &&
                annotationsArray.children[annoChildrenId].TestAttr(AstAttribute.NO_REFLECT_INFO)) {
                annoChildrenId++
            }
            CJC_ASSERT(annotationsArray.children.size == annoChildrenId)
        }

        let packageInit = builder.context.GetCurPackage().getOrThrow().GetPackageInitFunc().getOrThrow()
        let packageInitBody = packageInit.GetBody().getOrThrow()
        blockGroupStack.add(packageInitBody)
        currentBlock = packageInit.GetEntryBlock().getOrThrow().GetSuccessors()[1]
        CurrentBlock().GetTerminator().getOrThrow().RemoveSelfFromBlock()
        annoInstIndex = 0
        while (annoInstIndex < annoInsts.size) {
            builder.CreateApply(builder.context.GetUnitTy(), annoInsts[annoInstIndex].GetInitFunc().getOrThrow(),
                FuncCallContext(), CurrentBlock())
            annoInstIndex++
        }
        builder.CreateExit(None, CurrentBlock())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    public static func TranslateASTNode(node: AstNode, trans: Translator): Option<Value> {
        var base = node
        let backBlock = trans.currentBlock
        let nodePtr = GetDesugaredExpr(node)
        if (let Some(expr) <- (nodePtr as AstExpr)) {
            if (let Some(mapExpr) <- expr.mapExpr) {
                base = mapExpr
            }
        }
        if (let Some(baseExpr) <- (base as AstExpr)) {
            if (let Some(value) <- trans.TryGetExprValue(baseExpr)) {
                return value
            }
        }
        let result = match (nodePtr.astKind) {
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
            case ASTKind.PAREN_EXPR => trans.Visit(RequireNodeAsParenExpr(nodePtr))
            case ASTKind.POINTER_EXPR => trans.Visit(RequireNodeAsPointerExpr(nodePtr))
            case ASTKind.SPAWN_EXPR => trans.Visit(RequireNodeAsSpawnExpr(nodePtr))
            case _ => throw IllegalArgumentException(
                "not yet ported in faithful AST2CHIR: ${ASTKindName(nodePtr.astKind)}")
        }
        if (let Some(block) <- (nodePtr as AstBlock)) {
            if (nodePtr.objectId != node.objectId || nodePtr.TestAttr(AstAttribute.UNSAFE)) {
                let sourceBlock = backBlock ??
                    throw IllegalStateException("faithful AST2CHIR desugar block has no source block")
                trans.builder.CreateGoTo(trans.GetBlockByAST(block), sourceBlock)
            }
        }
        return result
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
        if (currentBlock.isSome() && !IsGlobalOrMemberFunc(funcDecl)) {
            return TranslateNestedFunc(funcDecl)
        }
        let value = globalSymbolTable.Get(funcDecl)
        let fn = (value as Function) ??
            throw IllegalStateException("faithful AST2CHIR function cache is not a Function: ${funcDecl.identifier.Val()}")
        if (let None <- funcDecl.funcBody) {
            return fn
        }
        if (funcDecl.TestAttr(AstAttribute.ABSTRACT)) {
            if (let Some(funcBody) <- funcDecl.funcBody) {
                if (let None <- funcBody.body) {
                    return fn
                }
            }
        }
        let body = EnsureFuncBody(fn)
        blockGroupStack.add(body)
        let savedAstFuncDecl = currentAstFuncDecl
        let savedDelayExitSignal = delayExitSignal
        delayExitSignal = None
        currentFunc = fn
        currentAstFuncDecl = funcDecl
        let savedBlock = currentBlock
        let entry = body.GetEntryBlock() ?? builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        currentBlock = entry
        BindFuncParams(funcDecl, fn)
        if (let Some(funcBody) <- funcDecl.funcBody) {
            if (let Some(astBody) <- funcBody.body) {
                TranslateConstructorDefaultFieldInitializers(funcDecl, funcBody)
                let lastBlock = CurrentBlock()
                let result = Translator.TranslateASTNode(astBody, this)
                if (lastBlock.GetTerminator().isNone()) {
                    builder.CreateGoTo(GetBlockByAST(astBody), lastBlock)
                }
                if (CurrentBlock().GetTerminator().isNone()) {
                    EmitImplicitFunctionExit(fn, result)
                }
            } else if (CurrentBlock().GetTerminator().isNone()) {
                builder.CreateExit(None, CurrentBlock())
            }
        }
        currentBlock = savedBlock
        delayExitSignal = savedDelayExitSignal
        currentFunc = None
        currentAstFuncDecl = savedAstFuncDecl
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        return fn
    }

    private func TranslateConstructorDefaultFieldInitializers(funcDecl: AstFuncDecl, funcBody: AstFuncBody): Unit {
        if (!AstIsInstanceConstructor(funcDecl)) {
            return
        }
        let owner = match (funcDecl.outerDecl) {
            case Some(value) => value
            case None => return
        }
        let thisVar = CurrentFunction().GetParam(0)
        SetSymbolTable(owner, thisVar)
        if (HasDelegatedThisCall(funcBody)) {
            return
        }
        if (owner.TestAnyAttr(AstAttribute.COMMON, AstAttribute.SPECIFIC)) {
            let typeDef = chirTy.GetGlobalNominalCache(owner)
            let varInitFunc = typeDef.GetVarInitializationFunc().getOrThrow()
            let args = ArrayList<Value>()
            args.add(thisVar)
            builder.CreateApply(varInitFunc.GetReturnType().getOrThrow(), varInitFunc,
                FuncCallContext(args: args, thisType: thisVar.GetType()), CurrentBlock())
            return
        }
        if (owner.astKind != ASTKind.CLASS_DECL && owner.astKind != ASTKind.STRUCT_DECL) {
            return
        }
        var fieldOffset = GetSuperInstanceVarSize(thisVar.GetType().getOrThrow())
        for (member in owner.GetMemberDeclPtrs()) {
            if (member.astKind != ASTKind.VAR_DECL || member.TestAttr(AstAttribute.STATIC)) {
                continue
            }
            let varDecl = Translator.RequireNodeAsVarDecl(member)
            if (let Some(initializer) <- varDecl.initializer) {
                let initValue = TranslateExprArg(initializer)
                let loc = TranslateLocation(member)
                let path = ArrayList<UInt64>()
                path.add(fieldOffset)
                let pureCurObjType = (thisVar.GetType().getOrThrow() as RefType).getOrThrow().GetBaseType()
                CJC_ASSERT(!pureCurObjType.IsRef() && pureCurObjType.IsNominal())
                let memberTy = (pureCurObjType as CustomType).getOrThrow()
                    .GetInstMemberTypeByPath(path, builder)
                let storedValue = if (refEq(initValue.GetType().getOrThrow(), memberTy)) {
                    initValue
                } else {
                    TypeCastOrBoxIfNeeded(initValue, memberTy, loc)
                }
                let store = builder.CreateStoreElementRef(storedValue, thisVar, path, CurrentBlock())
                store.SetDebugLocation(loc)
            }
            fieldOffset++
        }
    }

    private func HasDelegatedThisCall(funcBody: AstFuncBody): Bool {
        let body = funcBody.body ?? return false
        if (body.body.isEmpty()) {
            return false
        }
        let first = body.body[0]
        if (let Some(callExpr) <- (first as AstCallExpr)) {
            if (callExpr.callKind == AstCallKind.CALL_FUNCTION_PTR) {
                return false
            }
            if (let Some(resolved) <- callExpr.resolvedFunction) {
                if (resolved.TestAttr(AstAttribute.CONSTRUCTOR)) {
                    if (let Some(base) <- callExpr.baseFunc) {
                        if (let Some(refExpr) <- (base as AstRefExpr)) {
                            return refExpr.isThis
                        }
                    }
                }
            }
        }
        return false
    }

    private func GetSuperInstanceVarSize(thisType: Type): UInt64 {
        CJC_ASSERT(thisType.IsRef())
        let realType = (thisType as RefType).getOrThrow().GetBaseType()
        if (!realType.IsClass()) {
            return 0u64
        }
        if (let Some(superClassDef) <- (realType as ClassType).getOrThrow().GetClassDef().GetSuperClassDef()) {
            return UInt64(superClassDef.GetAllInstanceVarNum())
        }
        return 0u64
    }

    public func CreateClassStructDeclVarInit(decl: AstDecl): Unit {
        CJC_ASSERT(decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.STRUCT_DECL)
        let def = chirTy.GetGlobalNominalCache(decl)
        def.SetVarInitializationFunc(TranslateVarsInit(decl))
    }

    private func ClearOrCreateVarInitFunc(decl: AstDecl): Option<Function> {
        let postfix = "$varInit"
        let outerDecl = decl.outerDecl ?? decl
        if (outerDecl.TestAttr(AstAttribute.IMPORTED) ||
            !outerDecl.TestAnyAttr(AstAttribute.COMMON, AstAttribute.SPECIFIC)) {
            return None
        }

        let mangledName = decl.mangledName + postfix
        let (funcDef, body) = if (let Some(cachedFunc) <-
            TryGetFromCache<Function>(GLOBAL_VALUE_PREFIX + mangledName, deserializedVals)) {
            let newBody = builder.CreateBlockGroup(cachedFunc)
            cachedFunc.ReplaceBody(newBody)
            cachedFunc.SetDebugLocation(DebugLocation())
            (cachedFunc, newBody)
        } else {
            let identifier = decl.identifier.Val() + postfix
            let rawMangledName = decl.rawMangleName + postfix
            let packageName = outerDecl.fullPackageName
            let params = ArrayList<Type>()
            var returnTy = RequireAstTy(decl)
            if (let Some(varDecl) <- (decl as AstVarDecl)) {
                if (let Some(initializer) <- varDecl.initializer) {
                    returnTy = RequireAstTy(initializer)
                }
            }
            let returnType = if (refEq(decl, outerDecl)) {
                builder.context.GetUnitTy()
            } else {
                TranslateType(returnTy)
            }
            var funcType = builder.context.GetFuncTy(params, returnType)
            funcType = AdjustVarInitType(funcType, outerDecl, builder, chirTy)
            let loc = TranslateLocationWithoutScope(builder.context, decl.begin, decl.end)
            let customTypeDef = chirTy.GetGlobalNominalCache(outerDecl)
            let newFunc = builder.CreateFunction(funcType, mangledName, srcCodeIdentifier: identifier,
                rawMangledName: rawMangledName, packageName: packageName)
            newFunc.SetDebugLocation(loc)
            customTypeDef.AddMethod(newFunc)
            newFunc.SetFuncKind(FuncKind.INSTANCEVAR_INIT)
            newFunc.EnableAttr(Attribute.PRIVATE)
            newFunc.EnableAttr(Attribute.COMPILER_ADD)
            newFunc.EnableAttr(Attribute.MUT)
            let thisParam = builder.CreateParameter(funcType.GetParamTypes()[0], loc, newFunc)
            thisParam.SetSrcCodeIdentifier("this")
            let newBody = builder.CreateBlockGroup(newFunc)
            newFunc.InitBody(newBody)
            (newFunc, newBody)
        }
        blockGroupStack.add(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let retVal = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(builder.context.GetUnitTy()),
            builder.context.GetUnitTy(), entry))
        funcDef.SetReturnValue(retVal)
        let thisVar = funcDef.GetParam(0)
        builder.CreateDebug(builder.context.GetUnitTy(), thisVar, "this", entry)
        currentFunc = funcDef
        return Some(funcDef)
    }

    private func TranslateVarInit(varDecl: AstVarDecl): Option<Function> {
        let initializer = varDecl.initializer ?? return None
        let funcDef = ClearOrCreateVarInitFunc(varDecl) ?? return None
        let loc = TranslateLocationWithoutScope(builder.context, varDecl.begin, varDecl.end)
        let entry = funcDef.GetEntryBlock().getOrThrow()
        let thisVar = funcDef.GetParam(0)
        SetSymbolTable(varDecl.outerDecl.getOrThrow(), thisVar)
        let initBlock = CreateBlock()
        currentBlock = initBlock
        let value = TranslateExprArg(initializer)
        let lastBlock = CurrentBlock()
        let returnType = funcDef.GetReturnType().getOrThrow()
        let allocate = builder.CreateAllocate(builder.context.GetRefTy(returnType), returnType, lastBlock)
        allocate.SetDebugLocation(loc)
        let retVal = RequireResult(allocate)
        funcDef.SetReturnValue(retVal)
        let store = builder.CreateStore(value, retVal, lastBlock)
        store.SetDebugLocation(loc)
        builder.CreateExit(None, lastBlock)
        builder.CreateGoTo(initBlock, entry)
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        return Some(funcDef)
    }

    private func TranslateVarsInit(decl: AstDecl): Option<Function> {
        let funcDef = ClearOrCreateVarInitFunc(decl) ?? return None
        let thisVar = funcDef.GetParam(0)
        SetSymbolTable(decl, thisVar)
        let initBlock = CreateBlock()
        currentBlock = initBlock
        TranslateVariablesInit(decl, thisVar)
        let lastBlock = CurrentBlock()
        builder.CreateExit(None, lastBlock)
        builder.CreateGoTo(initBlock, funcDef.GetEntryBlock().getOrThrow())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        return Some(funcDef)
    }

    private func TranslateVariablesInit(parent: AstDecl, thisVar: Parameter): Unit {
        let offset = GetSuperInstanceVarSize(thisVar.GetType().getOrThrow())
        let typeDef = chirTy.GetGlobalNominalCache(parent)
        let varInfoByName = HashMap<String, MemberVarInfo>()
        let memberVars = typeDef.GetDirectInstanceVars()
        for (varInfo in memberVars) {
            varInfoByName[varInfo.name] = varInfo
        }
        let initOrder = AstGetVarsInitializationOrderWithPositions(parent)
        for (item in initOrder) {
            let member = item.decl.getOrThrow()
            CJC_ASSERT(!member.isMemberParam || member.initializer.isNone())
            let varInfo = varInfoByName.get(member.identifier.Val()).getOrThrow()
            if (ShouldTranslateMember(parent, member)) {
                let trans = Copy()
                varInfo.initializerFunc = trans.TranslateVarInit(member)
            }
            if (let Some(varInitFunc) <- varInfo.initializerFunc) {
                let args = ArrayList<Value>()
                args.add(thisVar)
                let loc = TranslateLocation(member)
                let apply = builder.CreateApply(varInitFunc.GetReturnType().getOrThrow(), varInitFunc,
                    FuncCallContext(args: args, thisType: thisVar.GetType()), CurrentBlock())
                apply.SetDebugLocation(loc)
                let value = RequireResult(apply)
                let path = ArrayList<UInt64>()
                path.add(offset + item.fieldPosition)
                let pureCurObjType = (thisVar.GetType().getOrThrow() as RefType).getOrThrow().GetBaseType()
                CJC_ASSERT(!pureCurObjType.IsRef() && pureCurObjType.IsNominal())
                let memberType = (pureCurObjType as CustomType).getOrThrow()
                    .GetInstMemberTypeByPath(path, builder)
                if (refEq(value.GetType().getOrThrow(), memberType)) {
                    let store = builder.CreateStoreElementRef(value, thisVar, path, CurrentBlock())
                    store.SetDebugLocation(loc)
                } else {
                    let castedValue = TypeCastOrBoxIfNeeded(value, memberType, loc)
                    let store = builder.CreateStoreElementRef(castedValue, thisVar, path, CurrentBlock())
                    store.SetDebugLocation(loc)
                }
            }
        }
        typeDef.SetDirectInstanceVars(memberVars)
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
        let savedDelayExitSignal = delayExitSignal
        delayExitSignal = None
        currentFunc = fn
        currentAstFuncDecl = None
        let savedBlock = currentBlock
        let entry = body.GetEntryBlock() ?? builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        currentBlock = entry
        if (let Some(astBody) <- funcBody.body) {
            let result = Translator.TranslateASTNode(astBody, this)
            if (entry.GetTerminator().isNone()) {
                builder.CreateGoTo(GetBlockByAST(astBody), entry)
            }
            if (CurrentBlock().GetTerminator().isNone()) {
                EmitImplicitFunctionExit(fn, result)
            }
        } else if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateExit(None, CurrentBlock())
        }
        currentBlock = savedBlock
        delayExitSignal = savedDelayExitSignal
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
        def.SetLinkTypeInfo(if (structDecl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) {
            BasicLinkage.INTERNAL
        } else {
            structDecl.linkage
        })
        SetImplementedInterfaces(def, structDecl)
        for (member in structDecl.GetMemberDeclPtrs()) {
            if (!ShouldTranslateMember(structDecl, member)) {
                continue
            }
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
        def.SetNonExhaustive(enumDecl.hasEllipsis)
        if (let Some(astTy) <- enumDecl.GetTy()) {
            def.SetType(RequireEnumType(chirTy.TranslateType(astTy)))
        }
        var enumTiLinkage = if (enumDecl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) {
            BasicLinkage.INTERNAL
        } else {
            enumDecl.linkage
        }
        if (enumTiLinkage == BasicLinkage.INTERNAL) {
            enumTiLinkage = BasicLinkage.LINKONCE_ODR
        }
        def.SetLinkTypeInfo(enumTiLinkage)
        SetImplementedInterfaces(def, enumDecl)
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
            var ctorFuncType: Option<FuncType> = None
            if (let Some(customTy) <- def.GetType()) {
                if (let Some(enumTy) <- (customTy as EnumType)) {
                    ctorFuncType = Some(builder.context.GetFuncTy(payloadTypes, enumTy))
                }
            }
            def.AddCtor(EnumCtorInfo(ctor.identifier.Val(), payloadTypes,
                mangledName: ctor.mangledName, funcType: ctorFuncType))
        }
        for (member in enumDecl.members) {
            if (!ShouldTranslateMember(enumDecl, member)) {
                continue
            }
            TranslateMemberDecl(def, member)
        }
        return None
    }

    public func Visit(extendDecl: AstExtendDecl): Option<Value> {
        let def = RequireExtendDef(chirTy.GetGlobalNominalCache(extendDecl))
        let extendedType = extendDecl.extendedType ??
            throw IllegalStateException("faithful AST2CHIR ExtendDecl has no extendedType")
        let translated = chirTy.TranslateType(RequireAstTy(extendedType))
        let extendedTy = if (let Some(refTy) <- (translated as RefType)) {
            refTy.GetBaseType()
        } else {
            translated
        }
        def.SetExtendedType(extendedTy)
        for (member in extendDecl.members) {
            if (member.IsCommonMatchedWithSpecific()) {
                continue
            }
            TranslateMemberDecl(def, member)
        }
        SetImplementedInterfaces(def, extendDecl)
        if (extendDecl.TestAttr(AstAttribute.GENERIC)) {
            let genericDecl = extendDecl.GetGeneric().getOrThrow()
            for (genericTy in genericDecl.typeParameters) {
                if (let Some(paramTy) <- genericTy.GetTy()) {
                    chirTy.FillGenericArgType((paramTy as AstGenericsTy).getOrThrow())
                }
            }
        }
        return None
    }

    public func Visit(varDecl: AstVarDecl): Option<Value> {
        if (currentBlock.isNone()) {
            return globalSymbolTable.TryGet(varDecl)
        }
        if (localConstVars.HasElement(varDecl)) {
            return None
        }
        let initializer = varDecl.initializer
        var leftValue = TranslateLeftValueOfVarDecl(varDecl, initializer.isNone(), true)
        if (let Some(initializerExpr) <- initializer) {
            let oldCompileTimeValueMark = builder.GetCompileTimeValueMark()
            builder.SetCompileTimeValueMark(varDecl.isConst)
            let initNode = TranslateExprArg(initializerExpr)
            builder.SetCompileTimeValueMark(oldCompileTimeValueMark)
            leftValue = Some(StoreRValueToLValue(varDecl, initNode, leftValue))
        }
        let finalLeftValue = leftValue ??
            throw IllegalStateException("faithful AST2CHIR VarDecl has no left value: ${varDecl.identifier.Val()}")
        SetSymbolTable(varDecl, finalLeftValue)
        return Some(finalLeftValue)
    }

    private func TranslateLeftValueOfVarDecl(decl: AstVarDecl, rValueIsEmpty: Bool, isLocalVar: Bool): Option<Value> {
        var leftValue: Option<Value> = None
        let varPos = TranslateLocation(decl)
        let leftType = chirTy.TranslateType(RequireAstTy(decl))
        if (isLocalVar) {
            if (ShouldCreateAlloc(decl, opts, rValueIsEmpty)) {
                let allocate = builder.CreateAllocate(builder.context.GetRefTy(leftType), leftType, CurrentBlock())
                allocate.SetDebugLocation(varPos)
                let allocatedValue = RequireResult(allocate)
                leftValue = Some(allocatedValue)
                if (!decl.TestAttr(AstAttribute.IMPLICIT_ADD)) {
                    allocatedValue.SetSrcCodeIdentifier(decl.identifier.Val())
                    let debugInfo = builder.CreateDebug(builder.context.GetUnitTy(), allocatedValue,
                        decl.identifier.Val(), CurrentBlock())
                    debugInfo.SetDebugLocation(varPos)
                    debugInfo.SetDebugLocationInfoForWarning(GetDeclLoc(builder.context, decl))
                }
                allocatedValue.AppendAttributeInfo(BuildVarDeclAttr(decl))
            }
        } else {
            let symbol = GetSymbolTable(decl)
            symbol.AppendAttributeInfo(BuildVarDeclAttr(decl))
            leftValue = Some(symbol)
        }
        return leftValue
    }

    private func StoreRValueToLValue(decl: AstVarDecl, rVal: Value, lVal: Option<Value>): Value {
        let leftType = chirTy.TranslateType(RequireAstTy(decl))
        let varPos = TranslateLocation(decl)
        if (let Some(leftValue) <- lVal) {
            CreateAndAppendWrappedStore(rVal, leftValue, varPos)
            return leftValue
        }
        let warnPos = GetDeclLoc(builder.context, decl)
        let castedValue = TypeCastOrBoxIfNeeded(rVal, leftType, varPos)
        if (!decl.TestAttr(AstAttribute.IMPLICIT_ADD) && !decl.isConst) {
            let debugInfo = builder.CreateDebug(builder.context.GetUnitTy(), castedValue,
                decl.identifier.Val(), CurrentBlock())
            debugInfo.SetDebugLocation(varPos)
            debugInfo.SetDebugLocationInfoForWarning(warnPos)
            let debugResult = RequireResult(debugInfo)
            debugResult.SetDebugLocation(warnPos)
            debugResult.EnableAttr(Attribute.READONLY)
        }
        return castedValue
    }

    private func IsUnnecessarySuperCall(node: AstNode): Bool {
        if (let Some(callExpr) <- (node as AstCallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(refExpr) <- (baseFunc as AstRefExpr)) {
                    if (refExpr.isSuper) {
                        if (let Some(astTy) <- callExpr.GetTy()) {
                            return astTy.IsObject()
                        }
                    }
                }
            }
        }
        return false
    }

    private func CollectBlockBodyNodes(block: AstBlock): ArrayList<AstNode> {
        let nodes = ArrayList<AstNode>()
        for (body in block.body) {
            if (IsUnnecessarySuperCall(body)) {
                continue
            }
            nodes.add(body)
        }
        return nodes
    }

    public func Visit(block: AstBlock): Option<Value> {
        let chirBlock = CreateBlock()
        SetSymbolTable(block, chirBlock)
        currentBlock = chirBlock
        let nodes = CollectBlockBodyNodes(block)
        if (nodes.isEmpty()) {
            return None
        }
        var idx: Int64 = 0
        while (idx + 1 < nodes.size) {
            TranslateBlockNodeToDiscarded(nodes[idx])
            idx++
        }
        return TranslateBlockNodeAsValue(nodes[idx])
    }

    public func Visit(expr: AstLitConstExpr): Option<Value> {
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        if (resultTy.IsUnit()) {
            return None
        }
        let literal = TranslateLitConstant(expr)
        return RequireResult(builder.CreateConstant(resultTy, literal, CurrentBlock()))
    }

    public func Visit(expr: AstRefExpr): Option<Value> {
        if (let Some(value) <- TryGetExprValue(expr)) {
            return value
        }
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
        let loc = TranslateLocation(expr)
        if (let Some(retExpr) <- expr.expr) {
            let value = TranslateExprArg(retExpr)
            StoreReturnExprValueIfNeeded(expr, value)
            UpdateDelayExitSignalForReturnIfNeeded()
            RecordFinallyControlIfNeeded(FaithfulFinallyControlType.RETURN)
            builder.CreateExit(None, CurrentBlock()).SetDebugLocation(loc)
            let group = RequireParentBlockGroup(CurrentBlock(), "return continuation")
            currentBlock = builder.CreateBlock(group)
            return None
        }
        UpdateDelayExitSignalForReturnIfNeeded()
        RecordFinallyControlIfNeeded(FaithfulFinallyControlType.RETURN)
        builder.CreateExit(None, CurrentBlock()).SetDebugLocation(loc)
        let group = RequireParentBlockGroup(CurrentBlock(), "return continuation")
        currentBlock = builder.CreateBlock(group)
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
        let binary = builder.CreateBinaryExpression(ToCHIRBinaryOp(expr.op), resultTy, lhs, rhs, CurrentBlock(),
            overflowStrategy: expr.overflowStrategy)
        return RequireResult(binary)
    }

    public func Visit(expr: AstUnaryExpr): Option<Value> {
        let operand = Translator.TranslateASTNode(RequireExpr(expr.expr, "unary operand"), this) ??
            throw IllegalStateException("faithful AST2CHIR unary operand produced no value")
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let kind = if (expr.op == AstTokenKind.NOT) {
            if (RequireAstTy(expr).IsBoolean()) { ExprKind.NOT } else { ExprKind.BITNOT }
        } else {
            ToCHIRUnaryOp(expr.op)
        }
        let unary = builder.CreateUnaryExpression(kind, resultTy, operand, CurrentBlock(),
            overflowStrategy: expr.overflowStrategy)
        return RequireResult(unary)
    }

    public func Visit(expr: AstParenExpr): Option<Value> {
        return Translator.TranslateASTNode(RequireExpr(expr.expr, "parenthesized expression"), this)
    }

    public func Visit(expr: AstPointerExpr): Option<Value> {
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        var intrinsicKind = IntrinsicKind.CPOINTER_INIT0
        let args = ArrayList<Value>()
        if (let Some(arg) <- expr.arg) {
            intrinsicKind = IntrinsicKind.CPOINTER_INIT1
            var argValue: Value
            if (arg.withInout) {
                let argExpr = RequireFuncArgExpr(arg, "pointer argument")
                argValue = GeneratePointerInoutArg(TranslateExprAsLeftValue(argExpr),
                    chirTy.TranslateType(RequireAstTy(argExpr)))
                let inoutArgs = ArrayList<Value>()
                inoutArgs.add(argValue)
                argValue = RequireResult(builder.CreateIntrinsic(chirTy.TranslateType(RequireAstTy(arg)),
                    IntrisicCallContext(kind: IntrinsicKind.INOUT_PARAM, args: inoutArgs), CurrentBlock()))
            } else {
                argValue = TranslateExprArg(RequireFuncArgExpr(arg, "pointer argument"))
            }
            args.add(GenerateLoadIfNecessaryForArg(argValue, arg.withInout))
        }
        return RequireResult(builder.CreateIntrinsic(resultTy, IntrisicCallContext(kind: intrinsicKind, args: args),
            CurrentBlock()))
    }

    public func Visit(expr: AstSpawnExpr): Option<Value> {
        let futureDecl = expr.futureObj ??
            throw IllegalStateException("faithful AST2CHIR SpawnExpr has no desugared future object")
        let futureInit = RequireExpr(futureDecl.initializer, "spawn future initializer")
        let futureObj = Translator.TranslateASTNode(futureInit, this) ??
            throw IllegalStateException("faithful AST2CHIR spawn future initializer produced no value")
        var spawnArg: Option<Value> = None
        if (let Some(arg) <- expr.arg) {
            if (let Some(desugar) <- arg.desugarExpr) {
                spawnArg = Translator.TranslateASTNode(desugar, this)
            }
        }
        CreateSpawnMaybeWithException(chirTy.TranslateType(RequireAstTy(expr)), futureObj, spawnArg)
        return futureObj
    }

    public func Visit(expr: AstCallExpr): Option<Value> {
        if (let Some(intrinsicResult) <- TranslateIntrinsicCall(expr)) {
            return Some(intrinsicResult)
        }
        if (let Some(cfuncCtor) <- TranslateCFuncConstructorCall(expr)) {
            return Some(cfuncCtor)
        }
        if (let Some(cstrCtor) <- TranslateCStringCtorCall(expr)) {
            return Some(cstrCtor)
        }
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
        let callee = GetSymbolTable(calleeDecl)
        let argValues = ArrayList<Value>()
        let expectedParamTys = FuncParamTypes(expr, calleeDecl)
        AppendTranslatedCallArgs(expr, calleeDecl, argValues, expectedParamTys, ArrayList<Value>())
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let instTypeArgs = TranslateFuncInstArgs(expr, calleeDecl)
        return CreateApplyMaybeWithException(resultTy, callee, FuncCallContext(args: argValues,
            instTypeArgs: instTypeArgs), loc: TranslateLocation(expr))
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
        let savedDelayExitSignal = delayExitSignal
        let savedTryCatchContext = tryCatchContext.clone()
        let savedTryBodyContext = tryBodyContext.clone()
        let savedFinallyContext = finallyContext.clone()
        delayExitSignal = None
        tryCatchContext.clear()
        tryBodyContext.clear()
        finallyContext.clear()
        blockGroupStack.add(body)
        currentLambda = lambda
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        currentBlock = entry
        CreateLambdaParamDebugs(funcBody, lambda, entry)
        let retSlot = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(funcTy.GetReturnType()),
            funcTy.GetReturnType(), entry))
        lambda.SetReturnValue(retSlot)
        if (let Some(astBody) <- funcBody.body) {
            let result = Translator.TranslateASTNode(astBody, this)
            if (entry.GetTerminator().isNone()) {
                builder.CreateGoTo(GetBlockByAST(astBody), entry)
            }
            if (CurrentBlock().GetTerminator().isNone()) {
                EmitImplicitLambdaExit(lambda, result)
            }
        } else if (CurrentBlock().GetTerminator().isNone()) {
            EmitImplicitLambdaExit(lambda, None)
        }
        currentBlock = savedBlock
        currentLambda = savedLambda
        delayExitSignal = savedDelayExitSignal
        tryCatchContext.clear()
        for (block in savedTryCatchContext) {
            tryCatchContext.add(block)
        }
        tryBodyContext.clear()
        for (tryExpr in savedTryBodyContext) {
            tryBodyContext.add(tryExpr)
        }
        finallyContext.clear()
        for (context in savedFinallyContext) {
            finallyContext.add(context)
        }
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        if (let Some(result) <- lambda.GetResult()) {
            return Some(result)
        }
        return None
    }

    private func IfConditionHasLetPattern(expr: AstExpr): Bool {
        if (let Some(_) <- (expr as AstLetPatternDestructor)) {
            return true
        }
        if (let Some(parenExpr) <- (expr as AstParenExpr)) {
            if (let Some(inner) <- parenExpr.expr) {
                return IfConditionHasLetPattern(inner)
            }
            return false
        }
        if (let Some(binaryExpr) <- (expr as AstBinaryExpr)) {
            if (binaryExpr.op == AstTokenKind.AND || binaryExpr.op == AstTokenKind.OR) {
                if (let Some(left) <- binaryExpr.leftExpr) {
                    if (IfConditionHasLetPattern(left)) {
                        return true
                    }
                }
                if (let Some(right) <- binaryExpr.rightExpr) {
                    return IfConditionHasLetPattern(right)
                }
            }
        }
        return false
    }

    private func TranslateIfCondition(expr: AstExpr, trueBlock: Block, falseBlock: Block): Unit {
        if (let Some(parenExpr) <- (expr as AstParenExpr)) {
            TranslateIfCondition(RequireExpr(parenExpr.expr, "parenthesized if condition"), trueBlock, falseBlock)
            return
        }
        if (let Some(letPattern) <- (expr as AstLetPatternDestructor)) {
            TranslateLetPatternCondition(letPattern, trueBlock, falseBlock)
            return
        }
        if (let Some(binaryExpr) <- (expr as AstBinaryExpr)) {
            if ((binaryExpr.op == AstTokenKind.AND || binaryExpr.op == AstTokenKind.OR) &&
                IfConditionHasLetPattern(binaryExpr)) {
                let group = RequireParentBlockGroup(CurrentBlock(), "if condition")
                let rightEntry = builder.CreateBlock(group)
                if (binaryExpr.op == AstTokenKind.AND) {
                    TranslateIfCondition(RequireExpr(binaryExpr.leftExpr, "if && lhs"), rightEntry, falseBlock)
                    currentBlock = rightEntry
                    TranslateIfCondition(RequireExpr(binaryExpr.rightExpr, "if && rhs"), trueBlock, falseBlock)
                } else {
                    TranslateIfCondition(RequireExpr(binaryExpr.leftExpr, "if || lhs"), trueBlock, rightEntry)
                    currentBlock = rightEntry
                    TranslateIfCondition(RequireExpr(binaryExpr.rightExpr, "if || rhs"), trueBlock, falseBlock)
                }
                return
            }
        }
        let cond = Translator.TranslateASTNode(expr, this) ??
            throw IllegalStateException("faithful AST2CHIR if condition produced no value")
        builder.CreateBranch(cond, trueBlock, falseBlock, CurrentBlock())
    }

    private func TranslateLetPatternCondition(letPattern: AstLetPatternDestructor, trueBlock: Block,
        falseBlock: Block): Unit {
        if (CanOptimizeLetPatternToSwitch(letPattern)) {
            TranslateLetPatternConditionAsTable(letPattern, trueBlock, falseBlock)
            return
        }
        TranslateLetPatternConditionAsMatch(letPattern, trueBlock, falseBlock)
    }

    private func TranslateLetPatternConditionAsMatch(letPattern: AstLetPatternDestructor, trueBlock: Block,
        falseBlock: Block): Unit {
        let selector = Translator.TranslateASTNode(RequireExpr(letPattern.initializer, "if-let initializer"), this) ??
            throw IllegalStateException("faithful AST2CHIR if-let initializer produced no value")
        let originLoc = TranslateLocation(letPattern)
        scopeInfo.add(-1)
        scopeInfo[scopeInfo.size - 1] = scopeInfo[scopeInfo.size - 1] + 1
        let (patternFalseBlock, patternTrueBlock) = if (letPattern.patterns.size == 1) {
            TranslateNestingCasePattern(letPattern.patterns[0], selector, originLoc, sourceExpr: SourceExpr.IF_EXPR)
        } else {
            TranslateOrPattern(letPattern.patterns, selector, originLoc)
        }
        scopeInfo.remove(at: scopeInfo.size - 1)
        builder.CreateGoTo(trueBlock, patternTrueBlock)
        builder.CreateGoTo(falseBlock, patternFalseBlock)
    }

    private func TranslateLetPatternConditionAsTable(letPattern: AstLetPatternDestructor, trueBlock: Block,
        falseBlock: Block): Unit {
        let selectorTy = RequireAstTy(RequireExpr(letPattern.initializer, "if-let initializer"))
        let selectorVal = Translator.TranslateASTNode(RequireExpr(letPattern.initializer, "if-let initializer"), this) ??
            throw IllegalStateException("faithful AST2CHIR if-let initializer produced no value")
        var enumDecl: Option<AstEnumDecl> = None
        if (let Some(decl) <- AstTy.GetDeclOfTy(Some(selectorTy))) {
            enumDecl = decl as AstEnumDecl
        }
        let (patternTrueBlock, patternFalseBlock) = if (let None <- enumDecl) {
            TranslateTrivialLetPatternAsTable(letPattern, selectorVal, 0)
        } else if (!enumDecl.getOrThrow().hasArguments || DoesNotHaveEnumSubpattern(letPattern)) {
            TranslateTrivialLetPatternAsTable(letPattern, GetEnumIDValue(selectorTy, selectorVal),
                enumDecl.getOrThrow().constructors.size)
        } else {
            TranslateEnumLetPatternMatchAsTable(letPattern, selectorVal)
        }
        builder.CreateGoTo(trueBlock, patternTrueBlock)
        if (let Some(block) <- patternFalseBlock) {
            builder.CreateGoTo(falseBlock, block)
        }
    }

    private func TranslateEnumLetPatternMatchAsTable(letPattern: AstLetPatternDestructor,
        enumVal: Value): (Block, Option<Block>) {
        var isStillReachable = true
        let baseBlock = CurrentBlock()
        let trueBlock = CreateBlock()
        let falseBlock = CreateBlock()
        var firstDefaultBlock = falseBlock
        let firstSelectorVal = GetEnumIDValue(RequireAstTy(RequireExpr(letPattern.initializer, "if-let initializer")),
            enumVal)
        let matchInfo = EnumMatchInfo()
        scopeInfo.add(-1)
        scopeInfo[scopeInfo.size - 1] = scopeInfo[scopeInfo.size - 1] + 1
        if (letPattern.patterns[0].astKind == ASTKind.WILDCARD_PATTERN) {
            isStillReachable = false
            firstDefaultBlock = trueBlock
            firstDefaultBlock.SetDebugLocation(TranslateLocation(letPattern.patterns[0]))
        }
        for (pattern in letPattern.patterns) {
            CollectEnumPatternInfo(pattern, matchInfo, 0)
        }
        scopeInfo.remove(at: scopeInfo.size - 1)
        let indexes = ArrayList<UInt64>()
        let blocks = ArrayList<Block>()
        for (key in matchInfo.firstSwitchBlocks.keys()) {
            indexes.add(key)
            blocks.add(matchInfo.firstSwitchBlocks.get(key).getOrThrow())
        }
        currentBlock = baseBlock
        builder.CreateMultiBranch(firstSelectorVal, firstDefaultBlock, indexes, blocks, baseBlock)
        let branchInfos = TranslateSecondLevelAsTable(matchInfo, enumVal, firstDefaultBlock)
        if (let Some(branchBlocks) <- branchInfos.get(0)) {
            for (block in branchBlocks) {
                builder.CreateGoTo(trueBlock, block)
            }
        }
        currentBlock = falseBlock
        return (trueBlock, if (isStillReachable) { Some(falseBlock) } else { None })
    }

    private func TranslateTrivialLetPatternAsTable(letPattern: AstLetPatternDestructor, selectorVal: Value,
        countOfPatterns: Int64): (Block, Option<Block>) {
        let indexToBodies = TreeMap<UInt64, Block>()
        let baseBlock = CurrentBlock()
        let trueBlock = CreateBlock()
        var defaultBlock: Option<Block> = None
        var isStillReachable = true
        scopeInfo.add(-1)
        scopeInfo[scopeInfo.size - 1] = scopeInfo[scopeInfo.size - 1] + 1
        CJC_ASSERT(!letPattern.patterns.isEmpty())
        if (letPattern.patterns[0].astKind == ASTKind.WILDCARD_PATTERN) {
            let patternBlock = CreateBlock()
            isStillReachable = false
            defaultBlock = Some(patternBlock)
        } else {
            for (pattern in letPattern.patterns) {
                let patternVal = GetJumpablePatternVal(pattern)
                let patternBlock = CreateBlock()
                patternBlock.SetDebugLocation(TranslateLocation(pattern))
                builder.CreateGoTo(trueBlock, patternBlock)
                if (indexToBodies.contains(patternVal)) {
                    continue
                }
                indexToBodies[patternVal] = patternBlock
                if (Int64(indexToBodies.size) == countOfPatterns) {
                    isStillReachable = false
                    defaultBlock = Some(patternBlock)
                }
            }
        }
        scopeInfo.remove(at: scopeInfo.size - 1)
        if (let None <- defaultBlock) {
            defaultBlock = Some(CreateBlock())
        }
        let realDefaultBlock = defaultBlock.getOrThrow()
        let indexes = ArrayList<UInt64>()
        let blocks = ArrayList<Block>()
        for (key in indexToBodies.keys()) {
            indexes.add(key)
            blocks.add(indexToBodies.get(key).getOrThrow())
        }
        currentBlock = baseBlock
        let targetType = if (let Some(enumTy) <- (RequireAstTy(RequireExpr(letPattern.initializer,
            "if-let initializer")) as AstEnumTy)) {
            GetSelectorType(enumTy)
        } else {
            builder.context.GetUInt64Ty()
        }
        let castedVal = TypeCastOrBoxIfNeeded(selectorVal, targetType, INVALID_LOCATION)
        let term = builder.CreateMultiBranch(castedVal, realDefaultBlock, indexes, blocks, baseBlock)
        term.SetDebugLocation(TranslateLocation(letPattern))
        currentBlock = realDefaultBlock
        return (trueBlock, if (isStillReachable) { Some(realDefaultBlock) } else { None })
    }

    public func Visit(expr: AstIfExpr): Option<Value> {
        let condExpr = RequireExpr(expr.condExpr, "if condition")
        let parentBlock = CurrentBlock()
        let group = parentBlock.GetParentBlockGroup() ??
            throw IllegalStateException("faithful AST2CHIR if requires parent block group")
        let thenBlock = builder.CreateBlock(group)
        let elseBlock = builder.CreateBlock(group)
        let joinBlock = builder.CreateBlock(group)
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let forceGenerateUnit = opts.enableCompileDebug && IsEmptyIf(expr)
        let resultLoc: Option<Value> = if ((HasTypeOfNothing(expr) || resultTy.IsUnit()) && !forceGenerateUnit) {
            None
        } else {
            let allocate = builder.CreateAllocate(builder.context.GetRefTy(resultTy), resultTy, parentBlock)
            allocate.SetDebugLocation(TranslateLocation(expr))
            RequireResult(allocate)
        }
        TranslateIfCondition(condExpr, thenBlock, elseBlock)

        currentBlock = thenBlock
        let thenAstBlock = RequireBlock(expr.thenBody, "if then body")
        let thenValue = Translator.TranslateASTNode(thenAstBlock, this)
        if (thenBlock.GetTerminator().isNone()) {
            builder.CreateGoTo(GetBlockByAST(thenAstBlock), thenBlock)
        }
        StoreIfResult(resultLoc, thenValue)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(joinBlock, CurrentBlock())
        }

        currentBlock = elseBlock
        let elseValue: Option<Value> = if (let Some(elseExpr) <- expr.elseBody) {
            let value = Translator.TranslateASTNode(elseExpr, this)
            if (let Some(elseAstBlock) <- (elseExpr as AstBlock)) {
                if (elseBlock.GetTerminator().isNone()) {
                    builder.CreateGoTo(GetBlockByAST(elseAstBlock), elseBlock)
                }
            }
            value
        } else {
            None
        }
        StoreIfResult(resultLoc, elseValue)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(joinBlock, CurrentBlock())
        }

        currentBlock = joinBlock
        if (let Some(location) <- resultLoc) {
            let load = builder.CreateLoad(resultTy, location, joinBlock)
            load.SetDebugLocation(TranslateLocation(expr))
            if (forceGenerateUnit) {
                load.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
            }
            return RequireResult(load)
        }
        return None
    }

    private func HasTypeOfNothing(expr: AstIfExpr): Bool {
        let elseBody = expr.elseBody ?? return false
        return RequireAstTy(RequireBlock(expr.thenBody, "if then body")).IsNothing() &&
            RequireAstTy(elseBody).IsNothing()
    }

    private func IsEmptyIf(expr: AstIfExpr): Bool {
        if (!IsEmptyBlock(RequireBlock(expr.thenBody, "if then body"))) {
            return false
        }
        if (let Some(elseBody) <- expr.elseBody) {
            if (let Some(block) <- (elseBody as AstBlock)) {
                return IsEmptyBlock(block)
            }
            if (let Some(elseIf) <- (elseBody as AstIfExpr)) {
                return IsEmptyIf(elseIf)
            }
            return false
        }
        return true
    }

    private func IsEmptyBlock(block: AstBlock): Bool {
        if (block.body.size == 1) {
            if (let Some(literal) <- (block.body[0] as AstLitConstExpr)) {
                return RequireAstTy(literal).IsUnit()
            }
            return false
        }
        return block.body.isEmpty()
    }

    public func Visit(expr: AstAssignExpr): Option<Value> {
        let leftExpr = RequireExpr(expr.leftValue, "assign left value")
        let rightExpr = RequireExpr(expr.rightExpr, "assign right expression")
        if (leftExpr.astKind == ASTKind.WILDCARD_EXPR) {
            let _ = Translator.TranslateASTNode(rightExpr, this)
            return None
        }
        if (TranslatePropertySetterAssign(expr, leftExpr, rightExpr)) {
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
            if (let Some(varDecl) <- (target as AstVarDecl)) {
                let leftValueInfo = TranslateMemberAccessAsLeftValue(expr)
                return LoadLeftValue(leftValueInfo, MemberAccessValueType(expr, target))
            }
            if (let Some(funcDecl) <- (target as AstFuncDecl)) {
                return Some(TranslateFuncMemberAccess(expr, funcDecl))
            }
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: unsupported member access")
    }

    private func TranslateFuncMemberAccess(member: AstMemberAccess, funcDecl: AstFuncDecl): Value {
        let instFuncType = GetInstCalleeInfoFromMemberAccess(member, funcDecl)
        let thisVal = TranslateThisObjectForFuncMemberAccess(member, funcDecl)
        return WrapMemberMethodByLambda(funcDecl, instFuncType, Some(thisVal))
    }

    private func GetInstCalleeInfoFromMemberAccess(member: AstMemberAccess,
        funcDecl: AstFuncDecl): FaithfulInstCalleeInfo {
        let baseExpr = RequireExpr(member.baseExpr, "member function reference base")
        var thisType = chirTy.TranslateType(RequireAstTy(baseExpr))
        thisType = AddRefIfFuncIsMutOrClass(thisType, funcDecl)

        let memberFuncTy = MemberAccessFuncType(member)
        let instParamTys = memberFuncTy.GetParamTypes()
        if (!funcDecl.TestAttr(AstAttribute.STATIC)) {
            instParamTys.add(thisType, at: 0)
        }
        let instRetTy = memberFuncTy.GetReturnType()
        let instParentTy = InstantiateMemberOwnerType(funcDecl, thisType)
        return FaithfulInstCalleeInfo(instParentTy, thisType, instParamTys, instRetTy,
            TranslateMemberAccessInstArgs(member), ShouldUseVirtualMemberDispatchForMemberAccess(member, funcDecl))
    }

    private func MemberAccessFuncType(member: AstMemberAccess): FuncType {
        let astTy = RequireAstTy(member)
        return RequireFuncType(chirTy.TranslateType(astTy))
    }

    private func TranslateMemberAccessInstArgs(member: AstMemberAccess): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (instTy in member.instTys) {
            out.add(chirTy.TranslateType(instTy))
        }
        return out
    }

    private func InstantiateMemberOwnerType(funcDecl: AstFuncDecl, thisType: Type): Type {
        let ownerTy = TranslateMemberOwnerType(funcDecl)
        let genericParams = TranslateFuncGenericParams(funcDecl)
        let replacements = ArrayList<Type>()
        AddMemberOwnerGenericReplacements(funcDecl, Some(thisType), genericParams, replacements)
        return SubstituteGenericType(ownerTy, genericParams, replacements).StripAllRefs()
    }

    private func AddRefIfFuncIsMutOrClass(thisType: Type, funcDecl: AstFuncDecl): Type {
        if (thisType.IsRef()) {
            return thisType
        }
        if (thisType.IsClassOrArray() || funcDecl.TestAnyAttr(AstAttribute.MUT, AstAttribute.CONSTRUCTOR)) {
            return builder.context.GetRefTy(thisType)
        }
        return thisType
    }

    private func ShouldUseVirtualMemberDispatchForMemberAccess(member: AstMemberAccess, funcDecl: AstFuncDecl): Bool {
        if (let Some(baseExpr) <- member.baseExpr) {
            if (let Some(refExpr) <- (baseExpr as AstRefExpr)) {
                if (refExpr.isSuper) {
                    return false
                }
            }
            let baseTy = chirTy.TranslateType(RequireAstTy(baseExpr)).StripAllRefs()
            if (baseTy.IsCustomType() && funcDecl.TestAttr(AstAttribute.STATIC)) {
                return false
            }
        }
        return ShouldUseVirtualMemberDispatch(funcDecl)
    }

    private func TranslateThisObjectForFuncMemberAccess(member: AstMemberAccess, funcDecl: AstFuncDecl): Value {
        let baseExpr = RequireExpr(member.baseExpr, "member function reference receiver")
        if (IsThisOrSuperRef(baseExpr)) {
            return GetCurrentThisObjectForMember(funcDecl)
        }
        var thisObj = Translator.TranslateASTNode(baseExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR member function reference receiver produced no value")
        let baseTy = RequireAstTy(baseExpr)
        if (baseTy.IsClassLike()) {
            if (let Some(objTy) <- thisObj.GetType()) {
                if (let Some(refTy) <- (objTy as RefType)) {
                    if (refTy.GetBaseType().IsRef()) {
                        thisObj = RequireResult(builder.CreateLoad(refTy.GetBaseType(), thisObj, CurrentBlock()))
                    }
                }
            }
        } else if (!baseTy.IsStruct() || !funcDecl.TestAttr(AstAttribute.MUT)) {
            if (let Some(objTy) <- thisObj.GetType()) {
                if (let Some(refTy) <- (objTy as RefType)) {
                    if (!refTy.GetBaseType().IsRef()) {
                        thisObj = RequireResult(builder.CreateLoad(refTy.GetBaseType(), thisObj, CurrentBlock()))
                    }
                }
            }
        }
        return thisObj
    }

    private func WrapMemberMethodByLambda(funcDecl: AstFuncDecl, instFuncType: FaithfulInstCalleeInfo,
        thisObj: Option<Value>): Value {
        let topLevelFunc = CurrentBlock().GetTopLevelFunc() ?? CurrentFunction()
        let lambdaMangledName = FaithfulTranslatorGenerateLambdaFuncMangleName(topLevelFunc, lambdaWrapperCounter)
        lambdaWrapperCounter++

        let lambdaParamTypes = instFuncType.instParamTys.clone()
        if (!funcDecl.TestAttr(AstAttribute.STATIC)) {
            if (lambdaParamTypes.isEmpty()) {
                throw IllegalStateException("faithful AST2CHIR member wrapper expected receiver parameter")
            }
            lambdaParamTypes.remove(at: 0)
        }
        let lambdaType = builder.context.GetFuncTy(lambdaParamTypes, instFuncType.instRetTy)
        let lambda = builder.CreateLambda(lambdaType, lambdaType, CurrentBlock(), isLocalFunc: false,
            identifier: lambdaMangledName, srcCodeIdentifier: funcDecl.identifier.Val())

        let lambdaBlockGroup = builder.CreateBlockGroup(topLevelFunc)
        lambda.InitBody(lambdaBlockGroup)
        let entry = builder.CreateBlock(lambdaBlockGroup)
        lambdaBlockGroup.SetEntryBlock(entry)
        for (paramTy in lambdaParamTypes) {
            builder.CreateParameter(paramTy, INVALID_LOCATION, lambda)
        }
        let retVal = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(instFuncType.instRetTy),
            instFuncType.instRetTy, entry))
        lambda.SetReturnValue(retVal)

        let currentBlockBackup = currentBlock
        currentBlock = entry
        let args = LambdaParamValues(lambda)
        let ret = if (instFuncType.isVirtualFuncCall) {
            CreateMemberWrapperInvoke(funcDecl, instFuncType, thisObj, args)
        } else {
            CreateMemberWrapperApply(funcDecl, instFuncType, thisObj, lambda, args)
        }
        builder.CreateStore(CastValueIfNeeded(ret, RequireRefBaseType(retVal)), retVal, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        currentBlock = currentBlockBackup
        return lambda.GetResult() ??
            throw IllegalStateException("faithful AST2CHIR member wrapper lambda has no result")
    }

    private func LambdaParamValues(lambda: Lambda): ArrayList<Value> {
        let out = ArrayList<Value>()
        for (param in lambda.GetParams()) {
            out.add(param)
        }
        return out
    }

    private func CreateMemberWrapperInvoke(funcDecl: AstFuncDecl, instFuncType: FaithfulInstCalleeInfo,
        thisObj: Option<Value>, args: ArrayList<Value>): Value {
        if (funcDecl.TestAttr(AstAttribute.STATIC)) {
            if (thisObj.isSome()) {
                throw IllegalStateException("faithful AST2CHIR static member wrapper unexpectedly captured receiver")
            }
            let rtti = RequireResult(builder.CreateGetRTTIStatic(builder.context.GetUnitTy(),
                instFuncType.thisType.StripAllRefs(), CurrentBlock()))
            let invokeInfo = GenerateInvokeCallContext(instFuncType, rtti, funcDecl, args)
            return RequireResult(builder.CreateInvokeStatic(instFuncType.instRetTy, invokeInfo, CurrentBlock()))
        }
        let caller = thisObj ??
            throw IllegalStateException("faithful AST2CHIR virtual member wrapper has no receiver")
        let invokeInfo = GenerateInvokeCallContext(instFuncType, caller, funcDecl, args)
        return RequireResult(builder.CreateInvoke(instFuncType.instRetTy, invokeInfo, CurrentBlock()))
    }

    private func CreateMemberWrapperApply(funcDecl: AstFuncDecl, instFuncType: FaithfulInstCalleeInfo,
        thisObj: Option<Value>, lambda: Lambda, lambdaArgs: ArrayList<Value>): Value {
        let args = lambdaArgs.clone()
        if (let Some(rawThis) <- thisObj) {
            var objExpectedType = instFuncType.instParentCustomTy
            if (objExpectedType.IsReferenceType()) {
                objExpectedType = builder.context.GetRefTy(objExpectedType)
            }
            args.add(TransformThisType(rawThis, objExpectedType, lambda), at: 0)
        }
        if (args.size != instFuncType.instParamTys.size) {
            throw IllegalStateException("faithful AST2CHIR member wrapper argument count mismatch")
        }
        let instTypeArgs = instFuncType.instantiatedTypeArgs.clone()
        var callee = GetSymbolTable(funcDecl)
        let funcType = builder.context.GetFuncTy(instFuncType.instParamTys, instFuncType.instRetTy)
        if (let Some(wrapperFunc) <- GetWrapperFuncFromMemberAccess(instFuncType.instParentCustomTy.StripAllRefs(),
            callee.GetSrcCodeIdentifier(), funcType, callee.TestAttr(Attribute.STATIC), instTypeArgs)) {
            callee = wrapperFunc
        }
        return RequireResult(builder.CreateApply(instFuncType.instRetTy, callee, FuncCallContext(args: args,
            instTypeArgs: instTypeArgs, thisType: Some(instFuncType.thisType)), CurrentBlock()))
    }

    private func GenerateInvokeCallContext(instFuncType: FaithfulInstCalleeInfo, caller: Value,
        callee: AstFuncDecl, args: ArrayList<Value>): InvokeCallContext {
        let methodType = BuildMethodFuncTypeForMemberAccess(callee)
        let genericParams = TranslateFuncGenericParams(callee)
        return InvokeCallContext(caller, FuncCallContext(args: args,
            instTypeArgs: instFuncType.instantiatedTypeArgs, thisType: Some(instFuncType.thisType)),
            FuncSigInfo(methodType, funcName: callee.identifier.Val(), genericTypeParams: genericParams))
    }

    private func BuildMethodFuncTypeForMemberAccess(funcDecl: AstFuncDecl): FuncType {
        let originalFuncDecl = if (let Some(resolver) <- overrideSrcFuncResolver) {
            resolver(funcDecl) ?? funcDecl
        } else {
            funcDecl
        }
        let funcTy = RequireFuncType(chirTy.TranslateType(RequireAstTy(originalFuncDecl)))
        let params = funcTy.GetParamTypes()
        if (!originalFuncDecl.TestAttr(AstAttribute.STATIC)) {
            params.add(AddRefIfFuncIsMutOrClass(TranslateMemberOwnerType(originalFuncDecl), originalFuncDecl), at: 0)
        }
        return builder.context.GetFuncTy(params, funcTy.GetReturnType())
    }

    private func TransformThisType(rawThis: Value, expectedTy: Type, curLambda: Lambda): Value {
        let rawThisTy = rawThis.GetType() ??
            throw IllegalStateException("faithful AST2CHIR member wrapper receiver has no type")
        if (rawThisTy.IsEqual(expectedTy)) {
            return rawThis
        }
        let parentBlock = curLambda.GetParentBlock() ??
            throw IllegalStateException("faithful AST2CHIR member wrapper lambda has no parent block")
        var expr: Expression
        if (let Some(refTy) <- (rawThisTy as RefType)) {
            if (refTy.GetBaseType().IsStruct() && refTy.GetBaseType().IsEqual(expectedTy)) {
                expr = builder.CreateLoad(expectedTy, rawThis, parentBlock)
            } else {
                expr = builder.CreateTypeCast(expectedTy, rawThis, parentBlock)
            }
        } else {
            expr = builder.CreateTypeCast(expectedTy, rawThis, parentBlock)
        }
        expr.MoveBefore(curLambda)
        return RequireResult(expr)
    }

    private func GetWrapperFuncFromMemberAccess(thisType: Type, funcName: String, instFuncType: FuncType,
        isStatic: Bool, funcInstTypeArgs: ArrayList<Type>): Option<Value> {
        if (let Some(genericType) <- (thisType as GenericType)) {
            for (upperBound in genericType.GetUpperBounds()) {
                let upperClassType = ((upperBound as RefType).getOrThrow().GetBaseType() as ClassType).getOrThrow()
                return GetWrapperFuncFromMemberAccess(upperClassType, funcName, instFuncType, isStatic,
                    funcInstTypeArgs)
            }
            return None
        }
        if (let Some(customTy) <- (thisType as CustomType)) {
            return GetExpectedFuncFromCustomType(customTy, funcName, instFuncType, true, funcInstTypeArgs)
        }
        if (let Some(builtinTy) <- (thisType as BuiltinType)) {
            for (extendDef in builtinTy.GetExtends(builder)) {
                let replaceTable = HashMap<Int64, Type>()
                let classInstArgs = builtinTy.GetTypeArgs()
                let classGenericArgs = extendDef.GetExtendedType().getOrThrow().GetTypeArgs()
                if (classInstArgs.size != classGenericArgs.size) {
                    throw IllegalStateException("faithful AST2CHIR member wrapper extend generic size mismatch")
                }
                var typeIdx: Int64 = 0
                while (typeIdx < classInstArgs.size) {
                    if (let Some(genericTy) <- (classGenericArgs[typeIdx] as GenericType)) {
                        if (!replaceTable.contains(genericTy.objectId)) {
                            replaceTable[genericTy.objectId] = classInstArgs[typeIdx]
                        }
                    }
                    typeIdx++
                }
                if (let Some(found) <- GetExpectedFuncFromDef(extendDef, funcName, instFuncType, true,
                    replaceTable, funcInstTypeArgs)) {
                    return found
                }
            }
        }
        return None
    }

    private func GetExpectedFuncFromCustomType(customTy: CustomType, funcName: String, instFuncType: FuncType,
        isStatic: Bool, funcInstTypeArgs: ArrayList<Type>): Option<Value> {
        let replaceTable = HashMap<Int64, Type>()
        let classInstArgs = customTy.GetTypeArgs()
        let classGenericArgs = customTy.GetCustomTypeDef().GetGenericTypeParams()
        if (!classGenericArgs.isEmpty()) {
            CJC_ASSERT(classInstArgs.size == classGenericArgs.size)
        }
        var classArgIdx: Int64 = 0
        while (classArgIdx < classGenericArgs.size) {
            replaceTable[classGenericArgs[classArgIdx].objectId] = classInstArgs[classArgIdx]
            classArgIdx++
        }
        if (let Some(found) <- GetExpectedFuncFromDef(customTy.GetCustomTypeDef(), funcName, instFuncType, isStatic,
            replaceTable, funcInstTypeArgs)) {
            return found
        }
        for (extendDef in customTy.GetCustomTypeDef().GetExtends()) {
            let matchResult = CollectReplaceTableForExtendedType(extendDef.GetExtendedType().getOrThrow(), customTy,
                replaceTable)
            if (!matchResult) {
                continue
            }
            if (let Some(found) <- GetExpectedFuncFromDef(extendDef, funcName, instFuncType, isStatic,
                replaceTable, funcInstTypeArgs)) {
                return found
            }
        }
        if (let Some(classTy) <- (customTy as ClassType)) {
            if (let Some(superTy) <- classTy.GetSuperClassTy()) {
                if (let Some(found) <- GetExpectedFuncFromCustomType(superTy, funcName, instFuncType, isStatic,
                    funcInstTypeArgs)) {
                    return found
                }
            }
        }
        for (interfaceTy in customTy.GetCustomTypeDef().GetImplementedInterfaceTys()) {
            if (let Some(found) <- GetExpectedFuncFromCustomType(interfaceTy, funcName, instFuncType, isStatic,
                funcInstTypeArgs)) {
                return found
            }
        }
        for (extendDef in customTy.GetCustomTypeDef().GetExtends()) {
            for (ty in extendDef.GetImplementedInterfaceTys()) {
                let superInterfaceTy = ReplaceRawGenericArgType(ty, replaceTable, builder)
                if (let Some(classTy) <- (superInterfaceTy as ClassType)) {
                    if (let Some(found) <- GetExpectedFuncFromCustomType(classTy, funcName, instFuncType, isStatic,
                        funcInstTypeArgs)) {
                        return found
                    }
                }
            }
        }
        return None
    }

    private func GetExpectedFuncFromDef(def: CustomTypeDef, funcName: String, instFuncType: FuncType, isStatic: Bool,
        replaceTable: HashMap<Int64, Type>, funcInstTypeArgs: ArrayList<Type>): Option<Function> {
        if (let Some(found) <- def.GetExpectedFunc(funcName, instFuncType, isStatic, replaceTable, funcInstTypeArgs,
            builder, false)) {
            return found
        }
        return None
    }

    private func GetExactParentType(fuzzyParentType: Type, resolvedFunction: AstFuncDecl, funcType: FuncType,
        funcInstTypeArgs: ArrayList<Type>, checkAbstractMethod: Bool): Option<Type> {
        if (fuzzyParentType.IsNothing()) {
            return fuzzyParentType
        }
        let outerDecl = resolvedFunction.outerDecl.getOrThrow()
        if (outerDecl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) {
            let parentTy = if (outerDecl.astKind == ASTKind.EXTEND_DECL) {
                let extendDecl = (outerDecl as AstExtendDecl).getOrThrow()
                let extendedType = extendDecl.extendedType.getOrThrow()
                chirTy.TranslateType(RequireAstTy(extendedType))
            } else {
                chirTy.TranslateType(RequireAstTy(outerDecl))
            }
            return parentTy.StripAllRefs()
        }
        let funcName = resolvedFunction.identifier.Val()
        let isStatic = resolvedFunction.TestAttr(AstAttribute.STATIC)
        if (let Some(genericTy) <- (fuzzyParentType as GenericType)) {
            for (upperBound in genericTy.GetUpperBounds()) {
                let upperClassType = ((upperBound as RefType).getOrThrow().GetBaseType() as ClassType).getOrThrow()
                if (let Some(exactParentType) <- GetExactParentType(upperClassType, resolvedFunction, funcType,
                    funcInstTypeArgs, checkAbstractMethod)) {
                    return exactParentType
                }
            }
            return None
        }
        if (let Some(customTy) <- (fuzzyParentType as CustomType)) {
            return GetExactParentType(customTy, funcName, funcType, isStatic, funcInstTypeArgs, checkAbstractMethod)
        }
        let classInstArgs = fuzzyParentType.GetTypeArgs()
        let extendDefs = fuzzyParentType.GetExtends(builder)
        CJC_ASSERT(!extendDefs.isEmpty())
        let replaceTable = HashMap<Int64, Type>()
        for (extendDef in extendDefs) {
            let classGenericArgs = extendDef.GetExtendedType().getOrThrow().GetTypeArgs()
            CJC_ASSERT(classInstArgs.size == classGenericArgs.size)
            var typeIdx: Int64 = 0
            while (typeIdx < classInstArgs.size) {
                if (let Some(genericTy) <- (classGenericArgs[typeIdx] as GenericType)) {
                    if (!replaceTable.contains(genericTy.objectId)) {
                        replaceTable[genericTy.objectId] = classInstArgs[typeIdx]
                    }
                }
                typeIdx++
            }
            if (let Some(found) <- GetExpectedFuncFromDef(extendDef, funcName, funcType, isStatic, replaceTable,
                funcInstTypeArgs)) {
                if (found.GetWrappedRawMethod().isNone()) {
                    return ReplaceRawGenericArgType(extendDef.GetExtendedType().getOrThrow(), replaceTable, builder)
                }
            }
        }
        for (extendDef in extendDefs) {
            for (ty in extendDef.GetImplementedInterfaceTys()) {
                if (let Some(customTy) <- (ty as CustomType)) {
                    if (let Some(exactParentType) <- GetExactParentType(customTy, funcName, funcType, isStatic,
                        funcInstTypeArgs, checkAbstractMethod)) {
                        return exactParentType
                    }
                }
            }
        }
        return None
    }

    private func GetExactParentType(customTy: CustomType, funcName: String, funcType: FuncType, isStatic: Bool,
        funcInstTypeArgs: ArrayList<Type>, checkAbstractMethod: Bool): Option<Type> {
        let replaceTable = HashMap<Int64, Type>()
        let classInstArgs = customTy.GetTypeArgs()
        let classGenericArgs = customTy.GetCustomTypeDef().GetGenericTypeParams()
        if (!classGenericArgs.isEmpty()) {
            CJC_ASSERT(classInstArgs.size == classGenericArgs.size)
        }
        var classArgIdx: Int64 = 0
        while (classArgIdx < classGenericArgs.size) {
            replaceTable[classGenericArgs[classArgIdx].objectId] = classInstArgs[classArgIdx]
            classArgIdx++
        }
        if (GetExpectedFuncFromDef(customTy.GetCustomTypeDef(), funcName, funcType, isStatic, replaceTable,
            funcInstTypeArgs).isSome()) {
            return customTy
        }
        for (extendDef in customTy.GetCustomTypeDef().GetExtends()) {
            let matchResult = CollectReplaceTableForExtendedType(extendDef.GetExtendedType().getOrThrow(), customTy,
                replaceTable)
            if (!matchResult) {
                continue
            }
            if (GetExpectedFuncFromDef(extendDef, funcName, funcType, isStatic, replaceTable, funcInstTypeArgs).isSome()) {
                return ReplaceRawGenericArgType(extendDef.GetExtendedType().getOrThrow(), replaceTable, builder)
            }
        }
        if (let Some(classTy) <- (customTy as ClassType)) {
            if (let Some(superTy) <- classTy.GetClassDef().GetSuperClassTy()) {
                let superClassTy = ReplaceRawGenericArgType(superTy, replaceTable, builder)
                if (let Some(superCustomTy) <- (superClassTy as CustomType)) {
                    if (let Some(exactParentType) <- GetExactParentType(superCustomTy, funcName, funcType, isStatic,
                        funcInstTypeArgs, checkAbstractMethod)) {
                        return exactParentType
                    }
                }
            }
        }
        for (ty in customTy.GetCustomTypeDef().GetImplementedInterfaceTys()) {
            let superInterfaceTy = ReplaceRawGenericArgType(ty, replaceTable, builder)
            if (let Some(superCustomTy) <- (superInterfaceTy as CustomType)) {
                if (let Some(exactParentType) <- GetExactParentType(superCustomTy, funcName, funcType, isStatic,
                    funcInstTypeArgs, checkAbstractMethod)) {
                    return exactParentType
                }
            }
        }
        for (extendDef in customTy.GetCustomTypeDef().GetExtends()) {
            for (ty in extendDef.GetImplementedInterfaceTys()) {
                let superInterfaceTy = ReplaceRawGenericArgType(ty, replaceTable, builder)
                if (let Some(superCustomTy) <- (superInterfaceTy as CustomType)) {
                    if (let Some(exactParentType) <- GetExactParentType(superCustomTy, funcName, funcType, isStatic,
                        funcInstTypeArgs, checkAbstractMethod)) {
                        return exactParentType
                    }
                }
            }
        }
        return None
    }

    private func CollectReplaceTableForExtendedType(extendedType: Type, instCustomType: Type,
        replaceTable: HashMap<Int64, Type>): Bool {
        let instTypeArgs = instCustomType.GetTypeArgs()
        let genericTypeArgs = extendedType.GetTypeArgs()
        if (instTypeArgs.size != genericTypeArgs.size) {
            return false
        }
        var idx: Int64 = 0
        while (idx < genericTypeArgs.size) {
            if (let Some(genericTy) <- (genericTypeArgs[idx] as GenericType)) {
                if (let Some(storedTy) <- replaceTable.get(genericTy.objectId)) {
                    if (!storedTy.IsEqual(instTypeArgs[idx])) {
                        return false
                    }
                } else {
                    replaceTable[genericTy.objectId] = instTypeArgs[idx]
                }
            } else {
                let genericArgTy = genericTypeArgs[idx] as CustomType
                let instArgTy = instTypeArgs[idx] as CustomType
                if (genericArgTy.isSome() && instArgTy.isNone()) {
                    return false
                }
                if (genericArgTy.isNone() && instArgTy.isSome()) {
                    return false
                }
                if (let Some(genericCustomTy) <- genericArgTy) {
                    if (let Some(instCustomTy) <- instArgTy) {
                        if (genericCustomTy.GetCustomTypeDef().nodeId != instCustomTy.GetCustomTypeDef().nodeId) {
                            return false
                        }
                    }
                }
                let matchResult = CollectReplaceTableForExtendedType(genericTypeArgs[idx], instTypeArgs[idx],
                    replaceTable)
                if (!matchResult) {
                    return false
                }
            }
            idx++
        }
        return true
    }

    private func TranslatePropertyGetter(expr: AstMemberAccess, propDecl: AstPropDecl): Value {
        if (propDecl.getters.isEmpty()) {
            throw IllegalStateException("faithful AST2CHIR property has no getter: ${propDecl.identifier.Val()}")
        }
        let getter = propDecl.getters[0]
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let callee = GetSymbolTable(getter)
        if (getter.TestAttr(AstAttribute.STATIC) || propDecl.TestAttr(AstAttribute.STATIC)) {
            let instTypeArgs = TranslateMemberAccessInstArgs(expr)
            let parentTy = TranslateMemberOwnerType(getter)
            return CreateApplyMaybeWithException(resultTy, callee,
                FuncCallContext(args: ArrayList<Value>(), instTypeArgs: instTypeArgs, thisType: parentTy))
        }
        let thisObj = TranslatePropertyGetterThisObject(expr, getter, callee)
        let args = ArrayList<Value>()
        args.add(thisObj)
        return CreateApplyMaybeWithException(resultTy, callee, FuncCallContext(args: args, thisType: thisObj.GetType()))
    }

    private func TranslatePropertyGetterThisObject(expr: AstMemberAccess, getter: AstFuncDecl, callee: Value): Value {
        var thisObj: Value
        if (let Some(baseExpr) <- expr.baseExpr) {
            let baseTy = chirTy.TranslateType(RequireAstTy(baseExpr))
            if (PropertyGetterNeedsAddress(callee)) {
                thisObj = AddressOfLeftValue(TranslateExprAsLeftValue(baseExpr), baseTy)
            } else {
                thisObj = Translator.TranslateASTNode(baseExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR property getter base produced no value")
            }
            return NormalizeThisObjectForNonStaticMemberFuncCall(thisObj, getter.TestAttr(AstAttribute.MUT))
        }
        if (let Some(_) <- getter.outerDecl) {
            thisObj = GetCurrentThisObject()
            return NormalizeThisObjectForNonStaticMemberFuncCall(thisObj, getter.TestAttr(AstAttribute.MUT))
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
        TranslateIfCondition(RequireExpr(expr.condExpr, "while condition"), bodyBlock, endBlock)

        currentBlock = bodyBlock
        let bodyAstBlock = RequireBlock(expr.body, "while body")
        let _ = Translator.TranslateASTNode(bodyAstBlock, this)
        if (bodyBlock.GetTerminator().isNone()) {
            builder.CreateGoTo(GetBlockByAST(bodyAstBlock), bodyBlock)
        }
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
        let bodyAstBlock = RequireBlock(expr.body, "do-while body")
        let _ = Translator.TranslateASTNode(bodyAstBlock, this)
        if (bodyBlock.GetTerminator().isNone()) {
            builder.CreateGoTo(GetBlockByAST(bodyAstBlock), bodyBlock)
        }
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
            case AstForInKind.FORIN_STRING => TranslateForInString(expr)
            case AstForInKind.FORIN_INVALID => TranslateForInInvalid(expr)
        }
    }

    public func Visit(expr: AstJumpExpr): Option<Value> {
        if (let Some(refLoop) <- expr.refLoop) {
            let shouldRecordFinally = ShouldRecordJumpForFinally(refLoop)
            if (refLoop.astKind == ASTKind.FOR_IN_EXPR && delayExitSignal.isSome()) {
                if (shouldRecordFinally) {
                    RecordFinallyControlIfNeeded(if (expr.isBreak) {
                        FaithfulFinallyControlType.BREAK
                    } else {
                        FaithfulFinallyControlType.CONTINUE
                    }, controlScopeLevel: refLoop.scopeLevel)
                }
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
        if (let Some(refLoop2) <- expr.refLoop) {
            if (ShouldRecordJumpForFinally(refLoop2)) {
                RecordFinallyControlIfNeeded(if (expr.isBreak) {
                    FaithfulFinallyControlType.BREAK
                } else {
                    FaithfulFinallyControlType.CONTINUE
                }, controlScopeLevel: refLoop2.scopeLevel)
            }
        }
        builder.CreateGoTo(destination, CurrentBlock())
        let group = RequireParentBlockGroup(CurrentBlock(), "jump continuation")
        currentBlock = builder.CreateBlock(group)
        return None
    }

    public func Visit(expr: AstMatchExpr): Option<Value> {
        let matchTy = chirTy.TranslateType(RequireAstTy(expr))
        let resultLoc: Option<Value> = if (HasTypeOfNothing(expr) || matchTy.IsUnit() || matchTy.IsNothing()) {
            None
        } else {
            RequireResult(builder.CreateAllocate(builder.context.GetRefTy(matchTy), matchTy, CurrentBlock()))
        }
        if (expr.matchMode) {
            if (CanOptimizeMatchToSwitch(expr)) {
                PrintDebugMessage(opts.chirDebugOptimizer, expr)
                TranslateMatchAsTable(expr, resultLoc)
            } else {
                TranslateMatchWithSelector(expr, resultLoc)
            }
        } else {
            TranslateConditionMatches(expr, resultLoc)
        }
        if (let Some(loc) <- resultLoc) {
            return RequireResult(builder.CreateLoad(matchTy, loc, CurrentBlock()))
        }
        return None
    }

    public func Visit(expr: AstTryExpr): Option<Value> {
        if (let Some(desugar) <- expr.desugarExpr) {
            return Translator.TranslateASTNode(desugar, this)
        }
        if (!expr.resourceSpec.isEmpty()) {
            throw IllegalArgumentException(
                "faithful AST2CHIR try-with-resources reached CHIR without after-type-check desugar")
        }
        if (!expr.handlers.isEmpty()) {
            throw IllegalArgumentException(
                "faithful AST2CHIR try-handle reached CHIR without after-type-check desugar")
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

        if (hasFinally) {
            PushFinallyContext(expr, normalEndBlock, finalEndBlock)
        }
        tryBodyContext.add(expr)
        tryCatchContext.add(exceptionBlock)
        if (expr.TestAttr(AstAttribute.MACRO_INVOKE_BODY)) {
            let pkg = builder.context.GetCurPackage() ??
                throw IllegalStateException("faithful AST2CHIR macro invoke body has no current package")
            let pkgInit = pkg.GetPackageInitFunc() ??
                throw IllegalStateException("faithful AST2CHIR macro invoke body has no package init function")
            let initFnTy = pkgInit.GetFuncType() ??
                throw IllegalStateException("faithful AST2CHIR package init function has no FuncType")
            let _ = CreateApplyMaybeWithException(initFnTy.GetReturnType(), pkgInit, FuncCallContext())
        }
        let baseBlock = CurrentBlock()
        let tryAstBlock = RequireBlock(expr.tryBlock, "try block")
        let tryValue = Translator.TranslateASTNode(tryAstBlock, this)
        if (baseBlock.GetTerminator().isNone()) {
            builder.CreateGoTo(GetBlockByAST(tryAstBlock), baseBlock)
        }
        let tryValueLoc = if (let Some(value) <- tryValue) {
            if (let Some(localVar) <- value.AsLocalVar()) {
                if (let Some(ownerExpr) <- localVar.GetExpr()) {
                    ownerExpr.GetDebugLocation()
                } else {
                    TranslateLocation(tryAstBlock)
                }
            } else {
                TranslateLocation(tryAstBlock)
            }
        } else {
            TranslateLocation(tryAstBlock)
        }
        if (!HasTypeOfNothing(expr)) {
            StoreTryResult(resultLoc, tryValue, tryValueLoc)
        }
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
            TranslateFinally(finallyBlock, pendingExceptionBlock ?? exceptionBlock)
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
        let tupleType = (RequireAstTy(expr) as AstTupleTy).getOrThrow()
        var idx: Int64 = 0
        while (idx < expr.children.size) {
            let value = TranslateExprArg(expr.children[idx], chirTy.TranslateType(tupleType.typeArgs[idx]))
            values.add(value)
            idx++
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
        return RequireResult(builder.CreateTypeCast(chirTy.TranslateType(RequireAstTy(expr)), operand, CurrentBlock(),
            overflowStrategy: expr.overflowStrategy))
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

    public func TranslateGlobalVarWithPatternInitializer(fn: Function, decl: AstVarWithPatternDecl): Unit {
        let body = fn.GetBody() ??
            throw IllegalStateException("faithful AST2CHIR global pattern initializer function has no body")
        let entry = body.GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR global pattern initializer function has no entry block")
        let savedFunc = currentFunc
        let savedBlock = currentBlock
        let savedDelayExitSignal = delayExitSignal
        delayExitSignal = None
        currentFunc = fn
        currentBlock = entry
        blockGroupStack.add(body)
        let initExpr = RequireExpr(decl.initializer, "global var-with-pattern initializer")
        let initValue = Translator.TranslateASTNode(initExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR global var-with-pattern initializer produced no value")
        FlattenVarWithPatternDecl(RequirePattern(decl.irrefutablePattern, "global var-with-pattern pattern"),
            Some(initValue), isLocalPattern: false)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateExit(None, CurrentBlock())
        }
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        delayExitSignal = savedDelayExitSignal
        currentFunc = savedFunc
        currentBlock = savedBlock
    }

    private func IsGlobalOrMemberFunc(funcDecl: AstFuncDecl): Bool {
        return funcDecl.TestAnyAttr(AstAttribute.GLOBAL, AstAttribute.IN_CLASSLIKE, AstAttribute.IN_ENUM) ||
            funcDecl.TestAnyAttr(AstAttribute.IN_STRUCT, AstAttribute.IN_EXTEND)
    }

    private func TranslateNestedFunc(funcDecl: AstFuncDecl): Option<Value> {
        if (funcDecl.TestAnyAttr(AstAttribute.INTRINSIC, AstAttribute.ABSTRACT, AstAttribute.FOREIGN)) {
            return None
        }
        let funcBody = funcDecl.funcBody ??
            throw IllegalStateException("faithful AST2CHIR nested FuncDecl has no FuncBody")
        let astBody = funcBody.body ??
            throw IllegalStateException("faithful AST2CHIR nested FuncDecl has no body")
        let funcTy = RequireFuncType(chirTy.TranslateType(RequireAstTy(funcDecl)))
        let body = builder.CreateBlockGroup(CurrentFunction())
        let identifier = if (funcDecl.mangledName.isEmpty()) {
            CurrentFunction().GetIdentifierWithoutPrefix() + "$local$" + funcDecl.identifier.Val()
        } else {
            funcDecl.mangledName
        }
        let lambda = builder.CreateLambda(funcTy, funcTy, CurrentBlock(), isLocalFunc: true,
            identifier: identifier, srcCodeIdentifier: funcDecl.identifier.Val())
        lambda.InitBody(body)
        if (funcDecl.isConst) {
            lambda.SetCompileTimeValue()
        }
        let lambdaValue = lambda.GetResult() ??
            throw IllegalStateException("faithful AST2CHIR nested FuncDecl lambda has no result")
        localValSymbolTable.Set(funcDecl, lambdaValue)
        BindLambdaParams(funcBody, lambda, funcTy)

        let savedBlock = currentBlock
        let savedLambda = currentLambda
        let savedAstFuncDecl = currentAstFuncDecl
        let savedDelayExitSignal = delayExitSignal
        let savedTryCatchContext = tryCatchContext.clone()
        let savedTryBodyContext = tryBodyContext.clone()
        let savedFinallyContext = finallyContext.clone()
        delayExitSignal = None
        tryCatchContext.clear()
        tryBodyContext.clear()
        finallyContext.clear()
        blockGroupStack.add(body)
        currentLambda = lambda
        currentAstFuncDecl = funcDecl
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        currentBlock = entry
        CreateLambdaParamDebugs(funcBody, lambda, entry, hasInitial: funcDecl.TestAttr(AstAttribute.HAS_INITIAL))
        let retTy = funcTy.GetReturnType()
        if (!retTy.IsUnit() && !retTy.IsNothing() && !retTy.IsVoid()) {
            let retSlot = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(retTy), retTy, entry))
            lambda.SetReturnValue(retSlot)
        }
        let result = Translator.TranslateASTNode(astBody, this)
        if (entry.GetTerminator().isNone()) {
            builder.CreateGoTo(GetBlockByAST(astBody), entry)
        }
        if (CurrentBlock().GetTerminator().isNone()) {
            EmitImplicitLambdaExit(lambda, result)
        }
        currentBlock = savedBlock
        currentLambda = savedLambda
        currentAstFuncDecl = savedAstFuncDecl
        delayExitSignal = savedDelayExitSignal
        tryCatchContext.clear()
        for (block in savedTryCatchContext) {
            tryCatchContext.add(block)
        }
        tryBodyContext.clear()
        for (tryExpr in savedTryBodyContext) {
            tryBodyContext.add(tryExpr)
        }
        finallyContext.clear()
        for (context in savedFinallyContext) {
            finallyContext.add(context)
        }
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        return Some(lambdaValue)
    }

    private func TranslateClassLikeDecl(def: ClassDef, decl: AstClassLikeDecl): Unit {
        if (let Some(astTy) <- decl.GetTy()) {
            let classTy = UnwrapClassType(chirTy.TranslateType(astTy))
            def.SetType(classTy)
        }
        let isImportedInstantiated = decl.TestAttr(AstAttribute.IMPORTED) &&
            decl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)
        var tiLinkage = if (isImportedInstantiated) {
            BasicLinkage.INTERNAL
        } else {
            decl.linkage
        }
        if (tiLinkage == BasicLinkage.INTERNAL) {
            tiLinkage = BasicLinkage.LINKONCE_ODR
        }
        def.SetLinkTypeInfo(tiLinkage)
        let needInitialSuperClassSetup = !decl.TestAttr(AstAttribute.SPECIFIC) ||
            decl.TestAttr(AstAttribute.IMPORTED) || decl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)
        if (needInitialSuperClassSetup) {
            SetClassSuperClass(def, decl)
            SetImplementedInterfaces(def, decl)
        }
        for (member in decl.GetMemberDeclPtrs()) {
            if (!ShouldTranslateMember(decl, member)) {
                continue
            }
            TranslateMemberDecl(def, member)
        }
    }

    private func DeclaredInDifferentFiles(left: AstDecl, right: AstDecl): Bool {
        if (let Some(leftFile) <- left.curFile) {
            if (let Some(rightFile) <- right.curFile) {
                return !refEq(leftFile, rightFile)
            }
        }
        return false
    }

    private func ShouldTranslateMember(decl: AstDecl, member: AstDecl): Bool {
        if (!mergingSpecific) {
            return true
        }
        if (decl.TestAttr(AstAttribute.IMPORTED)) {
            return true
        }
        if (!decl.TestAttr(AstAttribute.SPECIFIC)) {
            return true
        }
        if (decl.TestAttr(AstAttribute.GENERIC_INSTANTIATED)) {
            return true
        }
        let justIntroducedSpecific = !decl.TestAttr(AstAttribute.IMPORTED) &&
            decl.TestAttr(AstAttribute.SPECIFIC)
        if (mergingSpecific && justIntroducedSpecific && DeclaredInDifferentFiles(decl, member)) {
            return false
        }
        return true
    }

    private func SetClassSuperClass(def: ClassDef, decl: AstClassLikeDecl): Unit {
        if (def.GetSuperClassTy().isSome()) {
            return
        }
        if (let Some(astTy) <- decl.GetTy()) {
            if (let Some(classTy) <- (astTy as AstClassTy)) {
                if (let Some(superAstTy) <- classTy.GetSuperClassTy()) {
                    def.SetSuperClassTy(UnwrapClassType(chirTy.TranslateType(superAstTy)))
                }
            }
        }
    }

    private func SetImplementedInterfaces(def: CustomTypeDef, decl: AstInheritableDecl): Unit {
        for (superInterfaceTy in decl.GetStableSuperInterfaceTys()) {
            def.AddImplementedInterfaceTy(UnwrapClassType(chirTy.TranslateType(superInterfaceTy)))
        }
    }

    private func TranslateMemberDecl(def: CustomTypeDef, member: AstDecl): Unit {
        if (let Some(propDecl) <- (member as AstPropDecl)) {
            AddPropertyAccessors(def, propDecl)
        } else if (let Some(varDecl) <- (member as AstVarDecl)) {
            AddMemberVarDecl(def, varDecl)
        } else if (let Some(funcDecl) <- (member as AstFuncDecl)) {
            if (let Some(extendDef) <- (def as ExtendDef)) {
                AddExtendMethodAndDefaultParamMethods(extendDef, funcDecl)
            } else if (let Some(classDef) <- (def as ClassDef)) {
                TranslateClassLikeMemberFuncDecl(classDef, funcDecl)
            } else {
                AddMemberMethodToCustomTypeDef(def, funcDecl)
            }
        }
    }

    private func AddMethodIfPresent(def: CustomTypeDef, funcDecl: AstFuncDecl): Unit {
        if (let Some(value) <- globalSymbolTable.TryGet(funcDecl)) {
            if (let Some(fn) <- (value as Function)) {
                def.AddMethod(fn)
            }
        }
    }

    private func AddDefaultParamMethods(def: CustomTypeDef, funcDecl: AstFuncDecl): Unit {
        let body = match (funcDecl.funcBody) {
            case Some(value2) => value2
            case None => return
        }
        if (body.paramLists.isEmpty()) {
            return
        }
        for (param in body.paramLists[0].params) {
            if (let Some(desugarDecl) <- param.desugarDecl) {
                if (let Some(value) <- globalSymbolTable.TryGet(desugarDecl)) {
                    if (let Some(fn) <- (value as Function)) {
                        def.AddMethod(fn)
                    }
                }
            }
        }
    }

    private func AddMemberMethodToCustomTypeDef(def: CustomTypeDef, funcDecl: AstFuncDecl): Unit {
        if (IsStaticInit(funcDecl)) {
            return
        }
        AddMethodIfPresent(def, funcDecl)
        AddDefaultParamMethods(def, funcDecl)
        if (let Some(instFuncs) <- genericFuncMap.Get(funcDecl)) {
            AddMemberFunctionGenericInstantiations(def, instFuncs, funcDecl)
        }
    }

    private func TranslateClassLikeMemberFuncDecl(classDef: ClassDef, funcDecl: AstFuncDecl): Unit {
        if (SkipMemberFuncInSpecificMerging(classDef, funcDecl)) {
            return
        }
        AddMemberMethodToCustomTypeDef(classDef, funcDecl)
    }

    private func SkipMemberFuncInSpecificMerging(classDef: ClassDef, funcDecl: AstFuncDecl): Bool {
        if (!opts.IsCompilingCJMPSpecific() || !classDef.TestAttr(Attribute.DESERIALIZED)) {
            return false
        }
        for (method in classDef.GetMethods()) {
            if (method.GetIdentifierWithoutPrefix() == funcDecl.mangledName) {
                if (let Some(instFuncs) <- genericFuncMap.Get(funcDecl)) {
                    AddMemberFunctionGenericInstantiations(classDef, instFuncs, funcDecl)
                }
                return true
            }
        }
        return false
    }

    private func AddMemberFunctionGenericInstantiations(def: CustomTypeDef, instFuncs: ArrayList<AstFuncDecl>,
        originalDecl: AstFuncDecl): Unit {
        let originalOuterDecl = originalDecl.outerDecl.getOrThrow()
        for (instFunc in instFuncs) {
            CJC_ASSERT(instFunc.outerDecl.getOrThrow() == originalOuterDecl)
            AddMethodIfPresent(def, instFunc)
            AddDefaultParamMethods(def, instFunc)
        }
    }

    private func AddExtendMethodAndDefaultParamMethods(def: ExtendDef, funcDecl: AstFuncDecl): Unit {
        AddMethodIfPresent(def, funcDecl)
        let body = match (funcDecl.funcBody) {
            case Some(value) => value
            case None =>
                AddExtendGenericFuncInstantiations(def, funcDecl, funcDecl)
                return
        }
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                if (let Some(desugarDecl) <- param.desugarDecl) {
                    AddMethodIfPresent(def, desugarDecl)
                    AddExtendGenericFuncInstantiations(def, desugarDecl, funcDecl)
                }
            }
        }
        AddExtendGenericFuncInstantiations(def, funcDecl, funcDecl)
    }

    private func AddExtendGenericFuncInstantiations(def: ExtendDef, genericFunc: AstFuncDecl,
        originalDecl: AstFuncDecl): Unit {
        let originalOuterDecl = originalDecl.outerDecl.getOrThrow()
        if (let Some(instFuncs) <- genericFuncMap.Get(genericFunc)) {
            for (instFunc in instFuncs) {
                CJC_ASSERT(instFunc.outerDecl.getOrThrow() == originalOuterDecl)
                AddMethodIfPresent(def, instFunc)
            }
        }
    }

    private func AddPropertyAccessors(def: CustomTypeDef, propDecl: AstPropDecl): Unit {
        if (let Some(classDef) <- (def as ClassDef)) {
            for (getter in propDecl.getters) {
                TranslateClassLikeMemberFuncDecl(classDef, getter)
            }
            for (setter in propDecl.setters) {
                TranslateClassLikeMemberFuncDecl(classDef, setter)
            }
        } else {
            for (getter in propDecl.getters) {
                AddMethodIfPresent(def, getter)
            }
            for (setter in propDecl.setters) {
                AddMethodIfPresent(def, setter)
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
        memberInfo.attributeInfo = BuildVarDeclAttr(decl)
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

    private func BindLambdaParams(funcBody: AstFuncBody, lambda: Lambda, funcTy: FuncType): Unit {
        if (funcBody.paramLists.isEmpty()) {
            return
        }
        let params = funcBody.paramLists[0].params
        let paramTys = funcTy.GetParamTypes()
        var idx: Int64 = 0
        for (param in params) {
            if (idx < paramTys.size) {
                let chirParam = builder.CreateParameter(paramTys[idx],
                    TranslateLocationWithoutScope(builder.context, param.begin, param.end), lambda)
                chirParam.SetSrcCodeIdentifier(param.identifier.GetRawText())
                localValSymbolTable.Set(param, chirParam)
            }
            idx++
        }
    }

    private func CreateLambdaParamDebugs(funcBody: AstFuncBody, lambda: Lambda, entry: Block,
        hasInitial!: Bool = false): Unit {
        if (funcBody.paramLists.isEmpty()) {
            return
        }
        let params = funcBody.paramLists[0].params
        let offset: Int64 = if (params.size < lambda.GetNumOfParams()) { 1 } else { 0 }
        CJC_ASSERT(params.size + offset == lambda.GetNumOfParams())
        var idx: Int64 = 0
        for (param in params) {
            let debugInfo = builder.CreateDebug(builder.context.GetUnitTy(), lambda.GetParam(idx + offset),
                param.identifier.GetRawText(), entry)
            debugInfo.SetDebugLocation(TranslateLocationWithoutScope(builder.context, param.begin, param.end))
            debugInfo.SetDebugLocationInfoForWarning(GetDeclLoc(builder.context, param))
            if (hasInitial) {
                debugInfo.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
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
        let forInRetValLocation = GenerateForInRetValLocation()
        let inductiveVar = Translator.TranslateASTNode(inExpression.body[0], this) ??
            throw IllegalStateException("faithful AST2CHIR for-in range induction var produced no value")
        inductiveVar.AsLocalVar().getOrThrow().GetExpr().getOrThrow().SetGeneratedFromForIn(true)
        let stopExprVar = Translator.TranslateASTNode(inExpression.body[1], this) ??
            throw IllegalStateException("faithful AST2CHIR for-in range stop var produced no value")
        if (let Some(stopLocalVar) <- stopExprVar.AsLocalVar()) {
            stopLocalVar.GetExpr().getOrThrow().SetGeneratedFromForIn(true)
        }
        let condition = Translator.TranslateASTNode(inExpression.body[3], this) ??
            throw IllegalStateException("faithful AST2CHIR for-in range condition produced no value")
        condition.AsLocalVar().getOrThrow().GetExpr().getOrThrow().SetGeneratedFromForIn(true)
        let recordBlock = CurrentBlock()
        let parentGroup = RequireParentBlockGroup(recordBlock, "for-in range")
        let forInEntryBlock = builder.CreateBlock(parentGroup)
        currentBlock = forInEntryBlock
        let condVar = InitializeForInCondVar()
        InitializeDelayExitSignal()
        let forIn = InitForInExprSkeleton(expr, inductiveVar, condVar, isIter: false)
        if (let Some(retValLocation) <- forInRetValLocation) {
            forInExprReturnMap[RequireResult(forIn)] = retValLocation
        }

        TranslateForInRangeBody(expr, forIn)
        TranslateForInRangeLatch(inExpression.body[2], forIn)
        TranslateForInRangeCond(inExpression.body[3], inductiveVar, stopExprVar, condVar, forIn)

        let endBlock = builder.CreateBlock(parentGroup)
        builder.CreateGoTo(endBlock, forInEntryBlock)
        currentBlock = endBlock
        UpdateDelayExitSignalInForInEnd(forIn)
        let rangeEndBranch = builder.CreateBranch(condition, forInEntryBlock, CurrentBlock(), recordBlock)
        rangeEndBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
        CurrentBlock().SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        return None
    }

    private func TranslateForInString(expr: AstForInExpr): Option<Value> {
        let inExpression = RequireBlockExpr(expr.inExpression, "for-in string inExpression")
        if (inExpression.body.size < 3) {
            throw IllegalStateException("faithful AST2CHIR string ForInExpr expects desugared block with 3 nodes")
        }
        let forInExprBlock = CurrentBlock()
        let forInRetValLocation = GenerateForInRetValLocation()
        let _ = Translator.TranslateASTNode(inExpression, this)
        builder.CreateGoTo(GetBlockByAST(inExpression), forInExprBlock)
        let indexDecl = RequireBodyVarDecl(inExpression, 0, "for-in string induction var")
        let endDecl = RequireBodyVarDecl(inExpression, 2, "for-in string end var")
        let inductiveVar = GetSymbolTable(indexDecl)
        inductiveVar.AsLocalVar().getOrThrow().GetExpr().getOrThrow().SetGeneratedFromForIn(true)
        let stringSize = GetDerefedValue(GetSymbolTable(endDecl))
        let conditionExpr = builder.CreateBinaryExpression(ExprKind.LT, builder.context.GetBoolTy(),
            GetDerefedValue(inductiveVar), stringSize, CurrentBlock())
        conditionExpr.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        conditionExpr.SetGeneratedFromForIn(true)
        let condition = RequireResult(conditionExpr)
        let recordBlock = CurrentBlock()
        let parentGroup = RequireParentBlockGroup(recordBlock, "for-in string")
        let forInEntryBlock = builder.CreateBlock(parentGroup)
        currentBlock = forInEntryBlock
        let condVar = InitializeForInCondVar()
        InitializeDelayExitSignal()
        let forIn = InitForInExprSkeleton(expr, inductiveVar, condVar, isIter: false)
        if (let Some(retValLocation) <- forInRetValLocation) {
            forInExprReturnMap[RequireResult(forIn)] = retValLocation
        }

        TranslateForInStringBody(expr, forIn)
        TranslateForInStringLatch(inductiveVar, forIn)
        TranslateForInStringCond(inductiveVar, stringSize, condVar, forIn)

        let endBlock = builder.CreateBlock(parentGroup)
        builder.CreateGoTo(endBlock, forInEntryBlock)
        currentBlock = endBlock
        UpdateDelayExitSignalInForInEnd(forIn)
        let stringEndBranch = builder.CreateBranch(condition, forInEntryBlock, CurrentBlock(), recordBlock)
        stringEndBranch.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        stringEndBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
        return None
    }

    private func TranslateForInInvalid(expr: AstForInExpr): Option<Value> {
        if (IsClosedRangeOne(expr)) {
            return TranslateForInClosedRangeOne(expr)
        }
        throw IllegalArgumentException("faithful AST2CHIR unsupported ForInExpr kind FORIN_INVALID")
    }

    private func TranslateForInIter(expr: AstForInExpr): Option<Value> {
        let inExpression = RequireBlockExpr(expr.inExpression, "for-in iterator inExpression")
        if (inExpression.body.size < 2) {
            throw IllegalStateException("faithful AST2CHIR iterator ForInExpr expects desugared block with 2 nodes")
        }
        let forInRetValLocation = GenerateForInRetValLocation()
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
        if (let Some(retValLocation) <- forInRetValLocation) {
            forInExprReturnMap[RequireResult(forIn)] = retValLocation
        }

        TranslateForInIterBody(expr, iterNextLocation, forIn)
        TranslateForInIterLatch(matchExpr, iterNextLocation, forIn)
        TranslateForInIterCond(matchExpr, iterNextLocation, condVar, forIn)

        let endBlock = builder.CreateBlock(parentGroup)
        builder.CreateGoTo(endBlock, forInEntryBlock)
        currentBlock = endBlock
        UpdateDelayExitSignalInForInEnd(forIn)
        builder.CreateGoTo(forInEntryBlock, recordBlock)
        return None
    }

    private func TranslateForInClosedRangeOne(expr: AstForInExpr): Option<Value> {
        let beginValue = TranslateClosedRangeBound(expr, 0)
        let endValue = TranslateClosedRangeBound(expr, 1)
        let isIncrement = IsClosedRangeIncrement(expr)
        let preCondKind = if (isIncrement) { ExprKind.LE } else { ExprKind.GE }
        let preCond = RequireResult(builder.CreateBinaryExpression(preCondKind, builder.context.GetBoolTy(),
            beginValue, endValue, CurrentBlock()))
        let parentGroup = RequireParentBlockGroup(CurrentBlock(), "for-in closed range")
        let preCondTrueBlock = builder.CreateBlock(parentGroup)
        let preCondFalseBlock = builder.CreateBlock(parentGroup)
        preCondFalseBlock.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        let preCondBranch = builder.CreateBranch(preCond, preCondTrueBlock, preCondFalseBlock, CurrentBlock())
        preCondBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)

        currentBlock = preCondTrueBlock
        let iterVar = CreateClosedRangeIterVar(expr, beginValue)
        let forInEntryBlock = builder.CreateBlock(parentGroup)
        builder.CreateGoTo(forInEntryBlock, CurrentBlock())

        currentBlock = forInEntryBlock
        let condVar = InitializeForInCondVar()
        InitializeDelayExitSignal()
        let forInRetValLocation = GenerateForInRetValLocation()
        let forIn = InitForInClosedRangeExprSkeleton(expr, iterVar, condVar)
        if (let Some(retValLocation) <- forInRetValLocation) {
            forInExprReturnMap[RequireResult(forIn)] = retValLocation
        }

        let iterValue = TranslateForInClosedRangeBody(expr, iterVar, forIn)
        TranslateForInClosedRangeCond(expr, iterValue, endValue, condVar, forIn)
        TranslateForInClosedRangeLatch(iterVar, iterValue, isIncrement, condVar, forIn)

        let endBlock = builder.CreateBlock(parentGroup)
        builder.CreateGoTo(endBlock, forInEntryBlock)
        currentBlock = endBlock
        UpdateDelayExitSignalInForInEnd(forIn)
        builder.CreateGoTo(preCondFalseBlock, CurrentBlock())
        currentBlock = preCondFalseBlock
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
        let condEntryBlock = builder.CreateBlock(condBlockGroup)
        condBlockGroup.SetEntryBlock(condEntryBlock)
        return forIn
    }

    private func InitForInClosedRangeExprSkeleton(expr: AstForInExpr, inductiveVar: Value,
        condVar: Value): ForInClosedRange {
        let parentFunc = CurrentFunction()
        let bodyBlockGroup = builder.CreateBlockGroup(parentFunc)
        let latchBlockGroup = builder.CreateBlockGroup(parentFunc)
        let condBlockGroup = builder.CreateBlockGroup(parentFunc)
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let forIn = builder.CreateForInClosedRange(resultTy, inductiveVar, condVar, CurrentBlock())
        forIn.InitBlockGroups(bodyBlockGroup, latchBlockGroup, condBlockGroup)
        bodyBlockGroup.SetEntryBlock(builder.CreateBlock(bodyBlockGroup))
        latchBlockGroup.SetEntryBlock(builder.CreateBlock(latchBlockGroup))
        let condEntryBlock = builder.CreateBlock(condBlockGroup)
        condEntryBlock.SetGeneratedFromForIn(true)
        condBlockGroup.SetEntryBlock(condEntryBlock)
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

    private func ForInPatternVarDecl(pattern: AstPattern): Option<AstVarDecl> {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            return varPattern.varDecl
        }
        if (let Some(varOrEnum) <- (pattern as AstVarOrEnumPattern)) {
            if (let Some(realPattern) <- varOrEnum.pattern) {
                return ForInPatternVarDecl(realPattern)
            }
        }
        return None
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

    private func TranslateForInStringBody(expr: AstForInExpr, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetBody())
        currentBlock = forIn.GetBody().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in string body has no entry block")
        if (let Some(pattern) <- expr.pattern) {
            TranslateForInRangePatternDecl(pattern)
        }
        TranslateForInBodyBlockGroup(expr)
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInClosedRangeBody(expr: AstForInExpr, iterVar: Value, forIn: ForIn): Value {
        blockGroupStack.add(forIn.GetBody())
        currentBlock = forIn.GetBody().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in closed range body has no entry block")
        let iterValue = RequireResult(builder.CreateLoad(RequireRefBaseType(iterVar), iterVar, CurrentBlock()))
        if (let Some(pattern) <- expr.pattern) {
            if (let Some(varDecl) <- ForInPatternVarDecl(pattern)) {
                localValSymbolTable.Set(varDecl, iterValue)
            }
        }
        TranslateForInBodyBlockGroup(expr)
        if (let Some(pattern) <- expr.pattern) {
            if (let Some(varPattern) <- (pattern as AstVarPattern)) {
                localValSymbolTable.Erase(varPattern.varDecl.getOrThrow())
            }
        }
        blockGroupStack.remove(at: blockGroupStack.size - 1)
        return iterValue
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
            let prevBlock = CurrentBlock()
            let _ = Translator.TranslateASTNode(body, this)
            if (prevBlock.GetTerminator().isNone()) {
                builder.CreateGoTo(GetBlockByAST(body), prevBlock)
            }
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
        let delayExitBranch = builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock,
            CurrentBlock())
        delayExitBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
        currentBlock = trueBlock
        builder.CreateExit(None, CurrentBlock())
        currentBlock = falseBlock
        let _ = Translator.TranslateASTNode(updateNode, this)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateExit(None, CurrentBlock())
        }
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInStringLatch(inductiveVar: Value, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetLatch())
        currentBlock = forIn.GetLatch().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in string latch has no entry block")
        let trueBlock = builder.CreateBlock(forIn.GetLatch())
        let falseBlock = builder.CreateBlock(forIn.GetLatch())
        let delayExitBranch = builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock,
            CurrentBlock())
        delayExitBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
        currentBlock = trueBlock
        builder.CreateExit(None, CurrentBlock())
        currentBlock = falseBlock
        let inductiveValue = GetDerefedValue(inductiveVar)
        let inductiveTy = inductiveValue.GetType() ?? RequireRefBaseType(inductiveVar)
        let oneExpr = builder.CreateConstant(inductiveTy, IntLiteral(1), CurrentBlock())
        oneExpr.SetGeneratedFromForIn(true)
        let one = RequireResult(oneExpr)
        let plusOneExpr = builder.CreateBinaryExpression(ExprKind.ADD, inductiveTy, inductiveValue, one,
            CurrentBlock())
        plusOneExpr.SetGeneratedFromForIn(true)
        let plusOne = RequireResult(plusOneExpr)
        builder.CreateStore(plusOne, inductiveVar, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInClosedRangeLatch(iterVar: Value, iterValue: Value, isIncrement: Bool,
        condVar: Value, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetLatch())
        currentBlock = forIn.GetLatch().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in closed range latch has no entry block")
        let trueBlock = builder.CreateBlock(forIn.GetLatch())
        let falseBlock = builder.CreateBlock(forIn.GetLatch())
        let delayExitBranch = builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock,
            CurrentBlock())
        delayExitBranch.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        delayExitBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
        currentBlock = trueBlock
        let delayExit = builder.CreateExit(None, CurrentBlock())
        delayExit.SetSkipCheck(SkipKind.SKIP_FORIN_EXIT)
        currentBlock = falseBlock
        let updateBlock = builder.CreateBlock(forIn.GetLatch())
        let exitBlock = builder.CreateBlock(forIn.GetLatch())
        let condValue = RequireResult(builder.CreateLoad(builder.context.GetBoolTy(), condVar, CurrentBlock()))
        let condBranch = builder.CreateBranch(condValue, updateBlock, exitBlock, CurrentBlock())
        updateBlock.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        condBranch.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        condBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
        currentBlock = updateBlock
        let iterTy = iterValue.GetType() ?? RequireRefBaseType(iterVar)
        let one = RequireResult(builder.CreateConstant(iterTy, IntLiteral(1), CurrentBlock()))
        let op = if (isIncrement) { ExprKind.ADD } else { ExprKind.SUB }
        let newValue = RequireResult(builder.CreateBinaryExpression(op, iterTy, iterValue, one, CurrentBlock()))
        builder.CreateStore(newValue, iterVar, CurrentBlock())
        builder.CreateGoTo(exitBlock, CurrentBlock())
        currentBlock = exitBlock
        builder.CreateExit(None, CurrentBlock())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInIterLatch(matchExpr: AstMatchExpr, iterNextLocation: Value, forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetLatch())
        currentBlock = forIn.GetLatch().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in iterator latch has no entry block")
        let trueBlock = builder.CreateBlock(forIn.GetLatch())
        let falseBlock = builder.CreateBlock(forIn.GetLatch())
        let delayExitBranch = builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock,
            CurrentBlock())
        delayExitBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
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

    private func TranslateForInStringCond(inductiveVar: Value, stringSize: Value, condVar: Value,
        forIn: ForIn): Unit {
        blockGroupStack.add(forIn.GetCond())
        currentBlock = forIn.GetCond().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in string cond has no entry block")
        TranslateForInCondControlFlow(condVar)
        let condition = RequireResult(builder.CreateBinaryExpression(ExprKind.LT, builder.context.GetBoolTy(),
            GetDerefedValue(inductiveVar), stringSize, CurrentBlock()))
        builder.CreateStore(condition, condVar, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInClosedRangeCond(expr: AstForInExpr, iterValue: Value, iterEnd: Value,
        condVar: Value, forIn: ForIn): Unit {
        let _ = expr
        blockGroupStack.add(forIn.GetCond())
        currentBlock = forIn.GetCond().GetEntryBlock() ??
            throw IllegalStateException("faithful AST2CHIR for-in closed range cond has no entry block")
        TranslateForInCondControlFlow(condVar)
        let condition = RequireResult(builder.CreateBinaryExpression(ExprKind.NOTEQUAL, builder.context.GetBoolTy(),
            iterValue, iterEnd, CurrentBlock()))
        builder.CreateStore(condition, condVar, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        blockGroupStack.remove(at: blockGroupStack.size - 1)
    }

    private func TranslateForInCondControlFlow(condVar: Value): Unit {
        let trueBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "for-in cond control"))
        let falseBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "for-in cond control"))
        let delayExitBranch = builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock,
            CurrentBlock())
        delayExitBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
        currentBlock = trueBlock
        DecreaseDelayExitSignal()
        let constantFalseExpr = builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(false), CurrentBlock())
        constantFalseExpr.SetGeneratedFromForIn(true)
        let constantFalse = RequireResult(constantFalseExpr)
        builder.CreateStore(constantFalse, condVar, CurrentBlock())
        builder.CreateExit(None, CurrentBlock())
        currentBlock = falseBlock
    }

    private func UpdateDelayExitSignalInForInEnd(forIn: ForIn): Unit {
        let parentGroup = RequireParentBlockGroup(CurrentBlock(), "for-in end")
        let trueBlock = builder.CreateBlock(parentGroup)
        let falseBlock = builder.CreateBlock(parentGroup)
        let delayExitBranch = builder.CreateBranch(DelayExitSignalGreaterThanZero(), trueBlock, falseBlock,
            CurrentBlock())
        delayExitBranch.SetSourceExpr(SourceExpr.FOR_IN_EXPR)
        currentBlock = trueBlock
        DecreaseDelayExitSignal()
        RestoreForInRetValIfNeeded(forIn)
        if (!tryCatchContext.isEmpty()) {
            GenerateSignalCheckForThrow()
        }
        let forInExit = builder.CreateExit(None, CurrentBlock())
        forInExit.SetSkipCheck(SkipKind.SKIP_FORIN_EXIT)
        currentBlock = falseBlock
    }

    private func GenerateSignalCheckForThrow(): Unit {
        let constZeroExpr = builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(0), CurrentBlock())
        constZeroExpr.SetGeneratedFromForIn(true)
        let constZero = RequireResult(constZeroExpr)
        let signalLoad = builder.CreateLoad(builder.context.GetInt64Ty(), RequireDelayExitSignal(), CurrentBlock())
        signalLoad.SetGeneratedFromForIn(true)
        let signalValue = RequireResult(signalLoad)
        let hasThrow = RequireResult(builder.CreateBinaryExpression(ExprKind.GT, builder.context.GetBoolTy(),
            signalValue, constZero, CurrentBlock()))
        let parentGroup = RequireParentBlockGroup(CurrentBlock(), "for-in throw signal")
        let throwBlock = builder.CreateBlock(parentGroup)
        let exceptionTy = BaseExceptionObjectType()
        let exception = RequireResult(builder.CreateGetException(exceptionTy, throwBlock))
        let beginCatchArgs = ArrayList<Value>()
        beginCatchArgs.add(exception)
        let beginCatch = RequireResult(builder.CreateIntrinsic(exceptionTy,
            IntrisicCallContext(kind: IntrinsicKind.BEGIN_CATCH, args: beginCatchArgs), throwBlock))
        builder.CreateRaiseException(beginCatch, tryCatchContext[tryCatchContext.size - 1], throwBlock)
        let returnBlock = builder.CreateBlock(parentGroup)
        let branch = builder.CreateBranch(hasThrow, throwBlock, returnBlock, CurrentBlock())
        branch.SetGeneratedFromForIn(true)
        currentBlock = returnBlock
    }

    private func InitializeForInCondVar(): Value {
        let condVarExpr = builder.CreateAllocate(builder.context.GetRefTy(builder.context.GetBoolTy()),
            builder.context.GetBoolTy(), CurrentBlock())
        condVarExpr.SetGeneratedFromForIn(true)
        let condVar = RequireResult(condVarExpr)
        let constantTrueExpr = builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(true), CurrentBlock())
        constantTrueExpr.SetGeneratedFromForIn(true)
        let constantTrue = RequireResult(constantTrueExpr)
        builder.CreateStore(constantTrue, condVar, CurrentBlock())
        return condVar
    }

    private func InitializeDelayExitSignal(): Unit {
        if (delayExitSignal.isSome()) {
            return
        }
        let signalExpr = builder.CreateAllocate(builder.context.GetRefTy(builder.context.GetInt64Ty()),
            builder.context.GetInt64Ty(), CurrentBlock())
        signalExpr.SetGeneratedFromForIn(true)
        let signal = RequireResult(signalExpr)
        delayExitSignal = signal
        let zero = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(0), CurrentBlock()))
        builder.CreateStore(zero, signal, CurrentBlock())
    }

    private func DelayExitSignalGreaterThanZero(): Value {
        let signalLoad = builder.CreateLoad(builder.context.GetInt64Ty(), RequireDelayExitSignal(), CurrentBlock())
        signalLoad.SetGeneratedFromForIn(true)
        let signalValue = RequireResult(signalLoad)
        let zero = RequireResult(builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(0), CurrentBlock()))
        let isNeedExit = builder.CreateBinaryExpression(ExprKind.GT, builder.context.GetBoolTy(), signalValue, zero,
            CurrentBlock())
        isNeedExit.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        isNeedExit.SetGeneratedFromForIn(true)
        return RequireResult(isNeedExit)
    }

    private func DecreaseDelayExitSignal(): Unit {
        let signal = RequireDelayExitSignal()
        let signalLoad = builder.CreateLoad(builder.context.GetInt64Ty(), signal, CurrentBlock())
        signalLoad.SetGeneratedFromForIn(true)
        let signalValue = RequireResult(signalLoad)
        let oneExpr = builder.CreateConstant(builder.context.GetInt64Ty(), IntLiteral(1), CurrentBlock())
        oneExpr.SetGeneratedFromForIn(true)
        let one = RequireResult(oneExpr)
        let decreasedExpr = builder.CreateBinaryExpression(ExprKind.SUB, builder.context.GetInt64Ty(), signalValue,
            one, CurrentBlock())
        decreasedExpr.SetGeneratedFromForIn(true)
        let decreased = RequireResult(decreasedExpr)
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

    private func PushFinallyContext(expr: AstTryExpr, normalEndBlock: Block, finalEndBlock: Block): Unit {
        let context = FaithfulFinallyControlContext(expr)
        context.Add(FaithfulFinallyControlType.NORMAL, normalEndBlock, finalEndBlock, expr.scopeLevel)
        finallyContext.add(context)
    }

    private func PopFinallyContext(): FaithfulFinallyControlContext {
        if (finallyContext.isEmpty()) {
            throw IllegalStateException("faithful AST2CHIR finally context stack is empty")
        }
        let out = finallyContext[finallyContext.size - 1]
        finallyContext.remove(at: finallyContext.size - 1)
        return out
    }

    private func CurrentFinallyContext(): FaithfulFinallyControlContext {
        if (finallyContext.isEmpty()) {
            throw IllegalStateException("faithful AST2CHIR finally context stack is empty")
        }
        return finallyContext[finallyContext.size - 1]
    }

    private func RecordFinallyControlIfNeeded(kind: FaithfulFinallyControlType,
        controlScopeLevel!: UInt32 = 0u32): Unit {
        if (finallyContext.isEmpty()) {
            return
        }
        let prevBlock = CurrentBlock()
        let group = RequireParentBlockGroup(prevBlock, "finally control target")
        let nextBlock = builder.CreateBlock(group)
        currentBlock = nextBlock
        CurrentFinallyContext().Add(kind, prevBlock, nextBlock, controlScopeLevel)
    }

    private func ShouldRecordJumpForFinally(refLoop: AstNode): Bool {
        if (finallyContext.isEmpty()) {
            return false
        }
        return refLoop.scopeLevel < CurrentFinallyContext().tryScopeLevel
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

    private func CalculateDelayExitLevelForThrow(): Int64 {
        return CalculateDelayExitLevelForReturn() + 1
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
                if ((owner as Lambda).isSome()) {
                    break
                }
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

    private func RequireBodyVarDecl(block: AstBlock, index: Int64, context: String): AstVarDecl {
        if (index < 0 || index >= block.body.size) {
            throw IllegalStateException("faithful AST2CHIR ${context} missing from desugared block")
        }
        return (block.body[index] as AstVarDecl) ??
            throw IllegalStateException("faithful AST2CHIR ${context} is not a VarDecl")
    }

    private func IsClosedRangeOne(expr: AstForInExpr): Bool {
        let inExpr = expr.inExpression ?? return false
        if (let Some(rangeExpr) <- (inExpr as AstRangeExpr)) {
            if (let Some(desugar) <- rangeExpr.desugarExpr) {
                if (let Some(callExpr) <- (desugar as AstCallExpr)) {
                    return IsCallRangeConstructor(callExpr)
                }
                return false
            }
            return rangeExpr.isClosed && IsRangeStepOne(rangeExpr)
        }
        if (let Some(callExpr) <- (inExpr as AstCallExpr)) {
            return IsCallRangeConstructor(callExpr)
        }
        return false
    }

    private func ClosedRangeCallExpr(expr: AstExpr): Option<AstCallExpr> {
        if (let Some(callExpr) <- (expr as AstCallExpr)) {
            return Some(callExpr)
        }
        if (let Some(rangeExpr) <- (expr as AstRangeExpr)) {
            if (let Some(desugar) <- rangeExpr.desugarExpr) {
                if (let Some(callExpr) <- (desugar as AstCallExpr)) {
                    return Some(callExpr)
                }
            }
        }
        return None
    }

    private func IsCallRangeConstructor(callExpr: AstCallExpr): Bool {
        let rangeConstructorParamSize: Int64 = 6
        let rangeConstructorIntLength: Int64 = 3
        if (callExpr.callKind != AstCallKind.CALL_OBJECT_CREATION) {
            return false
        }
        let callee = (callExpr.baseFunc ?? return false) as AstRefExpr
        let calledFunc = ((callee ?? return false).ref.target ?? return false) as AstFuncDecl
        let funcBody = (calledFunc ?? return false).funcBody ?? return false
        if (funcBody.paramLists.isEmpty() || funcBody.paramLists[0].params.size != rangeConstructorParamSize) {
            return false
        }
        if (callExpr.args.size != rangeConstructorParamSize) {
            return false
        }
        var idx: Int64 = 0
        while (idx < rangeConstructorIntLength) {
            let argTy = callExpr.args[idx].GetTy() ?? return false
            if (!argTy.IsInteger()) {
                return false
            }
            idx++
        }
        let stepExpr = callExpr.args[rangeConstructorIntLength - 1].expr ?? return false
        let stepLit = (stepExpr as AstLitConstExpr) ?? return false
        let stepValue = stepLit.constNumValue.asInt.`Int64`()
        if (stepValue != 1 && stepValue != -1) {
            return false
        }
        idx = rangeConstructorIntLength
        while (idx < rangeConstructorParamSize) {
            let argTy = callExpr.args[idx].GetTy() ?? return false
            if (!argTy.IsBoolean()) {
                return false
            }
            idx++
        }
        let isClosedExpr = callExpr.args[rangeConstructorParamSize - 1].expr ?? return false
        let isClosedLit = (isClosedExpr as AstLitConstExpr) ?? return false
        return isClosedLit.constNumValue.asBoolean
    }

    private func IsRangeStepOne(rangeExpr: AstRangeExpr): Bool {
        if (let Some(startExpr) <- rangeExpr.startExpr) {
            let startTy = startExpr.GetTy() ?? return false
            if (startTy.IsInvalid() || !startTy.IsInteger()) {
                return false
            }
        } else {
            return false
        }
        if (let Some(stopExpr) <- rangeExpr.stopExpr) {
            let stopTy = stopExpr.GetTy() ?? return false
            if (stopTy.IsInvalid() || !stopTy.IsInteger()) {
                return false
            }
        } else {
            return false
        }
        if (let Some(stepExpr) <- rangeExpr.stepExpr) {
            if (!stepExpr.isConst) {
                return false
            }
            let stepValue = stepExpr.constNumValue.asInt.`Int64`()
            return stepValue == 1 || stepValue == -1
        }
        return true
    }

    private func TranslateClosedRangeBound(expr: AstForInExpr, argIndex: Int64): Value {
        let inExpr = RequireExpr(expr.inExpression, "for-in closed range inExpression")
        let boundExpr = ClosedRangeBoundExpr(inExpr, argIndex)
        let value = Translator.TranslateASTNode(boundExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR closed range bound produced no value")
        return GetDerefedValue(value)
    }

    private func ClosedRangeBoundExpr(inExpr: AstExpr, argIndex: Int64): AstExpr {
        if (let Some(callExpr) <- ClosedRangeCallExpr(inExpr)) {
            if (argIndex < 0 || argIndex >= callExpr.args.size) {
                throw IllegalStateException("faithful AST2CHIR closed range constructor bound missing")
            }
            return RequireFuncArgExpr(callExpr.args[argIndex], "closed range constructor bound")
        }
        let rangeExpr = (inExpr as AstRangeExpr) ??
            throw IllegalStateException("faithful AST2CHIR closed range inExpression is not a RangeExpr")
        if (argIndex == 0) {
            return RequireExpr(rangeExpr.startExpr, "closed range start")
        }
        if (argIndex == 1) {
            return RequireExpr(rangeExpr.stopExpr, "closed range stop")
        }
        throw IllegalStateException("faithful AST2CHIR closed range bound index out of range")
    }

    private func IsClosedRangeIncrement(expr: AstForInExpr): Bool {
        return ClosedRangeStepValue(expr) == 1
    }

    private func ClosedRangeStepValue(expr: AstForInExpr): Int64 {
        let inExpr = RequireExpr(expr.inExpression, "for-in closed range inExpression")
        if (let Some(callExpr) <- ClosedRangeCallExpr(inExpr)) {
            let stepExpr = RequireFuncArgExpr(callExpr.args[2], "closed range constructor step")
            let stepLit = (stepExpr as AstLitConstExpr) ??
                throw IllegalStateException("faithful AST2CHIR closed range constructor step is not a literal")
            return stepLit.constNumValue.asInt.`Int64`()
        }
        let rangeExpr = (inExpr as AstRangeExpr) ??
            throw IllegalStateException("faithful AST2CHIR closed range inExpression is not a RangeExpr")
        if (let Some(stepExpr) <- rangeExpr.stepExpr) {
            return stepExpr.constNumValue.asInt.`Int64`()
        }
        return 1
    }

    private func CreateClosedRangeIterVar(expr: AstForInExpr, beginValue: Value): Value {
        let _ = expr
        let iterTy = beginValue.GetType() ??
            throw IllegalStateException("faithful AST2CHIR closed range begin value has no type")
        let iterVarExpr = builder.CreateAllocate(builder.context.GetRefTy(iterTy), iterTy, CurrentBlock())
        iterVarExpr.SetGeneratedFromForIn(true)
        let iterVar = RequireResult(iterVarExpr)
        builder.CreateStore(beginValue, iterVar, CurrentBlock())
        return iterVar
    }

    private func GenerateForInRetValLocation(): Option<Value> {
        let funcRetValLocation = GetOuterBlockGroupReturnValLocation() ?? return None
        let forInType = RequireRefBaseType(funcRetValLocation)
        if (forInType.IsNothing() || forInType.IsUnit()) {
            return None
        }
        let retValExpr = builder.CreateAllocate(builder.context.GetRefTy(forInType), forInType, CurrentBlock())
        retValExpr.SetGeneratedFromForIn(true)
        let retValLocation = RequireResult(retValExpr)
        let nullVal = RequireResult(builder.CreateConstant(forInType, NullLiteral(), CurrentBlock()))
        builder.CreateStore(nullVal, retValLocation, CurrentBlock())
        return Some(retValLocation)
    }

    private func GetOuterBlockGroupReturnValLocation(): Option<Value> {
        var idx = blockGroupStack.size - 1
        while (idx >= 0) {
            let group = blockGroupStack[idx]
            if (let Some(owner) <- group.GetOwnerExpression()) {
                if (let Some(forIn) <- (owner as ForIn)) {
                    let forInResult = RequireResult(forIn)
                    if (forInExprReturnMap.contains(forInResult)) {
                        return Some(forInExprReturnMap[forInResult])
                    }
                }
            }
            idx--
        }
        if (blockGroupStack.isEmpty()) {
            return None
        }
        let group = blockGroupStack[blockGroupStack.size - 1]
        if (let Some(fn) <- group.GetOwnerFunc()) {
            if (let Some(returnValue) <- fn.GetReturnValue()) {
                return Some(returnValue)
            }
            return None
        }
        if (let Some(owner) <- group.GetOwnerExpression()) {
            if (let Some(lambda) <- (owner as Lambda)) {
                if (let Some(returnValue) <- lambda.GetReturnValue()) {
                    return Some(returnValue)
                }
                return None
            }
        }
        return None
    }

    private func StoreReturnExprValueIfNeeded(expr: AstReturnExpr, value: Value): Unit {
        if (let Some(returnLocation) <- GetOuterBlockGroupReturnValLocation()) {
            if (expr.TestAttr(AstAttribute.COMPILER_ADD)) {
                CreateAndAppendWrappedStore(value, returnLocation)
            } else {
                CreateAndAppendWrappedStore(value, returnLocation, TranslateLocation(expr))
            }
        }
    }

    private func RestoreForInRetValIfNeeded(forIn: ForIn): Unit {
        let funcRetValLocation = GetOuterBlockGroupReturnValLocation() ?? return
        let forInResult = RequireResult(forIn)
        if (!forInExprReturnMap.contains(forInResult)) {
            return
        }
        let forInRetValLocation = forInExprReturnMap[forInResult]
        let forInRetVal = RequireResult(builder.CreateLoad(RequireRefBaseType(forInRetValLocation),
            forInRetValLocation, CurrentBlock()))
        builder.CreateStore(CastValueIfNeeded(forInRetVal, RequireRefBaseType(funcRetValLocation)),
            funcRetValLocation, CurrentBlock())
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
                builder.CreateStore(CastValueIfNeeded(result, RequireRefBaseType(loc)), loc, CurrentBlock())
            }
        }
    }

    private func StoreTryResult(location: Option<Value>, value: Option<Value>, debugLoc: DebugLocation): Unit {
        if (let Some(resultLoc) <- location) {
            if (let Some(result) <- value) {
                CreateAndAppendWrappedStore(GetDerefedValue(result, debugLoc), resultLoc, debugLoc)
            }
        }
    }

    private func HasNothingTypeArg(args: ArrayList<Value>): Bool {
        for (arg in args) {
            if ((arg.GetType() ?? throw IllegalStateException("faithful AST2CHIR call argument has no type")).IsNothing()) {
                return true
            }
        }
        return false
    }

    private func HasTypeOfNothing(expr: AstTryExpr): Bool {
        if (!RequireAstTy(RequireBlock(expr.tryBlock, "try block")).IsNothing()) {
            return false
        }
        for (catchBlock in expr.catchBlocks) {
            if (!RequireAstTy(catchBlock).IsNothing()) {
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
        if (expr.catchBlocks.size != expr.catchPatterns.size) {
            throw IllegalStateException("faithful AST2CHIR catch block/pattern count mismatch")
        }
        var idx: Int64 = 0
        while (idx < expr.catchPatterns.size) {
            let (falseBlock, trueBlock) = TranslateExceptionPattern(expr.catchPatterns[idx], beginCatch)
            currentBlock = trueBlock
            BindExceptionPatternValues(expr.catchPatterns[idx], beginCatch)
            let catchBlock = expr.catchBlocks[idx]
            let catchValue = Translator.TranslateASTNode(catchBlock, this)
            if (trueBlock.GetTerminator().isNone()) {
                builder.CreateGoTo(GetBlockByAST(catchBlock), trueBlock)
            }
            StoreTryResult(resultLoc, catchValue, TranslateLocation(catchBlock))
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

    private func TranslateFinally(finallyBlock: AstBlock, exceptionBlock: Block): Unit {
        TranslateFinallyRethrowFlow(finallyBlock, exceptionBlock)
        let finallyControlInfo = PopFinallyContext()
        TranslateFinallyNormalFlows(finallyBlock, finallyControlInfo)
    }

    private func TranslateFinallyRethrowFlow(finallyBlock: AstBlock, exceptionBlock: Block): Unit {
        let activeContext = CurrentFinallyContext()
        let savedControlFlowBlocks = activeContext.CloneControlFlowBlocks()
        activeContext.ClearControlFlowBlocks()
        currentBlock = exceptionBlock
        exceptionBlock.SetExceptions(ArrayList<ClassType>())
        let exceptionTy = ExceptionValueTypeFromFinallyContext()
        let exception = RequireResult(builder.CreateGetException(exceptionTy, CurrentBlock()))
        let beginCatchArgs = ArrayList<Value>()
        beginCatchArgs.add(exception)
        let beginCatch = RequireResult(builder.CreateIntrinsic(exceptionTy,
            IntrisicCallContext(kind: IntrinsicKind.BEGIN_CATCH, args: beginCatchArgs), CurrentBlock()))
        let savedLocalValSymbolTable = localValSymbolTable
        localValSymbolTable = AST2CHIRNodeMap<Value>(savedLocalValSymbolTable)
        let savedAstNodeSymbolTable = astNodeSymbolTable
        astNodeSymbolTable = AST2CHIRNodeMap<Value>(savedAstNodeSymbolTable)
        let _ = Translator.TranslateASTNode(finallyBlock, this)
        if (exceptionBlock.GetTerminator().isNone()) {
            builder.CreateGoTo(GetBlockByAST(finallyBlock), exceptionBlock)
        }
        localValSymbolTable = savedLocalValSymbolTable
        astNodeSymbolTable = savedAstNodeSymbolTable
        let rethrowEdges = activeContext.CloneControlFlowBlocks()
        activeContext.RestoreControlFlowBlocks(savedControlFlowBlocks)
        let endCatchBlock = builder.CreateBlock(RequireParentBlockGroup(CurrentBlock(), "finally rethrow"))
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(endCatchBlock, CurrentBlock())
        }
        currentBlock = endCatchBlock
        if (let Some(outerBlock) <- CurrentTryCatchBlock()) {
            builder.CreateRaiseException(beginCatch, outerBlock, CurrentBlock())
        } else {
            builder.CreateRaiseException(beginCatch, CurrentBlock())
        }
        for (edges in rethrowEdges) {
            for (edge in edges) {
                if (edge.prevBlock.GetTerminator().isNone()) {
                    builder.CreateGoTo(endCatchBlock, edge.prevBlock)
                }
            }
        }
    }

    private func TranslateFinallyNormalFlows(finallyBlock: AstBlock,
        finallyControlInfo: FaithfulFinallyControlContext): Unit {
        var controlIndex: Int64 = 0
        while (controlIndex < finallyControlInfo.controlFlowBlocks.size) {
            let edges = finallyControlInfo.controlFlowBlocks[controlIndex]
            for (edge in edges) {
                TranslateFinallyNormalFlow(finallyBlock, FaithfulFinallyControlTypeFromIndex(controlIndex), edge)
            }
            controlIndex++
        }
    }

    private func TranslateFinallyNormalFlow(finallyBlock: AstBlock, controlType: FaithfulFinallyControlType,
        edge: FaithfulFinallyControlEdge): Unit {
        let group = RequireParentBlockGroup(edge.prevBlock, "finally normal flow")
        let finallyEntryBlock = builder.CreateBlock(group)
        builder.CreateGoTo(finallyEntryBlock, edge.prevBlock)
        currentBlock = finallyEntryBlock
        let savedLocalValSymbolTable = localValSymbolTable
        localValSymbolTable = AST2CHIRNodeMap<Value>(savedLocalValSymbolTable)
        let savedAstNodeSymbolTable = astNodeSymbolTable
        astNodeSymbolTable = AST2CHIRNodeMap<Value>(savedAstNodeSymbolTable)
        let _ = Translator.TranslateASTNode(finallyBlock, this)
        if (finallyEntryBlock.GetTerminator().isNone()) {
            builder.CreateGoTo(GetBlockByAST(finallyBlock), finallyEntryBlock)
        }
        localValSymbolTable = savedLocalValSymbolTable
        astNodeSymbolTable = savedAstNodeSymbolTable
        if (CurrentBlock().GetTerminator().isSome()) {
            return
        }
        if (finallyContext.isEmpty() || FaithfulFinallyControlTypeIndex(controlType) ==
            FaithfulFinallyControlTypeIndex(FaithfulFinallyControlType.NORMAL)) {
            builder.CreateGoTo(edge.nextBlock, CurrentBlock())
            return
        }
        let outerContext = CurrentFinallyContext()
        if (FaithfulFinallyControlTypeIndex(controlType) ==
            FaithfulFinallyControlTypeIndex(FaithfulFinallyControlType.RETURN) ||
            edge.controlScopeLevel < outerContext.tryScopeLevel) {
            outerContext.Add(controlType, CurrentBlock(), edge.nextBlock, edge.controlScopeLevel)
        } else {
            builder.CreateGoTo(edge.nextBlock, CurrentBlock())
        }
    }

    private func ExceptionValueTypeFromFinallyContext(): Type {
        return BaseExceptionObjectType()
    }

    private func CanOptimizeLetPatternToSwitch(letPattern: AstLetPatternDestructor): Bool {
        if (!opts.IsOptimizationExisted(OptimizationFlag.SWITCH_OPT)) {
            return false
        }
        if (letPattern.patterns[0].astKind == ASTKind.WILDCARD_PATTERN) {
            return false
        }
        let selectorTy = RequireAstTy(RequireExpr(letPattern.initializer, "if-let initializer"))
        let validSelectorTy = IsOptimizableTy(selectorTy) || (selectorTy.IsEnum() && IsOptimizableEnumTy(selectorTy))
        if (!validSelectorTy) {
            return false
        }
        for (curPattern in letPattern.patterns) {
            CJC_ASSERT(curPattern.astKind != ASTKind.WILDCARD_PATTERN)
            if (curPattern.astKind == ASTKind.CONST_PATTERN) {
                continue
            }
            let varOrEnumPattern = curPattern as AstVarOrEnumPattern
            let realPatternKind = if (let Some(vep) <- varOrEnumPattern) {
                RequirePattern(vep.pattern, "var-or-enum pattern").astKind
            } else {
                curPattern.astKind
            }
            if (realPatternKind != ASTKind.ENUM_PATTERN) {
                return false
            } else if (varOrEnumPattern.isSome()) {
                continue
            }
            let enumPattern = (curPattern as AstEnumPattern) ??
                throw IllegalStateException("faithful AST2CHIR optimizable if-let expected enum pattern")
            if (enumPattern.patterns.isEmpty()) {
                continue
            }
            let firstParamKind = enumPattern.patterns[0].astKind
            if (firstParamKind == ASTKind.WILDCARD_PATTERN || firstParamKind == ASTKind.CONST_PATTERN) {
                continue
            }
            return false
        }
        return true
    }

    private func CanOptimizeMatchToSwitch(matchExpr: AstMatchExpr): Bool {
        if (!opts.IsOptimizationExisted(OptimizationFlag.SWITCH_OPT)) {
            return false
        }
        if (matchExpr.matchCases.size <= 1 ||
            matchExpr.matchCases[0].patterns[0].astKind == ASTKind.WILDCARD_PATTERN) {
            return false
        }
        let selectorTy = RequireAstTy(RequireExpr(matchExpr.selector, "match selector"))
        let validSelectorTy = IsOptimizableTy(selectorTy) || (selectorTy.IsEnum() && IsOptimizableEnumTy(selectorTy))
        if (!validSelectorTy) {
            return false
        }
        for (curCase in matchExpr.matchCases) {
            if (curCase.patternGuard.isSome()) {
                return false
            }
            for (curPattern in curCase.patterns) {
                if (curPattern.astKind == ASTKind.WILDCARD_PATTERN) {
                    return true
                }
                if (curPattern.astKind == ASTKind.CONST_PATTERN) {
                    continue
                }
                let varOrEnumPattern = curPattern as AstVarOrEnumPattern
                let realPatternKind = if (let Some(vep) <- varOrEnumPattern) {
                    RequirePattern(vep.pattern, "var-or-enum pattern").astKind
                } else {
                    curPattern.astKind
                }
                if (realPatternKind != ASTKind.ENUM_PATTERN) {
                    return false
                }
                if (varOrEnumPattern.isSome()) {
                    continue
                }
                let enumPattern = (curPattern as AstEnumPattern) ??
                    throw IllegalStateException("faithful AST2CHIR optimizable match expected enum pattern")
                if (enumPattern.patterns.isEmpty()) {
                    continue
                }
                let firstParamKind = enumPattern.patterns[0].astKind
                if (firstParamKind == ASTKind.WILDCARD_PATTERN || firstParamKind == ASTKind.CONST_PATTERN) {
                    continue
                }
                return false
            }
        }
        return true
    }

    private func PrintDebugMessage(isDebug: Bool, node: AstNode): Unit {
        if (!isDebug) {
            return
        }
        let fileStr = " file: " + (if (let Some(file) <- node.curFile) {
            file.fileName
        } else {
            node.begin.fileID.toString()
        })
        let message = "The matchExpr in the" + fileStr + " line:" + node.begin.line.toString() +
            " and the column:" + node.begin.column.toString() + " was optimized by The opt: switchOpt"
        println(message)
    }

    private func HasTypeOfNothing(matchExpr: AstMatchExpr): Bool {
        if (matchExpr.matchMode) {
            for (matchCase in matchExpr.matchCases) {
                if (!RequireAstTy(matchCase).IsNothing()) {
                    return false
                }
            }
            return true
        }
        for (matchCase in matchExpr.matchCaseOthers) {
            if (!RequireAstTy(matchCase).IsNothing()) {
                return false
            }
        }
        return true
    }

    private func GetSourceExprByMatchExpr(matchExpr: AstMatchExpr): SourceExpr {
        return match (matchExpr.sugarKind) {
            case AstSugarKind.QUEST => SourceExpr.QUEST
            case _ => SourceExpr.MATCH_EXPR
        }
    }

    private func TranslateMatchWithSelector(matchExpr: AstMatchExpr, retVal: Option<Value>): Unit {
        let selectorVal = Translator.TranslateASTNode(RequireExpr(matchExpr.selector, "match selector"), this) ??
            throw IllegalStateException("faithful AST2CHIR match selector produced no value")
        SetSkipPrintWarning(selectorVal)
        let endBlock = CreateBlock()
        let caseNum = matchExpr.matchCases.size
        let needScope = match (matchExpr.sugarKind) {
            case AstSugarKind.IS | AstSugarKind.AS => false
            case _ => true
        }
        if (needScope) {
            scopeInfo.add(-1)
        }
        let originLoc = TranslateLocation(matchExpr)
        let sourceExpr = GetSourceExprByMatchExpr(matchExpr)
        var caseIdx: Int64 = 0
        while (caseIdx < caseNum) {
            if (needScope) {
                scopeInfo[scopeInfo.size - 1] = scopeInfo[scopeInfo.size - 1] + 1
            }
            let current = matchExpr.matchCases[caseIdx]
            let (falseBlock, matchedBlock) = if (current.patterns.size == 1) {
                TranslateNestingCasePattern(current.patterns[0], selectorVal, originLoc, sourceExpr: sourceExpr)
            } else {
                TranslateOrPattern(current.patterns, selectorVal, originLoc)
            }
            var trueBlock = matchedBlock
            trueBlock = TranslatePatternGuard(current, falseBlock, trueBlock)
            if (sourceExpr == SourceExpr.QUEST && caseIdx == 0) {
                CJC_ASSERT(caseNum == 2)
                let secondBody = RequireBlock(matchExpr.matchCases[1].exprOrDecls, "question match second body")
                if (!secondBody.body.isEmpty()) {
                    let loc1 = TranslateLocation(secondBody.body[0].begin, secondBody.body[secondBody.body.size - 1].end)
                    falseBlock.SetDebugLocation(loc1)
                }
                CJC_ASSERT(trueBlock.GetPredecessors().size == 1)
                let loc2 = TranslateLocation(matchExpr.matchCases[0])
                trueBlock.GetPredecessors()[0].SetDebugLocation(loc2)
            }
            let currentBody = TranslateMatchCaseBody(RequireBlock(current.exprOrDecls, "match case body"), retVal,
                endBlock)
            builder.CreateGoTo(currentBody, trueBlock)
            if (caseIdx == caseNum - 1) {
                builder.CreateGoTo(endBlock, falseBlock)
                falseBlock.EnableAttr(Attribute.UNREACHABLE)
            } else {
                currentBlock = falseBlock
            }
            caseIdx++
        }
        if (needScope) {
            scopeInfo.remove(at: scopeInfo.size - 1)
        }
        currentBlock = endBlock
    }

    private func TranslatePatternGuard(matchCase: AstMatchCase, falseBlock: Block, trueBlock: Block): Block {
        if (matchCase.patternGuard.isNone()) {
            return trueBlock
        }
        currentBlock = trueBlock
        let newTrueBlock = CreateBlock()
        let cond = Translator.TranslateASTNode(RequireExpr(matchCase.patternGuard, "match pattern guard"), this) ??
            throw IllegalStateException("faithful AST2CHIR match pattern guard produced no value")
        builder.CreateBranch(cond, newTrueBlock, falseBlock, CurrentBlock())
        return newTrueBlock
    }

    private func TranslateMatchCaseBody(caseBody: AstBlock, retVal: Option<Value>, endBlock: Block): Block {
        let loc = if (caseBody.rightCurlPos.IsZero()) {
            if (caseBody.body.isEmpty()) {
                TranslateLocation(caseBody.end, caseBody.end)
            } else {
                TranslateLocation(caseBody.body[caseBody.body.size - 1])
            }
        } else {
            TranslateLocation(caseBody)
        }
        TranslateSubExprToLoc(caseBody, retVal, loc)
        let currentBody = GetBlockByAST(caseBody)
        if (CurrentBlock().GetTerminator().isNone()) {
            builder.CreateGoTo(endBlock, CurrentBlock())
        }
        return currentBody
    }

    private func GetConstPatternVal(constPattern: AstConstPattern): UInt64 {
        let litExpr = (RequireExpr(constPattern.literal, "const pattern literal") as AstLitConstExpr) ??
            throw IllegalStateException("faithful AST2CHIR const pattern literal is not LitConstExpr")
        let ty = RequireAstTy(litExpr)
        if (ty.IsSignedInteger()) {
            return IntLiteral(litExpr.constNumValue.asInt.`Int64`()).GetUnsignedVal()
        }
        if (ty.IsUnsignedInteger()) {
            return litExpr.constNumValue.asInt.Uint64()
        }
        if (ty.IsRune()) {
            return UInt64(litExpr.codepoint[0])
        }
        if (ty.IsBoolean()) {
            return if (litExpr.constNumValue.asBoolean) { 1u64 } else { 0u64 }
        }
        throw IllegalArgumentException("unsupported const pattern type: ${ty.String()}")
    }

    private func GetRealEnumPattern(pattern: AstPattern): AstEnumPattern {
        CJC_ASSERT(pattern.astKind == ASTKind.VAR_OR_ENUM_PATTERN || pattern.astKind == ASTKind.ENUM_PATTERN)
        if (let Some(varOrEnumPattern) <- (pattern as AstVarOrEnumPattern)) {
            return (RequirePattern(varOrEnumPattern.pattern, "var-or-enum enum pattern") as AstEnumPattern) ??
                throw IllegalStateException("faithful AST2CHIR var-or-enum does not contain enum pattern")
        }
        return (pattern as AstEnumPattern) ??
            throw IllegalStateException("faithful AST2CHIR expected enum pattern")
    }

    private func IsOptimizableEnumPatterns(patterns: ArrayList<AstPattern>): Bool {
        for (pattern in patterns) {
            CJC_ASSERT(pattern.astKind == ASTKind.VAR_OR_ENUM_PATTERN || pattern.astKind == ASTKind.ENUM_PATTERN)
            if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
                for (subPattern in enumPattern.patterns) {
                    if (subPattern.astKind != ASTKind.WILDCARD_PATTERN) {
                        return false
                    }
                }
            }
        }
        return true
    }

    private func GetEnumPatternID(enumPattern: AstEnumPattern): UInt64 {
        return UInt64(GetEnumCtorId(RequireEnumPatternConstructor(enumPattern)))
    }

    private func TranslateOrPattern(patterns: ArrayList<AstPattern>, selectorVal: Value,
        originLoc: DebugLocation): (Block, Block) {
        CJC_ASSERT(patterns.size > 1)
        let patternKind = patterns[0].astKind
        if (patternKind == ASTKind.WILDCARD_PATTERN) {
            let trueBlock = CreateBlock()
            builder.CreateGoTo(trueBlock, CurrentBlock())
            return (CreateBlock(), trueBlock)
        }
        if (patternKind == ASTKind.CONST_PATTERN) {
            let patternTy = RequireAstTy(patterns[0])
            if (patternTy.IsString() || patternTy.IsFloating()) {
                return TranslateComplicatedOrPattern(patterns, selectorVal, originLoc)
            }
            if (patternTy.IsUnit()) {
                let trueBlock = CreateBlock()
                builder.CreateGoTo(trueBlock, CurrentBlock())
                return (CreateBlock(), trueBlock)
            }
            let values = TreeSet<UInt64>()
            for (pattern in patterns) {
                values.add(GetConstPatternVal((pattern as AstConstPattern) ??
                    throw IllegalStateException("faithful AST2CHIR or-pattern expected const pattern")))
            }
            let out = ArrayList<UInt64>()
            for (value in values) {
                out.add(value)
            }
            return TranslateConstantMultiOr(out, selectorVal)
        }
        if (patternKind == ASTKind.TUPLE_PATTERN || patternKind == ASTKind.TYPE_PATTERN) {
            return TranslateComplicatedOrPattern(patterns, selectorVal, originLoc)
        }
        CJC_ASSERT(patternKind == ASTKind.VAR_OR_ENUM_PATTERN || patternKind == ASTKind.ENUM_PATTERN)
        if (IsOptimizableEnumPatterns(patterns)) {
            let values = TreeSet<UInt64>()
            for (pattern in patterns) {
                values.add(GetEnumPatternID(GetRealEnumPattern(pattern)))
            }
            let out = ArrayList<UInt64>()
            for (value in values) {
                out.add(value)
            }
            return TranslateConstantMultiOr(out, GetEnumIDValue(RequireAstTy(patterns[0]), selectorVal))
        }
        return TranslateComplicatedOrPattern(patterns, selectorVal, originLoc)
    }

    private func GetEnumIDValue(ty: AstTy, selectorVal: Value): Value {
        CJC_ASSERT(ty.kind == AstTypeKind.TYPE_ENUM)
        let enumDecl = ((AstTy.GetDeclOfTy(Some(ty)) ??
            throw IllegalStateException("faithful AST2CHIR enum type has no enum decl")) as AstEnumDecl) ??
            throw IllegalStateException("faithful AST2CHIR enum type has no enum decl")
        let enumTy = (ty as AstEnumTy) ??
            throw IllegalStateException("faithful AST2CHIR enum selector ty is not EnumTy")
        let selectorType = GetSelectorType(enumTy)
        if (!enumDecl.hasArguments) {
            return CreateWrappedTypeCast(selectorType, GetDerefedValue(selectorVal), CurrentBlock())
        }
        let path = ArrayList<UInt64>()
        path.add(0u64)
        return RequireResult(builder.CreateField(selectorType, selectorVal, path, CurrentBlock()))
    }

    private func TranslateConstantMultiOr(values: ArrayList<UInt64>, value: Value): (Block, Block) {
        let falseBlock = CreateBlock()
        let trueBlock = CreateBlock()
        let succs = ArrayList<Block>()
        for (_ in values) {
            succs.add(trueBlock)
        }
        builder.CreateMultiBranch(TypeCastOrBoxIfNeeded(value, builder.context.GetUInt64Ty(), value.GetDebugLocation(),
            needCheck: false), falseBlock, values, succs, CurrentBlock())
        return (falseBlock, trueBlock)
    }

    private func TranslateComplicatedOrPattern(patterns: ArrayList<AstPattern>, selectorVal: Value,
        originLoc: DebugLocation): (Block, Block) {
        CJC_ASSERT(patterns.size > 1)
        let trueBlock = CreateBlock()
        for (pattern in patterns) {
            let (innerFalse, innerTrue) = TranslateNestingCasePattern(pattern, selectorVal, originLoc)
            builder.CreateGoTo(trueBlock, innerTrue)
            currentBlock = innerFalse
        }
        return (CurrentBlock(), trueBlock)
    }

    private func DispatchingPattern(queue: ArrayList<(AstPattern, Value)>, finalMatchedBlock: Block,
        nextConditionBlock: Block, originLoc: DebugLocation): Option<Value> {
        let (pattern, value) = queue[0]
        queue.remove(at: 0)
        if (pattern.astKind == ASTKind.VAR_OR_ENUM_PATTERN) {
            let varOrEnumPattern = (pattern as AstVarOrEnumPattern) ??
                throw IllegalStateException("faithful AST2CHIR expected var-or-enum pattern")
            queue.add((RequirePattern(varOrEnumPattern.pattern, "var-or-enum pattern"), value))
            return None
        }
        if (pattern.astKind == ASTKind.VAR_PATTERN) {
            HandleVarPattern((pattern as AstVarPattern) ??
                throw IllegalStateException("faithful AST2CHIR expected var pattern"), value, finalMatchedBlock)
            return None
        }
        if (pattern.astKind == ASTKind.WILDCARD_PATTERN) {
            return None
        }
        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
            CollectingSubPatterns(RequireAstTy(pattern),
                ((pattern as AstTuplePattern) ??
                    throw IllegalStateException("faithful AST2CHIR expected tuple pattern")).patterns, value, queue)
            return None
        }
        if (pattern.astKind == ASTKind.ENUM_PATTERN) {
            return HandleEnumPattern((pattern as AstEnumPattern) ??
                throw IllegalStateException("faithful AST2CHIR expected enum pattern"), value, queue,
                nextConditionBlock, originLoc)
        }
        if (pattern.astKind == ASTKind.TYPE_PATTERN) {
            return HandleTypePattern((pattern as AstTypePattern) ??
                throw IllegalStateException("faithful AST2CHIR expected type pattern"), value, queue)
        }
        if (pattern.astKind == ASTKind.CONST_PATTERN) {
            return HandleConstPattern((pattern as AstConstPattern) ??
                throw IllegalStateException("faithful AST2CHIR expected const pattern"), value, originLoc)
        }
        throw IllegalArgumentException("translating unsupported pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func TranslateNestingCasePattern(pattern: AstPattern, selectorVal: Value, originLoc: DebugLocation,
        sourceExpr!: SourceExpr = SourceExpr.MATCH_EXPR): (Block, Block) {
        let falseBlock = CreateBlock()
        let trueBlock = CreateBlock()
        let queue = ArrayList<(AstPattern, Value)>()
        queue.add((pattern, selectorVal))
        var newBlock = CreateBlock()
        let patternLoc = TranslateLocation(pattern)
        if (sourceExpr != SourceExpr.QUEST) {
            CurrentBlock().SetDebugLocation(patternLoc)
        }
        while (!queue.isEmpty()) {
            let cond = DispatchingPattern(queue, trueBlock, newBlock, originLoc)
            if (let Some(condValue) <- cond) {
                let nextBlock = if (queue.isEmpty()) { trueBlock } else { newBlock }
                if (sourceExpr != SourceExpr.QUEST) {
                    nextBlock.SetDebugLocation(patternLoc)
                }
                CreateWrappedBranch(sourceExpr, GetDerefedValue(condValue), nextBlock, falseBlock, CurrentBlock())
                currentBlock = nextBlock
                if (!queue.isEmpty()) {
                    newBlock = CreateBlock()
                }
            } else if (queue.isEmpty()) {
                if (sourceExpr != SourceExpr.QUEST) {
                    CurrentBlock().SetDebugLocation(patternLoc)
                }
                builder.CreateGoTo(trueBlock, CurrentBlock())
            }
        }
        newBlock.RemoveSelfFromBlockGroup()
        return (falseBlock, trueBlock)
    }

    private func CollectingSubPatterns(patternTy: AstTy, patterns: ArrayList<AstPattern>, value: Value,
        queue: ArrayList<(AstPattern, Value)>, offset!: Int64 = 0): Unit {
        if (patterns.isEmpty()) {
            return
        }
        let indexes = ArrayList<UInt64>()
        let funcTy = patternTy as AstFuncTy
        let isEnumField = funcTy.isSome()
        let typeArgs = if (let Some(realFuncTy) <- funcTy) {
            realFuncTy.paramTys
        } else {
            patternTy.typeArgs
        }
        CJC_ASSERT(typeArgs.size == patterns.size)
        var index: Int64 = 0
        while (index < patterns.size) {
            indexes.add(UInt64(index + offset))
            collectRecursively(patterns[index], typeArgs[index], value, queue, indexes, isEnumField)
            indexes.remove(at: indexes.size - 1)
            index++
        }
    }

    private func collectRecursively(pattern: AstPattern, ty: AstTy, value: Value,
        queue: ArrayList<(AstPattern, Value)>, indexes: ArrayList<UInt64>, isEnumField: Bool): Unit {
        if (pattern.astKind == ASTKind.WILDCARD_PATTERN) {
            queue.add((pattern, value))
            return
        }
        let tuplePattern = pattern as AstTuplePattern
        if (tuplePattern.isNone() || isEnumField) {
            let elementAstTy = if (ty.HasGeneric()) { RequireAstTy(pattern) } else { ty }
            let elementTy = chirTy.TranslateType(elementAstTy)
            let elementVal = RequireResult(builder.CreateField(elementTy, value, indexes, CurrentBlock()))
            queue.add((pattern, elementVal))
            return
        }
        let realTuplePattern = tuplePattern.getOrThrow()
        var idx: Int64 = 0
        while (idx < realTuplePattern.patterns.size) {
            indexes.add(UInt64(idx))
            collectRecursively(realTuplePattern.patterns[idx], RequireAstTy(realTuplePattern).typeArgs[idx], value,
                queue, indexes, isEnumField)
            indexes.remove(at: indexes.size - 1)
            idx++
        }
    }

    private func HandleVarPattern(varPattern: AstVarPattern, value: Value, trueBlock: Block): Unit {
        let backupBlock = CurrentBlock()
        currentBlock = trueBlock
        var val = if (varPattern.desugarExpr.isSome()) { GetDerefedValue(value) } else { value }
        let varType = chirTy.TranslateType(RequireAstTy(varPattern))
        let loc = TranslateLocation(varPattern)
        let varDecl = varPattern.varDecl ??
            throw IllegalStateException("faithful AST2CHIR VarPattern has no VarDecl")
        if (opts.enableCompileDebug || opts.enableCoverage) {
            let alloca = RequireResult(builder.CreateAllocate(builder.context.GetRefTy(varType), varType, trueBlock))
            if (!varDecl.TestAttr(AstAttribute.COMPILER_ADD)) {
                alloca.SetSrcCodeIdentifier(varDecl.identifier.Val())
                let debugInfo = builder.CreateDebug(builder.context.GetUnitTy(), alloca, varDecl.identifier.Val(),
                    trueBlock)
                debugInfo.SetDebugLocation(loc)
            }
            CreateAndAppendWrappedStore(val, alloca, trueBlock, loc)
            val = RequireResult(builder.CreateLoad(varType, alloca, trueBlock))
        } else {
            val = TypeCastOrBoxIfNeeded(val, varType, loc)
        }
        val.EnableAttr(Attribute.READONLY)
        currentBlock = backupBlock
        if (let Some(desugarExpr) <- varPattern.desugarExpr) {
            SetExprValue(desugarExpr, val)
        } else {
            SetSymbolTable(varDecl, val)
        }
    }

    private func HandleEnumPattern(enumPattern: AstEnumPattern, value: Value, queue: ArrayList<(AstPattern, Value)>,
        trueBlock: Block, originLoc: DebugLocation): Value {
        let enumIdx = GetEnumIDValue(RequireAstTy(enumPattern), value)
        let selectorTy = GetSelectorType((RequireAstTy(enumPattern) as AstEnumTy) ??
            throw IllegalStateException("faithful AST2CHIR enum pattern type is not EnumTy"))
        let enumId = GetEnumPatternID(enumPattern)
        let idValue = if (selectorTy.IsBoolean()) {
            RequireResult(builder.CreateConstant(selectorTy, BoolLiteral(enumId != 0u64), CurrentBlock()))
        } else {
            RequireResult(builder.CreateConstant(selectorTy, IntLiteral(enumId), CurrentBlock()))
        }
        let cond = RequireResult(builder.CreateBinaryExpression(ExprKind.EQUAL, builder.context.GetBoolTy(), enumIdx,
            idValue, CurrentBlock()))
        cond.SetDebugLocation(originLoc)
        let backBlock = CurrentBlock()
        currentBlock = trueBlock
        var enumValue = value
        if (!enumPattern.patterns.isEmpty()) {
            enumValue = CastEnumValueToConstructorTupleType(enumValue, enumPattern)
        }
        CollectingSubPatterns(RequireAstTy(RequireExpr(enumPattern.constructor, "enum pattern constructor")),
            enumPattern.patterns, enumValue, queue, offset: 1)
        currentBlock = backBlock
        return cond
    }

    private func GetSelectorType(ty: AstEnumTy): Type {
        let enumDecl = ty.decl ??
            throw IllegalStateException("faithful AST2CHIR enum ty has no decl")
        return if (IsOptionLikeEnumDecl(enumDecl)) {
            builder.context.GetBoolTy()
        } else {
            builder.context.GetUInt32Ty()
        }
    }

    private func HandleConstPattern(constPattern: AstConstPattern, value: Value, originLoc: DebugLocation): Value {
        if (constPattern.operatorCallExpr.isNone()) {
            let litVal = Translator.TranslateASTNode(RequireExpr(constPattern.literal, "const pattern literal"), this) ??
                throw IllegalStateException("faithful AST2CHIR const pattern literal produced no value")
            SetSkipPrintWarning(litVal)
            let cond = RequireResult(builder.CreateBinaryExpression(ExprKind.EQUAL, builder.context.GetBoolTy(), value,
                litVal, CurrentBlock()))
            cond.SetDebugLocation(originLoc)
            return cond
        }
        let operatorCallExpr = constPattern.operatorCallExpr.getOrThrow()
        let base = ConstPatternOperatorBase(operatorCallExpr)
        SetExprValue(base, value)
        return Translator.TranslateASTNode(operatorCallExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR const pattern operator call produced no value")
    }

    private func HandleTypePattern(typePattern: AstTypePattern, value: Value,
        queue: ArrayList<(AstPattern, Value)>): Option<Value> {
        let innerPattern = RequirePattern(typePattern.pattern, "type pattern inner")
        if (typePattern.matchBeforeRuntime) {
            if (let Some(desugarExpr) <- typePattern.desugarExpr) {
                let desugarVarPattern = typePattern.desugarVarPattern ??
                    throw IllegalStateException("faithful AST2CHIR type pattern missing desugar var pattern")
                let desugarVarDecl = desugarVarPattern.varDecl ??
                    throw IllegalStateException("faithful AST2CHIR type pattern missing desugar var decl")
                SetSymbolTable(desugarVarDecl, value)
                let newVal = Translator.TranslateASTNode(desugarExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR type pattern desugar produced no value")
                queue.add((innerPattern, newVal))
            } else if (innerPattern.astKind == ASTKind.VAR_PATTERN) {
                queue.add((innerPattern, value))
            }
            return None
        }
        let typeNode = typePattern.typeNode ??
            throw IllegalStateException("faithful AST2CHIR type pattern has no type node")
        let targetTy = chirTy.TranslateType(RequireAstTy(typeNode))
        queue.add((innerPattern, value))
        if (typePattern.needRuntimeTypeCheck) {
            return RequireResult(builder.CreateInstanceOf(builder.context.GetBoolTy(), value, targetTy, CurrentBlock()))
        }
        return RequireResult(builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(false), CurrentBlock()))
    }

    private func TranslateConditionMatches(matchExpr: AstMatchExpr, retVal: Option<Value>): Unit {
        let endBlock = CreateBlock()
        var isStillReachable = true
        let caseSize = matchExpr.matchCaseOthers.size
        scopeInfo.add(-1)
        var idx: Int64 = 0
        while (idx < caseSize) {
            scopeInfo[scopeInfo.size - 1] = scopeInfo[scopeInfo.size - 1] + 1
            let current = matchExpr.matchCaseOthers[idx]
            let baseBlock = CurrentBlock()
            let currentBody = TranslateMatchCaseBody(RequireBlock(current.exprOrDecls, "condition match body"),
                retVal, endBlock)
            if (!isStillReachable) {
                idx++
                continue
            }
            let matchCaseExpr = RequireExpr(current.matchExpr, "condition match expr")
            if (matchCaseExpr.astKind == ASTKind.WILDCARD_EXPR) {
                builder.CreateGoTo(currentBody, baseBlock)
                isStillReachable = false
            } else {
                currentBlock = baseBlock
                let nextBlock = CreateBlock()
                let cond = Translator.TranslateASTNode(matchCaseExpr, this) ??
                    throw IllegalStateException("faithful AST2CHIR condition match case produced no value")
                builder.CreateBranch(cond, currentBody, nextBlock, CurrentBlock())
                currentBlock = nextBlock
                if (idx == caseSize - 1) {
                    CurrentBlock().EnableAttr(Attribute.UNREACHABLE)
                }
            }
            idx++
        }
        scopeInfo.remove(at: scopeInfo.size - 1)
        currentBlock = endBlock
    }

    private func WithoutEnumSubPattern(matchExpr: AstMatchExpr): Bool {
        for (curCase in matchExpr.matchCases) {
            for (subPattern in curCase.patterns) {
                if (subPattern.astKind != ASTKind.ENUM_PATTERN) {
                    continue
                }
                let enumPattern = (subPattern as AstEnumPattern) ??
                    throw IllegalStateException("faithful AST2CHIR expected enum pattern")
                if (!enumPattern.patterns.isEmpty()) {
                    return false
                }
            }
        }
        return true
    }

    private func DoesNotHaveEnumSubpattern(letPattern: AstLetPatternDestructor): Bool {
        for (pattern in letPattern.patterns) {
            if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
                if (!enumPattern.patterns.isEmpty()) {
                    return false
                }
            }
        }
        return true
    }

    private func GetJumpablePatternVal(pattern: AstPattern): UInt64 {
        CJC_ASSERT(pattern.astKind == ASTKind.CONST_PATTERN || pattern.astKind == ASTKind.VAR_OR_ENUM_PATTERN ||
            pattern.astKind == ASTKind.ENUM_PATTERN)
        if (let Some(constPattern) <- (pattern as AstConstPattern)) {
            return GetConstPatternVal(constPattern)
        }
        return GetEnumPatternID(GetRealEnumPattern(pattern))
    }

    private func IsOptimizableTy(ty: AstTy): Bool {
        return ty.IsInteger() || ty.IsRune()
    }

    private func IsOptimizableEnumTy(ty: AstTy): Bool {
        CJC_ASSERT(ty.IsEnum())
        let enumTy = (ty as AstEnumTy) ??
            throw IllegalStateException("faithful AST2CHIR enum ty is not EnumTy")
        if (GetSelectorType(enumTy).IsBoolean()) {
            return false
        }
        let enumDecl = ((AstTy.GetDeclOfTy(Some(ty)) ??
            throw IllegalStateException("faithful AST2CHIR enum type has no enum decl")) as AstEnumDecl) ??
            throw IllegalStateException("faithful AST2CHIR enum type has no enum decl")
        if (enumDecl.hasEllipsis) {
            return false
        }
        for (ctor in enumDecl.constructors) {
            if (let Some(ctorTy) <- ctor.GetTy()) {
                if (let Some(funcTy) <- (ctorTy as AstFuncTy)) {
                    CJC_ASSERT(!funcTy.paramTys.isEmpty())
                    if (!IsOptimizableTy(funcTy.paramTys[0])) {
                        return false
                    }
                }
            }
        }
        return true
    }

    private func TranslateMatchAsTable(matchExpr: AstMatchExpr, retVal: Option<Value>): Unit {
        let selectorTy = RequireAstTy(RequireExpr(matchExpr.selector, "match selector"))
        let selectorVal = Translator.TranslateASTNode(RequireExpr(matchExpr.selector, "match selector"), this) ??
            throw IllegalStateException("faithful AST2CHIR match selector produced no value")
        SetSkipPrintWarning(selectorVal)
        var enumDecl: Option<AstEnumDecl> = None
        if (let Some(decl) <- AstTy.GetDeclOfTy(Some(selectorTy))) {
            enumDecl = decl as AstEnumDecl
        }
        if (let None <- enumDecl) {
            TranslateTrivialMatchAsTable(matchExpr, selectorVal, retVal, 0)
        } else if (!enumDecl.getOrThrow().hasArguments || WithoutEnumSubPattern(matchExpr)) {
            TranslateTrivialMatchAsTable(matchExpr, GetEnumIDValue(selectorTy, selectorVal), retVal,
                enumDecl.getOrThrow().constructors.size)
        } else {
            TranslateEnumPatternMatchAsTable(matchExpr, selectorVal, retVal)
        }
    }

    private func TranslateTrivialMatchAsTable(matchExpr: AstMatchExpr, selectorVal: Value, retVal: Option<Value>,
        countOfPatterns: Int64): Unit {
        let indexToBodies = TreeMap<UInt64, Block>()
        let baseBlock = CurrentBlock()
        let endBlock = CreateBlock()
        var defaultBlock = endBlock
        var isStillReachable = true
        scopeInfo.add(-1)
        for (curCase in matchExpr.matchCases) {
            scopeInfo[scopeInfo.size - 1] = scopeInfo[scopeInfo.size - 1] + 1
            let currentBody = TranslateMatchCaseBody(RequireBlock(curCase.exprOrDecls, "match case body"), retVal,
                endBlock)
            CJC_ASSERT(!curCase.patterns.isEmpty())
            if (!isStillReachable) {
                continue
            }
            if (curCase.patterns[0].astKind == ASTKind.WILDCARD_PATTERN) {
                defaultBlock = currentBody
                defaultBlock.SetDebugLocation(TranslateLocation(curCase.patterns[0]))
                isStillReachable = false
                continue
            }
            for (pattern in curCase.patterns) {
                let patternVal = GetJumpablePatternVal(pattern)
                currentBody.SetDebugLocation(TranslateLocation(pattern))
                if (indexToBodies.contains(patternVal)) {
                    continue
                }
                indexToBodies[patternVal] = currentBody
                CJC_ASSERT(!indexToBodies.isEmpty())
                if (Int64(indexToBodies.size) == countOfPatterns) {
                    isStillReachable = false
                }
            }
        }
        scopeInfo.remove(at: scopeInfo.size - 1)
        let indexes = ArrayList<UInt64>()
        let blocks = ArrayList<Block>()
        for (key in indexToBodies.keys()) {
            indexes.add(key)
            blocks.add(indexToBodies.get(key).getOrThrow())
        }
        if (refEq(defaultBlock, endBlock)) {
            defaultBlock = blocks[0]
        }
        currentBlock = baseBlock
        let targetType = if (let Some(enumTy) <- (RequireAstTy(RequireExpr(matchExpr.selector, "match selector")) as
            AstEnumTy)) {
            GetSelectorType(enumTy)
        } else {
            builder.context.GetUInt64Ty()
        }
        let castedVal = TypeCastOrBoxIfNeeded(selectorVal, targetType, selectorVal.GetDebugLocation(),
            needCheck: false)
        let term = builder.CreateMultiBranch(castedVal, defaultBlock, indexes, blocks, baseBlock)
        term.SetDebugLocation(TranslateLocation(matchExpr))
        currentBlock = endBlock
    }

    private func TranslateEnumPatternMatchAsTable(matchExpr: AstMatchExpr, enumVal: Value,
        retVal: Option<Value>): Unit {
        var isStillReachable = true
        let baseBlock = CurrentBlock()
        let endBlock = CreateBlock()
        var firstDefaultBlock = endBlock
        let firstSelectorVal = GetEnumIDValue(RequireAstTy(RequireExpr(matchExpr.selector, "match selector")), enumVal)
        let matchInfo = EnumMatchInfo()
        var wildcardIdx = matchExpr.matchCases.size
        scopeInfo.add(-1)
        var idx: Int64 = 0
        while (idx < matchExpr.matchCases.size) {
            scopeInfo[scopeInfo.size - 1] = scopeInfo[scopeInfo.size - 1] + 1
            let matchCase = matchExpr.matchCases[idx]
            CJC_ASSERT(!matchCase.patterns.isEmpty())
            if (!isStillReachable) {
                idx++
                continue
            }
            if (matchCase.patterns[0].astKind == ASTKind.WILDCARD_PATTERN) {
                isStillReachable = false
                firstDefaultBlock = TranslateMatchCaseBody(RequireBlock(matchCase.exprOrDecls, "match case body"),
                    retVal, endBlock)
                firstDefaultBlock.SetDebugLocation(TranslateLocation(matchCase.patterns[0].begin,
                    matchCase.patterns[0].end))
                wildcardIdx = idx
                idx++
                continue
            }
            for (pattern in matchCase.patterns) {
                CollectEnumPatternInfo(pattern, matchInfo, idx)
            }
            idx++
        }
        scopeInfo.remove(at: scopeInfo.size - 1)
        let indexes = ArrayList<UInt64>()
        let blocks = ArrayList<Block>()
        for (key in matchInfo.firstSwitchBlocks.keys()) {
            indexes.add(key)
            blocks.add(matchInfo.firstSwitchBlocks.get(key).getOrThrow())
        }
        if (refEq(firstDefaultBlock, endBlock)) {
            firstDefaultBlock = blocks[0]
        }
        currentBlock = baseBlock
        builder.CreateMultiBranch(firstSelectorVal, firstDefaultBlock, indexes, blocks, baseBlock)
        let branchInfos = TranslateSecondLevelAsTable(matchInfo, enumVal, firstDefaultBlock)
        var caseIdx: Int64 = 0
        while (caseIdx < matchExpr.matchCases.size) {
            if (caseIdx == wildcardIdx) {
                caseIdx++
                continue
            }
            let bodyBlock = TranslateMatchCaseBody(RequireBlock(matchExpr.matchCases[caseIdx].exprOrDecls,
                "match case body"), retVal, endBlock)
            if (let Some(branchBlocks) <- branchInfos.get(caseIdx)) {
                for (block in branchBlocks) {
                    builder.CreateGoTo(bodyBlock, block)
                }
            }
            caseIdx++
        }
        currentBlock = endBlock
    }

    private func CollectEnumPatternInfo(pattern: AstPattern, info: EnumMatchInfo, caseId: Int64): Unit {
        let enumPattern = GetRealEnumPattern(pattern)
        let patternVal = GetEnumPatternID(enumPattern)
        if (!info.firstSwitchBlocks.contains(patternVal)) {
            let block = CreateBlock()
            block.SetDebugLocation(TranslateLocation(pattern))
            info.firstSwitchBlocks[patternVal] = block
        }
        let switchInfo = SecondSwitchInfo(enumPattern, caseId)
        if (!info.indexToBodies.contains(patternVal)) {
            info.indexToBodies[patternVal] = TreeMap<UInt64, ArrayList<SecondSwitchInfo>>()
        }
        let secondSwitchMap = info.indexToBodies.get(patternVal).getOrThrow()
        if (enumPattern.patterns.isEmpty()) {
            if (!info.innerDefaultInfos.contains(patternVal)) {
                info.innerDefaultInfos[patternVal] = ArrayList<SecondSwitchInfo>()
            }
            info.innerDefaultInfos.get(patternVal).getOrThrow().add(switchInfo)
            return
        }
        let secondValPattern = enumPattern.patterns[0]
        if (secondValPattern.astKind == ASTKind.WILDCARD_PATTERN) {
            if (!info.innerDefaultInfos.contains(patternVal)) {
                info.innerDefaultInfos[patternVal] = ArrayList<SecondSwitchInfo>()
            }
            info.innerDefaultInfos.get(patternVal).getOrThrow().add(switchInfo)
        } else if (info.innerDefaultInfos.contains(patternVal) && enumPattern.patterns.size != 1) {
            info.innerDefaultInfos.get(patternVal).getOrThrow().add(switchInfo)
        } else {
            CJC_ASSERT(secondValPattern.astKind == ASTKind.CONST_PATTERN)
            let secondVal = GetConstPatternVal((secondValPattern as AstConstPattern) ??
                throw IllegalStateException("faithful AST2CHIR expected const second pattern"))
            if (!secondSwitchMap.contains(secondVal)) {
                secondSwitchMap[secondVal] = ArrayList<SecondSwitchInfo>()
            }
            secondSwitchMap.get(secondVal).getOrThrow().add(switchInfo)
        }
    }

    private func TranslateSecondLevelAsTable(info: EnumMatchInfo, enumVal: Value,
        firstDefaultBlock: Block): HashMap<Int64, ArrayList<Block>> {
        let blockBranchInfos = HashMap<Int64, ArrayList<Block>>()
        for (firstIdx in info.indexToBodies.keys()) {
            let secondMap = info.indexToBodies.get(firstIdx).getOrThrow()
            let firstLevelBlock = info.firstSwitchBlocks.get(firstIdx).getOrThrow()
            let found = info.innerDefaultInfos.get(firstIdx)
            var secondDefaultBlock = firstDefaultBlock
            if (let None <- found) {
                secondDefaultBlock = firstDefaultBlock
            } else if (!found.getOrThrow().isEmpty() && found.getOrThrow()[0].ep.patterns.isEmpty()) {
                let caseId = found.getOrThrow()[0].caseId
                if (!blockBranchInfos.contains(caseId)) {
                    blockBranchInfos[caseId] = ArrayList<Block>()
                }
                blockBranchInfos.get(caseId).getOrThrow().add(firstLevelBlock)
            } else {
                secondDefaultBlock = if (secondMap.isEmpty()) { firstLevelBlock } else { CreateBlock() }
                TranslateSecondLevelTable(firstDefaultBlock, secondDefaultBlock, enumVal, found.getOrThrow(),
                    blockBranchInfos)
            }
            if (secondMap.isEmpty()) {
                continue
            }
            currentBlock = firstLevelBlock
            var firstSecondKey = 0u64
            var hasFirstSecondKey = false
            for (secondKey in secondMap.keys()) {
                firstSecondKey = secondKey
                hasFirstSecondKey = true
                break
            }
            CJC_ASSERT(hasFirstSecondKey)
            CJC_ASSERT(!secondMap.get(firstSecondKey).getOrThrow().isEmpty())
            let enumPattern = secondMap.get(firstSecondKey).getOrThrow()[0].ep
            CJC_ASSERT(!enumPattern.patterns.isEmpty())
            let firstPattern = enumPattern.patterns[0]
            PrintDebugMessage(opts.chirDebugOptimizer, enumPattern)
            CJC_ASSERT(RequireAstTy(firstPattern).IsInteger() || RequireAstTy(firstPattern).IsRune())
            let selectorTy = chirTy.TranslateType(RequireAstTy(firstPattern))
            let enumValueTuple = CastEnumValueToConstructorTupleType(enumVal, enumPattern)
            let secondPath = ArrayList<UInt64>()
            secondPath.add(1u64)
            let secondSelectVar = RequireResult(builder.CreateField(selectorTy, enumValueTuple, secondPath,
                CurrentBlock()))
            let indexes = ArrayList<UInt64>()
            let blocks = ArrayList<Block>()
            for (index in secondMap.keys()) {
                indexes.add(index)
                let block = CreateBlock()
                blocks.add(block)
                TranslateSecondLevelTable(secondDefaultBlock, block, enumVal, secondMap.get(index).getOrThrow(),
                    blockBranchInfos)
            }
            currentBlock = firstLevelBlock
            builder.CreateMultiBranch(TypeCastOrBoxIfNeeded(secondSelectVar, builder.context.GetUInt64Ty(),
                secondSelectVar.GetDebugLocation(), needCheck: false), secondDefaultBlock, indexes, blocks,
                firstLevelBlock)
        }
        return blockBranchInfos
    }

    private func TranslateSecondLevelTable(endBlock: Block, tableBlock: Block, enumVal: Value,
        infos: ArrayList<SecondSwitchInfo>, blockBranchInfos: HashMap<Int64, ArrayList<Block>>): Unit {
        currentBlock = tableBlock
        var hasGotoBase = false
        CJC_ASSERT(!infos.isEmpty())
        CJC_ASSERT(!infos[0].ep.patterns.isEmpty())
        let isWildcardPattern = infos[0].ep.patterns[0].astKind == ASTKind.WILDCARD_PATTERN
        var idx: Int64 = 0
        while (idx < infos.size) {
            let current = infos[idx]
            let trueBlock = if (!hasGotoBase && current.ep.patterns.size == 1) { tableBlock } else { CreateBlock() }
            hasGotoBase = hasGotoBase || current.ep.patterns.size == 1
            let falseBlock = CreateBlock()
            let queue = ArrayList<(AstPattern, Value)>()
            let elementTys = ((RequireEnumPatternConstructor(current.ep).GetTy() ??
                throw IllegalStateException("faithful AST2CHIR enum constructor has no type")) as AstFuncTy) ??
                throw IllegalStateException("faithful AST2CHIR enum constructor type is not FuncTy")
            let start: Int64 = if (isWildcardPattern &&
                current.ep.patterns[0].astKind != ASTKind.WILDCARD_PATTERN) { 0 } else { 1 }
            var patternIdx = start
            while (patternIdx < current.ep.patterns.size) {
                let elementTy = chirTy.TranslateType(elementTys.paramTys[patternIdx])
                let enumValueTuple = CastEnumValueToConstructorTupleType(enumVal, current.ep)
                let path = ArrayList<UInt64>()
                path.add(UInt64(1 + patternIdx))
                let elementVal = RequireResult(builder.CreateField(elementTy, enumValueTuple, path, CurrentBlock()))
                queue.add((current.ep.patterns[patternIdx], elementVal))
                patternIdx++
            }
            var newBlock = CreateBlock()
            while (!queue.isEmpty()) {
                let originLoc = if (let Some(ctxExpr) <- current.ep.ctxExpr) {
                    TranslateLocation(ctxExpr.begin, ctxExpr.end)
                } else {
                    TranslateLocation(current.ep)
                }
                let cond = DispatchingPattern(queue, trueBlock, newBlock, originLoc)
                if (let Some(condValue) <- cond) {
                    let nextBlock = if (queue.isEmpty()) { trueBlock } else { newBlock }
                    builder.CreateBranch(condValue, nextBlock, falseBlock, CurrentBlock())
                    currentBlock = nextBlock
                } else if (queue.isEmpty()) {
                    builder.CreateGoTo(trueBlock, CurrentBlock())
                }
                if (cond.isSome() && !queue.isEmpty()) {
                    newBlock = CreateBlock()
                }
            }
            newBlock.RemoveSelfFromBlockGroup()
            if (!blockBranchInfos.contains(current.caseId)) {
                blockBranchInfos[current.caseId] = ArrayList<Block>()
            }
            blockBranchInfos.get(current.caseId).getOrThrow().add(trueBlock)
            if (idx == infos.size - 1) {
                builder.CreateGoTo(endBlock, falseBlock)
            } else {
                currentBlock = falseBlock
            }
            idx++
        }
    }

    private func TranslateSubExprToLoc(node: AstNode, location: Option<Value>): Unit {
        if (let None <- location) {
            let _ = Translator.TranslateASTNode(node, this)
            return
        }
        let loc = location.getOrThrow()
        let debugLoc = if (let Some(localVar) <- (loc as LocalVar)) {
            localVar.GetExpr().getOrThrow().GetDebugLocation()
        } else {
            loc.GetDebugLocation()
        }
        TranslateSubExprToLoc(node, location, debugLoc)
    }

    private func TranslateSubExprToLoc(node: AstNode, location: Option<Value>, debugLoc: DebugLocation): Unit {
        let value = Translator.TranslateASTNode(node, this)
        if (let None <- location) {
            return
        }
        let loc = location.getOrThrow()
        let targetTy = ((loc.GetType() ??
            throw IllegalStateException("faithful AST2CHIR location has no type")) as RefType) ??
            throw IllegalStateException("faithful AST2CHIR location is not ref")
        if (targetTy.GetBaseType().IsNothing()) {
            return
        }
        var storedValue = value
        if (RequireAstTy(node).IsUnit() && !targetTy.GetBaseType().IsUnit()) {
            storedValue = RequireResult(builder.CreateConstant(builder.context.GetUnitTy(), UnitLiteral(),
                CurrentBlock()))
            storedValue.getOrThrow().SetDebugLocation(debugLoc)
        }
        if (targetTy.GetBaseType().IsUnit() || storedValue.isNone()) {
            if (!opts.enableCompileDebug) {
                return
            }
            if (storedValue.isNone()) {
                if (RequireAstTy(node).IsUnit()) {
                    storedValue = RequireResult(builder.CreateConstant(builder.context.GetUnitTy(), UnitLiteral(),
                        CurrentBlock()))
                    storedValue.getOrThrow().SetDebugLocation(debugLoc)
                } else {
                    storedValue = RequireResult(builder.CreateConstant(builder.context.GetNothingType(), NullLiteral(),
                        CurrentBlock()))
                    storedValue.getOrThrow().SetDebugLocation(debugLoc)
                    SetSkipPrintWarning(storedValue.getOrThrow())
                }
            }
        }
        var realValue = GetDerefedValue(storedValue.getOrThrow())
        if ((realValue.GetType() ?? throw IllegalStateException("faithful AST2CHIR value has no type")).IsNothing()) {
            return
        }
        realValue = TypeCastOrBoxIfNeeded(realValue, targetTy.GetBaseType(), debugLoc)
        CreateAndAppendWrappedStore(realValue, loc, debugLoc)
    }

    private func CreateWrappedBranch(sourceExpr: SourceExpr, cond: Value, trueBlock: Block, falseBlock: Block,
        parent: Block): Unit {
        let branch = builder.CreateBranch(cond, trueBlock, falseBlock, parent)
        branch.SetSourceExpr(sourceExpr)
    }

    private func CreateWrappedTypeCast(ty: Type, operand: Value, parent: Block): Value {
        return RequireResult(builder.CreateTypeCast(ty, operand, parent))
    }

    private func SetSkipPrintWarning(value: Value): Unit {
        value.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
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
            let cond = TranslateConstPatternCondition(constPattern, selector)
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
        BindPatternValues(pattern, selector, CurrentBlock())
    }

    private func BindPatternValues(pattern: AstPattern, selector: Value, block: Block): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            BindVarPatternValue(varPattern, selector, block)
            return
        }
        if (let Some(varOrEnum) <- (pattern as AstVarOrEnumPattern)) {
            if (let Some(realPattern) <- varOrEnum.pattern) {
                BindPatternValues(realPattern, selector, block)
            }
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            var idx: Int64 = 0
            for (subPattern in tuplePattern.patterns) {
                let fieldValue = ExtractPatternField(selector, idx, chirTy.TranslateType(RequireAstTy(subPattern)))
                BindPatternValues(subPattern, fieldValue, block)
                idx++
            }
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            let enumSelector = EnumPatternPayloadSelector(selector, enumPattern)
            let payloadTypes = EnumPatternPayloadTypes(enumPattern)
            var idx: Int64 = 0
            for (subPattern in enumPattern.patterns) {
                let fieldTy = if (idx < payloadTypes.size) {
                    payloadTypes[idx]
                } else {
                    chirTy.TranslateType(RequireAstTy(subPattern))
                }
                let payloadValue = ExtractPatternField(enumSelector, idx + 1, fieldTy)
                BindPatternValues(subPattern, payloadValue, block)
                idx++
            }
            return
        }
        if (let Some(typePattern) <- (pattern as AstTypePattern)) {
            if (let Some(inner) <- typePattern.pattern) {
                BindPatternValues(inner, selector, block)
            }
            return
        }
    }

    private func BindVarPatternValue(pattern: AstVarPattern, value: Value, block: Block): Unit {
        let varDecl = pattern.varDecl ??
            throw IllegalStateException("faithful AST2CHIR match VarPattern has no VarDecl")
        let backup = currentBlock
        currentBlock = block
        let boundValue = CastValueIfNeeded(value, VarPatternBindingType(pattern, value))
        boundValue.EnableAttr(Attribute.READONLY)
        currentBlock = backup
        if (let Some(desugar) <- pattern.desugarExpr) {
            if (let Some(desugarTarget) <- desugar.GetTarget()) {
                localValSymbolTable.Set(desugarTarget, boundValue)
            }
        } else {
            localValSymbolTable.Set(varDecl, boundValue)
        }
    }

    private func VarPatternBindingType(pattern: AstVarPattern, value: Value): Type {
        let astTy = RequireAstTy(pattern)
        if (!astTy.IsAny()) {
            return chirTy.TranslateType(astTy)
        }
        return value.GetType() ??
            throw IllegalStateException("faithful AST2CHIR VarPattern value has no CHIR type")
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
        let payloadSelector = EnumPatternPayloadSelector(selector, pattern)
        TranslatePatternSequenceWithTypes(pattern.patterns, EnumPatternPayloadTypes(pattern), payloadSelector, 1,
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
                if (let Some(desugar) <- pattern.desugarExpr) {
                    if (let Some(varPattern) <- pattern.desugarVarPattern) {
                        BindVarPatternValue(varPattern, selector, CurrentBlock())
                    }
                    let newValue = Translator.TranslateASTNode(desugar, this) ??
                        throw IllegalStateException("faithful AST2CHIR type pattern desugar produced no value")
                    TranslateSinglePatternBranch(inner, newValue, trueBlock, falseBlock)
                } else {
                    TranslateSinglePatternBranch(inner, selector, trueBlock, falseBlock)
                }
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

    private func TranslateConstPatternCondition(pattern: AstConstPattern, selector: Value): Value {
        if (let Some(callExpr) <- pattern.operatorCallExpr) {
            let base = ConstPatternOperatorBase(callExpr)
            SetExprValue(base, selector)
            return Translator.TranslateASTNode(callExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR const pattern operator call produced no value")
        }
        let litValue = Translator.TranslateASTNode(RequireExpr(pattern.literal, "const pattern literal"), this) ??
            throw IllegalStateException("faithful AST2CHIR const pattern literal produced no value")
        return RequireResult(builder.CreateBinaryExpression(ExprKind.EQUAL, builder.context.GetBoolTy(), selector,
            litValue, CurrentBlock()))
    }

    private func ConstPatternOperatorBase(callExpr: AstCallExpr): AstExpr {
        let member = (RequireExpr(callExpr.baseFunc, "const pattern operator callee") as AstMemberAccess) ??
            throw IllegalStateException("faithful AST2CHIR const pattern operator callee is not MemberAccess")
        return RequireExpr(member.baseExpr, "const pattern operator base")
    }

    private func SetExprValue(expr: AstExpr, value: Value): Unit {
        exprValueTable[expr.objectId] = value
    }

    private func TryGetExprValue(expr: AstExpr): Option<Value> {
        return exprValueTable.get(expr.objectId)
    }

    private func EnumPatternPayloadTypes(pattern: AstEnumPattern): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (let Some(funcDecl) <- (RequireEnumPatternConstructor(pattern) as AstFuncDecl)) {
            if (let Some(ctorTy) <- funcDecl.GetTy()) {
                if (let Some(funcTy) <- (ctorTy as AstFuncTy)) {
                    for (paramTy in funcTy.paramTys) {
                        out.add(TranslateEnumPatternPayloadType(pattern, paramTy))
                    }
                    return out
                }
            }
        }
        if (let Some(constructorExpr) <- pattern.constructor) {
            if (let Some(constructorTy) <- constructorExpr.GetTy()) {
                if (let Some(funcTy) <- (constructorTy as AstFuncTy)) {
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

    private func EnumPatternPayloadSelector(value: Value, pattern: AstEnumPattern): Value {
        return CastEnumValueToConstructorTupleType(value, pattern)
    }

    private func CastEnumValueToConstructorTupleType(value: Value, pattern: AstEnumPattern): Value {
        let constructor = RequireEnumPatternConstructor(pattern)
        let enumDecl = ((constructor.outerDecl ?? throw IllegalStateException(
            "faithful AST2CHIR enum constructor has no outer enum")) as AstEnumDecl) ??
            throw IllegalStateException("faithful AST2CHIR enum constructor outer is not enum")
        let fieldTys = ArrayList<Type>()
        fieldTys.add(GetSelectorType((RequireAstTy(enumDecl) as AstEnumTy) ??
            throw IllegalStateException("faithful AST2CHIR enum decl type is not EnumTy")))
        let payloadTypes = EnumPatternPayloadTypes(pattern)
        if (!payloadTypes.isEmpty()) {
            for (payloadTy in payloadTypes) {
                fieldTys.add(payloadTy)
            }
        } else if (!pattern.patterns.isEmpty()) {
            let constructorTy = RequireAstTy(RequireExpr(pattern.constructor, "enum pattern constructor"))
            if (let Some(funcTy) <- (constructorTy as AstFuncTy)) {
                for (payloadTy in funcTy.paramTys) {
                    fieldTys.add(TranslateEnumPatternPayloadType(pattern, payloadTy))
                }
            } else {
                for (payloadTy in constructorTy.typeArgs) {
                    fieldTys.add(TranslateEnumPatternPayloadType(pattern, payloadTy))
                }
            }
        }
        let resultValue = TypeCastOrBoxIfNeeded(value, builder.context.GetTupleTy(fieldTys), value.GetDebugLocation())
        resultValue.SetEnumCaseIndex(Some(GetEnumCtorId(constructor)))
        return resultValue
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
        if (let Some(target) <- constructorExpr.GetTarget()) {
            return target
        }
        if (let Some(refExpr) <- (constructorExpr as AstRefExpr)) {
            return refExpr.ref.target ??
                throw IllegalStateException("faithful AST2CHIR enum pattern RefExpr has no target")
        }
        if (let Some(member) <- (constructorExpr as AstMemberAccess)) {
            return ResolveMemberAccessTarget(member, "faithful AST2CHIR enum pattern MemberAccess")
        }
        throw IllegalArgumentException("not yet ported in faithful AST2CHIR: enum pattern constructor expression")
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
            FuncCallContext(args: args, instTypeArgs: instTypeArgs, thisType: None))
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
            FuncCallContext(args: args, instTypeArgs: instTypeArgs, thisType: None))
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
        let field = builder.CreateField(chirTy.TranslateType(RequireAstTy(expr)), baseValue, path, CurrentBlock())
        if (expr.TestAttr(AstAttribute.IMPLICIT_ADD)) {
            field.SetSkipCheck(SkipKind.SKIP_DCE_WARNING)
        }
        return RequireResult(field)
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
        AppendTranslatedCallArgs(expr, calleeDecl, args, expectedParamTys, ArrayList<Value>())
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

    private func CreateApplyMaybeWithException(resultTy: Type, callee: Value, callContext: FuncCallContext,
        loc!: DebugLocation = INVALID_LOCATION): Value {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = CreateBlock()
            let exceptionBlock = DelayExitExceptionBlock(errorBlock)
            let term = if (let Some(exceptBlock) <- exceptionBlock) {
                builder.CreateApplyWithException(resultTy, callee, callContext, successBlock, exceptBlock,
                    CurrentBlock())
            } else {
                builder.CreateApplyWithException(resultTy, callee, callContext, successBlock, errorBlock,
                    CurrentBlock())
            }
            term.SetDebugLocation(loc)
            let result = RequireResult(term)
            FinishDelayExitExceptionBlock(exceptionBlock, successBlock)
            return result
        }
        let apply = builder.CreateApply(resultTy, callee, callContext, CurrentBlock())
        apply.SetDebugLocation(loc)
        return RequireResult(apply)
    }

    private func CreateAndAppendApplyCallFromCallExpr(resultTy: Type, callee: Value, callContext: FuncCallContext,
        expr: AstCallExpr): Value {
        let loc = TranslateLocation(expr)
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = CreateBlock()
            let exceptionBlock = DelayExitExceptionBlock(errorBlock)
            let term = if (let Some(exceptBlock) <- exceptionBlock) {
                builder.CreateApplyWithException(resultTy, callee, callContext, successBlock, exceptBlock,
                    CurrentBlock())
            } else {
                builder.CreateApplyWithException(resultTy, callee, callContext, successBlock, errorBlock,
                    CurrentBlock())
            }
            term.SetDebugLocation(loc)
            if (HasNothingTypeArg(callContext.args)) {
                if (let Some(baseFunc) <- expr.baseFunc) {
                    term.SetDebugLocationInfoForWarning(TranslateLocation(baseFunc))
                } else {
                    term.SetDebugLocationInfoForWarning(loc)
                }
            }
            let result = RequireResult(term)
            FinishDelayExitExceptionBlock(exceptionBlock, successBlock)
            return result
        }
        let apply = builder.CreateApply(resultTy, callee, callContext, CurrentBlock())
        apply.SetDebugLocation(loc)
        if (expr.callKind == AstCallKind.CALL_SUPER_FUNCTION) {
            apply.SetSuperCall()
        }
        if (HasNothingTypeArg(callContext.args)) {
            if (let Some(baseFunc) <- expr.baseFunc) {
                apply.SetDebugLocationInfoForWarning(TranslateLocation(baseFunc))
            } else {
                apply.SetDebugLocationInfoForWarning(loc)
            }
        }
        return RequireResult(apply)
    }

    private func CreateAllocateMaybeWithException(resultTy: Type, allocatedTy: Type,
        loc!: DebugLocation = INVALID_LOCATION): Value {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = CreateBlock()
            let exceptionBlock = DelayExitExceptionBlock(errorBlock)
            if (let Some(exceptBlock) <- exceptionBlock) {
                let term = builder.CreateAllocateWithException(resultTy, allocatedTy, successBlock, exceptBlock,
                    CurrentBlock())
                term.SetDebugLocation(loc)
                let result = RequireResult(term)
                FinishDelayExitExceptionBlock(exceptionBlock, successBlock)
                return result
            }
            let term = builder.CreateAllocateWithException(resultTy, allocatedTy, successBlock, errorBlock,
                CurrentBlock())
            term.SetDebugLocation(loc)
            let result = RequireResult(term)
            currentBlock = successBlock
            return result
        }
        let allocate = builder.CreateAllocate(resultTy, allocatedTy, CurrentBlock())
        allocate.SetDebugLocation(loc)
        return RequireResult(allocate)
    }

    private func CreateSpawnMaybeWithException(resultTy: Type, futureObj: Value, spawnArg: Option<Value>): Unit {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = CreateBlock()
            let exceptionBlock = DelayExitExceptionBlock(errorBlock)
            let targetBlock = match (exceptionBlock) {
                case Some(exceptBlock) => exceptBlock
                case None => errorBlock
            }
            if (let Some(arg) <- spawnArg) {
                builder.CreateSpawnWithException(resultTy, futureObj, arg, successBlock, targetBlock, CurrentBlock())
            } else {
                builder.CreateSpawnWithException(resultTy, futureObj, successBlock, targetBlock, CurrentBlock())
            }
            FinishDelayExitExceptionBlock(exceptionBlock, successBlock)
            return
        }
        if (let Some(arg) <- spawnArg) {
            builder.CreateSpawn(resultTy, futureObj, arg, CurrentBlock())
        } else {
            builder.CreateSpawn(resultTy, futureObj, CurrentBlock())
        }
    }

    private func DelayExitExceptionBlock(errorBlock: Block): Option<Block> {
        if (delayExitSignal.isNone() || blockGroupStack.isEmpty()) {
            return None
        }
        let errorBlockGroup = RequireParentBlockGroup(errorBlock, "with-exception error block")
        if (refEq(blockGroupStack[blockGroupStack.size - 1], errorBlockGroup)) {
            return None
        }
        let exceptBlock = CreateBlock()
        exceptBlock.SetExceptions(ArrayList<ClassType>())
        return Some(exceptBlock)
    }

    private func FinishDelayExitExceptionBlock(exceptionBlock: Option<Block>, successBlock: Block): Unit {
        if (let Some(exceptBlock) <- exceptionBlock) {
            currentBlock = exceptBlock
            UpdateDelayExitSignal(CalculateDelayExitLevelForThrow())
            builder.CreateExit(None, exceptBlock)
        }
        currentBlock = successBlock
    }

    private func ActiveCallArgs(expr: AstCallExpr): ArrayList<AstFuncArg> {
        if (let Some(desugarArgs) <- expr.desugarArgs) {
            return desugarArgs
        }
        return expr.args
    }

    // Faithful port of Translator::TranslateIntrinsicCall
    // (cangjie_compiler/src/CHIR/AST2CHIR/TranslateASTNode/TranslateCallExpr.cpp:515).
    // A CallExpr whose callKind is CALL_INTRINSIC_FUNCTION is lowered to a CHIR Intrinsic
    // expression (carrying the IntrinsicKind + args), instead of an Apply to a symbol. The
    // intrinsic func decl itself is intentionally not collected (FaithfulAST2CHIR.cj:442/606,
    // mirroring ASTPackage2CHIR.cpp:230/538), so codegen dispatches via the intrinsic kind.
    private func TranslateIntrinsicCall(expr: AstCallExpr): Option<Value> {
        // Conditions to check if this is a call to intrinsic
        if (expr.callKind != AstCallKind.CALL_INTRINSIC_FUNCTION) {
            return None
        }
        let base = RequireExpr(expr.baseFunc, "intrinsic call base")
        let target = base.GetTarget() ??
            throw IllegalStateException("faithful AST2CHIR intrinsic call base has no target")
        let identifier = target.identifier.Val()
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))

        // Get the intrinsic kind. Determine the package the intrinsic was declared in, mirroring
        // the C++ ordering: generic decl's package, else outer decl's generic package, else the
        // target's own package. Headless intrinsics are resolved first inside LookupPackageIntrinsicKind.
        let packageName = if (let Some(genericDecl) <- target.genericDecl) {
            genericDecl.fullPackageName
        } else if (let Some(outerDecl) <- target.outerDecl) {
            if (let Some(outerGenericDecl) <- outerDecl.genericDecl) {
                outerGenericDecl.fullPackageName
            } else {
                target.fullPackageName
            }
        } else {
            target.fullPackageName
        }
        let intrinsicKind = LookupPackageIntrinsicKind(packageName, identifier) ?? IntrinsicKind.NOT_INTRINSIC

        // Translate arguments (mirrors TranslateFuncArgs(expr, nullptr, nullptr)): generate the
        // `this` object first for a non-static member intrinsic, then the explicit args with no
        // expected-type coercion.
        let args = ArrayList<Value>()
        let previousDefaultArgs = ArrayList<Value>()
        if (let Some(callee) <- expr.resolvedFunction) {
            if (callee.IsMemberDecl() && !callee.TestAttr(AstAttribute.CONSTRUCTOR) &&
                !callee.TestAttr(AstAttribute.STATIC)) {
                let thisObj = TranslateThisObjectForMemberFuncCall(expr, callee)
                args.add(thisObj)
                previousDefaultArgs.add(thisObj)
            }
        }
        if (let Some(callee) <- expr.resolvedFunction) {
            AppendTranslatedCallArgs(expr, callee, args, ArrayList<Type>(), previousDefaultArgs)
        } else {
            for (arg in ActiveCallArgs(expr)) {
                args.add(TranslateTrivialArgWithNoSugar(arg, None))
            }
        }

        var retTy = resultTy
        if (intrinsicKind == IntrinsicKind.BLACK_BOX && !args.isEmpty()) {
            // intrinsic blackBox's signature is blackBox<T>(v: T): T;
            // args need to be converted into reference types to control variable lifetimes.
            BlackBoxModifyArgTypeToRef(args)
            retTy = args[0].GetType() ?? retTy
        }

        let instTypeArgs = ArrayList<Type>()
        if (let Some(nameRef) <- (base as AstNameReferenceExpr)) {
            for (instTy in nameRef.instTys) {
                instTypeArgs.add(chirTy.TranslateType(instTy))
            }
        }
        let callContext = IntrisicCallContext(kind: intrinsicKind, args: args, instTypeArgs: instTypeArgs)
        let intriVar = CreateIntrinsicMaybeWithException(retTy, callContext, loc: TranslateLocation(expr))

        if (RequireAstTy(expr).IsUnit()) {
            // Codegen will not generate a valid 'unit' value for intrinsic call.
            return RequireResult(builder.CreateConstant(builder.context.GetUnitTy(), UnitLiteral(), CurrentBlock()))
        }
        if (intrinsicKind == IntrinsicKind.BLACK_BOX && !refEq(retTy, resultTy)) {
            return RequireResult(builder.CreateLoad(resultTy, intriVar, CurrentBlock()))
        }
        return intriVar
    }

    private func CreateIntrinsicMaybeWithException(resultTy: Type, callContext: IntrisicCallContext,
        loc!: DebugLocation = INVALID_LOCATION): Value {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = CreateBlock()
            let exceptionBlock = DelayExitExceptionBlock(errorBlock)
            let term = if (let Some(exceptBlock) <- exceptionBlock) {
                builder.CreateIntrinsicWithException(resultTy, callContext, successBlock, exceptBlock,
                    CurrentBlock())
            } else {
                builder.CreateIntrinsicWithException(resultTy, callContext, successBlock, errorBlock,
                    CurrentBlock())
            }
            term.SetDebugLocation(loc)
            let result = RequireResult(term)
            FinishDelayExitExceptionBlock(exceptionBlock, successBlock)
            return result
        }
        let intrinsic = builder.CreateIntrinsic(resultTy, callContext, CurrentBlock())
        intrinsic.SetDebugLocation(loc)
        return RequireResult(intrinsic)
    }

    private func TranslateExprArg(expr: AstExpr): Value {
        if (let Some(value) <- Translator.TranslateASTNode(expr, this)) {
            return value
        }
        if (RequireAstTy(expr).IsUnit()) {
            return RequireResult(builder.CreateConstant(builder.context.GetUnitTy(), UnitLiteral(), CurrentBlock()))
        }
        return RequireResult(builder.CreateConstant(builder.context.GetNothingType(), NullLiteral(), CurrentBlock()))
    }

    private func TranslateExprArg(node: AstNode, targetTy: Type, deref!: Bool = true): Value {
        var value = Translator.TranslateASTNode(node, this)
        if (targetTy.IsUnit()) {
            return RequireResult(builder.CreateConstant(builder.context.GetUnitTy(), UnitLiteral(), CurrentBlock()))
        }
        if (RequireAstTy(node).IsNothing() || targetTy.IsNothing()) {
            return RequireResult(builder.CreateConstant(builder.context.GetNothingType(), NullLiteral(), CurrentBlock()))
        }
        if (value.isNone()) {
            if (RequireAstTy(node).IsUnit() && !targetTy.IsUnit()) {
                value = Some(RequireResult(builder.CreateConstant(builder.context.GetUnitTy(), UnitLiteral(),
                    CurrentBlock())))
            } else {
                return RequireResult(builder.CreateConstant(builder.context.GetNothingType(), NullLiteral(),
                    CurrentBlock()))
            }
        }
        var result = value.getOrThrow()
        if ((result.GetType() ?? throw IllegalStateException("faithful AST2CHIR value has no type")).IsNothing()) {
            return result
        }
        if (deref) {
            result = GetDerefedValue(result, TranslateLocation(node))
        }
        return TypeCastOrBoxIfNeeded(result, targetTy, TranslateLocation(node))
    }

    private func TranslateTrivialArgWithNoSugar(arg: AstFuncArg, expectedTy: Option<Type>): Value {
        let argExpr = RequireFuncArgExpr(arg, "call argument")
        var value = if (arg.withInout) {
            let argVal = GenerateLeftValue(TranslateExprAsLeftValue(argExpr), chirTy.TranslateType(RequireAstTy(arg)))
            let inoutArgs = ArrayList<Value>()
            inoutArgs.add(argVal)
            RequireResult(builder.CreateIntrinsic(chirTy.TranslateType(RequireAstTy(arg)),
                IntrisicCallContext(kind: IntrinsicKind.INOUT_PARAM, args: inoutArgs), CurrentBlock()))
        } else {
            TranslateExprArg(argExpr)
        }
        if (let Some(targetTy) <- expectedTy) {
            value = TypeCastOrBoxIfNeeded(value, targetTy, INVALID_LOCATION)
        }
        return value
    }

    private func GenerateLeftValue(info: FaithfulLeftValueInfo, expectedTy: Type): Value {
        let base = info.base.getOrThrow()
        if (info.path.isEmpty()) {
            return base
        }
        let baseTy = base.GetType() ??
            throw IllegalStateException("faithful AST2CHIR left value base has no type: ${base.GetIdentifier()}")
        if (baseTy.IsRef()) {
            return RequireResult(builder.CreateGetElementByName(builder.context.GetRefTy(expectedTy), base,
                info.path, CurrentBlock()))
        }
        return RequireResult(builder.CreateFieldByName(expectedTy, base, info.path, CurrentBlock()))
    }

    private func BlackBoxModifyArgTypeToRef(args: ArrayList<Value>): Unit {
        var idx: Int64 = 0
        while (idx < args.size) {
            let arg = args[idx]
            let argTy = arg.GetType() ??
                throw IllegalStateException("faithful AST2CHIR blackBox argument has no type: ${arg.GetIdentifier()}")
            if (argTy.IsRef()) {
                idx++
                continue
            }
            var newArg = arg
            if (let Some(localVar) <- arg.AsLocalVar()) {
                if (let Some(expr) <- localVar.GetExpr()) {
                    if (let Some(load) <- (expr as Load)) {
                        newArg = load.GetLocation()
                        RemoveDeadLoadForBlackBox(load)
                    } else {
                        let argRefType = builder.context.GetRefTy(argTy)
                        newArg = CreateAllocateMaybeWithException(argRefType, argTy)
                        builder.CreateStore(arg, newArg, CurrentBlock())
                    }
                }
            }
            args[idx] = newArg
            idx++
        }
    }

    private func RemoveDeadLoadForBlackBox(load: Load): Unit {
        let result = match (load.GetResult()) {
            case Some(value) => value
            case None => return
        }
        for (user in result.GetUsers()) {
            if (!user.IsDebug()) {
                return
            }
        }
        for (user in result.GetUsers()) {
            if (user.IsDebug()) {
                user.RemoveSelfFromBlock()
            }
        }
        load.RemoveSelfFromBlock()
    }

    private func DefaultValueFuncDecl(calleeDecl: AstFuncDecl, idx: Int64): AstFuncDecl {
        if (let Some(body) <- calleeDecl.funcBody) {
            if (!body.paramLists.isEmpty() && idx < body.paramLists[0].params.size) {
                if (let Some(desugarDecl) <- body.paramLists[0].params[idx].desugarDecl) {
                    return desugarDecl
                }
            }
        }
        throw IllegalStateException("faithful AST2CHIR default argument has no desugared function")
    }

    private func IsStaticInit(funcDecl: AstFuncDecl): Bool {
        return funcDecl.TestAttr(AstAttribute.STATIC) && funcDecl.TestAttr(AstAttribute.CONSTRUCTOR) &&
            funcDecl.identifier.Val() == STATIC_INIT_FUNC
    }

    private func IsStructMutFunction(funcDecl: AstFuncDecl): Bool {
        let outerDecl = match (funcDecl.outerDecl) {
            case Some(value) => value
            case None => return false
        }
        if (outerDecl.astKind == ASTKind.STRUCT_DECL) {
            return funcDecl.TestAnyAttr(AstAttribute.CONSTRUCTOR, AstAttribute.MUT)
        }
        if (outerDecl.astKind == ASTKind.EXTEND_DECL) {
            let extendDecl = (outerDecl as AstExtendDecl).getOrThrow()
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(astTy) <- extendedType.GetTy()) {
                    if (astTy.IsStruct()) {
                        return funcDecl.TestAnyAttr(AstAttribute.CONSTRUCTOR, AstAttribute.MUT)
                    }
                }
            }
        }
        return false
    }

    private func IsCallingConstructor(expr: AstCallExpr): Bool {
        let resolvedFunction = match (expr.resolvedFunction) {
            case Some(value) => value
            case None => return false
        }
        if (expr.callKind == AstCallKind.CALL_SUPER_FUNCTION) {
            return true
        }
        return resolvedFunction.TestAttr(AstAttribute.CONSTRUCTOR) &&
            !resolvedFunction.TestAttr(AstAttribute.STATIC)
    }

    private func GetMemberFuncParamAndRetInstTypes(expr: AstCallExpr,
        calleeDecl: AstFuncDecl): (ArrayList<Type>, Type) {
        let paramInstTys = FuncParamTypes(expr, calleeDecl)
        let retInstTy = if (calleeDecl.TestAttr(AstAttribute.CONSTRUCTOR) || calleeDecl.IsFinalizer()) {
            builder.context.GetUnitTy()
        } else {
            chirTy.TranslateType(CallBaseFuncTy(expr, calleeDecl).retTy)
        }
        return (paramInstTys, retInstTy)
    }

    private func GetMemberFuncCallerInstType(expr: AstCallExpr, needExactTy!: Bool = true): Option<Type> {
        var callerType: Option<Type> = None
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(memAccess) <- (base as AstMemberAccess)) {
                if (!IsPackageMemberAccess(memAccess)) {
                    let baseExpr = RequireExpr(memAccess.baseExpr, "member function caller base")
                    callerType = Some(chirTy.TranslateType(RequireAstTy(baseExpr)))
                } else if (IsCallingConstructor(expr)) {
                    callerType = Some(chirTy.TranslateType(RequireAstTy(expr)))
                }
            } else if (IsCallingConstructor(expr)) {
                callerType = Some(chirTy.TranslateType(RequireAstTy(expr)))
            } else if (let Some(resolvedFunction) <- expr.resolvedFunction) {
                if (let Some(outerDecl) <- resolvedFunction.outerDecl) {
                    if (outerDecl.IsNominalDecl()) {
                        if (let Some(outerDef) <- CurrentFunction().GetParentCustomTypeDef()) {
                            if (let Some(extendDef) <- (outerDef as ExtendDef)) {
                                callerType = extendDef.GetExtendedType()
                            } else {
                                callerType = outerDef.GetType()
                            }
                            if (let Some(curCallerType) <- callerType) {
                                if (curCallerType.IsClassOrArray()) {
                                    callerType = Some(builder.context.GetRefTy(curCallerType))
                                }
                            }
                        } else if (IsStaticInit(resolvedFunction)) {
                            callerType = None
                        } else {
                            callerType = Some(chirTy.TranslateType(RequireAstTy(outerDecl)))
                        }
                    }
                }
            }
        } else if (IsCallingConstructor(expr)) {
            callerType = Some(chirTy.TranslateType(RequireAstTy(expr)))
        }

        if (needExactTy) {
            if (let Some(curCallerType) <- callerType) {
                if (let Some(resolvedFunction) <- expr.resolvedFunction) {
                    var (paramInstTys, retInstTy) = GetMemberFuncParamAndRetInstTypes(expr, resolvedFunction)
                    if (!resolvedFunction.TestAttr(AstAttribute.STATIC)) {
                        paramInstTys.add(curCallerType, at: 0)
                    }
                    let instFuncType = builder.context.GetFuncTy(paramInstTys, retInstTy)
                    let funcInstTypeArgs = ArrayList<Type>()
                    if (let Some(base) <- expr.baseFunc) {
                        if (let Some(nameRef) <- (base as AstNameReferenceExpr)) {
                            if (!resolvedFunction.TestAttr(AstAttribute.CONSTRUCTOR)) {
                                for (instTy in nameRef.instTys) {
                                    funcInstTypeArgs.add(chirTy.TranslateType(instTy))
                                }
                            }
                        }
                    }
                    let root = if (let Some(refTy) <- (curCallerType as RefType)) {
                        refTy.GetBaseType()
                    } else {
                        curCallerType
                    }
                    var exactCallerType = GetExactParentType(root, resolvedFunction, instFuncType,
                        funcInstTypeArgs, false) ??
                        throw IllegalStateException("faithful AST2CHIR member caller has no exact parent type")
                    if (exactCallerType.IsClass()) {
                        exactCallerType = builder.context.GetRefTy(exactCallerType)
                    }
                    callerType = Some(exactCallerType)
                }
            }
        }

        if (let Some(resolvedFunction) <- expr.resolvedFunction) {
            if (IsStructMutFunction(resolvedFunction)) {
                if (let Some(curCallerType) <- callerType) {
                    callerType = Some(builder.context.GetRefTy(curCallerType))
                }
            }
        }
        return callerType
    }

    private func TranslateOneCallArg(expr: AstCallExpr, calleeDecl: AstFuncDecl, arg: AstFuncArg, idx: Int64,
        expectedTy: Option<Type>, previousDefaultArgs: ArrayList<Value>): Value {
        if (arg.TestAttr(AstAttribute.HAS_INITIAL)) {
            let defaultFunc = GetSymbolTable(DefaultValueFuncDecl(calleeDecl, idx))
            let retTy = chirTy.TranslateType(RequireAstTy(arg))
            let instArgs = if (calleeDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
                ArrayList<Type>()
            } else {
                TranslateFuncInstArgs(expr, calleeDecl)
            }
            var value = CreateApplyMaybeWithException(retTy, defaultFunc,
                FuncCallContext(args: previousDefaultArgs.clone(), instTypeArgs: instArgs,
                    thisType: GetMemberFuncCallerInstType(expr)), loc: TranslateLocation(expr))
            if (let Some(targetTy) <- expectedTy) {
                value = CoerceValueForExpectedType(value, targetTy)
            }
            return value
        }
        return TranslateTrivialArgWithNoSugar(arg, expectedTy)
    }

    private func AppendTranslatedCallArgs(expr: AstCallExpr, calleeDecl: AstFuncDecl, out: ArrayList<Value>,
        expectedParamTys: ArrayList<Type>, previousDefaultArgs: ArrayList<Value>): Unit {
        let args = ActiveCallArgs(expr)
        var idx: Int64 = 0
        for (arg in args) {
            let value = if (idx < expectedParamTys.size) {
                TranslateOneCallArg(expr, calleeDecl, arg, idx, Some(expectedParamTys[idx]), previousDefaultArgs)
            } else {
                TranslateOneCallArg(expr, calleeDecl, arg, idx, None, previousDefaultArgs)
            }
            out.add(value)
            previousDefaultArgs.add(value)
            idx++
        }
    }

    // C++ CHIR Translator::TranslateCFuncConstructorCall (TranslateCallExpr.cpp:756): a builtin
    // `CFunc<T>(p)` constructor reinterprets its single argument as the CFunc type. The base is the
    // CFUNC builtin decl (no resolvedFunction / not a FuncDecl), so it must be handled before the
    // function-value-call path, which would otherwise try to look the `CFunc` base up in the symbol
    // table. Translate the single argument, deref it and cast it to the call's CFunc result type --
    // exactly C++ TranslateExprArg(arg, TranslateType(ce.GetTy()), /*deref=*/true).
    private func TranslateCFuncConstructorCall(expr: AstCallExpr): Option<Value> {
        if (!IsValidCFuncConstructorCall(expr)) {
            return None
        }
        let arg = RequireFuncArgExpr(expr.args[0], "CFunc constructor argument")
        let targetTy = chirTy.TranslateType(RequireAstTy(expr))
        let value = TranslateExprArg(arg, targetTy, deref: true)
        return Some(value)
    }

    // C++ CHIR Translator::TranslateCStringCtorCall (TranslateCallExpr.cpp:606): a builtin
    // `CString(p)` constructor lowers to a CSTRING_INIT intrinsic over its single argument. Its base
    // is the CSTRING builtin decl (no resolvedFunction / not a FuncDecl), so like the CFunc
    // constructor it must be handled before the function-value-call path.
    private func TranslateCStringCtorCall(expr: AstCallExpr): Option<Value> {
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(target) <- base.GetTarget()) {
                if (let Some(builtinDecl) <- (target as BuiltInDecl)) {
                    if (builtinDecl.IsType(BuiltInType.CSTRING)) {
                        let ty = chirTy.TranslateType(RequireAstTy(expr))
                        let arg = RequireFuncArgExpr(expr.args[0], "CString constructor argument")
                        let args = ArrayList<Value>()
                        args.add(TranslateExprArg(arg))
                        return Some(RequireResult(builder.CreateIntrinsic(ty,
                            IntrisicCallContext(kind: IntrinsicKind.CSTRING_INIT, args: args), CurrentBlock())))
                    }
                }
            }
        }
        return None
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
            if (arg.expr.isSome()) {
                var value = TranslateTrivialArgWithNoSugar(arg, None)
                if (idx < baseFuncTy.paramTys.size) {
                    value = CoerceValueForExpectedType(value, chirTy.TranslateType(baseFuncTy.paramTys[idx]))
                }
                argValues.add(value)
            }
            idx++
        }
        return CreateApplyMaybeWithException(chirTy.TranslateType(RequireAstTy(expr)), callee,
            FuncCallContext(args: argValues), loc: TranslateLocation(expr))
    }

    private func CreateInvokeMaybeWithException(resultTy: Type, callContext: InvokeCallContext,
        loc!: DebugLocation = INVALID_LOCATION): Value {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = CreateBlock()
            let exceptionBlock = DelayExitExceptionBlock(errorBlock)
            let term = if (let Some(exceptBlock) <- exceptionBlock) {
                builder.CreateInvokeWithException(resultTy, callContext, successBlock, exceptBlock, CurrentBlock())
            } else {
                builder.CreateInvokeWithException(resultTy, callContext, successBlock, errorBlock, CurrentBlock())
            }
            term.SetDebugLocation(loc)
            let result = RequireResult(term)
            FinishDelayExitExceptionBlock(exceptionBlock, successBlock)
            return result
        }
        let invoke = builder.CreateInvoke(resultTy, callContext, CurrentBlock())
        invoke.SetDebugLocation(loc)
        return RequireResult(invoke)
    }

    private func CreateInvokeStaticMaybeWithException(resultTy: Type, callContext: InvokeCallContext,
        loc!: DebugLocation = INVALID_LOCATION): Value {
        if (let Some(errorBlock) <- CurrentTryCatchBlock()) {
            let successBlock = CreateBlock()
            let exceptionBlock = DelayExitExceptionBlock(errorBlock)
            let term = if (let Some(exceptBlock) <- exceptionBlock) {
                builder.CreateInvokeStaticWithException(resultTy, callContext, successBlock, exceptBlock,
                    CurrentBlock())
            } else {
                builder.CreateInvokeStaticWithException(resultTy, callContext, successBlock, errorBlock,
                    CurrentBlock())
            }
            term.SetDebugLocation(loc)
            let result = RequireResult(term)
            FinishDelayExitExceptionBlock(exceptionBlock, successBlock)
            return result
        }
        let invoke = builder.CreateInvokeStatic(resultTy, callContext, CurrentBlock())
        invoke.SetDebugLocation(loc)
        return RequireResult(invoke)
    }

    private func FuncParamTypes(expr: AstCallExpr, calleeDecl: AstFuncDecl,
        thisType!: Option<Type> = None): ArrayList<Type> {
        let out = ArrayList<Type>()
        let funcTy = CallBaseFuncTy(expr, calleeDecl)
        let genericParams = TranslateFuncGenericParams(calleeDecl)
        let replacements = TranslateFuncInstArgs(expr, calleeDecl)
        AddMemberOwnerGenericReplacements(calleeDecl, thisType, genericParams, replacements)
        for (paramTy in funcTy.paramTys) {
            out.add(SubstituteGenericType(chirTy.TranslateType(paramTy), genericParams, replacements))
        }
        return out
    }

    private func AddMemberOwnerGenericReplacements(calleeDecl: AstFuncDecl, thisType: Option<Type>,
        genericParams: ArrayList<GenericType>, replacements: ArrayList<Type>): Unit {
        let outer = match (calleeDecl.outerDecl) {
            case Some(value) => value
            case None => return
        }
        if (!outer.IsNominalDecl()) {
            return
        }
        let generic = match (outer.GetGeneric()) {
            case Some(value) => value
            case None => return
        }
        let receiverTy = match (thisType) {
            case Some(value2) => value2
            case None => return
        }
        let receiverCustom = match (receiverTy.StripAllRefs() as CustomType) {
            case Some(value3) => value3
            case None => return
        }
        let receiverArgs = receiverCustom.GetGenericArgs()
        var idx: Int64 = 0
        while (idx < generic.typeParameters.size && idx < receiverArgs.size) {
            match (generic.typeParameters[idx].GetTy()) {
                case Some(paramTy) =>
                    match (chirTy.TranslateType(paramTy) as GenericType) {
                        case Some(genericTy) =>
                            genericParams.add(genericTy)
                            replacements.add(receiverArgs[idx])
                        case None => ()
                    }
                case None => ()
            }
            idx++
        }
    }

    private func TranslateEnumCtorRef(constructor: AstDecl, astTy: AstTy): Value {
        let enumType = chirTy.TranslateType(astTy)
        let outer = constructor.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR enum constructor has no outer enum")
        let enumDecl = (outer as AstEnumDecl) ??
            throw IllegalStateException("faithful AST2CHIR enum constructor outer is not enum")
        let selector = CreateEnumSelectorConstant(constructor)
        if (enumDecl.hasArguments) {
            let args = ArrayList<Value>()
            args.add(selector)
            return RequireResult(builder.CreateTuple(enumType, args, CurrentBlock()))
        }
        return RequireResult(builder.CreateTypeCast(enumType, selector, CurrentBlock()))
    }

    // The instantiated this-type for a member call, taken from the base expression's (sema-resolved) type,
    // mirroring C++ GetInstCalleeInfoFromMemberAccess (TranslateMemberAccess.cpp:272). Returns None when the base
    // is not a member access or its type is unresolved, so the caller can fall back to the this-object's type.
    private func MemberCallInstantiatedThisType(expr: AstCallExpr, funcDecl: AstFuncDecl): Option<Type> {
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(member) <- (base as AstMemberAccess)) {
                if (let Some(baseExpr) <- member.baseExpr) {
                    if (let Some(astTy) <- baseExpr.GetTy()) {
                        if (AstTy.IsTyCorrect(astTy)) {
                            return Some(AddRefIfFuncIsMutOrClass(chirTy.TranslateType(astTy), funcDecl))
                        }
                    }
                }
            }
        }
        return None
    }

    private func TranslateMemberFuncCall(expr: AstCallExpr, calleeDecl: AstFuncDecl): Value {
        let loc = TranslateLocation(expr)
        let resultTy = chirTy.TranslateType(RequireAstTy(expr))
        let argValues = ArrayList<Value>()
        let callee = globalSymbolTable.Get(calleeDecl)
        var thisType: Option<Type> = if (calleeDecl.TestAttr(AstAttribute.STATIC)) {
            MemberCallInstantiatedThisType(expr, calleeDecl)
        } else {
            None
        }
        var dispatchReceiverType: Option<Type> = None
        var funcCallThisType: Option<Type> = None
        var thisObj: Option<Value> = None
        if (!calleeDecl.TestAttr(AstAttribute.STATIC)) {
            let rawObj = TranslateThisObjectForMemberFuncCall(expr, calleeDecl)
            dispatchReceiverType = rawObj.GetType()
            funcCallThisType = rawObj.GetType()
            let obj = CoerceThisObjectForCallee(calleeDecl, callee, rawObj)
            thisObj = obj
            thisType = obj.GetType()
            // For a builtin generic owner (CPointer<T>/CFunc<T>/VArray<T>) whose generic parameter is not exposed
            // through outerDecl.GetGeneric(), CoerceThisObjectForCallee generifies the concrete receiver, leaving
            // the coerced this-object (and hence the Apply's this-type) uninstantiated, which breaks runtime-TypeInfo
            // lowering. In exactly that case, recover the instantiated this-type from the base expression, mirroring
            // C++ GetInstCalleeInfoFromMemberAccess (TranslateMemberAccess.cpp:272). Normal calls keep the coerced
            // this-object type unchanged.
            if (let Some(coercedTy) <- thisType) {
                if (coercedTy.StripAllRefs().IsGenericRelated()) {
                    if (let Some(faithful) <- MemberCallInstantiatedThisType(expr, calleeDecl)) {
                        if (!faithful.StripAllRefs().IsGenericRelated()) {
                            thisType = Some(faithful)
                        }
                    }
                }
            }
        }
        let expectedParamTys = FuncParamTypes(expr, calleeDecl, thisType: thisType)
        let previousDefaultArgs = ArrayList<Value>()
        if (let Some(obj) <- thisObj) {
            previousDefaultArgs.add(obj)
        }
        AppendTranslatedCallArgs(expr, calleeDecl, argValues, expectedParamTys, previousDefaultArgs)
        if (ShouldUseVirtualMemberDispatchForCall(expr, calleeDecl, dispatchReceiverType)) {
            if (calleeDecl.TestAttr(AstAttribute.STATIC)) {
                let parentTy = thisType ?? TranslateMemberOwnerType(calleeDecl)
                let rtti = RequireResult(builder.CreateGetRTTIStatic(builder.context.GetUnitTy(),
                    parentTy.StripAllRefs(), CurrentBlock()))
                let instTypeArgs = TranslateFuncInstArgs(expr, calleeDecl)
                let invokeCtx = InvokeCallContext(rtti, FuncCallContext(args: argValues,
                    instTypeArgs: instTypeArgs, thisType: parentTy),
                    FuncSigInfo(BuildMethodFuncTypeForMemberAccess(calleeDecl), funcName: calleeDecl.identifier.Val()))
                let invoke = CreateInvokeStaticMaybeWithException(resultTy, invokeCtx, loc: loc)
                if (HasNothingTypeArg(argValues)) {
                    invoke.AsLocalVar().getOrThrow().GetExpr().getOrThrow().SetDebugLocationInfoForWarning(TranslateLocation(
                        RequireExpr(expr.baseFunc, "member call base")))
                }
                return invoke
            }
            let obj = thisObj ?? throw IllegalStateException("faithful AST2CHIR virtual member call has no this object")
            let objTy = thisType ?? throw IllegalStateException("faithful AST2CHIR virtual member call this has no type")
            let callThisTy = funcCallThisType ?? objTy
            let instTypeArgs = TranslateFuncInstArgs(expr, calleeDecl)
            let invokeCtx = InvokeCallContext(obj, FuncCallContext(args: argValues,
                instTypeArgs: instTypeArgs, thisType: callThisTy),
                FuncSigInfo(BuildMethodFuncTypeForMemberAccess(calleeDecl), funcName: calleeDecl.identifier.Val()))
            let invoke = CreateInvokeMaybeWithException(resultTy, invokeCtx, loc: loc)
            if (HasNothingTypeArg(argValues)) {
                invoke.AsLocalVar().getOrThrow().GetExpr().getOrThrow().SetDebugLocationInfoForWarning(TranslateLocation(
                    RequireExpr(expr.baseFunc, "member call base")))
            }
            return invoke
        }
        if (let Some(obj) <- thisObj) {
            argValues.add(obj, at: 0)
        }
        let instTypeArgs = TranslateFuncInstArgs(expr, calleeDecl)
        let applyThisType = match (funcCallThisType) {
            case Some(value) => Some(value)
            case None => thisType
        }
        return CreateApplyMaybeWithException(resultTy, callee, FuncCallContext(args: argValues,
            instTypeArgs: instTypeArgs, thisType: applyThisType), loc: loc)
    }

    private func TranslateFuncInstArgs(expr: AstCallExpr, calleeDecl: AstFuncDecl): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (calleeDecl.TestAttr(AstAttribute.CONSTRUCTOR)) {
            return out
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
            return builder.context.GetRefTy(SubstituteGenericType(refTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            return builder.context.GetRawArrayTy(SubstituteGenericType(rawArrayTy.GetElementType(), genericParams, replacements),
                dims: rawArrayTy.GetDims())
        }
        if (let Some(varrayTy) <- (ty as VArrayType)) {
            return builder.context.GetVArrayTy(SubstituteGenericType(varrayTy.GetElementType(), genericParams, replacements),
                varrayTy.size)
        }
        if (let Some(pointerTy) <- (ty as CPointerType)) {
            return builder.context.GetCPointerTy(SubstituteGenericType(pointerTy.GetElementType(), genericParams, replacements))
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return builder.context.GetBoxTy(SubstituteGenericType(boxTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            return builder.context.GetTupleTy(SubstituteGenericTypeArgs(tupleTy.GetTypeArgs(), genericParams, replacements))
        }
        if (let Some(funcTy) <- (ty as FuncType)) {
            let params = SubstituteGenericTypeArgs(funcTy.GetParamTypes(), genericParams, replacements)
            let retTy = SubstituteGenericType(funcTy.GetReturnType(), genericParams, replacements)
            return builder.context.GetFuncTy(params, retTy, hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
        }
        if (let Some(structTy) <- (ty as StructType)) {
            return builder.context.GetStructTy(structTy.GetStructDef(),
                SubstituteGenericTypeArgs(structTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            return builder.context.GetClassTy(classTy.GetClassDef(),
                SubstituteGenericTypeArgs(classTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(enumTy) <- (ty as EnumType)) {
            return builder.context.GetEnumTy(enumTy.GetEnumDef(),
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
        var thisObj: Value
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(member) <- (base as AstMemberAccess)) {
                if (let Some(baseExpr) <- member.baseExpr) {
                    if (IsThisOrSuperRef(baseExpr)) {
                        thisObj = GetCurrentThisObjectForMember(calleeDecl)
                        return NormalizeThisObjectForNonStaticMemberFuncCall(thisObj,
                            calleeDecl.TestAttr(AstAttribute.MUT))
                    }
                    if (calleeDecl.TestAttr(AstAttribute.MUT)) {
                        let leftValue = TranslateExprAsLeftValue(baseExpr)
                        if (leftValue.path.isEmpty()) {
                            thisObj = leftValue.base.getOrThrow()
                        } else {
                            thisObj = LoadLeftValue(leftValue, chirTy.TranslateType(RequireAstTy(baseExpr))) ??
                                throw IllegalStateException("faithful AST2CHIR mut member call base produced no value")
                        }
                        return NormalizeThisObjectForNonStaticMemberFuncCall(thisObj,
                            calleeDecl.TestAttr(AstAttribute.MUT))
                    }
                    thisObj = Translator.TranslateASTNode(baseExpr, this) ??
                        throw IllegalStateException("faithful AST2CHIR member call base produced no value")
                    return NormalizeThisObjectForNonStaticMemberFuncCall(thisObj,
                        calleeDecl.TestAttr(AstAttribute.MUT))
                }
            }
        }
        thisObj = GetCurrentThisObjectForMember(calleeDecl)
        return NormalizeThisObjectForNonStaticMemberFuncCall(thisObj, calleeDecl.TestAttr(AstAttribute.MUT))
    }

    private func NormalizeThisObjectForNonStaticMemberFuncCall(rawThisObj: Value, needsMutableThis: Bool): Value {
        let rawThisObjTy = rawThisObj.GetType() ??
            throw IllegalStateException("faithful AST2CHIR this object has no type: ${rawThisObj.GetIdentifier()}")
        if (!(rawThisObjTy.IsReferenceTypeWithRefDims(CLASS_REF_DIM) ||
            rawThisObjTy.IsReferenceTypeWithRefDims(1) ||
            rawThisObjTy.IsValueOrGenericTypeWithRefDims(1) ||
            rawThisObjTy.IsValueOrGenericTypeWithRefDims(0))) {
            throw IllegalStateException("faithful AST2CHIR unsupported this object type: ${rawThisObjTy.ToString()}")
        }
        var thisObj = rawThisObj
        if (!needsMutableThis) {
            if (rawThisObjTy.IsReferenceTypeWithRefDims(CLASS_REF_DIM) ||
                rawThisObjTy.IsValueOrGenericTypeWithRefDims(1)) {
                let pureThisObjTy = rawThisObjTy.StripAllRefs()
                var targetTy = pureThisObjTy
                if (pureThisObjTy.IsReferenceType()) {
                    targetTy = builder.context.GetRefTy(pureThisObjTy)
                }
                thisObj = RequireResult(builder.CreateLoad(targetTy, rawThisObj, CurrentBlock()))
            }
        } else {
            if (rawThisObjTy.IsValueOrGenericTypeWithRefDims(0)) {
                throw IllegalStateException("faithful AST2CHIR mutable this object is not a reference: ${rawThisObjTy.ToString()}")
            }
            if (rawThisObjTy.IsReferenceTypeWithRefDims(CLASS_REF_DIM)) {
                let pureThisObjTy = rawThisObjTy.StripAllRefs()
                let targetTy = builder.context.GetRefTy(pureThisObjTy)
                thisObj = RequireResult(builder.CreateLoad(targetTy, rawThisObj, CurrentBlock()))
            }
        }
        return thisObj
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

    private func ShouldUseVirtualMemberDispatchForCall(expr: AstCallExpr, funcDecl: AstFuncDecl,
        receiverTy: Option<Type>): Bool {
        if (!ShouldUseVirtualMemberDispatch(funcDecl)) {
            return false
        }
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(member) <- (base as AstMemberAccess)) {
                if (let Some(baseExpr) <- member.baseExpr) {
                    if (let Some(refExpr) <- (baseExpr as AstRefExpr)) {
                        if (refExpr.isSuper) {
                            return false
                        }
                    }
                    let baseTy = chirTy.TranslateType(RequireAstTy(baseExpr)).StripAllRefs()
                    if (baseTy.IsCustomType() && funcDecl.TestAttr(AstAttribute.STATIC)) {
                        return false
                    }
                }
            }
        }
        if (funcDecl.TestAttr(AstAttribute.STATIC)) {
            if (let Some(callerDef) <- CurrentFunction().GetOuterDeclaredOrExtendedDef()) {
                if (let Some(classDef) <- (callerDef as ClassDef)) {
                    if (!classDef.IsInterface() && !classDef.CanBeInherited()) {
                        return false
                    }
                }
            }
            return true
        }
        if (let Some(ty) <- receiverTy) {
            if (let Some(classTy) <- (ty.StripAllRefs() as ClassType)) {
                let classDef = classTy.GetClassDef()
                if (!classDef.IsInterface() && !classDef.CanBeInherited()) {
                    return false
                }
            }
        }
        return true
    }

    private func TranslateMemberOwnerType(funcDecl: AstFuncDecl): Type {
        let outer = funcDecl.outerDecl ??
            throw IllegalStateException("faithful AST2CHIR member function has no owner decl")
        return chirTy.TranslateType(RequireAstTy(outer))
    }

    private func IsThisOrSuperRef(expr: AstExpr): Bool {
        if (let Some(refExpr) <- (expr as AstRefExpr)) {
            return refExpr.isThis || refExpr.isSuper
        }
        return false
    }

    private func TranslateStructOrClassCtorCall(expr: AstCallExpr, calleeDecl: AstFuncDecl): Value {
        let loc = TranslateLocation(expr)
        let thisTy = chirTy.TranslateType(RequireAstTy(expr)).StripAllRefs()
        let thisRefTy = builder.context.GetRefTy(thisTy)
        let userArgs = ArrayList<Value>()
        let expectedParamTys = FuncParamTypes(expr, calleeDecl, thisType: Some(thisRefTy))
        AppendTranslatedCallArgs(expr, calleeDecl, userArgs, expectedParamTys, ArrayList<Value>())
        let thisObj = if (IsSuperOrThisCtorCall(expr)) {
            CastValueIfNeeded(GetCurrentConstructorThisObject(), thisRefTy)
        } else {
            let allocated = CreateAllocateMaybeWithException(thisRefTy, thisTy, loc: loc)
            allocated.AsLocalVar().getOrThrow().GetExpr().getOrThrow().SetDebugLocationInfoForWarning(loc)
            allocated
        }
        let args = ArrayList<Value>()
        args.add(thisObj)
        for (arg in userArgs) {
            args.add(arg)
        }
        let callee = globalSymbolTable.Get(calleeDecl)
        let _ = CreateAndAppendApplyCallFromCallExpr(builder.context.GetUnitTy(), callee,
            FuncCallContext(args: args, thisType: thisRefTy), expr)
        if (let Some(outerDecl) <- calleeDecl.outerDecl) {
            if (outerDecl.astKind == ASTKind.STRUCT_DECL) {
                let load = builder.CreateLoad(thisTy, thisObj, CurrentBlock())
                load.SetDebugLocation(loc)
                return RequireResult(load)
            }
        }
        return thisObj
    }

    private func GetCurrentConstructorThisObject(): Value {
        let fn = CurrentFunction()
        if (fn.GetNumOfParams() > 0) {
            return fn.GetParam(0)
        }
        throw IllegalStateException("faithful AST2CHIR constructor call requires current this object")
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
        if (expr.callKind == AstCallKind.CALL_SUPER_FUNCTION) {
            return true
        }
        if (let Some(base) <- expr.baseFunc) {
            if (let Some(refExpr) <- (base as AstRefExpr)) {
                return refExpr.isThis
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
            if (refEq(ctor, constructor)) {
                return idx
            }
            idx++
        }
        throw IllegalStateException("faithful AST2CHIR enum constructor not found: ${constructor.identifier.Val()}")
    }

    private func FlattenVarWithPatternDecl(pattern: AstPattern, initValue: Option<Value>,
        isLocalPattern!: Bool = true): Unit {
        if (let Some(varPattern) <- (pattern as AstVarPattern)) {
            HandleVarWithVarPattern(varPattern, initValue, isLocalPattern: isLocalPattern)
            return
        }
        if (let Some(tuplePattern) <- (pattern as AstTuplePattern)) {
            HandleTupleOrEnumPatternDecl(tuplePattern, tuplePattern.patterns, initValue,
                isLocalPattern: isLocalPattern)
            return
        }
        if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
            HandleTupleOrEnumPatternDecl(enumPattern, enumPattern.patterns, initValue, isLocalPattern: isLocalPattern)
            return
        }
        if (let Some(_) <- (pattern as AstWildcardPattern)) {
            return
        }
        throw IllegalArgumentException(
            "faithful AST2CHIR unsupported var-with-pattern: ${ASTKindName(pattern.astKind)}")
    }

    private func HandleVarWithVarPattern(pattern: AstVarPattern, initValue: Option<Value>,
        isLocalPattern!: Bool = true): Unit {
        let varDecl = pattern.varDecl ??
            throw IllegalStateException("faithful AST2CHIR var pattern has no VarDecl")
        var leftValue = TranslateLeftValueOfVarDecl(varDecl, initValue.isNone(), isLocalPattern)
        if (let Some(value) <- initValue) {
            let storedValue = StoreRValueToLValue(varDecl, value, leftValue)
            leftValue = Some(storedValue)
            if (let Some(globalVar) <- (storedValue as GlobalVar)) {
                let initFunc = GetTopLevelFunc(value)
                globalVar.SetInitFunc(initFunc)
            }
        }
        SetSymbolTable(varDecl, leftValue ??
            throw IllegalStateException("faithful AST2CHIR var pattern has no left value"))
    }

    private func GetTopLevelFunc(value: Value): Function {
        if (let Some(parameter) <- value.AsParameter()) {
            return parameter.GetTopLevelFunc().getOrThrow()
        } else if (let Some(localVar) <- value.AsLocalVar()) {
            return localVar.GetTopLevelFunc().getOrThrow()
        } else if (let Some(block) <- value.AsBlock()) {
            return block.GetTopLevelFunc().getOrThrow()
        } else if (let Some(blockGroup) <- value.AsBlockGroup()) {
            return blockGroup.GetTopLevelFunc().getOrThrow()
        }
        throw IllegalStateException("GetTopLevelFunc called with unsupported value kind")
    }

    private func HandleTupleOrEnumPatternDecl(pattern: AstPattern, subPatterns: ArrayList<AstPattern>,
        initValue: Option<Value>, isLocalPattern!: Bool = true): Unit {
        let isEnumPattern = pattern.astKind == ASTKind.ENUM_PATTERN
        var leftValue: Option<Value> = None
        if (let Some(value) <- initValue) {
            leftValue = Some(CastValueIfNeeded(GetDerefedValue(value), chirTy.TranslateType(RequireAstTy(pattern))))
        }
        var idx: Int64 = 0
        for (subPattern in subPatterns) {
            var fieldValue: Option<Value> = None
            if (let Some(value) <- leftValue) {
                let baseValue = if (isEnumPattern) {
                    let enumPattern = (pattern as AstEnumPattern) ??
                        throw IllegalStateException("faithful AST2CHIR enum pattern has wrong AST kind")
                    CastEnumValueToConstructorTupleType(value, enumPattern)
                } else {
                    value
                }
                let path = ArrayList<UInt64>()
                path.add(UInt64(if (isEnumPattern) { idx + 1 } else { idx }))
                fieldValue = RequireResult(builder.CreateField(chirTy.TranslateType(RequireAstTy(subPattern)),
                    GetDerefedValue(baseValue), path, CurrentBlock()))
            }
            FlattenVarWithPatternDecl(subPattern, fieldValue, isLocalPattern: isLocalPattern)
            idx++
        }
    }

    private func TranslateTrivialAssign(expr: AstAssignExpr, leftExpr: AstExpr, rightExpr: AstExpr): Option<Value> {
        let loc = TranslateLocation(expr)
        var rhs: Value
        var path = ArrayList<String>()
        var lhs: Option<Value> = None
        if (leftExpr.mapExpr.isSome()) {
            let info = TranslateExprAsLeftValue(leftExpr)
            lhs = info.base
            path = info.path
            if (!path.isEmpty()) {
                let base = info.base.getOrThrow()
                let memberRef = RequireResult(
                    builder.CreateGetElementByName(builder.context.GetRefTy(chirTy.TranslateType(RequireAstTy(leftExpr))),
                        base, path, CurrentBlock()))
                exprValueTable[leftExpr.objectId] = memberRef
            }
            rhs = Translator.TranslateASTNode(rightExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR assign rhs produced no value")
        } else {
            rhs = Translator.TranslateASTNode(rightExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR assign rhs produced no value")
            let info = TranslateExprAsLeftValue(leftExpr)
            lhs = info.base
            path = info.path
        }
        if (lhs.isNone()) {
            return None
        }
        let lhsValue = lhs.getOrThrow()
        if (!path.isEmpty()) {
            CreateAndAppendWrappedStoreElementByName(loc, rhs, lhsValue, path)
        } else {
            CreateAndAppendWrappedStore(rhs, lhsValue, loc)
        }
        return None
    }

    private func TranslateCompoundAssign(expr: AstAssignExpr, leftExpr: AstExpr, rightExpr: AstExpr): Option<Value> {
        let leftValueInfo = TranslateExprAsLeftValue(leftExpr)
        let lhsValue = LoadLeftValue(leftValueInfo, chirTy.TranslateType(RequireAstTy(leftExpr))) ??
            throw IllegalStateException("faithful AST2CHIR compound lhs produced no value")
        var compoundValue: Value
        if (expr.op == AstTokenKind.AND_ASSIGN) {
            compoundValue = TransShortCircuitAnd(lhsValue, rightExpr) ??
                throw IllegalStateException("faithful AST2CHIR compound &&= produced no value")
        } else if (expr.op == AstTokenKind.OR_ASSIGN) {
            compoundValue = TransShortCircuitOr(lhsValue, rightExpr) ??
                throw IllegalStateException("faithful AST2CHIR compound ||= produced no value")
        } else {
            let rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR compound rhs produced no value")
            let opResult = builder.CreateBinaryExpression(ToCHIRCompoundAssignOp(expr.op),
                lhsValue.GetType() ?? chirTy.TranslateType(RequireAstTy(leftExpr)), lhsValue, rhsValue, CurrentBlock(),
                overflowStrategy: expr.overflowStrategy)
            compoundValue = RequireResult(opResult)
        }
        StoreToLeftValue(leftValueInfo, compoundValue)
        return None
    }

    private func TranslatePropertySetterAssign(assign: AstAssignExpr, leftExpr: AstExpr, rightExpr: AstExpr): Bool {
        if (IsCompoundAssignOp(assign.op)) {
            return false
        }
        let target = leftExpr.GetTarget() ?? return false
        let propDecl = (target as AstPropDecl) ?? return false
        if (!propDecl.isVar || propDecl.setters.isEmpty()) {
            return false
        }
        let setter = propDecl.setters[0]
        let callee = GetSymbolTable(setter)
        let args = ArrayList<Value>()
        var thisTy: Option<Type> = None
        if (let Some(memberAccess) <- (leftExpr as AstMemberAccess)) {
            let baseExpr = RequireExpr(memberAccess.baseExpr, "property setter base")
            let baseInfo = TranslateExprAsLeftValue(baseExpr)
            let baseTy = chirTy.TranslateType(RequireAstTy(baseExpr))
            let thisObj = TranslatePropertySetterThisObject(setter, callee, baseInfo, baseTy)
            thisTy = thisObj.GetType()
            args.add(thisObj)
        }
        var rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
            throw IllegalStateException("faithful AST2CHIR property setter rhs produced no value")
        let expectedParamTys = FuncDeclParamTypes(setter)
        if (!expectedParamTys.isEmpty() && !expectedParamTys[0].IsGeneric()) {
            rhsValue = CoerceValueForExpectedType(rhsValue, expectedParamTys[0])
        }
        args.add(rhsValue)
        let _ = CreateApplyMaybeWithException(builder.context.GetUnitTy(), callee,
            FuncCallContext(args: args, thisType: thisTy))
        return true
    }

    private func TranslatePropertySetterThisObject(funcDecl: AstFuncDecl, callee: Value,
        baseInfo: FaithfulLeftValueInfo, baseTy: Type): Value {
        return TranslateSubscriptSetterThisObject(funcDecl, callee, baseInfo, baseTy)
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
            let thisObj = TranslateSubscriptSetterThisObject(setter, callee, baseInfo, baseTy)
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

    private func TranslateSubscriptSetterThisObject(funcDecl: AstFuncDecl, callee: Value,
        baseInfo: FaithfulLeftValueInfo, baseTy: Type): Value {
        let address = AddressOfLeftValue(baseInfo, baseTy)
        if (let Some(expectedTy) <- ExpectedThisParamType(funcDecl, callee, address.GetType() ?? baseTy)) {
            if (expectedTy.IsClassRef()) {
                let loaded = LoadLeftValue(baseInfo, baseTy) ??
                    throw IllegalStateException("faithful AST2CHIR setter class receiver produced no value")
                return CoerceValueForExpectedType(loaded, expectedTy)
            }
            return CoerceValueForExpectedType(address, expectedTy)
        }
        if (let Some(calleeTy) <- callee.GetType()) {
            if (let Some(funcTy) <- (calleeTy as FuncType)) {
                if (funcTy.GetNumOfParams() > 0 && !funcTy.GetParamType(0).IsRef()) {
                    return LoadLeftValue(baseInfo, baseTy) ??
                        throw IllegalStateException("faithful AST2CHIR subscript setter base produced no value")
                }
            }
        }
        return address
    }

    private func CoerceThisObjectForCallee(funcDecl: AstFuncDecl, callee: Value, thisObj: Value): Value {
        if (let Some(thisTy) <- thisObj.GetType()) {
            if (let Some(expectedTy) <- ExpectedThisParamType(funcDecl, callee, thisTy)) {
                return CoerceValueForExpectedType(thisObj, expectedTy)
            }
        }
        return thisObj
    }

    private func ExpectedThisParamType(funcDecl: AstFuncDecl, callee: Value, receiverTy: Type): Option<Type> {
        let calleeTy = callee.GetType() ?? return None
        let funcTy = (calleeTy as FuncType) ?? return None
        if (funcTy.GetNumOfParams() == 0) {
            return None
        }
        let genericParams = TranslateFuncGenericParams(funcDecl)
        let replacements = ArrayList<Type>()
        AddMemberOwnerGenericReplacements(funcDecl, Some(receiverTy), genericParams, replacements)
        return Some(SubstituteGenericType(funcTy.GetParamType(0), genericParams, replacements))
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
        if (subscriptExpr.indexExprs.size != 1) {
            throw IllegalArgumentException("faithful AST2CHIR VArray assignment expects exactly one index")
        }
        let elementTy = chirTy.TranslateType(RequireAstTy(subscriptExpr))
        let baseExpr = RequireExpr(subscriptExpr.baseExpr, "VArray assign base")
        let baseTy = chirTy.TranslateType(RequireAstTy(baseExpr))
        if (!IsCompoundAssignOp(assign.op)) {
            let rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR VArray assignment rhs produced no value")
            let rhs = GetDerefedValue(rhsValue)
            let baseLeftValueInfo = TranslateExprAsLeftValue(baseExpr)
            let lhsBase = AddressOfLeftValue(baseLeftValueInfo, baseTy)
            let indexValue = Translator.TranslateASTNode(subscriptExpr.indexExprs[0], this) ??
                throw IllegalStateException("faithful AST2CHIR VArray assignment index produced no value")
            CreateVArraySet(lhsBase, rhs, GetDerefedValue(indexValue), elementTy)
            return
        }

        let baseLeftValueInfo = TranslateExprAsLeftValue(baseExpr)
        let lhsBase = AddressOfLeftValue(baseLeftValueInfo, baseTy)
        let loadedBase = RequireResult(builder.CreateLoad(RequireRefBaseType(lhsBase), lhsBase, CurrentBlock()))
        let indexValue = Translator.TranslateASTNode(subscriptExpr.indexExprs[0], this) ??
            throw IllegalStateException("faithful AST2CHIR VArray assignment index produced no value")
        let index = GetDerefedValue(indexValue)
        let args = ArrayList<Value>()
        args.add(loadedBase)
        args.add(index)
        let callContext = IntrisicCallContext(kind: IntrinsicKind.VARRAY_GET, args: args)
        let lhsValue = RequireResult(builder.CreateIntrinsic(elementTy, callContext, CurrentBlock()))
        var compoundValue: Value
        if (assign.op == AstTokenKind.AND_ASSIGN) {
            compoundValue = TransShortCircuitAnd(lhsValue, rightExpr) ??
                throw IllegalStateException("faithful AST2CHIR VArray &&= produced no value")
        } else if (assign.op == AstTokenKind.OR_ASSIGN) {
            compoundValue = TransShortCircuitOr(lhsValue, rightExpr) ??
                throw IllegalStateException("faithful AST2CHIR VArray ||= produced no value")
        } else {
            let rhsValue = Translator.TranslateASTNode(rightExpr, this) ??
                throw IllegalStateException("faithful AST2CHIR VArray compound rhs produced no value")
            let opResult = builder.CreateBinaryExpression(ToCHIRCompoundAssignOp(assign.op),
                lhsValue.GetType() ?? elementTy, lhsValue, rhsValue, CurrentBlock(),
                overflowStrategy: assign.overflowStrategy)
            compoundValue = RequireResult(opResult)
        }
        CreateVArraySet(lhsBase, compoundValue, index, elementTy)
    }

    private func CreateVArraySet(lhs: Value, rhs: Value, index: Value, elementTy: Type): Unit {
        let args = ArrayList<Value>()
        args.add(lhs)
        args.add(CastValueIfNeeded(rhs, elementTy))
        args.add(index)
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
        if (let Some(parenExpr) <- (nodePtr as AstParenExpr)) {
            return TranslateExprAsLeftValue(RequireExpr(parenExpr.expr, "parenthesized left value"))
        }
        if (let Some(callExpr) <- (nodePtr as AstCallExpr)) {
            return TranslateCallExprAsLeftValue(callExpr)
        }
        if (let Some(_) <- (nodePtr as AstSubscriptExpr)) {
            throw IllegalArgumentException("not yet ported in faithful AST2CHIR: tuple/subscript left value")
        }
        let value = Translator.TranslateASTNode(expr, this)
        return FaithfulLeftValueInfo(value, ArrayList<String>())
    }

    private func TranslateCallExprAsLeftValue(expr: AstCallExpr): FaithfulLeftValueInfo {
        if (let Some(calleeDecl) <- expr.resolvedFunction) {
            if (IsStructOrClassCtorCall(expr, calleeDecl)) {
                return TranslateStructOrClassCtorCallAsLeftValue(expr, calleeDecl)
            }
        }
        let value = Translator.TranslateASTNode(expr, this) ??
            throw IllegalStateException("faithful AST2CHIR call left value produced no value")
        return FaithfulLeftValueInfo(value, ArrayList<String>())
    }

    private func TranslateStructOrClassCtorCallAsLeftValue(expr: AstCallExpr,
        calleeDecl: AstFuncDecl): FaithfulLeftValueInfo {
        let thisTy = chirTy.TranslateType(RequireAstTy(expr)).StripAllRefs()
        let thisRefTy = builder.context.GetRefTy(thisTy)
        let userArgs = ArrayList<Value>()
        let expectedParamTys = FuncParamTypes(expr, calleeDecl, thisType: Some(thisRefTy))
        AppendTranslatedCallArgs(expr, calleeDecl, userArgs, expectedParamTys, ArrayList<Value>())
        let thisObj = if (IsSuperOrThisCtorCall(expr)) {
            CastValueIfNeeded(GetCurrentConstructorThisObject(), thisRefTy)
        } else {
            let loc = TranslateLocation(expr)
            let allocated = CreateAllocateMaybeWithException(thisRefTy, thisTy, loc: loc)
            allocated.AsLocalVar().getOrThrow().GetExpr().getOrThrow().SetDebugLocationInfoForWarning(loc)
            allocated
        }
        let args = ArrayList<Value>()
        args.add(thisObj)
        for (arg in userArgs) {
            args.add(arg)
        }
        let callee = globalSymbolTable.Get(calleeDecl)
        let _ = CreateAndAppendApplyCallFromCallExpr(builder.context.GetUnitTy(), callee,
            FuncCallContext(args: args, thisType: thisRefTy), expr)
        return FaithfulLeftValueInfo(args[0], ArrayList<String>())
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
                let targetBaseAstTy = RequireAstTy(varDecl.outerDecl ??
                    throw IllegalStateException("faithful AST2CHIR member target has no outer declaration"))
                let baseInfo = NormalizeMemberBaseLeftValue(TranslateExprAsLeftValue(baseExpr), baseExpr,
                    targetBaseAstTy)
                let path = CopyStringList(baseInfo.path)
                path.add(varDecl.identifier.Val())
                if (!baseInfo.path.isEmpty()) {
                    return FaithfulLeftValueInfo(baseInfo.base, path)
                }
                let baseValue = baseInfo.base.getOrThrow()
                let baseValueTy = baseValue.GetType() ??
                    throw IllegalStateException("faithful AST2CHIR member base has no type: ${baseValue.GetIdentifier()}")
                var baseValRefDims = baseValueTy.GetRefDims()
                let strippedBaseValueTy = baseValueTy.StripAllRefs()
                let instMap = HashMap<Int64, (GenericType, Type)>()
                if (let Some(baseValCustomTy) <- (strippedBaseValueTy as CustomType)) {
                    baseValCustomTy.GetInstMap(instMap, builder)
                } else if (let Some(baseValGenericTy) <- (strippedBaseValueTy as GenericType)) {
                    baseValGenericTy.GetInstMap(instMap, builder)
                }
                var targetBaseTy = chirTy.TranslateType(targetBaseAstTy)
                if (targetBaseTy.GetRefDims() > baseValRefDims) {
                    baseValRefDims = targetBaseTy.GetRefDims()
                }
                targetBaseTy = ReplaceRawGenericArgType(targetBaseTy.StripAllRefs(), instMap, builder)
                var refIdx: Int64 = 0
                while (refIdx < baseValRefDims) {
                    targetBaseTy = builder.context.GetRefTy(targetBaseTy)
                    refIdx++
                }
                let castedBase = CastValueIfNeeded(baseValue, targetBaseTy)
                return FaithfulLeftValueInfo(castedBase, path)
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

    private func NormalizeMemberBaseLeftValue(info: FaithfulLeftValueInfo, baseExpr: AstExpr,
        targetBaseAstTy: AstTy): FaithfulLeftValueInfo {
        var base = info.base.getOrThrow()
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
        var memberBaseTy = (baseTy.StripAllRefs() as CustomType) ??
            throw IllegalStateException("faithful AST2CHIR member base is not custom type: ${baseTy.ToString()}")
        var memberTy: Option<Type> = None
        var pathIndex: Int64 = 0
        while (pathIndex < path.size) {
            let name = path[pathIndex]
            let allMemberVars = memberBaseTy.GetCustomTypeDef().GetAllInstanceVars()
            let instMap = HashMap<Int64, (GenericType, Type)>()
            memberBaseTy.GetInstMap(instMap, builder)
            var memberIndex = allMemberVars.size
            memberTy = None
            while (memberIndex > 0) {
                memberIndex--
                if (allMemberVars[memberIndex].name == name) {
                    memberTy = ReplaceRawGenericArgType(allMemberVars[memberIndex].ty, instMap, builder)
                    break
                }
            }
            let currentMemberTy = memberTy.getOrThrow()
            if (currentMemberTy.IsReferenceTypeWithRefDims(1)) {
                break
            }
            pathIndex++
            if (pathIndex < path.size) {
                memberBaseTy = (currentMemberTy.StripAllRefs() as CustomType) ??
                    throw IllegalStateException("faithful AST2CHIR member path is not custom type: ${currentMemberTy.ToString()}")
            }
        }
        let pathMemberTy = memberTy.getOrThrow()
        let baseExprTy = RequireAstTy(baseExpr)
        if (baseExprTy.IsClassLike() || baseExprTy.IsGeneric()) {
            var baseLeftValue = base
            var baseLeftValueTy = baseTy
            if (baseLeftValueTy.IsReferenceTypeWithRefDims(CLASS_REF_DIM)) {
                baseLeftValueTy = RequireRefBaseType(baseLeftValue)
                baseLeftValue = RequireResult(builder.CreateLoad(baseLeftValueTy, baseLeftValue, CurrentBlock()))
            }

            var baseVal: Option<Value> = None
            if (baseLeftValueTy.IsReferenceTypeWithRefDims(1) ||
                baseLeftValueTy.IsValueOrGenericTypeWithRefDims(1)) {
                let memberRefTy = builder.context.GetRefTy(pathMemberTy)
                let getMemberRef = RequireResult(builder.CreateGetElementByName(memberRefTy, baseLeftValue, path,
                    CurrentBlock()))
                baseVal = RequireResult(builder.CreateLoad(pathMemberTy, getMemberRef, CurrentBlock()))
            } else if (baseLeftValueTy.IsValueOrGenericTypeWithRefDims(0)) {
                baseVal = RequireResult(builder.CreateFieldByName(pathMemberTy, baseLeftValue, path, CurrentBlock()))
            }

            let concreteBaseVal = baseVal ??
                throw IllegalStateException("faithful AST2CHIR unsupported member base type: ${baseLeftValueTy.ToString()}")
            let concreteBaseValTy = concreteBaseVal.GetType() ??
                throw IllegalStateException("faithful AST2CHIR member base value has no type: ${concreteBaseVal.GetIdentifier()}")
            var baseValRefDims = concreteBaseValTy.GetRefDims()
            let strippedBaseValTy = concreteBaseValTy.StripAllRefs()
            let instMap = HashMap<Int64, (GenericType, Type)>()
            if (let Some(baseValCustomTy) <- (strippedBaseValTy as CustomType)) {
                baseValCustomTy.GetInstMap(instMap, builder)
            } else if (let Some(baseValGenericTy) <- (strippedBaseValTy as GenericType)) {
                baseValGenericTy.GetInstMap(instMap, builder)
            }
            var targetBaseTy = chirTy.TranslateType(targetBaseAstTy)
            if (targetBaseTy.GetRefDims() > baseValRefDims) {
                baseValRefDims = targetBaseTy.GetRefDims()
            }
            targetBaseTy = ReplaceRawGenericArgType(targetBaseTy.StripAllRefs(), instMap, builder)
            var refIdx: Int64 = 0
            while (refIdx < baseValRefDims) {
                targetBaseTy = builder.context.GetRefTy(targetBaseTy)
                refIdx++
            }
            let castedBaseVal = CastValueIfNeeded(concreteBaseVal, targetBaseTy)
            path.clear()
            return FaithfulLeftValueInfo(castedBaseVal, path)
        }
        if (!pathMemberTy.IsReferenceTypeWithRefDims(1) &&
            (baseTy.IsReferenceTypeWithRefDims(1) || baseTy.IsValueOrGenericTypeWithRefDims(1) ||
                baseTy.IsValueOrGenericTypeWithRefDims(0))) {
            return FaithfulLeftValueInfo(base, path)
        }
        let loaded = LoadLeftValue(info, chirTy.TranslateType(RequireAstTy(baseExpr))) ??
            throw IllegalStateException("faithful AST2CHIR member base produced no value")
        path.clear()
        return FaithfulLeftValueInfo(loaded, path)
    }

    private func AddressOfLeftValue(info: FaithfulLeftValueInfo, expectedTy: Type): Value {
        let base = info.base.getOrThrow()
        if (info.path.isEmpty()) {
            return base
        }
        let baseTy = base.GetType() ??
            throw IllegalStateException("faithful AST2CHIR address base has no type: ${base.GetIdentifier()}")
        if (baseTy.IsRef()) {
            let refTy = builder.context.GetRefTy(expectedTy)
            return RequireResult(builder.CreateGetElementByName(refTy, base, info.path, CurrentBlock()))
        }
        return RequireResult(builder.CreateFieldByName(expectedTy, base, info.path, CurrentBlock()))
    }

    private func LoadLeftValue(info: FaithfulLeftValueInfo, expectedTy: Type): Option<Value> {
        let base = info.base.getOrThrow()
        if (info.path.isEmpty()) {
            return GetDerefedValue(base)
        }
        let baseTy = base.GetType() ??
            throw IllegalStateException("faithful AST2CHIR left value base has no type: ${base.GetIdentifier()}")
        if (baseTy.IsReferenceTypeWithRefDims(1) || baseTy.IsValueOrGenericTypeWithRefDims(1)) {
            let refTy = builder.context.GetRefTy(expectedTy)
            let memberRef = RequireResult(builder.CreateGetElementByName(refTy, base, info.path, CurrentBlock()))
            return RequireResult(builder.CreateLoad(expectedTy, memberRef, CurrentBlock()))
        }
        if (baseTy.IsValueOrGenericTypeWithRefDims(0)) {
            return RequireResult(builder.CreateFieldByName(expectedTy, base, info.path, CurrentBlock()))
        }
        throw IllegalStateException("faithful AST2CHIR unsupported member left value base type: ${baseTy.ToString()}")
    }

    private func StoreToLeftValue(info: FaithfulLeftValueInfo, value: Value): Unit {
        let base = info.base.getOrThrow()
        if (info.path.isEmpty()) {
            builder.CreateStore(CastValueIfNeeded(value, RequireRefBaseType(base)), base, CurrentBlock())
            return
        }
        builder.CreateStoreElementByName(value, base, info.path, CurrentBlock())
    }

    private func TranslateStaticTargetOrPackageMemberAccess(expr: AstMemberAccess, target: AstDecl): Option<Value> {
        if (let Some(propDecl) <- (target as AstPropDecl)) {
            return Some(TranslatePropertyGetter(expr, propDecl))
        }
        let targetNode = GetSymbolTable(target)
        if (let Some(_) <- (target as AstVarDecl)) {
            let targetTy = chirTy.TranslateType(RequireAstTy(target))
            let loaded = RequireResult(builder.CreateLoad(targetTy, targetNode, CurrentBlock()))
            return CastValueIfNeeded(loaded, chirTy.TranslateType(RequireAstTy(expr)))
        }
        if (let Some(funcDecl) <- (target as AstFuncDecl)) {
            if (target.outerDecl.isSome()) {
                return Some(WrapMemberMethodByLambda(funcDecl, GetInstCalleeInfoFromMemberAccess(expr, funcDecl), None))
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
        if (decl.TestAttr(AstAttribute.STATIC)) {
            return false
        }
        if (let Some(outer) <- decl.outerDecl) {
            return outer.IsNominalDecl()
        }
        return false
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

    private func CoerceValueForExpectedType(value: Value, expectedTy: Type): Value {
        let valueTy = value.GetType() ??
            throw IllegalStateException("faithful AST2CHIR value has no type: ${value.GetIdentifier()}")
        if (valueTy.IsEqual(expectedTy)) {
            return value
        }
        if (expectedTy.IsGenericRelated() && !valueTy.IsGenericRelated()) {
            return RequireResult(builder.CreateTransformToGeneric(expectedTy, value, CurrentBlock()))
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

    private func TypeCastOrBoxIfNeeded(value: Value, expectedTy: Type, loc: DebugLocation,
        needCheck!: Bool = true): Value {
        return TypeCastOrBoxIfNeeded(value, expectedTy, builder, CurrentBlock(), loc, needCheck: needCheck)
    }

    private func CreateAndAppendWrappedStore(rhs: Value, lhs: Value, loc: DebugLocation): Unit {
        CreateAndAppendWrappedStore(rhs, lhs, CurrentBlock(), loc)
    }

    private func CreateAndAppendWrappedStoreElementByName(
        loc: DebugLocation, rhs: Value, lhs: Value, path: ArrayList<String>
    ): Unit {
        let lhsCustomType = (lhs.GetType().getOrThrow().StripAllRefs() as CustomType).getOrThrow()
        let memberType = GetInstMemberTypeByName(lhsCustomType, path, builder)
        let castedRhs = TypeCastOrBoxIfNeeded(rhs, memberType, loc)
        let store = builder.CreateStoreElementByName(castedRhs, lhs, path, CurrentBlock())
        store.SetDebugLocation(loc)
    }

    private func CreateAndAppendWrappedStore(rhs: Value, lhs: Value): Unit {
        CreateAndAppendWrappedStore(rhs, lhs, CurrentBlock(), INVALID_LOCATION)
    }

    private func CreateAndAppendWrappedStore(rhs: Value, lhs: Value, parent: Block, loc: DebugLocation): Unit {
        let lhsType = (lhs.GetType().getOrThrow() as RefType) ??
            throw IllegalStateException("faithful AST2CHIR wrapped store lhs is not ref: ${lhs.GetIdentifier()}")
        let castedRhs = TypeCastOrBoxIfNeeded(rhs, lhsType.GetBaseType(), loc)
        let store = builder.CreateStore(castedRhs, lhs, parent)
        store.SetDebugLocation(loc)
    }

    private func TranslateLocation(node: AstNode): DebugLocation {
        return TranslateLocation(node.begin, node.end)
    }

    private func TranslateLocation(beginPos: AstPosition, endPos: AstPosition): DebugLocation {
        match (beginPos.GetStatus()) {
            case AstPositionStatus.IGNORE => return TranslateFileLocation(beginPos.fileID)
            case _ => ()
        }
        var loc = TranslateLocationWithoutScope(builder.context, beginPos, endPos)
        loc.SetScopeInfo(scopeInfo)
        return loc
    }

    private func TranslateFileLocation(fileID: UInt64): DebugLocation {
        let fileId = UInt32(fileID)
        return DebugLocation(builder.context.GetSourceFileName(fileId), fileId, Position(), Position())
    }

    private func CopyStringList(values: ArrayList<String>): ArrayList<String> {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(value)
        }
        return out
    }

    private func SetSymbolTable(node: AstNode, value: Value, isLocal!: Bool = true): Unit {
        if (let Some(decl) <- (node as AstDecl)) {
            if (isLocal) {
                localValSymbolTable.Set(decl, value)
            } else {
                globalSymbolTable.Set(decl, value)
            }
            return
        }
        astNodeSymbolTable.Set(node, value)
    }

    private func ShouldInGlobalTable(node: AstNode): Bool {
        if (node.TestAttr(AstAttribute.GLOBAL) && !node.IsNominalDecl()) {
            return true
        }
        if ((node.TestAttr(AstAttribute.STATIC) && node.astKind == ASTKind.VAR_DECL) ||
            node.astKind == ASTKind.FUNC_DECL) {
            if (let Some(decl) <- (node as AstDecl)) {
                if (let Some(outerDecl) <- decl.outerDecl) {
                    if (outerDecl.IsNominalDecl()) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func GetSymbolTable(node: AstNode): Value {
        if (let Some(decl) <- (node as AstDecl)) {
            return GetSymbolTable(decl)
        }
        return astNodeSymbolTable.Get(node)
    }

    private func GetBlockByAST(block: AstBlock): Block {
        return (GetSymbolTable(block) as Block) ??
            throw IllegalStateException("faithful AST2CHIR block cache is not a Block")
    }

    private func CreateBlock(): Block {
        if (blockGroupStack.isEmpty()) {
            throw IllegalStateException("faithful AST2CHIR CreateBlock without block group")
        }
        return builder.CreateBlock(blockGroupStack[blockGroupStack.size - 1])
    }

    private func GetSymbolTable(decl: AstDecl): Value {
        if (ShouldInGlobalTable(decl)) {
            return globalSymbolTable.Get(decl)
        }
        if (localConstVars.HasElement(decl)) {
            return globalSymbolTable.Get(decl)
        }
        if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
            if (localConstFuncs.HasElement(funcDecl)) {
                return globalSymbolTable.Get(decl)
            }
        }
        return localValSymbolTable.Get(decl)
    }

    private func GetDerefedValue(value: Value): Value {
        if (let Some(ty) <- value.GetType()) {
            if (let Some(refTy) <- (ty as RefType)) {
                let valType = refTy.GetBaseType()
                if (valType.IsClassOrArray()) {
                    return value
                }
                return RequireResult(builder.CreateLoad(valType, value, CurrentBlock()))
            }
        }
        return value
    }

    private func GetDerefedValue(value: Value, loc: DebugLocation): Value {
        if (let Some(ty) <- value.GetType()) {
            if (let Some(refTy) <- (ty as RefType)) {
                let valType = refTy.GetBaseType()
                if (valType.IsClassOrArray()) {
                    return value
                }
                let load = builder.CreateLoad(valType, value, CurrentBlock())
                load.SetDebugLocation(loc)
                return RequireResult(load)
            }
        }
        return value
    }

    private func GenerateLoadIfNecessaryForArg(value: Value, isInOut: Bool): Value {
        let argTy = value.GetType() ??
            throw IllegalStateException("faithful AST2CHIR argument has no type: ${value.GetIdentifier()}")
        let pureArgTy = argTy.StripAllRefs()
        if (isInOut && (pureArgTy.IsValueType() || pureArgTy.IsGeneric())) {
            if (argTy.IsCPointer()) {
                return value
            }
            if (pureArgTy.IsGeneric()) {
                if (let Some(refTy) <- (argTy as RefType)) {
                    return RequireResult(builder.CreateLoad(refTy.GetBaseType(), value, CurrentBlock()))
                }
            }
            return value
        }
        if (pureArgTy.IsValueType() || pureArgTy.IsGeneric() || pureArgTy.IsFunc()) {
            if (let Some(refTy) <- (argTy as RefType)) {
                return RequireResult(builder.CreateLoad(refTy.GetBaseType(), value, CurrentBlock()))
            }
            return value
        }
        if (pureArgTy.IsReferenceType()) {
            if (let Some(refTy) <- (argTy as RefType)) {
                let baseTy = refTy.GetBaseType()
                if (baseTy.IsRef()) {
                    return RequireResult(builder.CreateLoad(baseTy, value, CurrentBlock()))
                }
            }
        }
        return value
    }

    private func GeneratePointerInoutArg(info: FaithfulLeftValueInfo, expectedTy: Type): Value {
        let base = info.base.getOrThrow()
        if (info.path.isEmpty()) {
            return base
        }
        let baseTy = base.GetType() ??
            throw IllegalStateException("faithful AST2CHIR pointer inout base has no type: ${base.GetIdentifier()}")
        if (baseTy.IsRef()) {
            return RequireResult(builder.CreateGetElementByName(builder.context.GetRefTy(expectedTy), base,
                info.path, CurrentBlock()))
        }
        return RequireResult(builder.CreateFieldByName(expectedTy, base, info.path, CurrentBlock()))
    }

    private func CurrentBlock(): Block {
        return currentBlock ?? throw IllegalStateException("faithful AST2CHIR has no current block")
    }

    private func RequireParentBlockGroup(block: Block, context: String): BlockGroup {
        return block.GetParentBlockGroup() ??
            throw IllegalStateException("faithful AST2CHIR ${context} requires parent block group")
    }

    private func TranslateLitConstant(expr: AstLitConstExpr): LiteralValue {
        let kind = RequireAstTy(expr).kind
        return match (kind) {
            case AstTypeKind.TYPE_FLOAT16 | AstTypeKind.TYPE_FLOAT64 | AstTypeKind.TYPE_IDEAL_FLOAT =>
                FloatLiteral(expr.constNumValue.asFloat.value)
            case AstTypeKind.TYPE_FLOAT32 =>
                let stringVal = expr.stringValue.replace("_", "")
                var value = 0.0
                try (cStringVal = unsafe { LibC.mallocCString(stringVal) }.asResource()) {
                    value = unsafe { CJSelfhostStrtoldToFloat32(cStringVal.value) }
                }
                FloatLiteral(value)
            case AstTypeKind.TYPE_UINT8 | AstTypeKind.TYPE_UINT16 | AstTypeKind.TYPE_UINT32 |
                AstTypeKind.TYPE_UINT64 | AstTypeKind.TYPE_UINT_NATIVE | AstTypeKind.TYPE_INT8 |
                AstTypeKind.TYPE_INT16 | AstTypeKind.TYPE_INT32 | AstTypeKind.TYPE_INT64 |
                AstTypeKind.TYPE_INT_NATIVE | AstTypeKind.TYPE_IDEAL_INT => TranslateIntegerLiteral(expr)
            case AstTypeKind.TYPE_RUNE => RuneLiteral(Rune(expr.codepoint[0]))
            case AstTypeKind.TYPE_BOOLEAN => BoolLiteral(expr.stringValue == "true")
            case AstTypeKind.TYPE_STRUCT => StringLiteral(expr.stringValue)
            case _ =>
                throw IllegalArgumentException("not yet ported in faithful AST2CHIR: literal type")
        }
    }

    private func TranslateIntegerLiteral(expr: AstLitConstExpr): IntLiteral {
        let astTy = RequireAstTy(expr)
        let kind = astTy.kind
        if (AstTypeKindInRange(kind, AstTypeKind.TYPE_UINT8, AstTypeKind.TYPE_UINT64) ||
            kind == AstTypeKind.TYPE_UINT_NATIVE) {
            return IntLiteral(UInt64LiteralBitsToInt64(expr.constNumValue.asInt.Uint64()))
        }
        return IntLiteral(expr.constNumValue.asInt.`Int64`())
    }

    private func UInt64LiteralBitsToInt64(value: UInt64): Int64 {
        if (value <= UInt64(Int64.Max)) {
            return Int64(value)
        }
        return -Int64(UInt64.Max - value) - 1
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

    private static func RequireNodeAsParenExpr(node: AstNode): AstParenExpr {
        return (node as AstParenExpr) ?? throw IllegalArgumentException("ASTKind cast failed: PAREN_EXPR")
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

    private static func RequireNodeAsPointerExpr(node: AstNode): AstPointerExpr {
        return (node as AstPointerExpr) ?? throw IllegalArgumentException("ASTKind cast failed: POINTER_EXPR")
    }

    private static func RequireNodeAsSpawnExpr(node: AstNode): AstSpawnExpr {
        return (node as AstSpawnExpr) ?? throw IllegalArgumentException("ASTKind cast failed: SPAWN_EXPR")
    }
}
