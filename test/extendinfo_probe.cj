package extendinfo_probe

import cjcj::basic.*

public func ProbeImportedExtend(): Bool {
    return Linkage.EXTERNAL == Linkage.INTERNAL
}

public class ProbeOwner {
    public func ProbeImportedExtendInMember(value: Linkage): Bool {
        return value == Linkage.INTERNAL
    }
}
