class IdBox{func id<T>(x:T):T{return x}}
main(){ let box=IdBox(); let f=box.id<Int64>; println(f(37)) }
