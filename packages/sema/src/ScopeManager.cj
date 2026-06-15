package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class ScopeManager {
    private let scopes: ArrayList<String> = ArrayList<String>()

    public init() {
        scopes.add(TOPLEVEL_SCOPE_NAME)
    }

    public func CurrentScope(): String {
        return scopes[scopes.size - 1]
    }

    public func Enter(name: String): Unit {
        scopes.add(name)
    }

    public func Leave(): Unit {
        if (scopes.size > 1) {
            scopes.remove(at: scopes.size - 1)
        }
    }
}
