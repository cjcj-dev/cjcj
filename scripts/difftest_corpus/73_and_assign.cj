func rhs(): Bool { println(100); return true }
main(){ var a=false; a &&= rhs(); println(a); a=true; a &&= rhs(); println(a) }
