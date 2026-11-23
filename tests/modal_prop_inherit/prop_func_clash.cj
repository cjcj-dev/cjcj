package modalpropclash

public interface HasLen {
    prop length: Int64 {
        get() {
            1
        }
    }
}

public interface LenFunc {
    func length(): Int64 {
        2
    }
}

public class Both <: HasLen & LenFunc {}

main(): Int64 {
    0
}
