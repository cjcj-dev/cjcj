package cjcj::incremental_compilation

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset, FlatBufferString, VerifierTemplate}

// CachedASTFormat.fbs:13-124. One non-default value is written and read for
// every one of the schema's 65 fields.
@Test
class CachedASTFormatBindingsTest {
    @TestCase
    func roundTripAllFields(): Unit {
        let builder = FlatBufferBuilder()

        let depValues = ArrayList<FlatBufferOffset>()
        depValues.add(builder.CreateString("dependency"))
        let depVector = builder.CreateVectorOffsets(depValues)
        let declDep = CreateDeclDep(builder, builder.CreateString("decl"), depVector)

        let effectedValues = ArrayList<FlatBufferOffset>()
        effectedValues.add(builder.CreateString("effected"))
        let effectedVector = builder.CreateVectorOffsets(effectedValues)
        let effectMap = CreateEffectMap(builder, builder.CreateString("source"), effectedVector)

        let virtualDep = CreateVirtualDep(builder, builder.CreateString("raw"), builder.CreateString("wrapper"))
        let varInitDep = CreateVirtualDep(builder, builder.CreateString("initRaw"), builder.CreateString("initWrapper"))

        let conditionValues = ArrayList<Bool>()
        conditionValues.add(true)
        conditionValues.add(false)
        let conditionVector = builder.CreateVectorBool(conditionValues)
        let parentValues = ArrayList<FlatBufferOffset>()
        parentValues.add(builder.CreateString("parent"))
        let parentVector = builder.CreateVectorOffsets(parentValues)
        let qualifierValues = ArrayList<FlatBufferOffset>()
        qualifierValues.add(builder.CreateString("qualifier"))
        let qualifierVector = builder.CreateVectorOffsets(qualifierValues)
        let nameInfo = CreateNameInfo(builder, builder.CreateString("name"), conditionVector, parentVector, qualifierVector)

        let usedDeclValues = ArrayList<FlatBufferOffset>()
        usedDeclValues.add(builder.CreateString("usedDecl"))
        let usedDeclVector = builder.CreateVectorOffsets(usedDeclValues)
        let usedNameValues = ArrayList<FlatBufferOffset>()
        usedNameValues.add(nameInfo)
        let usedNameVector = builder.CreateVectorOffsets(usedNameValues)
        let useInfo = CreateUseInfo(builder, usedDeclVector, usedNameVector)

        let boxedValues = ArrayList<FlatBufferOffset>()
        boxedValues.add(builder.CreateString("boxed"))
        let boxedVector = builder.CreateVectorOffsets(boxedValues)
        let usage = CreateUsage(builder, builder.CreateString("usageDef"), useInfo, useInfo, boxedVector)

        let inheritedValues = ArrayList<FlatBufferOffset>()
        inheritedValues.add(builder.CreateString("inherited"))
        let inheritedVector = builder.CreateVectorOffsets(inheritedValues)
        let extendsValues = ArrayList<FlatBufferOffset>()
        extendsValues.add(builder.CreateString("relationExtend"))
        let relationExtendsVector = builder.CreateVectorOffsets(extendsValues)
        let interfaceValues = ArrayList<FlatBufferOffset>()
        interfaceValues.add(builder.CreateString("extendInterface"))
        let interfaceVector = builder.CreateVectorOffsets(interfaceValues)
        let relation = CreateRelation(builder, builder.CreateString("relationDef"), inheritedVector,
            relationExtendsVector, interfaceVector)

        let relatedValues = ArrayList<FlatBufferOffset>()
        relatedValues.add(builder.CreateString("related"))
        let relatedVector = builder.CreateVectorOffsets(relatedValues)
        let compilerAddedUsage = CreateCompilerAddedUsage(builder, builder.CreateString("compilerDef"), relatedVector)

        let usageValues = ArrayList<FlatBufferOffset>()
        usageValues.add(usage)
        let usageVector = builder.CreateVectorOffsets(usageValues)
        let relationValues = ArrayList<FlatBufferOffset>()
        relationValues.add(relation)
        let relationVector = builder.CreateVectorOffsets(relationValues)
        let builtInRelationValues = ArrayList<FlatBufferOffset>()
        builtInRelationValues.add(relation)
        let builtInRelationVector = builder.CreateVectorOffsets(builtInRelationValues)
        let compilerUsageValues = ArrayList<FlatBufferOffset>()
        compilerUsageValues.add(compilerAddedUsage)
        let compilerUsageVector = builder.CreateVectorOffsets(compilerUsageValues)
        let semanticInfo = CreateSemanticInfo(builder, usageVector, relationVector,
            builtInRelationVector, compilerUsageVector)

        let gvid = CreateGlobalVarIndex(builder, builder.CreateString("file.cj"), 37)
        let leafMember = CreateMemberDecl(builder, builder.CreateString("leaf"), 1u64, 2u64, 3u64,
            4u8, false, gvid, 0u32, builder.CreateString("leafCg"))
        let memberValues = ArrayList<FlatBufferOffset>()
        memberValues.add(leafMember)
        let memberVector = builder.CreateVectorOffsets(memberValues)
        let member = CreateMemberDecl(builder, builder.CreateString("member"), 11u64, 12u64, 13u64,
            14u8, true, gvid, memberVector, builder.CreateString("memberCg"))
        let topMemberValues = ArrayList<FlatBufferOffset>()
        topMemberValues.add(member)
        let topMemberVector = builder.CreateVectorOffsets(topMemberValues)
        let topExtendsValues = ArrayList<FlatBufferOffset>()
        topExtendsValues.add(builder.CreateString("topExtend"))
        let topExtendsVector = builder.CreateVectorOffsets(topExtendsValues)
        let topDecl = CreateTopDecl(builder, builder.CreateString("top"), 21u64, 22u64, 23u64,
            24u8, true, 25u64, 26u64, gvid, topMemberVector, topExtendsVector,
            builder.CreateString("topCg"))

        let compileOptionValues = ArrayList<FlatBufferOffset>()
        compileOptionValues.add(builder.CreateString("--opt"))
        let compileOptionVector = builder.CreateVectorOffsets(compileOptionValues)
        let topValues = ArrayList<FlatBufferOffset>()
        topValues.add(topDecl)
        let topVector = builder.CreateVectorOffsets(topValues)
        let importedValues = ArrayList<FlatBufferOffset>()
        importedValues.add(topDecl)
        let importedVector = builder.CreateVectorOffsets(importedValues)
        let declDepValues = ArrayList<FlatBufferOffset>()
        declDepValues.add(declDep)
        let declDepVector = builder.CreateVectorOffsets(declDepValues)
        let effectValues = ArrayList<FlatBufferOffset>()
        effectValues.add(effectMap)
        let effectVector = builder.CreateVectorOffsets(effectValues)
        let virtualValues = ArrayList<FlatBufferOffset>()
        virtualValues.add(virtualDep)
        let virtualVector = builder.CreateVectorOffsets(virtualValues)
        let initValues = ArrayList<FlatBufferOffset>()
        initValues.add(varInitDep)
        let initVector = builder.CreateVectorOffsets(initValues)
        let ccOutValues = ArrayList<FlatBufferOffset>()
        ccOutValues.add(builder.CreateString("ccOut"))
        let ccOutVector = builder.CreateVectorOffsets(ccOutValues)
        let bitcodeValues = ArrayList<FlatBufferOffset>()
        bitcodeValues.add(builder.CreateString("pkg.bc"))
        let bitcodeVector = builder.CreateVectorOffsets(bitcodeValues)
        let rootOffset = CreateHashedPackage(builder, builder.CreateString("1.2.3"),
            builder.CreateString("pkg"), 31u64, compileOptionVector, topVector, importedVector,
            declDepVector, effectVector, virtualVector, initVector, ccOutVector, 32u64, 33u64,
            34u64, semanticInfo, bitcodeVector)
        let bytes = FinishHashedPackageBuffer(builder, rootOffset)

        let root = GetHashedPackage(bytes)
        let readTop = CachedASTFormat_TopDecl(bytes,
            (root.topDecls().getOrThrow().Get(0u32) as Int64).getOrThrow())
        let readMember = CachedASTFormat_MemberDecl(bytes,
            (readTop.members().getOrThrow().Get(0u32) as Int64).getOrThrow())
        let readGvid = readMember.gvid().getOrThrow()
        let readDeclDep = CachedASTFormat_DeclDep(bytes,
            (root.varAndFunc().getOrThrow().Get(0u32) as Int64).getOrThrow())
        let readEffectMap = CachedASTFormat_EffectMap(bytes,
            (root.chirOptInfo().getOrThrow().Get(0u32) as Int64).getOrThrow())
        let readVirtualDep = CachedASTFormat_VirtualDep(bytes,
            (root.virtualDep().getOrThrow().Get(0u32) as Int64).getOrThrow())
        let readUsage = CachedASTFormat_Usage(bytes,
            (root.semanticInfo().getOrThrow().usages().getOrThrow().Get(0u32) as Int64).getOrThrow())
        let readUseInfo = readUsage.apiUsage().getOrThrow()
        let readNameInfo = CachedASTFormat_NameInfo(bytes,
            (readUseInfo.usedNames().getOrThrow().Get(0u32) as Int64).getOrThrow())
        let readRelation = CachedASTFormat_Relation(bytes,
            (root.semanticInfo().getOrThrow().relations().getOrThrow().Get(0u32) as Int64).getOrThrow())
        let readCompilerUsage = CachedASTFormat_CompilerAddedUsage(bytes,
            (root.semanticInfo().getOrThrow().compilerAddedUsages().getOrThrow().Get(0u32) as Int64).getOrThrow())

        @Expect(readDeclDep.decl().getOrThrow().str(), "decl")
        @Expect(FlatBufferString(bytes, (readDeclDep.dependency().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "dependency")
        @Expect(readEffectMap.srcDecl().getOrThrow().str(), "source")
        @Expect(FlatBufferString(bytes, (readEffectMap.effectedDecls().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "effected")
        @Expect(readVirtualDep.raw().getOrThrow().str(), "raw")
        @Expect(readVirtualDep.wrapper().getOrThrow().str(), "wrapper")
        @Expect(readUsage.definition().getOrThrow().str(), "usageDef")
        @Expect(readUsage.apiUsage().isSome(), true)
        @Expect(readUsage.bodyUsage().isSome(), true)
        @Expect(FlatBufferString(bytes, (readUsage.boxedTypes().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "boxed")
        @Expect(FlatBufferString(bytes, (readUseInfo.usedDecls().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "usedDecl")
        @Expect(readUseInfo.usedNames().getOrThrow().size(), 1u32)
        @Expect(readNameInfo.name().getOrThrow().str(), "name")
        @Expect((readNameInfo.conditions().getOrThrow().Get(0u32) as Bool).getOrThrow(), true)
        @Expect(FlatBufferString(bytes, (readNameInfo.parentDecls().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "parent")
        @Expect(FlatBufferString(bytes, (readNameInfo.qualifiers().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "qualifier")
        @Expect(readRelation.definition().getOrThrow().str(), "relationDef")
        @Expect(FlatBufferString(bytes, (readRelation.inherited().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "inherited")
        @Expect(FlatBufferString(bytes, (readRelation.extends().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "relationExtend")
        @Expect(FlatBufferString(bytes, (readRelation.extendInterfaces().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "extendInterface")
        @Expect(readCompilerUsage.definition().getOrThrow().str(), "compilerDef")
        @Expect(FlatBufferString(bytes, (readCompilerUsage.related().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "related")
        @Expect(root.semanticInfo().getOrThrow().usages().getOrThrow().size(), 1u32)
        @Expect(root.semanticInfo().getOrThrow().relations().getOrThrow().size(), 1u32)
        @Expect(root.semanticInfo().getOrThrow().builtInTypeRelations().getOrThrow().size(), 1u32)
        @Expect(root.semanticInfo().getOrThrow().compilerAddedUsages().getOrThrow().size(), 1u32)
        @Expect(readGvid.file().getOrThrow().str(), "file.cj")
        @Expect(readGvid.id(), 37i32)
        @Expect(readMember.mangle().getOrThrow().str(), "member")
        @Expect(readMember.sig(), 11u64)
        @Expect(readMember.srcUse(), 12u64)
        @Expect(readMember.body(), 13u64)
        @Expect(readMember.`type`(), 14u8)
        @Expect(readMember.isGV(), true)
        @Expect(readMember.gvid().isSome(), true)
        @Expect(readMember.members().getOrThrow().size(), 1u32)
        @Expect(readMember.cgMangle().getOrThrow().str(), "memberCg")
        @Expect(readTop.mangle().getOrThrow().str(), "top")
        @Expect(readTop.sig(), 21u64)
        @Expect(readTop.srcUse(), 22u64)
        @Expect(readTop.body(), 23u64)
        @Expect(readTop.`type`(), 24u8)
        @Expect(readTop.isGV(), true)
        @Expect(readTop.instVar(), 25u64)
        @Expect(readTop.virt(), 26u64)
        @Expect(readTop.gvid().isSome(), true)
        @Expect(readTop.members().getOrThrow().size(), 1u32)
        @Expect(FlatBufferString(bytes, (readTop.extends().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "topExtend")
        @Expect(readTop.cgMangle().getOrThrow().str(), "topCg")
        @Expect(root.version().getOrThrow().str(), "1.2.3")
        @Expect(root.packageName().getOrThrow().str(), "pkg")
        @Expect(root.specs(), 31u64)
        @Expect(FlatBufferString(bytes, (root.compileOptionArgs().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "--opt")
        @Expect(root.topDecls().getOrThrow().size(), 1u32)
        @Expect(root.importedDecls().getOrThrow().size(), 1u32)
        @Expect(root.varAndFunc().getOrThrow().size(), 1u32)
        @Expect(root.chirOptInfo().getOrThrow().size(), 1u32)
        @Expect(root.virtualDep().getOrThrow().size(), 1u32)
        @Expect(root.varInitDep().getOrThrow().size(), 1u32)
        @Expect(FlatBufferString(bytes, (root.ccOutFuncs().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "ccOut")
        @Expect(root.lambdaCounter(), 32u64)
        @Expect(root.envClassCounter(), 33u64)
        @Expect(root.strLitCounter(), 34u64)
        @Expect(root.semanticInfo().isSome(), true)
        @Expect(FlatBufferString(bytes, (root.bitcodeFilesName().getOrThrow().Get(0u32) as Int64).getOrThrow()).str(), "pkg.bc")
        @Expect(HashedPackageBufferHasIdentifier(bytes), true)
        @Expect(VerifyHashedPackageBuffer(bytes, VerifierTemplate(bytes)), true)
    }
}
