package cjcj::sema.NativeFFI.ObjC

import std.collection.*

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/Emitter.h:30-41.
public struct EmittableObjCFuncMetainfo {
    public var identifier: String = ""
    public var mangledIdentifier: String = ""
    public var selectorComponents: ArrayList<String> = ArrayList<String>()
    public var isStatic: Bool = false
    public var bridge: Bool = false
    public var paramsDecl: String = ""
    public var paramStaticRef: String = ""
    public var callingParams: String = ""
    public var convertedParams: String = ""
    public var retType: String = ""

    public init() {}
}

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/Emitter.h:43-48.
public struct EmittableObjCClassMetainfo {
    public var className: String = ""
    public var superclassName: String = ""
    public var interfaces: ArrayList<String> = ArrayList<String>()
    public var isFinal: Bool = false

    public init() {}
}

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/Emitter.h:50-57.
public struct EmittableObjCPropMetainfo {
    public var name: String = ""
    public var type: String = ""
    public var isStatic: Bool = false
    public var isReadwrite: Bool = false
    public var getter: EmittableObjCFuncMetainfo = EmittableObjCFuncMetainfo()
    public var setter: EmittableObjCFuncMetainfo = EmittableObjCFuncMetainfo()

    public init() {}
}

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/Emitter.h:59-110 and Emitter.cpp:25-187.
public class Emitter {
    public static let END: String = "@end\n"

    public static func EmitHeaderImport(s: StringBuilder): Unit {
        s.append("#import <Foundation/Foundation.h>\n")
        s.append("#import <stddef.h>\n")
    }

    public static func EmitSourceImport(s: StringBuilder): Unit {
        s.append("#import <stdlib.h>\n")
    }

    public static func EmitFileImport(s: StringBuilder, identifier: String): Unit {
        s.append("#import \"")
        s.append(identifier)
        s.append(".h\"\n")
    }

    public static func EmitModuleImport(s: StringBuilder, identifier: String): Unit {
        s.append("#import ")
        s.append(identifier)
        s.append("\n")
    }

    public static func EmitTypedef(s: StringBuilder, identifier: String): Unit {
        s.append(identifier)
        s.append(";\n")
    }

    public static func EmitForwardDeclaration(s: StringBuilder, identifier: String): Unit {
        s.append("@class ")
        s.append(identifier)
        s.append(";\n")
    }

    public static func EmitForwardDeclarationProtocol(s: StringBuilder, identifier: String): Unit {
        s.append("@protocol ")
        s.append(identifier)
        s.append(";\n")
    }

    public static func EmitInterfaceDeclaration(s: StringBuilder, info: EmittableObjCClassMetainfo): Unit {
        s.append("@interface ")
        s.append(info.className)
        s.append(" : ")
        s.append(info.superclassName)
        s.append(JoinVec<String>(info.interfaces, { value: String => value }, pre: " <", suf: ">", force: false))
        s.append("\n")
    }

    public static func EmitImplementationDeclaration(s: StringBuilder, info: EmittableObjCClassMetainfo): Unit {
        s.append("@implementation ")
        s.append(info.className)
        s.append("\n")
    }

    public static func EmitObjCFuncHeaderFunctionDecl(s: StringBuilder, info: EmittableObjCFuncMetainfo): Unit {
        s.append(if (info.isStatic) { "+ (" } else { "- (" })
        s.append(info.retType)
        s.append(")")
        s.append(info.identifier)
        s.append(info.paramsDecl)
        s.append(";\n")
    }

    public static func EmitObjCFuncStaticReference(s: StringBuilder, info: EmittableObjCFuncMetainfo): Unit {
        s.append("extern ")
        s.append(info.retType)
        s.append(" ")
        s.append(info.mangledIdentifier)
        s.append(info.paramStaticRef)
        s.append(";\n")
    }

    public static func EmitObjCFuncInitialization(s: StringBuilder, info: EmittableObjCFuncMetainfo): Unit {
        s.append("        if ((")
        s.append(info.mangledIdentifier)
        s.append(" = dlsym(CJWorldDLHandle, \"")
        s.append(info.mangledIdentifier)
        s.append("\")) == NULL) {\n")
        s.append("            NSLog(@\"ERROR: Failed to find ")
        s.append(info.mangledIdentifier)
        s.append(" symbol in cjworld\");\n")
        s.append("            exit(1);\n")
        s.append("        }\n")
    }

    public static func EmitSyntheticHeaderFunctionDecls(s: StringBuilder): Unit {
        s.append("@property (readwrite) int64_t $registryId;\n")
        s.append("+ (void)initialize;\n")
    }

    public static func EmitSyntheticRefsDealloc(s: StringBuilder): Unit {
        s.append("- (void)deleteCJObject;\n")
        s.append("- (void)dealloc;\n")
    }

    public static func EmitInitialize(s: StringBuilder, cjLibraryPath: String,
        info: EmittableObjCClassMetainfo): Unit {
        s.append("+ (void)initialize {\n")
        s.append("    if (self == [")
        s.append(info.className)
        s.append(" class]) {\n")
        s.append("        if (initCJRuntime(\"")
        s.append(cjLibraryPath)
        s.append("\") == false) {\n")
        s.append("            exit(1);\n")
        s.append("        }\n")
        s.append("    }\n")
        s.append("}\n")
    }

    public static func EmitCtor(s: StringBuilder, ctor: EmittableObjCFuncMetainfo,
        cls: EmittableObjCClassMetainfo): Unit {
        s.append("- (id)")
        s.append(ctor.identifier)
        s.append(ctor.paramsDecl)
        s.append(" {\n")
        s.append("    self.$registryId = -1;\n")
        s.append("    self = (__bridge_transfer ")
        s.append(cls.className)
        s.append("*)")
        s.append(ctor.mangledIdentifier)
        s.append("((__bridge void*)self")
        s.append(ctor.callingParams)
        s.append(");\n")
        s.append("    return self;\n")
        s.append("}\n")
    }

    public static func EmitDoesNotRecognizeSelectorCtor(s: StringBuilder,
        ctor: EmittableObjCFuncMetainfo): Unit {
        s.append("- (id)")
        s.append(ctor.identifier)
        s.append(ctor.paramsDecl)
        s.append(" {\n")
        s.append("    [self doesNotRecognizeSelector:_cmd];\n")
        s.append("    return nil;\n")
        s.append("}\n")
    }

    public static func EmitDefaultFunctionImplementation(s: StringBuilder,
        func: EmittableObjCFuncMetainfo): Unit {
        s.append(if (func.isStatic) { "+" } else { "-" })
        s.append(" (")
        s.append(func.retType)
        s.append(")")
        s.append(func.identifier)
        s.append(func.paramsDecl)
        s.append(" {\n")
        if (!func.isStatic) {
            s.append("    if (self.$registryId == -1) {\n")
            s.append("        [NSException raise: @\"Use before Cangjie counterpart is initialized\" format: ")
            s.append("@\"selector `%@` is overridden in Cangjie and cannot be used before Cangjie counterpart ")
            s.append("is initialized\", NSStringFromSelector(_cmd)];\n")
            s.append("    }\n")
        }
        s.append("    ")
        if (func.retType != "void") {
            s.append("return ")
        }
        if (func.bridge) {
            s.append("(__bridge_transfer ")
            s.append(func.retType)
            s.append(")")
        }
        s.append(func.mangledIdentifier)
        s.append("(")
        s.append(func.convertedParams)
        s.append(");\n")
        s.append("}\n")
    }

    public static func EmitAdditionalStaticReferences(s: StringBuilder): Unit {
        s.append("extern bool initCJRuntime(const char*);\n")
    }

    public static func EmitDeleteCJObject(s: StringBuilder, mangledName: String): Unit {
        s.append("- (void)deleteCJObject {\n")
        s.append("    ")
        s.append(mangledName)
        s.append("(self.$registryId);\n")
        s.append("}\n")
    }

    public static func EmitDealloc(s: StringBuilder): Unit {
        s.append("- (void)dealloc {\n")
        s.append("    [self deleteCJObject];\n")
        s.append("}\n")
    }

    public static func EmitDeleteCJObjectInitialization(s: StringBuilder, mangledName: String): Unit {
        s.append("        if ((")
        s.append(mangledName)
        s.append(" = dlsym(CJWorldDLHandle, \"")
        s.append(mangledName)
        s.append("\")) == NULL) {\n")
        s.append("            NSLog(@\"ERROR: Failed to find ")
        s.append(mangledName)
        s.append(" symbol in cjworld\");\n")
        s.append("            exit(1);\n")
        s.append("        }\n")
    }

    public static func EmitProperty(s: StringBuilder, prop: EmittableObjCPropMetainfo): Unit {
        s.append("@property (")
        s.append(if (prop.isReadwrite) { "readwrite" } else { "readonly" })
        s.append(", getter=")
        s.append(prop.getter.identifier)
        if (prop.isReadwrite) {
            s.append(", setter=")
            s.append(prop.setter.identifier)
        }
        s.append(") ")
        s.append(prop.type)
        s.append(" ")
        s.append(prop.name)
        s.append(";\n")
    }
}
