func ap2<T>(f:(T,T)->T, x:T):T{ return f(x,x) }
main(){ let n=5; println(ap2<Int64>({a,b=>a+b+n}, 2)) }
