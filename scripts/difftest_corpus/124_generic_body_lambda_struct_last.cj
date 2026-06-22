struct Pair{let a:Int64;let b:Int64;init(x:Int64,y:Int64){a=x;b=y}}
func structLast<T>(x:T,p:Pair):Int64{let g={=>p.a};return g()}
main(){println(structLast<Int64>(0,Pair(42,7)))}
