@When[os == "Linux"]
func platform(): String {
    return "linux"
}

@When[os != "Linux"]
func platform(): String {
    return "other"
}

main() {
    println(platform())
}
