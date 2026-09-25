package cjcj::chir

import std.collection.*
import cjcj::utils.FileUtil
import std.core.Box as CoreBox
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class StringBackingIntrinsicTest {
    @TestCase
    public func LookupBacking(): Unit {
        let actual = LookupCoreIntrinsicKind("canonicalizeStringBacking")
        @Expect(actual == Some(IntrinsicKind.CANONICALIZE_STRING_BACKING), true)
        println("BACKING_LOOKUP matched=${actual == Some(IntrinsicKind.CANONICALIZE_STRING_BACKING)}")
    }

    @TestCase
    public func LookupStackTraceControl(): Unit {
        @Expect(LookupCoreIntrinsicKind("fillInStackTrace") == Some(IntrinsicKind.FILL_IN_STACK_TRACE), true)
        @Expect(CHIRFB_INTRINSIC_KIND_FILL_IN_STACK_TRACE, 24u16)
        @Expect(CHIRFB_INTRINSIC_KIND_EXCLUSIVE_SCOPE, 361u16)
        println("STACK_TRACE_CONTROL executed")
    }

    private func RoundTrip(kind: IntrinsicKind, binary: Bool): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("backing")
        let arrayTy = context.GetRefTy(context.GetRawArrayTy(context.GetUInt8Ty()))
        let host = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([arrayTy]), arrayTy),
            "host", srcCodeIdentifier: "host", packageName: "backing")
        let arg = builder.CreateParameter(arrayTy, DebugLocation(), host)
        let body = builder.CreateBlockGroup(host)
        host.InitBody(body)
        pkg.SetPackageLiteralInitFunc(host)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let expr = builder.CreateIntrinsic(arrayTy,
            IntrisicCallContext(kind: kind, args: ArrayList<Value>([arg])), block)
        block.AppendExpression(expr)
        block.AppendExpression(builder.CreateExit(expr.GetResult(), block))
        let restoredContext = CHIRContext()
        let restoredBuilder = CHIRBuilder(restoredContext)
        if (binary) {
            let filename = "backing-${IntrinsicKindName(kind)}.chir"
            CHIRSerializer.Serialize(pkg, filename, ToCHIRPhase.RAW)
            let (ok, bytes, _) = FileUtil.ReadBinaryFileToBuffer(filename)
            @Expect(ok, true)
            let rawPackage = GetCHIRPackage(bytes)
            let kinds = rawPackage.GetExprs_type().getOrThrow()
            let values = rawPackage.GetExprs().getOrThrow()
            var idsObserved = 0
            for (index in 0u32..kinds.size()) {
                if (kinds.Get(index, 0u8) == CHIRFB_EXPRESSION_ELEM_INTRINSIC_BASE) {
                    let position = (values.Get(index) as Int64).getOrThrow()
                    let id = PackageFormat_IntrinsicBase(bytes, position).GetIntrinsicKind()
                    let expected = if (kind == IntrinsicKind.CANONICALIZE_STRING_BACKING) { 362u16 } else { 24u16 }
                    @Expect(id, expected)
                    idsObserved++
                    println("BACKING_WIRE_ID actual=${id} expected=${expected}")
                }
            }
            @Expect(idsObserved, 1)
            @Expect(CHIRDeserializer.Deserialize(filename, restoredBuilder,
                CoreBox<ToCHIRPhase>(ToCHIRPhase.RAW)), true)
        } else {
            CHIRDeserializerImpl(restoredBuilder).DeserializePackage(CHIRSerializerImpl().SerializePackage(pkg))
        }
        let restored = restoredContext.GetCurPackage().getOrThrow()
            .TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + "host").getOrThrow()
        var observed = 0
        for (value in restored.GetEntryBlock().getOrThrow().GetExpressions()) {
            if (let Some(intrinsic) <- (value as Intrinsic)) {
                observed++
                @Expect(intrinsic.GetIntrinsicKind() == kind, true)
                @Expect(intrinsic.GetArgs().size, 1)
                println("BACKING_ROUNDTRIP expected=${IntrinsicKindName(kind)} actual=${IntrinsicKindName(intrinsic.GetIntrinsicKind())} binary=${binary}")
            }
        }
        @Expect(observed, 1)
    }

    @TestCase public func BackingBinary(): Unit { RoundTrip(IntrinsicKind.CANONICALIZE_STRING_BACKING, true) }
    @TestCase public func BackingText(): Unit { RoundTrip(IntrinsicKind.CANONICALIZE_STRING_BACKING, false) }
    @TestCase public func StackTraceBinaryControl(): Unit { RoundTrip(IntrinsicKind.FILL_IN_STACK_TRACE, true) }
    @TestCase public func StackTraceTextControl(): Unit { RoundTrip(IntrinsicKind.FILL_IN_STACK_TRACE, false) }
}
