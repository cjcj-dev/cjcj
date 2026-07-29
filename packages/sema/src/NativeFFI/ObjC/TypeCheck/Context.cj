package cjcj::sema.NativeFFI.ObjC.TypeCheck

import cjcj::ast.Decl
import cjcj::basic.DiagnosticEngine
import cjcj::sema.NativeFFI.ObjC.TypeMapper
import cjcj::sema.TypeManager

// C++ src/Sema/NativeFFI/ObjC/TypeCheck/Context.h:22-32.
public class TypeCheckContext {
    public let target: Decl
    public let diag: DiagnosticEngine
    public let typeMapper: TypeMapper
    public let typeManager: TypeManager

    public init(target: Decl, diag: DiagnosticEngine, typeMapper: TypeMapper, typeManager: TypeManager) {
        this.target = target
        this.diag = diag
        this.typeMapper = typeMapper
        this.typeManager = typeManager
    }
}
