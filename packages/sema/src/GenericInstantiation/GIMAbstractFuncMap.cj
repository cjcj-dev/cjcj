package cjcj::sema.GenericInstantiation

import std.collection.*
import cjcj::ast.*

public class AbstractFuncMapEntry {
    public var ty: Ty
    public var absFunc: FuncDecl
    public let impls: ArrayList<(Decl, Int64)> = ArrayList<(Decl, Int64)>()

    public init(ty: Ty, absFunc: FuncDecl) {
        this.ty = ty
        this.absFunc = absFunc
    }
}

public class AbstractFuncMap {
    private let entries: HashMap<Int64, HashMap<Int64, AbstractFuncMapEntry>> =
        HashMap<Int64, HashMap<Int64, AbstractFuncMapEntry>>()
    private var entryCount: Int64 = 0

    public init() {}

    public func Add(ty: Ty, absFunc: FuncDecl, implDecl: Decl, offset: Int64): Unit {
        let tyKey = ty.objectId
        let funcKey = absFunc.objectId
        if (!entries.contains(tyKey)) {
            entries[tyKey] = HashMap<Int64, AbstractFuncMapEntry>()
        }
        let tyEntries = entries.get(tyKey).getOrThrow()
        if (let Some(entry) <- tyEntries.get(funcKey)) {
            AddImpl(entry.impls, implDecl, offset)
            return
        }
        let entry = AbstractFuncMapEntry(ty, absFunc)
        AddImpl(entry.impls, implDecl, offset)
        tyEntries[funcKey] = entry
        entryCount++
    }

    public func Find(ty: Ty, absFunc: FuncDecl): Option<ArrayList<(Decl, Int64)>> {
        if (let Some(tyEntries) <- entries.get(ty.objectId)) {
            if (let Some(entry) <- tyEntries.get(absFunc.objectId)) {
                return entry.impls
            }
        }
        return None
    }

    public func Clear(): Unit {
        entries.clear()
        entryCount = 0
    }

    public func Size(): Int64 {
        return entryCount
    }

    private func AddImpl(impls: ArrayList<(Decl, Int64)>, implDecl: Decl, offset: Int64): Unit {
        for ((decl, existingOffset) in impls) {
            if (SameDecl(decl, implDecl) && existingOffset == offset) {
                return
            }
        }
        impls.add((implDecl, offset))
    }
}
