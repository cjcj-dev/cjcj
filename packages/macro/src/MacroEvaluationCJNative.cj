package cjcj::macro_pkg

import std.collection.HashMap
import std.sync.*

type InvokeNewTaskFromC = CFunc<(CPointer<Unit>, CPointer<Unit>) -> CPointer<Unit>>
type ReleaseHandleFromC = CFunc<(CPointer<Unit>) -> Unit>

// Mirrors src/Macro/MacroEvaluationCJNative.cpp:35-44 MacroInvoke.
class MacroInvoke {
    let macCall: MacroCall
    let mtx: Mutex = Mutex()
    let cv: Condition
    var isDataReady: Bool = false

    init(mc: MacroCall) {
        macCall = mc
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

// Mirrors src/Macro/MacroEvaluationCJNative.cpp:56-79 InvokeMacroFunc.
@C
func InvokeMacroFunc(mc: CPointer<Unit>): CPointer<Unit> {
    let macCall = lookupMacroCtx(mc)
    let _ = evaluateNativeMacro(macCall)
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
        let (ctxId, ctxHandle) = registerMacroCtx(mInvoke.macCall)
        try {
            let _ = unsafe { InvokeMacroFunc(CPointer<Unit>(ctxHandle)) }
        } finally {
            unregisterMacroCtx(ctxId, ctxHandle)
        }
        mInvoke.cv.notify()
    }
    return CPointer<Unit>()
}
