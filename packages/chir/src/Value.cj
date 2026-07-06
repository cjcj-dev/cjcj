package cangjie_compiler::chir

import cangjie_compiler::basic.Linkage as BasicLinkage
import std.collection.*

public open class Value <: Base & Hashable & Equatable<Value> {
    private var ty: Option<Type>
    private var identifier: String
    private let kind: ValueKind
    private let users: ArrayList<Expression> = ArrayList<Expression>()

    public init(ty: Option<Type>, identifier: String, kind: ValueKind) {
        super()
        this.ty = ty
        this.identifier = identifier
        this.kind = kind
    }

    public operator func ==(right: Value): Bool {
        return nodeId == right.nodeId
    }

    public operator func !=(right: Value): Bool {
        return nodeId != right.nodeId
    }

    public func hashCode(): Int64 {
        return nodeId.hashCode()
    }

    public func GetValueKind(): ValueKind {
        return kind
    }

    public func IsBlock(): Bool { return kind == ValueKind.KIND_BLOCK }
    public func IsBlockGroup(): Bool { return kind == ValueKind.KIND_BLOCK_GROUP }
    public func IsFunc(): Bool { return kind == ValueKind.KIND_FUNC }
    public func IsGlobal(): Bool { return kind == ValueKind.KIND_GLOBALVAR || kind == ValueKind.KIND_FUNC }
    public func IsGlobalVar(): Bool { return kind == ValueKind.KIND_GLOBALVAR }
    public func IsLiteral(): Bool { return kind == ValueKind.KIND_LITERAL }
    public func IsLocalVar(): Bool { return kind == ValueKind.KIND_LOCALVAR }
    public func IsParameter(): Bool { return kind == ValueKind.KIND_PARAMETER }

    public func IsImportedFunc(): Bool {
        return IsFunc() && TestAttr(Attribute.IMPORTED)
    }

    public func IsImportedVar(): Bool {
        return IsGlobalVar() && TestAttr(Attribute.IMPORTED)
    }

    public func IsImportedSymbol(): Bool {
        return IsImportedFunc() || IsImportedVar()
    }

    public func IsFuncWithBody(): Bool {
        if (let Some(fn) <- AsFunction()) {
            return fn.GetBody().isSome()
        }
        return false
    }

    public func IsGlobalVarWithInitializer(): Bool {
        if (let Some(globalVar) <- AsGlobalVar()) {
            return globalVar.GetInitializerValue().isSome() || globalVar.GetInitFunc().isSome()
        }
        return false
    }

    public func GetType(): Option<Type> {
        return ty
    }

    public func SetType(newType: Type): Unit {
        ty = newType
    }

    public open func GetSrcCodeIdentifier(): String {
        return ""
    }

    public func GetIdentifier(): String {
        return identifier
    }

    public func SetIdentifier(newIdentifier: String): Unit {
        identifier = newIdentifier
    }

    public func GetIdentifierWithoutPrefix(): String {
        if (identifier.size > 0) {
            return identifier[1..]
        }
        return identifier
    }

    public func GetUsers(): ArrayList<Expression> {
        return users.clone()
    }

    public func GetUsersRef(): ArrayList<Expression> {
        return users
    }

    public func AddUserOnly(expr: Expression): Unit {
        users.add(expr)
    }

    public func RemoveUserOnly(expr: Expression): Unit {
        var idx: Int64 = 0
        while (idx < users.size) {
            if (users[idx].nodeId == expr.nodeId) {
                users.remove(at: idx)
                continue
            }
            idx++
        }
    }

    public func ClearUsersOnly(): Unit {
        users.clear()
    }

    public func ReplaceWith(newValue: Value): Unit {
        ReplaceWith(newValue, None)
    }

    public func ReplaceWith(newValue: Value, scope: Option<BlockGroup>): Unit {
        let oldUsers = users.clone()
        for (user in oldUsers) {
            if (user.GetParentBlock().isNone()) {
                continue
            }
            if (scope.isNone()) {
                user.ReplaceOperand(this, newValue)
            } else if (let Some(scopeGroup) <- scope) {
                if (IsNestedBlockOf(user.GetParentBlockGroup(), scopeGroup)) {
                    user.ReplaceOperand(this, newValue)
                }
            }
        }
    }

    public func IsCompileTimeValue(): Bool {
        if (IsLiteral()) {
            return true
        }
        if (let Some(local) <- AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                return expr.IsConstant()
            }
        }
        return TestAttr(Attribute.CONST)
    }

    public func Dump(): Unit {
        println(ToString(0))
    }

    public open func ToString(indent: Int64): String {
        let typeText = if (let Some(valueTy) <- ty) { valueTy.ToString() } else { "<none>" }
        return IndentToString(indent) + identifier + ": " + typeText
    }

    public open func AsParameter(): Option<Parameter> { return None }
    public open func AsLocalVar(): Option<LocalVar> { return None }
    public open func AsBlock(): Option<Block> { return None }
    public open func AsBlockGroup(): Option<BlockGroup> { return None }
    public open func AsFunction(): Option<Function> { return None }
    public open func AsGlobalVar(): Option<GlobalVar> { return None }
}

public class Parameter <: Value {
    private var ownerFunc: Option<Function> = None
    private var ownerLambda: Option<Lambda> = None
    private var srcCodeIdentifier: String = ""
    private let annoInfo: AnnoInfo = AnnoInfo()

    public init(ty: Type, id: String, ownerFunc: Option<Function>) {
        super(ty, id, ValueKind.KIND_PARAMETER)
        this.ownerFunc = ownerFunc
        if (let Some(fn) <- ownerFunc) {
            fn.AddParam(this)
        }
    }

    public init(ty: Type, id: String, ownerLambda: Lambda) {
        super(ty, id, ValueKind.KIND_PARAMETER)
        this.ownerLambda = ownerLambda
        ownerLambda.AddParam(this)
    }

    public override func AsParameter(): Option<Parameter> { return this }

    public override func GetSrcCodeIdentifier(): String {
        return srcCodeIdentifier
    }

    public func SetSrcCodeIdentifier(newName: String): Unit {
        srcCodeIdentifier = newName
    }

    public func GetOwnerFunc(): Option<Function> {
        return ownerFunc
    }

    public func SetOwnerFunc(owner: Function): Unit {
        ownerFunc = owner
        ownerLambda = None
    }

    public func GetOwnerLambda(): Option<Lambda> {
        return ownerLambda
    }

    public func SetOwnerLambda(owner: Lambda): Unit {
        ownerLambda = owner
        ownerFunc = None
    }

    public func GetTopLevelFunc(): Option<Function> {
        if (ownerFunc.isSome()) {
            return ownerFunc
        }
        if (let Some(lambdaExpr) <- ownerLambda) {
            return lambdaExpr.GetTopLevelFunc()
        }
        return None
    }

    public func GetAnnoInfo(): AnnoInfo {
        return annoInfo
    }

    public func GetDebugExpr(): Option<Debug> {
        var idx = GetUsersRef().size - 1
        while (idx >= 0) {
            if (let Some(debugExpr) <- (GetUsersRef()[idx] as Debug)) {
                return debugExpr
            }
            idx--
        }
        return None
    }

    public override func ToString(indent: Int64): String {
        let typeText = if (let Some(valueTy) <- GetType()) { valueTy.ToString() } else { "<none>" }
        var out = annoInfo.ToString(indent: indent)
        if (!out.isEmpty()) {
            out += "\n"
        }
        out += IndentToString(indent) + GetAttributeInfo().ToString() + GetIdentifier()
        if (!srcCodeIdentifier.isEmpty()) {
            out += "[" + srcCodeIdentifier + "]"
        }
        return out + ": " + typeText
    }
}

public class LocalVar <: Value {
    private var expr: Option<Expression> = None
    private var isRetValue: Bool = false
    private var srcCodeIdentifier: String = ""

    public init(ty: Type, indexStr: String, expr: Option<Expression>) {
        super(ty, indexStr, ValueKind.KIND_LOCALVAR)
        this.expr = expr
        if (let Some(ownerExpr) <- expr) {
            ownerExpr.SetResult(this)
        }
    }

    public override func AsLocalVar(): Option<LocalVar> { return this }

    public func GetExpr(): Option<Expression> {
        return expr
    }

    public func SetExpr(newExpr: Expression): Unit {
        expr = newExpr
        newExpr.SetResult(this)
    }

    public override func GetSrcCodeIdentifier(): String {
        return srcCodeIdentifier
    }

    public func SetSrcCodeIdentifier(newName: String): Unit {
        srcCodeIdentifier = newName
    }

    public override func GetDebugLocation(): DebugLocation {
        if (let Some(ownerExpr) <- expr) {
            return ownerExpr.GetDebugLocation()
        }
        return super.GetDebugLocation()
    }

    public func GetDebugExpr(): Option<Debug> {
        var idx = GetUsersRef().size - 1
        while (idx >= 0) {
            if (let Some(debugExpr) <- (GetUsersRef()[idx] as Debug)) {
                return debugExpr
            }
            idx--
        }
        return None
    }

    public func IsRetValue(): Bool {
        return isRetValue
    }

    public func SetRetValue(flag: Bool): Unit {
        isRetValue = flag
    }

    public func GetOwnerBlockGroup(): Option<BlockGroup> {
        if (let Some(ownerExpr) <- expr) {
            return ownerExpr.GetParentBlockGroup()
        }
        return None
    }

    public func GetTopLevelFunc(): Option<Function> {
        if (let Some(ownerExpr) <- expr) {
            return ownerExpr.GetTopLevelFunc()
        }
        return None
    }

    public override func ToString(indent: Int64): String {
        let typeText = if (let Some(valueTy) <- GetType()) { valueTy.ToString() } else { "<none>" }
        var out = IndentToString(indent) + GetAttributeInfo().ToString() + GetIdentifier()
        if (!srcCodeIdentifier.isEmpty()) {
            out += "[" + srcCodeIdentifier + "]"
        }
        return out + ": " + typeText
    }
}

public class Block <: Value {
    private var parentGroup: Option<BlockGroup> = None
    private let exprs: ArrayList<Expression> = ArrayList<Expression>()
    private let predecessors: ArrayList<Block> = ArrayList<Block>()
    private var exceptions: Option<ArrayList<ClassType>> = None

    public init(identifier: String, parentGroup: Option<BlockGroup>) {
        super(None, identifier, ValueKind.KIND_BLOCK)
        this.parentGroup = parentGroup
        if (let Some(group) <- parentGroup) {
            group.AddBlock(this)
        }
    }

    public override func AsBlock(): Option<Block> { return this }

    public func GetSuccessors(): ArrayList<Block> {
        if (let Some(term) <- GetTerminator()) {
            return term.GetSuccessors()
        }
        return ArrayList<Block>()
    }

    public func GetPredecessors(): ArrayList<Block> {
        return predecessors.clone()
    }

    public func GetPredecessorsRef(): ArrayList<Block> {
        return predecessors
    }

    public func SetExceptions(ep: ArrayList<ClassType>): Unit {
        let out = ArrayList<ClassType>()
        for (ty in ep) {
            out.add(ty)
        }
        exceptions = out
    }

    public func GetExceptions(): ArrayList<ClassType> {
        if (let Some(ep) <- exceptions) {
            let out = ArrayList<ClassType>()
            for (ty in ep) {
                out.add(ty)
            }
            return out
        }
        return ArrayList<ClassType>()
    }

    public func IsLandingPadBlock(): Bool {
        return exceptions.isSome()
    }

    public func IsEntry(): Bool {
        if (let Some(group) <- parentGroup) {
            if (let Some(entry) <- group.GetEntryBlock()) {
                return entry.nodeId == nodeId
            }
        }
        return false
    }

    public func AppendExpressions(expressions: ArrayList<Expression>): Unit {
        for (expression in expressions) {
            AppendExpression(expression)
        }
    }

    public func AppendExpression(expression: Expression): Unit {
        var hasExpression = false
        for (expr in exprs) {
            if (refEq(expr, expression)) {
                hasExpression = true
                break
            }
        }
        if (!hasExpression) {
            exprs.add(expression)
        }
        expression.SetParent(this)
        if (let Some(term) <- expression.AsTerminator()) {
            term.SyncSuccessorPredecessors()
        }
    }

    public func InsertExprIntoHead(expr: Expression): Unit {
        var idx: Int64 = 0
        while (idx < exprs.size) {
            if (refEq(exprs[idx], expr)) {
                exprs.remove(at: idx)
                break
            }
            idx++
        }
        exprs.add(expr, at: 0)
        expr.SetParent(this)
    }

    public func GetExpressionByIdx(idx: Int64): Expression {
        return exprs[idx]
    }

    public func GetExpressions(): ArrayList<Expression> {
        return exprs.clone()
    }

    public func GetExpressionsRef(): ArrayList<Expression> {
        return exprs
    }

    public func GetExpressionsNum(): Int64 {
        var res: Int64 = 0
        for (expr in exprs) {
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                let lambdaBody = lambdaExpr.GetBody().getOrThrow()
                res += lambdaBody.GetExpressionsNum()
            }
        }
        res += exprs.size
        return res
    }

    public func GetNonTerminatorExpressions(): ArrayList<Expression> {
        let out = ArrayList<Expression>()
        for (expr in exprs) {
            if (!expr.IsTerminator()) {
                out.add(expr)
            }
        }
        return out
    }

    public func GetTerminator(): Option<Terminator> {
        if (exprs.isEmpty()) {
            return None
        }
        return exprs[exprs.size - 1] as Terminator
    }

    public func GetParentBlockGroup(): Option<BlockGroup> {
        return parentGroup
    }

    public func SetParentBlockGroup(parent: BlockGroup): Unit {
        parentGroup = parent
    }

    public func GetTopLevelFunc(): Option<Function> {
        if (let Some(group) <- parentGroup) {
            return group.GetTopLevelFunc()
        }
        return None
    }

    public func GetFuncOrLambdaBody(): Option<BlockGroup> {
        if (let Some(group) <- parentGroup) {
            return group.GetFuncOrLambdaBody()
        }
        return None
    }

    public func MoveTo(newBlockGroup: BlockGroup): Unit {
        if (let Some(group) <- parentGroup) {
            group.RemoveBlock(this)
            if (let Some(entry) <- group.GetEntryBlock()) {
                if (refEq(entry, this)) {
                    group.SetEntryBlock(None)
                }
            }
        }
        newBlockGroup.AddBlock(this)
    }

    public func RemoveSelfFromBlockGroup(): Unit {
        if (let Some(group) <- parentGroup) {
            group.RemoveBlock(this)
            if (let Some(entry) <- group.GetEntryBlock()) {
                if (refEq(entry, this)) {
                    group.SetEntryBlock(None)
                }
            }
        }
        parentGroup = None
        ClearPredecessorsOnly()
        ClearUsersOnly()
        for (expr in GetExpressions()) {
            expr.RemoveSelfFromBlock()
        }
        ClearExprsOnly()
    }

    public func RemoveExprOnly(expr: Expression): Unit {
        var idx: Int64 = 0
        while (idx < exprs.size) {
            if (refEq(exprs[idx], expr)) {
                exprs.remove(at: idx)
                break
            }
            idx++
        }
    }

    public func AddPredecessor(block: Block): Unit {
        var hasBlock = false
        for (predecessor in predecessors) {
            if (refEq(predecessor, block)) {
                hasBlock = true
                break
            }
        }
        if (!hasBlock) {
            predecessors.add(block)
        }
    }

    public func RemovePredecessor(block: Block): Unit {
        var idx: Int64 = 0
        while (idx < predecessors.size) {
            if (refEq(predecessors[idx], block)) {
                predecessors.remove(at: idx)
                continue
            }
            idx++
        }
        if (let Some(term) <- block.GetTerminator()) {
            RemoveUserOnly(term)
        }
    }

    public func ClearPredecessorsOnly(): Unit {
        predecessors.clear()
    }

    public func ClearExprsOnly(): Unit {
        exprs.clear()
    }

    public func Clone(builder: CHIRBuilder, newGroup: BlockGroup): Block {
        let newBlock = builder.CreateBlock(newGroup)
        newBlock.CopyBaseInfoFrom(this)
        if (let Some(blockExceptions) <- exceptions) {
            newBlock.SetExceptions(blockExceptions)
        }
        for (expr in exprs) {
            let newExpr = expr.Clone(builder, newBlock)
            newExpr.CopyBaseInfoFrom(expr)
            if (let Some(sourceResult) <- expr.GetResult()) {
                if (let Some(clonedResult) <- newExpr.GetResult()) {
                    clonedResult.CopyBaseInfoFrom(sourceResult)
                }
            }
        }
        return newBlock
    }

    public override func ToString(indent: Int64): String {
        var out = IndentToString(indent) + GetIdentifier() + ":"
        for (expr in exprs) {
            out += "\n" + expr.ToString(indent + 2)
        }
        return out
    }
}

public class BlockGroup <: Value {
    private var entryBlock: Option<Block> = None
    private let blocks: ArrayList<Block> = ArrayList<Block>()
    private var ownerFunc: Option<Function> = None
    private var ownerExpression: Option<Expression> = None

    public init(identifier: String) {
        super(None, identifier, ValueKind.KIND_BLOCK_GROUP)
    }

    public override func AsBlockGroup(): Option<BlockGroup> { return this }

    public func GetExpressionsNum(): Int64 {
        var num: Int64 = 0
        for (block in blocks) {
            num += block.GetExpressionsNum()
        }
        return num
    }

    public func AddBlock(block: Block): Unit {
        var hasBlock = false
        for (item in blocks) {
            if (refEq(item, block)) {
                hasBlock = true
                break
            }
        }
        if (!hasBlock) {
            blocks.add(block)
        }
        block.SetParentBlockGroup(this)
        if (entryBlock.isNone()) {
            entryBlock = block
        }
    }

    public func AddBlocks(newBlocks: ArrayList<Block>): Unit {
        for (block in newBlocks) {
            AddBlock(block)
        }
    }

    public func GetBlockByIdx(idx: Int64): Block {
        return blocks[idx]
    }

    public func GetBlocks(): ArrayList<Block> {
        return blocks.clone()
    }

    public func GetBlocksRef(): ArrayList<Block> {
        return blocks
    }

    public func GetEntryBlock(): Option<Block> {
        return entryBlock
    }

    public func SetEntryBlock(block: Option<Block>): Unit {
        if (let None <- block) {
            entryBlock = None
            return
        }
        let realBlock = block.getOrThrow()
        var hasBlock = false
        for (item in blocks) {
            if (refEq(item, realBlock)) {
                hasBlock = true
                break
            }
        }
        if (!hasBlock) {
            AddBlock(realBlock)
        }
        entryBlock = realBlock
    }

    public func GetTopLevelFunc(): Option<Function> {
        if (ownerFunc.isSome()) {
            return ownerFunc
        }
        if (let Some(expr) <- ownerExpression) {
            return expr.GetTopLevelFunc()
        }
        return None
    }

    public func GetFuncOrLambdaBody(): Option<BlockGroup> {
        if (ownerFunc.isSome()) {
            return this
        }
        if (let Some(expr) <- ownerExpression) {
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                return lambdaExpr.GetBody()
            }
            return expr.GetFuncOrLambdaBody()
        }
        return this
    }

    public func GetOwnerFunc(): Option<Function> {
        return ownerFunc
    }

    public func SetOwnerFunc(fn: Function): Unit {
        ownerFunc = fn
        ownerExpression = None
    }

    public func GetOwnerExpression(): Option<Expression> {
        return ownerExpression
    }

    public func SetOwnerExpression(expr: Expression): Unit {
        ownerExpression = expr
        ownerFunc = None
    }

    public func RemoveBlock(block: Block): Unit {
        var idx: Int64 = 0
        while (idx < blocks.size) {
            if (refEq(blocks[idx], block)) {
                blocks.remove(at: idx)
                continue
            }
            idx++
        }
    }

    public func ClearBlockGroup(): Unit {
        for (block in blocks) {
            block.ClearPredecessorsOnly()
        }
        blocks.clear()
        entryBlock = None
    }

    public func Clone(builder: CHIRBuilder, newFunc: Function): BlockGroup {
        let newGroup = builder.CreateBlockGroup(newFunc)
        newGroup.SetOwnerFunc(newFunc)
        newGroup.CopyBaseInfoFrom(this)
        CloneBlocks(builder, newGroup)
        return newGroup
    }

    public func Clone(builder: CHIRBuilder, newLambda: Lambda): BlockGroup {
        let parentFunc = newLambda.GetTopLevelFunc()
        if (parentFunc.isNone()) {
            throw IllegalArgumentException("lambda block-group clone requires a top-level function")
        }
        let ownerFunc = parentFunc.getOrThrow()
        let newGroup = builder.CreateBlockGroup(ownerFunc)
        if (newLambda.GetBody().isNone()) {
            newLambda.InitBody(newGroup)
        } else {
            newGroup.SetOwnerExpression(newLambda)
        }
        newGroup.CopyBaseInfoFrom(this)
        CloneBlocks(builder, newGroup)
        return newGroup
    }

    private func CloneBlocks(builder: CHIRBuilder, target: BlockGroup): Unit {
        if (!target.GetBlocksRef().isEmpty() || target.GetEntryBlock().isSome()) {
            throw IllegalArgumentException("target block group for clone must be empty")
        }
        let blockMap = HashMap<Int64, Block>()
        for (sourceBlock in blocks) {
            let clonedBlock = sourceBlock.Clone(builder, target)
            if (let Some(entry) <- entryBlock) {
                if (entry.nodeId == sourceBlock.nodeId) {
                    target.SetEntryBlock(clonedBlock)
                }
            }
            blockMap.add(sourceBlock.nodeId, clonedBlock)
        }
        for (clonedBlock in target.GetBlocks()) {
            if (let Some(term) <- clonedBlock.GetTerminator()) {
                let successors = term.GetSuccessors()
                var idx: Int64 = 0
                while (idx < successors.size) {
                    if (let Some(mappedBlock) <- blockMap.get(successors[idx].nodeId)) {
                        term.ReplaceSuccessor(idx, mappedBlock)
                    }
                    idx++
                }
            }
        }
    }

    public override func ToString(indent: Int64): String {
        var out = IndentToString(indent) + GetIdentifier() + " {"
        for (block in blocks) {
            out += "\n" + block.ToString(indent + 2)
        }
        return out + "\n" + IndentToString(indent) + "}"
    }
}

public open class GlobalValue <: Value {
    private var srcCodeIdentifier: String
    private var rawMangledName: String
    private var packageName: String
    private var declaredParent: Option<CustomTypeDef> = None
    private let features: ArrayList<String> = ArrayList<String>()
    private let annoInfo: AnnoInfo = AnnoInfo()
    private var linkage: Linkage = Linkage.EXTERNAL
    private var linkTypeInfo: BasicLinkage = BasicLinkage.EXTERNAL

    public init(kind: ValueKind, ty: Option<Type>, identifier: String, srcCodeIdentifier: String,
        rawMangledName: String, packageName: String) {
        super(ty, identifier, kind)
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        this.packageName = packageName
    }

    public func GetPackageName(): String {
        return packageName
    }

    public override func GetSrcCodeIdentifier(): String {
        return srcCodeIdentifier
    }

    public func SetSrcCodeIdentifier(name: String): Unit {
        srcCodeIdentifier = name
    }

    public func GetRawMangledName(): String {
        return rawMangledName
    }

    public func SetRawMangledName(name: String): Unit {
        rawMangledName = name
    }

    public func GetFeatures(): ArrayList<String> {
        let out = ArrayList<String>()
        for (feature in features) {
            out.add(feature)
        }
        return out
    }

    public func SetFeatures(newFeatures: ArrayList<String>): Unit {
        features.clear()
        for (feature in newFeatures) {
            if (!features.contains(feature)) {
                features.add(feature)
            }
        }
    }

    public func AddFeature(feature: String): Unit {
        if (!features.contains(feature)) {
            features.add(feature)
        }
    }

    public func GetParentCustomTypeDef(): Option<CustomTypeDef> {
        return declaredParent
    }

    public func SetOuterDeclaredOrExtendedDef(def: CustomTypeDef): Unit {
        declaredParent = def
    }

    public open func IsSrcCodeImported(): Bool {
        return TestAttr(Attribute.SRC_CODE_IMPORTED)
    }

    public func GetAnnoInfo(): AnnoInfo {
        return annoInfo
    }

    public func SetLinkage(value: Linkage): Unit {
        linkage = value
    }

    public func GetLinkage(): Linkage {
        return linkage
    }

    public func SetLinkTypeInfo(linkType: BasicLinkage): Unit {
        linkTypeInfo = linkType
        SetAnnotation("LinkTypeInfo", LinkTypeInfo(linkType).ToString())
    }

    public func GetLinkTypeInfo(): BasicLinkage {
        return linkTypeInfo
    }

    public open func DestroySelf(): Unit {}

    public func GlobalValueCommentToString(): String {
        let base = BaseCommentToString()
        if (features.isEmpty()) {
            return base
        }
        let featureText = "features=" + JoinStrings(features, ",")
        if (base.isEmpty()) {
            return featureText
        }
        return base + " " + featureText
    }
}

public class GlobalVar <: GlobalValue {
    private var initializer: Option<Value> = None

    public init(ty: Type, identifier: String, srcCodeIdentifier: String, rawMangledName: String, packageName: String) {
        super(ValueKind.KIND_GLOBALVAR, ty, identifier, srcCodeIdentifier, rawMangledName, packageName)
    }

    public override func AsGlobalVar(): Option<GlobalVar> { return this }

    public override func IsSrcCodeImported(): Bool {
        return TestAttr(Attribute.IMPORTED) && initializer.isSome()
    }

    public func IsLocalConst(): Bool {
        return TestAttr(Attribute.CONST) && TestAttr(Attribute.COMPILER_ADD)
    }

    public func GetInitializerValue(): Option<Value> {
        return initializer
    }

    public func SetInitializer(value: LiteralValue): Unit {
        initializer = value
    }

    public func GetInitializer(): Option<LiteralValue> {
        if (let Some(value) <- initializer) {
            return value as LiteralValue
        }
        return None
    }

    public func SetInitFunc(value: Function): Unit {
        initializer = value
    }

    public func DestroyInitializer(): Unit {
        if (let Some(fn) <- GetInitFunc()) {
            for (user in fn.GetUsers()) {
                user.RemoveSelfFromBlock()
            }
            fn.DestroySelf()
        }
        initializer = None
    }

    public func GetInitFunc(): Option<Function> {
        if (let Some(value) <- initializer) {
            return value as Function
        }
        return None
    }

    public override func DestroySelf(): Unit {
        if (let Some(parentDef) <- GetParentCustomTypeDef()) {
            let variables = ArrayList<GlobalVar>()
            for (variable in parentDef.GetStaticMemberVars()) {
                if (variable.nodeId != nodeId) {
                    variables.add(variable)
                }
            }
            parentDef.SetStaticMemberVars(variables)
        }
    }

    public override func ToString(indent: Int64): String {
        let typeText = if (let Some(valueTy) <- GetType()) { valueTy.ToString() } else { "<none>" }
        var out = IndentToString(indent) + GetAttributeInfo().ToString() + "global " + GetIdentifier() + ": " + typeText
        if (let Some(initValue) <- GetInitializer()) {
            out += " = " + initValue.ToString(0)
        } else if (let Some(fn) <- GetInitFunc()) {
            out += " = " + fn.GetIdentifier() + "()"
        }
        return out
    }
}

public class Function <: GlobalValue {
    private var funcKind: FuncKind = FuncKind.DEFAULT
    private var body: Option<BlockGroup> = None
    private let params: ArrayList<Parameter> = ArrayList<Parameter>()
    private let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    private var returnValue: Option<LocalVar> = None
    private var wrappedRawMethod: Option<Function> = None
    private var overrideSrcFuncType: Option<FuncType> = None
    private var genericDecl: Option<Function> = None
    private var paramDftValHostFunc: Option<Function> = None
    private var blockId: UInt64 = 0u64
    private var blockGroupId: UInt64 = 0u64
    private var localId: UInt64 = 0u64
    private var propLocation: DebugLocation = DebugLocation()
    private var originalLambdaInfo: Option<FuncSigInfo> = None

    public init(funcType: FuncType, identifier: String, srcCodeIdentifier: String, rawMangledName: String,
        packageName: String, genericTypeParams!: ArrayList<GenericType> = ArrayList<GenericType>()) {
        super(ValueKind.KIND_FUNC, funcType, identifier, srcCodeIdentifier, rawMangledName, packageName)
        for (param in genericTypeParams) {
            this.genericTypeParams.add(param)
        }
    }

    public override func AsFunction(): Option<Function> { return this }

    public func IsConstructor(): Bool {
        return (funcKind == FuncKind.CLASS_CONSTRUCTOR || funcKind == FuncKind.STRUCT_CONSTRUCTOR ||
            funcKind == FuncKind.PRIMAL_CLASS_CONSTRUCTOR || funcKind == FuncKind.PRIMAL_STRUCT_CONSTRUCTOR) &&
            !TestAttr(Attribute.STATIC)
    }

    public func IsFinalizer(): Bool { return funcKind == FuncKind.FINALIZER }
    public func IsGVInit(): Bool { return funcKind == FuncKind.GLOBALVAR_INIT }
    public func IsLambda(): Bool { return funcKind == FuncKind.LAMBDA }
    public func IsPrimalConstructor(): Bool {
        return funcKind == FuncKind.PRIMAL_CLASS_CONSTRUCTOR || funcKind == FuncKind.PRIMAL_STRUCT_CONSTRUCTOR
    }
    public func IsInstanceVarInit(): Bool { return funcKind == FuncKind.INSTANCEVAR_INIT }
    public func IsStaticInit(): Bool {
        return (funcKind == FuncKind.CLASS_CONSTRUCTOR || funcKind == FuncKind.STRUCT_CONSTRUCTOR) &&
            GetSrcCodeIdentifier() == "static.init"
    }

    public func GetFuncKind(): FuncKind { return funcKind }

    public func SetFuncKind(kind: FuncKind): Unit {
        funcKind = kind
    }

    public func GetGenericDecl(): Option<Function> { return genericDecl }
    public func SetGenericDecl(decl: Function): Unit { genericDecl = decl }

    public func AddGenericTypeParam(param: GenericType): Unit {
        genericTypeParams.add(param)
    }

    public func GetGenericTypeParams(): ArrayList<GenericType> {
        let out = ArrayList<GenericType>()
        for (param in genericTypeParams) {
            out.add(param)
        }
        return out
    }

    public func GetGenericTypeParamsRef(): ArrayList<GenericType> {
        return genericTypeParams
    }

    public func SetOriginalLambdaInfo(info: FuncSigInfo): Unit {
        if (funcKind != FuncKind.LAMBDA) {
            throw IllegalArgumentException("original lambda info requires lambda function")
        }
        originalLambdaInfo = info
    }

    public func GetOriginalLambdaType(): Option<FuncType> {
        if (funcKind == FuncKind.LAMBDA) {
            if (let Some(info) <- originalLambdaInfo) {
                return info.funcType
            }
            return None
        }
        return GetFuncType()
    }

    public func GetOriginalGenericTypeParams(): ArrayList<GenericType> {
        if (funcKind == FuncKind.LAMBDA) {
            if (let Some(info) <- originalLambdaInfo) {
                return info.GetGenericTypeParams()
            }
            return ArrayList<GenericType>()
        }
        return GetGenericTypeParams()
    }

    public func GetOriginalGenericTypeParamsRef(): ArrayList<GenericType> {
        if (funcKind == FuncKind.LAMBDA) {
            if (let Some(info) <- originalLambdaInfo) {
                return info.genericTypeParams
            }
            return ArrayList<GenericType>()
        }
        return genericTypeParams
    }

    public func IsFastNative(): Bool { return TestAttr(Attribute.FAST_NATIVE) }
    public func SetFastNative(fastNative: Bool): Unit {
        if (fastNative) { EnableAttr(Attribute.FAST_NATIVE) } else { DisableAttr(Attribute.FAST_NATIVE) }
    }

    public func IsCFFIWrapper(): Bool { return TestAttr(Attribute.CFFI_WRAPPER) }
    public func SetCFFIWrapper(isWrapper: Bool): Unit {
        if (isWrapper) { EnableAttr(Attribute.CFFI_WRAPPER) } else { DisableAttr(Attribute.CFFI_WRAPPER) }
    }

    public func GetParamDftValHostFunc(): Option<Function> { return paramDftValHostFunc }
    public func SetParamDftValHostFunc(hostFunc: Function): Unit { paramDftValHostFunc = hostFunc }
    public func ClearParamDftValHostFunc(): Unit { paramDftValHostFunc = None }

    public func GenerateBlockId(): UInt64 {
        let id = blockId
        blockId++
        return id
    }

    public func GenerateBlockGroupId(): UInt64 {
        blockGroupId++
        return blockGroupId
    }

    public func GenerateLocalId(): UInt64 {
        localId++
        return localId
    }

    public func SetLocalId(id: UInt64): Unit {
        localId = id
    }

    public func SetBlockId(id: UInt64): Unit {
        blockId = id
    }

    public func SetBlockGroupId(id: UInt64): Unit {
        blockGroupId = id
    }

    public func InheritIDFromFunc(fn: Function): Unit {
        blockId = fn.blockId
        blockGroupId = fn.blockGroupId
        localId = fn.localId
    }

    public func GetPropLocation(): DebugLocation { return propLocation }
    public func SetPropLocation(loc: DebugLocation): Unit { propLocation = loc }

    public func GetNumOfParams(): Int64 { return params.size }

    public func GetFuncType(): Option<FuncType> {
        if (let Some(ty) <- GetType()) {
            return ty as FuncType
        }
        return None
    }

    public func GetReturnType(): Option<Type> {
        if (let Some(funcTy) <- GetFuncType()) {
            return funcTy.GetReturnType()
        }
        return None
    }

    public func GetOverrideSrcFuncType(): Option<FuncType> { return overrideSrcFuncType }
    public func SetOverrideSrcFuncType(funcTy: FuncType): Unit { overrideSrcFuncType = funcTy }
    public func ClearOverrideSrcFuncType(): Unit { overrideSrcFuncType = None }

    public func GetWrappedRawMethod(): Option<Function> { return wrappedRawMethod }
    public func SetWrappedRawMethod(method: Function): Unit { wrappedRawMethod = method }
    public func ClearWrappedRawMethod(): Unit { wrappedRawMethod = None }

    public func GetBody(): Option<BlockGroup> { return body }

    public func InitBody(newBody: BlockGroup): Unit {
        if (body.isSome()) {
            throw IllegalArgumentException("function body already initialized")
        }
        body = newBody
        var updateOwner = true
        if (let Some(owner) <- newBody.GetOwnerFunc()) {
            updateOwner = owner.nodeId != nodeId
        }
        if (updateOwner) {
            newBody.SetOwnerFunc(this)
        }
    }

    public func ReplaceBody(newBody: BlockGroup): Unit {
        DestroyFuncBody()
        InitBody(newBody)
    }

    public func DestroyFuncBody(): Unit {
        returnValue = None
        if (let Some(funcBody) <- body) {
            for (block in funcBody.GetBlocks()) {
                for (expr in block.GetExpressions()) {
                    expr.RemoveSelfFromBlock()
                }
            }
        }
        body = None
    }

    public func GetEntryBlock(): Option<Block> {
        if (let Some(funcBody) <- body) {
            return funcBody.GetEntryBlock()
        }
        return None
    }

    public func AddParam(param: Parameter): Unit {
        params.add(param)
        param.SetOwnerFunc(this)
    }

    public func RemoveParams(): Unit {
        params.clear()
    }

    public func GetParam(index: Int64): Parameter {
        return params[index]
    }

    public func GetParams(): ArrayList<Parameter> {
        let out = ArrayList<Parameter>()
        for (param in params) {
            out.add(param)
        }
        return out
    }

    public func GetReturnValue(): Option<LocalVar> { return returnValue }
    public func HasReturnValue(): Bool { return returnValue.isSome() }
    public func SetReturnValue(ret: LocalVar): Unit {
        returnValue = ret
        ret.SetRetValue(true)
    }

    public func ReplaceReturnValue(newReturn: Option<LocalVar>, builder: CHIRBuilder): Unit {
        if (let Some(curFuncTy) <- GetFuncType()) {
            let paramTys = curFuncTy.GetParamTypes()
            let newReturnTy = if (let Some(newRet) <- newReturn) {
                if (let Some(retTy) <- newRet.GetType()) {
                    if (let Some(refTy) <- (retTy as RefType)) {
                        refTy.GetBaseType()
                    } else {
                        retTy
                    }
                } else {
                    builder.context.GetVoidTy()
                }
            } else {
                builder.context.GetVoidTy()
            }
            SetType(builder.context.GetFuncTy(paramTys, newReturnTy, hasVarLenParam: curFuncTy.HasVarArg(),
                isCFunc: curFuncTy.IsCFunc()))
        }
        if (let Some(oldRet) <- returnValue) {
            oldRet.SetRetValue(false)
        }
        returnValue = newReturn
        if (let Some(newRetValue) <- returnValue) {
            newRetValue.SetRetValue(true)
        }
    }

    public func GetExpressionsNum(): Int64 {
        if (let Some(funcBody) <- body) {
            return funcBody.GetExpressionsNum()
        }
        return 0
    }

    public func GetParentCustomTypeOrExtendedType(): Option<Type> {
        if (let Some(def) <- GetParentCustomTypeDef()) {
            return def.GetType()
        }
        return None
    }

    public func GetOuterDeclaredOrExtendedDef(): Option<CustomTypeDef> {
        let declaredParent = GetParentCustomTypeDef() ?? return None
        if (let Some(extendDef) <- (declaredParent as ExtendDef)) {
            if (let Some(extendedType) <- extendDef.GetExtendedType()) {
                if (let Some(customTy) <- (extendedType as CustomType)) {
                    return customTy.GetCustomTypeDef()
                }
            }
            return None
        }
        return declaredParent
    }

    public func IsMemberFunc(): Bool {
        return GetParentCustomTypeDef().isSome()
    }

    public func IsClassMethod(): Bool {
        if (let Some(outerDef) <- GetOuterDeclaredOrExtendedDef()) {
            return outerDef.IsClass()
        }
        return false
    }

    public func IsStructMethod(): Bool {
        if (let Some(outerDef) <- GetOuterDeclaredOrExtendedDef()) {
            return outerDef.IsStruct()
        }
        return false
    }

    public func IsEnumMethod(): Bool {
        if (let Some(outerDef) <- GetOuterDeclaredOrExtendedDef()) {
            return outerDef.IsEnum()
        }
        return false
    }

    public func IsInExtend(): Bool {
        if (let Some(def) <- GetParentCustomTypeDef()) {
            return def.GetCustomKind() == CustomDefKind.TYPE_EXTEND
        }
        return false
    }

    public func IsInGenericContext(): Bool {
        if (TestAttr(Attribute.GENERIC)) {
            return true
        }
        if (let Some(def) <- GetParentCustomTypeDef()) {
            return def.TestAttr(Attribute.GENERIC)
        }
        return false
    }

    public func IsCFunc(): Bool {
        if (let Some(valueTy) <- GetType()) {
            return valueTy.IsCFunc()
        }
        return false
    }

    public func IsVirtualFunc(): Bool {
        return TestAttr(Attribute.VIRTUAL) || TestAttr(Attribute.FINAL)
    }

    public func IsPureAbstract(): Bool {
        return TestAttr(Attribute.ABSTRACT) && body.isNone()
    }

    public override func IsSrcCodeImported(): Bool {
        return TestAttr(Attribute.IMPORTED) && body.isSome()
    }

    public override func DestroySelf(): Unit {
        if (let Some(parentDef) <- GetParentCustomTypeDef()) {
            let methods = ArrayList<Function>()
            for (method in parentDef.GetMethods()) {
                if (method.nodeId != nodeId) {
                    methods.add(method)
                }
            }
            parentDef.SetMethods(methods)
        }
        DestroyFuncBody()
    }

    public override func ToString(indent: Int64): String {
        let typeText = if (let Some(valueTy) <- GetType()) { valueTy.ToString() } else { "<none>" }
        var out = IndentToString(indent) + GetAttributeInfo().ToString() + "func " + GetIdentifier() +
            " [" + FuncKindName(funcKind) + "]: " + typeText
        let comments = ArrayList<String>()
        if (let Some(rawMethod) <- wrappedRawMethod) {
            if (rawMethod.GetBody().isSome()) {
                comments.add("wrapped raw method: " + rawMethod.GetIdentifier())
            }
        }
        if (let Some(funcTy) <- overrideSrcFuncType) {
            comments.add("OverrideSrcFuncType: " + funcTy.ToString())
        }
        if (!comments.isEmpty()) {
            out += " // " + JoinStrings(comments, ", ")
        }
        if (!params.isEmpty()) {
            let paramTexts = ArrayList<String>()
            for (param in params) {
                paramTexts.add(param.ToString(0))
            }
            out += "\n" + IndentToString(indent + 2) + "params: " + JoinStrings(paramTexts, ", ")
        }
        if (let Some(funcBody) <- body) {
            out += "\n" + funcBody.ToString(indent + 2)
        }
        return out
    }
}

public func IsNestedBlockOf(group: Option<BlockGroup>, scope: BlockGroup): Bool {
    if (let Some(curGroup) <- group) {
        if (curGroup.nodeId == scope.nodeId) {
            return true
        }
        if (let Some(ownerExpr) <- curGroup.GetOwnerExpression()) {
            return IsNestedBlockOf(ownerExpr.GetParentBlockGroup(), scope)
        }
    }
    return false
}
