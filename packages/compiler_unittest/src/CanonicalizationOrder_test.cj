package cjcj::compiler_unittest

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::chir.BlockGroup
import cjcj::chir.CHIRBuilder
import cjcj::chir.ExprKind
import cjcj::chir.Package as ChirPackage
import cjcj::frontend.CompileStage
import cjcj::meta_transformation.CHIRPluginManager
import cjcj::meta_transformation.MetaTransform
import cjcj::option.CandidateEmitCHIRPhase

class CanonicalizationOrderProbe <: MetaTransform<ChirPackage> {
    public var nameAccessAtPlugin: Int64 = 0
    public var ran: Bool = false

    public init() {
        super()
    }

    public func Run(decl: ChirPackage): Unit {
        ran = true
        nameAccessAtPlugin = CountNameAccess(decl)
        println("PLUGIN_SAW name_access=${nameAccessAtPlugin}")
    }
}

private func CountNameAccess(pkg: ChirPackage): Int64 {
    var count: Int64 = 0
    for (fn in pkg.GetGlobalFuncsWithBody()) {
        if (let Some(body) <- fn.GetBody()) {
            count = count + CountNameAccessInGroup(body)
        }
    }
    return count
}

private func CountNameAccessInGroup(group: BlockGroup): Int64 {
    var count: Int64 = 0
    for (block in group.GetBlocks()) {
        for (expr in block.GetExpressions()) {
            let kind = expr.GetExprKind()
            if (kind == ExprKind.GET_ELEMENT_BY_NAME || kind == ExprKind.FIELD_BY_NAME) {
                count++
            }
            for (sub in expr.GetBlockGroups()) {
                count = count + CountNameAccessInGroup(sub)
            }
        }
    }
    return count
}

@Test
public class CanonicalizationOrderTest {
    @TestCase
    public func pluginSeesNameAccessBeforeCanonicalization(): Unit {
        let result = CompileSource("""
            package order_probe

            class Point {
                public var x: Int64 = 0
            }

            func readX(p: Point): Int64 {
                return p.x
            }
            """, stage: CompileStage.MANGLING)
        @Assert(result.ok)
        let probe = CanonicalizationOrderProbe()
        let instance = result.instance
        instance.invocation.globalOptions.emitCHIRPhase = CandidateEmitCHIRPhase.RAW
        instance.invocation.globalOptions.pluginPaths.add("order-probe")
        instance.metaTransformPluginBuilder.SetIsCppPlugin(true)
        instance.metaTransformPluginBuilder.RegisterCHIRPluginCallback({
            manager: CHIRPluginManager, _: CHIRBuilder => manager.AddMetaTransform(probe)
        })
        let chirOk = instance.PerformCHIRCompilation()
        @Assert(chirOk)
        @Assert(probe.ran)
        let packages = instance.chirData.getOrThrow().GetAllRealCHIRPackages()
        @Assert(!packages.isEmpty())
        let finalCount = CountNameAccess(packages[0])
        println("ORDER_ASSERT plugin_name_access=${probe.nameAccessAtPlugin} final_name_access=${finalCount}")
        @Assert(probe.nameAccessAtPlugin > 0)
        @Assert(finalCount == 0)
    }
}
