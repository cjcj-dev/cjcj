package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public enum TypeCompatibility {
    | INCOMPATIBLE
    | SUBTYPE
    | IDENTICAL
}

private func TypeCompatibilityIndex(value: TypeCompatibility): Int64 {
    return match (value) {
        case TypeCompatibility.INCOMPATIBLE => 0
        case TypeCompatibility.SUBTYPE => 1
        case TypeCompatibility.IDENTICAL => 2
    }
}

extend TypeCompatibility <: Equatable<TypeCompatibility> {
    public operator func ==(right: TypeCompatibility): Bool {
        return TypeCompatibilityIndex(this) == TypeCompatibilityIndex(right)
    }

    public operator func !=(right: TypeCompatibility): Bool {
        return !(this == right)
    }
}

public let FUTURE_TYPE_NAME: String = "Future"
public let INT32_SIZE: Int64 = 4

public class TyVarScope {
    private var manager: Option<TypeManager> = None
    private let tyVars: ArrayList<GenericsTy> = ArrayList<GenericsTy>()
    private var closed: Bool = false

    public init() {}

    public init(typeManager: TypeManager) {
        manager = typeManager
        typeManager.PushTyVarScope(this)
    }

    public func AddTyVar(tyVar: GenericsTy): Unit {
        tyVars.add(tyVar)
    }

    public func ContainsTyVar(tyVar: GenericsTy): Bool {
        for (value in tyVars) {
            if (SameTy(value, tyVar)) {
                return true
            }
        }
        return false
    }

    public func AddUnsolvedTyVars(out: ArrayList<GenericsTy>, unsolved: ArrayList<GenericsTy>): Unit {
        for (tyVar in tyVars) {
            for (candidate in unsolved) {
                if (SameTy(tyVar, candidate)) {
                    out.add(tyVar)
                    break
                }
            }
        }
    }

    public func Close(): Unit {
        if (closed) {
            return
        }
        if (let Some(typeManager) <- manager) {
            for (tyVar in tyVars) {
                typeManager.ReleaseTyVar(tyVar)
            }
            typeManager.PopTyVarScope(this)
        }
        closed = true
    }
}

public class InstCtxScope {
    public var curMaps: SubstPack = SubstPack()
    public var refMaps: SubstPack = SubstPack()
    public var maps: SubstPack = SubstPack()
    private var manager: Option<TypeManager> = None
    private var closed: Bool = false

    public init() {}

    public init(typeManager: TypeManager) {
        manager = typeManager
        typeManager.PushInstCtxScope(this)
    }

    public func SetRefDecl(decl: Decl, instTy: Ty): Unit {
        if (let Some(generic) <- decl.GetGeneric()) {
            if (generic.typeParameters.size != instTy.typeArgs.size) {
                return
            }
            refMaps = SubstPack()
            var idx: Int64 = 0
            while (idx < instTy.typeArgs.size) {
                if (let Some(paramTy) <- generic.typeParameters[idx].GetTy()) {
                    if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                        if (let Some(typeManager) <- manager) {
                            let instVar = typeManager.AllocTyVar()
                            refMaps.u2i.Put(genericTy, instVar)
                            refMaps.inst.Put(instVar, instTy.typeArgs[idx])
                        }
                    }
                }
                idx++
            }
            maps = curMaps.Clone()
            maps.Merge(refMaps)
        }
    }

    public func SetRefDeclSimple(typeManager: TypeManager, fd: FuncDecl): Unit {
        if (let Some(generic) <- fd.GetGeneric()) {
            refMaps = SubstPack()
            for (param in generic.typeParameters) {
                if (let Some(paramTy) <- param.GetTy()) {
                    if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                        typeManager.MakeInstTyVar(refMaps, genericTy)
                    }
                }
            }
            maps = curMaps.Clone()
            maps.Merge(refMaps)
        }
    }

    public func Close(): Unit {
        if (closed) {
            return
        }
        if (let Some(typeManager) <- manager) {
            typeManager.PopInstCtxScope(this)
        }
        closed = true
    }
}

private class OverrideCacheEntry {
    public var src: FuncDecl
    public var target: FuncDecl
    public var baseTy: Option<Ty>
    public var expectInstParent: Option<Ty>
    public var value: Bool

    public init(src: FuncDecl, target: FuncDecl, baseTy: Option<Ty>, expectInstParent: Option<Ty>, value: Bool) {
        this.src = src
        this.target = target
        this.baseTy = baseTy
        this.expectInstParent = expectInstParent
        this.value = value
    }
}

private class TopOverrideEntry {
    public var src: FuncDecl
    public let targets: ArrayList<FuncDecl> = ArrayList<FuncDecl>()

    public init(src: FuncDecl) {
        this.src = src
    }
}

public class DeclExtendsEntry {
    public var decl: InheritableDecl
    public let extends: ArrayList<ExtendDecl> = ArrayList<ExtendDecl>()

    public init(decl: InheritableDecl) {
        this.decl = decl
    }
}

public class TyExtendsEntry {
    public var ty: Ty
    public let extends: ArrayList<ExtendDecl> = ArrayList<ExtendDecl>()

    public init(ty: Ty) {
        this.ty = ty
    }
}

private class TyUsedExtendsEntry {
    public var ty: Ty
    public let extends: ArrayList<ExtendDecl> = ArrayList<ExtendDecl>()

    public init(ty: Ty) {
        this.ty = ty
    }
}

private class CheckedTyExtendRelation {
    public var child: Ty
    public var interfaceTy: Ty

    public init(child: Ty, interfaceTy: Ty) {
        this.child = child
        this.interfaceTy = interfaceTy
    }
}

private class TyVarScopeDepthEntry {
    public var tyVar: GenericsTy
    public var depth: Int64

    public init(tyVar: GenericsTy, depth: Int64) {
        this.tyVar = tyVar
        this.depth = depth
    }
}

public class TypeManager {
    public let constraints: Constraint = Constraint()
    public let builtinTyToExtendMap: ArrayList<TyExtendsEntry> = ArrayList<TyExtendsEntry>()
    public let declToExtendMap: ArrayList<DeclExtendsEntry> = ArrayList<DeclExtendsEntry>()

    private var anyTy: Ty = AnyTy()
    private var ctypeTy: Option<Ty> = None
    private let overrideCache: ArrayList<OverrideCacheEntry> = ArrayList<OverrideCacheEntry>()
    private let topOverrideMap: ArrayList<TopOverrideEntry> = ArrayList<TopOverrideEntry>()
    private let boxUsedExtends: ArrayList<ExtendDecl> = ArrayList<ExtendDecl>()
    private let boxedNonGenericDecls: ArrayList<InheritableDecl> = ArrayList<InheritableDecl>()
    private let boxedTys: ArrayList<Ty> = ArrayList<Ty>()
    private let tyUsedExtends: ArrayList<TyUsedExtendsEntry> = ArrayList<TyUsedExtendsEntry>()
    private let checkedTyExtendRelation: ArrayList<CheckedTyExtendRelation> = ArrayList<CheckedTyExtendRelation>()
    private let unsolvedTyVars: ArrayList<GenericsTy> = ArrayList<GenericsTy>()
    private let tyVarScopes: ArrayList<TyVarScope> = ArrayList<TyVarScope>()
    private let tyVarScopeDepth: ArrayList<TyVarScopeDepthEntry> = ArrayList<TyVarScopeDepthEntry>()
    private let instCtxScopes: ArrayList<InstCtxScope> = ArrayList<InstCtxScope>()
    private var nextUniqId: UInt64 = 0u64

    public init() {
        tyVarScopes.add(TyVarScope())
    }

    public static func GetPrimitiveTy(kind: TypeKind): PrimitiveTy {
        if (kind == TypeKind.TYPE_NOTHING) {
            return NothingTy()
        }
        return PrimitiveTy(kind)
    }

    public static func GetInvalidTy(): InvalidTy {
        return InvalidTy()
    }

    public static func GetNothingTy(): PrimitiveTy {
        return NothingTy()
    }

    public static func GetQuestTy(): QuestTy {
        return QuestTy()
    }

    public static func GetCStringTy(): CStringTy {
        return CStringTy()
    }

    public static func GetBoolTy(): PrimitiveTy {
        return PrimitiveTy(TypeKind.TYPE_BOOLEAN)
    }

    public static func GetNonNullTy(ty: Ty): Ty {
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (enumTy.IsCoreOptionType() && enumTy.typeArgs.size == 1) {
                return enumTy.typeArgs[0]
            }
        }
        return ty
    }

    public static func IsCoreFutureType(ty: Ty): Bool {
        return ty.name == FUTURE_TYPE_NAME && (ty.IsClass() || ty.IsInterface() || ty.IsStruct())
    }

    public func GetGenericsTy(gpd: GenericParamDecl): GenericsTy {
        let raw = gpd.identifier.Val()
        let name = if (raw.isEmpty()) { "T" } else { raw }
        return GenericsTy(name, gpd)
    }

    public func GetEnumTy(ed: EnumDecl, typeArgs!: Array<Ty> = Array<Ty>()): EnumTy {
        return EnumTy(declName(ed), ed, typeArgs)
    }

    public func GetRefEnumTy(ed: EnumDecl, typeArgs: Array<Ty>): RefEnumTy {
        return RefEnumTy(declName(ed), ed, typeArgs)
    }

    public func GetStructTy(sd: StructDecl, typeArgs: Array<Ty>): StructTy {
        return StructTy(declName(sd), sd, typeArgs)
    }

    public func GetTupleTy(typeArgs: Array<Ty>, isClosureTy!: Bool = false): TupleTy {
        return TupleTy(typeArgs, isClosureTy: isClosureTy)
    }

    public func GetFunctionTy(paramTys: Array<Ty>, retTy: Ty, cfg!: FuncTyConfig = FuncTyConfig()): FuncTy {
        return FuncTy(paramTys, retTy, cfg: cfg)
    }

    public func GetArrayTy(elemTy: Ty, dims: UInt64): ArrayTy {
        return ArrayTy(elemTy, dims)
    }

    public func GetVArrayTy(elemTy: Ty, size: Int64): VArrayTy {
        return VArrayTy(elemTy, size)
    }

    public func GetPointerTy(elemTy: Ty): PointerTy {
        return PointerTy(elemTy)
    }

    public func GetArrayTy(): ArrayTy {
        return ArrayTy(GetInvalidTy(), 1u64)
    }

    public func GetClassTy(cd: ClassDecl, typeArgs: Array<Ty>): ClassTy {
        return ClassTy(declName(cd), cd, typeArgs)
    }

    public func GetClassThisTy(cd: ClassDecl, typeArgs: Array<Ty>): ClassThisTy {
        return ClassThisTy(declName(cd), cd, typeArgs)
    }

    public func GetInterfaceTy(id: InterfaceDecl, typeArgs: Array<Ty>): InterfaceTy {
        return InterfaceTy(declName(id), id, typeArgs)
    }

    public func GetTypeAliasTy(tad: TypeAliasDecl, typeArgs: Array<Ty>): TypeAliasTy {
        return TypeAliasTy(declName(tad), tad, typeArgs)
    }

    public func GetIntersectionTy(tys: Array<Ty>): Ty {
        if (tys.size == 0) {
            return GetInvalidTy()
        }
        if (tys.size == 1) {
            return tys[0]
        }
        return IntersectionTy(tys)
    }

    public func GetUnionTy(tys: Array<Ty>): Ty {
        if (tys.size == 0) {
            return GetInvalidTy()
        }
        if (tys.size == 1) {
            return tys[0]
        }
        return UnionTy(tys)
    }

    public func GetAnyTy(): Ty {
        return anyTy
    }

    public func GetCTypeTy(): Ty {
        if (let Some(value) <- ctypeTy) {
            return value
        }
        return anyTy
    }

    public func SetSemaAnyTy(semAnyTy: Ty): Unit {
        anyTy = semAnyTy
    }

    public func SetSemaCTypeTy(semCTypeTy: Ty): Unit {
        ctypeTy = semCTypeTy
    }

    public func GetInstantiatedTys(ty: Ty, mts: MultiTypeSubst): TySet {
        if (let Some(gen) <- (ty as GenericsTy)) {
            if (let Some(values) <- mts.Get(gen)) {
                return values.Clone()
            }
        }
        let out = TySet()
        out.Add(GetBestInstantiatedTy(ty, mts))
        return out
    }

    public func GetBestInstantiatedTy(ty: Ty, mts: MultiTypeSubst): Ty {
        if (let Some(gen) <- (ty as GenericsTy)) {
            if (let Some(values) <- mts.Get(gen)) {
                if (!values.values.isEmpty()) {
                    return values.values[0]
                }
            }
        }
        let subst = TypeSubst()
        for (entry in mts.entries) {
            if (!entry.tys.values.isEmpty()) {
                subst.Put(entry.tyVar, entry.tys.values[0])
            }
        }
        return GetInstantiatedTy(ty, subst)
    }

    public func GetInstantiatedTy(ty: Ty, typeMapping: TypeSubst): Ty {
        if (let Some(gen) <- (ty as GenericsTy)) {
            if (let Some(mapped) <- typeMapping.Get(gen)) {
                return mapped
            }
            return gen
        }
        if (let Some(arrayTy) <- (ty as ArrayTy)) {
            if (arrayTy.typeArgs.size == 1) {
                return GetArrayTy(GetInstantiatedTy(arrayTy.typeArgs[0], typeMapping), arrayTy.dims)
            }
        }
        if (let Some(varrayTy) <- (ty as VArrayTy)) {
            if (varrayTy.typeArgs.size == 1) {
                return GetVArrayTy(GetInstantiatedTy(varrayTy.typeArgs[0], typeMapping), varrayTy.size)
            }
        }
        if (let Some(pointerTy) <- (ty as PointerTy)) {
            if (pointerTy.typeArgs.size == 1) {
                return GetPointerTy(GetInstantiatedTy(pointerTy.typeArgs[0], typeMapping))
            }
        }
        if (let Some(tupleTy) <- (ty as TupleTy)) {
            let args = instantiateArgs(tupleTy.typeArgs, typeMapping)
            return GetTupleTy(args, isClosureTy: tupleTy.isClosureTy)
        }
        if (let Some(funcTy) <- (ty as FuncTy)) {
            let params = instantiateArgs(funcTy.paramTys, typeMapping)
            let ret = GetInstantiatedTy(funcTy.retTy, typeMapping)
            let cfg = FuncTyConfig()
            cfg.isC = funcTy.isC
            cfg.isClosureTy = funcTy.isClosureTy
            cfg.hasVariableLenArg = funcTy.hasVariableLenArg
            cfg.noCast = funcTy.noCast
            return GetFunctionTy(params, ret, cfg: cfg)
        }
        if (let Some(classTy) <- (ty as ClassThisTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                return GetClassThisTy(decl, instantiateArgs(classTy.typeArgs, typeMapping))
            }
        }
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                return GetClassTy(decl, instantiateArgs(classTy.typeArgs, typeMapping))
            }
        }
        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                return GetInterfaceTy(decl, instantiateArgs(interfaceTy.typeArgs, typeMapping))
            }
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                return GetStructTy(decl, instantiateArgs(structTy.typeArgs, typeMapping))
            }
        }
        if (let Some(refEnumTy) <- (ty as RefEnumTy)) {
            if (let Some(decl) <- refEnumTy.declPtr) {
                return GetRefEnumTy(decl, instantiateArgs(refEnumTy.typeArgs, typeMapping))
            }
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                return GetEnumTy(decl, typeArgs: instantiateArgs(enumTy.typeArgs, typeMapping))
            }
        }
        if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
            if (let Some(decl) <- aliasTy.declPtr) {
                return GetTypeAliasTy(decl, instantiateArgs(aliasTy.typeArgs, typeMapping))
            }
        }
        if (let Some(unionTy) <- (ty as UnionTy)) {
            return GetUnionTy(instantiateArgs(unionTy.tys, typeMapping))
        }
        if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
            return GetIntersectionTy(instantiateArgs(intersectionTy.tys, typeMapping))
        }
        return ty
    }

    public func ApplyTypeSubstForTys(subst: TypeSubst, tys: TySet): TySet {
        let out = TySet()
        for (ty in tys.values) {
            out.Add(GetInstantiatedTy(ty, subst))
        }
        return out
    }

    private func getSolvedU2I(maps: SubstPack): TypeSubst {
        let out = TypeSubst()
        for (entry in maps.u2i.entries) {
            if (let Some(instTv) <- (entry.ty as GenericsTy)) {
                if (let Some(_) <- maps.inst.Get(instTv)) {
                    out.Put(entry.tyVar, entry.ty)
                }
            }
        }
        return out
    }

    public func ApplySubstPack(declaredTy: Ty, maps: SubstPack, ignoreUnsolved!: Bool = false): Ty {
        let u2i = if (ignoreUnsolved) { getSolvedU2I(maps) } else { maps.u2i }
        let afterU2I = GetInstantiatedTy(declaredTy, u2i)
        return GetBestInstantiatedTy(afterU2I, maps.inst)
    }

    public func ApplySubstPackNonUniq(declaredTy: Ty, maps: SubstPack, ignoreUnsolved!: Bool = false): TySet {
        let u2i = if (ignoreUnsolved) { getSolvedU2I(maps) } else { maps.u2i }
        return GetInstantiatedTys(GetInstantiatedTy(declaredTy, u2i), maps.inst)
    }

    public func InstOf(ty: Ty): Ty {
        if (instCtxScopes.isEmpty()) {
            return ty
        }
        let topIndex = instCtxScopes.size - 1
        return ApplySubstPack(ty, instCtxScopes[topIndex].maps)
    }

    public func RecoverUnivTyVar(ty: Ty): Ty {
        if (instCtxScopes.isEmpty()) {
            return ty
        }
        let mapping = GetInstMapping()
        let i2uMap = TypeSubst()
        for (entry in mapping.u2i.entries) {
            if (let Some(instTv) <- (entry.ty as GenericsTy)) {
                i2uMap.Put(instTv, entry.tyVar)
            }
        }
        return GetInstantiatedTy(ty, i2uMap)
    }

    public func GetInstMapping(): SubstPack {
        if (instCtxScopes.isEmpty()) {
            return SubstPack()
        }
        let topIndex = instCtxScopes.size - 1
        return instCtxScopes[topIndex].maps.Clone()
    }

    private func ensureInstTyVar(maps: SubstPack, tv: GenericsTy): Option<GenericsTy> {
        if (let Some(existing) <- maps.u2i.Get(tv)) {
            if (let Some(existingGen) <- (existing as GenericsTy)) {
                return existingGen
            }
        }
        if (tv.isPlaceholder) {
            return None
        }
        let instTv = AllocTyVar(srcId: tv.name)
        maps.u2i.Put(tv, instTv)
        return instTv
    }

    public func PackMapping(maps: SubstPack, m: MultiTypeSubst): Unit {
        for (entry in m.entries) {
            if (entry.tyVar.isPlaceholder) {
                let instTys = entry.tys.Clone()
                let _ = instTys.Remove(entry.tyVar)
                maps.inst.PutAll(entry.tyVar, instTys)
            } else if (!entry.tys.IsEmpty()) {
                if (let Some(instTv) <- ensureInstTyVar(maps, entry.tyVar)) {
                    maps.inst.PutAll(instTv, entry.tys)
                }
            }
        }
    }

    public func PackMapping(maps: SubstPack, m: TypeSubst): Unit {
        for (entry in m.entries) {
            if (entry.tyVar.isPlaceholder) {
                if (!SameTy(entry.tyVar, entry.ty)) {
                    maps.inst.Put(entry.tyVar, entry.ty)
                }
            } else {
                if (let Some(instTv) <- ensureInstTyVar(maps, entry.tyVar)) {
                    maps.inst.Put(instTv, entry.ty)
                }
            }
        }
    }

    public func PackMapping(maps: SubstPack, tv: GenericsTy, instTy: Ty): Unit {
        if (tv.isPlaceholder) {
            if (!SameTy(tv, instTy)) {
                maps.inst.Put(tv, instTy)
            }
        } else {
            if (let Some(instTv) <- ensureInstTyVar(maps, tv)) {
                maps.inst.Put(instTv, instTy)
            }
        }
    }

    public func ZipSubstPack(mapping: SubstPack): MultiTypeSubst {
        let out = MultiTypeSubst()
        for (entry in mapping.u2i.entries) {
            if (let Some(instVar) <- (entry.ty as GenericsTy)) {
                if (let Some(instSet) <- mapping.inst.Get(instVar)) {
                    out.PutAll(entry.tyVar, instSet)
                } else {
                    out.Put(entry.tyVar, entry.ty)
                }
            } else {
                out.Put(entry.tyVar, entry.ty)
            }
        }
        return out
    }

    public func MakeInstTyVar(maps: SubstPack, uTv: GenericsTy): Unit {
        let _ = ensureInstTyVar(maps, uTv)
    }

    public func MakeInstTyVar(maps: SubstPack, d: Decl): Unit {
        if (let Some(generic) <- d.GetGeneric()) {
            for (param in generic.typeParameters) {
                if (let Some(paramTy) <- param.GetTy()) {
                    if (let Some(genTy) <- (paramTy as GenericsTy)) {
                        MakeInstTyVar(maps, genTy)
                    }
                }
            }
        }
    }

    public func GetTypeArgs(ty: Ty): ArrayList<Ty> {
        let out = ArrayList<Ty>()
        for (arg in ty.typeArgs) {
            out.add(arg)
        }
        return out
    }

    public func GetBlockRealTy(block: Block): Ty {
        if (let Some(ty) <- block.GetTy()) {
            return ty
        }
        return GetInvalidTy()
    }

    public func GetRealExtendedTy(child: Ty, interfaceTy: Ty): Ty {
        let _ = interfaceTy
        return child
    }

    public func GetAllSuperTys(ty: Ty, typeMapping!: TypeSubst = TypeSubst(), withExtended!: Bool = true): TySet {
        let _ = typeMapping
        let _ = withExtended
        let out = TySet()
        out.Add(ty)
        collectDeclaredSupers(ty, out)
        out.Add(anyTy)
        return out
    }

    public func HasSuperTy(ty: Ty, superTy: Ty, typeMapping: TypeSubst, withExtended!: Bool = true): Bool {
        let supers = GetAllSuperTys(ty, typeMapping: typeMapping, withExtended: withExtended)
        return supers.Contains(superTy)
    }

    public func GetAllCommonSuperTys(tys: TySet): TySet {
        let out = TySet()
        if (tys.values.isEmpty()) {
            return out
        }
        let firstSupers = GetAllSuperTys(tys.values[0])
        for (candidate in firstSupers.values) {
            var allHave = true
            for (ty in tys.values) {
                if (!HasSuperTy(ty, candidate, TypeSubst())) {
                    allHave = false
                    break
                }
            }
            if (allHave) {
                out.Add(candidate)
            }
        }
        return out
    }

    public func GetSubstituteMapping(nominalTy: Ty, typeMapping: TypeSubst): TypeSubst {
        let _ = nominalTy
        return typeMapping.Clone()
    }

    public func GetAllSuperInterfaceTysBFS(decl: InheritableDecl): ArrayList<InterfaceTy> {
        let out = ArrayList<InterfaceTy>()
        let queue = ArrayList<InterfaceTy>()
        for (ty in decl.GetSuperInterfaceTys()) {
            queue.add(ty)
        }
        var index: Int64 = 0
        while (index < queue.size) {
            let item = queue[index]
            index++
            if (!containsInterface(out, item)) {
                out.add(item)
                for (parent in item.GetSuperInterfaceTys()) {
                    queue.add(parent)
                }
            }
        }
        return out
    }

    public func IsSubtype(leaf: Ty, root: Ty, implicitBoxed!: Bool = true, allowOptionBox!: Bool = true): Bool {
        let _ = implicitBoxed
        let _ = allowOptionBox
        if (leaf.HasInvalidTy() || root.HasInvalidTy()) {
            return false
        }
        if (SameTy(leaf, root)) {
            return true
        }
        if (root.IsAny() || leaf.IsNothing()) {
            return true
        }
        if (IsPrimitiveNumericWidening(leaf, root)) {
            return true
        }
        if (let Some(rootUnion) <- (root as UnionTy)) {
            for (candidate in rootUnion.tys) {
                if (IsSubtype(leaf, candidate)) {
                    return true
                }
            }
            return false
        }
        if (let Some(leafUnion) <- (leaf as UnionTy)) {
            for (candidate in leafUnion.tys) {
                if (!IsSubtype(candidate, root)) {
                    return false
                }
            }
            return true
        }
        if (let Some(rootIntersection) <- (root as IntersectionTy)) {
            for (candidate in rootIntersection.tys) {
                if (!IsSubtype(leaf, candidate)) {
                    return false
                }
            }
            return true
        }
        if (let Some(leafIntersection) <- (leaf as IntersectionTy)) {
            for (candidate in leafIntersection.tys) {
                if (IsSubtype(candidate, root)) {
                    return true
                }
            }
        }
        if (leaf.IsFunc() && root.IsFunc()) {
            return IsFuncSubtype(leaf, root)
        }
        if (leaf.IsTuple() && root.IsTuple()) {
            return IsTupleSubtype(leaf, root)
        }
        if (leaf.IsArray() && root.IsArray()) {
            return SameTypeArgs(leaf.typeArgs, root.typeArgs)
        }
        if (leaf.IsPointer() && root.IsPointer()) {
            return SameTypeArgs(leaf.typeArgs, root.typeArgs)
        }
        if (leaf.IsGeneric()) {
            if (let Some(gen) <- (leaf as GenericsTy)) {
                for (upper in gen.upperBounds) {
                    if (IsSubtype(upper, root)) {
                        return true
                    }
                }
            }
        }
        return HasSuperTy(leaf, root, TypeSubst())
    }

    public func IsFuncSubtype(leaf: Ty, root: Ty): Bool {
        if (let Some(leftFunc) <- (leaf as FuncTy)) {
            if (let Some(rightFunc) <- (root as FuncTy)) {
                return IsFuncTySubType(leftFunc, rightFunc)
            }
        }
        return false
    }

    public func IsFuncParametersSubtype(leaf: FuncTy, root: FuncTy): Bool {
        if (leaf.paramTys.size != root.paramTys.size) {
            return false
        }
        for (idx in 0..leaf.paramTys.size) {
            if (!IsSubtype(root.paramTys[idx], leaf.paramTys[idx])) {
                return false
            }
        }
        return true
    }

    public func IsTupleSubtype(leaf: Ty, root: Ty): Bool {
        if (let Some(leftTuple) <- (leaf as TupleTy)) {
            if (let Some(rightTuple) <- (root as TupleTy)) {
                if (leftTuple.typeArgs.size != rightTuple.typeArgs.size) {
                    return false
                }
                for (idx in 0..leftTuple.typeArgs.size) {
                    if (!IsSubtype(leftTuple.typeArgs[idx], rightTuple.typeArgs[idx])) {
                        return false
                    }
                }
                return true
            }
        }
        return false
    }

    public func IsTyEqual(subTy: Ty, baseTy: Ty): Bool {
        return SameTy(subTy, baseTy)
    }

    public func IsPlaceholderEqual(leaf: Ty, root: Ty): Bool {
        return leaf.IsPlaceholder() && root.IsPlaceholder() && SameTy(leaf, root)
    }

    public func IsLitBoxableType(leaf: Ty, root: Ty): Bool {
        return IsPrimitiveNumericWidening(leaf, root)
    }

    public func HasExtensionRelation(childTy: Ty, interfaceTy: Ty): Bool {
        for (entry in builtinTyToExtendMap) {
            if (SameTy(entry.ty, childTy)) {
                for (extendDecl in entry.extends) {
                    for (inherited in extendDecl.inheritedTypes) {
                        if (let Some(ty) <- inherited.GetTy()) {
                            if (SameTy(ty, interfaceTy)) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    public func IsFuncParameterTypesIdentical(t1: FuncTy, t2: FuncTy): Bool {
        return IsFuncParameterTypesIdentical(t1.paramTys, t2.paramTys)
    }

    public func IsFuncParameterTypesIdentical(paramTys1: ArrayList<Ty>, paramTys2: ArrayList<Ty>,
        typeMapping!: TypeSubst = TypeSubst()): Bool {
        if (paramTys1.size != paramTys2.size) {
            return false
        }
        for (idx in 0..paramTys1.size) {
            if (!SameTy(GetInstantiatedTy(paramTys1[idx], typeMapping), paramTys2[idx])) {
                return false
            }
        }
        return true
    }

    public func CheckTypeCompatibility(lvalue: Ty, rvalue: Ty, implicitBoxed!: Bool = true,
        isGeneric!: Bool = false): TypeCompatibility {
        let _ = isGeneric
        if (SameTy(lvalue, rvalue)) {
            return TypeCompatibility.IDENTICAL
        }
        if (IsSubtype(rvalue, lvalue, implicitBoxed: implicitBoxed)) {
            return TypeCompatibility.SUBTYPE
        }
        return TypeCompatibility.INCOMPATIBLE
    }

    public func CheckGenericDeclInstantiation(d: Option<Decl>, typeArgs: ArrayList<Ty>): Bool {
        if (let Some(decl) <- d) {
            if (typeArgs.isEmpty()) {
                return true
            }
            let genericParamTys = GetDeclTypeParams(decl)
            if (genericParamTys.size != typeArgs.size) {
                return false
            }
            var idx: Int64 = 0
            while (idx < typeArgs.size) {
                if (!genericParamTys[idx].HasGeneric() && !SameTy(genericParamTys[idx], typeArgs[idx])) {
                    return false
                }
                idx++
            }
            if (let None <- decl.GetGeneric()) {
                return decl.astKind == ASTKind.EXTEND_DECL
            }
            let instantiateMap = GenerateTypeMapping(decl, typeArgs)
            if (decl.astKind == ASTKind.EXTEND_DECL) {
                idx = 0
                while (idx < typeArgs.size) {
                    let instantiatedParam = GetInstantiatedTy(genericParamTys[idx], instantiateMap)
                    if (!SameTy(instantiatedParam, typeArgs[idx])) {
                        return false
                    }
                    idx++
                }
            }
            return CheckGenericConstraints(decl, instantiateMap)
        }
        return false
    }

    public func CheckExtendWithConstraint(ty: Ty, extendDecl: Option<ExtendDecl>): Bool {
        if (let Some(value) <- extendDecl) {
            let declOpt: Option<Decl> = value as Decl
            return CheckGenericDeclInstantiation(declOpt, GetTypeArgs(ty))
        }
        return false
    }

    public func GetDeclTypeParams(decl: Decl): ArrayList<Ty> {
        let out = ArrayList<Ty>()
        if (let Some(generic) <- decl.GetGeneric()) {
            for (param in generic.typeParameters) {
                if (let Some(paramTy) <- param.GetTy()) {
                    out.add(paramTy)
                }
            }
        } else if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    for (typeArg in extendedTy.typeArgs) {
                        out.add(typeArg)
                    }
                }
            }
        }
        return out
    }

    private func hasVisitedGenericMappingTy(visited: ArrayList<Ty>, ty: Ty): Bool {
        for (value in visited) {
            if (SameTy(value, ty)) {
                return true
            }
        }
        return false
    }

    private func isInheritableTypeForGenericMapping(ty: Ty): Bool {
        if (!Ty.IsTyCorrect(ty) || !ty.IsClassLike()) {
            return false
        }
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(ty))) {
            return !decl.TestAttr(Attribute.IN_REFERENCE_CYCLE)
        }
        return false
    }

    private func generateGenericMappingVisit(m: MultiTypeSubst, baseType: Ty, visited: ArrayList<Ty>): Unit {
        if (!Ty.IsTyCorrect(baseType) || hasVisitedGenericMappingTy(visited, baseType)) {
            return
        }
        visited.add(baseType)
        generateExtendGenericMappingVisit(m, baseType, visited)
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(baseType))) {
            generateStructDeclGenericMappingVisit(m, decl, baseType, visited)
        }
    }

    private func generateExtendGenericMappingVisit(m: MultiTypeSubst, baseType: Ty, visited: ArrayList<Ty>): Unit {
        if (!Ty.IsTyCorrect(baseType)) {
            return
        }
        for (extendDecl in GetAllExtendsByTy(baseType)) {
            generateStructDeclGenericMappingVisit(m, extendDecl, baseType, visited)
        }
    }

    private func generateStructDeclGenericMappingVisit(m: MultiTypeSubst, decl: InheritableDecl, targetTy: Ty,
        visited: ArrayList<Ty>): Unit {
        if (!Ty.IsTyCorrect(targetTy)) {
            return
        }
        generateDeclGenericMapping(m, decl, targetTy)
        for (inheritedType in decl.inheritedTypes) {
            if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                if (isInheritableTypeForGenericMapping(inheritedTy)) {
                    generateGenericMappingVisit(m, inheritedTy, visited)
                }
            }
        }
    }

    private func generateGenericMappingVisit(m: SubstPack, baseType: Ty, visited: ArrayList<Ty>, contextual: Bool): Unit {
        if (!Ty.IsTyCorrect(baseType) || hasVisitedGenericMappingTy(visited, baseType)) {
            return
        }
        visited.add(baseType)
        generateExtendGenericMappingVisit(m, baseType, visited, contextual)
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(baseType))) {
            generateStructDeclGenericMappingVisit(m, decl, baseType, visited, contextual)
        }
    }

    private func generateExtendGenericMappingVisit(m: SubstPack, baseType: Ty, visited: ArrayList<Ty>,
        contextual: Bool): Unit {
        if (!Ty.IsTyCorrect(baseType)) {
            return
        }
        for (extendDecl in GetAllExtendsByTy(baseType)) {
            generateStructDeclGenericMappingVisit(m, extendDecl, baseType, visited, contextual)
        }
    }

    private func generateStructDeclGenericMappingVisit(m: SubstPack, decl: InheritableDecl, targetTy: Ty,
        visited: ArrayList<Ty>, contextual: Bool): Unit {
        if (!Ty.IsTyCorrect(targetTy)) {
            return
        }
        if (contextual) {
            GenerateTypeMapping(this, m, decl, targetTy.typeArgs)
        } else {
            let typeArgs = ArrayList<Ty>()
            for (argTy in targetTy.typeArgs) {
                typeArgs.add(GetInstantiatedTy(argTy, m.u2i))
            }
            GenerateTypeMapping(this, m, decl, typeArgs)
        }
        for (inheritedType in decl.inheritedTypes) {
            if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                if (isInheritableTypeForGenericMapping(inheritedTy)) {
                    generateGenericMappingVisit(m, inheritedTy, visited, false)
                }
            }
        }
    }

    public func GenerateStructDeclGenericMapping(m: MultiTypeSubst, decl: InheritableDecl, targetTy: Ty): Unit {
        let visited = ArrayList<Ty>()
        generateStructDeclGenericMappingVisit(m, decl, targetTy, visited)
    }

    public func GenerateGenericMapping(m: MultiTypeSubst, baseType: Ty): Unit {
        let visited = ArrayList<Ty>()
        generateGenericMappingVisit(m, baseType, visited)
    }

    public func GenerateGenericMapping(m: SubstPack, baseType: Ty): Unit {
        let visited = ArrayList<Ty>()
        generateGenericMappingVisit(m, baseType, visited, true)
    }

    public func GenerateGenericMappingFromGeneric(parentDecl: Decl, childDecl: Decl): TypeSubst {
        let out = TypeSubst()
        if (let Some(parentGeneric) <- parentDecl.GetGeneric()) {
            if (let Some(childGeneric) <- childDecl.GetGeneric()) {
                if (parentGeneric.typeParameters.size == childGeneric.typeParameters.size) {
                    var idx: Int64 = 0
                    while (idx < parentGeneric.typeParameters.size) {
                        if (let Some(parentParamTy) <- parentGeneric.typeParameters[idx].GetTy()) {
                            if (let Some(parentGenTy) <- (parentParamTy as GenericsTy)) {
                                if (let Some(childParamTy) <- childGeneric.typeParameters[idx].GetTy()) {
                                    out.Put(parentGenTy, childParamTy)
                                }
                            }
                        }
                        idx++
                    }
                }
            }
        }
        return out
    }

    public func GenerateStructDeclTypeMapping(decl: Decl): MultiTypeSubst {
        let out = MultiTypeSubst()
        if (!decl.IsNominalDecl()) {
            return out
        }
        var parentTy = decl.GetTy()
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                parentTy = extendedType.GetTy()
            } else {
                return out
            }
        }
        if (let Some(value) <- parentTy) {
            GenerateGenericMapping(out, value)
        }
        return out
    }

    public func ReplaceIdealTy(ty: Ty): Ty {
        if (ty.kind == TypeKind.TYPE_IDEAL_INT) {
            return GetPrimitiveTy(TypeKind.TYPE_INT64)
        }
        if (ty.kind == TypeKind.TYPE_IDEAL_FLOAT) {
            return GetPrimitiveTy(TypeKind.TYPE_FLOAT64)
        }
        return ty
    }

    public func RestoreJavaGenericsTy(decl: Decl): Unit {
        let _ = decl
    }

    public func GetAllExtendInterfaceTy(ty: Ty): TySet {
        let out = TySet()
        for (entry in builtinTyToExtendMap) {
            if (SameTy(entry.ty, ty)) {
                for (extendDecl in entry.extends) {
                    for (inherited in extendDecl.inheritedTypes) {
                        if (let Some(inheritedTy) <- inherited.GetTy()) {
                            out.Add(inheritedTy)
                        }
                    }
                }
            }
        }
        return out
    }

    public func HasExtendedInterfaceTy(ty: Ty, superTy: Ty, typeMapping: TypeSubst): Bool {
        let _ = typeMapping
        return GetAllExtendInterfaceTy(ty).Contains(superTy)
    }

    public func GetTyForExtendMap(ty: Ty): Ty {
        if (ty.IsArray()) {
            return GetArrayTy()
        }
        if (ty.IsPointer()) {
            return GetPointerTy(TypeManager.GetInvalidTy())
        }
        if (let Some(genericTy) <- Ty.GetGenericTyOfInsTy(ty)) {
            return genericTy
        }
        return ty
    }

    private func addBuiltinExtendsForTy(out: ArrayList<ExtendDecl>, ty: Ty): Unit {
        for (entry in builtinTyToExtendMap) {
            if (SameTy(entry.ty, ty)) {
                addUniqueExtends(out, entry.extends)
            }
        }
    }

    private func collectIdealBuiltinExtends(ty: Ty): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        if (ty.kind == TypeKind.TYPE_IDEAL_INT) {
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_INT64))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_UINT64))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_INT32))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_UINT32))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_INT16))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_UINT16))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_INT8))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_UINT8))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_INT_NATIVE))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_UINT_NATIVE))
        } else if (ty.kind == TypeKind.TYPE_IDEAL_FLOAT) {
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_FLOAT64))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_FLOAT32))
            addBuiltinExtendsForTy(out, GetPrimitiveTy(TypeKind.TYPE_FLOAT16))
        }
        return out
    }

    public func GetBuiltinTyExtends(ty: Ty): ArrayList<ExtendDecl> {
        if (ty.IsIdeal()) {
            return collectIdealBuiltinExtends(ty)
        }
        for (entry in builtinTyToExtendMap) {
            if (SameTy(entry.ty, ty)) {
                return entry.extends
            }
        }
        return ArrayList<ExtendDecl>()
    }

    public func GetOverrideCache(src: Option<FuncDecl>, target: Option<FuncDecl>, baseTy: Option<Ty>,
        expectInstParent: Option<Ty>): Option<Bool> {
        if (let Some(srcDecl) <- src) {
            if (let Some(targetDecl) <- target) {
                for (entry in overrideCache) {
                    if (SameDecl(entry.src, srcDecl) && SameDecl(entry.target, targetDecl) &&
                        SameTy(entry.baseTy, baseTy) && SameTy(entry.expectInstParent, expectInstParent)) {
                        return entry.value
                    }
                }
            }
        }
        return None
    }

    public func AddOverrideCache(src: FuncDecl, target: FuncDecl, baseTy: Option<Ty>, expectInstParent: Option<Ty>,
        value: Bool): Unit {
        overrideCache.add(OverrideCacheEntry(src, target, baseTy, expectInstParent, value))
    }

    public func GetDeclExtends(decl: InheritableDecl): ArrayList<ExtendDecl> {
        for (entry in declToExtendMap) {
            if (SameDecl(entry.decl, decl)) {
                return entry.extends
            }
        }
        return ArrayList<ExtendDecl>()
    }

    public func GetAllExtendsByTy(ty: Ty): ArrayList<ExtendDecl> {
        if (let Some(decl) <- declOfInheritableTy(ty)) {
            return GetDeclExtends(decl)
        }
        return GetBuiltinTyExtends(GetTyForExtendMap(ty))
    }

    public func GetAllExtendedDecls(): ArrayList<InheritableDecl> {
        let out = ArrayList<InheritableDecl>()
        for (entry in declToExtendMap) {
            out.add(entry.decl)
        }
        return out
    }

    public func GetAllExtendedBuiltIn(): TySet {
        let out = TySet()
        for (entry in builtinTyToExtendMap) {
            out.Add(entry.ty)
        }
        return out
    }

    public func UpdateBuiltInTyExtendDecl(builtinTy: Ty, ed: ExtendDecl): Unit {
        for (entry in builtinTyToExtendMap) {
            if (SameTy(entry.ty, builtinTy)) {
                entry.extends.add(ed)
                return
            }
        }
        let entry = TyExtendsEntry(builtinTy)
        entry.extends.add(ed)
        builtinTyToExtendMap.add(entry)
    }

    public func RecordUsedExtend(child: Ty, interfaceTy: Ty): Unit {
        if (hasCheckedTyExtendRelation(child, interfaceTy)) {
            return
        }
        checkedTyExtendRelation.add(CheckedTyExtendRelation(child, interfaceTy))
        let extendedTy = GetRealExtendedTy(child, interfaceTy)
        addBoxedTy(extendedTy)
        RecordUsedGenericExtend(extendedTy)
        if (let Some(decl) <- declOfInheritableTy(extendedTy)) {
            if (let None <- decl.GetGeneric()) {
                addBoxedNonGenericDecl(decl)
            }
            addBoxUsedExtends(collectAllRelatedExtends(decl))
        } else {
            addBoxUsedExtends(GetAllExtendsByTy(extendedTy))
        }
    }

    public func RecordUsedGenericExtend(boxedTy: Ty, extendDecl!: Option<ExtendDecl> = None): Unit {
        addBoxedTy(boxedTy)
        if (let Some(ed) <- extendDecl) {
            if ((let None <- ed.GetGeneric()) || ed.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                return
            }
            addTyUsedExtend(boxedTy, ed)
            return
        }
        if (let Some(decl) <- declOfInheritableTy(boxedTy)) {
            addTyUsedExtends(boxedTy, collectAllRelatedExtends(decl))
        } else {
            addTyUsedExtends(boxedTy, GetAllExtendsByTy(boxedTy))
        }
    }

    public func RemoveExtendFromMap(ed: ExtendDecl): Unit {
        for (entry in builtinTyToExtendMap) {
            removeExtend(entry.extends, ed)
        }
        for (entry in declToExtendMap) {
            removeExtend(entry.extends, ed)
        }
    }

    public func GetAllBoxedTys(): ArrayList<Ty> {
        return boxedTys
    }

    public func Clear(): Unit {
        constraints.Clear()
        ClearMapCache()
        unsolvedTyVars.clear()
    }

    public func ClearMapCache(): Unit {
        builtinTyToExtendMap.clear()
        declToExtendMap.clear()
        overrideCache.clear()
        ClearRecordUsedExtends()
    }

    public func GetBoxUsedExtends(): ArrayList<ExtendDecl> {
        return boxUsedExtends
    }

    public func GetBoxedNonGenericDecls(): ArrayList<InheritableDecl> {
        return boxedNonGenericDecls
    }

    public func GetTyUsedExtends(ty: Ty): ArrayList<ExtendDecl> {
        if (let Some(entry) <- findTyUsedExtendsEntry(ty)) {
            return entry.extends
        }
        return ArrayList<ExtendDecl>()
    }

    public func ClearRecordUsedExtends(): Unit {
        boxUsedExtends.clear()
        boxedTys.clear()
        tyUsedExtends.clear()
        checkedTyExtendRelation.clear()
    }

    public func ReleaseSemaQueryCaches(): Unit {
        overrideCache.clear()
    }

    public func ReleasePostSemaCaches(): Unit {
        ClearRecordUsedExtends()
    }

    public func GetOverrideDeclInClassLike(baseDecl: Decl, funcDecl: FuncDecl,
        withAbstractOverrides!: Bool = false): Option<Decl> {
        let _ = withAbstractOverrides
        for (member in baseDecl.GetMemberDecls()) {
            if (let Some(memberFunc) <- (member as FuncDecl)) {
                if (IsFuncDeclEqualType(memberFunc, funcDecl)) {
                    return member
                }
            }
        }
        return None
    }

    public func UpdateTopOverriddenFuncDeclMap(src: Option<Decl>, target: Option<Decl>): Unit {
        if (let Some(srcDecl) <- src) {
            if (let Some(targetDecl) <- target) {
                if (SameDecl(srcDecl, targetDecl)) {
                    return
                }
                if (let Some(srcFunc) <- (srcDecl as FuncDecl)) {
                    if (let Some(targetFunc) <- (targetDecl as FuncDecl)) {
                        addTopOverride(srcFunc, targetFunc)
                    }
                } else if (let Some(srcProp) <- (srcDecl as PropDecl)) {
                    if (let Some(targetProp) <- (targetDecl as PropDecl)) {
                        if (!srcProp.getters.isEmpty() && !targetProp.getters.isEmpty()) {
                            addTopOverride(srcProp.getters[0], targetProp.getters[0])
                        }
                        if (!srcProp.setters.isEmpty() && !targetProp.setters.isEmpty()) {
                            addTopOverride(srcProp.setters[0], targetProp.setters[0])
                        }
                    }
                }
            }
        }
    }

    public func GetTopOverriddenFuncDecl(funcDecl: Option<FuncDecl>): Option<FuncDecl> {
        if (let Some(fd) <- funcDecl) {
            if (let Some(first) <- firstTopOverrideTarget(fd)) {
                var current = first
                let traversed = ArrayList<FuncDecl>()
                while (let Some(next) <- firstTopOverrideTarget(current)) {
                    if (containsFuncDecl(traversed, current)) {
                        return None
                    }
                    traversed.add(current)
                    current = next
                }
                return current
            }
        }
        return None
    }

    public func IsFuncDeclSubType(decl: FuncDecl, funcDecl: FuncDecl): Bool {
        if (let Some(leftTy) <- decl.GetTy()) {
            if (let Some(rightTy) <- funcDecl.GetTy()) {
                return IsFuncSubtype(leftTy, rightTy)
            }
        }
        return false
    }

    public func IsFuncTySubType(type1: FuncTy, type2: FuncTy): Bool {
        if (type1.paramTys.size != type2.paramTys.size) {
            return false
        }
        if (type1.isC != type2.isC || type1.hasVariableLenArg != type2.hasVariableLenArg) {
            return false
        }
        if (!IsSubtype(type1.retTy, type2.retTy)) {
            return false
        }
        return IsFuncParametersSubtype(type1, type2)
    }

    public func IsFuncDeclEqualType(decl: FuncDecl, funcDecl: FuncDecl): Bool {
        if (let Some(leftTy) <- decl.GetTy()) {
            if (let Some(rightTy) <- funcDecl.GetTy()) {
                return SameTy(leftTy, rightTy)
            }
        }
        return decl.identifier == funcDecl.identifier
    }

    public func IsExtendInheritRelation(r: ExtendDecl, l: ExtendDecl): (Bool, Bool) {
        let rInterfaces = collectExtendInterfaces(r)
        let lInterfaces = collectExtendInterfaces(l)
        for (rightTy in rInterfaces.values) {
            for (leftTy in lInterfaces.values) {
                if (SameTy(rightTy, leftTy)) {
                    return (true, false)
                }
                if (IsSubtype(leftTy, rightTy)) {
                    return (true, true)
                }
                if (IsSubtype(rightTy, leftTy)) {
                    return (true, false)
                }
            }
        }
        return (false, false)
    }

    public func PairIsOverrideOrImpl(child: Decl, parent: Decl, baseTy!: Option<Ty> = None,
        parentTy!: Option<Ty> = None): Bool {
        let _ = baseTy
        let _ = parentTy
        if (child.identifier != parent.identifier) {
            return false
        }
        if (let Some(childFunc) <- (child as FuncDecl)) {
            if (let Some(parentFunc) <- (parent as FuncDecl)) {
                return IsFuncDeclSubType(childFunc, parentFunc) || IsFuncDeclEqualType(childFunc, parentFunc)
            }
        }
        return false
    }

    public func ConstrainByCtor(tv: GenericsTy, tyCtor: Ty): Option<Ty> {
        let bounds = constraints.GetOrCreate(tv)
        bounds.ubs.Add(tyCtor)
        return tyCtor
    }

    public func AddSumByCtor(tv: GenericsTy, tyCtor: Ty, tyArgs: ArrayList<GenericsTy>): Option<Ty> {
        let _ = tyArgs
        let bounds = constraints.GetOrCreate(tv)
        bounds.sum.Add(tyCtor)
        return tyCtor
    }

    public func OfSameCtor(ty: Ty, tyCtor: Ty): Bool {
        return ty.kind == tyCtor.kind && ty.name == tyCtor.name && ty.typeArgs.size == tyCtor.typeArgs.size
    }

    public func GetDummyBuiltInDecl(ty: Ty): Decl {
        let decl = BuiltInDecl(BuiltInType.ARRAY)
        decl.identifier = SrcIdentifier(ty.name)
        decl.SetTy(ty)
        return decl
    }

    public func GetExtendDeclByInterface(baseTy: Ty, interfaceTy: Ty): Option<ExtendDecl> {
        for (extendDecl in GetBuiltinTyExtends(baseTy)) {
            for (inherited in extendDecl.inheritedTypes) {
                if (let Some(ty) <- inherited.GetTy()) {
                    if (SameTy(ty, interfaceTy)) {
                        return extendDecl
                    }
                }
            }
        }
        return None
    }

    public func GetExtendDeclByMember(member: Decl, baseTy: Ty): Option<ExtendDecl> {
        for (extendDecl in GetBuiltinTyExtends(baseTy)) {
            for (decl in extendDecl.GetMemberDecls()) {
                if (SameDecl(decl, member)) {
                    return extendDecl
                }
            }
        }
        return None
    }

    private func putTyVarScopeDepth(tyVar: GenericsTy, depth: Int64): Unit {
        for (entry in tyVarScopeDepth) {
            if (SameTy(entry.tyVar, tyVar)) {
                entry.depth = depth
                return
            }
        }
        tyVarScopeDepth.add(TyVarScopeDepthEntry(tyVar, depth))
    }

    private func removeTyVarScopeDepth(tyVar: GenericsTy): Unit {
        var idx: Int64 = 0
        while (idx < tyVarScopeDepth.size) {
            if (SameTy(tyVarScopeDepth[idx].tyVar, tyVar)) {
                tyVarScopeDepth.remove(at: idx)
                return
            }
            idx++
        }
    }

    private func findTyVarScopeDepth(tyVar: GenericsTy): Option<Int64> {
        for (entry in tyVarScopeDepth) {
            if (SameTy(entry.tyVar, tyVar)) {
                return entry.depth
            }
        }
        var idx: Int64 = 0
        while (idx < tyVarScopes.size) {
            if (tyVarScopes[idx].ContainsTyVar(tyVar)) {
                putTyVarScopeDepth(tyVar, idx)
                return idx
            }
            idx++
        }
        return None
    }

    private func currentTyVarScopeDepth(): Int64 {
        if (tyVarScopes.isEmpty()) {
            tyVarScopes.add(TyVarScope())
        }
        return tyVarScopes.size - 1
    }

    private func addTyVarToScope(tyVar: GenericsTy, depth: Int64): Unit {
        if (depth >= 0 && depth < tyVarScopes.size) {
            tyVarScopes[depth].AddTyVar(tyVar)
            putTyVarScopeDepth(tyVar, depth)
            return
        }
        let fallbackDepth = currentTyVarScopeDepth()
        tyVarScopes[fallbackDepth].AddTyVar(tyVar)
        putTyVarScopeDepth(tyVar, fallbackDepth)
    }

    public func AllocTyVar(srcId!: String = "Ti", needSolving!: Bool = false,
        derivedFrom!: Option<GenericsTy> = None): GenericsTy {
        let decl = GenericParamDecl()
        decl.identifier = SrcIdentifier("${srcId}${nextUniqId}")
        nextUniqId++
        let tv = GenericsTy(decl.identifier.Val(), decl)
        tv.isPlaceholder = true
        if (let Some(parent) <- derivedFrom) {
            for (upper in parent.upperBounds) {
                tv.upperBounds.add(upper)
            }
            tv.lowerBound = parent.lowerBound
        }
        if (let Some(parent) <- derivedFrom) {
            if (let Some(parentDepth) <- findTyVarScopeDepth(parent)) {
                addTyVarToScope(tv, parentDepth)
            } else {
                addTyVarToScope(tv, currentTyVarScopeDepth())
            }
        } else {
            addTyVarToScope(tv, currentTyVarScopeDepth())
        }
        if (needSolving) {
            MarkAsUnsolvedTyVar(tv)
        }
        return tv
    }

    public func PushTyVarScope(scope: TyVarScope): Unit {
        tyVarScopes.add(scope)
    }

    public func PopTyVarScope(scope: TyVarScope): Unit {
        let _ = scope
        if (tyVarScopes.isEmpty()) {
            return
        }
        tyVarScopes.remove(at: tyVarScopes.size - 1)
    }

    public func PushInstCtxScope(scope: InstCtxScope): Unit {
        instCtxScopes.add(scope)
    }

    public func PopInstCtxScope(scope: InstCtxScope): Unit {
        let _ = scope
        if (instCtxScopes.isEmpty()) {
            return
        }
        instCtxScopes.remove(at: instCtxScopes.size - 1)
    }

    public func ReleaseTyVar(tv: GenericsTy): Unit {
        tv.upperBounds.clear()
        tv.lowerBound = None
        var idx: Int64 = 0
        while (idx < unsolvedTyVars.size) {
            if (SameTy(unsolvedTyVars[idx], tv)) {
                unsolvedTyVars.remove(at: idx)
            } else {
                idx++
            }
        }
        removeTyVarScopeDepth(tv)
    }

    public func ScopeDepthOfTyVar(tyVar: GenericsTy): Int64 {
        if (let Some(depth) <- findTyVarScopeDepth(tyVar)) {
            return depth
        }
        return 0
    }

    public func TyVarHasNoSum(tv: GenericsTy): Bool {
        let sum = constraints.GetOrCreate(tv).sum
        return sum.Size() == 1 && sum.values[0].IsAny()
    }

    public func GetUnsolvedTyVars(): ArrayList<GenericsTy> {
        return unsolvedTyVars
    }

    public func MarkAsUnsolvedTyVar(tv: GenericsTy): Unit {
        if (!containsGeneric(unsolvedTyVars, tv)) {
            unsolvedTyVars.add(tv)
        }
        constraints.GetOrCreate(tv).sum.Add(GetAnyTy())
    }

    public func GetInnermostUnsolvedTyVars(): ArrayList<GenericsTy> {
        let out = ArrayList<GenericsTy>()
        if (tyVarScopes.isEmpty()) {
            return out
        }
        tyVarScopes[tyVarScopes.size - 1].AddUnsolvedTyVars(out, unsolvedTyVars)
        return out
    }

    public func TryGreedySubst(ty: Ty): Ty {
        if (let Some(gen) <- (ty as GenericsTy)) {
            let bounds = constraints.GetOrCreate(gen)
            if (bounds.eq.Size() == 1) {
                return bounds.eq.values[0]
            }
        }
        return ty
    }

    public func ReplaceThisTy(now: Ty): Ty {
        if (let Some(thisTy) <- (now as ClassThisTy)) {
            if (let Some(decl) <- thisTy.declPtr) {
                return GetClassTy(decl, CopyTypeArgs(thisTy.typeArgs))
            }
        }
        return now
    }

    public func GetThisRealTy(now: Ty): Ty {
        return ReplaceThisTy(now)
    }

    public func ObtainsAliasType(node: Option<Node>): Option<Ty> {
        if (let Some(value) <- node) {
            if (let Some(ty) <- value.GetTy()) {
                if (ty.HasAliasTy()) {
                    return ty
                }
            }
        }
        return None
    }

    public func SubstituteTypeAliasInTy(ty: Ty, needSubstituteGeneric!: Bool = false,
        typeMapping!: TypeSubst = TypeSubst()): Ty {
        let _ = needSubstituteGeneric
        if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
            if (let Some(decl) <- aliasTy.declPtr) {
                if (decl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                    return GetInstantiatedTy(ty, typeMapping)
                }
                if (let Some(typeNode) <- decl.typeNode) {
                    if (let Some(targetTy) <- typeNode.GetTy()) {
                        return GetInstantiatedTy(targetTy, typeMapping)
                    }
                }
            }
        }
        return GetInstantiatedTy(ty, typeMapping)
    }

    private func declName(decl: Decl): String {
        let name = decl.identifier.Val()
        return if (name.isEmpty()) { decl.identifier.GetRawText() } else { name }
    }

    private func instantiateArgs(args: ArrayList<Ty>, typeMapping: TypeSubst): Array<Ty> {
        let out = ArrayList<Ty>()
        for (arg in args) {
            out.add(GetInstantiatedTy(arg, typeMapping))
        }
        return out.toArray()
    }

    private func collectDeclaredSupers(ty: Ty, out: TySet): Unit {
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(superClass) <- classTy.GetSuperClassTy()) {
                if (out.Add(superClass)) {
                    collectDeclaredSupers(superClass, out)
                }
            }
            for (interfaceTy in classTy.GetSuperInterfaceTys()) {
                if (out.Add(interfaceTy)) {
                    collectDeclaredSupers(interfaceTy, out)
                }
            }
        } else if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            for (parent in interfaceTy.GetSuperInterfaceTys()) {
                if (out.Add(parent)) {
                    collectDeclaredSupers(parent, out)
                }
            }
        } else if (let Some(structTy) <- (ty as StructTy)) {
            for (interfaceTy in structTy.GetSuperInterfaceTys()) {
                if (out.Add(interfaceTy)) {
                    collectDeclaredSupers(interfaceTy, out)
                }
            }
        } else if (let Some(enumTy) <- (ty as EnumTy)) {
            for (interfaceTy in enumTy.GetSuperInterfaceTys()) {
                if (out.Add(interfaceTy)) {
                    collectDeclaredSupers(interfaceTy, out)
                }
            }
        }
    }

    private func containsInterface(values: ArrayList<InterfaceTy>, ty: InterfaceTy): Bool {
        for (value in values) {
            if (SameTy(value, ty)) {
                return true
            }
        }
        return false
    }

    private func containsTy(values: ArrayList<Ty>, ty: Ty): Bool {
        for (value in values) {
            if (SameTy(value, ty)) {
                return true
            }
        }
        return false
    }

    private func containsGeneric(values: ArrayList<GenericsTy>, ty: GenericsTy): Bool {
        for (value in values) {
            if (SameTy(value, ty)) {
                return true
            }
        }
        return false
    }

    private func containsFuncDecl(values: ArrayList<FuncDecl>, decl: FuncDecl): Bool {
        for (value in values) {
            if (SameDecl(value, decl)) {
                return true
            }
        }
        return false
    }

    private func findTopOverrideEntry(src: FuncDecl): Option<TopOverrideEntry> {
        for (entry in topOverrideMap) {
            if (SameDecl(entry.src, src)) {
                return entry
            }
        }
        return None
    }

    private func addTopOverride(src: FuncDecl, target: FuncDecl): Unit {
        if (SameDecl(src, target)) {
            return
        }
        if (let Some(entry) <- findTopOverrideEntry(src)) {
            if (!containsFuncDecl(entry.targets, target)) {
                entry.targets.add(target)
            }
            return
        }
        let entry = TopOverrideEntry(src)
        entry.targets.add(target)
        topOverrideMap.add(entry)
    }

    private func firstTopOverrideTarget(src: FuncDecl): Option<FuncDecl> {
        if (let Some(entry) <- findTopOverrideEntry(src)) {
            if (!entry.targets.isEmpty()) {
                return entry.targets[0]
            }
        }
        return None
    }

    private func addBoxedTy(ty: Ty): Unit {
        if (!containsTy(boxedTys, ty)) {
            boxedTys.add(ty)
        }
    }

    private func addBoxedNonGenericDecl(decl: InheritableDecl): Unit {
        for (value in boxedNonGenericDecls) {
            if (SameDecl(value, decl)) {
                return
            }
        }
        boxedNonGenericDecls.add(decl)
    }

    private func addBoxUsedExtend(extendDecl: ExtendDecl): Unit {
        if (!containsExtend(boxUsedExtends, extendDecl)) {
            boxUsedExtends.add(extendDecl)
        }
    }

    private func addBoxUsedExtends(extends: ArrayList<ExtendDecl>): Unit {
        for (extendDecl in extends) {
            addBoxUsedExtend(extendDecl)
        }
    }

    private func hasCheckedTyExtendRelation(child: Ty, interfaceTy: Ty): Bool {
        for (entry in checkedTyExtendRelation) {
            if (SameTy(entry.child, child) && SameTy(entry.interfaceTy, interfaceTy)) {
                return true
            }
        }
        return false
    }

    private func findTyUsedExtendsEntry(ty: Ty): Option<TyUsedExtendsEntry> {
        for (entry in tyUsedExtends) {
            if (SameTy(entry.ty, ty)) {
                return entry
            }
        }
        return None
    }

    private func getOrCreateTyUsedExtendsEntry(ty: Ty): TyUsedExtendsEntry {
        if (let Some(entry) <- findTyUsedExtendsEntry(ty)) {
            return entry
        }
        let entry = TyUsedExtendsEntry(ty)
        tyUsedExtends.add(entry)
        return entry
    }

    private func addTyUsedExtend(ty: Ty, extendDecl: ExtendDecl): Unit {
        let entry = getOrCreateTyUsedExtendsEntry(ty)
        if (!containsExtend(entry.extends, extendDecl)) {
            entry.extends.add(extendDecl)
        }
    }

    private func addTyUsedExtends(ty: Ty, extends: ArrayList<ExtendDecl>): Unit {
        for (extendDecl in extends) {
            addTyUsedExtend(ty, extendDecl)
        }
    }

    private func declOfInheritableTy(ty: Ty): Option<InheritableDecl> {
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                return decl
            }
        }
        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                return decl
            }
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                return decl
            }
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                return decl
            }
        }
        return None
    }

    private func collectAllRelatedExtends(decl: InheritableDecl): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        addUniqueExtends(out, GetDeclExtends(decl))
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            var current = classDecl.GetSuperClassDecl()
            while (let Some(superClass) <- current) {
                addUniqueExtends(out, GetDeclExtends(superClass))
                current = superClass.GetSuperClassDecl()
            }
        }
        return out
    }

    private func addUniqueExtends(target: ArrayList<ExtendDecl>, source: ArrayList<ExtendDecl>): Unit {
        for (extendDecl in source) {
            if (!containsExtend(target, extendDecl)) {
                target.add(extendDecl)
            }
        }
    }

    private func containsExtend(values: ArrayList<ExtendDecl>, ed: ExtendDecl): Bool {
        for (value in values) {
            if (SameDecl(value, ed)) {
                return true
            }
        }
        return false
    }

    private func removeExtend(values: ArrayList<ExtendDecl>, ed: ExtendDecl): Unit {
        var idx: Int64 = 0
        while (idx < values.size) {
            if (SameDecl(values[idx], ed)) {
                values.remove(at: idx)
            } else {
                idx++
            }
        }
    }

    private func collectExtendInterfaces(extendDecl: ExtendDecl): TySet {
        let out = TySet()
        for (inherited in extendDecl.inheritedTypes) {
            if (let Some(ty) <- inherited.GetTy()) {
                out.Add(ty)
            }
        }
        return out
    }

    private func generateDeclGenericMapping(m: MultiTypeSubst, decl: InheritableDecl, targetTy: Ty): Unit {
        if (let Some(generic) <- decl.GetGeneric()) {
            var idx: Int64 = 0
            while (idx < generic.typeParameters.size && idx < targetTy.typeArgs.size) {
                if (let Some(paramTy) <- generic.typeParameters[idx].GetTy()) {
                    if (let Some(genTy) <- (paramTy as GenericsTy)) {
                        m.Put(genTy, targetTy.typeArgs[idx])
                    }
                }
                idx++
            }
        }
    }

    private func GenerateTypeMapping(decl: Decl, typeArgs: ArrayList<Ty>): TypeSubst {
        let out = TypeSubst()
        if (let Some(generic) <- decl.GetGeneric()) {
            var idx: Int64 = 0
            while (idx < generic.typeParameters.size && idx < typeArgs.size) {
                if (let Some(paramTy) <- generic.typeParameters[idx].GetTy()) {
                    if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                        out.Put(genericTy, typeArgs[idx])
                    }
                }
                idx++
            }
        }
        return out
    }

    private func CheckGenericConstraints(decl: Decl, instantiateMap: TypeSubst): Bool {
        if (let Some(generic) <- decl.GetGeneric()) {
            for (constraint in generic.genericConstraints) {
                if (let None <- constraint.refType) {
                    return false
                }
                let refType = constraint.refType.getOrThrow()
                if (let None <- refType.GetTy()) {
                    return false
                }
                let typeTy = GetInstantiatedTy(refType.GetTy().getOrThrow(), instantiateMap)
                let isNotGeneric = typeTy.kind != TypeKind.TYPE_GENERICS
                for (upperBound in constraint.upperBounds) {
                    if (let None <- upperBound.GetTy()) {
                        return false
                    }
                    let upperBoundTy = GetInstantiatedTy(upperBound.GetTy().getOrThrow(), instantiateMap)
                    let typeNotMatch = !IsSubtype(typeTy, upperBoundTy)
                    if (isNotGeneric && typeNotMatch) {
                        return false
                    }
                    if (isNotGeneric) {
                        continue
                    }
                    if (let Some(genericTy) <- (typeTy as GenericsTy)) {
                        var satisfyConstraint = false
                        for (assumptionUpper in genericTy.upperBounds) {
                            if (IsSubtype(assumptionUpper, upperBoundTy)) {
                                satisfyConstraint = true
                                break
                            }
                        }
                        if (!satisfyConstraint && typeNotMatch) {
                            return false
                        }
                    } else if (typeNotMatch) {
                        return false
                    }
                }
            }
        }
        return true
    }
}
