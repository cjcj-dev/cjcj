package cjcj::option

// The option package's normal CJPM compile-option supplies this build setting.
// Match the upstream CANGJIE_VISIBLE_OPTIONS_ONLY default without a runtime
// environment switch: help, lookup, value checks and actions share one policy.
@When[CANGJIE_VISIBLE_OPTIONS_ONLY == "true"]
internal let CANGJIE_VISIBLE_OPTIONS_ONLY: Bool = true

@When[CANGJIE_VISIBLE_OPTIONS_ONLY == "false"]
internal let CANGJIE_VISIBLE_OPTIONS_ONLY: Bool = false
