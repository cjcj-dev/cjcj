package cjcj::macro_pkg

import std.collection.HashMap
import std.sync.*

type InvokeNewTaskFromC = CFunc<(CPointer<Unit>, CPointer<Unit>) -> CPointer<Unit>>
type ReleaseHandleFromC = CFunc<(CPointer<Unit>) -> Unit>
type InitGlobalFuncPtr = CFunc<(CPointer<ResetNotify>) -> CPointer<Unit>>

// ABI v2 (ir2): callback(context, kind, typeBytes, typeLength, messageBytes, messageLength).
// Pointers refer to native UTF-8 bytes retained by R until this synchronous
// callback returns. No R managed value is visible to the host callback.
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
    // Allocate before submitting the task: even notification allocation failure
    // must return through the C ABI without throwing into the target runtime.
    let notificationFailure = IllegalStateException("macro reset error notification could not be copied; original details unavailable")
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

// The host owns this error record, not the target's dynamic Exception/Error.
class MacroResetFailure <: Exception {
    let remoteKind: UInt32
    let remoteType: String
    let remoteMessage: String

    init(kind: UInt32, typeName: String, message: String) {
        super("macro reset failed (kind=" + kind.toString() + ", type=" + typeName + "): " + message)
        remoteKind = kind
        remoteType = typeName
        remoteMessage = message
    }
}

private func CopyResetBytes(bytes: CPointer<UInt8>, length: UIntNative): String {
    if (length == 0) { return "" }
    if (bytes.isNull()) { throw IllegalArgumentException("macro reset notification has null nonempty bytes") }
    let copy = Array<UInt8>(Int64(length), { i => unsafe { bytes.read(i) } })
    return String.fromUtf8(copy)
}

@C
func ResetVariableFinishNotify(mi: CPointer<Unit>, kind: UInt32, typeBytes: CPointer<UInt8>,
    typeLength: UIntNative, messageBytes: CPointer<UInt8>, messageLength: UIntNative): Int32 {
    try {
        return RecordResetNotification(mi, kind, typeBytes, typeLength, messageBytes, messageLength)
    } catch (_: Exception) {
        return -1
    } catch (_: Error) {
        return -1
    }
}

private func RecordResetNotification(mi: CPointer<Unit>, kind: UInt32, typeBytes: CPointer<UInt8>,
    typeLength: UIntNative, messageBytes: CPointer<UInt8>, messageLength: UIntNative): Int32 {
    if (mi.isNull()) { return -1 }
    let id = unsafe { CPointer<Int64>(mi).read() }
    let entry = synchronized(macroInvokeTableLock) { macroInvokeTable.get(id) }
    // The submitting owner detects a missing notification after GetTaskRet.
    if (entry.isNone()) { return -1 }
    let mInvoke = entry.getOrThrow()
    synchronized(mInvoke.mtx) {
        var status: Int32 = 0
        try {
            if (mInvoke.isDataReady || kind > 4) { throw mInvoke.notificationFailure }
            if (kind == 0) {
                if (typeLength != 0 || messageLength != 0) { throw mInvoke.notificationFailure }
            } else {
                let typeName = CopyResetBytes(typeBytes, typeLength)
                let message = CopyResetBytes(messageBytes, messageLength)
                if ((kind == 1 || kind == 2) && typeName.isEmpty()) { throw mInvoke.notificationFailure }
                mInvoke.failure = Some(MacroResetFailure(kind, typeName, message))
            }
        } catch (e: Exception) {
            if (mInvoke.failure.isNone()) { mInvoke.failure = Some(e) }
            status = -1
        } catch (_: Error) {
            if (mInvoke.failure.isNone()) { mInvoke.failure = Some(mInvoke.notificationFailure) }
            status = -1
        }
        // Publish only after the result was actually stored. If even storing
        // the failure throws, the outer C callback returns -1 and leaves this
        // predicate unset; the generated task's result also rejects success.
        mInvoke.isDataReady = true
        return status
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
