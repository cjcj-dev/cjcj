package cangjie_compiler::sema.CJMP

import cangjie_compiler::sema.*

public class MPTypeCheckerImpl {
    public var typeManager: TypeManager
    public var compileCommon: Bool = false
    public var compilePlatform: Bool = false
    public var severalParents: Bool = false

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
    }
}
