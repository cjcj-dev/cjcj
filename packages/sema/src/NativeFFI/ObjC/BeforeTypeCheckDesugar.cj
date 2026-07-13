package cjcj::sema.NativeFFI.ObjC

import std.collection.ArrayList
import cjcj::ast.*
import cjcj::sema.NativeFFI.{GetObjCMirrorForeignName, INIT_IDENT, NSOBJECT_CLASS_IDENT,
    NSSTRING_CLASS_IDENT, TOSTRING_METHOD_IDENT}
import cjcj::utils.STD_LIB_STRING

// Mirrors Sema/NativeFFI/ObjC/BeforeTypeCheck/Desugar.cpp:21.
private let INIT_PARAM_IDENT: String = "str"

// Mirrors AddFuncDeclToClass, Desugar.cpp:23-30.
private func AddFuncDeclToClass(decl: FuncDecl, target: ClassDecl): Unit {
    decl.curFile = target.curFile
    let bodyEnd = target.body.getOrThrow().end
    decl.identifier.SetPos(bodyEnd, bodyEnd)
    decl.begin = bodyEnd
    decl.end = bodyEnd
    decl.EnableAttr(Attribute.IN_CLASSLIKE)
}

// Mirrors CreateNSStringFromStringCtorDecl, Desugar.cpp:32-53.
private func CreateNSStringFromStringCtorDecl(target: ClassDecl): Decl {
    let param = CreateFuncParam(INIT_PARAM_IDENT, CreateRefType(STD_LIB_STRING), None, None)
    let ctorParams = ArrayList<FuncParam>()
    ctorParams.add(param)
    let paramList = CreateFuncParamList(ctorParams)
    let paramLists = ArrayList<FuncParamList>()
    paramLists.add(paramList)
    let block = CreateBlock(ArrayList<Node>(), None)
    block.EnableAttr(Attribute.IS_CHECK_VISITED)
    let ctorBody = CreateFuncBody(paramLists, None, block, None)
    let ctorDecl = CreateFuncDecl(INIT_IDENT, ctorBody, None)
    ctorDecl.EnableAttr(Attribute.PUBLIC)
    ctorDecl.EnableAttr(Attribute.CONSTRUCTOR)
    AddFuncDeclToClass(ctorDecl, target)
    return ctorDecl
}

// Mirrors CreateNSObjectToStringDecl, Desugar.cpp:55-73.
private func CreateNSObjectToStringDecl(target: ClassDecl): Decl {
    let funcParams = ArrayList<FuncParam>()
    let paramList = CreateFuncParamList(funcParams)
    let paramLists = ArrayList<FuncParamList>()
    paramLists.add(paramList)
    let block = CreateBlock(ArrayList<Node>(), None)
    block.EnableAttr(Attribute.IS_CHECK_VISITED)
    let funcBody = CreateFuncBody(paramLists, CreateRefType(STD_LIB_STRING), block, None)
    let funcDecl = CreateFuncDecl(TOSTRING_METHOD_IDENT, funcBody, None)
    funcDecl.EnableAttr(Attribute.PUBLIC)
    AddFuncDeclToClass(funcDecl, target)
    return funcDecl
}

// Mirrors InsertNSStringCtor, Desugar.cpp:75-79.
private func InsertNSStringCtor(classDecl: ClassDecl): Unit {
    let ctorDecl = CreateNSStringFromStringCtorDecl(classDecl)
    classDecl.body.getOrThrow().decls.add(ctorDecl)
}

// Mirrors InsertNSObjectToString, Desugar.cpp:81-85.
private func InsertNSObjectToString(classDecl: ClassDecl): Unit {
    let funcDecl = CreateNSObjectToStringDecl(classDecl)
    classDecl.body.getOrThrow().decls.add(funcDecl)
}

// Mirrors DesugarMirrorClass, Desugar.cpp:87-97.
private func DesugarMirrorClass(classDecl: ClassDecl): Unit {
    InsertMirrorVarProp(classDecl, Attribute.OBJ_C_MIRROR)
    let foreignName = GetObjCMirrorForeignName(classDecl)
    if (foreignName == NSSTRING_CLASS_IDENT) {
        InsertNSStringCtor(classDecl)
    } else if (foreignName == NSOBJECT_CLASS_IDENT) {
        InsertNSObjectToString(classDecl)
    }
}

// Mirrors PrepareTypeCheck, Desugar.cpp:100-113.
public func PrepareTypeCheck(pkg: Package): Unit {
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (!decl.TestAttr(Attribute.OBJ_C_MIRROR)) {
                continue
            }
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                DesugarMirrorClass(classDecl)
            }
        }
    }
}
