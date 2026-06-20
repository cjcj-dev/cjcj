class PatternErr <: Exception { init(m:String){ super(m) } }
main(){ try{ throw PatternErr("x") } catch(e:PatternErr){ println(83) } }
