func ap2<T>(f:(T,T)->T, x:T):T{ return f(x,x) }
main(){ println(ap2({a,b=>a+b}, 3)) }
