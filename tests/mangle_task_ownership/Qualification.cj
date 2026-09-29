package cjcj::frontend

import cjcj::ast.*
import std.collection.*

// This file is copied into a disposable compiler tree only. It observes the
// normal desugared AST immediately before the real mangling task dispatcher.
func MangleOwnershipQualification(decls: ArrayList<(String, Decl)>, workers: Int64): Unit {
    println("MANGLE_QUALIFY topDecls=${decls.size} workers=${workers}")
    var first: Option<Ty> = None
    var second: Option<Ty> = None
    var firstIndex: Int64 = -1
    var secondIndex: Int64 = -1
    for (index in 0..decls.size) {
        let decl = decls[index][1]
        println("MANGLE_TOP index=${index} batch=${index / 30} name=${decl.identifier.Val()} kind=${ASTKindName(decl.astKind)}")
        if (decl.astKind != ASTKind.MACRO_DECL) { continue }
        if (let Some(desugar) <- decl.GetDesugarDecl()) {
            if (let Some(body) <- desugar.funcBody) {
                for (params in body.paramLists) {
                    for (param in params.params) {
                        if (let Some(ty) <- param.GetTy()) {
                            var hasDecl = false
                            if (let Some(classTy) <- (ty as ClassTy)) {
                                hasDecl = classTy.decl.isSome()
                            }
                            println("MANGLE_SOURCE macro=${decl.identifier.Val()} type=${ty.objectId} kind=${TypeKindName(ty.kind)} classDecl=${hasDecl}")
                            if (decl.identifier.Val() == "RaceA" && hasDecl) {
                                first = ty
                                firstIndex = index
                            }
                            if (decl.identifier.Val() == "RaceB" && hasDecl) {
                                second = ty
                                secondIndex = index
                            }
                        }
                    }
                }
            }
        }
    }
    if (let Some(a) <- first) {
        if (let Some(b) <- second) {
            let same = refEq(a, b)
            let separate = firstIndex / 30 != secondIndex / 30
            let fullTasks = firstIndex < decls.size / 30 * 30 && secondIndex < decls.size / 30 * 30
            println("MANGLE_QUALIFICATION shared=${same} separate=${separate} fullTasks=${fullTasks} remainder=${decls.size % 30}")
        }
    }
}
