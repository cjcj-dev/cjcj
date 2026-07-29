package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::basic.Warningln
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{GenericConfigInfo, GetActualTypeKind, GetCangjieLibName,
    GetForeignNameAnnotation, GetGenericActualType}
import cjcj::utils.{CJC_ASSERT, FileUtil, OBJECT_NAME}

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/Transpiler.h:32-116 and
// Transpiler.cpp:30-567.
public class Transpiler {
    private static let DEFAULT_OUTPUT_DIR: String = "objc-gen"
    private static let DEFAULT_OUTPUT_DIR_WARNING: String =
        "default value objc-gen of Objective-C generated sources directory will be changed in" +
        " next Cangjie SDK release"

    private let sourceBody = StringBuilder()
    private let headerBody = StringBuilder()
    private let dependenciesStream = StringBuilder()
    private let sourceImport = StringBuilder()
    private let headerImport = StringBuilder()
    private let staticReferences = StringBuilder()
    private let funcInitialization = StringBuilder()
    private let initialize = StringBuilder()
    private let ctors = StringBuilder()
    private let defaultFuncImpls = StringBuilder()

    private let dependencies = HashSet<Decl>()
    private let typedefs = HashSet<String>()

    private let outputFilePath: String
    private let cjLibOutputPath: String
    private let decl: Decl
    private let ctx: InteropContext
    private let interopType: InteropType
    private let genericConfig: Option<GenericConfigInfo>
    private let isGenericGlueCode: Bool

    // C++ Transpiler.cpp:30-43.
    public init(ctx: InteropContext, declArg: Decl, outputFilePath: String,
        cjLibOutputPath: String, interopType: InteropType) {
        this.ctx = ctx
        this.decl = declArg
        this.outputFilePath = if (outputFilePath.isEmpty()) { DEFAULT_OUTPUT_DIR } else { outputFilePath }
        this.cjLibOutputPath = cjLibOutputPath
        this.interopType = interopType
        this.genericConfig = None
        this.isGenericGlueCode = false
        if (outputFilePath.isEmpty()) {
            Warningln(DEFAULT_OUTPUT_DIR_WARNING)
        }
    }

    // C++ Transpiler.cpp:45-61.
    public init(ctx: InteropContext, declArg: Decl, outputFilePath: String,
        cjLibOutputPath: String, interopType: InteropType, genericConfig: GenericConfigInfo,
        isGenericGlueCode: Bool) {
        this.ctx = ctx
        this.decl = declArg
        this.outputFilePath = if (outputFilePath.isEmpty()) { DEFAULT_OUTPUT_DIR } else { outputFilePath }
        this.cjLibOutputPath = cjLibOutputPath
        this.interopType = interopType
        this.genericConfig = Some(genericConfig)
        this.isGenericGlueCode = isGenericGlueCode
        if (outputFilePath.isEmpty()) {
            Warningln(DEFAULT_OUTPUT_DIR_WARNING)
        }
    }

    // C++ Transpiler.cpp:63-84.
    private func CheckFunction(arg: Decl): Bool {
        if (ctx.factory.IsGeneratedMember(arg)) {
            return false
        }
        if (!arg.TestAttr(Attribute.PUBLIC)) {
            return false
        }
        if (let InteropType.CJ_Mapping <- interopType) {
            if (!TypeMapper.IsObjCCJMappingMember(arg) || arg.IsOpen()) {
                return false
            }
        }
        if (IsNotThisActualTyFunc(arg)) {
            return false
        }
        if (arg.astKind == ASTKind.FUNC_DECL &&
            !arg.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.FINALIZER)) {
            return true
        }
        return false
    }

    // C++ Transpiler.cpp:86-119.
    private func CheckCtor(arg: Decl): Bool {
        if (!arg.TestAttr(Attribute.PUBLIC)) {
            return false
        }
        if (ctx.factory.IsGeneratedMember(arg)) {
            return false
        }
        if (!arg.TestAttr(Attribute.CONSTRUCTOR)) {
            return false
        }
        if (arg.astKind != ASTKind.FUNC_DECL) {
            return false
        }
        let funcDecl = (arg as FuncDecl).getOrThrow()
        if (let None <- funcDecl.funcBody) {
            return false
        }
        if (let InteropType.CJ_Mapping <- interopType) {
            if (!TypeMapper.IsObjCCJMappingMember(arg)) {
                return false
            }
        }
        return true
    }

    // C++ Transpiler.cpp:121-142.
    private func CheckProp(arg: Decl): Bool {
        if (arg.astKind != ASTKind.VAR_DECL && arg.astKind != ASTKind.PROP_DECL) {
            return false
        }
        if (!arg.TestAttr(Attribute.PUBLIC)) {
            return false
        }
        if (ctx.factory.IsGeneratedNativeHandleField(arg)) {
            return false
        }
        if (let InteropType.CJ_Mapping <- interopType) {
            if (!TypeMapper.IsObjCCJMappingMember(arg)) {
                return false
            }
        }
        return true
    }

    // C++ Transpiler.cpp:144-163.
    private func CollectDependencies(ty: Ty): Unit {
        if (TypeMapper.IsObjCObjectType(ty)) {
            if (TypeMapper.IsObjCId(ty)) {
                return
            }
            if (!ty.IsCoreOptionType()) {
                let declTy = Ty.GetDeclOfTy(Some(ty)).getOrThrow()
                if (declTy.identifier.Val() != ctx.nameGenerator.GetObjCDeclName(decl)) {
                    dependencies.add(declTy)
                }
            }
        }
        for (typeArg in ty.typeArgs) {
            CollectDependencies(typeArg)
        }
    }

    // C++ Transpiler.cpp:165-179.
    private func FormatCJLibName(): String {
        var cjLibName = GetCangjieLibName(cjLibOutputPath, decl.fullPackageName, trimmed: false)
        if (!cjLibName.startsWith("lib")) {
            cjLibName = "lib" + cjLibName
        }
        let sharedLibraryExtension = ctx.sharedLibraryExtension
        if (let Some(extIdx) <- cjLibName.lastIndexOf(".")) {
            if (cjLibName[extIdx..] != sharedLibraryExtension) {
                cjLibName += sharedLibraryExtension
            }
        } else {
            cjLibName += sharedLibraryExtension
        }
        return cjLibName
    }

    // C++ Transpiler.cpp:181-200.
    private func ProcessPreamble(metainfo: EmittableObjCClassMetainfo,
        hasImplicitImplParent: Bool): Unit {
        Emitter.EmitFileImport(sourceImport, metainfo.className)
        Emitter.EmitSourceImport(sourceImport)
        Emitter.EmitHeaderImport(headerImport)
        for (interfaceName in metainfo.interfaces) {
            Emitter.EmitFileImport(headerImport, interfaceName)
        }
        Emitter.EmitInterfaceDeclaration(headerBody, metainfo)
        Emitter.EmitFileImport(headerImport, metainfo.superclassName)
        Emitter.EmitImplementationDeclaration(sourceBody, metainfo)
        Emitter.EmitSyntheticHeaderFunctionDecls(headerBody)
        if (!hasImplicitImplParent) {
            Emitter.EmitSyntheticRefsDealloc(headerBody)
        }
    }

    // C++ Transpiler.cpp:202-219.
    private func ProcessSuffix(cjLibName: String, metainfo: EmittableObjCClassMetainfo,
        hasImplicitImplParent: Bool): Unit {
        Emitter.EmitAdditionalStaticReferences(staticReferences)
        if (!hasImplicitImplParent) {
            let deleteCJObjectMangledName = ctx.nameGenerator.GenerateDeleteCjObjectName(decl)
            Emitter.EmitDeleteCJObject(defaultFuncImpls, deleteCJObjectMangledName)
            Emitter.EmitDeleteCJObjectInitialization(funcInitialization, deleteCJObjectMangledName)
            Emitter.EmitDealloc(defaultFuncImpls)
        }
        Emitter.EmitInitialize(initialize, cjLibName, metainfo)
    }

    // C++ Transpiler.cpp:221-337.
    private func ProcessMemberDecls(metainfo: EmittableObjCClassMetainfo,
        classDecl: Option<ClassDecl>): Unit {
        let generatedCtors = ArrayList<ArrayList<String>>()
        for (declPtr in decl.GetMemberDecls()) {
            match (declPtr.astKind) {
                case ASTKind.FUNC_DECL =>
                    if (CheckFunction(declPtr)) {
                        let funcDecl = (declPtr as FuncDecl).getOrThrow()
                        let funcMeta = GetObjCFuncMetainfo(funcDecl)
                        Emitter.EmitObjCFuncHeaderFunctionDecl(headerBody, funcMeta)
                        Emitter.EmitObjCFuncInitialization(funcInitialization, funcMeta)
                        Emitter.EmitDefaultFunctionImplementation(defaultFuncImpls, funcMeta)
                        CollectDependencies(funcDecl.GetTy().getOrThrow())
                    }
                    if (CheckCtor(declPtr)) {
                        let funcDecl = (declPtr as FuncDecl).getOrThrow()
                        if (let Some(funcBody) <- funcDecl.funcBody) {
                            if (funcBody.retType.isSome()) {
                                let funcMeta = GetObjCCtorMetainfo(funcDecl)
                                Emitter.EmitCtor(ctors, funcMeta, metainfo)
                                Emitter.EmitObjCFuncInitialization(funcInitialization, funcMeta)
                                Emitter.EmitObjCFuncHeaderFunctionDecl(headerBody, funcMeta)
                                CollectDependencies(funcDecl.GetTy().getOrThrow())
                                if (let InteropType.ObjC_Mirror <- interopType) {
                                    generatedCtors.add(funcMeta.selectorComponents)
                                }
                            }
                        }
                    }
                case ASTKind.VAR_DECL =>
                    if (CheckProp(declPtr)) {
                        let propDecl = (declPtr as VarDeclAbstract).getOrThrow()
                        let propMeta = GetObjCPropMetainfoFromProp(propDecl)
                        Emitter.EmitObjCFuncInitialization(funcInitialization, propMeta.getter)
                        Emitter.EmitDefaultFunctionImplementation(defaultFuncImpls, propMeta.getter)
                        Emitter.EmitProperty(headerBody, propMeta)
                        Emitter.EmitObjCFuncHeaderFunctionDecl(headerBody, propMeta.getter)
                        if (propMeta.isReadwrite) {
                            Emitter.EmitObjCFuncInitialization(funcInitialization, propMeta.setter)
                            Emitter.EmitDefaultFunctionImplementation(defaultFuncImpls, propMeta.setter)
                            Emitter.EmitObjCFuncHeaderFunctionDecl(headerBody, propMeta.setter)
                        }
                        CollectDependencies(propDecl.GetTy().getOrThrow())
                    }
                case ASTKind.PROP_DECL =>
                    if (CheckProp(declPtr)) {
                        let propDecl = (declPtr as VarDeclAbstract).getOrThrow()
                        let propMeta = GetObjCPropMetainfoFromProp(propDecl)
                        Emitter.EmitObjCFuncInitialization(funcInitialization, propMeta.getter)
                        Emitter.EmitDefaultFunctionImplementation(defaultFuncImpls, propMeta.getter)
                        Emitter.EmitProperty(headerBody, propMeta)
                        Emitter.EmitObjCFuncHeaderFunctionDecl(headerBody, propMeta.getter)
                        if (propMeta.isReadwrite) {
                            Emitter.EmitObjCFuncInitialization(funcInitialization, propMeta.setter)
                            Emitter.EmitDefaultFunctionImplementation(defaultFuncImpls, propMeta.setter)
                            Emitter.EmitObjCFuncHeaderFunctionDecl(headerBody, propMeta.setter)
                        }
                        CollectDependencies(propDecl.GetTy().getOrThrow())
                    }
                case _ => ()
            }
        }

        for (declPtr in ctx.genDecls) {
            if (declPtr.curFile != decl.curFile || !declPtr.TestAttr(Attribute.C) ||
                declPtr.TestAttr(Attribute.FOREIGN)) {
                continue
            }
            if (IsNotThisActualTyFunc(declPtr)) {
                continue
            }
            if (declPtr.astKind == ASTKind.FUNC_DECL && CheckFunction(declPtr)) {
                Emitter.EmitObjCFuncStaticReference(staticReferences,
                    GetObjCFuncMetainfo((declPtr as FuncDecl).getOrThrow(), mangled: true))
            }
        }

        for (dependency in dependencies) {
            let identifier = ctx.nameGenerator.GetObjCDeclName(dependency)
            if (dependency.astKind == ASTKind.INTERFACE_DECL) {
                Emitter.EmitForwardDeclarationProtocol(dependenciesStream, identifier)
            } else {
                Emitter.EmitForwardDeclaration(dependenciesStream, identifier)
            }
            Emitter.EmitFileImport(sourceImport, identifier)
        }
        for (typedef in typedefs) {
            Emitter.EmitTypedef(headerImport, typedef)
        }

        if (let InteropType.ObjC_Mirror <- interopType) {
            if (let Some(concreteClassDecl) <- classDecl) {
                let ctorsToGenerate = ctx.factory.GetAllParentCtors(concreteClassDecl)
                for (ctor in ctorsToGenerate) {
                    if (!ctor.TestAttr(Attribute.PUBLIC) && ctor.outerDecl != Some(decl)) {
                        continue
                    }
                    if (ctx.factory.IsGeneratedMember(ctor)) {
                        continue
                    }
                    let funcBody = ctor.funcBody.getOrThrow()
                    if (funcBody.paramLists[0].params.size > 1 &&
                        NameGenerator.GetUserDefinedObjCName(ctor).isNone()) {
                        continue
                    }
                    let selectorComponents = ctx.nameGenerator.GetObjCDeclSelectorComponents(ctor)
                    if (generatedCtors.contains(selectorComponents)) {
                        continue
                    }
                    var funcMeta = GetObjCFuncMetainfo(ctor)
                    funcMeta.retType = ObjCParamMapper.ID_TYPE
                    Emitter.EmitDoesNotRecognizeSelectorCtor(ctors, funcMeta)
                    Emitter.EmitObjCFuncHeaderFunctionDecl(headerBody, funcMeta)
                    generatedCtors.add(selectorComponents)
                }
            }
        }
    }

    // C++ Transpiler.cpp:368-383.
    public func Generate(): Unit {
        let cjLibName = FormatCJLibName()
        let classDecl = decl as ClassDecl
        let concreteClassDecl = classDecl.getOrThrow()
        let metainfo = GetObjCClassMetainfo(classDecl)
        let hasImplicitImplParent = HasImplSuperClass(concreteClassDecl)
        ProcessPreamble(metainfo, hasImplicitImplParent)
        ProcessMemberDecls(metainfo, classDecl)
        ProcessSuffix(cjLibName, metainfo, hasImplicitImplParent)
        WriteToFile()
    }

    // C++ Transpiler.cpp:386-396.
    private func IsNotThisActualTyFunc(declPtr: Decl): Bool {
        if (let Some(config) <- genericConfig) {
            if (!declPtr.identifier.Val().contains(config.declInstName)) {
                return true
            }
        }
        return false
    }

    // C++ Transpiler.cpp:399-432.
    private func GetObjCClassMetainfo(classDecl: Option<ClassDecl>): EmittableObjCClassMetainfo {
        let concreteClassDecl = classDecl.getOrThrow()
        let className = ctx.nameGenerator.GetObjCDeclName(concreteClassDecl)
        let superClassPtr = concreteClassDecl.GetSuperClassDecl()
        let isClassInheritedFromClass = if (let Some(superClass) <- superClassPtr) {
            superClass.identifier.Val() != OBJECT_NAME
        } else {
            false
        }
        let superclassName = if (isClassInheritedFromClass) {
            ctx.nameGenerator.GetObjCDeclName(superClassPtr.getOrThrow())
        } else {
            ""
        }
        let isFinal = if (let InteropType.CJ_Mapping <- interopType) {
            TypeMapper.IsOneWayMapping(decl) && !decl.IsOpen()
        } else {
            false
        }
        let interfaceNames = ArrayList<String>()
        for (interfaceTy in concreteClassDecl.GetSuperInterfaceTys()) {
            if (!TypeMapper.IsObjCId(interfaceTy)) {
                interfaceNames.add(ctx.nameGenerator.GetObjCDeclName(interfaceTy.decl.getOrThrow()))
            }
        }
        var result = EmittableObjCClassMetainfo()
        result.className = className
        result.superclassName = superclassName
        result.isFinal = isFinal
        result.interfaces = interfaceNames
        return result
    }

    // C++ Transpiler.cpp:434-437.
    private func SkipSetterForValueTypeDecl(declArg: Decl): Bool {
        if (let InteropType.CJ_Mapping <- interopType) {
            return declArg.GetTy().getOrThrow() is StructTy
        }
        return false
    }

    // C++ Transpiler.cpp:439-468.
    private func GetObjCPropMetainfoFromProp(varDecl: VarDeclAbstract): EmittableObjCPropMetainfo {
        var result = EmittableObjCPropMetainfo()
        result.isStatic = varDecl.TestAttr(Attribute.STATIC)
        if (isGenericGlueCode && varDecl.GetTy().getOrThrow().IsGeneric()) {
            let config = genericConfig.getOrThrow()
            let genericActualTy = TypeManager.GetPrimitiveTy(
                GetActualTypeKind(GetGenericActualType(config, varDecl.GetTy().getOrThrow().name)))
            result.`type` = ObjCParamMapper.MapCJTypeToObjCType(typedefs, genericActualTy)
        } else {
            result.`type` = ObjCParamMapper.MapCJTypeToObjCType(typedefs, varDecl.GetTy().getOrThrow())
        }
        result.isReadwrite = varDecl.isVar && !SkipSetterForValueTypeDecl(decl)
        result.name = ctx.nameGenerator.GetObjCDeclName(varDecl)
        let varTy = varDecl.GetTy().getOrThrow()
        let bridge = (TypeMapper.IsObjCObjectType(varTy) || TypeMapper.IsObjCBlock(varTy)) &&
            !TypeMapper.IsObjCCJMapping(varTy)
        result.getter = ObjCParamMapper.GetGetterForProp(result, ctx.nameGenerator.GetObjCGetterName(varDecl),
            ctx.nameGenerator.GetFieldGetterWrapperName((varDecl as VarDecl).getOrThrow()), bridge)
        if (result.isReadwrite) {
            result.setter = ObjCParamMapper.GetSetterForProp(result, varTy,
                ctx.nameGenerator.GetObjCSetterName(varDecl),
                ctx.nameGenerator.GetFieldSetterWrapperName((varDecl as VarDecl).getOrThrow()))
        }
        return result
    }

    // C++ Transpiler.cpp:470-505.
    private func GetObjCFuncMetainfo(funcDecl: FuncDecl, mangled!: Bool = false): EmittableObjCFuncMetainfo {
        var result = EmittableObjCFuncMetainfo()
        result.isStatic = funcDecl.TestAttr(Attribute.STATIC)
        result.selectorComponents = ctx.nameGenerator.GetObjCDeclSelectorComponents(funcDecl)
        result.mangledIdentifier = if (mangled) {
            funcDecl.identifier.Val()
        } else {
            ctx.nameGenerator.GenerateMethodWrapperName(funcDecl)
        }
        result.identifier = result.selectorComponents[0]
        let retTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow().retTy
        result.retType = ObjCParamMapper.MapCJTypeToObjCType(typedefs, retTy)
        let funcBody = funcDecl.funcBody.getOrThrow()
        result.paramsDecl = ObjCParamMapper.GenerateFuncParamLists(typedefs, funcBody.paramLists,
            result.selectorComponents, format: FunctionListFormat.DECLARATION,
            `type`: if (result.isStatic) { ObjCFunctionType.STATIC } else { ObjCFunctionType.INSTANCE },
            hasForeignNameAnno: GetForeignNameAnnotation(funcDecl).isSome())
        let params = funcBody.paramLists[0].params
        result.paramStaticRef = if (params.isEmpty()) {
            "()"
        } else {
            JoinVec<FuncParam>(params,
                {param: FuncParam => ObjCParamMapper.MapCJTypeToObjCType(typedefs, param.GetTy().getOrThrow())},
                sep: ",", pre: "(", suf: ")", force: false)
        }
        result.callingParams = JoinVec<FuncParam>(params,
            {param: FuncParam => param.identifier.Val()}, sep: ", ", pre: ", ", suf: "", force: false)
        result.convertedParams = ObjCParamMapper.ConvertParamsListToArgsListToString(funcBody.paramLists,
            !result.isStatic)
        result.bridge = (TypeMapper.IsObjCObjectType(retTy) || TypeMapper.IsObjCBlock(retTy)) &&
            !TypeMapper.IsObjCCJMapping(retTy)
        return result
    }

    // C++ Transpiler.cpp:507-541.
    private func GetObjCCtorMetainfo(funcDecl: FuncDecl): EmittableObjCFuncMetainfo {
        var result = EmittableObjCFuncMetainfo()
        let ctor = if (let InteropType.ObjC_Mirror <- interopType) {
            ctx.factory.GetGeneratedImplCtor(decl, funcDecl).getOrThrow()
        } else {
            funcDecl
        }
        let selectorComponents = ctx.nameGenerator.GetObjCDeclSelectorComponents(funcDecl)
        CJC_ASSERT(!selectorComponents.isEmpty())
        let cjWrapperName = if (let Some(config) <- genericConfig) {
            ctx.nameGenerator.GenerateInitCjObjectName(ctor, genericActualName: Some(config.declInstName))
        } else {
            ctx.nameGenerator.GenerateInitCjObjectName(ctor)
        }
        result.isStatic = ctor.TestAttr(Attribute.STATIC)
        result.selectorComponents = selectorComponents
        result.mangledIdentifier = cjWrapperName
        result.identifier = selectorComponents[0]
        result.retType = ObjCParamMapper.ID_TYPE
        let funcBody = funcDecl.funcBody.getOrThrow()
        result.paramsDecl = ObjCParamMapper.GenerateFuncParamLists(typedefs, funcBody.paramLists,
            selectorComponents, format: FunctionListFormat.DECLARATION,
            `type`: if (result.isStatic) { ObjCFunctionType.STATIC } else { ObjCFunctionType.INSTANCE },
            hasForeignNameAnno: GetForeignNameAnnotation(funcDecl).isSome())
        let params = funcBody.paramLists[0].params
        result.paramStaticRef = JoinVec<FuncParam>(params,
            {param: FuncParam => ObjCParamMapper.MapCJTypeToObjCType(typedefs, param.GetTy().getOrThrow())},
            sep: ",", pre: "(", suf: ")", force: false)
        result.callingParams = JoinVec<FuncParam>(params,
            {param: FuncParam => ObjCParamMapper.GenerateArgumentCast(param.GetTy().getOrThrow(),
                param.identifier.Val())}, sep: ", ", pre: ", ", suf: "", force: false)
        result.bridge = false
        return result
    }

    // C++ Transpiler.cpp:543-559.
    private func WriteToFile(): Unit {
        WriteToHeader(headerImport.toString() + dependenciesStream.toString() + headerBody.toString() + Emitter.END)
        WriteToSource(sourceImport.toString() + staticReferences.toString() + sourceBody.toString() +
            ctors.toString() + initialize.toString() + defaultFuncImpls.toString() + Emitter.END)
    }

    // C++ Transpiler.cpp:561-567.
    private func WriteToHeader(content: String): Unit {
        let objCDeclName = if (let Some(config) <- genericConfig) {
            ctx.nameGenerator.GetObjCDeclName(decl, genericActualName: Some(config.declInstName))
        } else {
            ctx.nameGenerator.GetObjCDeclName(decl)
        }
        FileUtil.WriteToFile(FileUtil.JoinPath(outputFilePath, objCDeclName + ".h"), content)
    }

    // C++ Transpiler.cpp:569-575.
    private func WriteToSource(content: String): Unit {
        let objCDeclName = if (let Some(config) <- genericConfig) {
            ctx.nameGenerator.GetObjCDeclName(decl, genericActualName: Some(config.declInstName))
        } else {
            ctx.nameGenerator.GetObjCDeclName(decl)
        }
        FileUtil.WriteToFile(FileUtil.JoinPath(outputFilePath, objCDeclName + ".m"), content)
    }
}
