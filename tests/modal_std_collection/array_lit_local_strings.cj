package modalcollarraylit

// String literals in a @local! array literal are built in the array's region
// (HLT API/std/core/local_mode h04_cross_boundary_survival.cj:33).
main(): Int64 {
    let localArray: Array<String> @local! = ["a", "bee", "c"]
    let localValue: String @local? = localArray[1]
    if (localValue.size == 3) { 0 } else { 1 }
}
