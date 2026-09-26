package enum_const_cast

public enum Choice { A | B | C }

public func knownChoice(): Int64 {
    let choice = Choice.B
    match (choice) {
        case Choice.A => 11
        case Choice.B => 22
        case Choice.C => 33
    }
}

public func dynamicChoice(choice: Choice): Int64 {
    match (choice) {
        case Choice.A => 11
        case Choice.B => 22
        case Choice.C => 33
    }
}

public func numericControl(): Int64 {
    let value: UInt32 = 7
    Int64(value) + 1
}
