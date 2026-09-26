package cjcj::ast

// C++ pointer containers compare declaration identity, not declaration contents.
extend FuncDecl <: Comparable<FuncDecl> {
    public operator func ==(right: FuncDecl): Bool { return SameDecl(this, right) }
    public operator func !=(right: FuncDecl): Bool { return !SameDecl(this, right) }
    public operator func <(right: FuncDecl): Bool { return CompNodeByPos(this, right) }
    public func compare(right: FuncDecl): Ordering {
        if (SameDecl(this, right)) {
            return Ordering.EQ
        }
        if (CompNodeByPos(this, right)) {
            return Ordering.LT
        }
        return Ordering.GT
    }
}

extend ClassLikeDecl <: Comparable<ClassLikeDecl> {
    public operator func ==(right: ClassLikeDecl): Bool { return SameDecl(this, right) }
    public operator func !=(right: ClassLikeDecl): Bool { return !SameDecl(this, right) }
    public operator func <(right: ClassLikeDecl): Bool { return objectId < right.objectId }
    public func compare(right: ClassLikeDecl): Ordering { return objectId.compare(right.objectId) }
}

extend ExtendDecl <: Comparable<ExtendDecl> {
    public operator func ==(right: ExtendDecl): Bool { return SameDecl(this, right) }
    public operator func !=(right: ExtendDecl): Bool { return !SameDecl(this, right) }
    public operator func <(right: ExtendDecl): Bool { return objectId < right.objectId }
    public func compare(right: ExtendDecl): Ordering { return objectId.compare(right.objectId) }
}
