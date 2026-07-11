package cjcj::chir

import cjcj::utils.{TaskQueue, TaskResult}
import std.collection.*

// C++ AnalysisWrapper.h:29-181. C++ parameter-pack construction is represented
// by createAnalysis at the concrete template-instantiation point; the optional
// InitialiseLetGVState operation represents IsValueAnalysis at :18-22.
public class AnalysisWrapper<TAnalysis, TDomain> where TDomain <: AbstractDomain<TDomain>,
    TAnalysis <: Analysis<TDomain> {
    private let builder: CHIRBuilder
    private let initialiseLetGVState: Option<(Package, CHIRBuilder) -> Unit>
    private let resultsMap: HashMap<Function, Option<Results<TDomain>>> =
        HashMap<Function, Option<Results<TDomain>>>()

    // C++ AnalysisWrapper.h:38-40.
    public init(builder: CHIRBuilder) {
        this.builder = builder
        this.initialiseLetGVState = None
    }

    // C++ AnalysisWrapper.h:38-40 plus IsValueAnalysis at :18-22. This
    // overload supplies the operation present only on value analyses.
    public init(builder: CHIRBuilder, initialiseLetGVState: (Package, CHIRBuilder) -> Unit) {
        this.builder = builder
        this.initialiseLetGVState = Some(initialiseLetGVState)
    }

    // C++ AnalysisWrapper.h:50-58. createAnalysis carries Args&&... because
    // Cangjie has no variadic generic function parameters.
    public func RunOnPackage(pkg: Package, isDebug: Bool, threadNum: Int64,
        createAnalysis: (Function, CHIRBuilder, Bool) -> TAnalysis): Unit {
        if (threadNum == 1) {
            RunOnPackageInSerial(pkg, isDebug, createAnalysis)
        } else {
            RunOnPackageInParallel(pkg, isDebug, threadNum, createAnalysis)
        }
    }

    // C++ AnalysisWrapper.h:68-74.
    public func RunOnFunc(funcValue: Function, isDebug: Bool,
        createAnalysis: (Function, CHIRBuilder, Bool) -> TAnalysis): Option<Results<TDomain>> {
        let analysis = createAnalysis(funcValue, builder, isDebug)
        return Engine<TDomain>(funcValue, analysis).IterateToFixpoint()
    }

    // C++ AnalysisWrapper.h:81-88.
    public func CheckFuncResult(funcValue: Function): Option<Results<TDomain>> {
        if (let Some(result) <- resultsMap.get(funcValue)) {
            return result
        }
        return None
    }

    // C++ AnalysisWrapper.h:93-96.
    public func InvalidateAllAnalysisResults(): Unit {
        resultsMap.clear()
    }

    // C++ AnalysisWrapper.h:103-111.
    public func InvalidateAnalysisResult(funcValue: Function): Bool {
        if (resultsMap.contains(funcValue)) {
            resultsMap.remove(funcValue)
            return true
        }
        return false
    }

    // C++ AnalysisWrapper.h:114-127.
    private func RunOnPackageInSerial(pkg: Package, isDebug: Bool,
        createAnalysis: (Function, CHIRBuilder, Bool) -> TAnalysis): Unit {
        if (initialiseLetGVState.isSome()) {
            SetUpGlobalVarState(pkg, isDebug, createAnalysis)
        }
        for (funcValue in pkg.GetGlobalFuncsWithBody()) {
            if (ShouldBeAnalysed(funcValue)) {
                if (let Some(result) <- RunOnFunc(funcValue, isDebug, createAnalysis)) {
                    if (!resultsMap.contains(funcValue)) {
                        resultsMap[funcValue] = Some(result)
                    }
                }
            }
        }
    }

    // C++ AnalysisWrapper.h:129-154.
    private func RunOnPackageInParallel(pkg: Package, isDebug: Bool, threadNum: Int64,
        createAnalysis: (Function, CHIRBuilder, Bool) -> TAnalysis): Unit {
        if (initialiseLetGVState.isSome()) {
            SetUpGlobalVarState(pkg, isDebug, createAnalysis)
        }
        let taskQueue = TaskQueue(threadNum)
        let results = ArrayList<TaskResult<Option<Results<TDomain>>>>()
        for (funcValue in pkg.GetGlobalFuncsWithBody()) {
            if (ShouldBeAnalysed(funcValue)) {
                results.add(taskQueue.AddTask<Option<Results<TDomain>>>({ =>
                    RunOnFunc(funcValue, isDebug, createAnalysis)
                }, priority: UInt64(funcValue.GetBody().getOrThrow().GetBlocks().size)))
            }
        }

        taskQueue.RunAndWaitForAllTasksCompleted()

        for (taskResult in results) {
            if (let Some(result) <- taskResult.get()) {
                if (!resultsMap.contains(result.functionValue)) {
                    resultsMap[result.functionValue] = Some(result)
                }
            }
        }
    }

    // C++ AnalysisWrapper.h:156-164.
    private func ShouldBeAnalysed(funcValue: Function): Bool {
        if (initialiseLetGVState.isSome() && resultsMap.contains(funcValue)) {
            return false
        }
        return TAnalysis.Filter(funcValue)
    }

    // C++ AnalysisWrapper.h:166-177.
    private func SetUpGlobalVarState(pkg: Package, isDebug: Bool,
        createAnalysis: (Function, CHIRBuilder, Bool) -> TAnalysis): Unit {
        initialiseLetGVState.getOrThrow()(pkg, builder)
        for (gv in pkg.GetGlobalVarsWithInit()) {
            if (let Some(initFunc) <- gv.GetInitFunc()) {
                if (gv.TestAttr(Attribute.READONLY) && !resultsMap.contains(initFunc)) {
                    resultsMap[initFunc] = RunOnFunc(initFunc, isDebug, createAnalysis)
                }
            }
        }
    }
}
