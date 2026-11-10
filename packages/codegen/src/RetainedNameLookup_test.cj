package cjcj::codegen

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::basic.DiagnosticEngine
import cjcj::chir.*
import cjcj::incremental_compilation.CachedMangleMap
import cjcj::option.{GlobalOptions, TripleInfo, OptimizationLevel}

// Name lookups that keep unused globals and functions in EraseUselessGVAndFunctionsImpl:
// the llvm.used names and the compile-unit globals of CGContext, and the metadata link
// names of a module that has none when the erase starts.
@Test
public class RetainedNameLookupTest {
    private func WithModule(body: (CGModule, LLVMModuleHandle) -> Unit): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("retained_name_lookup_test")
        let options = GlobalOptions()
        options.host = TripleInfo()
        options.target = TripleInfo()
        options.optimizationLevel = OptimizationLevel.O2
        let diag = DiagnosticEngine()
        let pkgContext = CGPkgContext(CHIRData(context, pkg), options, false,
            NoHeapAllocChecker(diag), NoWriteBarrierRecChecker(diag), CachedMangleMap())
        let module = CGModule(SubCHIRPackage(1), pkgContext)
        try {
            body(module, module.GetLLVMModule().getOrThrow())
        } finally {
            module.Clear()
            pkgContext.Clear()
        }
    }

    private func NulName(): String {
        return String.fromUtf8([110u8, 117u8, 108u8, 0u8, 116u8]) // "nul\0t"
    }

    // The scan and the lookup with precomputed state must agree for every name.
    private func LookupBytes(values: HashSet<String>, bytes: Array<UInt8>): Bool {
        let raw = unsafe { LibC.malloc<UInt8>(count: bytes.size + 1) }
        @Assert(!raw.isNull())
        var idx: Int64 = 0
        while (idx < bytes.size) {
            unsafe { (raw + idx).write(bytes[idx]) }
            idx++
        }
        unsafe { (raw + bytes.size).write(0u8) }
        let name = unsafe { CString(raw) }
        let scanned = CGContext.ContainsCString(values, name)
        let looked = CGContext.ContainsCString(values, CGContext.HasNulEntry(values), name,
            CGContext.CheckedString(name))
        unsafe { LibC.free(raw) }
        @Expect(looked, scanned)
        return looked
    }

    private func Lookup(values: HashSet<String>, name: String): Bool {
        return LookupBytes(values, name.toArray())
    }

    private func AddInternalGlobal(module: CGModule, handle: LLVMModuleHandle, name: String): Unit {
        let i64 = unsafe { LLVMInt64TypeInContext(module.GetLLVMContext().raw) }
        try (cName = unsafe { LibC.mallocCString(name) }.asResource()) {
            let global = unsafe { LLVMAddGlobal(handle.raw, i64, cName.value) }
            unsafe { LLVMSetInitializer(global, LLVMConstNull(i64)) }
            unsafe { LLVMSetLinkage(global, LLVMLinkageValue(LLVMLinkage.Internal)) }
        }
    }

    private func HasGlobal(handle: LLVMModuleHandle, name: String): Bool {
        var found = false
        try (cName = unsafe { LibC.mallocCString(name) }.asResource()) {
            found = !unsafe { LLVMGetNamedGlobal(handle.raw, cName.value) }.isNull()
        }
        return found
    }

    private func UsedInMeta(module: CGModule, name: String): Bool {
        var used = false
        try (cName = unsafe { LibC.mallocCString(name) }.asResource()) {
            used = module.IsLinkNameUsedInMetaCString(cName.value)
        }
        return used
    }

    @TestCase
    public func ExactNamesWithoutNulEntry(): Unit {
        let values = HashSet<String>(["used_keep", "shared_prefix_long", ""])
        @Expect(CGContext.HasNulEntry(values), false)
        @Expect(Lookup(values, "used_keep"), true)
        @Expect(Lookup(values, "shared_prefix_long"), true)
        @Expect(Lookup(values, ""), true)
        @Expect(Lookup(values, "used_kee"), false)
        @Expect(Lookup(values, "used_keep_"), false)
        @Expect(Lookup(values, "shared_prefix"), false)
        @Expect(LookupBytes(values, [117u8, 0xFFu8]), false)
        @Expect(Lookup(HashSet<String>(), "used_keep"), false)
        @Expect(Lookup(HashSet<String>(), ""), false)
        @Expect(CGContext.ContainsCString(values, false, unsafe { CString(CPointer<UInt8>()) }, None), false)
    }

    @TestCase
    public func NulEntryMatchesUpToNul(): Unit {
        let values = HashSet<String>(["used_keep", NulName()])
        @Expect(CGContext.HasNulEntry(values), true)
        @Expect(Lookup(values, "nul"), true)
        @Expect(Lookup(values, "nu"), false)
        @Expect(Lookup(values, "nult"), false)
        @Expect(Lookup(values, "used_keep"), true)
        @Expect(Lookup(values, "used_kee"), false)
        @Expect(LookupBytes(values, [0xFFu8]), false)
    }

    // No module metadata: the erase keeps exactly the names of the two context sets.
    // Compile-unit globals keep globals only up to an entry's NUL byte as well.
    @TestCase
    public func RetainsContextNamedGlobals(): Unit {
        WithModule { module, handle =>
            let cgCtx = module.GetCGContext()
            cgCtx.AddLLVMUsedVars("used_keep")
            cgCtx.AddGlobalsOfCompileUnit("cu_keep")
            cgCtx.AddGlobalsOfCompileUnit(NulName())
            for (name in ["used_keep", "used_kee", "cu_keep", "cu_keep_x", "nul", "nult", "absent"]) {
                AddInternalGlobal(module, handle, name)
            }
            EraseUselessGVAndFunctionsImpl(module)
            @Expect(HasGlobal(handle, "used_keep"), true)
            @Expect(HasGlobal(handle, "cu_keep"), true)
            @Expect(HasGlobal(handle, "nul"), true)
            @Expect(HasGlobal(handle, "used_kee"), false)
            @Expect(HasGlobal(handle, "cu_keep_x"), false)
            @Expect(HasGlobal(handle, "nult"), false)
            @Expect(HasGlobal(handle, "absent"), false)
        }
    }

    @TestCase
    public func RetainsUsedNameBeforeNul(): Unit {
        WithModule { module, handle =>
            module.GetCGContext().AddLLVMUsedVars(NulName())
            for (name in ["nul", "nu", "nult"]) {
                AddInternalGlobal(module, handle, name)
            }
            EraseUselessGVAndFunctionsImpl(module)
            @Expect(HasGlobal(handle, "nul"), true)
            @Expect(HasGlobal(handle, "nu"), false)
            @Expect(HasGlobal(handle, "nult"), false)
        }
    }

    // An erase over a module without metadata link names leaves no stale state: names added
    // to the metadata afterwards are seen by the lookup and keep their global in the next erase.
    @TestCase
    public func MetadataAddedAfterEmptyErase(): Unit {
        WithModule { module, handle =>
            for (name in ["late_keep", "absent"]) {
                AddInternalGlobal(module, handle, name)
            }
            EraseUselessGVAndFunctionsImpl(module)
            @Expect(HasGlobal(handle, "late_keep"), false)
            @Expect(HasGlobal(handle, "absent"), false)
            @Expect(UsedInMeta(module, "late_keep"), false)

            LLVMAddNamedMetadataOperand(handle, METADATA_GLOBAL_VAR,
                LLVMCreateMDTupleFromStrings(module.GetLLVMContext(), ArrayList<String>(["late_keep"])))
            @Expect(UsedInMeta(module, "late_keep"), true)
            for (name in ["late_keep", "absent"]) {
                AddInternalGlobal(module, handle, name)
            }
            EraseUselessGVAndFunctionsImpl(module)
            @Expect(HasGlobal(handle, "late_keep"), true)
            @Expect(HasGlobal(handle, "absent"), false)
        }
    }
}
