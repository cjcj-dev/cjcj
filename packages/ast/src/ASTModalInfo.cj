package cjcj::ast

public enum ASTMode <: Equatable<ASTMode> {
    | NOT
    | HALF
    | FULL

    public operator func ==(other: ASTMode): Bool {
        return match ((this, other)) {
            case (ASTMode.NOT, ASTMode.NOT) | (ASTMode.HALF, ASTMode.HALF) | (ASTMode.FULL, ASTMode.FULL) => true
            case _ => false
        }
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
