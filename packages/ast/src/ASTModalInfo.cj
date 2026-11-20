package cjcj::ast

public enum ASTMode <: Equatable<ASTMode> {
    | NOT
    | HALF
    | FULL

    // NOT (01) and FULL (10) can each be passed to HALF (11).
    public func Suffix(): String {
        return match (this) {
            case NOT => ""
            case HALF => " @local?"
            case FULL => " @local!"
        }
    }

    public func IsSubMode(other: ASTMode): Bool {
        return this == other || other == ASTMode.HALF
    }

    public func WireValue(): UInt8 {
        return match (this) {
            case NOT => 0u8
            case FULL => 1u8
            case HALF => 2u8
        }
    }

    public static func FromWire(value: UInt8): ASTMode {
        return match (value) {
            case 0u8 => NOT
            case 1u8 => FULL
            case 2u8 => HALF
            case _ => throw IllegalArgumentException("unknown CJO local mode")
        }
    }

    public operator func ==(other: ASTMode): Bool {
        return match ((this, other)) {
            case (ASTMode.NOT, ASTMode.NOT) | (ASTMode.HALF, ASTMode.HALF) | (ASTMode.FULL, ASTMode.FULL) => true
            case _ => false
        }
    }

    public operator func !=(other: ASTMode): Bool {
        return !(this == other)
    }
}

// A missing suffix is None on the AST node; explicit @~local is kept as NOT.
public struct ASTModalInfo {
    public let local: ASTMode
    public let atPos: Position
    public let localPos: Position
    public let end: Position

    public init(local: ASTMode, atPos: Position, localPos: Position, end: Position) {
        this.local = local
        this.atPos = atPos
        this.localPos = localPos
        this.end = end
    }
}

public func PropertyMode(pd: PropDecl): ASTMode {
    if (let Some(t) <- pd.typeNode) { return t.modal.map({ m => m.local }) ?? t.resolvedMode }
    return pd.resolvedMode
}

// The receiver is separate from the explicit parameter list. Default-argument
// functions execute with the receiver contract of their enclosing declaration.
public func GetReceiverMode(fd: FuncDecl): ASTMode {
    if (fd.TestAttr(Attribute.STATIC)) { return ASTMode.NOT }
    if (let Some(owner) <- fd.ownerFunc) { return GetReceiverMode(owner) }
    if (let Some(propertyDecl) <- fd.propDecl) {
        return PropertyMode(propertyDecl)
    }
    if ((let Some(body) <- fd.funcBody) && !body.paramLists.isEmpty()) {
        if (let Some(modal) <- body.paramLists[0].receiverModal) { return modal.local }
        if (let Some(tp) <- body.paramLists[0].thisParam) { return tp.resolvedMode }
    }
    return ASTMode.NOT
}

public func HasLocalModifier(decl: Decl, kind: TokenKind): Bool {
    for (modifier in decl.modifiers) { if (modifier.modifier == kind) { return true } }
    return false
}

public func LocalParameterMode(fd: FuncDecl, i: Int64): ASTMode {
    if (let Some(body) <- fd.funcBody) {
        if (!body.paramLists.isEmpty() && i < body.paramLists[0].params.size) {
            let param = body.paramLists[0].params[i]
            if ((let Some(t) <- param.typeNode) && (let Some(m) <- t.modal)) { return m.local }
        }
    }
    if ((let Some(ty) <- fd.GetTy()) && (let Some(ft) <- (ty as FuncTy)) && i < ft.paramTys.size) {
        return ft.ParamMode(i)
    }
    return ASTMode.NOT
}

// Return modes participate in function types, but do not introduce overloads.
public func SameModalInputs(left: Decl, right: Decl): Bool {
    if ((let Some(a) <- (left as PropDecl)) && (let Some(b) <- (right as PropDecl))) {
        return PropertyMode(a) == PropertyMode(b)
    }
    let a = (left as FuncDecl) ?? return true;
    let b = (right as FuncDecl) ?? return true;
    if (GetReceiverMode(a) != GetReceiverMode(b)) { return false }
    let body = a.funcBody ?? return true;
    if (body.paramLists.isEmpty()) { return true }
    for (i in 0..body.paramLists[0].params.size) {
        if (LocalParameterMode(a, i) != LocalParameterMode(b, i)) { return false }
    }
    return true
}
