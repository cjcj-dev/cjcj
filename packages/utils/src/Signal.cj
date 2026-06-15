package cangjie_compiler::utils

public let SIGNAL_MSG_PART_ONE: String = "Interrupt signal ("
public let SIGNAL_MSG_PART_TWO: String = ") received."

public func RegisterCrashSignalHandler(): Unit {
    // TODO(selfhost:Utils): install POSIX/Windows crash handlers through C FFI with alternate signal stack support.
}

public func RegisterCrtlCSignalHandler(): Unit {
    // TODO(selfhost:Utils): bind SIGINT handling through C FFI.
}

public func CreateAltSignalStack(): Unit {
    // TODO(selfhost:Utils): bind sigaltstack on Unix-like targets.
}

