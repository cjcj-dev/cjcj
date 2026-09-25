package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.{MemberMap, TypeManager}
import cjcj::sema.NativeFFI.{GetJavaRefField, InteropLibBridge, IsSynthetic, Utils, WithinFile}
import cjcj::utils.JAVA_REF_GETTER_FUNC_NAME

public class GenerateJavaMirrorApiStub {
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge
    private let utils: Utils
    private let memberMap: HashMap<InheritableDecl, MemberMap>

    public init(typeManager: TypeManager, ilib: InteropLibBridge, utils: Utils,
        memberMap: HashMap<InheritableDecl, MemberMap>) {
        this.typeManager = typeManager
        this.ilib = ilib
        this.utils = utils
        this.memberMap = memberMap
    }

    private func CreateWrappingConstructorStub(mirror: ClassDecl): FuncDecl {
        let curFile = mirror.curFile
        let javaEntityDecl = ilib.GetJavaEntityDecl().getOrThrow()
        let param = CreateFuncParam("$ref", Some(CreateRefType(javaEntityDecl)), None, javaEntityDecl.GetTy())
        let ctorNodes = ArrayList<Node>()
        if (IsJObject(mirror)) {
            let lhsRef = WithinFile<RefExpr>(CreateRefExpr(GetJavaRefField(mirror)), curFile)
            let rhs = WithinFile<RefExpr>(CreateRefExpr(param), curFile)
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            let ensured = ilib.CreateEnsureNotNullCall(WithinFile<RefExpr>(CreateRefExpr(param), curFile))
            if (let Some(call) <- ensured) {
                ctorNodes.add(call)
            }
            ctorNodes.add(CreateAssignExpr(lhsRef, rhs, Some(unitTy)))
        }
        let paramTys = ArrayList<Ty>()
        paramTys.add(param.GetTy().getOrThrow())
        let ctorFuncTy = typeManager.GetFunctionTy(paramTys.toArray(), mirror.GetTy().getOrThrow())
        let ctorParams = ArrayList<FuncParam>()
        ctorParams.add(param)
        let paramList = CreateFuncParamList(ctorParams)
        paramList.curFile = curFile
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(paramList)
        let ctorFuncBody = CreateFuncBody(paramLists, Some(CreateRefType(mirror)),
            Some(CreateBlock(ctorNodes, mirror.GetTy())), mirror.GetTy())
        let fd = CreateFuncDecl("init", Some(ctorFuncBody), Some(ctorFuncTy))
        fd.funcBody.getOrThrow().funcDecl = fd
        fd.constructorCall = ConstructorCall.SUPER
        fd.EnableAttr(Attribute.PUBLIC)
        fd.EnableAttr(Attribute.IN_CLASSLIKE)
        fd.EnableAttr(Attribute.CONSTRUCTOR)
        return fd
    }

    public func InsertWrappingConstructor(mirror: ClassDecl): FuncDecl {
        let ctor = CreateWrappingConstructorStub(mirror)
        ctor.funcBody.getOrThrow().parentClassLike = Some(mirror)
        ctor.fullPackageName = mirror.fullPackageName
        ctor.outerDecl = Some(mirror)
        ctor.curFile = mirror.curFile
        mirror.body.getOrThrow().decls.add(ctor)
        return ctor
    }

    private func InsertJStringOfStringConstructor(jstring: ClassDecl): Unit {
        let stringDecl = utils.GetStringDecl()
        let param = CreateFuncParam("s", Some(CreateRefType(stringDecl)), None, stringDecl.GetTy())
        let ctorFuncTy = typeManager.GetFunctionTy([param.GetTy().getOrThrow()], jstring.GetTy().getOrThrow())
        let ctorParams = ArrayList<FuncParam>()
        ctorParams.add(param)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(CreateFuncParamList(ctorParams))
        let ctorFuncBody = CreateFuncBody(paramLists, Some(CreateRefType(jstring)),
            Some(CreateBlock(ArrayList<Node>(), jstring.GetTy())), jstring.GetTy())
        let fd = CreateFuncDecl("init", Some(ctorFuncBody), Some(ctorFuncTy))
        fd.funcBody.getOrThrow().funcDecl = fd
        fd.funcBody.getOrThrow().parentClassLike = Some(jstring)
        fd.constructorCall = ConstructorCall.SUPER
        fd.EnableAttr(Attribute.PUBLIC)
        fd.EnableAttr(Attribute.IN_CLASSLIKE)
        fd.EnableAttr(Attribute.CONSTRUCTOR)
        fd.fullPackageName = jstring.fullPackageName
        fd.outerDecl = Some(jstring)
        fd.curFile = jstring.curFile
        fd.begin = jstring.begin
        jstring.body.getOrThrow().decls.add(fd)
    }

    private func InsertAbstractJavaReferenceGetterStub(mirror: InterfaceDecl): Unit {
        let javaEntityDecl = ilib.GetJavaEntityDecl().getOrThrow()
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
        let funcTy = typeManager.GetFunctionTy(Array<Ty>(), javaEntityDecl.GetTy().getOrThrow())
        let funcBody = CreateFuncBody(paramLists, Some(CreateRefType(javaEntityDecl)), None, javaEntityDecl.GetTy())
        let fd = CreateFuncDecl(JAVA_REF_GETTER_FUNC_NAME, Some(funcBody), Some(funcTy))
        fd.EnableAttr(Attribute.PUBLIC)
        fd.EnableAttr(Attribute.IN_CLASSLIKE)
        fd.EnableAttr(Attribute.ABSTRACT)
        fd.funcBody.getOrThrow().funcDecl = fd
        fd.funcBody.getOrThrow().parentClassLike = Some(mirror)
        fd.fullPackageName = mirror.fullPackageName
        fd.outerDecl = Some(mirror)
        fd.curFile = mirror.curFile
        fd.begin = mirror.begin
        mirror.body.getOrThrow().decls.add(fd)
    }

    private func InsertSyntheticAbstractWrapperMethodStubs(wrapper: ClassDecl): Unit {
        if (let Some(map) <- memberMap.get(wrapper)) {
        for (entry in map.entries) {
            if (let Some(decl) <- entry.signature.decl) {
                if (let Some(fd) <- (decl as FuncDecl)) {
                    if (!fd.TestAttr(Attribute.ABSTRACT)) {
                        continue
                    }
                    if (let Some(cloned) <- (ASTCloner.Clone(fd) as FuncDecl)) {
                        cloned.DisableAttr(Attribute.ABSTRACT)
                        cloned.outerDecl = Some(wrapper)
                        cloned.funcBody.getOrThrow().parentClassLike = Some(wrapper)
                        cloned.curFile = wrapper.curFile
                        cloned.fullPackageName = wrapper.fullPackageName
                        wrapper.body.getOrThrow().decls.add(cloned)
                    }
                }
            }
        }
        }
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (mirror in ctx.GetJavaMirrors()) {
            if (mirror.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let Some(mirrorClass) <- (mirror as ClassDecl)) {
                InsertWrappingConstructor(mirrorClass)
                if (let Some(jstring) <- utils.GetJStringDecl()) {
                    if (mirrorClass == jstring) {
                        InsertJStringOfStringConstructor(mirrorClass)
                    }
                }
                if (IsSynthetic(mirrorClass)) {
                    InsertSyntheticAbstractWrapperMethodStubs(mirrorClass)
                }
            } else if (let Some(mirrorInterface) <- (mirror as InterfaceDecl)) {
                InsertAbstractJavaReferenceGetterStub(mirrorInterface)
            }
        }
    }
}
