// Shared annotation type: a minimal reflective custom annotation (@Annotation marks Tag as an
// annotation type; Tag[...] then applies it, populating the target decl's annotationsArray).
@Annotation
public class Tag {
    public const init(name: String) {
        this.name = name
    }
    public let name: String
}

@Tag["struct"]
struct S {
    let x: Int64 = 1
}

main() {
    0
}
