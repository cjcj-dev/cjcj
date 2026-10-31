package std.core

public class RegistrationFinalized {
    public init() {}
    ~init() {}
}

public class RegistrationPlain {
    public init() {}
}

public func registrationMakeFinalized(): Object { RegistrationFinalized() }
public func registrationMakePlain(): Object { RegistrationPlain() }

public func registrationCaught(): Object {
    try {
        return RegistrationFinalized()
    } catch (exception: Exception) {
        return RegistrationPlain()
    }
}
