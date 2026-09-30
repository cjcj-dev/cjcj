package cjcj::basic

import std.unittest.*
import std.unittest.testmacro.*

@Test
class DiagnosticCacheTest {
    // C++ DiagnosticEngine.h:741-754: an empty vector has no reserved storage.
    @TestCase
    func emptyCacheHasNoReservedStorage(): Unit {
        let cache = DiagnosticCache()
        @Expect(cache.cachedDiags.capacity, 0)
        @Expect(cache.cachedDiags.size, 0)
    }

    // C++ DiagnosticEngine.cpp:1136-1145: replace the prefix with a new suffix vector.
    @TestCase
    func backUpOwnsOnlyTheNewDiagnosticSuffix(): Unit {
        let previous = Diagnostic()
        previous.errorMessage = "previous"
        let added = Diagnostic()
        added.errorMessage = "suffix"
        let before = DiagnosticEngine()
        before.SetStoredDiags(Array<Diagnostic>(32, repeat: previous))
        let after = DiagnosticEngine()
        after.SetStoredDiags(Array<Diagnostic>(33, { idx => if (idx < 32) { previous } else { added } }))
        let cache = DiagnosticCache()
        cache.ToExclude(before)
        cache.BackUp(after)
        @Expect(cache.cachedDiags.capacity, 1)
        @Expect(cache.cachedDiags.size, 1)
        @Expect(cache.cachedDiags[0].errorMessage, "suffix")
        let restored = DiagnosticEngine()
        cache.Restore(restored)
        @Expect(restored.GetStoredDiags().size, 1)
        @Expect(restored.GetStoredDiags()[0].errorMessage, "suffix")
    }

    // The other upstream branch clears elements without replacing the vector's storage.
    @TestCase
    func backUpWithoutNewDiagnosticsPreservesStorage(): Unit {
        for (remaining in [0, 32]) {
            let diagnostic = Diagnostic()
            let before = DiagnosticEngine()
            before.SetStoredDiags(Array<Diagnostic>(32, repeat: diagnostic))
            let after = DiagnosticEngine()
            after.SetStoredDiags(Array<Diagnostic>(remaining, repeat: diagnostic))
            let cache = DiagnosticCache()
            cache.ToExclude(before)
            let capacity = cache.cachedDiags.capacity
            cache.BackUp(after)
            @Expect(cache.cachedDiags.size, 0)
            @Expect(cache.cachedDiags.capacity, capacity)
        }
    }
}
