package cjcj::ast

// C++ pointer containers compare declaration identity, not declaration contents.
extend FuncDecl <: Equatable<FuncDecl> {
    public operator func ==(right: FuncDecl): Bool { return SameDecl(this, right) }
    public operator func !=(right: FuncDecl): Bool { return !SameDecl(this, right) }
}

extend ClassLikeDecl <: Comparable<ClassLikeDecl> {
    public operator func ==(right: ClassLikeDecl): Bool { return SameDecl(this, right) }
    public operator func !=(right: ClassLikeDecl): Bool { return !SameDecl(this, right) }
    public operator func <(right: ClassLikeDecl): Bool { return objectId < right.objectId }
    public func compare(right: ClassLikeDecl): Ordering { return objectId.compare(right.objectId) }
}

