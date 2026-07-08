package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::sema.*
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::option.OptimizationLevel
import cangjie_compiler::option.OutputMode
import cangjie_compiler::option.enumIndex
import cangjie_compiler::utils.CJC_ASSERT

private var currentOptLevel: OptimizationLevel = OptimizationLevel.O0
private var currentOutputMode: OutputMode = OutputMode.EXECUTABLE

private let ins2generic: HashMap<Int64, Decl> = HashMap<Int64, Decl>()
private let generic2ins: HashMap<Int64, ArrayList<Decl>> = HashMap<Int64, ArrayList<Decl>>()

public type ReversedTypeSubst = TreeMap<Int64, GenericsTy>

private func hasInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Bool {
    if (let Some(values) <- generic2ins.get(genericDecl.objectId)) {
        for (value in values) {
            if (SameDecl(value, instantiatedDecl)) {
                return true
            }
        }
    }
    return false
}

private func registerInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Unit {
    if (hasInstantiation(genericDecl, instantiatedDecl)) {
        return
    }
    let genericKey = genericDecl.objectId
    if (!generic2ins.contains(genericKey)) {
        generic2ins[genericKey] = ArrayList<Decl>()
    }
    if (let Some(values) <- generic2ins.get(genericKey)) {
        values.add(instantiatedDecl)
    }
    ins2generic[instantiatedDecl.objectId] = genericDecl
}

public func SetOptLevel(opts: OptionGlobalOptions): Unit {
    currentOptLevel = opts.optimizationLevel
    currentOutputMode = opts.outputMode
}

private func IsCPointerFrozenMember(decl: Decl): Bool {
    if (decl.fullPackageName != "std.core" || decl.astKind != ASTKind.FUNC_DECL ||
        !decl.HasAnno(AstAnnotationKind.FROZEN)) {
        return false
    }
    if (let Some(outer) <- decl.outerDecl) {
        if (let Some(extendDecl) <- (outer as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    return extendedTy.IsPointer()
                }
            }
        }
    }
    return false
}

public func RequireInstantiation(decl: Decl): Bool {
    if (currentOutputMode == OutputMode.CHIR || decl.IsCommonMatchedWithSpecific()) {
        return false
    }
    if (IsCPointerFrozenMember(decl)) {
        return true
    }
    if (decl.astKind == ASTKind.INTERFACE_DECL) {
        return false
    }
    if (decl.IsNominalDecl()) {
        if (enumIndex(currentOptLevel) >= enumIndex(OptimizationLevel.O2) && !decl.TestAttr(Attribute.IMPORTED)) {
            return true
        }
        if (decl.TestAttr(Attribute.GENERIC)) {
            for (member in decl.GetMemberDecls()) {
                if (RequireInstantiation(member)) {
                    return true
                }
            }
        }
        return false
    }
    if (IsVirtualMember(decl)) {
        return false
    }
    if (decl.IsConst()) {
        return true
    }
    if (decl.TestAttr(Attribute.CONTAINS_MOCK_CREATION_CALL) && decl.HasAnno(AstAnnotationKind.FROZEN)) {
        return true
    }
    if (enumIndex(currentOptLevel) < enumIndex(OptimizationLevel.O2)) {
        return false
    }
    if (!IsInDeclWithAttribute(decl, Attribute.IMPORTED)) {
        return true
    }
    return decl.HasAnno(AstAnnotationKind.FROZEN)
}

private func collectDeclPair(source: Node, target: Node, pairs: ArrayList<(Decl, Decl)>): Unit {
    if (let Some(sourceDecl) <- (source as Decl)) {
        if (let Some(targetDecl) <- (target as Decl)) {
            targetDecl.genericDecl = sourceDecl
            pairs.add((sourceDecl, targetDecl))
        }
    }
}

private func InstantiationVisitFunc(source: Node, target: Node, visitor: (Node, Node) -> Unit,
    pairs: ArrayList<(Decl, Decl)>): Unit {
    collectDeclPair(source, target, pairs)
    visitor(source, target)
}

private func enableCompilerAddOnDecls(root: Node): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(decl) <- (node as Decl)) {
            decl.EnableAttr(Attribute.COMPILER_ADD)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func resetOuterDeclForClonedMembers(root: Node): Unit {
    if (let Some(rootDecl) <- (root as Decl)) {
        for (member in rootDecl.GetMemberDecls()) {
            member.outerDecl = rootDecl
        }
        return
    }
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(decl) <- (node as Decl)) {
            for (member in decl.GetMemberDecls()) {
                member.outerDecl = decl
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func pruneClassBody(body: ClassBody): Unit {
    var idx: Int64 = 0
    while (idx < body.decls.size) {
        let decl = body.decls[idx]
        if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            (decl.astKind != ASTKind.VAR_DECL && !RequireInstantiation(decl)) || IsStaticVar(decl) ||
            IsStaticInitializer(decl)) {
            body.decls.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func pruneStructBody(body: StructBody): Unit {
    var idx: Int64 = 0
    while (idx < body.decls.size) {
        let decl = body.decls[idx]
        if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            (decl.astKind != ASTKind.VAR_DECL && !RequireInstantiation(decl)) || IsStaticVar(decl) ||
            IsStaticInitializer(decl)) {
            body.decls.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func pruneInterfaceBody(body: InterfaceBody): Unit {
    var idx: Int64 = 0
    while (idx < body.decls.size) {
        let decl = body.decls[idx]
        if (decl.astKind == ASTKind.PROP_DECL || (decl.astKind == ASTKind.FUNC_DECL && !RequireInstantiation(decl))) {
            body.decls.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func PruneNonInstantiatedMembers(root: Node): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(body) <- (node as ClassBody)) {
            pruneClassBody(body)
        } else if (let Some(body) <- (node as StructBody)) {
            pruneStructBody(body)
        } else if (let Some(body) <- (node as InterfaceBody)) {
            pruneInterfaceBody(body)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func FinalizeInstantiatedTree(root: Node): Unit {
    enableCompilerAddOnDecls(root)
    resetOuterDeclForClonedMembers(root)
    PruneNonInstantiatedMembers(root)
}

private func collectReachableDecls(root: Node): ArrayList<Decl> {
    let decls = ArrayList<Decl>()
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(decl) <- (node as Decl)) {
            decls.add(decl)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return decls
}

private func isReachableDecl(decls: ArrayList<Decl>, decl: Decl): Bool {
    for (candidate in decls) {
        if (SameDecl(candidate, decl)) {
            return true
        }
    }
    return false
}

private func RegisterReachableDeclPairs(root: Node, pairs: ArrayList<(Decl, Decl)>): Unit {
    let reachableDecls = collectReachableDecls(root)
    for (pair in pairs) {
        if (isReachableDecl(reachableDecls, pair[1])) {
            registerInstantiation(pair[0], pair[1])
        }
    }
}

private func clonedGenericDecl(generic: Generic, visitor: (Node, Node) -> Unit): Generic {
    let pairs = ArrayList<(Decl, Decl)>()
    if (let Some(cloned) <- (ASTCloner.Clone(generic, { source: Node, target: Node =>
        InstantiationVisitFunc(source, target, visitor, pairs)
    }) as Generic)) {
        FinalizeInstantiatedTree(cloned)
        RegisterReachableDeclPairs(cloned, pairs)
        return cloned
    }
    return Generic()
}

private func clonedNode(node: Node, visitor: (Node, Node) -> Unit): Node {
    let pairs = ArrayList<(Decl, Decl)>()
    let cloned = ASTCloner.Clone(node, { source: Node, target: Node =>
        InstantiationVisitFunc(source, target, visitor, pairs)
    })
    FinalizeInstantiatedTree(cloned)
    RegisterReachableDeclPairs(cloned, pairs)
    return cloned
}

public func GetOptLevel(): OptimizationLevel {
    return currentOptLevel
}

public func IsOpenDecl(decl: Decl): Bool {
    if (!decl.IsClassLikeDecl()) {
        return false
    }
    if (decl.TestAttr(Attribute.OPEN_TO_MOCK)) {
        return false
    }
    if (decl.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)) {
        return true
    }
    return decl.astKind == ASTKind.INTERFACE_DECL
}

private func generalizeTypeArgs(typeArgs: ArrayList<Ty>, generalizer: TyGeneralizer): Array<Ty> {
    let out = ArrayList<Ty>()
    for (ty in typeArgs) {
        out.add(generalizer.Generalize(ty))
    }
    return out.toArray()
}

private func generalizeSetTys(typeArgs: ArrayList<Ty>, generalizer: TyGeneralizer): Array<Ty> {
    let out = ArrayList<Ty>()
    let tys = TreeMap<Int64, Ty>()
    for (ty in typeArgs) {
        let generalized = generalizer.Generalize(ty)
        if (!tys.contains(generalized.objectId)) {
            tys.add(generalized.objectId, generalized)
        }
    }
    for (key in tys.keys()) {
        if (let Some(ty) <- tys.get(key)) {
            out.add(ty)
        }
    }
    return out.toArray()
}

public func GetReversedTypeSubst(typeMapping: TypeSubst): ReversedTypeSubst {
    let out = ReversedTypeSubst()
    for (entry in typeMapping.entries) {
        if (!out.contains(entry.ty.objectId)) {
            out.add(entry.ty.objectId, entry.tyVar)
        }
    }
    return out
}

public class TyGeneralizer {
    private var tyMgr: TypeManager
    private var typeMapping: ReversedTypeSubst

    public init(tyMgr: TypeManager, mapping: ReversedTypeSubst) {
        this.tyMgr = tyMgr
        typeMapping = mapping
    }

    public func Generalize(ty: Ty): Ty {
        if (typeMapping.size == 0 || !Ty.IsTyCorrect(ty)) {
            return ty
        }
        if (let Some(genericTy) <- typeMapping.get(ty.objectId)) {
            return genericTy
        }
        if (let Some(funcTy) <- (ty as FuncTy)) {
            let paramTys = ArrayList<Ty>()
            for (paramTy in funcTy.paramTys) {
                paramTys.add(Generalize(paramTy))
            }
            let cfg = FuncTyConfig()
            cfg.isC = funcTy.IsCFunc()
            cfg.isClosureTy = funcTy.isClosureTy
            cfg.hasVariableLenArg = funcTy.hasVariableLenArg
            return tyMgr.GetFunctionTy(paramTys.toArray(), Generalize(funcTy.retTy), cfg: cfg)
        }
        if (let Some(tupleTy) <- (ty as TupleTy)) {
            return tyMgr.GetTupleTy(generalizeTypeArgs(tupleTy.typeArgs, this), isClosureTy: tupleTy.isClosureTy)
        }
        if (let Some(arrayTy) <- (ty as ArrayTy)) {
            if (arrayTy.typeArgs.isEmpty()) {
                return arrayTy
            }
            return tyMgr.GetArrayTy(Generalize(arrayTy.typeArgs[0]), arrayTy.dims)
        }
        if (let Some(pointerTy) <- (ty as PointerTy)) {
            if (pointerTy.typeArgs.isEmpty()) {
                return pointerTy
            }
            return tyMgr.GetPointerTy(Generalize(pointerTy.typeArgs[0]))
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetStructTy(decl, generalizeTypeArgs(structTy.typeArgs, this))
                }
            }
            return structTy
        }
        if (let Some(classThisTy) <- (ty as ClassThisTy)) {
            if (let Some(decl) <- classThisTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetClassThisTy(decl, generalizeTypeArgs(classThisTy.typeArgs, this))
                }
            }
            return classThisTy
        }
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetClassTy(decl, generalizeTypeArgs(classTy.typeArgs, this))
                }
            }
            return classTy
        }
        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetInterfaceTy(decl, generalizeTypeArgs(interfaceTy.typeArgs, this))
                }
            }
            return interfaceTy
        }
        if (let Some(refEnumTy) <- (ty as RefEnumTy)) {
            if (let Some(decl) <- refEnumTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetRefEnumTy(decl, generalizeTypeArgs(refEnumTy.typeArgs, this))
                }
            }
            return refEnumTy
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    let generalized = tyMgr.GetEnumTy(decl, typeArgs: generalizeTypeArgs(enumTy.typeArgs, this))
                    generalized.hasCorrespondRefEnumTy = enumTy.hasCorrespondRefEnumTy
                    return generalized
                }
            }
            return enumTy
        }
        if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
            if (let Some(decl) <- aliasTy.declPtr) {
                return tyMgr.GetTypeAliasTy(decl, generalizeTypeArgs(aliasTy.typeArgs, this))
            }
            return aliasTy
        }
        if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
            return tyMgr.GetIntersectionTy(generalizeSetTys(intersectionTy.tys, this))
        }
        if (let Some(unionTy) <- (ty as UnionTy)) {
            return tyMgr.GetUnionTy(generalizeSetTys(unionTy.tys, this))
        }
        return ty
    }
}

public func DefaultVisitFunc(source: Node, target: Node): Unit {
    let _ = source
    let _ = target
}

public func InstantiateMacroInvocation(invocation: MacroInvocation): MacroInvocation {
    return CloneMacroInvocation(invocation)
}

public func InstantiateGeneric(generic: Generic, visitor: (Node, Node) -> Unit): Generic {
    return clonedGenericDecl(generic, visitor)
}

public class PartialInstantiation {
    public init() {}

    public static func Instantiate(node: Node): Node {
        return Instantiate(node, DefaultVisitFunc)
    }

    public static func Instantiate(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        return clonedNode(node, visitFunc)
    }

    public static func GetGeneralDecl(clonedDecl: Decl): Decl {
        if (let Some(genericDecl) <- clonedDecl.genericDecl) {
            return genericDecl
        }
        if (clonedDecl.TestAttr(Attribute.GENERATED_TO_MOCK)) {
            return clonedDecl
        }
        if (let Some(genericDecl) <- ins2generic.get(clonedDecl.objectId)) {
            return genericDecl
        }
        CJC_ASSERT(false)
        return clonedDecl
    }

    public static func GetInstantiatedDecl(genericDecl: Decl): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(values) <- generic2ins.get(genericDecl.objectId)) {
            for (value in values) {
                out.add(value)
            }
        }
        return out
    }

    public static func RegisterInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Unit {
        registerInstantiation(genericDecl, instantiatedDecl)
    }

    public static func ResetGlobalMap(): Unit {
        generic2ins.clear()
        ins2generic.clear()
    }
}
