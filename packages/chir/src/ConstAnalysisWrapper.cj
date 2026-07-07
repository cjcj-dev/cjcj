package cangjie_compiler::chir

import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import std.collection.*

private let OVERHEAD_BLOCK_SIZE: Int64 = 1000
private let USE_ACTIVE_BLOCK_SIZE: Int64 = 300

private enum ConstAnalysisStrategy {
    | SkipAnalysis | FullStatePool | ActiveStatePool
}

private func ConstAnalysisStrategyIndex(value: ConstAnalysisStrategy): Int64 {
    return match (value) {
        case ConstAnalysisStrategy.SkipAnalysis => 0
        case ConstAnalysisStrategy.FullStatePool => 1
        case ConstAnalysisStrategy.ActiveStatePool => 2
    }
}

extend ConstAnalysisStrategy <: Equatable<ConstAnalysisStrategy> {
    public operator func ==(right: ConstAnalysisStrategy): Bool {
        return ConstAnalysisStrategyIndex(this) == ConstAnalysisStrategyIndex(right)
    }

    public operator func !=(right: ConstAnalysisStrategy): Bool {
        return !(this == right)
    }
}

public class ConstAnalysisWrapper {
    private let builder: CHIRBuilder
    private let resultsMap: HashMap<Int64, Results<ConstDomain>> = HashMap<Int64, Results<ConstDomain>>()

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package, diag: BasicDiagnosticEngine, isDebug!: Bool = false): Unit {
        RunOnPackageInSerial(pkg, diag, isDebug: isDebug)
    }

    public func RunOnFunc(funcValue: Function, diag: BasicDiagnosticEngine,
        isDebug!: Bool = false): Option<Results<ConstDomain>> {
        let analysis = ConstAnalysis(funcValue, builder, diag, isDebug: isDebug)
        return Engine<ConstDomain>(funcValue, analysis).IterateToFixpoint()
    }

    public func CheckFuncResult(funcValue: Function): Option<Results<ConstDomain>> {
        return resultsMap.get(funcValue.nodeId)
    }

    public func InvalidateAllAnalysisResults(): Unit {
        resultsMap.clear()
    }

    private func RunOnPackageInSerial(pkg: Package, diag: BasicDiagnosticEngine, isDebug!: Bool = false): Unit {
        SetUpGlobalVarState(pkg, diag, isDebug: isDebug)
        for (funcValue in pkg.GetGlobalFuncsWithBody()) {
            let strategy = ChooseAnalysisStrategy(funcValue)
            if (strategy == ConstAnalysisStrategy.ActiveStatePool) {
                // GAP_TODO(valanalysis 批4): ActiveStatePool 保守跳过
                continue
            } else if (strategy == ConstAnalysisStrategy.FullStatePool) {
                if (let Some(result) <- RunOnFunc(funcValue, diag, isDebug: isDebug)) {
                    resultsMap[funcValue.nodeId] = result
                }
            }
        }
    }

    private func SetUpGlobalVarState(pkg: Package, diag: BasicDiagnosticEngine, isDebug!: Bool = false): Unit {
        ConstAnalysis.InitialiseLetGVState(pkg, builder)
        for (gv in pkg.GetGlobalVarsWithInit()) {
            if (let Some(initFunc) <- gv.GetInitFunc()) {
                if (gv.TestAttr(Attribute.READONLY) && !resultsMap.contains(initFunc.nodeId)) {
                    if (let Some(result) <- RunOnFunc(initFunc, diag, isDebug: isDebug)) {
                        resultsMap[initFunc.nodeId] = result
                    }
                }
            }
        }
    }

    private func ChooseAnalysisStrategy(funcValue: Function): ConstAnalysisStrategy {
        if (resultsMap.contains(funcValue.nodeId)) {
            return ConstAnalysisStrategy.SkipAnalysis
        }
        if (!ConstAnalysis.Filter(funcValue)) {
            return ConstAnalysisStrategy.SkipAnalysis
        }
        if (IsSTDFunction(funcValue)) {
            return ConstAnalysisStrategy.FullStatePool
        }
        let blockSize = CountBlockSize(funcValue)
        if (blockSize > OVERHEAD_BLOCK_SIZE) {
            return ConstAnalysisStrategy.SkipAnalysis
        } else if (blockSize > USE_ACTIVE_BLOCK_SIZE) {
            return ConstAnalysisStrategy.ActiveStatePool
        }
        return ConstAnalysisStrategy.FullStatePool
    }

    private static func GetBlockSize(expr: Expression): Int64 {
        if (expr.GetExprKind() != ExprKind.LAMBDA) {
            return 0
        }
        let lambda = (expr as Lambda).getOrThrow()
        let body = lambda.GetBody() ?? return 0
        return CountBlockGroupSize(body, OVERHEAD_BLOCK_SIZE + 1)
    }

    private static func CountBlockSize(funcValue: Function): Int64 {
        let body = funcValue.GetBody() ?? return 0
        return CountBlockGroupSize(body, OVERHEAD_BLOCK_SIZE + 1)
    }

    private static func CountBlockGroupSize(body: BlockGroup, limit: Int64): Int64 {
        var blockSize = body.GetBlocks().size
        if (blockSize > limit) {
            return limit
        }
        for (block in body.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                blockSize += GetBlockSize(expr)
                if (blockSize > limit) {
                    return limit
                }
            }
        }
        return blockSize
    }
}
