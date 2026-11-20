package cjcj::ast

public enum ASTMode <: Equatable<ASTMode> {
    | NOT
    | HALF
    | FULL

    // NOT (01) and FULL (10) can each be passed to HALF (11).
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
