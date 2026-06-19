func f(n:Int64):Int64{if(n<=1){return 1};return n*f(n-1)}
main(){ println(f(5)) }
