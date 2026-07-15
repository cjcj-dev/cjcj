package cjcj::sema

import std.collection.*
import std.env.getVariable
import std.sort.*
import cjcj::ast.*
import cjcj::modules.GetPackageRelation as ModulesGetPackageRelation
import cjcj::modules.PackageRelation as ModulesPackageRelation
import cjcj::modules.SplitQualifiedName as ModulesSplitQualifiedName
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, PData}

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

private func insertTypeManagerCacheKeyPair(pairs: ArrayList<(Int64, Int64)>, pair: (Int64, Int64)): Unit {
    var idx: Int64 = 0
    while (idx < pairs.size) {
        let current = pairs[idx]
        if (pair[0] < current[0] || (pair[0] == current[0] && pair[1] < current[1])) {
            pairs.add(pair, at: idx)
            return
        }
        idx++
    }
    pairs.add(pair)
}

private func typeSubstCacheKey(mapping: TypeSubst): String {
    let builder = StringBuilder()
    let pairs = ArrayList<(Int64, Int64)>()
    for ((tyVar, ty) in mapping.entries) {
        insertTypeManagerCacheKeyPair(pairs, (tyVar.value.objectId, ty.objectId))
    }
    for (pair in pairs) {
        builder.append("|")
        builder.append(pair[0].toString())
        builder.append("=")
        builder.append(pair[1].toString())
    }
    return builder.toString()
}

private func superTysCacheKey(ty: Ty, mapping: TypeSubst, withExtended: Bool): String {
    let builder = StringBuilder()
    builder.append(ty.objectId.toString())
    builder.append(if (withExtended) { ":1" } else { ":0" })
    builder.append(typeSubstCacheKey(mapping))
    return builder.toString()
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
            if (Ptr<GenericsTy>(value) == Ptr<GenericsTy>(tyVar)) {
                return true
            }
        }
        return false
    }

    public func AddUnsolvedTyVars(out: ArrayList<GenericsTy>, unsolved: ArrayList<GenericsTy>): Unit {
        for (tyVar in tyVars) {
            for (candidate in unsolved) {
                if (Ptr<GenericsTy>(tyVar) == Ptr<GenericsTy>(candidate)) {
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

// C++ TypeManager.h:510-537 OverrideOrShadowKey and its pointer-tuple equality.
private struct OverrideOrShadowKey <: Comparable<OverrideOrShadowKey> & Equatable<OverrideOrShadowKey> {
    private let src: Int64
    private let target: Int64
    private let baseTy: Int64
    private let expectInstParent: Int64

    public init(s: FuncDecl, t: FuncDecl, b: Option<Ty>, e: Option<Ty>) {
        src = s.objectId
        target = t.objectId
        baseTy = match (b) {
            case Some(value) => value.objectId
            case None => 0
        }
        expectInstParent = match (e) {
            case Some(value) => value.objectId
            case None => 0
        }
    }

    public operator func ==(right: OverrideOrShadowKey): Bool {
        return src == right.src && target == right.target && baseTy == right.baseTy &&
            expectInstParent == right.expectInstParent
    }

    public operator func !=(right: OverrideOrShadowKey): Bool {
        return !(this == right)
    }

    public func compare(right: OverrideOrShadowKey): Ordering {
        if (src != right.src) {
            return src.compare(right.src)
        }
        if (target != right.target) {
            return target.compare(right.target)
        }
        if (baseTy != right.baseTy) {
            return baseTy.compare(right.baseTy)
        }
        return expectInstParent.compare(right.expectInstParent)
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

private class DeclInstantiationStatusEntry {
    public var decl: Decl
    public let typeArgs: ArrayList<Ty> = ArrayList<Ty>()
    public var value: Bool

    public init(decl: Decl, typeArgs: ArrayList<Ty>, value: Bool) {
        this.decl = decl
        for (ty in typeArgs) {
            this.typeArgs.add(ty)
        }
        this.value = value
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
    private static let theInvalidTy: InvalidTy = InvalidTy()
    private static let theAnyTy: AnyTy = AnyTy()
    private static let theQuestTy: QuestTy = QuestTy()
    private static let theCStringTy: CStringTy = CStringTy()
    private static let primitiveTys: Array<PrimitiveTy> = [
        PrimitiveTy(TypeKind.TYPE_UNIT),
        PrimitiveTy(TypeKind.TYPE_INT8),
        PrimitiveTy(TypeKind.TYPE_INT16),
        PrimitiveTy(TypeKind.TYPE_INT32),
        PrimitiveTy(TypeKind.TYPE_INT64),
        PrimitiveTy(TypeKind.TYPE_INT_NATIVE),
        PrimitiveTy(TypeKind.TYPE_IDEAL_INT),
        PrimitiveTy(TypeKind.TYPE_UINT8),
        PrimitiveTy(TypeKind.TYPE_UINT16),
        PrimitiveTy(TypeKind.TYPE_UINT32),
        PrimitiveTy(TypeKind.TYPE_UINT64),
        PrimitiveTy(TypeKind.TYPE_UINT_NATIVE),
        PrimitiveTy(TypeKind.TYPE_FLOAT16),
        PrimitiveTy(TypeKind.TYPE_FLOAT32),
        PrimitiveTy(TypeKind.TYPE_FLOAT64),
        PrimitiveTy(TypeKind.TYPE_IDEAL_FLOAT),
        PrimitiveTy(TypeKind.TYPE_RUNE),
        NothingTy(),
        PrimitiveTy(TypeKind.TYPE_BOOLEAN),
    ]

    public let constraints: Constraint = Constraint()
    public let builtinTyToExtendMap: ArrayList<TyExtendsEntry> = ArrayList<TyExtendsEntry>()
    public let declToExtendMap: ArrayList<DeclExtendsEntry> = ArrayList<DeclExtendsEntry>()

    private var anyTy: Ty = theAnyTy
    private var ctypeTy: Option<Ty> = None
    private let overrideCache: TreeMap<OverrideOrShadowKey, Bool> = TreeMap<OverrideOrShadowKey, Bool>()
    private let topOverrideMap: ArrayList<TopOverrideEntry> = ArrayList<TopOverrideEntry>()
    private let boxUsedExtends: ArrayList<ExtendDecl> = ArrayList<ExtendDecl>()
    private let boxedNonGenericDecls: ArrayList<InheritableDecl> = ArrayList<InheritableDecl>()
    private let boxedTys: ArrayList<Ty> = ArrayList<Ty>()
    private let tyUsedExtends: ArrayList<TyUsedExtendsEntry> = ArrayList<TyUsedExtendsEntry>()
    private let checkedTyExtendRelation: ArrayList<CheckedTyExtendRelation> = ArrayList<CheckedTyExtendRelation>()
    private let tyExtendInterfaceTyMap: HashMap<Int64, TySet> = HashMap<Int64, TySet>()
    private let tyToSuperTysMap: HashMap<String, TySet> = HashMap<String, TySet>()
    private let subtypeCache: HashMap<Int64, HashMap<Int64, HashMap<Int64, Bool>>> =
        HashMap<Int64, HashMap<Int64, HashMap<Int64, Bool>>>()
    private let declInstantiationStatus: ArrayList<DeclInstantiationStatusEntry> =
        ArrayList<DeclInstantiationStatusEntry>()
    private let allocatedTyCache: HashMap<String, Ty> = HashMap<String, Ty>()
    private var allocatedTyConstructionTraces: Option<HashMap<Int64, String>> = None
    private let allocatedClassLikeTys: ArrayList<Ty> = ArrayList<Ty>()
    private var validateTypeManagerInterning: Bool = false
    private let unsolvedTyVars: ArrayList<GenericsTy> = ArrayList<GenericsTy>()
    private let tyVarScopes: ArrayList<TyVarScope> = ArrayList<TyVarScope>()
    private let declToExtendIndex: HashMap<Int64, DeclExtendsEntry> = HashMap<Int64, DeclExtendsEntry>()
    private let tyVarScopeDepth: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let instCtxScopes: ArrayList<InstCtxScope> = ArrayList<InstCtxScope>()
    private var nextUniqId: UInt64 = 0u64
    private let resolvedImportedDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    private let declToTypeAlias: HashMap<Int64, HashSet<String>> = HashMap<Int64, HashSet<String>>()
    public var compileTestsOnly: Bool = false

    public init() {
        tyVarScopes.add(TyVarScope())
        if (let Some(value) <- getVariable("CJC_VALIDATE_TY_INTERNING")) {
            validateTypeManagerInterning = value == "1"
            if (validateTypeManagerInterning) {
                allocatedTyConstructionTraces = Some(HashMap<Int64, String>())
            }
        }
    }

    public func AddResolvedImportedDecls(fileHash: UInt64, name: String, decls: ArrayList<Decl>): Unit {
        if (!resolvedImportedDeclsMap.contains(fileHash)) {
            resolvedImportedDeclsMap[fileHash] = HashMap<String, ArrayList<Decl>>()
        }
        if (let Some(fileMap) <- resolvedImportedDeclsMap.get(fileHash)) {
            if (!fileMap.contains(name)) {
                fileMap[name] = ArrayList<Decl>()
            }
            if (let Some(values) <- fileMap.get(name)) {
                for (decl in decls) {
                    var found = false
                    for (value in values) {
                        if (SameDecl(value, decl)) {
                            found = true
                            break
                        }
                    }
                    if (!found) {
                        var idx: Int64 = 0
                        while (idx < values.size) {
                            if (CompNodeByPos(decl, values[idx])) {
                                values.add(decl, at: idx)
                                break
                            }
                            idx++
                        }
                        if (idx < values.size) {
                            RecordTypeAlias(decl, name)
                            continue
                        }
                        values.add(decl)
                    }
                    RecordTypeAlias(decl, name)
                }
            }
        }
    }

    private func CompNodeByPos(left: Decl, right: Decl): Bool {
        return left.begin.fileID < right.begin.fileID ||
            (left.begin.fileID == right.begin.fileID && left.begin < right.begin) ||
            (left.begin.fileID == right.begin.fileID && left.begin == right.begin && left.objectId < right.objectId)
    }

    private func RecordTypeAlias(decl: Decl, alias: String): Unit {
        let key = DeclAliasKey(decl)
        if (!declToTypeAlias.contains(key)) {
            declToTypeAlias[key] = HashSet<String>()
        }
        if (let Some(values) <- declToTypeAlias.get(key)) {
            values.add(alias)
            // Mirror C++ ImportManager.cpp:1146-1148: when the imported name differs from the
            // decl's own identifier, record BOTH so cross-package extend-member visibility
            // (IsDeclAccessible's type-alias fallback) can resolve via the decl's real name.
            let ident = decl.identifier.Val()
            if (ident != alias) {
                values.add(ident)
            }
        }
    }

    private func DeclAliasKey(decl: Decl): Int64 {
        return decl.objectId
    }

    public static func GetPrimitiveTy(kind: TypeKind): PrimitiveTy {
        let validParam = TypeKindIndex(kind) >= TypeKindIndex(TypeKind.TYPE_UNIT) &&
            TypeKindIndex(kind) <= TypeKindIndex(TypeKind.TYPE_BOOLEAN)
        CJC_ASSERT(validParam)
        let index = if (validParam) { TypeKindIndex(kind) - TypeKindIndex(TypeKind.TYPE_UNIT) } else { 0 }
        CJC_ASSERT(index < primitiveTys.size)
        return primitiveTys[index]
    }

    public static func GetInvalidTy(): InvalidTy {
        return theInvalidTy
    }

    public static func GetNothingTy(): PrimitiveTy {
        return GetPrimitiveTy(TypeKind.TYPE_NOTHING)
    }

    public static func GetQuestTy(): QuestTy {
        return theQuestTy
    }

    public static func GetCStringTy(): CStringTy {
        return theCStringTy
    }

    public static func GetBoolTy(): PrimitiveTy {
        return GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
    }

    public static func GetNonNullTy(ty: Ty): Ty {
        if (Ty.IsInitialTy(Some(ty))) {
            return GetInvalidTy()
        }
        return ty
    }

    public static func IsCoreFutureType(ty: Ty): Bool {
        if (!ty.IsClass()) {
            return false
        }
        if (let Some(declPtr) <- Ty.GetDeclPtrOfTy(Some(ty))) {
            return declPtr.identifier == FUTURE_TYPE_NAME && declPtr.fullPackageName == "std.core" &&
                ty.typeArgs.size == 1
        }
        return false
    }

    public func GetGenericsTy(gpd: GenericParamDecl): GenericsTy {
        let raw = gpd.identifier.Val()
        let name = if (raw.isEmpty()) { "T" } else { raw }
        let ty = GenericsTy(name, gpd)
        return (internAllocatedTy(ty) as GenericsTy).getOrThrow()
    }

    public func GetEnumTy(ed: EnumDecl, typeArgs!: Array<Ty> = Array<Ty>()): EnumTy {
        let ty = EnumTy(declName(ed), ed, typeArgs)
        return (internAllocatedTy(ty) as EnumTy).getOrThrow()
    }

    public func GetRefEnumTy(ed: EnumDecl, typeArgs: Array<Ty>): RefEnumTy {
        let ty = RefEnumTy(declName(ed), ed, typeArgs)
        return (internAllocatedTy(ty) as RefEnumTy).getOrThrow()
    }

    public func GetStructTy(sd: StructDecl, typeArgs: Array<Ty>): StructTy {
        let ty = StructTy(declName(sd), sd, typeArgs)
        return (internAllocatedTy(ty, classLike: true) as StructTy).getOrThrow()
    }

    public func GetTupleTy(typeArgs: Array<Ty>, isClosureTy!: Bool = false): TupleTy {
        let ty = TupleTy(typeArgs, isClosureTy: isClosureTy)
        return (internAllocatedTy(ty) as TupleTy).getOrThrow()
    }

    public func GetFunctionTy(paramTys: Array<Ty>, retTy: Ty, cfg!: FuncTyConfig = FuncTyConfig()): FuncTy {
        let ty = FuncTy(paramTys, retTy, cfg: cfg)
        return (internAllocatedTy(ty) as FuncTy).getOrThrow()
    }

    public func GetArrayTy(elemTy: Ty, dims: UInt64): ArrayTy {
        var realElemTy = elemTy
        var realDims = dims
        if (Ty.IsTyCorrect(elemTy)) {
            if (let Some(arrayTy) <- (elemTy as ArrayTy)) {
                if (!arrayTy.typeArgs.isEmpty()) {
                    realElemTy = arrayTy.typeArgs[0]
                    realDims += arrayTy.dims
                }
            }
        } else {
            realElemTy = GetInvalidTy()
        }
        let ty = ArrayTy(realElemTy, realDims)
        return (internAllocatedTy(ty) as ArrayTy).getOrThrow()
    }

    public func GetVArrayTy(elemTy: Ty, size: Int64): VArrayTy {
        let ty = VArrayTy(elemTy, size)
        return (internAllocatedTy(ty) as VArrayTy).getOrThrow()
    }

    public func GetPointerTy(elemTy: Ty): PointerTy {
        let realElemTy = if (Ty.IsTyCorrect(elemTy)) { elemTy } else { GetInvalidTy() }
        let ty = PointerTy(realElemTy)
        return (internAllocatedTy(ty) as PointerTy).getOrThrow()
    }

    public func GetArrayTy(): ArrayTy {
        return GetArrayTy(GetInvalidTy(), 1u64)
    }

    public func GetClassTy(cd: ClassDecl, typeArgs: Array<Ty>): ClassTy {
        let ty = ClassTy(declName(cd), cd, typeArgs)
        return (internAllocatedTy(ty, classLike: true) as ClassTy).getOrThrow()
    }

    public func GetClassThisTy(cd: ClassDecl, typeArgs: Array<Ty>): ClassThisTy {
        let ty = ClassThisTy(declName(cd), cd, typeArgs)
        return (internAllocatedTy(ty, classLike: true) as ClassThisTy).getOrThrow()
    }

    public func GetInterfaceTy(id: InterfaceDecl, typeArgs: Array<Ty>): InterfaceTy {
        let ty = InterfaceTy(declName(id), id, typeArgs)
        return (internAllocatedTy(ty, classLike: true) as InterfaceTy).getOrThrow()
    }

    public func GetTypeAliasTy(tad: TypeAliasDecl, typeArgs: Array<Ty>): TypeAliasTy {
        let ty = TypeAliasTy(declName(tad), tad, typeArgs)
        return (internAllocatedTy(ty) as TypeAliasTy).getOrThrow()
    }

    public func GetIntersectionTy(tys: Array<Ty>): Ty {
        if (tys.size == 0) {
            return GetInvalidTy()
        }
        if (tys.size == 1) {
            return tys[0]
        }
        let ty = IntersectionTy(tys)
        return internAllocatedTy(ty)
    }

    public func GetUnionTy(tys: Array<Ty>): Ty {
        if (tys.size == 0) {
            return GetInvalidTy()
        }
        if (tys.size == 1) {
            return tys[0]
        }
        let ty = UnionTy(tys)
        return internAllocatedTy(ty)
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

    private func internAllocatedTy(ty: Ty, classLike!: Bool = false): Ty {
        let key = typeManagerTyKey(ty)
        if (let Some(cached) <- allocatedTyCache.get(key)) {
            return cached
        }
        allocatedTyCache[key] = ty
        if (validateTypeManagerInterning && ty.Hash() % 16 == 0) {
            if (let Some(traces) <- allocatedTyConstructionTraces) {
                traces[ty.objectId] = ThreadSnapshot.dumpCurrentThread().toString()
            }
        }
        if (classLike) {
            allocatedClassLikeTys.add(ty)
        }
        return ty
    }

    private func ValidateTypeManagerInterning(): Bool {
        let tysByHash = HashMap<Int64, ArrayList<Ty>>()
        var sampled: Int64 = 0
        var violations: Int64 = 0
        for ((_, ty) in allocatedTyCache) {
            let hash = ty.Hash()
            if (hash % 16 != 0) {
                continue
            }
            sampled++
            if (let Some(tys) <- tysByHash.get(hash)) {
                for (other in tys) {
                    if (ty == other && ty.objectId != other.objectId) {
                        violations++
                        eprintln("TY-INTERN-VIOLATION hash=${hash} left=${other.objectId} right=${ty.objectId}")
                        eprintln("TY-INTERN-LEFT ${other.String()}")
                        if (let Some(traces) <- allocatedTyConstructionTraces) {
                            if (let Some(trace) <- traces.get(other.objectId)) {
                                eprintln(trace)
                            }
                        }
                        eprintln("TY-INTERN-RIGHT ${ty.String()}")
                        if (let Some(traces) <- allocatedTyConstructionTraces) {
                            if (let Some(trace) <- traces.get(ty.objectId)) {
                                eprintln(trace)
                            }
                        }
                    }
                }
                tys.add(ty)
            } else {
                tysByHash[hash] = ArrayList<Ty>([ty])
            }
        }
        eprintln("TY-INTERN-VALIDATION TOTAL=${allocatedTyCache.size} SAMPLED=${sampled} " +
            "VIOLATIONS=${violations}")
        return violations == 0
    }

    public func GetInstantiatedTys(ty: Ty, mts: MultiTypeSubst): TySet {
        if (mts.entries.isEmpty()) {
            return TySet([ty])
        }
        let usefulTys = TySet([ty])
        let reduced = ReduceMultiTypeSubst(this, GetAllGenericTys(ty), mts)
        let mappings = ExpandMultiTypeSubst(reduced, usefulTys)
        let res = TySet()
        for (mapping in mappings) {
            res.Add(GetInstantiatedTy(ty, mapping))
        }
        if (res.values.size > 1) {
            let _ = res.Remove(ty)
        }
        return res
    }

    public func GetBestInstantiatedTy(ty: Ty, mts: MultiTypeSubst): Ty {
        if (mts.entries.isEmpty()) {
            return ty
        }
        if (!Ty.IsTyCorrect(ty)) {
            return TypeManager.GetInvalidTy()
        }
        let instTys = GetInstantiatedTys(ty, mts)
        if (instTys.IsEmpty()) {
            return ty
        }
        return instTys.values[0]
    }

    public func GetInstantiatedTy(ty: Ty, typeMapping: TypeSubst): Ty {
        if (typeMapping.IsEmpty() || !Ty.IsTyCorrect(ty)) {
            return ty
        }
        if (let Some(gen) <- (ty as GenericsTy)) {
            return getInstantiatedGenericTy(gen, typeMapping)
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
        for ((tyVar, ty) in maps.u2i.entries) {
            if (let Some(instTv) <- (ty as GenericsTy)) {
                if (let Some(_) <- maps.inst.Get(instTv)) {
                    out.Put(tyVar.value, ty)
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
        for ((tyVar, ty) in mapping.u2i.entries) {
            if (let Some(instTv) <- (ty as GenericsTy)) {
                i2uMap.Put(instTv, tyVar.value)
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
        for ((tyVar, tys) in m.entries) {
            if (tyVar.value.isPlaceholder) {
                for (ty in tys) {
                    if (ty != Ptr<Ty>(tyVar.value)) {
                        maps.inst.Put(tyVar.value, ty.value)
                    }
                }
            } else if (!tys.isEmpty()) {
                if (let Some(instTv) <- ensureInstTyVar(maps, tyVar.value)) {
                    for (ty in tys) {
                        maps.inst.Put(instTv, ty.value)
                    }
                }
            }
        }
    }

    public func PackMapping(maps: SubstPack, m: TypeSubst): Unit {
        for ((tyVar, ty) in m.entries) {
            if (tyVar.value.isPlaceholder) {
                if (!SameTy(tyVar.value, ty)) {
                    maps.inst.Put(tyVar.value, ty)
                }
            } else {
                if (let Some(instTv) <- ensureInstTyVar(maps, tyVar.value)) {
                    maps.inst.Put(instTv, ty)
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
        for ((tyVar, ty) in mapping.u2i.entries) {
            if (let Some(instVar) <- (ty as GenericsTy)) {
                if (let Some(instSet) <- mapping.inst.Get(instVar)) {
                    for (instTy in instSet) {
                        out.Put(tyVar.value, instTy.value)
                    }
                } else {
                    out.Put(tyVar.value, ty)
                }
            } else {
                out.Put(tyVar.value, ty)
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
        if (let Some(arrayTy) <- (ty as ArrayTy)) {
            if (arrayTy.dims == 1u64) {
                for (arg in arrayTy.typeArgs) {
                    out.add(arg)
                }
                return out
            }
            if (!arrayTy.typeArgs.isEmpty() && arrayTy.dims > 1u64) {
                out.add(GetArrayTy(arrayTy.typeArgs[0], arrayTy.dims - 1u64))
                return out
            }
        }
        for (arg in ty.typeArgs) {
            out.add(arg)
        }
        return out
    }

    public func GetBlockRealTy(block: Block): Ty {
        if (let Some(desugar) <- block.desugarExpr) {
            if (let Some(desugarTy) <- desugar.GetTy()) {
                return desugarTy
            }
            return GetInvalidTy()
        }
        if (block.body.isEmpty()) {
            return GetPrimitiveTy(TypeKind.TYPE_UNIT)
        }
        let lastNode = block.body[block.body.size - 1]
        if (lastNode.IsDecl()) {
            return GetPrimitiveTy(TypeKind.TYPE_UNIT)
        }
        if (let Some(expr) <- (lastNode as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                if (let Some(desugarTy) <- desugar.GetTy()) {
                    return desugarTy
                }
                return GetInvalidTy()
            }
            if (let Some(exprTy) <- expr.GetTy()) {
                return exprTy
            }
            return GetInvalidTy()
        }
        if (let Some(ty) <- block.GetTy()) {
            return ty
        }
        return GetInvalidTy()
    }

    public func GetRealExtendedTy(child: Ty, interfaceTy: Ty): Ty {
        if (interfaceTy.IsInterface() && child.IsClass() && !isTyExtendInterface(child, interfaceTy)) {
            if (let Some(superTy) <- getExtendInterfaceSuperTy(child, interfaceTy)) {
                return superTy
            }
        }
        return child
    }

    public func GetAllSuperTys(ty: Ty, typeMapping!: TypeSubst = TypeSubst(), withExtended!: Bool = true): TySet {
        let out = TySet()
        if (!Ty.IsTyCorrect(ty)) {
            return out
        }
        let cacheKey = superTysCacheKey(ty, typeMapping, withExtended)
        if (let Some(cached) <- tyToSuperTysMap.get(cacheKey)) {
            return cached.Clone()
        }
        let maybeInstTy = if (typeMapping.IsEmpty()) { ty } else { GetInstantiatedTy(ty, typeMapping) }
        if (maybeInstTy.IsClassLike() || maybeInstTy.IsStruct()) {
            out.Add(maybeInstTy)
        } else if (let Some(genTy) <- (maybeInstTy as GenericsTy)) {
            out.AddAll(collectAllUpperBounds(genTy))
            out.Add(genTy)
        } else if (let Some(intersectionTy) <- (maybeInstTy as IntersectionTy)) {
            for (item in intersectionTy.tys) {
                out.AddAll(GetAllSuperTys(item, typeMapping: typeMapping, withExtended: withExtended))
            }
            out.Add(intersectionTy)
        }
        if (ty.IsNominal()) {
            collectNominalSuperTys(ty, typeMapping, withExtended, out)
        }
        if (withExtended) {
            for (extendInterfaceTy in GetAllExtendInterfaceTy(ty).values) {
                out.Add(GetInstantiatedTy(extendInterfaceTy, typeMapping))
            }
        }
        if (!ty.HasPlaceholder()) {
            tyToSuperTysMap[cacheKey] = out.Clone()
        }
        return out
    }

    public func HasSuperTy(ty: Ty, superTy: Ty, typeMapping: TypeSubst, withExtended!: Bool = true): Bool {
        if (!Ty.IsTyCorrect(ty) || !Ty.IsTyCorrect(superTy)) {
            return false
        }
        let maybeInstTy = if (typeMapping.IsEmpty()) { ty } else { GetInstantiatedTy(ty, typeMapping) }
        if (SameTy(maybeInstTy, superTy)) {
            return true
        }
        if (let Some(genTy) <- (maybeInstTy as GenericsTy)) {
            if (collectAllUpperBounds(genTy).Contains(superTy)) {
                return true
            }
        } else if (let Some(intersectionTy) <- (maybeInstTy as IntersectionTy)) {
            for (item in intersectionTy.tys) {
                if (HasSuperTy(item, superTy, typeMapping, withExtended: withExtended)) {
                    return true
                }
            }
        }
        if (ty.IsNominal() && hasNominalSuperTy(ty, superTy, typeMapping, withExtended)) {
            return true
        }
        return withExtended && HasExtendedInterfaceTy(ty, superTy, typeMapping)
    }

    public func GetAllCommonSuperTys(tys: TySet): TySet {
        if (tys.values.isEmpty()) {
            return TySet()
        }
        var supers = GetAllSuperTys(tys.values[0])
        let firstWithSelf = tys.values[0]
        if (Ty.IsTyCorrect(firstWithSelf)) {
            supers.Add(firstWithSelf)
        }
        for (ty in tys.values) {
            let supersCur = TySet()
            if (Ty.IsTyCorrect(ty)) {
                supersCur.AddAll(GetAllSuperTys(ty))
                supersCur.Add(ty)
            }
            let supersNext = TySet()
            for (candidate in supersCur.values) {
                if (supers.Contains(candidate)) {
                    supersNext.Add(candidate)
                }
            }
            supers = supersNext
        }
        return supers
    }

    private func getResolvedImportedDeclsByName(file: File, name: String): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(fileMap) <- resolvedImportedDeclsMap.get(file.fileHash)) {
            if (let Some(decls) <- fileMap.get(name)) {
                for (decl in decls) {
                    out.add(decl)
                }
            }
        }
        return out
    }

    private func containsDecl(values: ArrayList<Decl>, decl: Decl): Bool {
        for (value in values) {
            if (SameDecl(value, decl)) {
                return true
            }
        }
        return false
    }

    private func isVisibleInRelation(node: Decl, relation: ModulesPackageRelation): Bool {
        return node.TestAttr(Attribute.PUBLIC) || relation == ModulesPackageRelation.SAME_PACKAGE ||
            (node.TestAttr(Attribute.PROTECTED) && relation != ModulesPackageRelation.NONE) ||
            (node.TestAttr(Attribute.INTERNAL) &&
                (relation == ModulesPackageRelation.CHILD || relation == ModulesPackageRelation.SAME_PACKAGE))
    }

    public func IsDeclAccessible(file: File, decl: Decl): Bool {
        var ret = false
        var relation = ModulesPackageRelation.NONE
        if (let Some(filePackage) <- file.curPackage) {
            ret = decl.fullPackageName == filePackage.fullPackageName
            relation = ModulesGetPackageRelation(filePackage.fullPackageName, decl.fullPackageName)
        }
        if (containsDecl(getResolvedImportedDeclsByName(file, decl.identifier.Val()), decl)) {
            return true
        }
        let packageNames = ModulesSplitQualifiedName(decl.fullPackageName)
        var idx = packageNames.size - 1
        while (idx >= 0) {
            if (!getResolvedImportedDeclsByName(file, packageNames[idx]).isEmpty() &&
                isVisibleInRelation(decl, relation)) {
                ret = true
            }
            idx--
        }
        if (let Some(aliases) <- declToTypeAlias.get(DeclAliasKey(decl))) {
            for (aliasName in aliases) {
                if (!getResolvedImportedDeclsByName(file, aliasName).isEmpty()) {
                    ret = true
                }
            }
        }
        return ret
    }

    public func GetSubstituteMapping(nominalTy: Ty, typeMapping: TypeSubst): TypeSubst {
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(nominalTy))) {
            let substituteMapping = GenerateTypeMapping(decl, nominalTy.typeArgs)
            for ((tyVar, ty) in substituteMapping.entries) {
                substituteMapping.entries[tyVar] = GetInstantiatedTy(ty, typeMapping)
            }
            return substituteMapping
        }
        return TypeSubst()
    }

    public func GetAllSuperInterfaceTysBFS(decl: InheritableDecl): ArrayList<InterfaceTy> {
        let out = ArrayList<InterfaceTy>()
        let queue = ArrayList<InterfaceTy>()
        let mappings = ArrayList<TypeSubst>()
        for (ty in decl.GetSuperInterfaceTys()) {
            queue.add(ty)
            mappings.add(GetSubstituteMapping(ty, TypeSubst()))
        }
        var index: Int64 = 0
        while (index < queue.size) {
            let item = queue[index]
            let itemMapping = mappings[index]
            index++
            if (!containsInterface(out, item)) {
                out.add(item)
                if (let Some(interfaceDecl) <- item.declPtr) {
                    for (parentType in interfaceDecl.inheritedTypes) {
                        if (let Some(parentTy) <- parentType.GetTy()) {
                            if (let Some(parentInterfaceTy) <- (parentTy as InterfaceTy)) {
                                let parentMapping = GetSubstituteMapping(parentInterfaceTy, itemMapping)
                                if (let Some(instParent) <- (GetInstantiatedTy(parentInterfaceTy, itemMapping) as InterfaceTy)) {
                                    queue.add(instParent)
                                    mappings.add(parentMapping)
                                }
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    public func IsSubtype(leaf: Ty, root: Ty, implicitBoxed!: Bool = true, allowOptionBox!: Bool = true): Bool {
        if (!Ty.IsTyCorrect(leaf) || !Ty.IsTyCorrect(root)) {
            return false
        }
        if (leaf.IsQuest() || root.IsQuest()) {
            return true
        }
        let ffiFastCheck = Ty.IsMetCType(leaf) && root.IsCType()
        let fastCheck = ffiFastCheck || SameTy(leaf, root) || (leaf.IsNothing() && !root.IsPlaceholder()) ||
            ((implicitBoxed || leaf.IsClassLike()) && root.IsAny() && !leaf.IsPlaceholder())
        if (fastCheck) {
            return true
        }
        if (root.IsNothing()) {
            return false
        }
        if (let Some(cached) <- getSubtypeCache(leaf, root, implicitBoxed, allowOptionBox)) {
            return cached
        }
        addSubtypeCache(leaf, root, implicitBoxed, allowOptionBox, false)
        var result = false
        if (isCommonAndSpecificRelation(leaf, root)) {
            result = true
        } else if (isPlaceholderSubtype(leaf, root)) {
            result = true
        } else if (isGenericSubtype(leaf, root, implicitBoxed, allowOptionBox)) {
            result = true
        } else if (isClassLikeSubtype(leaf, root, implicitBoxed, allowOptionBox)) {
            result = true
        } else if (isPointerSubtype(leaf, root)) {
            result = true
        } else if (isStructOrEnumSubtype(leaf, root, implicitBoxed, allowOptionBox)) {
            result = true
        } else if (IsFuncSubtype(leaf, root)) {
            result = true
        } else if (IsTupleSubtype(leaf, root)) {
            result = true
        } else if (isArraySubtype(leaf, root)) {
            result = true
        } else if (isVArraySubtype(leaf, root)) {
            result = true
        } else if (isPrimitiveSubtype(leaf, root)) {
            result = true
        } else if (implicitBoxed && !leaf.IsGeneric() && root.IsInterface()) {
            if (GetAllExtendInterfaceTy(leaf).Contains(root)) {
                result = true
            } else if ((leaf.HasPlaceholder() || root.HasPlaceholder()) &&
                LocalTypeArgumentSynthesis.Unify(this, constraints, leaf, root)) {
                result = true
            }
        }
        setSubtypeCache(leaf, root, implicitBoxed, allowOptionBox, result)
        if (leaf.HasPlaceholder() || root.HasPlaceholder()) {
            removeSubtypeCache(leaf, root, implicitBoxed, allowOptionBox)
        }
        return result
    }

    public func IsFuncSubtype(leaf: Ty, root: Ty): Bool {
        if (let Some(leftFunc) <- (leaf as FuncTy)) {
            if (let Some(rightFunc) <- (root as FuncTy)) {
                if (IsFuncParametersSubtype(leftFunc, rightFunc)) {
                    let noCast = leftFunc.noCast || rightFunc.noCast
                    return IsSubtype(leftFunc.retTy, rightFunc.retTy, implicitBoxed: noCast)
                }
            }
        }
        return false
    }

    public func IsFuncParametersSubtype(leaf: FuncTy, root: FuncTy): Bool {
        if (leaf.paramTys.size != root.paramTys.size) {
            return false
        }
        let noCast = leaf.noCast || root.noCast
        for (idx in 0..leaf.paramTys.size) {
            if (!IsSubtype(root.paramTys[idx], leaf.paramTys[idx], implicitBoxed: noCast)) {
                return false
            }
        }
        return leaf.isC == root.isC && leaf.hasVariableLenArg == root.hasVariableLenArg
    }

    public func IsTupleSubtype(leaf: Ty, root: Ty): Bool {
        if (let Some(leftTuple) <- (leaf as TupleTy)) {
            if (let Some(rightTuple) <- (root as TupleTy)) {
                if (leftTuple.typeArgs.size != rightTuple.typeArgs.size) {
                    return false
                }
                for (idx in 0..leftTuple.typeArgs.size) {
                    if (!IsSubtype(leftTuple.typeArgs[idx], rightTuple.typeArgs[idx], implicitBoxed: false)) {
                        return false
                    }
                }
                return true
            }
        }
        return false
    }

    public func IsTyEqual(subTy: Ty, baseTy: Ty): Bool {
        try (cs = constraints.CommitScope()) {
            if (IsSubtype(subTy, baseTy, implicitBoxed: false, allowOptionBox: false) &&
                IsSubtype(baseTy, subTy, implicitBoxed: false, allowOptionBox: false)) {
                return true
            }
            constraints.Reset()
            return false
        }
        return false
    }

    public func IsPlaceholderEqual(leaf: Ty, root: Ty): Bool {
        return leaf.IsPlaceholder() && root.IsPlaceholder() && SameTy(leaf, root)
    }

    public func IsLitBoxableType(leaf: Ty, root: Ty): Bool {
        if (!Ty.IsTyCorrect(leaf) || !Ty.IsTyCorrect(root)) {
            return false
        }
        if (SameTy(leaf, root) || (root.IsInteger() && leaf.IsInteger()) ||
            (root.IsFloating() && leaf.IsFloating())) {
            return true
        }
        if (IsSubtype(leaf, root)) {
            return true
        }
        if (root.IsCoreOptionType() && root.typeArgs.size == 1) {
            return IsLitBoxableType(leaf, root.typeArgs[0])
        }
        return false
    }

    public func HasExtensionRelation(childTy: Ty, interfaceTy: Ty): Bool {
        if (!Ty.IsTyCorrect(childTy) || !Ty.IsTyCorrect(interfaceTy)) {
            return false
        }
        let validRelation = childTy.kind != TypeKind.TYPE_INTERFACE && childTy.kind != TypeKind.TYPE_NOTHING &&
            interfaceTy.kind == TypeKind.TYPE_INTERFACE
        if (!validRelation) {
            return false
        }
        if (interfaceTy.IsAny()) {
            return true
        }
        if (!childTy.IsClass()) {
            return GetAllSuperTys(childTy, typeMapping: TypeSubst(), withExtended: true).Contains(interfaceTy)
        }
        return GetAllExtendInterfaceTy(childTy).Contains(interfaceTy)
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
        if (!Ty.IsTyCorrect(lvalue) || !Ty.IsTyCorrect(rvalue)) {
            return TypeCompatibility.INCOMPATIBLE
        }
        if (SameTy(lvalue, rvalue) || isCommonAndSpecificRelation(lvalue, rvalue)) {
            return TypeCompatibility.IDENTICAL
        }
        if (IsSubtype(rvalue, lvalue, implicitBoxed: implicitBoxed)) {
            return TypeCompatibility.SUBTYPE
        }
        if (isGeneric && checkGenericType(lvalue, rvalue, implicitBoxed)) {
            return TypeCompatibility.IDENTICAL
        }
        if (lvalue.IsEnum() && rvalue.IsEnum()) {
            if (let Some(leftEnum) <- (lvalue as EnumTy)) {
                if (let Some(rightEnum) <- (rvalue as EnumTy)) {
                    if (isEnumCompatibleForSubtype(leftEnum, rightEnum, implicitBoxed)) {
                        return TypeCompatibility.IDENTICAL
                    }
                }
            }
        }
        return TypeCompatibility.INCOMPATIBLE
    }

    public func CheckGenericDeclInstantiation(d: Option<Decl>, typeArgs: ArrayList<Ty>): Bool {
        if (let Some(decl) <- d) {
            if (typeArgs.isEmpty()) {
                return true
            }
            let genericParamTys = GetDeclTypeParams(decl)
            if (let Some(genericDecl) <- decl.GetGeneric()) {
                for (constraint in genericDecl.genericConstraints) {
                    if (let None <- constraint.refType) {
                        return false
                    }
                }
            }
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
            if (let Some(value) <- getDeclInstantiationStatus(decl, typeArgs)) {
                return value
            }
            let instantiateMap = GenerateTypeMapping(decl, typeArgs)
            if (decl.astKind == ASTKind.EXTEND_DECL) {
                idx = 0
                while (idx < typeArgs.size) {
                    let instantiatedParam = GetInstantiatedTy(genericParamTys[idx], instantiateMap)
                    if (!SameTy(instantiatedParam, typeArgs[idx])) {
                        addDeclInstantiationStatus(decl, typeArgs, false)
                        return false
                    }
                    idx++
                }
            }
            let result = CheckGenericConstraints(decl, instantiateMap)
            addDeclInstantiationStatus(decl, typeArgs, result)
            return result
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

    private func typeManagerTyKey(ty: Ty): String {
        if (let Some(genericTy) <- (ty as GenericsTy)) {
            if (let Some(genericDecl) <- genericTy.decl) {
                return genericDecl.objectId.toString()
            }
            return genericTy.objectId.toString()
        }
        if (let Some(classThisTy) <- (ty as ClassThisTy)) {
            var out = "nominal:" + TypeKindIndex(TypeKind.TYPE_CLASS).toString() + ":1:" + classThisTy.name
            for (typeArg in classThisTy.typeArgs) {
                out += ":" + typeArg.objectId.toString()
            }
            if (let Some(decl) <- classThisTy.declPtr) {
                out += ":" + decl.objectId.toString()
            } else {
                out += ":0"
            }
            return out
        }
        if (let Some(classTy) <- (ty as ClassTy)) {
            var out = "nominal:" + TypeKindIndex(TypeKind.TYPE_CLASS).toString() + ":0:" + classTy.name
            for (typeArg in classTy.typeArgs) {
                out += ":" + typeArg.objectId.toString()
            }
            if (let Some(decl) <- classTy.declPtr) {
                out += ":" + decl.objectId.toString()
            } else {
                out += ":0"
            }
            return out
        }
        if (let Some(refEnumTy) <- (ty as RefEnumTy)) {
            var out = "nominal:" + TypeKindIndex(TypeKind.TYPE_ENUM).toString() + ":1:" + refEnumTy.name
            for (typeArg in refEnumTy.typeArgs) {
                out += ":" + typeArg.objectId.toString()
            }
            if (let Some(decl) <- refEnumTy.declPtr) {
                out += ":" + decl.objectId.toString()
            } else {
                out += ":0"
            }
            return out
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            var out = "nominal:" + TypeKindIndex(TypeKind.TYPE_ENUM).toString() + ":0:" + enumTy.name
            for (typeArg in enumTy.typeArgs) {
                out += ":" + typeArg.objectId.toString()
            }
            if (let Some(decl) <- enumTy.declPtr) {
                out += ":" + decl.objectId.toString()
            } else {
                out += ":0"
            }
            return out
        }
        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            var out = "nominal:" + TypeKindIndex(TypeKind.TYPE_INTERFACE).toString() + ":" + interfaceTy.name
            for (typeArg in interfaceTy.typeArgs) {
                out += ":" + typeArg.objectId.toString()
            }
            if (let Some(decl) <- interfaceTy.declPtr) {
                out += ":" + decl.objectId.toString()
            } else {
                out += ":0"
            }
            return out
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            var out = "nominal:" + TypeKindIndex(TypeKind.TYPE_STRUCT).toString() + ":" + structTy.name
            for (typeArg in structTy.typeArgs) {
                out += ":" + typeArg.objectId.toString()
            }
            if (let Some(decl) <- structTy.declPtr) {
                out += ":" + decl.objectId.toString()
            } else {
                out += ":0"
            }
            return out
        }
        if (let Some(typeAliasTy) <- (ty as TypeAliasTy)) {
            var out = "nominal:" + TypeKindIndex(TypeKind.TYPE).toString() + ":" + typeAliasTy.name
            for (typeArg in typeAliasTy.typeArgs) {
                out += ":" + typeArg.objectId.toString()
            }
            if (let Some(decl) <- typeAliasTy.declPtr) {
                out += ":" + decl.objectId.toString()
            } else {
                out += ":0"
            }
            return out
        }
        if (let Some(arrayTy) <- (ty as ArrayTy)) {
            var out = "compound:" + TypeKindIndex(TypeKind.TYPE_ARRAY).toString()
            if (!arrayTy.typeArgs.isEmpty()) {
                out += ":" + arrayTy.typeArgs[0].objectId.toString()
            } else {
                out += ":0"
            }
            return out + ":" + arrayTy.dims.toString()
        }
        if (let Some(varrayTy) <- (ty as VArrayTy)) {
            var out = "compound:" + TypeKindIndex(TypeKind.TYPE_VARRAY).toString()
            if (!varrayTy.typeArgs.isEmpty()) {
                out += ":" + varrayTy.typeArgs[0].objectId.toString()
            } else {
                out += ":0"
            }
            return out + ":" + varrayTy.size.toString()
        }
        if (let Some(pointerTy) <- (ty as PointerTy)) {
            var out = "compound:" + TypeKindIndex(TypeKind.TYPE_POINTER).toString()
            if (!pointerTy.typeArgs.isEmpty()) {
                out += ":" + pointerTy.typeArgs[0].objectId.toString()
            } else {
                out += ":0"
            }
            return out
        }
        if (let Some(tupleTy) <- (ty as TupleTy)) {
            var out = "compound:" + TypeKindIndex(TypeKind.TYPE_TUPLE).toString() + ":" + tupleTy.isClosureTy.toString()
            for (typeArg in tupleTy.typeArgs) {
                out += ":" + typeArg.objectId.toString()
            }
            return out
        }
        if (let Some(funcTy) <- (ty as FuncTy)) {
            var out = "compound:" + TypeKindIndex(TypeKind.TYPE_FUNC).toString() + ":" + funcTy.retTy.objectId.toString()
            for (paramTy in funcTy.paramTys) {
                out += ":" + paramTy.objectId.toString()
            }
            out += ":" + funcTy.isClosureTy.toString()
            out += ":" + funcTy.isC.toString()
            out += ":" + funcTy.hasVariableLenArg.toString()
            out += ":" + funcTy.noCast.toString()
            return out
        }
        if (let Some(unionTy) <- (ty as UnionTy)) {
            let memberIds = ArrayList<Int64>()
            for (memberTy in unionTy.tys) {
                memberIds.add(memberTy.objectId)
            }
            sort(memberIds, by: { left: Int64, right: Int64 =>
                if (left < right) {
                    Ordering.LT
                } else if (left > right) {
                    Ordering.GT
                } else {
                    Ordering.EQ
                }
            }, stable: true)
            var out = "union:" + TypeKindIndex(TypeKind.TYPE_UNION).toString()
            for (memberId in memberIds) {
                out += ":" + memberId.toString()
            }
            return out
        }
        if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
            let memberIds = ArrayList<Int64>()
            for (memberTy in intersectionTy.tys) {
                memberIds.add(memberTy.objectId)
            }
            sort(memberIds, by: { left: Int64, right: Int64 =>
                if (left < right) {
                    Ordering.LT
                } else if (left > right) {
                    Ordering.GT
                } else {
                    Ordering.EQ
                }
            }, stable: true)
            var out = "intersection:" + TypeKindIndex(TypeKind.TYPE_INTERSECTION).toString()
            for (memberId in memberIds) {
                out += ":" + memberId.toString()
            }
            return out
        }
        return ty.objectId.toString()
    }

    private func hasVisitedGenericMappingTy(visited: HashSet<Int64>, ty: Ty): Bool {
        return visited.contains(ty.objectId)
    }

    private func IsInheritableType(ty: Ty): Bool {
        if (!Ty.IsTyCorrect(ty) || !ty.IsClassLike()) {
            return false
        }
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(ty))) {
            return !decl.TestAttr(Attribute.IN_REFERENCE_CYCLE)
        }
        return false
    }

    private func generateGenericMappingVisit(m: MultiTypeSubst, baseType: Ty, visited: HashSet<Int64>): Unit {
        if (!Ty.IsTyCorrect(baseType) || hasVisitedGenericMappingTy(visited, baseType)) {
            return
        }
        visited.add(baseType.objectId)
        generateExtendGenericMappingVisit(m, baseType, visited)
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(baseType))) {
            generateStructDeclGenericMappingVisit(m, decl, baseType, visited)
        }
    }

    private func generateExtendGenericMappingVisit(m: MultiTypeSubst, baseType: Ty, visited: HashSet<Int64>): Unit {
        if (!Ty.IsTyCorrect(baseType)) {
            return
        }
        for (extendDecl in GetAllExtendsByTy(baseType)) {
            generateStructDeclGenericMappingVisit(m, extendDecl, baseType, visited)
        }
    }

    private func generateStructDeclGenericMappingVisit(m: MultiTypeSubst, decl: InheritableDecl, targetTy: Ty,
        visited: HashSet<Int64>): Unit {
        if (!Ty.IsTyCorrect(targetTy)) {
            return
        }
        generateDeclGenericMapping(m, decl, targetTy)
        for (inheritedType in decl.inheritedTypes) {
            if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                if (IsInheritableType(inheritedTy)) {
                    generateGenericMappingVisit(m, inheritedTy, visited)
                }
            }
        }
    }

    private func generateGenericMappingVisit(m: SubstPack, baseType: Ty, visited: HashSet<Int64>, contextual: Bool): Unit {
        if (!Ty.IsTyCorrect(baseType) || hasVisitedGenericMappingTy(visited, baseType)) {
            return
        }
        visited.add(baseType.objectId)
        generateExtendGenericMappingVisit(m, baseType, visited, contextual)
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(baseType))) {
            generateStructDeclGenericMappingVisit(m, decl, baseType, visited, contextual)
        }
    }

    private func generateExtendGenericMappingVisit(m: SubstPack, baseType: Ty, visited: HashSet<Int64>,
        contextual: Bool): Unit {
        if (!Ty.IsTyCorrect(baseType)) {
            return
        }
        for (extendDecl in GetAllExtendsByTy(baseType)) {
            generateStructDeclGenericMappingVisit(m, extendDecl, baseType, visited, contextual)
        }
    }

    private func generateStructDeclGenericMappingVisit(m: SubstPack, decl: InheritableDecl, targetTy: Ty,
        visited: HashSet<Int64>, contextual: Bool): Unit {
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
                if (IsInheritableType(inheritedTy)) {
                    generateGenericMappingVisit(m, inheritedTy, visited, false)
                }
            }
        }
    }

    public func GenerateStructDeclGenericMapping(m: MultiTypeSubst, decl: InheritableDecl, targetTy: Ty): Unit {
        let visited = HashSet<Int64>()
        generateStructDeclGenericMappingVisit(m, decl, targetTy, visited)
    }

    public func GenerateGenericMapping(m: MultiTypeSubst, baseType: Ty): Unit {
        let visited = HashSet<Int64>()
        generateGenericMappingVisit(m, baseType, visited)
    }

    public func GenerateGenericMapping(m: SubstPack, baseType: Ty): Unit {
        let visited = HashSet<Int64>()
        generateGenericMappingVisit(m, baseType, visited, true)
    }

    public func GenerateTypeMappingForUpperBounds(m: SubstPack, ma: MemberAccess, target: Decl): Unit {
        for ((foundTarget, upperBounds) in ma.foundUpperBoundMap) {
            if (foundTarget == target) {
                for (upperBound in upperBounds) {
                    GenerateGenericMapping(m, upperBound)
                }
                return
            }
        }
    }

    public func GenerateTypeMappingForUpperBounds(m: MultiTypeSubst, ma: MemberAccess, target: Decl): Unit {
        for ((foundTarget, upperBounds) in ma.foundUpperBoundMap) {
            if (foundTarget == target) {
                for (upperBound in upperBounds) {
                    GenerateGenericMapping(m, upperBound)
                }
                return
            }
        }
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
        if (!Ty.IsTyCorrect(ty)) {
            return ty
        }
        if (ty.kind == TypeKind.TYPE_IDEAL_INT) {
            return GetPrimitiveTy(TypeKind.TYPE_INT64)
        }
        if (ty.kind == TypeKind.TYPE_IDEAL_FLOAT) {
            return GetPrimitiveTy(TypeKind.TYPE_FLOAT64)
        }
        if (ty.kind == TypeKind.TYPE_CLASS || ty.kind == TypeKind.TYPE_INTERFACE ||
            ty.kind == TypeKind.TYPE_ENUM || ty.kind == TypeKind.TYPE_ARRAY ||
            ty.kind == TypeKind.TYPE_POINTER || ty.kind == TypeKind.TYPE_TUPLE) {
            var idx: Int64 = 0
            while (idx < ty.typeArgs.size) {
                ty.typeArgs[idx] = ReplaceIdealTy(ty.typeArgs[idx])
                idx++
            }
        }
        return ty
    }

    public func RestoreJavaGenericsTy(decl: Decl): Unit {
        if (!decl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            return
        }
        if (let None <- HasJavaAttr(decl)) {
            return
        }
        if (let Some(genericDecl) <- decl.genericDecl) {
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                for (ty in allocatedClassLikeTys) {
                    if (SameDeclOption(Ty.GetDeclPtrOfTy(ty), Some(genericDecl))) {
                        if (let Some(classTy) <- (ty as ClassTy)) {
                            classTy.declPtr = classDecl
                            classTy.decl = classDecl
                        }
                    }
                }
            } else if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
                for (ty in allocatedClassLikeTys) {
                    if (SameDeclOption(Ty.GetDeclPtrOfTy(ty), Some(genericDecl))) {
                        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
                            interfaceTy.declPtr = interfaceDecl
                            interfaceTy.decl = interfaceDecl
                        }
                    }
                }
            }
        }
    }

    public func GetAllExtendInterfaceTy(ty: Ty): TySet {
        if (!Ty.IsTyCorrect(ty)) {
            return TySet()
        }
        if (let Some(cached) <- tyExtendInterfaceTyMap.get(ty.objectId)) {
            return cached.Clone()
        }
        let out = getAllExtendInterfaceTyHelper(GetAllExtendsByTy(ty), GetTypeArgs(ty))
        if (ty.IsClass()) {
            let directSupers = GetAllSuperTys(ty, typeMapping: TypeSubst(), withExtended: false)
            for (superTy in directSupers.values) {
                if (SameTy(superTy, ty)) {
                    continue
                }
                if (let Some(classTy) <- (superTy as ClassTy)) {
                    if (let Some(classDecl) <- classTy.declPtr) {
                        out.AddAll(getAllExtendInterfaceTyHelper(GetDeclExtends(classDecl), GetTypeArgs(superTy)))
                    }
                }
            }
        }
        if (!ty.HasPlaceholder()) {
            tyExtendInterfaceTyMap[ty.objectId] = out.Clone()
        }
        return out
    }

    public func HasExtendedInterfaceTy(ty: Ty, superTy: Ty, typeMapping: TypeSubst): Bool {
        if (!Ty.IsTyCorrect(ty) || !Ty.IsTyCorrect(superTy)) {
            return false
        }
        if (HasExtendInterfaceTyHelper(superTy, GetAllExtendsByTy(ty), GetTypeArgs(ty))) {
            return true
        }
        if (ty.IsClass()) {
            if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(ty))) {
                let substituteMapping = GetSubstituteMapping(ty, typeMapping)
                for (inheritedType in decl.inheritedTypes) {
                    if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                        if (inheritedTy.IsClass() && IsInheritableType(inheritedTy)) {
                            return HasExtendedInterfaceTy(inheritedTy, superTy, substituteMapping)
                        }
                    }
                }
            }
        }
        return false
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
                return overrideCache.get(OverrideOrShadowKey(srcDecl, targetDecl, baseTy, expectInstParent))
            }
        }
        return None
    }

    public func AddOverrideCache(src: FuncDecl, target: FuncDecl, baseTy: Option<Ty>, expectInstParent: Option<Ty>,
        value: Bool): Unit {
        let key = OverrideOrShadowKey(src, target, baseTy, expectInstParent)
        if (!overrideCache.contains(key)) {
            overrideCache.add(key, value)
        }
    }

    public func AddDeclExtendsEntry(entry: DeclExtendsEntry): Unit {
        declToExtendMap.add(entry)
        declToExtendIndex[entry.decl.objectId] = entry
    }

    public func GetDeclExtends(decl: InheritableDecl): ArrayList<ExtendDecl> {
        if (let Some(entry) <- declToExtendIndex.get(decl.objectId)) {
            return entry.extends
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
        allocatedTyCache.clear()
        if (let Some(traces) <- allocatedTyConstructionTraces) {
            traces.clear()
        }
        allocatedClassLikeTys.clear()
        unsolvedTyVars.clear()
        subtypeCache.clear()
        declInstantiationStatus.clear()
    }

    public func ClearMapCache(): Unit {
        builtinTyToExtendMap.clear()
        declToExtendMap.clear()
        declToExtendIndex.clear()
        tyExtendInterfaceTyMap.clear()
        tyToSuperTysMap.clear()
        overrideCache.clear()
        declInstantiationStatus.clear()
        subtypeCache.clear()
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
        tyExtendInterfaceTyMap.clear()
        tyToSuperTysMap.clear()
        subtypeCache.clear()
        declInstantiationStatus.clear()
    }

    public func ReleasePostSemaCaches(): Unit {
        if (validateTypeManagerInterning) {
            let interningValid = ValidateTypeManagerInterning()
            if (!interningValid) {
                throw IllegalStateException("Ty interning invariant violation")
            }
        }
        ReleaseSemaQueryCaches()
        ClearRecordUsedExtends()
        boxedNonGenericDecls.clear()
    }

    public func GetOverrideDeclInClassLike(baseDecl: Decl, funcDecl: FuncDecl,
        withAbstractOverrides!: Bool = false): Option<Decl> {
        for (member in baseDecl.GetMemberDecls()) {
            if (member.astKind != ASTKind.FUNC_DECL && member.astKind != ASTKind.PROP_DECL) {
                continue
            }
            if ((!withAbstractOverrides && member.TestAttr(Attribute.ABSTRACT)) ||
                member.TestAttr(Attribute.GENERIC)) {
                continue
            }
            if (let Some(memberFunc) <- (member as FuncDecl)) {
                if (IsFuncDeclSubType(memberFunc, funcDecl)) {
                    return memberFunc
                }
            } else if (let Some(propDecl) <- (member as PropDecl)) {
                for (getter in propDecl.getters) {
                    if (IsFuncDeclSubType(getter, funcDecl)) {
                        return getter
                    }
                }
                for (setter in propDecl.setters) {
                    if (IsFuncDeclSubType(setter, funcDecl)) {
                        return setter
                    }
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
        if (decl.identifier != funcDecl.identifier) {
            return false
        }
        if (let Some(leftTy) <- decl.GetTy()) {
            if (let Some(leftFuncTy) <- (leftTy as FuncTy)) {
                if (let Some(rightTy) <- funcDecl.GetTy()) {
                    if (let Some(rightFuncTy) <- (rightTy as FuncTy)) {
                        return IsFuncTySubType(leftFuncTy, rightFuncTy)
                    }
                }
            }
        }
        return false
    }

    public func IsFuncTySubType(type1: FuncTy, type2: FuncTy): Bool {
        return IsFuncParameterTypesIdentical(type1.paramTys, type2.paramTys) &&
            IsSubtype(type1.retTy, type2.retTy)
    }

    public func IsFuncDeclEqualType(decl: FuncDecl, funcDecl: FuncDecl): Bool {
        return IsFuncDeclSubType(decl, funcDecl) && IsFuncDeclSubType(funcDecl, decl)
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
        if (child.astKind != parent.astKind || child.identifier != parent.identifier) {
            return false
        }
        if (let Some(childFunc) <- (child as FuncDecl)) {
            if (let Some(parentFunc) <- (parent as FuncDecl)) {
                return IsOverrideOrShadow(childFunc, parentFunc, baseTy, parentTy)
            }
        } else if (let Some(childProp) <- (child as PropDecl)) {
            if (let Some(parentProp) <- (parent as PropDecl)) {
                return IsOverrideOrShadow(childProp, parentProp, baseTy)
            }
        }
        return false
    }

    private func IsOverrideOrShadow(src: FuncDecl, target: FuncDecl, baseTy: Option<Ty>,
        expectInstParent: Option<Ty>): Bool {
        if (let Some(cached) <- GetOverrideCache(Some(src), Some(target), baseTy, expectInstParent)) {
            return cached
        }
        if (src.TestAttr(Attribute.STATIC) != target.TestAttr(Attribute.STATIC)) {
            return false
        }
        let srcFuncTy = GetFuncTyForOverride(src)
        let targetFuncTy = GetFuncTyForOverride(target)
        let mts = GenerateOverrideTypeMapping(src, target, expectInstParent)
        let usefulTys = CollectOverrideUsefulTys(srcFuncTy, targetFuncTy, src, target)
        for (typeMapping in ExpandMultiTypeSubst(mts, usefulTys)) {
            let srcParamTys = GetOverrideParamTys(src, srcFuncTy)
            let targetParamTys = GetOverrideParamTys(target, targetFuncTy)
            if (srcParamTys.size != targetParamTys.size) {
                AddOverrideCache(src, target, baseTy, expectInstParent, false)
                return false
            }
            AddInterfaceBaseMappingIfNeeded(typeMapping, src.outerDecl, target.outerDecl, baseTy)
            let instantiatedSrcParams = InstantiateTyList(srcParamTys, typeMapping)
            let instantiatedTargetParams = InstantiateTyList(targetParamTys, typeMapping)
            if (IsFuncParameterTypesIdentical(instantiatedSrcParams, instantiatedTargetParams)) {
                if (IsCrossPlatformPair(src, target)) {
                    continue
                }
                AddOverrideCache(src, target, baseTy, expectInstParent, true)
                return true
            }
        }
        AddOverrideCache(src, target, baseTy, expectInstParent, false)
        return false
    }

    private func IsOverrideOrShadow(src: PropDecl, target: PropDecl, baseTy: Option<Ty>): Bool {
        if (let None <- src.outerDecl) {
            return false
        }
        let outerDecl = src.outerDecl.getOrThrow()
        let mts = GenerateStructDeclTypeMapping(outerDecl)
        let typeMapping = MultiTypeSubstToTypeSubst(mts)
        AddInterfaceBaseMappingIfNeeded(typeMapping, src.outerDecl, target.outerDecl, baseTy)
        if (let Some(srcTy) <- GetPropOverrideTy(src)) {
            if (let Some(targetTy) <- GetPropOverrideTy(target)) {
                let ret = SameTy(srcTy, GetInstantiatedTy(targetTy, typeMapping))
                if (ret && SameDeclOption(src.outerDecl, GetDeclPtrOfOptionTy(baseTy)) &&
                    src.TestAttr(Attribute.STATIC) == target.TestAttr(Attribute.STATIC)) {
                    UpdateTopOverriddenFuncDeclMap(Some(src), Some(target))
                }
                return ret
            }
        }
        return false
    }

    private func GenerateOverrideTypeMapping(src: FuncDecl, target: FuncDecl,
        expectInstParent: Option<Ty>): MultiTypeSubst {
        let mts = MultiTypeSubst()
        if (let Some(parentTy) <- expectInstParent) {
            if (let Some(targetOuter) <- target.outerDecl) {
                MergeTypeSubstToMultiTypeSubst(mts, GenerateTypeMappingByTy(targetOuter.GetTy(), Some(parentTy)))
            }
            if (let Some(srcOuter) <- src.outerDecl) {
                if (let Some(targetOuter) <- target.outerDecl) {
                    if (let Some(srcOuterTy) <- srcOuter.GetTy()) {
                        if (let Some(targetOuterTy) <- targetOuter.GetTy()) {
                            for (promotedTy in Promotion(this).Promote(srcOuterTy, targetOuterTy).values) {
                                MergeTypeSubstToMultiTypeSubst(mts,
                                    GenerateTypeMappingByTy(Some(promotedTy), Some(parentTy)))
                            }
                        }
                    }
                }
            }
            if (target.TestAttr(Attribute.GENERIC) && src.TestAttr(Attribute.GENERIC)) {
                MergeTypeSubstToMultiTypeSubst(mts, GenerateGenericMappingFromGeneric(target, src))
            }
            return mts
        }
        if (let Some(srcOuter) <- src.outerDecl) {
            if (Ty.IsTyCorrect(srcOuter.GetTy())) {
                MergeMultiTypeSubsts(mts, GenerateStructDeclTypeMapping(srcOuter))
            }
        }
        if (target.TestAttr(Attribute.GENERIC) && src.TestAttr(Attribute.GENERIC)) {
            MergeTypeSubstToMultiTypeSubst(mts, GenerateGenericMappingFromGeneric(target, src))
        }
        return mts
    }

    private func AddInterfaceBaseMappingIfNeeded(typeMapping: TypeSubst, srcOuter: Option<Decl>,
        targetOuter: Option<Decl>, baseTy: Option<Ty>): Unit {
        if (let Some(base) <- baseTy) {
            if (!Ty.IsTyCorrect(base)) {
                return
            }
            if (let Some(srcOuterDecl) <- srcOuter) {
                if (let Some(targetOuterDecl) <- targetOuter) {
                    if ((let Some(_) <- (srcOuterDecl as InterfaceDecl)) &&
                        (let Some(_) <- (targetOuterDecl as InterfaceDecl))) {
                        if (let Some(targetOuterTy) <- targetOuterDecl.GetTy()) {
                            if (let Some(srcOuterTy) <- srcOuterDecl.GetTy()) {
                                let parentStructTy = GetInstantiatedTy(targetOuterTy, typeMapping)
                                let childStructTy = GetInstantiatedTy(srcOuterTy, typeMapping)
                                if (!IsSubtype(childStructTy, parentStructTy)) {
                                    let baseMapping = MultiTypeSubst()
                                    GenerateGenericMapping(baseMapping, base)
                                    mergeTypeSubst(typeMapping, MultiTypeSubstToTypeSubst(baseMapping))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func CollectOverrideUsefulTys(srcFuncTy: Option<FuncTy>, targetFuncTy: Option<FuncTy>,
        src: FuncDecl, target: FuncDecl): TySet {
        let usefulTys = TySet()
        if (let Some(srcTy) <- srcFuncTy) {
            usefulTys.Add(srcTy)
        } else {
            for (ty in GetParamTys(src)) {
                usefulTys.Add(ty)
            }
        }
        if (let Some(targetTy) <- targetFuncTy) {
            usefulTys.Add(targetTy)
        } else {
            for (ty in GetParamTys(target)) {
                usefulTys.Add(ty)
            }
        }
        return usefulTys
    }

    private func GetOverrideParamTys(fd: FuncDecl, funcTy: Option<FuncTy>): ArrayList<Ty> {
        if (let Some(value) <- funcTy) {
            return CopyTyList(value.paramTys)
        }
        return GetParamTys(fd)
    }

    private func GetFuncTyForOverride(fd: FuncDecl): Option<FuncTy> {
        if (let Some(ty) <- fd.GetTy()) {
            return ty as FuncTy
        }
        return None
    }

    private func GetPropOverrideTy(propDecl: PropDecl): Option<Ty> {
        if (let Some(typeNode) <- propDecl.typeNode) {
            if (let Some(ty) <- typeNode.GetTy()) {
                return ty
            }
        }
        return propDecl.GetTy()
    }

    private func InstantiateTyList(values: ArrayList<Ty>, typeMapping: TypeSubst): ArrayList<Ty> {
        let out = ArrayList<Ty>()
        for (ty in values) {
            out.add(GetInstantiatedTy(ty, typeMapping))
        }
        return out
    }

    private func CopyTyList(values: ArrayList<Ty>): ArrayList<Ty> {
        let out = ArrayList<Ty>()
        for (ty in values) {
            out.add(ty)
        }
        return out
    }

    private func IsCrossPlatformPair(src: Decl, target: Decl): Bool {
        return (src.TestAttr(Attribute.COMMON) && target.TestAttr(Attribute.SPECIFIC)) ||
            (src.TestAttr(Attribute.SPECIFIC) && target.TestAttr(Attribute.COMMON))
    }

    private func GetDeclPtrOfOptionTy(ty: Option<Ty>): Option<Decl> {
        if (let Some(value) <- ty) {
            return Ty.GetDeclPtrOfTy(value)
        }
        return None
    }

    private func SameDeclOption(left: Option<Decl>, right: Option<Decl>): Bool {
        if (let Some(leftDecl) <- left) {
            if (let Some(rightDecl) <- right) {
                return SameDecl(leftDecl, rightDecl)
            }
            return false
        }
        if (let Some(_) <- right) {
            return false
        }
        return true
    }

    public func ConstrainByCtor(tv: GenericsTy, tyCtor: Ty): Option<Ty> {
        let bounds = constraints.GetOrCreate(tv)
        for (upper in bounds.ubs.values) {
            if (OfSameCtor(upper, tyCtor)) {
                return upper
            }
        }
        let mapping = TypeSubst()
        for (tyArg in tyCtor.typeArgs) {
            if (let Some(ctorArg) <- (tyArg as GenericsTy)) {
                mapping.Put(ctorArg, AllocTyVar(srcId: "T-Fly", needSolving: true, derivedFrom: tv))
            } else {
                return None
            }
        }
        let placeholderTy = GetInstantiatedTy(tyCtor, mapping)
        if (IsSubtype(tv, placeholderTy, implicitBoxed: true, allowOptionBox: false)) {
            return placeholderTy
        }
        return None
    }

    public func AddSumByCtor(tv: GenericsTy, tyCtor: Ty, tyArgs: ArrayList<GenericsTy>): Option<Ty> {
        var idx: Int64 = tyArgs.size
        while (idx < tyCtor.typeArgs.size) {
            tyArgs.add(AllocTyVar(srcId: "T-Fly", needSolving: true, derivedFrom: tv))
            idx++
        }
        let mapping = TypeSubst()
        idx = 0
        while (idx < tyCtor.typeArgs.size) {
            if (let Some(ctorArg) <- (tyCtor.typeArgs[idx] as GenericsTy)) {
                mapping.Put(ctorArg, tyArgs[idx])
            } else {
                return None
            }
            idx++
        }
        let placeholderTy = GetInstantiatedTy(tyCtor, mapping)
        let bounds = constraints.GetOrCreate(tv)
        bounds.sum.Add(placeholderTy)
        return placeholderTy
    }

    public func OfSameCtor(ty: Ty, tyCtor: Ty): Bool {
        if (!Ty.IsTyCorrect(ty) || !Ty.IsTyCorrect(tyCtor)) {
            return false
        }
        if (ty.typeArgs.size != tyCtor.typeArgs.size) {
            return false
        }
        let mapping = TypeSubst()
        var idx: Int64 = 0
        while (idx < tyCtor.typeArgs.size) {
            if (let Some(ctorArg) <- (tyCtor.typeArgs[idx] as GenericsTy)) {
                mapping.Put(ctorArg, ty.typeArgs[idx])
            } else {
                return false
            }
            idx++
        }
        return SameTy(GetInstantiatedTy(tyCtor, mapping), ty)
    }

    public func GetDummyBuiltInDecl(ty: Ty): Decl {
        let decl = BuiltInDecl(BuiltInType.ARRAY)
        decl.identifier = SrcIdentifier(ty.name)
        decl.SetTy(ty)
        return decl
    }

    public func GetExtendDeclByInterface(baseTy: Ty, interfaceTy: Ty): Option<ExtendDecl> {
        if (!interfaceTy.IsInterface()) {
            return None
        }
        let extendedTy = GetRealExtendedTy(baseTy, interfaceTy)
        for (extendDecl in GetAllExtendsByTy(extendedTy)) {
            for (inherited in extendDecl.inheritedTypes) {
                if (let Some(ty) <- inherited.GetTy()) {
                    if (IsSubtype(ty, interfaceTy)) {
                        return extendDecl
                    }
                }
            }
        }
        return None
    }

    public func GetExtendDeclByMember(member: Decl, baseTy: Ty): Option<ExtendDecl> {
        if (let Some(outer) <- member.outerDecl) {
            if (outer.astKind == ASTKind.INTERFACE_DECL) {
                if (let Some(outerTy) <- outer.GetTy()) {
                    return GetExtendDeclByInterface(baseTy, outerTy)
                }
            } else if (let Some(extendDecl) <- (outer as ExtendDecl)) {
                return extendDecl
            }
        }
        return None
    }

    private func putTyVarScopeDepth(tyVar: GenericsTy, depth: Int64): Unit {
        tyVarScopeDepth[tyVar.objectId] = depth
    }

    private func removeTyVarScopeDepth(tyVar: GenericsTy): Unit {
        let key = tyVar.objectId
        if (tyVarScopeDepth.contains(key)) {
            tyVarScopeDepth.remove(key)
        }
    }

    private func findTyVarScopeDepth(tyVar: GenericsTy): Option<Int64> {
        let key = tyVar.objectId
        if (let Some(depth) <- tyVarScopeDepth.get(key)) {
            return depth
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
        let tv = GetGenericsTy(decl)
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
            if (Ptr<GenericsTy>(unsolvedTyVars[idx]) == Ptr<GenericsTy>(tv)) {
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
        if (Ty.IsTyCorrect(ty) && ty.HasPlaceholder()) {
            let subst = TypeSubst()
            for (entry in constraints.entries) {
                if (!entry.bounds.eq.IsEmpty()) {
                    subst.Put(entry.tyVar, entry.bounds.eq.values[0])
                }
            }
            return GetInstantiatedTy(ty, subst)
        }
        return ty
    }

    public func ReplaceThisTy(now: Ty): Ty {
        if (let Some(thisTy) <- (now as ClassThisTy)) {
            if (let Some(decl) <- thisTy.declPtr) {
                return GetClassTy(decl, replaceThisArgs(thisTy.typeArgs))
            }
        }
        if (now.typeArgs.isEmpty()) {
            return now
        }
        let replacedArgs = replaceThisArgs(now.typeArgs)
        if (!typeArgsChanged(now.typeArgs, replacedArgs)) {
            return now
        }
        if (let Some(funcTy) <- (now as FuncTy)) {
            let params = ArrayList<Ty>()
            for (paramTy in funcTy.paramTys) {
                params.add(ReplaceThisTy(paramTy))
            }
            let cfg = FuncTyConfig()
            cfg.isC = funcTy.isC
            cfg.isClosureTy = funcTy.isClosureTy
            cfg.hasVariableLenArg = funcTy.hasVariableLenArg
            cfg.noCast = funcTy.noCast
            return GetFunctionTy(params.toArray(), ReplaceThisTy(funcTy.retTy), cfg: cfg)
        }
        if (let Some(tupleTy) <- (now as TupleTy)) {
            return GetTupleTy(replacedArgs, isClosureTy: tupleTy.isClosureTy)
        }
        if (let Some(arrayTy) <- (now as ArrayTy)) {
            if (!replacedArgs.isEmpty()) {
                return GetArrayTy(replacedArgs[0], arrayTy.dims)
            }
        }
        if (let Some(varrayTy) <- (now as VArrayTy)) {
            if (!replacedArgs.isEmpty()) {
                return GetVArrayTy(replacedArgs[0], varrayTy.size)
            }
        }
        if (let Some(pointerTy) <- (now as PointerTy)) {
            let _ = pointerTy
            if (!replacedArgs.isEmpty()) {
                return GetPointerTy(replacedArgs[0])
            }
        }
        if (let Some(classTy) <- (now as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                return GetClassTy(decl, replacedArgs)
            }
        }
        if (let Some(interfaceTy) <- (now as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                return GetInterfaceTy(decl, replacedArgs)
            }
        }
        if (let Some(structTy) <- (now as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                return GetStructTy(decl, replacedArgs)
            }
        }
        if (let Some(refEnumTy) <- (now as RefEnumTy)) {
            if (let Some(decl) <- refEnumTy.declPtr) {
                return GetRefEnumTy(decl, replacedArgs)
            }
        }
        if (let Some(enumTy) <- (now as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                return GetEnumTy(decl, typeArgs: replacedArgs)
            }
        }
        if (let Some(aliasTy) <- (now as TypeAliasTy)) {
            if (let Some(decl) <- aliasTy.declPtr) {
                return GetTypeAliasTy(decl, replacedArgs)
            }
        }
        return now
    }

    public func GetThisRealTy(now: Ty): Ty {
        return ReplaceThisTy(now)
    }

    private func ObtainsAliasTypeOfRefType(rt: RefType): Option<Ty> {
        let rtTy = rt.GetTy()
        CJC_NULLPTR_CHECK(rtTy)
        if (rtTy.getOrThrow().IsCFunc()) {
            CJC_ASSERT(rt.typeArguments.size == 1)
            let funcType = rt.typeArguments[0] as FuncType
            CJC_NULLPTR_CHECK(funcType)
            funcType.getOrThrow().isC = true
            return ObtainsAliasType(Some(funcType.getOrThrow()))
        }
        if ((rtTy.getOrThrow() as ClassThisTy).isSome()) {
            return rtTy
        }
        let typeArgs = ArrayList<Ty>()
        for (typeArg in rt.typeArguments) {
            typeArgs.add(ObtainsAliasType(Some(typeArg)).getOrThrow())
        }
        return substituteTypeArgs(rtTy.getOrThrow(), typeArgs.toArray())
    }

    private func ObtainsAliasTypeOfFuncDecl(fd: FuncDecl): Option<Ty> {
        CJC_NULLPTR_CHECK(fd.funcBody)
        let fb = fd.funcBody.getOrThrow()
        let typeArgs = ArrayList<Ty>()
        for (param in fb.paramLists[0].params) {
            typeArgs.add(ObtainsAliasType(Some(param)).getOrThrow())
        }
        if (let Some(retType) <- fb.retType) {
            typeArgs.add(ObtainsAliasType(Some(retType)).getOrThrow())
        } else {
            let funcTy = fd.GetTy().flatMap({ ty => ty as FuncTy })
            CJC_NULLPTR_CHECK(funcTy)
            typeArgs.add(funcTy.getOrThrow().retTy)
        }
        CJC_NULLPTR_CHECK(fd.GetTy())
        return substituteTypeArgs(fd.GetTy().getOrThrow(), typeArgs.toArray())
    }

    public func ObtainsAliasType(node: Option<Node>): Option<Ty> {
        if (node.isNone() || !Ty.IsTyCorrect(node.getOrThrow().GetTy())) {
            return GetInvalidTy()
        }
        let value = node.getOrThrow()
        let valueTy = value.GetTy().getOrThrow()
        if (value.TestAttr(Attribute.COMPILER_ADD)) {
            return valueTy
        }
        if (let Some(typeNode) <- (value as Type)) {
            if (!Ty.IsInitialTy(typeNode.aliasTy)) {
                let typeAliasDecl = Ty.GetDeclPtrOfTy(typeNode.aliasTy)
                CJC_NULLPTR_CHECK(typeAliasDecl)
                let aliasDecl = typeAliasDecl.getOrThrow()
                if (!aliasDecl.IsExportedDecl() && !aliasDecl.TestAttr(Attribute.IMPLICIT_USED)) {
                    return valueTy
                }
                return typeNode.aliasTy
            }
        }
        if (value.astKind == ASTKind.REF_TYPE) {
            return ObtainsAliasTypeOfRefType((value as RefType).getOrThrow())
        }
        if (value.astKind == ASTKind.PAREN_TYPE) {
            let innerType = (value as ParenType).getOrThrow().innerType
            return ObtainsAliasType(if (let Some(inner) <- innerType) { Some(inner) } else { None })
        }
        if (value.astKind == ASTKind.VARRAY_TYPE) {
            let varrayType = (value as VArrayType).getOrThrow()
            let typeArgument: Option<Node> = if (let Some(arg) <- varrayType.typeArgument) { Some(arg) } else { None }
            let typeArgs = [ObtainsAliasType(typeArgument).getOrThrow()]
            return substituteTypeArgs(valueTy, typeArgs)
        }
        if (value.astKind == ASTKind.FUNC_TYPE) {
            let funcType = (value as FuncType).getOrThrow()
            let funcTy = (valueTy as FuncTy).getOrThrow()
            let params = ArrayList<Ty>()
            for (param in funcType.paramTypes) {
                params.add(ObtainsAliasType(Some(param)).getOrThrow())
            }
            let retType: Option<Node> = if (let Some(ret) <- funcType.retType) { Some(ret) } else { None }
            let retTy = ObtainsAliasType(retType).getOrThrow()
            let cfg = FuncTyConfig()
            cfg.isC = funcType.isC
            cfg.hasVariableLenArg = funcTy.hasVariableLenArg
            return GetFunctionTy(params.toArray(), retTy, cfg: cfg)
        }
        if (value.astKind == ASTKind.TUPLE_TYPE) {
            let tupleType = (value as TupleType).getOrThrow()
            let typeArgs = ArrayList<Ty>()
            for (field in tupleType.fieldTypes) {
                typeArgs.add(ObtainsAliasType(Some(field)).getOrThrow())
            }
            return substituteTypeArgs(valueTy, typeArgs.toArray())
        }
        if (value.astKind == ASTKind.VAR_DECL || value.astKind == ASTKind.FUNC_PARAM ||
            value.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            let varDecl = (value as VarDeclAbstract).getOrThrow()
            if (let Some(typeNode) <- varDecl.typeNode) {
                return ObtainsAliasType(Some(typeNode))
            }
            return valueTy
        }
        if (value.astKind == ASTKind.FUNC_DECL) {
            return ObtainsAliasTypeOfFuncDecl((value as FuncDecl).getOrThrow())
        }
        if (value.astKind == ASTKind.EXTEND_DECL) {
            let extendedType = (value as ExtendDecl).getOrThrow().extendedType
            return ObtainsAliasType(if (let Some(typeNode) <- extendedType) { Some(typeNode) } else { None })
        }
        return valueTy
    }

    public func SubstituteTypeAliasInTy(ty: Ty, needSubstituteGeneric!: Bool = false,
        typeMapping!: TypeSubst = TypeSubst()): Ty {
        if (!Ty.IsTyCorrect(ty)) {
            return GetInvalidTy()
        }
        let typeArgs = substituteAliasArgs(ty, needSubstituteGeneric, typeMapping)
        if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
            if (let Some(decl) <- aliasTy.declPtr) {
                if (decl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                    return GetTypeAliasTy(decl, typeArgs)
                }
                if (let Some(typeNode) <- decl.typeNode) {
                    if (let Some(targetTy) <- typeNode.GetTy()) {
                        let aliasMapping = GenerateTypeMapping(decl, arrayToTypeList(typeArgs))
                        let instAliasedTy = GetInstantiatedTy(targetTy, aliasMapping)
                        if (instAliasedTy.HasAliasTy()) {
                            return SubstituteTypeAliasInTy(instAliasedTy, needSubstituteGeneric: needSubstituteGeneric,
                                typeMapping: typeMapping)
                        }
                        return instAliasedTy
                    }
                }
            }
        }
        if (let Some(genTy) <- (ty as GenericsTy)) {
            if (!needSubstituteGeneric) {
                return genTy
            }
            if (let Some(mapped) <- typeMapping.Get(genTy)) {
                return mapped
            }
            let intersectionArgs = ArrayList<Ty>()
            intersectionArgs.add(genTy)
            return GetIntersectionTy(intersectionArgs.toArray())
        }
        return substituteTypeArgs(ty, typeArgs)
    }

    private func sameDeclInstantiationTypeArgs(left: ArrayList<Ty>, right: ArrayList<Ty>): Bool {
        if (left.size != right.size) {
            return false
        }
        for (idx in 0..left.size) {
            if (!SameTy(left[idx], right[idx])) {
                return false
            }
        }
        return true
    }

    private func sameDeclInstantiationStatusKey(entry: DeclInstantiationStatusEntry, decl: Decl,
        typeArgs: ArrayList<Ty>): Bool {
        return SameDecl(entry.decl, decl) && sameDeclInstantiationTypeArgs(entry.typeArgs, typeArgs)
    }

    private func getDeclInstantiationStatus(decl: Decl, typeArgs: ArrayList<Ty>): Option<Bool> {
        for (entry in declInstantiationStatus) {
            if (sameDeclInstantiationStatusKey(entry, decl, typeArgs)) {
                return entry.value
            }
        }
        return None
    }

    private func addDeclInstantiationStatus(decl: Decl, typeArgs: ArrayList<Ty>, value: Bool): Unit {
        if (let None <- getDeclInstantiationStatus(decl, typeArgs)) {
            declInstantiationStatus.add(DeclInstantiationStatusEntry(decl, typeArgs, value))
        }
    }

    private func subtypeCacheFlagKey(implicitBoxed: Bool, allowOptionBox: Bool): Int64 {
        var key: Int64 = 0
        if (implicitBoxed) {
            key += 1
        }
        if (allowOptionBox) {
            key += 2
        }
        return key
    }

    private func getSubtypeCache(leaf: Ty, root: Ty, implicitBoxed: Bool, allowOptionBox: Bool): Option<Bool> {
        if (let Some(rootMap) <- subtypeCache.get(leaf.objectId)) {
            if (let Some(flagMap) <- rootMap.get(root.objectId)) {
                return flagMap.get(subtypeCacheFlagKey(implicitBoxed, allowOptionBox))
            }
        }
        return None
    }

    private func addSubtypeCache(leaf: Ty, root: Ty, implicitBoxed: Bool, allowOptionBox: Bool, value: Bool): Unit {
        setSubtypeCache(leaf, root, implicitBoxed, allowOptionBox, value)
    }

    private func setSubtypeCache(leaf: Ty, root: Ty, implicitBoxed: Bool, allowOptionBox: Bool, value: Bool): Unit {
        let leafKey = leaf.objectId
        if (let None <- subtypeCache.get(leafKey)) {
            subtypeCache[leafKey] = HashMap<Int64, HashMap<Int64, Bool>>()
        }
        if (let Some(rootMap) <- subtypeCache.get(leafKey)) {
            let rootKey = root.objectId
            if (let None <- rootMap.get(rootKey)) {
                rootMap[rootKey] = HashMap<Int64, Bool>()
            }
            if (let Some(flagMap) <- rootMap.get(rootKey)) {
                flagMap[subtypeCacheFlagKey(implicitBoxed, allowOptionBox)] = value
            }
        }
    }

    private func removeSubtypeCache(leaf: Ty, root: Ty, implicitBoxed: Bool, allowOptionBox: Bool): Unit {
        if (let Some(rootMap) <- subtypeCache.get(leaf.objectId)) {
            if (let Some(flagMap) <- rootMap.get(root.objectId)) {
                flagMap.remove(subtypeCacheFlagKey(implicitBoxed, allowOptionBox))
            }
        }
    }

    private func isPlaceholderSubtype(leaf: Ty, root: Ty): Bool {
        if (leaf.IsPlaceholder() || root.IsPlaceholder()) {
            return LocalTypeArgumentSynthesis.Unify(this, constraints, leaf, root)
        }
        return false
    }

    private func isGenericSubtype(leaf: Ty, root: Ty, implicitBoxed: Bool, allowOptionBox: Bool): Bool {
        if (let Some(genTy) <- (leaf as GenericsTy)) {
            if (root.IsAny() && !implicitBoxed) {
                for (upper in genTy.upperBounds) {
                    if (upper.IsClass()) {
                        return true
                    }
                }
                return false
            }
            for (upper in genTy.upperBounds) {
                if (SameTy(upper, root)) {
                    return true
                }
            }
            if (!genTy.isUpperBoundLegal) {
                return false
            }
            if (genTy.isAliasParam) {
                return true
            }
            for (upper in genTy.upperBounds) {
                if (IsSubtype(upper, root, implicitBoxed: implicitBoxed, allowOptionBox: allowOptionBox)) {
                    return true
                }
            }
        }
        if (let Some(intersectionTy) <- (leaf as IntersectionTy)) {
            for (ty in intersectionTy.tys) {
                if (IsSubtype(ty, root, implicitBoxed: implicitBoxed, allowOptionBox: allowOptionBox)) {
                    return true
                }
            }
        }
        if (let Some(intersectionTy) <- (root as IntersectionTy)) {
            for (ty in intersectionTy.tys) {
                if (!IsSubtype(leaf, ty, implicitBoxed: implicitBoxed, allowOptionBox: allowOptionBox)) {
                    return false
                }
            }
            return true
        }
        if (let Some(unionTy) <- (leaf as UnionTy)) {
            for (ty in unionTy.tys) {
                if (!IsSubtype(ty, root, implicitBoxed: implicitBoxed, allowOptionBox: allowOptionBox)) {
                    return false
                }
            }
            return true
        }
        return false
    }

    private func isCommonAndSpecificRelation(leafTy: Ty, rootTy: Ty): Bool {
        if (!leafTy.IsNominal() || !rootTy.IsNominal()) {
            return false
        }
        if (let Some(leafDeclRaw) <- Ty.GetDeclOfTy(Some(leafTy))) {
            if (let Some(rootDeclRaw) <- Ty.GetDeclOfTy(Some(rootTy))) {
                let leafDecl = if (let Some(specific) <- leafDeclRaw.specificImplementation) {
                    specific
                } else {
                    leafDeclRaw
                }
                let rootDecl = if (let Some(specific) <- rootDeclRaw.specificImplementation) {
                    specific
                } else {
                    rootDeclRaw
                }
                if (!leafDecl.TestAttr(Attribute.SPECIFIC) || !rootDecl.TestAttr(Attribute.SPECIFIC)) {
                    return false
                }
                return SameDecl(leafDecl, rootDecl)
            }
        }
        return false
    }

    private func isClassLikeSubtype(leaf: Ty, root: Ty, implicitBoxed: Bool, allowOptionBox: Bool): Bool {
        if (let Some(thisTyOfLeaf) <- (leaf as ClassThisTy)) {
            if (let Some(leafDecl) <- thisTyOfLeaf.declPtr) {
                let leafClassTy = GetClassTy(leafDecl, thisTyOfLeaf.typeArgs.toArray())
                if (let Some(thisTyOfRoot) <- (root as ClassThisTy)) {
                    if (let Some(rootDecl) <- thisTyOfRoot.declPtr) {
                        return IsSubtype(leafClassTy, GetClassTy(rootDecl, thisTyOfRoot.typeArgs.toArray()))
                    }
                }
                return IsSubtype(leafClassTy, root, implicitBoxed: implicitBoxed, allowOptionBox: allowOptionBox)
            }
        }
        if (leaf.IsClassLike() && root.IsClassLike()) {
            let superTys = GetAllSuperTys(leaf, typeMapping: TypeSubst(), withExtended: true)
            for (superTy in superTys.values) {
                if (isClassTyEqual(superTy, root)) {
                    return true
                }
            }
        }
        return false
    }

    private func isClassTyEqual(leaf: Ty, root: Ty): Bool {
        if (SameTy(leaf, root) || isCommonAndSpecificRelation(leaf, root)) {
            return true
        }
        if (isClassThisType(leaf) || isClassThisType(root)) {
            return false
        }
        if (!leaf.IsClassLike() || !root.IsClassLike() || leaf.IsClass()) {
            return false
        }
        if (leaf.typeArgs.size != root.typeArgs.size) {
            return false
        }
        if (let Some(leftClassLike) <- (leaf as ClassLikeTy)) {
            if (let Some(rightClassLike) <- (root as ClassLikeTy)) {
                if (let Some(leftDecl) <- leftClassLike.commonDecl) {
                    if (let Some(rightDecl) <- rightClassLike.commonDecl) {
                        if (!SameDecl(leftDecl, rightDecl)) {
                            return false
                        }
                    } else {
                        return false
                    }
                } else {
                    return false
                }
            }
        }
        var idx: Int64 = 0
        while (idx < leaf.typeArgs.size) {
            let leafArg = leaf.typeArgs[idx]
            let rootArg = root.typeArgs[idx]
            if (rootArg.IsIntersection()) {
                if (!IsSubtype(leafArg, rootArg)) {
                    return false
                }
            } else if (!SameTy(rootArg, leafArg) && !IsPlaceholderEqual(rootArg, leafArg)) {
                return false
            }
            idx++
        }
        return true
    }

    private func isEnumCompatibleForSubtype(left: EnumTy, right: EnumTy, implicitBoxed: Bool): Bool {
        if (left.typeArgs.size != right.typeArgs.size || left.name != right.name ||
            !sameEnumDeclOption(left.declPtr, right.declPtr)) {
            return false
        }
        var idx: Int64 = 0
        while (idx < left.typeArgs.size) {
            if (CheckTypeCompatibility(left.typeArgs[idx], right.typeArgs[idx], implicitBoxed: implicitBoxed,
                isGeneric: left.typeArgs[idx].IsGeneric()) == TypeCompatibility.INCOMPATIBLE) {
                return false
            }
            idx++
        }
        return true
    }

    private func isStructOrEnumSubtype(leaf: Ty, root: Ty, implicitBoxed: Bool, allowOptionBox: Bool): Bool {
        let enumRefCompatible = (isRefEnumType(leaf) && leaf.IsEnum() && root.IsEnum()) ||
            (isRefEnumType(root) && root.IsEnum() && leaf.IsEnum())
        if (enumRefCompatible) {
            if (let Some(leftEnum) <- (leaf as EnumTy)) {
                if (let Some(rightEnum) <- (root as EnumTy)) {
                    if (isEnumCompatibleForSubtype(leftEnum, rightEnum, implicitBoxed)) {
                        return true
                    }
                }
            }
        }
        if (implicitBoxed) {
            if (leaf.IsStruct() && root.kind == TypeKind.TYPE_INTERFACE &&
                HasSuperTy(leaf, root, TypeSubst(), withExtended: implicitBoxed)) {
                return true
            }
            if (root.IsCoreOptionType() && root.typeArgs.size == 1 && allowOptionBox &&
                CountOptionNestedLevel(leaf) < CountOptionNestedLevel(root)) {
                return IsSubtype(leaf, root.typeArgs[0], implicitBoxed: implicitBoxed)
            }
            if (leaf.IsEnum() && root.kind == TypeKind.TYPE_INTERFACE &&
                HasSuperTy(leaf, root, TypeSubst(), withExtended: implicitBoxed)) {
                return true
            }
        }
        return false
    }

    private func isArraySubtype(leaf: Ty, root: Ty): Bool {
        if (let Some(leftArray) <- (leaf as ArrayTy)) {
            if (let Some(rightArray) <- (root as ArrayTy)) {
                return leftArray.dims == rightArray.dims && !leftArray.typeArgs.isEmpty() &&
                    !rightArray.typeArgs.isEmpty() && IsTyEqual(leftArray.typeArgs[0], rightArray.typeArgs[0])
            }
        }
        return false
    }

    private func isVArraySubtype(leaf: Ty, root: Ty): Bool {
        if (let Some(leftArray) <- (leaf as VArrayTy)) {
            if (let Some(rightArray) <- (root as VArrayTy)) {
                return leftArray.size == rightArray.size && !leftArray.typeArgs.isEmpty() &&
                    !rightArray.typeArgs.isEmpty() && IsTyEqual(leftArray.typeArgs[0], rightArray.typeArgs[0])
            }
        }
        return false
    }

    private func isPointerSubtype(leaf: Ty, root: Ty): Bool {
        if (let Some(leftPointer) <- (leaf as PointerTy)) {
            if (let Some(rightPointer) <- (root as PointerTy)) {
                return !leftPointer.typeArgs.isEmpty() && !rightPointer.typeArgs.isEmpty() &&
                    IsTyEqual(leftPointer.typeArgs[0], rightPointer.typeArgs[0])
            }
        }
        return false
    }

    private func isPrimitiveSubtype(leaf: Ty, root: Ty): Bool {
        if (leaf.kind == TypeKind.TYPE_IDEAL_INT && root.IsInteger()) {
            return true
        }
        if (leaf.kind == TypeKind.TYPE_IDEAL_FLOAT && root.IsFloating()) {
            return true
        }
        if (leaf.kind == TypeKind.TYPE_IDEAL_INT) {
            return IsSubtype(GetPrimitiveTy(TypeKind.TYPE_INT64), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_UINT64), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_INT32), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_UINT32), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_INT16), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_UINT16), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_INT8), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_UINT8), root)
        }
        if (leaf.kind == TypeKind.TYPE_IDEAL_FLOAT) {
            return IsSubtype(GetPrimitiveTy(TypeKind.TYPE_FLOAT64), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_FLOAT32), root) ||
                IsSubtype(GetPrimitiveTy(TypeKind.TYPE_FLOAT16), root)
        }
        return leaf.IsPrimitive() && root.IsPrimitive() && leaf.kind == root.kind
    }

    private func checkGenericType(lvalue: Ty, rvalue: Ty, implicitBoxed: Bool): Bool {
        if (Ty.IsTyCorrect(lvalue) && Ty.IsTyCorrect(rvalue) &&
            lvalue.kind == TypeKind.TYPE_GENERICS && rvalue.kind == TypeKind.TYPE_GENERICS) {
            if (let Some(leftGen) <- (lvalue as GenericsTy)) {
                if (let Some(rightGen) <- (rvalue as GenericsTy)) {
                    if (leftGen.isPlaceholder || rightGen.isPlaceholder) {
                        return false
                    }
                    if (leftGen.upperBounds.isEmpty() && rightGen.upperBounds.isEmpty()) {
                        return true
                    }
                    if (leftGen.upperBounds.size != rightGen.upperBounds.size) {
                        return false
                    }
                    var idx: Int64 = 0
                    while (idx < leftGen.upperBounds.size) {
                        if (CheckTypeCompatibility(leftGen.upperBounds[idx], rightGen.upperBounds[idx],
                            implicitBoxed: implicitBoxed) != TypeCompatibility.IDENTICAL) {
                            return false
                        }
                        idx++
                    }
                    return true
                }
            }
        }
        return IsSubtype(rvalue, lvalue, implicitBoxed: implicitBoxed, allowOptionBox: false)
    }

    private func isClassThisType(ty: Ty): Bool {
        if (let Some(_) <- (ty as ClassThisTy)) {
            return true
        }
        return false
    }

    private func isRefEnumType(ty: Ty): Bool {
        if (let Some(_) <- (ty as RefEnumTy)) {
            return true
        }
        return false
    }

    private func sameEnumDeclOption(left: Option<EnumDecl>, right: Option<EnumDecl>): Bool {
        if (let Some(leftDecl) <- left) {
            if (let Some(rightDecl) <- right) {
                return SameDecl(leftDecl, rightDecl)
            }
            return false
        }
        if (let Some(_) <- right) {
            return false
        }
        return true
    }

    private func replaceThisArgs(args: ArrayList<Ty>): Array<Ty> {
        let out = ArrayList<Ty>()
        for (arg in args) {
            out.add(ReplaceThisTy(arg))
        }
        return out.toArray()
    }

    private func arrayToTypeList(args: Array<Ty>): ArrayList<Ty> {
        let out = ArrayList<Ty>()
        for (arg in args) {
            out.add(arg)
        }
        return out
    }

    private func typeArgsChanged(original: ArrayList<Ty>, replaced: Array<Ty>): Bool {
        if (original.size != replaced.size) {
            return true
        }
        var idx: Int64 = 0
        while (idx < original.size) {
            if (!SameTy(original[idx], replaced[idx])) {
                return true
            }
            idx++
        }
        return false
    }

    private func substituteAliasArgs(ty: Ty, needSubstituteGeneric: Bool, typeMapping: TypeSubst): Array<Ty> {
        let out = ArrayList<Ty>()
        for (arg in ty.typeArgs) {
            if (Ty.IsTyCorrect(arg) || needSubstituteGeneric) {
                out.add(SubstituteTypeAliasInTy(arg, needSubstituteGeneric: needSubstituteGeneric,
                    typeMapping: typeMapping))
            } else {
                out.add(arg)
            }
        }
        return out.toArray()
    }

    private func substituteTypeArgs(ty: Ty, typeArgs: Array<Ty>): Ty {
        if (let Some(thisTy) <- (ty as ClassThisTy)) {
            if (let Some(decl) <- thisTy.declPtr) {
                return GetClassThisTy(decl, typeArgs)
            }
        }
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                return GetClassTy(decl, typeArgs)
            }
        }
        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                return GetInterfaceTy(decl, typeArgs)
            }
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                return GetStructTy(decl, typeArgs)
            }
        }
        if (let Some(refEnumTy) <- (ty as RefEnumTy)) {
            if (let Some(decl) <- refEnumTy.declPtr) {
                return GetRefEnumTy(decl, typeArgs)
            }
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                return GetEnumTy(decl, typeArgs: typeArgs)
            }
        }
        if (let Some(funcTy) <- (ty as FuncTy)) {
            if (typeArgs.isEmpty()) {
                return GetInvalidTy()
            }
            let params = ArrayList<Ty>()
            var idx: Int64 = 0
            while (idx + 1 < typeArgs.size) {
                params.add(typeArgs[idx])
                idx++
            }
            let cfg = FuncTyConfig()
            cfg.isC = funcTy.isC
            cfg.hasVariableLenArg = funcTy.hasVariableLenArg
            return GetFunctionTy(params.toArray(), typeArgs[typeArgs.size - 1], cfg: cfg)
        }
        if (ty is TupleTy) {
            return GetTupleTy(typeArgs)
        }
        if (let Some(arrayTy) <- (ty as ArrayTy)) {
            if (!typeArgs.isEmpty()) {
                return GetArrayTy(typeArgs[0], arrayTy.dims)
            }
        }
        if (let Some(varrayTy) <- (ty as VArrayTy)) {
            if (!typeArgs.isEmpty()) {
                return GetVArrayTy(typeArgs[0], varrayTy.size)
            }
        }
        if (let Some(pointerTy) <- (ty as PointerTy)) {
            let _ = pointerTy
            if (!typeArgs.isEmpty()) {
                return GetPointerTy(typeArgs[0])
            }
        }
        if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
            if (let Some(decl) <- aliasTy.declPtr) {
                return GetTypeAliasTy(decl, typeArgs)
            }
        }
        if (let Some(unionTy) <- (ty as UnionTy)) {
            let _ = unionTy
            return GetUnionTy(typeArgs)
        }
        if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
            let _ = intersectionTy
            return GetIntersectionTy(typeArgs)
        }
        return ty
    }

    private func collectAllUpperBounds(genTy: GenericsTy): TySet {
        let out = TySet()
        let worklist = ArrayList<Ty>()
        for (upper in genTy.upperBounds) {
            if (out.Add(upper) && upper.IsGeneric()) {
                worklist.add(upper)
            }
        }
        while (!worklist.isEmpty()) {
            let last = worklist[worklist.size - 1]
            worklist.remove(at: worklist.size - 1)
            if (let Some(currentGen) <- (last as GenericsTy)) {
                for (upper in currentGen.upperBounds) {
                    if (out.Add(upper) && upper.IsGeneric()) {
                        worklist.add(upper)
                    }
                }
            }
        }
        return out
    }

    private func collectNominalSuperTys(ty: Ty, typeMapping: TypeSubst, withExtended: Bool, out: TySet): Unit {
        let _ = withExtended
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(ty))) {
            let substituteMapping = GetSubstituteMapping(ty, typeMapping)
            for (inheritedType in decl.inheritedTypes) {
                if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                    if (IsInheritableType(inheritedTy)) {
                        out.AddAll(GetAllSuperTys(inheritedTy, typeMapping: substituteMapping))
                    }
                }
            }
        }
    }

    private func hasNominalSuperTy(ty: Ty, superTy: Ty, typeMapping: TypeSubst, withExtended: Bool): Bool {
        let _ = withExtended
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(ty))) {
            let substituteMapping = GetSubstituteMapping(ty, typeMapping)
            for (inheritedType in decl.inheritedTypes) {
                if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                    if (IsInheritableType(inheritedTy) &&
                        HasSuperTy(inheritedTy, superTy, substituteMapping)) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func mergeTypeSubst(target: TypeSubst, source: TypeSubst): Unit {
        for ((tyVar, ty) in source.entries) {
            target.Put(tyVar.value, ty)
        }
    }

    private func getAllExtendInterfaceTyHelper(extends: ArrayList<ExtendDecl>, typeArgs: ArrayList<Ty>): TySet {
        let out = TySet()
        for (extendDecl in extends) {
            if (!CheckGenericDeclInstantiation(Some(extendDecl), typeArgs)) {
                continue
            }
            let typeMapping = TypeSubst()
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    if (extendedTy.typeArgs.size != typeArgs.size) {
                        continue
                    }
                    var idx: Int64 = 0
                    while (idx < typeArgs.size) {
                        mergeTypeSubst(typeMapping,
                            GenerateTypeMappingByTy(Some(extendedTy.typeArgs[idx]), Some(typeArgs[idx])))
                        idx++
                    }
                }
            }
            for (superInterfaceTy in extendDecl.inheritedTypes) {
                if (let Some(inheritedTy) <- superInterfaceTy.GetTy()) {
                    if (IsInheritableType(inheritedTy)) {
                        let instTy = GetInstantiatedTy(inheritedTy, typeMapping)
                        out.AddAll(GetAllSuperTys(instTy, typeMapping: TypeSubst(), withExtended: true))
                    }
                }
            }
        }
        return out
    }

    private func HasExtendInterfaceTyHelper(
        superTy: Ty, extends: ArrayList<ExtendDecl>, typeArgs: ArrayList<Ty>): Bool {
        try (cs = PData.CommitScope(constraints)) {
            for (extendDecl in extends) {
                if (!CheckGenericDeclInstantiation(Some(extendDecl), typeArgs)) {
                    PData.Reset(constraints)
                    continue
                }
                let extendedTy: Option<Ty> = if (let Some(extendedType) <- extendDecl.extendedType) {
                    extendedType.GetTy()
                } else {
                    None
                }
                if ((let None <- extendedTy) || extendedTy.getOrThrow().typeArgs.size != typeArgs.size) {
                    PData.Reset(constraints)
                    continue
                }
                let typeMapping = TypeSubst()
                var idx: Int64 = 0
                while (idx < typeArgs.size) {
                    if (let Some(genericSuper) <- (extendedTy.getOrThrow().typeArgs[idx] as GenericsTy)) {
                        typeMapping.Put(genericSuper, typeArgs[idx])
                    }
                    idx++
                }
                for (superInterfaceTy in extendDecl.inheritedTypes) {
                    if (let Some(inheritedTy) <- superInterfaceTy.GetTy()) {
                        if (!IsInheritableType(inheritedTy)) {
                            continue
                        }
                        let instTy = GetInstantiatedTy(inheritedTy, typeMapping)
                        if (HasSuperTy(instTy, superTy, typeMapping, withExtended: true)) {
                            return true
                        }
                    }
                }
                PData.Reset(constraints)
            }
        }
        return false
    }

    private func isTyExtendInterface(classTy: Ty, interfaceTy: Ty): Bool {
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(Some(classTy))) {
            return getAllExtendInterfaceTyHelper(GetDeclExtends(decl), GetTypeArgs(classTy)).Contains(interfaceTy)
        }
        return false
    }

    private func getExtendInterfaceSuperTy(classTy: Ty, interfaceTy: Ty): Option<Ty> {
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(classTy))) {
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                let mapping = MultiTypeSubst()
                GenerateGenericMapping(mapping, classTy)
                let typeMapping = MultiTypeSubstToTypeSubst(mapping)
                var current = classDecl.GetSuperClassDecl()
                while (let Some(superDecl) <- current) {
                    if (let Some(superTy) <- superDecl.GetTy()) {
                        let instTy = GetInstantiatedTy(superTy, typeMapping)
                        if (isTyExtendInterface(instTy, interfaceTy)) {
                            return instTy
                        }
                    }
                    current = superDecl.GetSuperClassDecl()
                }
            }
        }
        return None
    }

    private func declName(decl: Decl): String {
        let name = decl.identifier.Val()
        return if (name.isEmpty()) { decl.identifier.GetRawText() } else { name }
    }

    private func getInstantiatedGenericTy(ty: GenericsTy, typeMapping: TypeSubst): Ty {
        var current: Ty = ty
        let mapping = typeMapping.Clone()
        let visited = ArrayList<GenericsTy>()
        var searching = true
        while (searching) {
            searching = false
            if (let Some(currentGen) <- (current as GenericsTy)) {
                if (containsGeneric(visited, currentGen)) {
                    return current
                }
                visited.add(currentGen)
                if (let Some(mapped) <- mapping.Get(currentGen)) {
                    current = mapped
                    removeTypeSubst(mapping, currentGen)
                    searching = true
                }
            }
        }
        if (!mapping.IsEmpty() && !current.IsGeneric() && current.HasGeneric()) {
            return GetInstantiatedTy(current, mapping)
        }
        return current
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
            if (Ptr<GenericsTy>(value) == Ptr<GenericsTy>(ty)) {
                return true
            }
        }
        return false
    }

    private func removeTypeSubst(mapping: TypeSubst, tyVar: GenericsTy): Unit {
        mapping.entries.remove(Ptr<GenericsTy>(tyVar))
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
