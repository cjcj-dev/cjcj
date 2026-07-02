func platformValue(): Int64 {
    @When[os == "Windows"]
    let value = 1
    @When[os != "Windows"]
    let value = 2
    return value
}

main() {
    println(platformValue())
}
