struct Box { let a:Int64; let b:Int64; init(x:Int64,y:Int64){a=x;b=y} }
interface Maker<T> { func make():T }
class BMaker<:Maker<Box> { public func make():Box{return Box(3,4)} }
main(){ let m:Maker<Box>=BMaker(); let bx=m.make(); println(bx.a+bx.b) }
