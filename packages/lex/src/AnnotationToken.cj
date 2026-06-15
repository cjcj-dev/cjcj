package cangjie_compiler::lex

public enum AnnotationTokenKind {
    | EXCEPT
    | INCLUDE
    | PRIMAL
    | STAGE
    | MODE
    | FORWARD
    | BACKWARD
    | DUAL
    | ILLEGAL
}

public func AnnotationTokenKindIndex(kind: AnnotationTokenKind): Int64 {
    return match (kind) {
        case AnnotationTokenKind.EXCEPT => 0
        case AnnotationTokenKind.INCLUDE => 1
        case AnnotationTokenKind.PRIMAL => 2
        case AnnotationTokenKind.STAGE => 3
        case AnnotationTokenKind.MODE => 4
        case AnnotationTokenKind.FORWARD => 5
        case AnnotationTokenKind.BACKWARD => 6
        case AnnotationTokenKind.DUAL => 7
        case AnnotationTokenKind.ILLEGAL => 8
    }
}

extend AnnotationTokenKind <: Equatable<AnnotationTokenKind> {
    public operator func ==(right: AnnotationTokenKind): Bool {
        return AnnotationTokenKindIndex(this) == AnnotationTokenKindIndex(right)
    }

    public operator func !=(right: AnnotationTokenKind): Bool {
        return !(this == right)
    }
}

public let ANNOTATION_TOKENS: Array<String> = [
    "except", "include", "primal", "stage", "mode", "forward", "backward", "dual", ""
]

public func AnnotationTokenLiteral(kind: AnnotationTokenKind): String {
    return ANNOTATION_TOKENS[AnnotationTokenKindIndex(kind)]
}
