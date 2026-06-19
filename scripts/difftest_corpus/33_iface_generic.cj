interface Holder<T> { func get():T }
class IntCell<:Holder<Int64> { let v:Int64; init(x:Int64){v=x}; public func get():Int64{return v} }
main(){ let h:Holder<Int64>=IntCell(9); println(h.get()) }
