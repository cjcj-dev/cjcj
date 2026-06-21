interface Shiftable { func shifted(): Int64 }
extend Int64 <: Shiftable { public func shifted(): Int64 { return this + 1 } }
main(){ println(41.shifted()) }
