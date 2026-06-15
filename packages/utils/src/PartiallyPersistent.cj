package cangjie_compiler::utils

import std.collection.*

public type VersionID = Int64
public let DUMMY_VERSION_ID: VersionID = 0

private class PSetLog<T> where T <: Comparable<T> {
    let isInsert: Bool
    let data: T

    init(isInsert: Bool, data: T) {
        this.isInsert = isInsert
        this.data = data
    }
}

private func cloneLogList<T>(logs: ArrayList<PSetLog<T>>): ArrayList<PSetLog<T>> where T <: Comparable<T> {
    let cloned = ArrayList<PSetLog<T>>()
    for (entry in logs) {
        cloned.add(entry)
    }
    return cloned
}

public class PSet<T> where T <: Comparable<T> {
    private var data: TreeSet<T> = TreeSet<T>()
    private let log: ArrayList<ArrayList<PSetLog<T>>> = ArrayList<ArrayList<PSetLog<T>>>()
    private let stashes: ArrayList<ArrayList<ArrayList<PSetLog<T>>>> = ArrayList<ArrayList<ArrayList<PSetLog<T>>>>()

    public init() {
        commit()
    }

    public init(values: Array<T>) {
        for (value in values) {
            data.add(value)
        }
        commit()
    }

    public func raw(): TreeSet<T> {
        return data
    }

    public func clear(): Unit {
        data.clear()
        log.clear()
        stashes.clear()
        commit()
    }

    public func softClear(): Unit {
        let values = ArrayList<T>()
        for (value in data) {
            values.add(value)
        }
        for (value in values) {
            erase(value)
        }
    }

    public func insert(value: T): Bool {
        checkIn(value)
        return data.add(value)
    }

    public func erase(value: T): Bool {
        checkOut(value)
        return data.remove(value)
    }

    public func contains(value: T): Bool {
        return data.contains(value)
    }

    public func count(value: T): Int64 {
        return if (contains(value)) { 1 } else { 0 }
    }

    public func merge(src: PSet<T>): Unit {
        let values = ArrayList<T>()
        for (value in src.raw()) {
            values.add(value)
        }
        for (value in values) {
            insert(value)
        }
        src.clear()
    }

    public func empty(): Bool {
        return data.size == 0
    }

    public func size(): Int64 {
        return data.size
    }

    public func find(value: T): Option<T> {
        if (!data.contains(value)) {
            return None
        }
        for (entry in data) {
            if (entry.compare(value) == Ordering.EQ) {
                return entry
            }
        }
        return None
    }

    public func commit(): Unit {
        log.add(ArrayList<PSetLog<T>>())
        stashes.add(ArrayList<ArrayList<PSetLog<T>>>())
    }

    public func reset(): Unit {
        CJC_ASSERT(!log.isEmpty())
        let last = log[log.size - 1]
        var idx = last.size - 1
        while (idx >= 0) {
            resetOne(last[idx])
            idx--
        }
        last.clear()
    }

    public func stash(): VersionID {
        CJC_ASSERT(!stashes.isEmpty())
        let lastLog = log[log.size - 1]
        let currentStashes = stashes[stashes.size - 1]
        currentStashes.add(cloneLogList(lastLog))
        reset()
        return currentStashes.size
    }

    public func apply(version: VersionID): Unit {
        if (version == 0) {
            return
        }
        let versionRaw = version - 1
        let currentStashes = stashes[stashes.size - 1]
        CJC_ASSERT(currentStashes.size > versionRaw)
        for (entry in currentStashes[versionRaw]) {
            applyOne(entry)
        }
    }

    public func resetSoft(): Unit {
        if (log.size > 1) {
            stashes.remove(at: stashes.size - 1)
            let newLast = log[log.size - 2]
            for (entry in log[log.size - 1]) {
                newLast.add(entry)
            }
            log.remove(at: log.size - 1)
        } else {
            stashes[stashes.size - 1].clear()
        }
    }

    public func diff(): Bool {
        return log[log.size - 1].isEmpty()
    }

    private func resetOne(entry: PSetLog<T>): Unit {
        if (entry.isInsert) {
            data.remove(entry.data)
        } else {
            data.add(entry.data)
        }
    }

    private func applyOne(entry: PSetLog<T>): Unit {
        if (entry.isInsert) {
            data.add(entry.data)
        } else {
            data.remove(entry.data)
        }
    }

    private func checkIn(value: T): Unit {
        if (!contains(value)) {
            log[log.size - 1].add(PSetLog<T>(true, value))
        }
    }

    private func checkOut(value: T): Unit {
        if (contains(value)) {
            log[log.size - 1].add(PSetLog<T>(false, value))
        }
    }
}

public class PData {
    public static func Commit<T>(data: PSet<T>): Unit where T <: Comparable<T> {
        data.commit()
    }

    public static func Reset<T>(data: PSet<T>): Unit where T <: Comparable<T> {
        data.reset()
    }

    public static func Stash<T>(data: PSet<T>): VersionID where T <: Comparable<T> {
        return data.stash()
    }

    public static func Apply<T>(data: PSet<T>, version: VersionID): Unit where T <: Comparable<T> {
        data.apply(version)
    }

    public static func ResetSoft<T>(data: PSet<T>): Unit where T <: Comparable<T> {
        data.resetSoft()
    }
}

