class MyErr <: Exception { init(m:String){ super(m) } }
func risky(b:Bool):Int64{ if(b){ throw MyErr("boom") }; return 7 }
main(){ try { println(risky(true)) } catch(e:MyErr){ println("caught") } }
