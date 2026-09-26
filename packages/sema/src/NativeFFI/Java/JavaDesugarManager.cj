package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{DEFAULT_POSITION, DiagKindRefactor, DiagnosticEngine}
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::option.MaybeString
import cjcj::sema.{GenerateGetTypeForTypeParamIntrinsic, MemberMap, TypeManager}
import cjcj::sema.NativeFFI.{CreateSuperCall, GetJavaMirrorWrappingConstructor, GetJavaRefField, InteropLibBridge,
    IsJArray, Utils, WithinFile, WrapReturningLambdaCall}
import cjcj::utils.{HAS_INITED_IDENT, JAVA_REF_GETTER_FUNC_NAME}

public class JavaDesugarManager {
    private let importManager: SemaImportManager
    private let typeManager: TypeManager
    private let diag: DiagnosticEngine
    private let mangler: BaseMangler
    private let javagenOutputPath: MaybeString
    private let outputPath: String
    private let memberMap: HashMap<InheritableDecl, MemberMap>
    private var utilsStore: Option<Utils> = None
    private var ilibStore: Option<InteropLibBridge> = None
    private var jniStore: Option<JniBridge> = None

    public init(importManager: SemaImportManager, typeManager: TypeManager, diag: DiagnosticEngine,
        mangler: BaseMangler, javagenOutputPath: MaybeString, outputPath: String,
        memberMap: HashMap<InheritableDecl, MemberMap>) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.diag = diag
        this.mangler = mangler
        this.javagenOutputPath = javagenOutputPath
        this.outputPath = outputPath
        this.memberMap = memberMap
    }

    private func Ensure(ctx: AfterTypeCheckContext): Unit {
        if (utilsStore.isSome()) {
            return
        }
        let utils = Utils(importManager, typeManager, ctx.pkg)
        let ilib = InteropLibBridge(importManager, typeManager, diag, utils)
        ilib.CheckInteropLibVersion()
        utilsStore = Some(utils)
        ilibStore = Some(ilib)
    }

    private func BridgeUtils(): Utils {
        return utilsStore.getOrThrow()
    }

    private func BridgeLib(): InteropLibBridge {
        return ilibStore.getOrThrow()
    }

    private func BridgeJni(): JniBridge {
        if (let Some(jni) <- jniStore) {
            return jni
        }
        let ilib = BridgeLib()
        var envDecl: Option<Decl> = None
        if (let Some(decl) <- ilib.GetJniEnvPtrDecl()) {
            envDecl = Some(decl)
        }
        var jobjectDecl: Option<Decl> = None
        if (let Some(decl) <- ilib.GetJobjectDecl()) {
            jobjectDecl = Some(decl)
        }
        let jni = JniBridge(typeManager, importManager, mangler, BridgeUtils(), envDecl, jobjectDecl)
        jniStore = Some(jni)
        return jni
    }

    private func InsertJavaMirrorWrappingConstructorBody(decl: ClassDecl): Unit {
        if (IsJObject(decl)) {
            return
        }
        let ctor = GetJavaMirrorWrappingConstructor(decl)
        if (let None <- ctor) {
            return
        }
        let superDecl = decl.GetSuperClassDecl()
        if (let None <- superDecl) {
            return
        }
        let superCtor = GetJavaMirrorWrappingConstructor(superDecl.getOrThrow())
        if (let None <- superCtor) {
            return
        }
        if (let None <- superCtor.getOrThrow().GetTy()) {
            return
        }
        let wrapping = ctor.getOrThrow()
        let param = wrapping.funcBody.getOrThrow().paramLists[0].params[0]
        let arg = CreateFuncArg(WithinFile<RefExpr>(CreateRefExpr(param), decl.curFile))
        let superCall = CreateSuperCall(decl, superCtor.getOrThrow(), superCtor.getOrThrow().GetTy().getOrThrow())
        superCall.args.add(arg)
        wrapping.funcBody.getOrThrow().body.getOrThrow().body.add(superCall)
    }

    private func InsertJavaMirrorHasInited(mirror: ClassDecl): Unit {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let initializer = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy)
        let field = WithinFile<VarDecl>(CreateVarDecl(HAS_INITED_IDENT, Some(initializer), None), mirror.curFile)
        field.isVar = true
        field.fullPackageName = mirror.fullPackageName
        field.outerDecl = Some(mirror)
        field.EnableAttr(Attribute.PRIVATE)
        field.EnableAttr(Attribute.NO_REFLECT_INFO)
        field.EnableAttr(Attribute.IN_CLASSLIKE)
        field.EnableAttr(Attribute.HAS_INITED_FIELD)
        mirror.body.getOrThrow().decls.add(field)
    }

    private func InsertJavaMirrorFinalizer(mirror: ClassDecl): Unit {
        if (BridgeLib().GetDeleteGlobalRefDecl().isNone() || BridgeLib().GetGetJniEnvDecl().isNone()) {
            return
        }
        mirror.body.getOrThrow().decls.add(BridgeLib().CreateDeletingGlobalRefFinalizer(mirror))
    }

    private func InsertJavaRefGetterWithBody(decl: ClassDecl): Unit {
        let javaEntityDecl = BridgeLib().GetJavaEntityDecl()
        if (let None <- javaEntityDecl) {
            return
        }
        let entity = javaEntityDecl.getOrThrow()
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
        let javaRef = GetJavaRefField(decl)
        let ref = CreateRefExpr(javaRef)
        ref.curFile = decl.curFile
        let ret = CreateReturnExpr(ref)
        ret.SetTy(TypeManager.GetNothingTy())
        let nodes = ArrayList<Node>()
        nodes.add(ret)
        let block = CreateBlock(nodes, entity.GetTy())
        let funcBody = CreateFuncBody(paramLists, Some(CreateRefType(entity)), Some(block),
            Some(TypeManager.GetNothingTy()))
        let funcTy = typeManager.GetFunctionTy(Array<Ty>(), entity.GetTy().getOrThrow())
        let fd = CreateFuncDecl(JAVA_REF_GETTER_FUNC_NAME, Some(funcBody), Some(funcTy))
        fd.EnableAttr(Attribute.PUBLIC)
        fd.EnableAttr(Attribute.IN_CLASSLIKE)
        fd.EnableAttr(Attribute.INITIALIZED)
        fd.EnableAttr(Attribute.IS_CHECK_VISITED)
        fd.fullPackageName = decl.fullPackageName
        fd.funcBody.getOrThrow().funcDecl = fd
        fd.funcBody.getOrThrow().parentClassLike = Some(decl)
        fd.outerDecl = Some(decl)
        fd.curFile = decl.curFile
        decl.body.getOrThrow().decls.add(fd)
    }

    private func InsertArrayJavaEntityGet(decl: ClassDecl): Unit {
        if (let None <- decl.body) {
            return
        }
        var getOperation: Option<FuncDecl> = None
        for (member in decl.body.getOrThrow().decls) {
            if (let Some(fd) <- (member as FuncDecl)) {
                if (let Some(body) <- fd.funcBody) {
                    if (!body.paramLists.isEmpty() && fd.identifier.Val() == "[]" &&
                        body.paramLists[0].params.size == 1) {
                        getOperation = Some(fd)
                        break
                    }
                }
            }
        }
        if (let None <- getOperation) {
            return
        }
        if (let None <- BridgeLib().GetJavaEntityTy()) {
            return
        }
        if (let Some(cloned) <- (ASTCloner.Clone(getOperation.getOrThrow()) as FuncDecl)) {
            let javaEntity = BridgeLib().GetJavaEntityTy().getOrThrow()
            cloned.identifier = SrcIdentifier("$javaarrayget")
            let intTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT32)
            cloned.SetTy(typeManager.GetFunctionTy([intTy], javaEntity))
            if (let Some(retType) <- cloned.funcBody.getOrThrow().retType) {
                retType.SetTy(javaEntity)
            }
            cloned.outerDecl = Some(decl)
            cloned.curFile = decl.curFile
            decl.body.getOrThrow().decls.add(cloned)
        }
    }

    private func InsertArrayJavaEntitySet(decl: ClassDecl): Unit {
        if (let None <- decl.body) {
            return
        }
        var setOperation: Option<FuncDecl> = None
        for (member in decl.body.getOrThrow().decls) {
            if (let Some(fd) <- (member as FuncDecl)) {
                if (let Some(body) <- fd.funcBody) {
                    if (!body.paramLists.isEmpty() && fd.identifier.Val() == "[]" &&
                        body.paramLists[0].params.size == 2) {
                        setOperation = Some(fd)
                        break
                    }
                }
            }
        }
        if (let None <- setOperation) {
            return
        }
        if (let None <- BridgeLib().GetJavaEntityTy()) {
            return
        }
        if (let Some(cloned) <- (ASTCloner.Clone(setOperation.getOrThrow()) as FuncDecl)) {
            let javaEntity = BridgeLib().GetJavaEntityTy().getOrThrow()
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            cloned.identifier = SrcIdentifier("$javaarrayset")
            let valueParam = cloned.funcBody.getOrThrow().paramLists[0].params[1]
            valueParam.SetTy(javaEntity)
            if (let Some(typeNode) <- valueParam.typeNode) {
                typeNode.SetTy(javaEntity)
            }
            cloned.SetTy(typeManager.GetFunctionTy(
                [TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT32), javaEntity], unitTy))
            if (let Some(retType) <- cloned.funcBody.getOrThrow().retType) {
                retType.SetTy(unitTy)
            }
            cloned.outerDecl = Some(decl)
            cloned.curFile = decl.curFile
            decl.body.getOrThrow().decls.add(cloned)
        }
    }

    private func InsertJStringOfStringCtorBody(decl: ClassDecl): Unit {
        var generated: Option<FuncDecl> = None
        for (member in decl.GetMemberDecls()) {
            if (let Some(fd) <- (member as FuncDecl)) {
                if (!fd.TestAttr(Attribute.CONSTRUCTOR) || fd.funcBody.isNone()) {
                    continue
                }
                let lists = fd.funcBody.getOrThrow().paramLists
                if (lists.isEmpty() || lists[0].params.size != 1) {
                    continue
                }
                if (let Some(ty) <- lists[0].params[0].GetTy()) {
                    if (ty.IsString()) {
                        generated = Some(fd)
                        break
                    }
                }
            }
        }
        if (let None <- generated) {
            return
        }
        let ctor = generated.getOrThrow()
        let wrapping = GetJavaMirrorWrappingConstructor(decl)
        if (let None <- wrapping) {
            return
        }
        if (let None <- wrapping.getOrThrow().GetTy()) {
            return
        }
        let curFile = decl.curFile
        if (let None <- curFile) {
            return
        }
        let file = curFile.getOrThrow()
        let param = ctor.funcBody.getOrThrow().paramLists[0].params[0]
        let envCall = BridgeLib().CreateGetJniEnvCall(Some(file))
        if (let None <- envCall) {
            return
        }
        let envVar = CreateTmpVarDecl(None, Some((envCall.getOrThrow() as Expr).getOrThrow()))
        envVar.curFile = Some(file)
        let paramRef = WithinFile<RefExpr>(CreateRefExpr(param), file)
        let convert = BridgeLib().CreateCangjieStringToJavaCall(WithinFile<RefExpr>(CreateRefExpr(envVar), file), paramRef)
        if (let None <- convert) {
            return
        }
        let asObj = BridgeLib().CreateAsJniJobjectCall(convert.getOrThrow())
        if (let None <- asObj) {
            return
        }
        let swapped = BridgeLib().CreateSwapLocalWithGlobalRefCall(
            WithinFile<RefExpr>(CreateRefExpr(envVar), file), asObj.getOrThrow())
        if (let None <- swapped) {
            return
        }
        let entity = BridgeLib().CreateJavaEntityJobjectCall(swapped.getOrThrow())
        if (let None <- entity) {
            return
        }
        let nodes = ArrayList<Node>()
        nodes.add(envVar)
        nodes.add(entity.getOrThrow())
        let superCall = CreateSuperCall(decl, wrapping.getOrThrow(), wrapping.getOrThrow().GetTy().getOrThrow())
        superCall.args.add(CreateFuncArg(WrapReturningLambdaCall(typeManager, nodes)))
        ctor.funcBody.getOrThrow().body.getOrThrow().body.add(superCall)
    }

    public func GenerateInMirror(classDecl: ClassDecl): Unit {
        InsertJavaMirrorWrappingConstructorBody(classDecl)
        InsertJavaMirrorHasInited(classDecl)
        InsertJavaMirrorFinalizer(classDecl)
        if (let Some(jstring) <- BridgeUtils().GetJStringDecl()) {
            if (classDecl == jstring) {
                InsertJStringOfStringCtorBody(classDecl)
            }
        }
        if (IsJArray(classDecl)) {
            InsertArrayJavaEntityGet(classDecl)
            InsertArrayJavaEntitySet(classDecl)
        }
        if (IsJObject(classDecl)) {
            InsertJavaRefGetterWithBody(classDecl)
        }
    }

    public func GenerateInMirrors(file: File): Unit {
        if (let Some(pkg) <- file.curPackage) {
            GenerateGetTypeForTypeParamIntrinsic(pkg, typeManager)
        }
        for (decl in file.decls) {
            if (let Some(classLike) <- (decl as ClassLikeDecl)) {
                if (!IsMirror(classLike)) {
                    continue
                }
                if (classLike.TestAttr(Attribute.IS_BROKEN)) {
                    return
                }
                if (let Some(classDecl) <- (classLike as ClassDecl)) {
                    GenerateInMirror(classDecl)
                }
            }
        }
    }

    public func GenerateJavaSourceCode(ctx: AfterTypeCheckContext): Unit {
        if (!javagenOutputPath.hasValue) {
            return
        }
        let location = if (outputPath.isEmpty()) {
            mangler.MangleFullPackageName(ctx.pkg.fullPackageName)
        } else {
            outputPath
        }
        diag.DiagnoseRefactor(DiagKindRefactor.sema_java_interop_not_supported, DEFAULT_POSITION,
            "java source generation at " + location).Emit()
    }

    public func ProcessJavaMirrorImplStages(ctx: AfterTypeCheckContext, desugarPropRef: (Node) -> Unit): Unit {
        Ensure(ctx)
        GenerateJavaReferenceFieldInJObject(BridgeLib()).Process(ctx)
        GenerateJavaMirrorApiStub(typeManager, BridgeLib(), BridgeUtils(), memberMap).Process(ctx)
        GenerateJavaImplApiStub(typeManager, BridgeLib(), BridgeJni()).Process(ctx)
        for (file in ctx.pkg.files) {
            GenerateInMirrors(file)
        }
        GenerateInJavaImplRegistryCompanion(typeManager, BridgeLib()).Process(ctx)
        DesugarJavaImplSuperConstructorCall(typeManager, BridgeLib(), BridgeJni(), diag, BridgeUtils()).Process(ctx)
        GenerateInJavaImplReferenceWrapper(typeManager, importManager, BridgeLib(), ASTFactory(BridgeLib()),
            BridgeUtils()).Process(ctx)
        DesugarJavaImplSuperMethodCall(BridgeLib(), ASTFactory(BridgeLib()), BridgeUtils()).Process(ctx)
        RewriteJavaImplReferenceWrapperFields(typeManager, BridgeUtils(), desugarPropRef).Process(ctx)
        GenerateNativeBridgeForJavaImpl().Process(ctx)
        let ilib = BridgeLib()
        PopulateJavaMirrorStubs(typeManager, ilib, BridgeUtils(), ASTFactory(ilib)).Process(ctx)
        GenerateJavaSourceCode(ctx)
    }

    public func ProcessCallSiteDesugarStages(ctx: AfterTypeCheckContext): Unit {
        Ensure(ctx)
        DesugarJArray(typeManager, importManager, BridgeLib()).Process(ctx)
        DesugarTypeCheckingAndCasting(BridgeLib(), diag, BridgeUtils()).Process(ctx)
    }
}
