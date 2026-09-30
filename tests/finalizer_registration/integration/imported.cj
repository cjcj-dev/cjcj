package registration_imported

import std.core.*

public class ImportedFinalized <: Object {
    public const init() { super() }
    ~init() {}
}

public const importedInstance = ImportedFinalized()
public const importedShared = importedInstance
public func importedMake(): Object { ImportedFinalized() }
