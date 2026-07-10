package cangjie_compiler::macro_pkg

import std.collection.*
import std.sync.Mutex

// C++ passes the live MacroCall* through one wrapper invocation
// (MacroEvaluationCJNative.cpp:56-70). The selfhost ABI keeps that lifetime
// while using a native Int64 cell as the stable, non-GC handle carrier.
private let macroCtxLock = Mutex()
private var macroCtxNextId: Int64 = 1
private let macroCtxTable = HashMap<Int64, MacroCall>()

func registerMacroCtx(macCall: MacroCall): (Int64, CPointer<Int64>) {
    let id = synchronized(macroCtxLock) {
        let currentId = macroCtxNextId
        macroCtxNextId++
        macroCtxTable[currentId] = macCall
        currentId
    }
    let handle = unsafe { LibC.malloc<Int64>() }
    if (handle.isNull()) {
        synchronized(macroCtxLock) {
            macroCtxTable.remove(id)
        }
        throw IllegalMemoryException("MacroCall handle allocation failed.")
    }
    unsafe { handle.write(id) }
    return (id, handle)
}

func unregisterMacroCtx(id: Int64, handle: CPointer<Int64>): Unit {
    synchronized(macroCtxLock) {
        macroCtxTable.remove(id)
    }
    unsafe { LibC.free(handle) }
}

func lookupMacroCtx(fptr: CPointer<Unit>): MacroCall {
    let id = unsafe { CPointer<Int64>(fptr).read() }
    return synchronized(macroCtxLock) {
        macroCtxTable.get(id).getOrThrow()
    }
}

// Mirrors libcangjie-std-ast ast_api.cpp:CJ_GetMacroPosition.
@C
public func CJ_GetMacroPosition(fptr: CPointer<Unit>, fileID: CPointer<UInt32>, line: CPointer<Int32>,
    column: CPointer<Int32>): Unit {
    let pos = lookupMacroCtx(fptr).GetBeginPos()
    unsafe {
        fileID.write(UInt32(pos.fileID))
        line.write(Int32(pos.line))
        column.write(Int32(pos.column))
    }
}
