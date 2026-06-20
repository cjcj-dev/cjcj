main(){ try{ throw IllegalArgumentException("x") } catch(e:IllegalArgumentException){ println("iae") } catch(e:Exception){ println("e") } }
