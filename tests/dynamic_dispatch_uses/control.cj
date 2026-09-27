package dispatch_uses_control

public class Item {
    public prop size: Int64 { get() { 7 } }
}

public func entry(value: Item): Int64 { value.size }

main(): Int64 { entry(Item()) - 7 }
