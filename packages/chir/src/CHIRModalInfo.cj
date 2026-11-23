package cjcj::chir

import cjcj::ast.ASTMode

// CHIR local-region modal carried by every CHIR type. Mirrors the official CHIR
// `Mode`/`ModalInfo` pair (include/cangjie/CHIR/IR/Type/Type.h:71-90 and
// src/CHIR/IR/Type/Type.cpp:1795-1846 @63bf237b). NONE is the ordinary heap modal and
// never changes a type's identity, hash or printed form.
public enum CHIRMode <: Equatable<CHIRMode> {
    | NONE
    | MAYBE
    | MUST

    public operator func ==(other: CHIRMode): Bool {
        return match ((this, other)) {
            case (CHIRMode.NONE, CHIRMode.NONE) | (CHIRMode.MAYBE, CHIRMode.MAYBE) | (CHIRMode.MUST, CHIRMode.MUST) =>
                true
            case _ => false
        }
    }

    public operator func !=(other: CHIRMode): Bool {
        return !(this == other)
    }
}

public struct ModalInfo <: Equatable<ModalInfo> {
    public let local: CHIRMode

    public init() {
        this.local = CHIRMode.NONE
    }

    public init(local: CHIRMode) {
        this.local = local
    }

    public func Local(): CHIRMode {
        return local
    }

    public operator func ==(other: ModalInfo): Bool {
        return local == other.local
    }

    public operator func !=(other: ModalInfo): Bool {
        return local != other.local
    }

    // NONE and MUST can each be passed where MAYBE is expected.
    public func IsSubModal(other: ModalInfo): Bool {
        return (local == CHIRMode.NONE && other.local == CHIRMode.MAYBE) ||
            (local == CHIRMode.MUST && other.local == CHIRMode.MAYBE)
    }

    public func IsEqualOrSubModal(other: ModalInfo): Bool {
        return this == other || IsSubModal(other)
    }

    public func ToString(): String {
        return match (local) {
            case CHIRMode.NONE => "@~local"
            case CHIRMode.MAYBE => "@local?"
            case CHIRMode.MUST => "@local!"
        }
    }

    func HashIndex(): Int64 {
        return match (local) {
            case CHIRMode.NONE => 0
            case CHIRMode.MAYBE => 1
            case CHIRMode.MUST => 2
        }
    }
}

// Official ASTModal2CHIRModal (src/CHIR/AST2CHIR/Utils.cpp:412-425 @63bf237b). The input must be a
// Sema-resolved mode (function slot or, once Sema provides it, a declaration/expression mode); a
// syntactic type-node suffix is not a resolved mode.
public func ASTModal2CHIRModal(mode: ASTMode): ModalInfo {
    return match (mode) {
        case ASTMode.NOT => ModalInfo(CHIRMode.NONE)
        case ASTMode.HALF => ModalInfo(CHIRMode.MAYBE)
        case ASTMode.FULL => ModalInfo(CHIRMode.MUST)
    }
}

// Mixes a non-NONE modal into a type hash. NONE leaves the hash unchanged so ordinary types keep
// their existing interning buckets.
func HashModal(seed: Int64, modal: ModalInfo): Int64 {
    if (modal.local == CHIRMode.NONE) {
        return seed
    }
    return HashCombine(seed, 0x4d4f44414c + modal.HashIndex())
}
