package cjmpext

public common func probe(): Int64

extend Int64 {
    public func fromCommon(): Int64 { this + 1 }
}
