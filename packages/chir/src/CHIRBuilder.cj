package cangjie_compiler::chir

import std.collection.*

public class CHIRBuilder {
    public let context: CHIRContext

    public init(context: CHIRContext) {
        this.context = context
    }

    public func CreatePackage(name: String): Package {
        let pkg = Package(name)
        context.SetCurPackage(pkg)
        return pkg
    }

    public func CreateStructDef(packageName: String, identifier: String): StructDef {
        let def = StructDef(packageName, identifier)
        context.RegisterStruct(def)
        return def
    }

    public func CreateClassDef(packageName: String, identifier: String): ClassDef {
        let def = ClassDef(packageName, identifier)
        context.RegisterClass(def)
        return def
    }

    public func CreateEnumDef(packageName: String, identifier: String): EnumDef {
        let def = EnumDef(packageName, identifier)
        context.RegisterEnum(def)
        return def
    }

    public func CreateExtendDef(packageName: String, identifier: String): ExtendDef {
        let def = ExtendDef(packageName, identifier)
        context.RegisterExtend(def)
        return def
    }

    public func CreateFunction(funcType: FuncType, identifier: String, srcCodeIdentifier!: String = "",
        rawMangledName!: String = "", packageName!: String = ""): Function {
        let fn = Function(funcType, identifier, srcCodeIdentifier, rawMangledName, packageName)
        context.RegisterValue(fn)
        return fn
    }

    public func CreateGlobalVar(ty: Type, identifier: String, srcCodeIdentifier!: String = "",
        rawMangledName!: String = "", packageName!: String = ""): GlobalVar {
        let globalVar = GlobalVar(ty, identifier, srcCodeIdentifier, rawMangledName, packageName)
        context.RegisterValue(globalVar)
        return globalVar
    }

    public func CreateBlockGroup(identifier: String): BlockGroup {
        let group = BlockGroup(identifier)
        context.RegisterValue(group)
        return group
    }

    public func CreateBlock(identifier: String, parentGroup: Option<BlockGroup>): Block {
        let block = Block(identifier, parentGroup)
        context.RegisterValue(block)
        return block
    }

    public func CreateBlock(parentGroup: BlockGroup): Block {
        let owner = parentGroup.GetTopLevelFunc()
        let id = if (let Some(fn) <- owner) { fn.GenerateBlockId() } else { UInt64(context.GetAllNodesNum()) }
        return CreateBlock("bb${id}", parentGroup)
    }

    public func CreateParameter(ty: Type, identifier: String, ownerFunc: Option<Function>): Parameter {
        let param = Parameter(ty, identifier, ownerFunc)
        context.RegisterValue(param)
        return param
    }

    public func CreateLocalVar(ty: Type, identifier: String, expr: Option<Expression>): LocalVar {
        let local = LocalVar(ty, identifier, expr)
        context.RegisterValue(local)
        return local
    }

    public func CreateExpression(kind: ExprKind, resultTy: Option<Type>, operands: ArrayList<Value>,
        parent: Block): Expression {
        let expr = Expression(kind, operands, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        if (let Some(ty) <- resultTy) {
            let localName = "%${context.GetAllNodesNum()}"
            CreateLocalVar(ty, localName, expr)
        }
        return expr
    }

    public func CreateUnaryExpression(kind: ExprKind, resultTy: Type, operand: Value, parent: Block): UnaryExpression {
        let expr = UnaryExpression(kind, operand, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateBinaryExpression(kind: ExprKind, resultTy: Type, left: Value, right: Value,
        parent: Block): BinaryExpression {
        let expr = BinaryExpression(kind, left, right, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateConstant(resultTy: Type, literal: LiteralValue, parent: Block): Constant {
        let expr = Constant(literal, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateAllocate(resultTy: Type, allocatedTy: Type, parent: Block): Allocate {
        let expr = Allocate(allocatedTy, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateLoad(resultTy: Type, location: Value, parent: Block): Load {
        let expr = Load(location, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateStore(value: Value, location: Value, parent: Block): Store {
        let expr = Store(value, location, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        return expr
    }

    public func CreateGetElementRef(resultTy: Type, location: Value, path: ArrayList<UInt64>,
        parent: Block): GetElementRef {
        let expr = GetElementRef(location, path, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateGetElementByName(resultTy: Type, location: Value, names: ArrayList<String>,
        parent: Block): GetElementByName {
        let expr = GetElementByName(location, names, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateStoreElementRef(value: Value, location: Value, path: ArrayList<UInt64>,
        parent: Block): StoreElementRef {
        let expr = StoreElementRef(value, location, path, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        return expr
    }

    public func CreateStoreElementByName(value: Value, location: Value, names: ArrayList<String>,
        parent: Block): StoreElementByName {
        let expr = StoreElementByName(value, location, names, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        return expr
    }

    public func CreateApply(resultTy: Type, callee: Value, callContext: FuncCallContext, parent: Block): Apply {
        let expr = Apply(callee, callContext, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateInvoke(resultTy: Type, callContext: InvokeCallContext, parent: Block): Invoke {
        let expr = Invoke(callContext, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateInvokeStatic(resultTy: Type, callContext: InvokeCallContext, parent: Block): InvokeStatic {
        let expr = InvokeStatic(callContext, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateGetRTTI(resultTy: Type, value: Value, parent: Block): GetRTTI {
        let expr = GetRTTI(value, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateGetRTTIStatic(resultTy: Type, ty: Type, parent: Block): GetRTTIStatic {
        let expr = GetRTTIStatic(ty, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateTypeCast(resultTy: Type, source: Value, parent: Block): TypeCast {
        let expr = TypeCast(source, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateInstanceOf(resultTy: Type, value: Value, ty: Type, parent: Block): InstanceOf {
        let expr = InstanceOf(value, ty, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateTuple(resultTy: Type, values: ArrayList<Value>, parent: Block): Tuple {
        let expr = Tuple(values, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateField(resultTy: Type, value: Value, path: ArrayList<UInt64>, parent: Block): Field {
        let expr = Field(value, path, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateFieldByName(resultTy: Type, value: Value, names: ArrayList<String>, parent: Block): FieldByName {
        let expr = FieldByName(value, names, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateRawArrayAllocate(resultTy: Type, elementTy: Type, size: Value,
        parent: Block): RawArrayAllocate {
        let expr = RawArrayAllocate(elementTy, size, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateRawArrayLiteralInit(resultTy: Type, rawArray: Value, elements: ArrayList<Value>,
        parent: Block): RawArrayLiteralInit {
        let expr = RawArrayLiteralInit(rawArray, elements, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateRawArrayInitByValue(resultTy: Type, rawArray: Value, size: Value, initValue: Value,
        parent: Block): RawArrayInitByValue {
        let expr = RawArrayInitByValue(rawArray, size, initValue, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateVArray(resultTy: Type, elements: ArrayList<Value>, parent: Block): `VArray` {
        let expr = `VArray`(elements, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateVArrayBuilder(resultTy: Type, size: Value, item: Option<Value>, initFunc: Option<Value>,
        parent: Block): VArrayBuilder {
        let expr = VArrayBuilder(size, item, initFunc, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateGetException(resultTy: Type, parent: Block): GetException {
        let expr = GetException(parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateDebug(resultTy: Type, value: Value, srcCodeIdentifier: String, parent: Block): Debug {
        let expr = Debug(value, srcCodeIdentifier, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateSpawn(resultTy: Type, value: Value, parent: Block): Spawn {
        let expr = Spawn(value, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateSpawn(resultTy: Type, value: Value, arg: Value, parent: Block): Spawn {
        let expr = Spawn(value, arg, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateGetInstantiateValue(resultTy: Type, value: Value, instantiatedTypes: ArrayList<Type>,
        parent: Block): GetInstantiateValue {
        let expr = GetInstantiateValue(value, instantiatedTypes, parent)
        parent.AppendExpression(expr)
        context.RegisterExpression(expr)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", expr)
        return expr
    }

    public func CreateGoTo(target: Block, parent: Block): GoTo {
        let term = GoTo(target, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        return term
    }

    public func CreateBranch(cond: Value, trueBlock: Block, falseBlock: Block, parent: Block): Branch {
        let term = Branch(cond, trueBlock, falseBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        return term
    }

    public func CreateMultiBranch(cond: Value, defaultBlock: Block, vals: ArrayList<UInt64>,
        succs: ArrayList<Block>, parent: Block): MultiBranch {
        let term = MultiBranch(cond, defaultBlock, vals, succs, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        return term
    }

    public func CreateExit(value: Option<Value>, parent: Block): Exit {
        let term = Exit(value, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        return term
    }

    public func CreateRaiseException(value: Value, parent: Block): RaiseException {
        let term = RaiseException(value, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        return term
    }

    public func CreateRaiseException(value: Value, exceptionBlock: Block, parent: Block): RaiseException {
        let term = RaiseException(value, exceptionBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        return term
    }

    public func CreateApplyWithException(resultTy: Type, callee: Value, callContext: FuncCallContext,
        successBlock: Block, errorBlock: Block, parent: Block): ApplyWithException {
        let term = ApplyWithException(callee, callContext, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateInvokeWithException(resultTy: Type, callContext: InvokeCallContext, successBlock: Block,
        errorBlock: Block, parent: Block): InvokeWithException {
        let term = InvokeWithException(callContext, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateInvokeStaticWithException(resultTy: Type, callContext: InvokeCallContext, successBlock: Block,
        errorBlock: Block, parent: Block): InvokeStaticWithException {
        let term = InvokeStaticWithException(callContext, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateUnaryIntOpWithException(resultTy: Type, opKind: ExprKind, operand: Value, successBlock: Block,
        errorBlock: Block, parent: Block): IntOpWithException {
        let term = IntOpWithException(opKind, operand, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateBinaryIntOpWithException(resultTy: Type, opKind: ExprKind, left: Value, right: Value,
        successBlock: Block, errorBlock: Block, parent: Block): IntOpWithException {
        let term = IntOpWithException(opKind, left, right, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateTypeCastWithException(resultTy: Type, source: Value, successBlock: Block, errorBlock: Block,
        parent: Block): TypeCastWithException {
        let term = TypeCastWithException(source, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateAllocateWithException(resultTy: Type, allocatedTy: Type, successBlock: Block, errorBlock: Block,
        parent: Block): AllocateWithException {
        let term = AllocateWithException(allocatedTy, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateRawArrayAllocateWithException(resultTy: Type, elementTy: Type, size: Value,
        successBlock: Block, errorBlock: Block, parent: Block): RawArrayAllocateWithException {
        let term = RawArrayAllocateWithException(elementTy, size, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateSpawnWithException(resultTy: Type, value: Value, successBlock: Block, errorBlock: Block,
        parent: Block): SpawnWithException {
        let term = SpawnWithException(value, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }

    public func CreateSpawnWithException(resultTy: Type, value: Value, arg: Value, successBlock: Block,
        errorBlock: Block, parent: Block): SpawnWithException {
        let term = SpawnWithException(value, arg, successBlock, errorBlock, parent)
        parent.AppendExpression(term)
        context.RegisterExpression(term)
        CreateLocalVar(resultTy, "%${context.GetAllNodesNum()}", term)
        return term
    }
}
