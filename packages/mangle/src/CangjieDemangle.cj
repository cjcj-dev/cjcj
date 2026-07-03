package cangjie_compiler::mangle

public class DemangleData {
    private var pkgName: String
    private var fullName: String
    private var isFunctionLike: Bool = false
    private var isValid: Bool
    private var isPrivateDeclaration: Bool = false

    public init(pkgName: String, fullName: String, isFunctionLike: Bool, isValid: Bool) {
        this.pkgName = pkgName
        this.fullName = fullName
        this.isFunctionLike = isFunctionLike
        this.isValid = isValid
    }

    public func GetPkgName(): String {
        return pkgName
    }

    public func GetFullName(): String {
        return fullName
    }

    public func IsFunctionLike(): Bool {
        return isFunctionLike
    }

    public func IsValid(): Bool {
        return isValid
    }

    public func SetPrivateDeclaration(isPrivate: Bool): Unit {
        isPrivateDeclaration = isPrivate
    }

    public func IsPrivateDeclaration(): Bool {
        return isPrivateDeclaration
    }
}

public func Demangle(mangled: String, scopeRes: String): DemangleData {
    let demangler = Demangler(mangled, scopeRes: scopeRes)
    let di = demangler.Demangle()
    let dd = DemangleData(di.GetPkgName(), di.GetFullName(demangler.ScopeResolution()), di.IsFunctionLike(),
        di.IsValid())
    dd.SetPrivateDeclaration(di.isPrivateDeclaration)
    return dd
}

public func Demangle(mangled: String): DemangleData {
    return Demangle(mangled, "::")
}

public func Demangle(mangled: String, scopeRes: String, genericVec: Array<String>): DemangleData {
    let demangler = Demangler(mangled, scopeRes: scopeRes)
    demangler.setGenericVec(genericVec)
    let di = demangler.Demangle()
    let dd = DemangleData(di.GetPkgName(), di.GetFullName(demangler.ScopeResolution()), di.IsFunctionLike(),
        di.IsValid())
    dd.SetPrivateDeclaration(di.isPrivateDeclaration)
    return dd
}

public func Demangle(mangled: String, genericVec: Array<String>): DemangleData {
    return Demangle(mangled, "::", genericVec)
}

public func DemangleType(mangled: String, scopeRes: String): DemangleData {
    let demangler = Demangler(mangled, scopeRes: scopeRes)
    let di = demangler.Demangle(isType: true)
    let dd = DemangleData(di.GetPkgName(), di.GetFullName(demangler.ScopeResolution()), false, di.IsValid())
    dd.SetPrivateDeclaration(di.isPrivateDeclaration)
    return dd
}

public func DemangleType(mangled: String): DemangleData {
    return DemangleType(mangled, "::")
}
