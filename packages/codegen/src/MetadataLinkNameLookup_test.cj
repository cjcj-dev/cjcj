package cjcj::codegen

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::basic.DiagnosticEngine
import cjcj::chir.*
import cjcj::incremental_compilation.CachedMangleMap
import cjcj::option.{GlobalOptions, TripleInfo, OptimizationLevel}

// Metadata link-name lookup used to keep globals in EraseUselessGVAndFunctionsImpl.
// An entry compares up to its first NUL byte, as strcmp did.
@Test
public class MetadataLinkNameLookupTest {
    private func WithModule(nulEntry: Bool, body: (CGModule, LLVMModuleHandle) -> Unit): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("metadata_lookup_test")
        let options = GlobalOptions()
        options.host = TripleInfo()
        options.target = TripleInfo()
        options.optimizationLevel = OptimizationLevel.O2
        let diag = DiagnosticEngine()
        let pkgContext = CGPkgContext(CHIRData(context, pkg), options, false,
            NoHeapAllocChecker(diag), NoWriteBarrierRecChecker(diag), CachedMangleMap())
        let module = CGModule(SubCHIRPackage(1), pkgContext)
        try {
            let handle = module.GetLLVMModule().getOrThrow()
            let names = ArrayList<String>(["meta_keep", "shared_prefix_long"])
            if (nulEntry) {
                names.add(String.fromUtf8([110u8, 117u8, 108u8, 0u8, 116u8])) // "nul\0t"
            }
            LLVMAddNamedMetadataOperand(handle, METADATA_GLOBAL_VAR,
                LLVMCreateMDTupleFromStrings(module.GetLLVMContext(), names))
            body(module, handle)
        } finally {
            module.Clear()
            pkgContext.Clear()
        }
    }

    private func Used(module: CGModule, name: String): Bool {
        var used = false
        try (cName = unsafe { LibC.mallocCString(name) }.asResource()) {
            used = module.IsLinkNameUsedInMetaCString(cName.value)
        }
        return used
    }

    private func UsedBytes(module: CGModule, bytes: Array<UInt8>): Bool {
        let raw = unsafe { LibC.malloc<UInt8>(count: bytes.size + 1) }
        @Assert(!raw.isNull())
        var idx: Int64 = 0
        while (idx < bytes.size) {
            unsafe { (raw + idx).write(bytes[idx]) }
            idx++
        }
        unsafe { (raw + bytes.size).write(0u8) }
        let used = module.IsLinkNameUsedInMetaCString(unsafe { CString(raw) })
        unsafe { LibC.free(raw) }
        return used
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

    private func CheckRetention(nulEntry: Bool): Unit {
        WithModule(nulEntry) { module, handle =>
            for (name in ["meta_keep", "meta_kee", "meta_keep_x", "nul", "absent"]) {
                AddInternalGlobal(module, handle, name)
            }
            EraseUselessGVAndFunctionsImpl(module)
            @Expect(HasGlobal(handle, "meta_keep"), true)
            @Expect(HasGlobal(handle, "nul"), nulEntry)
            @Expect(HasGlobal(handle, "meta_kee"), false)
            @Expect(HasGlobal(handle, "meta_keep_x"), false)
            @Expect(HasGlobal(handle, "absent"), false)
            println("METADATA_RETENTION_ASSERT nulEntry=${nulEntry}")
        }
    }

    @TestCase
    public func ExactNamesAndSharedPrefixes(): Unit {
        WithModule(false) { module, _ =>
            @Expect(Used(module, "meta_keep"), true)
            @Expect(Used(module, "shared_prefix_long"), true)
            @Expect(Used(module, "meta_kee"), false)
            @Expect(Used(module, "meta_keep_"), false)
            @Expect(Used(module, "shared_prefix"), false)
            @Expect(Used(module, "absent"), false)
            @Expect(Used(module, ""), false)
            @Expect(UsedBytes(module, [109u8, 0xFFu8]), false)
        }
    }

    @TestCase
    public func NulEntryMatchesUpToNul(): Unit {
        WithModule(true) { module, _ =>
            @Expect(Used(module, "nul"), true)
            @Expect(Used(module, "nu"), false)
            @Expect(Used(module, "nult"), false)
            @Expect(Used(module, "meta_keep"), true)
            @Expect(Used(module, "meta_kee"), false)
            @Expect(UsedBytes(module, [0xFFu8]), false)
        }
    }

    @TestCase public func RetainsMetadataNamedGlobals(): Unit { CheckRetention(false) }
    @TestCase public func RetainsGlobalNamedBeforeNul(): Unit { CheckRetention(true) }
}
