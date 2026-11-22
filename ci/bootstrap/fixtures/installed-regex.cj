import std.regex.{Regex, RegexOption}

main(): Int64 {
    let pattern = Regex("^(Cat|Dog)[0-9]+$", RegexOption().ignoreCase())
    if (!pattern.matches("cat231") || pattern.matches("cat")) {
        return 1
    }
    println("SDK_REGEX_MATCH_PASS")
    return 0
}
