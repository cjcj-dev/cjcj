package cangjie_compiler::incremental_compilation

import std.collection.*
import std.sort.*

public class ASTCacheCalculator {
    public let mangled2Decl: RawMangled2DeclMap = RawMangled2DeclMap()
    public let ret: ASTCache = ASTCache()
    public let duplicatedMangleNames: HashSet<IncrDecl> = HashSet<IncrDecl>()
    public let directExtends: HashMap<String, ArrayList<DirectExtendEntry>> =
        HashMap<String, ArrayList<DirectExtendEntry>>()
    public let order: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    public let fileMap: FileMap = FileMap()

    private let pkg: IncrPackage
    private let srcInfo: (Bool, Bool)
    private var gid: Int64 = 0
    private var inVarWithPattern: Bool = false
    private var curFileDecls: Option<ArrayList<IncrDecl>> = None

    public init(pkg: IncrPackage, srcInfo: (Bool, Bool)) {
        this.pkg = pkg
        this.srcInfo = srcInfo
    }

    public func Walk(): Unit {
        // Adapter declarations may carry precomputed ASTHasher/ASTMangler values; otherwise the
        // package-local stable fallbacks below keep cache calculation deterministic.
        for (file in pkg.files) {
            gid = 0
            inVarWithPattern = false
            let trimmedPath = GetTrimmedPath(file)
            if (!fileMap.contains(trimmedPath)) {
                fileMap[trimmedPath] = ArrayList<IncrDecl>()
            }
            curFileDecls = Some(fileMap[trimmedPath])
            var idx: Int64 = 0
            while (idx < file.decls.size) {
                let decl = file.decls[idx]
                if (idx == 0 && (decl.astKind == IncrDeclKind.VAR_DECL ||
                    decl.astKind == IncrDeclKind.VAR_WITH_PATTERN_DECL)) {
                    gid--
                }
                WalkDecl(decl)
                idx++
            }
        }

        for ((mangle, extends) in directExtends) {
            if (extends.isEmpty()) {
                continue
            }
            mangled2Decl[mangle] = extends[0].decl
            ret[mangle] = ComputeDirectExtend(extends)
        }
    }

    private func WalkDecl(decl: IncrDecl): Unit {
        if (decl.astKind == IncrDeclKind.EXTEND_DECL && decl.constructorMangles.isEmpty() &&
            decl.HasExtendedTypeMangle()) {
            decl.rawMangleName = MangleDecl(decl)
            if (!directExtends.contains(decl.rawMangleName)) {
                directExtends[decl.rawMangleName] = ArrayList<DirectExtendEntry>()
                order.add(decl)
            }
            directExtends[decl.rawMangleName].add(DirectExtendEntry(decl, gid))
            for (member in GetMembers(decl)) {
                PrevisitDirectExtendMember(member)
            }
            return
        }
        order.add(decl)
        ret[visitTopLevelMangle(decl)] = VisitTopLevel(decl)
        CollectDecl(decl)
    }

    private func ComputeDirectExtend(extends: ArrayList<DirectExtendEntry>): TopLevelDeclCache {
        let result = TopLevelDeclCache()
        let publicMembers = ArrayList<IncrDecl>()
        for (entry in extends) {
            for (member in GetMembers(entry.decl)) {
                result.members.add(RevisitDirectExtendMember(member, entry.gvid))
                if (member.TestAttr(IncrAttribute.PUBLIC)) {
                    publicMembers.add(member)
                }
            }
        }
        let decl = extends[0].decl
        decl.cacheHash.srcUse = ComputeDeclSrcUseHash(decl)
        decl.cacheHash.sig = ComputeDeclSigHash(decl)
        decl.cacheHash.bodyHash = HashMemberAPIs(publicMembers)
        result.srcUse = decl.cacheHash.srcUse
        result.sigHash = decl.cacheHash.sig
        result.bodyHash = decl.cacheHash.bodyHash
        result.gvid = GlobalVarIndex(GetTrimmedPath(decl), extends[0].gvid)
        decl.cacheHash.gvid = result.gvid.id
        result.astKind = UInt8(IncrDeclKindIndex(decl.astKind))
        result.isGV = false
        result.cgMangle = if (decl.cgMangle.isEmpty()) { decl.mangledName } else { decl.cgMangle }
        return result
    }

    private func HashMemberAPIs(members: ArrayList<IncrDecl>): UInt64 {
        var hash = 0u64
        let sortedMembers = ArrayList<IncrDecl>()
        for (member in members) {
            sortedMembers.add(member)
        }
        sort(sortedMembers, by: { left: IncrDecl, right: IncrDecl =>
            CompareStrings(left.rawMangleName, right.rawMangleName)
        }, stable: true)
        for (member in sortedMembers) {
            hash = CombineHash(hash, StableHash(member.rawMangleName))
            hash = CombineHash(hash, ComputeDeclSigHash(member))
            hash = CombineHash(hash, ComputeDeclSrcUseHash(member))
        }
        return hash
    }

    private func PrevisitDirectExtendMember(decl: IncrDecl): Unit {
        for (member in GetMembers(decl)) {
            PrevisitDirectExtendMember(member)
        }
        decl.rawMangleName = MangleDecl(decl)
        CollectDecl(decl)
        decl.cacheHash.srcUse = ComputeDeclSrcUseHash(decl)
        decl.cacheHash.bodyHash = ComputeDeclBodyHash(decl, srcInfo)
        decl.cacheHash.sig = ComputeDeclSigHash(decl)
        decl.cacheHash.gvid = gid
        if (IsOOEAffectedDecl(decl)) {
            AddCurFileDecl(decl)
        }
    }

    private func VisitTopLevelDeclMembers(decl: IncrDecl, result: TopLevelDeclCache): Unit {
        for (member in GetMembers(decl)) {
            if (IsStaticVar(member)) {
                result.members.add(VisitMember(member))
            }
        }
        for (member in GetMembers(decl)) {
            if (!IsStaticVar(member)) {
                result.members.add(VisitMember(member))
                if (member.astKind == IncrDeclKind.PRIMARY_CTOR_DECL) {
                    for (param in member.members) {
                        if (param.isMemberParam) {
                            result.members.add(VisitMember(param))
                        }
                    }
                }
            }
        }
    }

    private func VisitTopLevel(decl: IncrDecl): TopLevelDeclCache {
        let result = TopLevelDeclCache()
        VisitTopLevelDeclMembers(decl, result)

        decl.rawMangleName = MangleDecl(decl)
        decl.cacheHash.srcUse = ComputeDeclSrcUseHash(decl)
        decl.cacheHash.bodyHash = ComputeDeclBodyHash(decl, srcInfo)
        decl.cacheHash.sig = ComputeDeclSigHash(decl)
        result.srcUse = decl.cacheHash.srcUse
        result.bodyHash = decl.cacheHash.bodyHash
        result.sigHash = decl.cacheHash.sig
        VisitTopLevelImpl(decl, result)
        decl.cacheHash.instVar = result.instVarHash
        decl.cacheHash.virt = result.virtHash
        result.gvid = GlobalVarIndex(GetTrimmedPath(decl), gid)
        decl.cacheHash.gvid = gid
        result.astKind = UInt8(IncrDeclKindIndex(decl.astKind))
        result.cgMangle = if (decl.cgMangle.isEmpty()) { decl.mangledName } else { decl.cgMangle }
        return result
    }

    private func VisitTopLevelImpl(decl: IncrDecl, result: TopLevelDeclCache): Unit {
        match (decl.astKind) {
            case IncrDeclKind.ENUM_DECL =>
                result.instVarHash = VisitEnumConstructors(decl)
            case IncrDeclKind.INTERFACE_DECL =>
                result.virtHash = VirtualHashOfInterface(decl)
            case IncrDeclKind.CLASS_DECL =>
                result.virtHash = VirtualHashOfClass(decl)
                result.instVarHash = VisitMemberVariables(decl)
            case IncrDeclKind.STRUCT_DECL =>
                result.instVarHash = VisitMemberVariables(decl)
            case IncrDeclKind.VAR_WITH_PATTERN_DECL =>
                gid++
                inVarWithPattern = true
                for (member in decl.members) {
                    WalkDecl(member)
                }
                inVarWithPattern = false
                result.isGV = true
                AddCurFileDecl(decl)
            case IncrDeclKind.VAR_DECL =>
                result.isGV = !inVarWithPattern
                if (!inVarWithPattern) {
                    gid++
                    if (IsOOEAffectedDecl(decl)) {
                        AddCurFileDecl(decl)
                    }
                }
            case IncrDeclKind.FUNC_DECL =>
                if (IsOOEAffectedDecl(decl)) {
                    AddCurFileDecl(decl)
                }
            case IncrDeclKind.MAIN_DECL =>
                AddCurFileDecl(decl)
            case IncrDeclKind.MACRO_DECL =>
                AddCurFileDecl(decl)
            case _ => ()
        }
    }

    private func VisitMemberVariables(decl: IncrDecl): UInt64 {
        var hash = 0u64
        for (member in GetMembers(decl)) {
            if (member.astKind == IncrDeclKind.VAR_DECL && IsInstance(member)) {
                hash = CombineDeclHash(hash, member)
                if (!member.hasExplicitType) {
                    hash = CombineHash(hash, ComputeDeclBodyHash(member, (true, true)))
                }
            } else if (member.astKind == IncrDeclKind.PRIMARY_CTOR_DECL) {
                for (param in member.members) {
                    if (param.isMemberParam) {
                        hash = CombineDeclHash(hash, param)
                    }
                }
            }
        }
        return hash
    }

    private func VisitEnumConstructors(decl: IncrDecl): UInt64 {
        var hash = StableHashBool(decl.hasEllipsis)
        for (mangle in decl.enumConstructorMangles) {
            hash = CombineHash(hash, StableHash(mangle))
        }
        for (member in GetMembers(decl)) {
            if (member.TestAttr(IncrAttribute.ENUM_CONSTRUCTOR)) {
                hash = CombineDeclHash(hash, member)
            }
        }
        return hash
    }

    private func VirtualHashOfClass(decl: IncrDecl): UInt64 {
        var hash = 0u64
        for (member in GetMembers(decl)) {
            if (IsVirtual(member)) {
                hash = CombineDeclHash(hash, member)
                if (IsUntyped(member)) {
                    hash = CombineHash(hash, ComputeDeclBodyHash(member, (false, false)))
                }
            }
        }
        return hash
    }

    private func VirtualHashOfInterface(decl: IncrDecl): UInt64 {
        let membersToHash = ArrayList<IncrDecl>()
        for (member in GetMembers(decl)) {
            if (member.astKind == IncrDeclKind.FUNC_DECL || member.astKind == IncrDeclKind.PROP_DECL) {
                membersToHash.add(member)
                for (accessor in GetMembers(member)) {
                    membersToHash.add(accessor)
                }
            }
        }
        sort(membersToHash, by: { left: IncrDecl, right: IncrDecl =>
            CompareStrings(left.rawMangleName, right.rawMangleName)
        }, stable: true)
        var hash = 0u64
        for (member in membersToHash) {
            hash = CombineDeclHash(hash, member)
            if (IsUntyped(member)) {
                hash = CombineHash(hash, ComputeDeclBodyHash(member, (false, false)))
            }
        }
        return hash
    }

    private func VisitMember(decl: IncrDecl): MemberDeclCache {
        let result = MemberDeclCache()
        for (member in GetMembers(decl)) {
            result.members.add(VisitMember(member))
        }
        decl.rawMangleName = MangleDecl(decl)
        result.rawMangle = decl.rawMangleName
        CollectDecl(decl)
        decl.cacheHash.srcUse = ComputeDeclSrcUseHash(decl)
        decl.cacheHash.bodyHash = ComputeDeclBodyHash(decl, srcInfo)
        decl.cacheHash.sig = ComputeDeclSigHash(decl)
        result.srcUse = decl.cacheHash.srcUse
        result.bodyHash = decl.cacheHash.bodyHash
        result.sigHash = decl.cacheHash.sig
        if (IsStaticVar(decl)) {
            gid++
        }
        result.gvid = GlobalVarIndex(GetTrimmedPath(decl), gid)
        decl.cacheHash.gvid = gid
        if (IsOOEAffectedDecl(decl)) {
            AddCurFileDecl(decl)
        }
        result.astKind = UInt8(IncrDeclKindIndex(if (decl.isMemberParam) { IncrDeclKind.VAR_DECL } else { decl.astKind }))
        result.isGV = decl.astKind == IncrDeclKind.VAR_DECL && decl.TestAttr(IncrAttribute.STATIC)
        result.cgMangle = if (decl.cgMangle.isEmpty()) { decl.mangledName } else { decl.cgMangle }
        return result
    }

    private func RevisitDirectExtendMember(decl: IncrDecl, gvid: Int64): MemberDeclCache {
        let result = MemberDeclCache()
        for (member in GetMembers(decl)) {
            result.members.add(RevisitDirectExtendMember(member, gvid))
        }
        result.rawMangle = decl.rawMangleName
        result.srcUse = decl.cacheHash.srcUse
        result.bodyHash = decl.cacheHash.bodyHash
        result.sigHash = decl.cacheHash.sig
        result.astKind = UInt8(IncrDeclKindIndex(decl.astKind))
        result.gvid = GlobalVarIndex(GetTrimmedPath(decl), gvid)
        result.isGV = false
        result.cgMangle = if (decl.cgMangle.isEmpty()) { decl.mangledName } else { decl.cgMangle }
        decl.cacheHash.gvid = gvid
        for (member in GetMembers(decl)) {
            member.cacheHash.gvid = gvid
        }
        for (memberCache in result.members) {
            memberCache.gvid.id = gvid
        }
        return result
    }

    private func CollectDecl(decl: IncrDecl): Unit {
        let mangle = decl.rawMangleName
        if (mangle.isEmpty()) {
            return
        }
        if (let Some(oldDecl) <- mangled2Decl.get(mangle)) {
            duplicatedMangleNames.add(decl)
            duplicatedMangleNames.add(oldDecl)
        }
        mangled2Decl[mangle] = decl
    }

    private func AddCurFileDecl(decl: IncrDecl): Unit {
        if (let Some(fileDecls) <- curFileDecls) {
            fileDecls.add(decl)
        }
    }

    private func visitTopLevelMangle(decl: IncrDecl): String {
        decl.rawMangleName = MangleDecl(decl)
        return decl.rawMangleName
    }

    private func CombineDeclHash(hash: UInt64, decl: IncrDecl): UInt64 {
        var out = CombineHash(hash, StableHash(decl.rawMangleName))
        out = CombineHash(out, ComputeDeclSigHash(decl))
        out = CombineHash(out, ComputeDeclSrcUseHash(decl))
        return out
    }
}
