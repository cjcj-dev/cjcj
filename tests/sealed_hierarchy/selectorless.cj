package sealed_fixture
func sibling(flag: Bool): Int64 {
    match {
        case _ => 1
        case flag => 2
        case !flag => 3
    }
}
