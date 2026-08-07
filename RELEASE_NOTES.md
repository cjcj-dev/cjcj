# Release notes

## 0.0.2 (unreleased)

### Known limitations

**cjdb requires a system Python 3.11**

`cjdb` links against `libpython3.11.so.1.0`, which the SDK does not ship. Install
python3.11 (or a distribution package providing that shared library) before using
the debugger; the rest of the toolchain does not depend on it.

The upstream Cangjie SDK has the same requirement — its `cjdb` also fails to start
without a system Python 3.11 — so this is inherited rather than specific to this
build. We chose to document the dependency rather than bundle a ~35MB Python
runtime.

**Generational GC is enabled and currently costs throughput**

Minor collection is fully stop-the-world while the bulk of a major collection runs
concurrently, so a single minor pause is roughly 3.3x the cost of a full major
cycle. Combined with the read/write barrier tax paid on every access, the
generational configuration measures 3.9-4.1x slower than the non-generational one
on allocation-heavy workloads. Concurrent minor collection is the fix and is not
finished: the thread handshake is in place (7us median, 44us p95, against a
190ms minor pause) but stack scanning still runs under stop-the-world.

**GC crash rate is not yet characterised**

The reference-colouring migration is complete in source but the crash floor has
not been measured against a standard library rebuilt end-to-end with the current
compiler. Treat GC stability in this release as unquantified rather than as
known-good.
