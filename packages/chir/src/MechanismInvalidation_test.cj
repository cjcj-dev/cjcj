package cjcj::chir

import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::option.GlobalOptions
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

func CheckMechanismIR(fn: Function, b: CHIRBuilder): Unit {
    let pkg = b.CreatePackage("fixture")
    pkg.AddGlobalFunc(fn)
    @Expect(CHIRChecker(pkg, GlobalOptions(), b).CheckPackage(ArrayList<CHIRCheckerRule>()), true)
}

// All observations below run the production Engine and Results replay.  The
// fixture builds typed CHIR; it never supplies abstract state to the analysis.
private class InvalidationFixture {
    let context = CHIRContext()
    let builder: CHIRBuilder
    let fn: Function
    let body: BlockGroup
    let entry: Block
    let x: Value
    let pointer: Value
    let before: Load
    let after = ArrayList<Load>()
    let valueTy: Type

    init(kind: String, nested!: Bool = false, write!: Bool = true) {
        builder = CHIRBuilder(context)
        fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()), "analysisHost", packageName: "fixture")
        let top = builder.CreateBlockGroup(fn)
        fn.InitBody(top)
        let topEntry = builder.CreateBlock(top)
        top.SetEntryBlock(topEntry)
        let ret = builder.CreateAllocate(context.GetRefTy(context.GetUnitTy()), context.GetUnitTy(), topEntry)
        topEntry.AppendExpression(ret)
        fn.SetReturnValue(ret.GetResult().getOrThrow())
        if (nested) {
            let ft = context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy())
            let lambda = builder.CreateLambda(ft, ft, topEntry, identifier: "nestedAnalysis")
            topEntry.AppendExpressions(ArrayList<Expression>([lambda, builder.CreateExit(None, topEntry)]))
            body = builder.CreateBlockGroup(fn)
            lambda.InitBody(body)
        } else {
            body = top
        }
        entry = if (nested) { builder.CreateBlock(body) } else { topEntry }
        body.SetEntryBlock(entry)
        valueTy = context.GetInt64Ty()
        if (nested) {
            let ret = builder.CreateAllocate(context.GetRefTy(context.GetUnitTy()), context.GetUnitTy(), entry)
            entry.AppendExpression(ret)
            let lambda = (body.GetOwnerExpression().getOrThrow() as Lambda).getOrThrow()
            lambda.SetReturnValue(ret.GetResult().getOrThrow())
        }
        let alloc = builder.CreateAllocate(context.GetRefTy(valueTy), valueTy, entry)
        x = alloc.GetResult().getOrThrow()
        let address = builder.CreateIntrinsic(context.GetCPointerTy(valueTy),
            IntrisicCallContext(kind: IntrinsicKind.INOUT_PARAM, args: ArrayList<Value>([x])), entry)
        let initPointer = builder.CreateIntrinsic(context.GetCPointerTy(valueTy),
            IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1, args: ArrayList<Value>([address.GetResult().getOrThrow()])), entry)
        pointer = initPointer.GetResult().getOrThrow()
        entry.AppendExpressions(ArrayList<Expression>([alloc, address, initPointer]))
        let seven = builder.CreateConstant(valueTy, IntLiteral(7), entry)
        entry.AppendExpression(seven)
        let value = seven.GetResult().getOrThrow()
        entry.AppendExpression(builder.CreateStore(value, x, entry))
        before = builder.CreateLoad(valueTy, x, entry)
        entry.AppendExpression(before)
        let normal = builder.CreateBlock(body)
        let error = builder.CreateBlock(body)
        // Without a potential write, the exact same escaped address and direct
        // store must retain the fact.  A parameter condition visits both edges.
        let trigger = if (write) {
            InvalidationTrigger(builder, kind, entry, normal, error, ArrayList<Value>([pointer]), valueTy)
        } else {
            let cond = builder.CreateParameter(context.GetBoolTy(), DebugLocation(), fn)
            builder.CreateBranch(cond, normal, error, entry)
        }
        entry.AppendExpression(trigger)
        if (!trigger.IsTerminator()) {
            let cond = builder.CreateParameter(context.GetBoolTy(), DebugLocation(), fn)
            entry.AppendExpression(builder.CreateBranch(cond, normal, error, entry))
        }
        for (block in ArrayList<Block>([normal, error])) {
            let load = builder.CreateLoad(valueTy, x, block)
            after.add(load)
            block.AppendExpressions(ArrayList<Expression>([load, builder.CreateExit(None, block)]))
        }
        let params = ArrayList<Type>()
        for (param in fn.GetParams()) { params.add(param.GetType().getOrThrow()) }
        fn.SetType(context.GetFuncTy(params, context.GetUnitTy()))
        CheckMechanismIR(fn, builder)
    }
}

// Matches Translator's ordinary/exceptional call and intrinsic builders. Spawn
// consumes a typed Future object without the optional ThreadContext argument;
// dispatch consumes a class receiver or RTTI.
private func InvalidationTrigger(b: CHIRBuilder, kind: String, block: Block, normal: Block, error: Block,
    pointers: ArrayList<Value>, valueTy: Type): Expression {
    let c = b.context
    if (kind == "intrinsic" || kind == "tryIntrinsic") {
        let zero = b.CreateConstant(c.GetInt64Ty(), IntLiteral(0), block)
        let two = b.CreateConstant(valueTy, IntLiteral(2), block)
        block.AppendExpressions(ArrayList<Expression>([zero, two]))
        let call = IntrisicCallContext(kind: IntrinsicKind.CPOINTER_WRITE,
            args: ArrayList<Value>([pointers[0], zero.GetResult().getOrThrow(), two.GetResult().getOrThrow()]),
            instTypeArgs: ArrayList<Type>([valueTy]))
        return if (kind == "intrinsic") { b.CreateIntrinsic(c.GetUnitTy(), call, block) }
            else { b.CreateTryIntrinsic(c.GetUnitTy(), call, normal, error, block) }
    }
    if (kind == "spawn" || kind == "trySpawn") {
        let def = b.CreateClassDef("std.core", "Future", "Future")
        let generic = c.GetGenericTy("FutureResult")
        def.AddGenericTypeParam(generic)
        def.SetType(c.GetClassTy(def, ArrayList<Type>([generic])))
        let ty = c.GetRefTy(c.GetClassTy(def, ArrayList<Type>([c.GetUnitTy()])))
        let future = b.CreateParameter(ty, DebugLocation(), block.GetTopLevelFunc().getOrThrow())
        return if (kind == "spawn") { b.CreateSpawn(ty, future, block) }
            else { b.CreateTrySpawn(ty, future, normal, error, block) }
    }
    let params = ArrayList<Type>()
    for (p in pointers) { params.add(p.GetType().getOrThrow()) }
    if (kind == "apply" || kind == "tryApply") {
        let callee = b.CreateFunction(c.GetFuncTy(params, c.GetUnitTy()), "unknownWriter")
        let call = FuncCallContext(args: pointers)
        return if (kind == "apply") { b.CreateApply(c.GetUnitTy(), callee, call, block) }
            else { b.CreateTryApply(c.GetUnitTy(), callee, call, normal, error, block) }
    }
    let def = b.CreateClassDef("fixture", "Receiver", "Receiver")
    def.EnableAttr(Attribute.VIRTUAL)
    let ty = c.GetClassTy(def, ArrayList<Type>())
    def.SetType(ty)
    let isStatic = kind == "invokeStatic" || kind == "tryInvokeStatic"
    let methodParams = ArrayList<Type>()
    if (!isStatic) { methodParams.add(c.GetRefTy(ty)) }
    for (param in params) { methodParams.add(param) }
    let callee = b.CreateFunction(c.GetFuncTy(methodParams, c.GetUnitTy()), "method", srcCodeIdentifier: "method")
    callee.EnableAttr(Attribute.PUBLIC)
    callee.EnableAttr(Attribute.VIRTUAL)
    def.AddMethod(callee)
    callee.SetOuterDeclaredOrExtendedDef(def)
    let caller: Value
    if (isStatic) {
        callee.EnableAttr(Attribute.STATIC)
        let rtti = b.CreateGetRTTIStatic(c.GetUnitTy(), ty, block)
        block.AppendExpression(rtti)
        caller = rtti.GetResult().getOrThrow()
    } else {
        caller = b.CreateParameter(c.GetRefTy(ty), DebugLocation(), block.GetTopLevelFunc().getOrThrow())
    }
    VTableGenerator(b).GenerateVTable(def)
    let call = InvokeCallContext(callee, caller, FuncCallContext(args: pointers, thisType: Some(ty)))
    return match (kind) {
        case "invoke" => b.CreateInvoke(c.GetUnitTy(), call, block)
        case "invokeStatic" => b.CreateInvokeStatic(c.GetUnitTy(), call, block)
        case "tryInvoke" => b.CreateTryInvoke(c.GetUnitTy(), call, normal, error, block)
        case "tryInvokeStatic" => b.CreateTryInvokeStatic(c.GetUnitTy(), call, normal, error, block)
        case _ => throw IllegalArgumentException("unknown invalidation fixture ${kind}")
    }
}

@Test
public class SharedValueInvalidationMechanismTest {
    private func CheckRange(kind: String, write: Bool, nested: Bool): Unit {
        let f = InvalidationFixture(kind, nested: nested, write: write)
        let result = Engine<RangeDomain>(f.fn, RangeAnalysis(f.fn, f.builder, BasicDiagnosticEngine())).IterateToFixpoint().getOrThrow()
        let seen = ArrayList<Int64>()
        result.VisitWith({ _: RangeDomain, _: Expression, _: Int64 => () },
            { state: RangeDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == f.before.nodeId) {
                    let value = (state.CheckAbstractValue(f.before.GetResult().getOrThrow()).getOrThrow() as SIntRange).getOrThrow()
                    @Expect(value.GetVal().IsSingleValue(), true)
                    @Expect(value.GetVal().NumericBound().GetSingleElement().SVal(), 7)
                    seen.add(expr.nodeId)
                }
                for (load in f.after) {
                    if (expr.nodeId == load.nodeId) {
                        let value = state.CheckAbstractValue(load.GetResult().getOrThrow())
                        let single = if (let Some(v) <- value) { (v as SIntRange).getOrThrow().GetVal().IsSingleValue() } else { false }
                        @Expect(single, !write)
                        if (!write) { @Expect((value.getOrThrow() as SIntRange).getOrThrow().GetVal().NumericBound().GetSingleElement().SVal(), 7) }
                        seen.add(expr.nodeId)
                    }
                }
            }, { _: RangeDomain, _: Expression, _: Option<Block> => () })
        @Expect(seen.size, 3)
        println("MECHANISM Range ${kind} write=${write} nested=${nested} observed=${seen.size}")
    }

    private func CheckType(kind: String, write: Bool): Unit {
        // INOUT accepts CType, not Class. Observe the location's concrete Int64
        // fact; a later primitive Load can infer its static result type again.
        let f = InvalidationFixture(kind, write: write)
        let pkg = f.builder.CreatePackage("typeFixture")
        let result = Engine<TypeDomain>(f.fn, TypeAnalysis(f.fn, f.builder, false, DevirtualizationInfo(pkg))).IterateToFixpoint().getOrThrow()
        let seen = ArrayList<Int64>()
        result.VisitWith({ state: TypeDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == f.before.nodeId) {
                    let value = state.GetAbstractDomain(f.x).getOrThrow().CheckAbsVal().getOrThrow()
                    @Expect(value.GetTypeKind(), DevirtualTyKind.EXACTLY)
                    @Expect(value.GetSpecificType() == f.valueTy, true)
                    seen.add(expr.nodeId)
                }
                for (load in f.after) {
                    if (expr.nodeId == load.nodeId) {
                        let value = state.GetAbstractDomain(f.x).getOrThrow().CheckAbsVal()
                        @Expect(value.isSome(), !write)
                        if (!write) { @Expect(value.getOrThrow().GetSpecificType() == f.valueTy, true) }
                        seen.add(expr.nodeId)
                    }
                }
            }, { _: TypeDomain, _: Expression, _: Int64 => () },
            { _: TypeDomain, _: Expression, _: Option<Block> => () })
        @Expect(seen.size, 3)
        println("MECHANISM Type CType ${kind} write=${write} observed=${seen.size}")
    }

    private func CheckTypeField(kind: String, write: Bool, nested!: Bool = false): Unit {
        let c = CHIRContext()
        let b = CHIRBuilder(c)
        let fn = b.CreateFunction(c.GetFuncTy(ArrayList<Type>(), c.GetUnitTy()), "classFieldHost", packageName: "fixture")
        let body = b.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = b.CreateBlock(body)
        body.SetEntryBlock(entry)
        let normal = b.CreateBlock(body)
        let error = b.CreateBlock(body)
        let ret = b.CreateAllocate(c.GetRefTy(c.GetUnitTy()), c.GetUnitTy(), entry)
        fn.SetReturnValue(ret.GetResult().getOrThrow())
        let def = b.CreateClassDef("fixture", "Concrete", "Concrete")
        let classTy = c.GetClassTy(def, ArrayList<Type>())
        def.SetType(classTy)
        def.EnableAttr(Attribute.VIRTUAL)
        let valueTy = c.GetRefTy(classTy)
        let holder = b.CreateStructDef("fixture", "Holder")
        let holderTy = c.GetStructTy(holder, ArrayList<Type>())
        holder.SetType(holderTy)
        holder.AddInstanceVar(MemberVarInfo("item", valueTy))
        let storageTy: Type = if (nested) {
            let outer = b.CreateStructDef("fixture", "OuterHolder")
            let ty = c.GetStructTy(outer, ArrayList<Type>())
            outer.SetType(ty)
            outer.AddInstanceVar(MemberVarInfo("holder", holderTy))
            ty
        } else { holderTy }
        let object = b.CreateAllocate(valueTy, classTy, entry)
        let storage = b.CreateAllocate(c.GetRefTy(storageTy), storageTy, entry)
        let address = b.CreateIntrinsic(c.GetCPointerTy(storageTy),
            IntrisicCallContext(kind: IntrinsicKind.INOUT_PARAM, args: ArrayList<Value>([storage.GetResult().getOrThrow()])), entry)
        let pointer = b.CreateIntrinsic(c.GetCPointerTy(storageTy),
            IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1, args: ArrayList<Value>([address.GetResult().getOrThrow()])), entry)
        let fieldBase: Value = if (nested) {
            let inner = b.CreateGetElementRef(c.GetRefTy(holderTy), storage.GetResult().getOrThrow(), ArrayList<UInt64>([0u64]), entry)
            entry.AppendExpressions(ArrayList<Expression>([ret, object, storage, address, pointer, inner]))
            inner.GetResult().getOrThrow()
        } else {
            entry.AppendExpressions(ArrayList<Expression>([ret, object, storage, address, pointer]))
            storage.GetResult().getOrThrow()
        }
        let field = b.CreateGetElementRef(c.GetRefTy(valueTy), fieldBase, ArrayList<UInt64>([0u64]), entry)
        let store = b.CreateStore(object.GetResult().getOrThrow(), field.GetResult().getOrThrow(), entry)
        let before = b.CreateLoad(valueTy, field.GetResult().getOrThrow(), entry)
        entry.AppendExpressions(ArrayList<Expression>([field, store, before]))
        let trigger = if (write) {
            InvalidationTrigger(b, kind, entry, normal, error, ArrayList<Value>([pointer.GetResult().getOrThrow()]), storageTy)
        } else {
            let cond = b.CreateParameter(c.GetBoolTy(), DebugLocation(), fn)
            b.CreateBranch(cond, normal, error, entry)
        }
        entry.AppendExpression(trigger)
        if (!trigger.IsTerminator()) {
            let cond = b.CreateParameter(c.GetBoolTy(), DebugLocation(), fn)
            entry.AppendExpression(b.CreateBranch(cond, normal, error, entry))
        }
        let after = ArrayList<Load>()
        let freshAfter = ArrayList<Load>()
        for (block in ArrayList<Block>([normal, error])) {
            let load = b.CreateLoad(valueTy, field.GetResult().getOrThrow(), block)
            after.add(load)
            let freshBase: Value = if (nested) {
                let inner = b.CreateGetElementRef(c.GetRefTy(holderTy), storage.GetResult().getOrThrow(), ArrayList<UInt64>([0u64]), block)
                block.AppendExpression(inner)
                inner.GetResult().getOrThrow()
            } else { storage.GetResult().getOrThrow() }
            let freshField = b.CreateGetElementRef(c.GetRefTy(valueTy), freshBase, ArrayList<UInt64>([0u64]), block)
            let fresh = b.CreateLoad(valueTy, freshField.GetResult().getOrThrow(), block)
            freshAfter.add(fresh)
            block.AppendExpressions(ArrayList<Expression>([load, freshField, fresh, b.CreateExit(None, block)]))
        }
        let params = ArrayList<Type>()
        for (param in fn.GetParams()) { params.add(param.GetType().getOrThrow()) }
        fn.SetType(c.GetFuncTy(params, c.GetUnitTy()))
        CheckMechanismIR(fn, b)
        let pkg = b.CreatePackage("typeFixture")
        let result = Engine<TypeDomain>(fn, TypeAnalysis(fn, b, false, DevirtualizationInfo(pkg))).IterateToFixpoint().getOrThrow()
        let seen = ArrayList<Int64>()
        result.VisitWith({ _: TypeDomain, _: Expression, _: Int64 => () },
            { state: TypeDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == before.nodeId) {
                    let value = state.GetAbstractDomain(before.GetResult().getOrThrow()).getOrThrow().CheckAbsVal().getOrThrow()
                    @Expect(value.GetTypeKind(), DevirtualTyKind.EXACTLY)
                    @Expect(value.GetSpecificType() == classTy, true)
                    seen.add(expr.nodeId)
                }
                for (load in after) {
                    if (expr.nodeId == load.nodeId) {
                        let snapshot = state.GetAbstractDomain(before.GetResult().getOrThrow()).getOrThrow().CheckAbsVal().getOrThrow()
                        @Expect(snapshot.GetTypeKind(), DevirtualTyKind.EXACTLY)
                        @Expect(snapshot.GetSpecificType() == classTy, true)
                        let domain = state.GetAbstractDomain(load.GetResult().getOrThrow())
                        let value: Option<TypeValue> = if (let Some(d) <- domain) { d.CheckAbsVal() } else { None }
                        @Expect(value.isSome(), !write)
                        if (!write) {
                            @Expect(value.getOrThrow().GetTypeKind(), DevirtualTyKind.EXACTLY)
                            @Expect(value.getOrThrow().GetSpecificType() == classTy, true)
                        }
                        seen.add(expr.nodeId)
                    }
                }
            }, { _: TypeDomain, _: Expression, _: Option<Block> => () })
        @Expect(seen.size, 3)
        // Base ValueAnalysis deliberately models aggregate children one level
        // deep; TypeAnalysis independently models these nested field addresses.
        if (!nested) { CheckFieldBindings(fn, b, before, freshAfter, write) }
        println("MECHANISM Type class-field ${kind} write=${write} nested=${nested} observed=${seen.size}")
    }

    private func CheckFieldBindings(fn: Function, b: CHIRBuilder, before: Load, after: ArrayList<Load>, write: Bool): Unit {
        let seen = ArrayList<Int64>()
        let constResult = ConstAnalysisWrapper(b).RunOnFunc(fn, BasicDiagnosticEngine()).getOrThrow()
        constResult.VisitWith({ _: ConstDomain, _: Expression, _: Int64 => () },
            { state: ConstDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == before.nodeId) {
                    @Expect(state.CheckAbstractObjectRefBy(before.GetResult().getOrThrow()).isSome(), true)
                    seen.add(expr.nodeId)
                }
                for (load in after) {
                    if (expr.nodeId == load.nodeId) {
                        @Expect(state.CheckAbstractObjectRefBy(load.GetResult().getOrThrow()).isSome(), !write)
                        @Expect(state.CheckAbstractObjectRefBy(before.GetResult().getOrThrow()).isSome(), true)
                        seen.add(expr.nodeId)
                    }
                }
            }, { _: ConstDomain, _: Expression, _: Option<Block> => () })
        let activeResult = ConstAnalysisWrapper(b).RunOnFuncWithPool(fn, BasicDiagnosticEngine()).getOrThrow()
        activeResult.VisitWith({ _: ConstPoolDomain, _: Expression, _: Int64 => () },
            { state: ConstPoolDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == before.nodeId) {
                    @Expect(state.CheckAbstractObjectRefBy(before.GetResult().getOrThrow()).isSome(), true)
                    seen.add(expr.nodeId)
                }
                for (load in after) {
                    if (expr.nodeId == load.nodeId) {
                        @Expect(state.CheckAbstractObjectRefBy(load.GetResult().getOrThrow()).isSome(), !write)
                        @Expect(state.CheckAbstractObjectRefBy(before.GetResult().getOrThrow()).isSome(), true)
                        seen.add(expr.nodeId)
                    }
                }
            }, { _: ConstPoolDomain, _: Expression, _: Option<Block> => () })
        let rangeResult = Engine<RangeDomain>(fn, RangeAnalysis(fn, b, BasicDiagnosticEngine())).IterateToFixpoint().getOrThrow()
        rangeResult.VisitWith({ _: RangeDomain, _: Expression, _: Int64 => () },
            { state: RangeDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == before.nodeId) {
                    @Expect(state.CheckAbstractObjectRefBy(before.GetResult().getOrThrow()).isSome(), true)
                    seen.add(expr.nodeId)
                }
                for (load in after) {
                    if (expr.nodeId == load.nodeId) {
                        @Expect(state.CheckAbstractObjectRefBy(load.GetResult().getOrThrow()).isSome(), !write)
                        @Expect(state.CheckAbstractObjectRefBy(before.GetResult().getOrThrow()).isSome(), true)
                        seen.add(expr.nodeId)
                    }
                }
            }, { _: RangeDomain, _: Expression, _: Option<Block> => () })
        @Expect(seen.size, 9)
        println("MECHANISM Const/Active/Range reference fields write=${write} observed=${seen.size}")
    }

    @TestCase public func TypeFieldCall(): Unit { CheckTypeField("apply", true) }
    @TestCase public func TypeFieldTryCall(): Unit { CheckTypeField("tryApply", true) }
    @TestCase public func TypeFieldNoWriteControl(): Unit { CheckTypeField("apply", false) }

    @TestCase public func TypeNestedFieldCall(): Unit { CheckTypeField("apply", true, nested: true) }
    @TestCase public func TypeNestedFieldTryCall(): Unit { CheckTypeField("tryApply", true, nested: true) }
    @TestCase public func TypeNestedFieldNoWriteControl(): Unit { CheckTypeField("apply", false, nested: true) }

    @TestCase public func TypeConcreteClassControl(): Unit {
        let c = CHIRContext()
        let b = CHIRBuilder(c)
        let fn = b.CreateFunction(c.GetFuncTy(ArrayList<Type>(), c.GetUnitTy()), "classControl", packageName: "fixture")
        let body = b.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = b.CreateBlock(body)
        body.SetEntryBlock(block)
        let def = b.CreateClassDef("fixture", "Concrete", "Concrete")
        let ty = c.GetClassTy(def, ArrayList<Type>())
        def.SetType(ty)
        let object = b.CreateAllocate(c.GetRefTy(ty), ty, block)
        let ret = b.CreateAllocate(c.GetRefTy(c.GetUnitTy()), c.GetUnitTy(), block)
        fn.SetReturnValue(ret.GetResult().getOrThrow())
        let callee = b.CreateFunction(c.GetFuncTy(ArrayList<Type>(), c.GetUnitTy()), "noAddressEscaped")
        let call = b.CreateApply(c.GetUnitTy(), callee, FuncCallContext(), block)
        block.AppendExpressions(ArrayList<Expression>([ret, object, call, b.CreateExit(None, block)]))
        CheckMechanismIR(fn, b)
        let pkg = b.CreatePackage("typeFixture")
        let result = Engine<TypeDomain>(fn, TypeAnalysis(fn, b, false, DevirtualizationInfo(pkg))).IterateToFixpoint().getOrThrow()
        let seen = ArrayList<Int64>()
        result.VisitWith({ _: TypeDomain, _: Expression, _: Int64 => () },
            { state: TypeDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == object.nodeId || expr.nodeId == call.nodeId) {
                    let value = state.GetAbstractDomain(object.GetResult().getOrThrow()).getOrThrow().CheckAbsVal().getOrThrow()
                    @Expect(value.GetTypeKind(), DevirtualTyKind.EXACTLY)
                    @Expect(value.GetSpecificType() == ty, true)
                    seen.add(expr.nodeId)
                }
            }, { _: TypeDomain, _: Expression, _: Option<Block> => () })
        @Expect(seen.size, 2)
    }

    private func CheckConst(kind: String, write: Bool, nested: Bool): Unit {
        let f = InvalidationFixture(kind, write: write, nested: nested)
        let result = ConstAnalysisWrapper(f.builder).RunOnFunc(f.fn, BasicDiagnosticEngine()).getOrThrow()
        let seen = ArrayList<Int64>()
        result.VisitWith({ _: ConstDomain, _: Expression, _: Int64 => () },
            { state: ConstDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == f.before.nodeId) {
                    @Expect(state.CheckAbstractValue(f.before.GetResult().getOrThrow()).isSome(), true)
                    @Expect((state.CheckAbstractValue(f.before.GetResult().getOrThrow()).getOrThrow() as ConstIntVal).getOrThrow().GetVal(), 7)
                    seen.add(expr.nodeId)
                }
                for (load in f.after) {
                    if (expr.nodeId == load.nodeId) {
                        @Expect(state.CheckAbstractValue(load.GetResult().getOrThrow()).isSome(), !write)
                        if (!write) { @Expect((state.CheckAbstractValue(load.GetResult().getOrThrow()).getOrThrow() as ConstIntVal).getOrThrow().GetVal(), 7) }
                        seen.add(expr.nodeId)
                    }
                }
            }, { _: ConstDomain, _: Expression, _: Option<Block> => () })
        @Expect(seen.size, 3)
        println("MECHANISM Const ${kind} write=${write} nested=${nested} observed=${seen.size}")
    }

    private func CheckActive(kind: String, write: Bool, nested: Bool): Unit {
        let f = InvalidationFixture(kind, write: write, nested: nested)
        let result = ConstAnalysisWrapper(f.builder).RunOnFuncWithPool(f.fn, BasicDiagnosticEngine()).getOrThrow()
        let seen = ArrayList<Int64>()
        result.VisitWith({ _: ConstPoolDomain, _: Expression, _: Int64 => () },
            { state: ConstPoolDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == f.before.nodeId) {
                    @Expect(state.CheckAbstractValue(f.before.GetResult().getOrThrow()).isSome(), true)
                    seen.add(expr.nodeId)
                }
                for (load in f.after) {
                    if (expr.nodeId == load.nodeId) {
                        @Expect(state.CheckAbstractValue(load.GetResult().getOrThrow()).isSome(), !write)
                        seen.add(expr.nodeId)
                    }
                }
            }, { _: ConstPoolDomain, _: Expression, _: Option<Block> => () })
        @Expect(seen.size, 3)
        println("MECHANISM ConstActive ${kind} write=${write} nested=${nested} observed=${seen.size}")
    }

    @TestCase public func RangeCall(): Unit { CheckRange("apply", true, false) }
    @TestCase public func RangePointerWrite(): Unit { CheckRange("intrinsic", true, false) }
    @TestCase public func RangeTryCall(): Unit { CheckRange("tryApply", true, false) }
    @TestCase public func RangeNoWriteControl(): Unit { CheckRange("apply", false, false) }
    @TestCase public func RangeRecursiveGroup(): Unit { CheckRange("apply", true, true) }
    @TestCase public func RangeRecursiveControl(): Unit { CheckRange("apply", false, true) }
    @TestCase public func TypeCall(): Unit { CheckType("apply", true) }
    @TestCase public func TypeTryCall(): Unit { CheckType("tryApply", true) }
    @TestCase public func TypeNoWriteControl(): Unit { CheckType("apply", false) }
    @TestCase public func ConstCall(): Unit { CheckConst("apply", true, false) }
    @TestCase public func ConstTryCall(): Unit { CheckConst("tryApply", true, false) }
    @TestCase public func ConstTryIntrinsic(): Unit { CheckConst("tryIntrinsic", true, false) }
    @TestCase public func ConstRecursiveGroup(): Unit { CheckConst("apply", true, true) }
    @TestCase public func ConstNoWriteControl(): Unit { CheckConst("apply", false, false) }
    @TestCase public func ConstRecursiveControl(): Unit { CheckConst("apply", false, true) }
    @TestCase public func ConstInvoke(): Unit { CheckConst("invoke", true, false) }
    @TestCase public func ConstInvokeStatic(): Unit { CheckConst("invokeStatic", true, false) }
    @TestCase public func ConstSpawn(): Unit { CheckConst("spawn", true, false) }
    @TestCase public func ConstTryInvoke(): Unit { CheckConst("tryInvoke", true, false) }
    @TestCase public func ConstTryInvokeStatic(): Unit { CheckConst("tryInvokeStatic", true, false) }
    @TestCase public func ConstTrySpawn(): Unit { CheckConst("trySpawn", true, false) }
    @TestCase public func ActiveCall(): Unit { CheckActive("apply", true, false) }
    @TestCase public func ActiveTryCall(): Unit { CheckActive("tryApply", true, false) }
    @TestCase public func ActiveRecursiveGroup(): Unit { CheckActive("apply", true, true) }
    @TestCase public func ActiveNoWriteControl(): Unit { CheckActive("apply", false, false) }
    @TestCase public func ActiveRecursiveControl(): Unit { CheckActive("apply", false, true) }
}

@Test
public class ReachingDefinitionDispatchMechanismTest {
    private func Check(kind: String, escaped!: Bool = true): Unit {
        let c = CHIRContext()
        let b = CHIRBuilder(c)
        let fn = b.CreateFunction(c.GetFuncTy(ArrayList<Type>(), c.GetUnitTy()), "rdaHost", packageName: "fixture")
        let body = b.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = b.CreateBlock(body)
        body.SetEntryBlock(block)
        let ret = b.CreateAllocate(c.GetRefTy(c.GetUnitTy()), c.GetUnitTy(), block)
        block.AppendExpression(ret)
        fn.SetReturnValue(ret.GetResult().getOrThrow())
        let normal = b.CreateBlock(body)
        let error = b.CreateBlock(body)
        let x = b.CreateAllocate(c.GetRefTy(c.GetInt64Ty()), c.GetInt64Ty(), block)
        let z = b.CreateAllocate(c.GetRefTy(c.GetInt64Ty()), c.GetInt64Ty(), block)
        let y = b.CreateAllocate(c.GetRefTy(c.GetInt64Ty()), c.GetInt64Ty(), block)
        block.AppendExpressions(ArrayList<Expression>([x, z, y]))
        let pointers = ArrayList<Value>()
        for (loc in ArrayList<Value>([x.GetResult().getOrThrow(), z.GetResult().getOrThrow()])) {
            if (escaped) {
                let address = b.CreateIntrinsic(c.GetCPointerTy(c.GetInt64Ty()),
                    IntrisicCallContext(kind: IntrinsicKind.INOUT_PARAM, args: ArrayList<Value>([loc])), block)
                let initPointer = b.CreateIntrinsic(c.GetCPointerTy(c.GetInt64Ty()),
                    IntrisicCallContext(kind: IntrinsicKind.CPOINTER_INIT1, args: ArrayList<Value>([address.GetResult().getOrThrow()])), block)
                block.AppendExpressions(ArrayList<Expression>([address, initPointer]))
                pointers.add(initPointer.GetResult().getOrThrow())
            } else {
                pointers.add(b.CreateParameter(c.GetCPointerTy(c.GetInt64Ty()), DebugLocation(), fn))
            }
        }
        let seven = b.CreateConstant(c.GetInt64Ty(), IntLiteral(7), block)
        let xStore = b.CreateStore(seven.GetResult().getOrThrow(), x.GetResult().getOrThrow(), block)
        let yStore = b.CreateStore(seven.GetResult().getOrThrow(), y.GetResult().getOrThrow(), block)
        let zBefore = b.CreateLoad(c.GetInt64Ty(), z.GetResult().getOrThrow(), block)
        block.AppendExpressions(ArrayList<Expression>([seven, xStore, yStore, zBefore]))
        let trigger: Expression
        if (kind == "store" || kind == "storeElement") {
            let element = if (kind == "store") { c.GetInt64Ty() } else {
                c.GetTupleTy(ArrayList<Type>([c.GetInt64Ty(), c.GetInt64Ty()]))
            }
            // Primitive/tuple ref parameters are not legal CHIR function
            // parameters. Derive the indirect address from a real array ref.
            let array = b.CreateParameter(c.GetRefTy(c.GetRawArrayTy(element)), DebugLocation(), fn)
            let index = b.CreateConstant(c.GetInt64Ty(), IntLiteral(0), block)
            let alias = b.CreateIntrinsic(c.GetRefTy(element),
                IntrisicCallContext(kind: IntrinsicKind.ARRAY_GET_REF_UNCHECKED,
                    args: ArrayList<Value>([array, index.GetResult().getOrThrow()])), block)
            block.AppendExpressions(ArrayList<Expression>([index, alias]))
            index.MoveBefore(seven)
            alias.MoveBefore(seven)
            trigger = if (kind == "store") {
                b.CreateStore(seven.GetResult().getOrThrow(), alias.GetResult().getOrThrow(), block)
            } else {
                b.CreateStoreElementRef(seven.GetResult().getOrThrow(), alias.GetResult().getOrThrow(), ArrayList<UInt64>([0u64]), block)
            }
        } else {
            trigger = InvalidationTrigger(b, kind, block, normal, error, pointers, c.GetInt64Ty())
        }
        block.AppendExpression(trigger)
        if (!trigger.IsTerminator()) {
            let cond = b.CreateParameter(c.GetBoolTy(), DebugLocation(), fn)
            block.AppendExpression(b.CreateBranch(cond, normal, error, block))
        }
        let targets = ArrayList<Load>()
        let controls = ArrayList<Load>()
        for (succ in ArrayList<Block>([normal, error])) {
            let lx = b.CreateLoad(c.GetInt64Ty(), x.GetResult().getOrThrow(), succ)
            let lz = b.CreateLoad(c.GetInt64Ty(), z.GetResult().getOrThrow(), succ)
            let ly = b.CreateLoad(c.GetInt64Ty(), y.GetResult().getOrThrow(), succ)
            targets.add(lx); targets.add(lz); controls.add(ly)
            succ.AppendExpressions(ArrayList<Expression>([lx, lz, ly, b.CreateExit(None, succ)]))
        }
        let params = ArrayList<Type>()
        for (param in fn.GetParams()) { params.add(param.GetType().getOrThrow()) }
        fn.SetType(c.GetFuncTy(params, c.GetUnitTy()))
        CheckMechanismIR(fn, b)
        let result = Engine<ReachingDefinitionDomain>(fn, ReachingDefinitionAnalysis(fn)).IterateToFixpoint().getOrThrow()
        let seen = ArrayList<Int64>()
        result.VisitWith({ state: ReachingDefinitionDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == trigger.nodeId) {
                    @Expect(state.CheckReachingDef(x.GetResult().getOrThrow()).isSome(), true)
                    @Expect(state.CheckReachingLoadDef(z.GetResult().getOrThrow()).isSome(), true)
                }
                for (target in targets) {
                    if (expr.nodeId == target.nodeId) {
                        @Expect(state.CheckReachingDef(x.GetResult().getOrThrow()).isNone(), escaped)
                        @Expect(state.CheckReachingLoadDef(z.GetResult().getOrThrow()).isNone(), escaped)
                        seen.add(expr.nodeId)
                    }
                }
                for (control in controls) {
                    if (expr.nodeId == control.nodeId) {
                        @Expect(state.CheckReachingDef(y.GetResult().getOrThrow()).getOrThrow().nodeId, yStore.nodeId)
                        seen.add(expr.nodeId)
                    }
                }
            }, { state: ReachingDefinitionDomain, expr: Expression, _: Int64 =>
                if (expr.nodeId == zBefore.nodeId) {
                    @Expect(state.CheckReachingDef(x.GetResult().getOrThrow()).isSome(), true)
                    @Expect(state.CheckReachingLoadDef(z.GetResult().getOrThrow()).isSome(), true)
                    seen.add(expr.nodeId)
                }
            },
            { state: ReachingDefinitionDomain, expr: Expression, _: Option<Block> =>
                if (expr.nodeId == trigger.nodeId) {
                    @Expect(state.CheckReachingDef(x.GetResult().getOrThrow()).isNone(), escaped)
                    @Expect(state.CheckReachingLoadDef(z.GetResult().getOrThrow()).isNone(), escaped)
                    seen.add(expr.nodeId)
                }
            })
        @Expect(seen.size, if (trigger.IsTerminator()) { 8 } else { 7 })
        RedundantLoadElimination().RunOnFunction(fn)
        for (target in targets) { @Expect(target.GetParentBlock().isSome(), escaped) }
        for (control in controls) { @Expect(control.GetParentBlock().isNone(), true) }
        println("MECHANISM RDA ${kind} targets=${targets.size} controls=${controls.size} observed=${seen.size} escaped=${escaped}")
    }

    @TestCase public func IndirectStore(): Unit { Check("store") }
    @TestCase public func StoreElement(): Unit { Check("storeElement") }
    @TestCase public func Invoke(): Unit { Check("invoke") }
    @TestCase public func InvokeStatic(): Unit { Check("invokeStatic") }
    @TestCase public func Spawn(): Unit { Check("spawn") }
    @TestCase public func TryApply(): Unit { Check("tryApply") }
    @TestCase public func TryIntrinsic(): Unit { Check("tryIntrinsic") }
    @TestCase public func TryInvoke(): Unit { Check("tryInvoke") }
    @TestCase public func TryInvokeStatic(): Unit { Check("tryInvokeStatic") }
    @TestCase public func TrySpawn(): Unit { Check("trySpawn") }
    @TestCase public func IndirectStoreNoEscapeControl(): Unit { Check("store", escaped: false) }
    @TestCase public func StoreElementNoEscapeControl(): Unit { Check("storeElement", escaped: false) }
    @TestCase public func InvokeNoEscapeControl(): Unit { Check("invoke", escaped: false) }
    @TestCase public func InvokeStaticNoEscapeControl(): Unit { Check("invokeStatic", escaped: false) }
    @TestCase public func SpawnNoEscapeControl(): Unit { Check("spawn", escaped: false) }
    @TestCase public func TryApplyNoEscapeControl(): Unit { Check("tryApply", escaped: false) }
    @TestCase public func TryIntrinsicNoEscapeControl(): Unit { Check("tryIntrinsic", escaped: false) }
    @TestCase public func TryInvokeNoEscapeControl(): Unit { Check("tryInvoke", escaped: false) }
    @TestCase public func TryInvokeStaticNoEscapeControl(): Unit { Check("tryInvokeStatic", escaped: false) }
    @TestCase public func TrySpawnNoEscapeControl(): Unit { Check("trySpawn", escaped: false) }

}
