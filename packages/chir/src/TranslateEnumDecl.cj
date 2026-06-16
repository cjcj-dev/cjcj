package cangjie_compiler::chir

import std.collection.*

extend AST2CHIRDeclTranslator {
    public func LowerEnumDecl(spec: AST2CHIRNominalSpec, def: CustomTypeDef): Unit {
        if (let Some(enumDef) <- (def as EnumDef)) {
            for (ctorSpec in spec.enumCtors) {
                if (!HasEnumCtor(enumDef, ctorSpec)) {
                    enumDef.AddCtor(EnumCtorInfo(ctorSpec.name, ctorSpec.payloadTypes))
                }
            }
        }
        LowerMemberVarsAndMethods(spec, def)
    }

    private func HasEnumCtor(enumDef: EnumDef, ctorSpec: AST2CHIREnumCtorSpec): Bool {
        for (ctor in enumDef.GetCtors()) {
            if (ctor.name == ctorSpec.name && HasSamePayloadTypes(ctor.payloadTypes, ctorSpec.payloadTypes)) {
                return true
            }
        }
        return false
    }

    private func HasSamePayloadTypes(left: ArrayList<Type>, right: ArrayList<Type>): Bool {
        if (left.size != right.size) {
            return false
        }
        var index: Int64 = 0
        while (index < left.size) {
            if (!left[index].IsEqual(right[index])) {
                return false
            }
            index++
        }
        return true
    }
}
