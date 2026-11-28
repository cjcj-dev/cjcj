package cjcj::chir

import cjcj::basic.Linkage as BasicLinkage
import cjcj::option.{GlobalOptions, OutputMode}
import cjcj::utils.{ANNOTATION_VAR_POSTFIX, REFLECT_PACKAGE_NAME}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private class FunctionDCEFixture {
    let builder = CHIRBuilder(CHIRContext())
    let pkg: Package
    let ty: FuncType

    init() {
        pkg = builder.CreatePackage("function_dce")
        ty = builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetUnitTy())
    }

    func Add(name: String, isCFunc!: Bool = false): Function {
        let funcTy = if (isCFunc) {
            builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetUnitTy(), isCFunc: true)
        } else { ty }
        let fn = builder.CreateFunction(funcTy, name)
        fn.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        body.SetEntryBlock(builder.CreateBlock(body))
        return fn
    }

    func Call(caller: Function, callee: Function): Unit {
        let block = caller.GetEntryBlock().getOrThrow()
        block.AppendExpression(builder.CreateApply(builder.context.GetUnitTy(), callee, FuncCallContext(), block))
    }

    func Run(opts: GlobalOptions): Array<String> {
        DeadCodeElimination(builder).UselessFuncElimination(pkg, opts)
        let names = ArrayList<String>()
        for (fn in pkg.GetGlobalFunctionsRef()) { names.add(fn.GetIdentifierWithoutPrefix()) }
        return names.toArray()
    }
}

@Test
class DeadCodeEliminationTest {
    @TestCase
    func peelsCallsAndNestedAddressUsesUntilStable(): Unit {
        let f = FunctionDCEFixture()
        let leaf = f.Add("leaf")
        let cycleA = f.Add("cycle.a")
        let mid = f.Add("middle")
        let root = f.Add("dead.caller")
        let entryMain = f.Add("user.main")
        let cycleB = f.Add("cycle.b")
        let live = f.Add("live")
        let pinned = f.Add("pinned")
        f.Call(root, mid)
        f.Call(entryMain, live)
        f.Call(cycleA, cycleB)
        f.Call(cycleB, cycleA)
        // A registered user outside the removed bodies is still a use.
        let outside = Expression(ExprKind.TUPLE, ArrayList<Value>([pinned]), None)
        outside.ConnectOperandsAndGroups()
        let midEntry = mid.GetEntryBlock().getOrThrow()
        let b = f.builder
        let lambda = b.CreateLambda(f.ty, f.ty, midEntry)
        let body = b.CreateBlockGroup("nested")
        lambda.InitBody(body)
        let entry = b.CreateBlock(body)
        body.SetEntryBlock(entry)
        let address = b.CreateDebug(b.context.GetUnitTy(), leaf, "address use", entry)
        entry.AppendExpression(address)
        midEntry.AppendExpression(lambda)
        @Expect(mid.GetUsersRef().size, 1)
        @Expect(leaf.GetUsersRef().size, 1)

        @Expect(f.Run(GlobalOptions()), ["cycle.a", "user.main", "cycle.b", "live", "pinned"])
        @Expect(root.GetBody().isNone())
        @Expect(mid.GetBody().isNone())
        @Expect(leaf.GetBody().isNone())
        @Expect(live.GetBody().isSome())
        @Expect(f.pkg.TryGetGlobalFunc(leaf.GetIdentifier()).isNone())
        @Expect(f.pkg.TryGetGlobalFunc(live.GetIdentifier()).isSome())
    }

    @TestCase
    func keepsProtectionRootsInPackageOrder(): Unit {
        let f = FunctionDCEFixture()
        let _ = f.Add("dead.first")
        let imported = f.Add("imported")
        imported.EnableAttr(Attribute.IMPORTED)
        let _ = f.Add("user.main")
        f.pkg.SetPackageInitFunc(Some(f.Add("pkg.init")))
        f.pkg.SetPackageLiteralInitFunc(f.Add("literal.init"))
        let _ = f.Add("_CNat6Future.member")
        let anno = f.Add("factory")
        anno.SetFuncKind(FuncKind.ANNOFACTORY_FUNC)
        let _ = f.Add("backing" + ANNOTATION_VAR_POSTFIX)
        f.Add("public.c", isCFunc: true).EnableAttr(Attribute.PUBLIC)
        let _ = f.Add("private.c", isCFunc: true)
        f.Add("virtual").EnableAttr(Attribute.VIRTUAL)
        f.Add("final").EnableAttr(Attribute.FINAL)
        f.Add("ctor").SetFuncKind(FuncKind.CLASS_CONSTRUCTOR)
        f.Add("finalizer").SetFuncKind(FuncKind.FINALIZER)
        let _ = f.builder.CreateStruct(DebugLocation(), "Mirror", "Mirror", REFLECT_PACKAGE_NAME, true)
        f.Add("reflected").EnableAttr(Attribute.PUBLIC)
        let hidden = f.Add("hidden")
        hidden.EnableAttr(Attribute.PUBLIC)
        hidden.EnableAttr(Attribute.NO_REFLECT_INFO)
        f.Add("export").SetLinkTypeInfo(BasicLinkage.EXTERNAL)
        f.Add("main.entry").SetFuncKind(FuncKind.MAIN_ENTRY)
        let opts = GlobalOptions()
        opts.outputMode = OutputMode.SHARED_LIB
        @Expect(f.Run(opts), ["imported", "user.main", "pkg.init", "literal.init", "_CNat6Future.member", "factory",
            "backing" + ANNOTATION_VAR_POSTFIX, "public.c", "virtual", "final", "ctor", "finalizer", "reflected", "export"])

        let executable = FunctionDCEFixture()
        executable.Add("main.entry").SetFuncKind(FuncKind.MAIN_ENTRY)
        executable.Add("export").SetLinkTypeInfo(BasicLinkage.EXTERNAL)
        @Expect(executable.Run(GlobalOptions()), ["main.entry"])
    }
}
