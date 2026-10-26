package cjcj::macro_pkg

import std.collection.HashMap
import std.sync.*

type InvokeNewTaskFromC = CFunc<(CPointer<Unit>, CPointer<Unit>) -> CPointer<Unit>>
type ReleaseHandleFromC = CFunc<(CPointer<Unit>) -> Unit>
type InitGlobalFuncPtr = CFunc<(CPointer<ResetNotify>) -> CPointer<Unit>>

// Mirrors src/Macro/MacroEvaluationCJNative.cpp:27-33 ResetNotify.
@C
struct ResetNotify {
    let cFunc: CPointer<Unit>
    let param: CPointer<Unit>

    init(cFunc: CPointer<Unit>, param: CPointer<Unit>) {
        this.cFunc = cFunc
        this.param = param
    }
}

// Mirrors src/Macro/MacroEvaluationCJNative.cpp:35-44 MacroInvoke.
class MacroInvoke {
    let macCall: Option<MacroCall>
    let mtx: Mutex = Mutex()
    let cv: Condition
    var isDataReady: Bool = false
    var failure: Option<Exception> = None
    // Kept by macroInvokeTable until the corresponding R future is DONE.
    var argument = CPointer<Int64>()
    var resetArgument = CPointer<ResetNotify>()

    init(mc: MacroCall) {
        macCall = Some(mc)
        synchronized(mtx) {
            cv = mtx.condition()
        }
    }

    init() {
        macCall = None
        synchronized(mtx) {
            cv = mtx.condition()
        }
    }
}

// C++ passes MacroInvoke* through RunCJTask. A native Int64 cell carries the
// equivalent object identity across the selfhost C ABI without exposing a GC address.
let macroInvokeTableLock = Mutex()
let macroInvokeTable = HashMap<Int64, MacroInvoke>()
var macroInvokeNextId: Int64 = 1

// Mirrors src/Macro/MacroEvaluationCJNative.cpp:46-54 ResetVariableFinishNotify.
@C
func ResetVariableFinishNotify(mi: CPointer<Unit>): Unit {
    let id = unsafe { CPointer<Int64>(mi).read() }
    let mInvoke = synchronized(macroInvokeTableLock) {
        macroInvokeTable.get(id).getOrThrow()
    }
    synchronized(mInvoke.mtx) {
        mInvoke.isDataReady = true
        mInvoke.cv.notify()
    }
}

// Mirrors src/Macro/MacroEvaluationCJNative.cpp:56-79 InvokeMacroFunc.
@C
func InvokeMacroFunc(mc: CPointer<Unit>): CPointer<Unit> {
    let macCall = lookupMacroCtx(mc)
    // false has already marked FAIL/ILLEGAL; it must never become SUCCESS
    // merely because the task completed and published its readiness.
    let succeeded = evaluateNativeMacro(macCall)
    if (!succeeded) { macCall.status = MacroEvalStatus.FAIL }
    macCall.isDataReady = true
    return CPointer<Unit>()
}

// Mirrors src/Macro/MacroEvaluationCJNative.cpp:81-91 InvokeMacro.
@C
func InvokeMacro(mi: CPointer<Unit>): CPointer<Unit> {
    let id = unsafe { CPointer<Int64>(mi).read() }
    let mInvoke = synchronized(macroInvokeTableLock) {
        macroInvokeTable.get(id).getOrThrow()
    }
    synchronized(mInvoke.mtx) {
        try {
            let (ctxId, ctxHandle) = registerMacroCtx(mInvoke.macCall.getOrThrow())
            var failed = false
            try {
                let _ = unsafe { InvokeMacroFunc(CPointer<Unit>(ctxHandle)) }
            } catch (e: Exception) {
                failed = true
                throw e
            } finally {
                try {
                    unregisterMacroCtx(ctxId, ctxHandle)
                } catch (e: Exception) {
                    if (!failed) { throw e }
                }
            }
        } catch (e: Exception) {
            // Do not unwind a host Cangjie exception across the R callback ABI.
            // The submitting host rethrows this same object after R reports DONE.
            mInvoke.failure = Some(e)
            mInvoke.macCall.getOrThrow().status = MacroEvalStatus.FAIL
        } finally {
            mInvoke.cv.notify()
        }
    }
    return CPointer<Unit>()
}
