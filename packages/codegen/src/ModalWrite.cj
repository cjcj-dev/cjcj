package cjcj::codegen

import std.collection.ArrayList
import cjcj::chir.{Attribute, CHIRMode, CustomType, GetElementByName, GetElementRef, LocalVar, Type, Value}

public enum ModalWriteKind { | ORDINARY | MAYBE_LOCAL | DEMODE }

func RegionWriteKind(ty: Type): ModalWriteKind {
    return if (ty.IsLocalRegion()) { ModalWriteKind.MAYBE_LOCAL } else { ModalWriteKind.ORDINARY }
}

func ClassifyAddressWrite(ir: IRBuilder2, address: Value): ModalWriteKind {
    let local = (address as LocalVar) ?? return ModalWriteKind.ORDINARY
    let expr = local.GetExpr() ?? return ModalWriteKind.ORDINARY
    if (let Some(field) <- (expr as GetElementRef)) {
        return ClassifyMemberWrite(ir, field.GetLocation(), field.GetPath())
    }
    if (let Some(field) <- (expr as GetElementByName)) {
        let base = field.GetLocation()
        let path = ResolveElementPathByNames(ir.GetCGModule(), base.GetType().getOrThrow(), field.GetNames()) ??
            return ModalWriteKind.ORDINARY
        return ClassifyMemberWrite(ir, base, path)
    }
    return ModalWriteKind.ORDINARY
}

func ClassifyMemberWrite(ir: IRBuilder2, base: Value, path: ArrayList<UInt64>): ModalWriteKind {
    let locationTy = base.GetType() ?? return ModalWriteKind.ORDINARY
    if (!locationTy.IsRef()) { return ModalWriteKind.ORDINARY }
    var owner = (locationTy.StripAllRefs() as CustomType) ?? return ModalWriteKind.ORDINARY
    for (i in 0..path.size) {
        let vars = owner.GetCustomTypeDef().GetAllInstanceVars()
        let types = owner.GetInstantiatedMemberTys(ir.GetCGContext().GetCHIRBuilder())
        let index = Int64(path[i])
        if (index < 0 || index >= vars.size || index >= types.size) { return ModalWriteKind.ORDINARY }
        let member = types[index]
        let data = member.StripAllRefs()
        if (i + 1 == path.size) {
            if (data.IsCopyable()) {
                return if (owner.IsModal()) { ModalWriteKind.MAYBE_LOCAL } else { ModalWriteKind.ORDINARY }
            }
            if (vars[index].TestAttr(Attribute.DEMODE)) {
                return if (owner.IsModal()) { ModalWriteKind.DEMODE } else { ModalWriteKind.ORDINARY }
            }
            if (!data.IsModal() || (owner.modal.local == CHIRMode.MUST && data.modal.local == CHIRMode.MUST &&
                (member.IsRef() || !data.IsGenericRelated()))) { return ModalWriteKind.ORDINARY }
            return ModalWriteKind.MAYBE_LOCAL
        }
        owner = (data as CustomType) ?? return ModalWriteKind.ORDINARY
    }
    return ModalWriteKind.ORDINARY
}
