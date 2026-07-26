package cjcj::chir

import std.collection.*
import cjcj::utils.ProfileRecorder

// C++: CHIR/Transformation/ReplaceSrcCodeImportedVal.cpp:15-89.
public class ReplaceSrcCodeImportedVal {
    private let `package`: Package

    public init(`package`: Package) {
        this.`package` = `package`
    }

    public func Run(srcCodeImportedFuncs: ArrayList<Function>, srcCodeImportedVars: ArrayList<GlobalVar>,
        uselessClasses: ArrayList<ClassDef>, uselessLambda: ArrayList<Function>): Unit {
        try (recorder = ProfileRecorder("CHIR", "ReplaceSrcCodeImportedVal")) {
            for (funcValue in srcCodeImportedFuncs) {
                funcValue.DestroyFuncBody()
            }
            let toBeRemovedFuncs = HashSet<Function>()
            for (globalVar in srcCodeImportedVars) {
                if (let Some(initFunc) <- globalVar.GetInitFunc()) {
                    toBeRemovedFuncs.add(initFunc)
                }
                globalVar.DestroyInitializer()
            }
            let newFuncs = ArrayList<Function>()
            for (funcValue in `package`.GetGlobalFunctions(includePureAbstract: true)) {
                if (toBeRemovedFuncs.contains(funcValue)) {
                    continue
                }
                newFuncs.add(funcValue)
            }
            `package`.SetAllGlobalFuncs(newFuncs)
            RemoveUselessDefFromCC(uselessClasses, uselessLambda)
        }
    }

    private func RemoveUselessDefFromCC(uselessClasses: ArrayList<ClassDef>,
        uselessLambda: ArrayList<Function>): Unit {
        try (recorder = ProfileRecorder("ReplaceSrcCodeImportedVal", "RemoveUselessDefFromCC")) {
            let toBeRemovedFuncs = HashSet<Function>()
            for (lambda in uselessLambda) {
                for (user in lambda.GetUsers()) {
                    user.RemoveSelfFromBlock()
                }
                lambda.DestroySelf()
                toBeRemovedFuncs.add(lambda)
            }

            for (def in uselessClasses) {
                for (funcValue in def.GetMethods()) {
                    for (user in funcValue.GetUsers()) {
                        user.RemoveSelfFromBlock()
                    }
                    funcValue.DestroySelf()
                    toBeRemovedFuncs.add(funcValue)
                }
            }
            let uselessClassSet = HashSet<CustomTypeDef>()
            for (def in uselessClasses) {
                uselessClassSet.add(def)
            }
            let newClasses = ArrayList<ClassDef>()
            for (def in `package`.GetClasses()) {
                if (!uselessClassSet.contains(def)) {
                    newClasses.add(def)
                }
            }
            `package`.SetClasses(newClasses)

            let globalFuncs = ArrayList<Function>()
            for (funcValue in `package`.GetGlobalFunctions(includePureAbstract: true)) {
                if (toBeRemovedFuncs.contains(funcValue)) {
                    continue
                }
                globalFuncs.add(funcValue)
            }
            `package`.SetAllGlobalFuncs(globalFuncs)
        }
    }
}
