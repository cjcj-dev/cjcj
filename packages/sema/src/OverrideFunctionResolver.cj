package cjcj::sema

import std.collection.*
import cjcj::ast.*

public type MemberFuncSet = HashSet<FuncDecl>

public class OverrideFunctionResolver {
    private let typeManager: TypeManager

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
    }

    public func IsImplementationFunc(srcFunc: FuncDecl, superFunc: FuncDecl,
        srcInstFuncTy: FuncTy, superInstFuncTy: FuncTy): Bool {
        if (!IsVirtualMember(superFunc)) {
            return false
        }
        let noRelation = srcFunc.TestAttr(Attribute.STATIC) != superFunc.TestAttr(Attribute.STATIC) ||
            srcFunc.TestAttr(Attribute.GENERIC) != superFunc.TestAttr(Attribute.GENERIC) ||
            srcFunc.identifier != superFunc.identifier
        if (noRelation) {
            return false
        }
        if (srcFunc.TestAttr(Attribute.GENERIC) && superFunc.TestAttr(Attribute.GENERIC)) {
            let mapping = typeManager.GenerateGenericMappingFromGeneric(srcFunc, superFunc)
            let substSrc = (typeManager.GetInstantiatedTy(srcInstFuncTy, mapping) as FuncTy).getOrThrow()
            return typeManager.IsFuncTySubType(substSrc, superInstFuncTy)
        }
        return typeManager.IsFuncTySubType(srcInstFuncTy, superInstFuncTy)
    }

    public func IsImplementationFunc(srcFunc: FuncDecl, superFunc: FuncDecl): Bool {
        if (srcFunc.outerDecl.isNone() || superFunc.outerDecl.isNone() ||
            !(srcFunc.GetTy().getOrThrow() is FuncTy) || !(superFunc.GetTy().getOrThrow() is FuncTy)) {
            return false
        }
        let srcFuncTy = (srcFunc.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let mappings = Promotion(typeManager).GetPromoteTypeMapping(
            srcFunc.outerDecl.getOrThrow().GetTy().getOrThrow(),
            superFunc.outerDecl.getOrThrow().GetTy().getOrThrow())
        let instSuperFuncTys = typeManager.GetInstantiatedTys(superFunc.GetTy().getOrThrow(), mappings)
        for (instSuperFuncTy in instSuperFuncTys.values) {
            if (IsImplementationFunc(srcFunc, superFunc, srcFuncTy, (instSuperFuncTy as FuncTy).getOrThrow())) {
                return true
            }
        }
        return false
    }

    public func GetTopOverriddenFuncs(instBaseTy: Ty, funcDecl: FuncDecl): MemberFuncSet {
        let baseDecl = Ty.GetInheritableDeclPtrOfTy(Some(instBaseTy))
        let superDecls = TreeSet<ClassLikeDecl>()
        let extendDecls = TreeSet<ExtendDecl>()
        let result = MemberFuncSet()
        if (let Some(base) <- baseDecl) {
            for (decl in base.GetAllSuperDecls()) {
                superDecls.add(decl)
            }
            extendDecls.add(all: typeManager.GetDeclExtends(base))
        } else {
            extendDecls.add(all: typeManager.GetAllExtendsByTy(instBaseTy))
        }
        for (extendDecl in extendDecls) {
            for (decl in extendDecl.GetAllSuperDecls()) {
                superDecls.add(decl)
            }
        }
        for (superDecl in superDecls) {
            if (let Some(base) <- baseDecl) {
                if (SameDecl(superDecl, base)) {
                    continue
                }
            }
            let visit = { member: Decl =>
                if (let Some(parentFunc) <- (member as FuncDecl)) {
                    if (!SameDecl(parentFunc, funcDecl) && IsImplementationFunc(funcDecl, parentFunc)) {
                        let parentTops = GetTopOverriddenFuncs(superDecl.GetTy().getOrThrow(), parentFunc)
                        if (parentTops.isEmpty()) {
                            result.add(parentFunc)
                        } else {
                            result.add(all: parentTops)
                        }
                    }
                }
            }
            WorkForMembersOfDecl(superDecl, visit)
        }
        return result
    }
}
