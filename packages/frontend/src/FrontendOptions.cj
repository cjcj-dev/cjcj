package cjcj::frontend

public import cjcj::option.{
    ArgList, CreateOptionTable, GlobalOptions, ID as OptionID,
    OptionArgInstance, OptionInfo, OptionTable, SetupConditionalCompilationCfg
}
public import cjcj::utils.{
    CACHED_AST_EXTENSION, CACHED_LOG_EXTENSION, CJ_D_FILE_EXTENSION, DEFAULT_PACKAGE_NAME, SERIALIZED_FILE_EXTENSION,
    OverflowStrategy, OverflowStrategyName
}

public enum DumpAction {
    | NO_ACTION
    | DUMP_TOKENS
    | DUMP_SYMBOLS
    | TYPE_CHECK
    | DUMP_DEP_PKG
    | DESERIALIZE_CHIR
}

private func DumpActionIndex(action: DumpAction): Int64 {
    return match (action) {
        case DumpAction.NO_ACTION => 0
        case DumpAction.DUMP_TOKENS => 1
        case DumpAction.DUMP_SYMBOLS => 2
        case DumpAction.TYPE_CHECK => 3
        case DumpAction.DUMP_DEP_PKG => 4
        case DumpAction.DESERIALIZE_CHIR => 5
    }
}

extend DumpAction <: Equatable<DumpAction> {
    public operator func ==(rhs: DumpAction): Bool {
        return DumpActionIndex(this) == DumpActionIndex(rhs)
    }

    public operator func !=(rhs: DumpAction): Bool {
        return !(this == rhs)
    }
}

public class FrontendOptions <: GlobalOptions {
    public var dumpAction: DumpAction = DumpAction.NO_ACTION

    public init() {
        super()
    }

    protected override func ParseOption(arg: OptionArgInstance): Option<Bool> {
        let id = arg.info.GetID()
        if (id == OptionID.DUMP_TOKENS) {
            dumpAction = DumpAction.DUMP_TOKENS
            return Some(true)
        }
        if (id == OptionID.DUMP_SYMBOLS) {
            dumpAction = DumpAction.DUMP_SYMBOLS
            return Some(true)
        }
        if (id == OptionID.TYPE_CHECK) {
            dumpAction = DumpAction.TYPE_CHECK
            return Some(true)
        }
        if (id == OptionID.DUMP_DEPENDENT_PACKAGE) {
            scanDepPkg = true
            dumpAction = DumpAction.DUMP_DEP_PKG
            return Some(true)
        }
        if (id == OptionID.DESERIALIZE_CHIR_AND_DUMP) {
            chirDeserialize = true
            dumpCHIR = true
            chirDeserializePath = arg.value
            dumpAction = DumpAction.DESERIALIZE_CHIR
            return Some(true)
        }
        if (id == OptionID.COMPILE_CJD) {
            compileCjd = true
            return Some(true)
        }
        return super.ParseOption(arg)
    }

}
