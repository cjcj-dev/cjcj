package cjcj::chir

import std.sync.AtomicInt64
import std.env.{atExit, getVariable}
import std.fs.File

// Temporary private measurement candidate; no public compiler option and no output by default.
private class ChirCounts {
    static let instance = ChirCounts()
    let destination: String = getVariable("CJCJ_CHIR_COUNTS_FILE") ?? ""
    let values = Array<AtomicInt64>(1107, { _: Int64 => AtomicInt64(0) })
    private init() { if (!destination.isEmpty()) { atExit({ => Flush() }) } }
    func Add(site: Int64, metric: Int64, value: Int64): Unit {
        if (!destination.isEmpty()) { values[site * 9 + metric].fetchAdd(value) }
    }
    func Flush(): Unit {
        let out = StringBuilder()
        out.append("site\tcalls\tsize\ttests\thits\tmisses\ttail_or_prefix\tscope_first\tscope_stable_repeat\tscope_mutated_repeat\n")
        for (site in 0..123) {
            out.append(site.toString())
            for (metric in 0..9) { out.append("\t" + values[site * 9 + metric].load().toString()) }
            out.append("\n")
        }
        File.writeTo(destination, out.toString().toArray())
        eprintln("CHIR_COUNTS_COMPLETE " + destination)
    }
}
func ChirCountScan(site: Int64, size: Int64, tests: Int64, hit: Bool, tail: Int64): Unit {
    let c = ChirCounts.instance
    c.Add(site, 0, 1); c.Add(site, 1, size); c.Add(site, 2, tests)
    c.Add(site, if (hit) { 3 } else { 4 }, 1); c.Add(site, 5, tail)
}
public class ChirCountTraversal {
    private let site: Int64
    private var first = true
    private var previousVersion: Int64 = 0
    public init(site: Int64) { this.site = site }
    public func Query(tests: Int64, version: Int64): Unit {
        let c = ChirCounts.instance
        c.Add(site, 0, 1); c.Add(site, 2, tests)
        c.Add(site, if (first) { 6 } else if (version == previousVersion) { 7 } else { 8 }, 1)
        first = false; previousVersion = version
    }
}
