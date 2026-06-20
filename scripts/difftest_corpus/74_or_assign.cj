func rhs(): Bool { println(200); return false }
main(){ var a=true; a ||= rhs(); println(a); a=false; a ||= rhs(); println(a) }
