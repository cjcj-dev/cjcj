open class A{}
class B<:A{ let v:Int64; init(){v=7} }
main(){ let a:A=B(); let r=match(a){ case b:B=>b.v; case _=>0 }; println(r) }
