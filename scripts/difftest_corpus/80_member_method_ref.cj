class Acc{var base:Int64;init(x:Int64){base=x};func add(x:Int64):Int64{return base+x}}
main(){ let obj=Acc(39); let f=obj.add; println(f(3)) }
