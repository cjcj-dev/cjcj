package cjmpext

extend Int64 {
    public func fromSpecific(): Int64 { this + 2 }
}

public specific func probe(): Int64 { 40.fromCommon() + 0.fromSpecific() - 1 }
