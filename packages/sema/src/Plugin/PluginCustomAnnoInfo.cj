package cangjie_compiler::sema.Plugin

public class PluginCustomAnnoInfo {
    public var since: APILevelVersion = APILevelVersion()
    public var syscap: String = ""
    public var hasHideAnno: Option<Bool> = None

    public init() {}

    public init(since!: APILevelVersion = APILevelVersion(), syscap!: String = "",
        hasHideAnno!: Option<Bool> = None) {
        this.since = since
        this.syscap = syscap
        this.hasHideAnno = hasHideAnno
    }
}
