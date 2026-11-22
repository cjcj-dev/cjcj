package modalcollneglowered

public class Box {
    public init() {}
    public exclave init(this @local!) {}

    public prop details: Int64 {
        get() { 1 }
    }
}

func pass(b: Box @local!): Box @local! {
    b
}

// Negative control: the pipeline lowers to a call with a @local! result, and only a plain-receiver
// `details` exists, so the read must still be rejected.
func read(b: Box @local!): Int64 {
    let r = b |> pass
    r.details
}

main(): Int64 {
    0
}
