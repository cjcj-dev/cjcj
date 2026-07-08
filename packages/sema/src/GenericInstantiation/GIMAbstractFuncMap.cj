package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

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
    private let entries: ArrayList<AbstractFuncMapEntry> = ArrayList<AbstractFuncMapEntry>()

    public init() {}

    public func Add(ty: Ty, absFunc: FuncDecl, implDecl: Decl, offset: Int64): Unit {
        for (entry in entries) {
            if (SameTy(entry.ty, ty) && SameDecl(entry.absFunc, absFunc)) {
                AddImpl(entry.impls, implDecl, offset)
                return
            }
        }
        let entry = AbstractFuncMapEntry(ty, absFunc)
        AddImpl(entry.impls, implDecl, offset)
        entries.add(entry)
    }

    public func Find(ty: Ty, absFunc: FuncDecl): Option<ArrayList<(Decl, Int64)>> {
        for (entry in entries) {
            if (SameTy(entry.ty, ty) && SameDecl(entry.absFunc, absFunc)) {
                return entry.impls
            }
        }
        return None
    }

    public func Clear(): Unit {
        entries.clear()
    }

    public func Size(): Int64 {
        return entries.size
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
