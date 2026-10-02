package signal_fixture

import cjcj::utils.CreateAltSignalStack

foreign {
    func fixture_run(callback: CFunc<() -> Int32>): Int32
    func fixture_verify_seed(): Int32
}

// The typed noncapturing lambda uses the supported CFunc bridge, as in
// packages/utils/src/Signal.cj:101. Its name must not match the observer needle.
private let fixtureCallback: CFunc<() -> Int32> = { =>
    let qualification = unsafe { fixture_verify_seed() }
    if (qualification != 0) { qualification } else {
        CreateAltSignalStack()
        0i32
    }
}

main(): Int64 {
    let rc = unsafe { fixture_run(fixtureCallback) }
    println("FIXTURE_MAIN rc=${rc}")
    return Int64(rc)
}
