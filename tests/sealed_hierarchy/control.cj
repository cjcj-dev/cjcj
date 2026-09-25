package sealed_fixture
func boolean(flag: Bool): Int64 {
    match (flag) {
        case true => 1
        case false => 2
    }
}
