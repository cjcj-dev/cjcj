class R <: Resource {var closed:Bool;init(){closed=false};public func isClosed():Bool{return closed};public func close(){closed=true; println("closed")}}
main(){ try(r=R()){ println("body"); println(r.isClosed()) } }
