package cjcj::chir

import std.collection.*
import std.sync.Mutex
import std.sort.*
import cjcj::basic.Range as BasicRange

// Every LLVM symbol CodeGen can request only while lowering Local Mode. Each name is selected in
// IRBuilder/OtherExprDispatcher from the same predicate that SetMemRegion used to place the region:
// region boundaries (START_REGION/END_REGION), Type.IsLocalRegion()/IsMustLocalRegion() allocations and
// generic copies, and ModalWrite MAYBE_LOCAL/DEMODE barriers. Ordinary heap code never requests them.
public let LOCAL_LOWERING_SYMBOLS: Array<String> = [
    "CJ_MCC_StartLocalRegion",
    "CJ_MCC_EndLocalRegion",
    "llvm.cj.malloc.local.object",
    "llvm.cj.malloc.local.array",
    "llvm.cj.malloc.local.array.generic",
    "llvm.cj.alloca.local.generic",
    "llvm.cj.assign.local.generic",
    "llvm.cj.maybe.local.write.ref",
    "llvm.cj.maybe.local.write.generic",
    "llvm.cj.demode.write.ref"
]

public func IsLocalLoweringSymbol(name: String): Bool {
    for (symbol in LOCAL_LOWERING_SYMBOLS) {
        if (symbol == name) { return true }
    }
    return false
}

public const LOCAL_LOWERING_TARGET_MESSAGE: String = "local mode lowering is only supported on Linux x86_64 GNU targets"

// Thrown from the emission point so no unsupported symbol ever reaches LLVMLookupIntrinsicID.
public class LocalLoweringUnsupportedException <: Exception {
    public init(symbol: String) {
        super(LOCAL_LOWERING_TARGET_MESSAGE + ": codegen requested '" + symbol + "'")
    }
}

public class LocalLoweringReport {
    public let functionName: String
    public let symbol: String
    public let position: (Bool, BasicRange)

    public init(functionName: String, symbol: String, position: (Bool, BasicRange)) {
        this.functionName = functionName
        this.symbol = symbol
        this.position = position
    }

    public func Message(): String {
        return LOCAL_LOWERING_TARGET_MESSAGE + ": '" + functionName + "' needs '" + symbol + "'"
    }
}

private func CompareLocalLoweringReport(left: LocalLoweringReport, right: LocalLoweringReport): Ordering {
    let l = left.position[1].begin
    let r = right.position[1].begin
    if (l.fileID != r.fileID) { return if (l.fileID < r.fileID) { Ordering.LT } else { Ordering.GT } }
    if (l.line != r.line) { return if (l.line < r.line) { Ordering.LT } else { Ordering.GT } }
    if (l.column != r.column) { return if (l.column < r.column) { Ordering.LT } else { Ordering.GT } }
    if (left.functionName != right.functionName) {
        return if (left.functionName < right.functionName) { Ordering.LT } else { Ordering.GT }
    }
    if (left.symbol != right.symbol) { return if (left.symbol < right.symbol) { Ordering.LT } else { Ordering.GT } }
    return Ordering.EQ
}

// Target capability gate consulted by CodeGen at the exact point a Local Mode symbol is requested.
// It therefore covers exactly the declarations, instantiations and imported bodies that CHIR handed
// to CodeGen, with no AST-side approximation of SetMemRegion or FaithfulAST2CHIR selection.
public class LocalLoweringTargetChecker {
    private let supported: Bool
    private let reportMutex: Mutex = Mutex()
    private let reports: ArrayList<LocalLoweringReport> = ArrayList<LocalLoweringReport>()

    public init(supported: Bool) {
        this.supported = supported
    }

    public func IsSupported(): Bool { return supported }

    public func Check(symbol: String, fn: Option<Function>, expr: Option<Expression>): Unit {
        if (supported || !IsLocalLoweringSymbol(symbol)) { return }
        var position = (false, BasicRange())
        if (let Some(e) <- expr) { position = GetDebugPos(e) }
        if (!position[0]) {
            if (let Some(f) <- fn) { position = GetDebugPos(f) }
        }
        let name = if (let Some(f) <- fn) {
            if (f.GetSrcCodeIdentifier().isEmpty()) { f.GetIdentifier() } else { f.GetSrcCodeIdentifier() }
        } else {
            "<module>"
        }
        synchronized(reportMutex) {
            reports.add(LocalLoweringReport(name, symbol, position))
        }
        throw LocalLoweringUnsupportedException(symbol)
    }

    public func GetReports(): ArrayList<LocalLoweringReport> {
        let sorted = synchronized(reportMutex) { ArrayList<LocalLoweringReport>(reports) }
        sort(sorted, by: CompareLocalLoweringReport, stable: true)
        return sorted
    }
}
