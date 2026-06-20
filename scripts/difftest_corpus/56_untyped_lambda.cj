func adder(n:Int64):(Int64)->Int64{ return {x=>x+n} }
main(){ let a=adder(10); println(a(5)) }
