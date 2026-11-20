package cjcj::chir

import cjcj::ast.ASTMode
import cjcj::ast.PrimitiveTy as AstPrimitiveTy
import cjcj::ast.TypeKind as AstTypeKind
import cjcj::option.GlobalOptions
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// A function owning `var v: T` that an escaping lambda reads and the function later reassigns, so
// ClosureConversion must box `v`. `capturedModal` is the modal of T (official !2370 inputs).
private class ModalCaptureFixture {
    let builder = CHIRBuilder(CHIRContext())
    let pkg: Package
    let fn: Function
    let valueTy: Type

    init(copyable: Bool, capturedModal: ModalInfo) {
        let ctx = builder.context
        pkg = builder.CreatePackage("modal_capture")
        if (copyable) {
            valueTy = builder.WithModal(ctx.GetInt64Ty(), capturedModal)
        } else {
            let owner = builder.CreateClass(DebugLocation(), "Holder", "Holder", "modal_capture", true, false)
            let clsTy = ctx.GetClassTy(owner, ArrayList<Type>())
            owner.SetType(clsTy)
            valueTy = builder.WithModal(ctx.GetRefTy(clsTy), capturedModal)
        }
        fn = builder.CreateFunction(ctx.GetFuncTy(ArrayList<Type>([valueTy, valueTy]), ctx.GetUnitTy()), "capture",
            srcCodeIdentifier: "capture", packageName: "modal_capture")
        pkg.SetPackageInitFunc(fn)
        pkg.SetPackageLiteralInitFunc(fn)
        let initial = builder.CreateParameter(valueTy, DebugLocation(), fn)
        let updated = builder.CreateParameter(valueTy, DebugLocation(), fn)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let local = builder.CreateAllocate(ctx.GetRefTy(valueTy), valueTy, entry)
        let captured = local.GetResult().getOrThrow()
        entry.AppendExpressions(ArrayList<Expression>([local, builder.CreateStore(initial, captured, entry)]))
        let closureTy = ctx.GetFuncTy(ArrayList<Type>(), valueTy)
        let closure = builder.CreateLambda(closureTy, closureTy, entry, identifier: "_CN13modal_capture7captureEL_E")
        let closureBody = builder.CreateBlockGroup(fn)
        closure.InitBody(closureBody)
        let closureEntry = builder.CreateBlock(closureBody)
        closureBody.SetEntryBlock(closureEntry)
        let closureSlot = builder.CreateAllocate(ctx.GetRefTy(valueTy), valueTy, closureEntry)
        closure.SetReturnValue(closureSlot.GetResult().getOrThrow())
        let read = builder.CreateLoad(valueTy, captured, closureEntry)
        closureEntry.AppendExpressions(ArrayList<Expression>([closureSlot, read,
            builder.CreateStore(read.GetResult().getOrThrow(), closure.GetReturnValue().getOrThrow(), closureEntry),
            builder.CreateExit(None, closureEntry)]))
        // A stored closure escapes, so the capture survives LambdaInline and must be boxed.
        let sink = builder.CreateGlobalVar(ctx.GetRefTy(closureTy), "savedClosure")
        entry.AppendExpressions(ArrayList<Expression>([closure,
            builder.CreateStore(closure.GetResult().getOrThrow(), sink, entry),
            builder.CreateStore(updated, captured, entry), builder.CreateExit(None, entry)]))
        ClosureConversion(builder, opts: GlobalOptions()).RunOnPackage(pkg)
    }

    // The box allocation ClosureConversion inserted for `v`.
    func BoxAllocation(): Allocate {
        let found = ArrayList<Allocate>()
        for (block in fn.GetBody().getOrThrow().GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (let Some(alloc) <- (expr as Allocate)) {
                    if (let Some(classTy) <- (alloc.GetType() as ClassType)) {
                        if (classTy.GetClassDef().GetSrcCodeIdentifier().startsWith("$Captured_")) {
                            found.add(alloc)
                        }
                    }
                }
            }
        }
        if (found.size != 1) {
            throw IllegalStateException("expected exactly one box allocation, found ${found.size}")
        }
        return found[0]
    }
}

@Test
class ModalClosureBoxTest {
    private func Box(copyable: Bool, mode: CHIRMode): ClassType {
        let fixture = ModalCaptureFixture(copyable, ModalInfo(mode))
        let alloc = fixture.BoxAllocation()
        let boxTy = (alloc.GetType() as ClassType).getOrThrow()
        // The Allocate result is a reference to exactly the allocated (possibly modal) box type.
        let resultTy = (alloc.GetResult().getOrThrow().GetType().getOrThrow() as RefType).getOrThrow()
        @Expect(refEq(resultTy.GetBaseType(), boxTy), true)
        // Every box keeps the one class definition derived from the captured value type.
        @Expect(refEq(boxTy.GetClassDef().GetType().getOrThrow(), fixture.builder.WithModal(boxTy, ModalInfo())), true)
        return boxTy
    }

    @TestCase
    func ordinaryCaptureKeepsHeapBox(): Unit {
        let boxTy = Box(false, CHIRMode.NONE)
        @Expect(boxTy.IsModal(), false)
        @Expect(refEq(boxTy, boxTy.GetClassDef().GetType().getOrThrow()), true)
        @Expect(boxTy.ToString().startsWith("Class-$Captured_"), true)
        @Expect(boxTy.ToString().contains("@"), false)
    }

    @TestCase
    func mustLocalCaptureAllocatesBoxInLocalRegion(): Unit {
        let boxTy = Box(false, CHIRMode.MUST)
        @Expect(boxTy.GetModalInfo() == ModalInfo(CHIRMode.MUST), true)
        @Expect(boxTy.IsLocalRegion(), true)
        @Expect(boxTy.ToString().endsWith(" @local!"), true)
    }

    @TestCase
    func maybeLocalCaptureAllocatesBoxInMaybeRegion(): Unit {
        let boxTy = Box(false, CHIRMode.MAYBE)
        @Expect(boxTy.GetModalInfo() == ModalInfo(CHIRMode.MAYBE), true)
        @Expect(boxTy.IsMaybeLocalRegion(), true)
    }

    @TestCase
    func copyableModalCaptureOpensNoRegion(): Unit {
        // `Int64 @local?` is modal but Copyable: SetMemRegion opens no region, so neither does the box.
        let boxTy = Box(true, CHIRMode.MAYBE)
        @Expect(boxTy.IsModal(), false)
    }

    @TestCase
    func withModalInternsAndRestoresIdentity(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let ctx = builder.context
        let owner = builder.CreateClass(DebugLocation(), "Holder", "Holder", "modal_capture", true, false)
        let clsTy = ctx.GetClassTy(owner, ArrayList<Type>())
        owner.SetType(clsTy)
        let must = builder.WithModal(clsTy, ModalInfo(CHIRMode.MUST))
        @Expect(refEq(must, builder.WithModal(clsTy, ModalInfo(CHIRMode.MUST))), true)
        @Expect(refEq(must, clsTy), false)
        @Expect(refEq(builder.WithModal(must, ModalInfo()), clsTy), true)
        @Expect(clsTy.Hash() == must.Hash(), false)
        // Ref wrappers are looked through and kept.
        let refMust = (builder.WithModal(ctx.GetRefTy(clsTy), ModalInfo(CHIRMode.MUST)) as RefType).getOrThrow()
        @Expect(refEq(refMust.GetBaseType(), must), true)
        let maybeInt = builder.WithModal(ctx.GetInt64Ty(), ModalInfo(CHIRMode.MAYBE))
        @Expect(maybeInt.ToString(), "Int64 @local?")
        @Expect(maybeInt.IsLocalRegion(), false)
        @Expect(refEq(builder.WithModal(maybeInt, ModalInfo()), ctx.GetInt64Ty()), true)
    }

    @TestCase
    func translateResolvedModeFromAstType(): Unit {
        let builder = CHIRBuilder(CHIRContext())
        let chirType = CHIRType(builder, CHIRTypeCache())
        let astInt = AstPrimitiveTy(AstTypeKind.TYPE_INT64)
        @Expect(refEq(chirType.TranslateType(astInt, ASTMode.NOT), builder.context.GetInt64Ty()), true)
        @Expect(chirType.TranslateType(astInt, ASTMode.FULL).GetModalInfo() == ModalInfo(CHIRMode.MUST), true)
        @Expect(chirType.TranslateType(astInt, ASTMode.HALF).GetModalInfo() == ModalInfo(CHIRMode.MAYBE), true)
        // The unmoded translation is unchanged by a moded request.
        @Expect(refEq(chirType.TranslateType(astInt), builder.context.GetInt64Ty()), true)
    }
}
