package modalcollarraylitneg

func plain(): String { "bee" }

// Only literals take the array's mode: a plain String value still cannot be stored in a @local! array.
main(): Int64 {
    let p: String = plain()
    let localArray: Array<String> @local! = ["a", p]
    localArray.size
}
