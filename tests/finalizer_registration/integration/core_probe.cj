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
