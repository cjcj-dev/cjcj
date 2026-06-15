package cangjie_compiler::sema

public func MergeMultiTypeSubst(lhs: MultiTypeSubst, rhs: MultiTypeSubst): MultiTypeSubst {
    let out = lhs.Clone()
    for (entry in rhs.entries) {
        out.PutAll(entry.tyVar, entry.tys)
    }
    return out
}
