package cjcj::incremental_compilation

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::mangle.ASTMangler
import cjcj::parse.{ASTHasher, GetTrimmedPath}
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, SipHash}

public class ASTCacheCalculator {
    public let mangled2Decl: RawMangled2DeclMap = RawMangled2DeclMap()
    public let ret: ASTCache = ASTCache()
    public let duplicatedMangleNames: HashSet<Decl> = HashSet<Decl>()
    public let directExtends: HashMap<RawMangledName, ArrayList<(ExtendDecl, Int64)>> =
        HashMap<RawMangledName, ArrayList<(ExtendDecl, Int64)>>()
    public let order: ArrayList<Decl> = ArrayList<Decl>()
    public let fileMap: FileMap = FileMap()

    private let pkg: Package
    private let mangler: ASTMangler
    private let srcInfo: (Bool, Bool)
    private var gid: Int64 = 0
    private var invp: Bool = false
    private var curFile: Option<ArrayList<Decl>> = None

    public init(pkg: Package, srcInfo: (Bool, Bool)) {
        this.pkg = pkg
        this.mangler = ASTMangler(pkg.fullPackageName)
        this.srcInfo = srcInfo
    }

    public func Walk(): Unit {
        for (file in pkg.files) {
            gid = 0
            invp = false
            let path = GetTrimmedPath(Some(file))
            if (!fileMap.contains(path)) {
                fileMap[path] = ArrayList<Decl>()
            }
            curFile = Some(fileMap[path])
            var idx: Int64 = 0
            while (idx < file.decls.size) {
                let decl = file.decls[idx]
                if (idx == 0 && (decl as VarDeclAbstract).isSome()) {
                    gid--
                }
                WalkDecl(decl)
                idx++
            }
        }

        for ((mangle, extends) in directExtends) {
            mangled2Decl[mangle] = extends[0][0]
            ret[mangle] = ComputeDirectExtend(extends)
        }
    }

    private func ComputeDirectExtend(extends: ArrayList<(ExtendDecl, Int64)>): TopLevelDeclCache {
        let result = TopLevelDeclCache()
        let members = ArrayList<Decl>()
        for (extendEntry in extends) {
            for (member in extendEntry[0].members) {
                result.members.add(RevisitDirectExtendMember(member, extendEntry[1]))
                if (member.TestAttr(Attribute.PUBLIC)) {
                    members.add(member)
                }
            }
        }
        let decl = extends[0][0]
        decl.hash.srcUse = ASTHasher.SrcUseHash(decl)
        result.srcUse = decl.hash.srcUse
        decl.hash.sig = ASTHasher.SigHash(decl)
        result.sigHash = decl.hash.sig
        decl.hash.bodyHash = ASTHasher.HashMemberAPIs(members)
        result.bodyHash = decl.hash.bodyHash
        result.gvid = GlobalVarIndex(GetTrimmedPath(decl.curFile), extends[0][1])
        decl.hash.gvid = result.gvid.id
        result.astKind = UInt8(ASTKindIndex(decl.astKind))
        result.isGV = false
        return result
    }

    private func WalkDecl(decl: Decl): Unit {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (extendDecl.inheritedTypes.isEmpty()) {
                extendDecl.rawMangleName = mangler.Mangle(extendDecl)
                if (!directExtends.contains(extendDecl.rawMangleName)) {
                    directExtends[extendDecl.rawMangleName] = ArrayList<(ExtendDecl, Int64)>()
                    order.add(decl)
                }
                directExtends[extendDecl.rawMangleName].add((extendDecl, gid))
                for (member in extendDecl.GetMemberDeclPtrs()) {
                    PrevisitDirectExtendMember(member)
                }
                return
            }
        }
        order.add(decl)
        let declCache = VisitTopLevel(decl)
        ret[decl.rawMangleName] = declCache
        CollectDecl(decl)
    }

    private static func CombineDeclHash(acc: UInt64, decl: Decl): UInt64 {
        var result = ASTHasher.CombineHash(acc, SipHash.GetHashValue(decl.rawMangleName))
        result = ASTHasher.CombineHash(result, ASTHasher.SigHash(decl))
        result = ASTHasher.CombineHash(result, ASTHasher.SrcUseHash(decl))
        return result
    }

    private func VisitMemberVariables(decl: Decl): UInt64 {
        var hashed: UInt64 = 0u64
        var primaryCtor: Option<PrimaryCtorDecl> = None
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.astKind == ASTKind.VAR_DECL) {
                if (IsInstance(member)) {
                    hashed = CombineDeclHash(hashed, member)
                    let memberVar = (member as VarDecl).getOrThrow()
                    if (let None <- memberVar.typeNode) {
                        hashed = ASTHasher.CombineHash(hashed, ASTHasher.BodyHash(memberVar, srcInfo: (true, true)))
                    }
                }
            } else if (member.astKind == ASTKind.PRIMARY_CTOR_DECL) {
                primaryCtor = member as PrimaryCtorDecl
            }
        }
        if (let Some(pc) <- primaryCtor) {
            if (let Some(funcBody) <- pc.funcBody) {
                for (paramList in funcBody.paramLists) {
                    for (param in paramList.params) {
                        if (param.isMemberParam) {
                            hashed = CombineDeclHash(hashed, param)
                        }
                    }
                }
            }
        }
        return hashed
    }

    private func VisitEnumConstructors(decl: EnumDecl): UInt64 {
        var hashed = SipHash.GetHashValue(decl.hasEllipsis)
        for (constructor in decl.constructors) {
            hashed = CombineDeclHash(hashed, constructor)
        }
        return hashed
    }

    private func VirtualHashOfInterface(decl: Decl): UInt64 {
        var hashed: UInt64 = 0u64
        let allMemberFuncs = ArrayList<Decl>()
        for (member in decl.GetMemberDeclPtrs()) {
            if (member.astKind == ASTKind.FUNC_DECL) {
                allMemberFuncs.add(member)
            } else if (let Some(propDecl) <- (member as PropDecl)) {
                allMemberFuncs.add(propDecl)
                for (getter in propDecl.getters) {
                    allMemberFuncs.add(getter)
                }
                for (setter in propDecl.setters) {
                    allMemberFuncs.add(setter)
                }
            }
        }
        sort(allMemberFuncs, by: { left: Decl, right: Decl =>
            if (left.rawMangleName < right.rawMangleName) {
                Ordering.LT
            } else if (left.rawMangleName > right.rawMangleName) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (member in allMemberFuncs) {
            hashed = CombineDeclHash(hashed, member)
            if (IsUntyped(member)) {
                hashed = ASTHasher.CombineHash(hashed, ASTHasher.BodyHash(member, srcInfo: (false, false)))
            }
        }
        return hashed
    }

    private func VisitVarWithPattern(decl: VarWithPatternDecl): Unit {
        CJC_NULLPTR_CHECK(decl.irrefutablePattern)
        Walker(decl.irrefutablePattern.getOrThrow(), visitPre: { node: Node =>
            if (let Some(varDecl) <- (node as VarDecl)) {
                WalkDecl(varDecl)
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
    }

    private func VisitTopLevelDeclMembers(decl: Decl, result: TopLevelDeclCache): Unit {
        for (member in decl.GetMemberDeclPtrs()) {
            if (IsStaticVar(member)) {
                result.members.add(VisitMember(member))
            }
        }
        for (member in decl.GetMemberDeclPtrs()) {
            if (!IsStaticVar(member)) {
                result.members.add(VisitMember(member))
                if (let Some(primaryCtor) <- (member as PrimaryCtorDecl)) {
                    if (let Some(funcBody) <- primaryCtor.funcBody) {
                        if (!funcBody.paramLists.isEmpty()) {
                            for (param in funcBody.paramLists[0].params) {
                                if (param.isMemberParam) {
                                    result.members.add(VisitMember(param))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func IsDirectExtend(decl: Decl): Bool {
        if (decl.astKind != ASTKind.EXTEND_DECL) {
            return false
        }
        return (decl as ExtendDecl).getOrThrow().inheritedTypes.isEmpty()
    }

    private func PrevisitDirectExtendMember(decl: Decl): Unit {
        for (member in GetMembers(decl)) {
            PrevisitDirectExtendMember(member)
        }
        decl.rawMangleName = mangler.Mangle(decl)
        CollectDecl(decl)
        decl.hash.srcUse = ASTHasher.SrcUseHash(decl)
        decl.hash.bodyHash = ASTHasher.BodyHash(decl, srcInfo: srcInfo)
        decl.hash.sig = ASTHasher.SigHash(decl)
        decl.hash.gvid = gid
        if (IsOOEAffectedDecl(decl)) {
            CJC_NULLPTR_CHECK(curFile)
            curFile.getOrThrow().add(decl)
        }
    }

    private func VisitTopLevelImpl1(decl: Decl, result: TopLevelDeclCache): Unit {
        if (decl.astKind == ASTKind.ENUM_DECL) {
            result.instVarHash = VisitEnumConstructors((decl as EnumDecl).getOrThrow())
        } else if (decl.astKind == ASTKind.INTERFACE_DECL) {
            result.virtHash = VirtualHashOfInterface(decl)
        } else if (decl.astKind == ASTKind.CLASS_DECL) {
            result.virtHash = ASTHasher.VirtualHash((decl as ClassDecl).getOrThrow())
            result.instVarHash = VisitMemberVariables(decl)
        } else if (decl.astKind == ASTKind.STRUCT_DECL) {
            result.instVarHash = VisitMemberVariables(decl)
        } else if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            gid++
            invp = true
            VisitVarWithPattern((decl as VarWithPatternDecl).getOrThrow())
            invp = false
            result.isGV = true
            CJC_ASSERT(IsOOEAffectedDecl(decl))
            CJC_NULLPTR_CHECK(curFile)
            curFile.getOrThrow().add(decl)
        } else if (decl.astKind == ASTKind.VAR_DECL) {
            result.isGV = !invp
            if (!invp) {
                gid++
                if (IsOOEAffectedDecl(decl)) {
                    CJC_NULLPTR_CHECK(curFile)
                    curFile.getOrThrow().add(decl)
                }
            }
        } else if (decl.astKind == ASTKind.FUNC_DECL) {
            if (IsOOEAffectedDecl(decl)) {
                CJC_NULLPTR_CHECK(curFile)
                curFile.getOrThrow().add(decl)
            }
        } else if (decl.astKind == ASTKind.MAIN_DECL || decl.astKind == ASTKind.MACRO_DECL) {
            CJC_NULLPTR_CHECK(curFile)
            curFile.getOrThrow().add(decl)
        }
    }

    private func VisitTopLevel(decl: Decl): TopLevelDeclCache {
        let result = TopLevelDeclCache()
        VisitTopLevelDeclMembers(decl, result)
        decl.rawMangleName = mangler.Mangle(decl)
        decl.hash.srcUse = ASTHasher.SrcUseHash(decl)
        result.srcUse = decl.hash.srcUse
        decl.hash.bodyHash = ASTHasher.BodyHash(decl, srcInfo: srcInfo)
        result.bodyHash = decl.hash.bodyHash
        decl.hash.sig = ASTHasher.SigHash(decl)
        result.sigHash = decl.hash.sig
        VisitTopLevelImpl1(decl, result)
        decl.hash.instVar = result.instVarHash
        decl.hash.virt = result.virtHash
        result.gvid = GlobalVarIndex(GetTrimmedPath(decl.curFile), gid)
        decl.hash.gvid = gid
        result.astKind = UInt8(ASTKindIndex(decl.astKind))
        return result
    }

    private func VisitMember(decl: Decl): MemberDeclCache {
        let result = MemberDeclCache()
        for (member in GetMembers(decl)) {
            result.members.add(VisitMember(member))
        }
        decl.rawMangleName = mangler.Mangle(decl)
        result.rawMangle = decl.rawMangleName
        CollectDecl(decl)
        decl.hash.srcUse = ASTHasher.SrcUseHash(decl)
        result.srcUse = decl.hash.srcUse
        decl.hash.bodyHash = ASTHasher.BodyHash(decl, srcInfo: srcInfo)
        result.bodyHash = decl.hash.bodyHash
        decl.hash.sig = ASTHasher.SigHash(decl)
        result.sigHash = decl.hash.sig
        if (IsStaticVar(decl)) {
            gid++
        }
        result.gvid = GlobalVarIndex(GetTrimmedPath(decl.curFile), gid)
        decl.hash.gvid = gid
        if (IsOOEAffectedDecl(decl)) {
            CJC_NULLPTR_CHECK(curFile)
            curFile.getOrThrow().add(decl)
        }
        if (IsMemberParam(decl)) {
            result.astKind = UInt8(ASTKindIndex(ASTKind.VAR_DECL))
            result.isGV = false
        } else {
            result.astKind = UInt8(ASTKindIndex(decl.astKind))
            result.isGV = decl.astKind == ASTKind.VAR_DECL && decl.TestAttr(Attribute.STATIC)
        }
        return result
    }

    private func RevisitDirectExtendMember(decl: Decl, gvid: Int64): MemberDeclCache {
        let result = MemberDeclCache()
        for (member in GetMembers(decl)) {
            result.members.add(RevisitDirectExtendMember(member, gvid))
        }
        result.rawMangle = decl.rawMangleName
        result.srcUse = decl.hash.srcUse
        result.bodyHash = decl.hash.bodyHash
        result.sigHash = decl.hash.sig
        result.astKind = UInt8(ASTKindIndex(decl.astKind))
        result.gvid.file = GetTrimmedPath(decl.curFile)
        decl.hash.gvid = gvid
        result.gvid.id = gvid
        for (member in decl.GetMemberDeclPtrs()) {
            member.hash.gvid = gvid
        }
        for (member in result.members) {
            member.gvid.id = gvid
        }
        return result
    }

    private func CollectDecl(decl: Decl): Unit {
        let mangled = decl.rawMangleName
        if (let Some(oldDecl) <- mangled2Decl.get(mangled)) {
            duplicatedMangleNames.add(decl)
            duplicatedMangleNames.add(oldDecl)
        }
        mangled2Decl[mangled] = decl
    }
}
