package cjcj::mangle

import std.collection.*
import cjcj::utils.{CJC_ASSERT, Stoi}

public enum EntityType {
    | NAME
    | PACKAGE
    | ANONYMOUS
    | GENERAL_FUNCTION
    | GENERIC_FUNCTION
    | GENERIC_DATA
    | EXTEND
    | LAMBDA
    | ERROR_ENTITY_TYPE
}

private func EntityTypeIndex(entityTy: EntityType): Int64 {
    return match (entityTy) {
        case EntityType.NAME => 0
        case EntityType.PACKAGE => 1
        case EntityType.ANONYMOUS => 2
        case EntityType.GENERAL_FUNCTION => 3
        case EntityType.GENERIC_FUNCTION => 4
        case EntityType.GENERIC_DATA => 5
        case EntityType.EXTEND => 6
        case EntityType.LAMBDA => 7
        case EntityType.ERROR_ENTITY_TYPE => 8
    }
}

extend EntityType <: Equatable<EntityType> {
    public operator func ==(right: EntityType): Bool {
        return EntityTypeIndex(this) == EntityTypeIndex(right)
    }

    public operator func !=(right: EntityType): Bool {
        return !(this == right)
    }
}

public enum BaseType {
    | PRIMITIVE_TYPE
    | ARRAY_TYPE
    | RAWARRAY_TYPE
    | VARRAY_TYPE
    | TUPLE_TYPE
    | CPOINTER_TYPE
    | CSTRING_TYPE
    | GENERIC_TYPE
    | ENUM_TYPE
    | STRUCT_TYPE
    | CLASS_TYPE
    | FUNCTION_TYPE
    | ERROR_BASE_TYPE
}

private func BaseTypeIndex(baseTy: BaseType): Int64 {
    return match (baseTy) {
        case BaseType.PRIMITIVE_TYPE => 0
        case BaseType.ARRAY_TYPE => 1
        case BaseType.RAWARRAY_TYPE => 2
        case BaseType.VARRAY_TYPE => 3
        case BaseType.TUPLE_TYPE => 4
        case BaseType.CPOINTER_TYPE => 5
        case BaseType.CSTRING_TYPE => 6
        case BaseType.GENERIC_TYPE => 7
        case BaseType.ENUM_TYPE => 8
        case BaseType.STRUCT_TYPE => 9
        case BaseType.CLASS_TYPE => 10
        case BaseType.FUNCTION_TYPE => 11
        case BaseType.ERROR_BASE_TYPE => 12
    }
}

extend BaseType <: Equatable<BaseType> {
    public operator func ==(right: BaseType): Bool {
        return BaseTypeIndex(this) == BaseTypeIndex(right)
    }

    public operator func !=(right: BaseType): Bool {
        return !(this == right)
    }
}

public open class Entity {
    public var mangledName: String
    public var entityTy: EntityType

    public init(mangledName: String, entityTy: EntityType) {
        this.mangledName = mangledName
        this.entityTy = entityTy
    }
}

public open class CJType {
    public var mangledName: String
    public var baseTy: BaseType

    public init(mangledName: String, baseTy: BaseType) {
        this.mangledName = mangledName
        this.baseTy = baseTy
    }
}

public class FunctionEntity <: Entity {
    public let paramTys: ArrayList<CJType> = ArrayList<CJType>()
    public let genericTys: ArrayList<CJType> = ArrayList<CJType>()

    public init(mangledName: String, entityTy: EntityType, paramTys: ArrayList<CJType>,
        genericTys: ArrayList<CJType>) {
        super(mangledName, entityTy)
        for (ty in paramTys) {
            this.paramTys.add(ty)
        }
        for (ty in genericTys) {
            this.genericTys.add(ty)
        }
    }
}

public class DataEntity <: Entity {
    public let genericTys: ArrayList<CJType> = ArrayList<CJType>()

    public init(mangledName: String, entityTy: EntityType, genericTys: ArrayList<CJType>) {
        super(mangledName, entityTy)
        for (ty in genericTys) {
            this.genericTys.add(ty)
        }
    }
}

public class ExtendEntity <: Entity {
    public var extendTy: CJType
    public var fileId: String
    public var localId: String

    public init(mangledName: String, entityTy: EntityType, extendTy: CJType, fileId: String, localId: String) {
        super(mangledName, entityTy)
        this.extendTy = extendTy
        this.fileId = fileId
        this.localId = localId
    }
}

public class CompositeType <: CJType {
    public let genericTys: ArrayList<CJType> = ArrayList<CJType>()
    public var pkg: String
    public var name: String

    public init(mangledName: String, baseTy: BaseType, genericTys: ArrayList<CJType>, pkg: String, name: String) {
        super(mangledName, baseTy)
        for (ty in genericTys) {
            this.genericTys.add(ty)
        }
        this.pkg = pkg
        this.name = name
    }
}

public class CompressionFunctionType <: CJType {
    public var retTy: CJType
    public let paramTys: ArrayList<CJType> = ArrayList<CJType>()

    public init(mangledName: String, baseTy: BaseType, retTy: CJType, paramTys: ArrayList<CJType>) {
        super(mangledName, baseTy)
        this.retTy = retTy
        for (ty in paramTys) {
            this.paramTys.add(ty)
        }
    }
}

public class CompressionTupleType <: CJType {
    public let elementTys: ArrayList<CJType> = ArrayList<CJType>()

    public init(mangledName: String, baseTy: BaseType, elementTys: ArrayList<CJType>) {
        super(mangledName, baseTy)
        for (ty in elementTys) {
            this.elementTys.add(ty)
        }
    }
}

public class ParseState {
    public var isCompressed: Bool = false
    public init() {}
}

public class StringRef {
    public var value: String
    public init(value: String) {
        this.value = value
    }
}

public class IntRef {
    public var value: Int64
    public init(value: Int64) {
        this.value = value
    }
}

private func CompressionDecimalToManglingNumber(decimal: String): String {
    CJC_ASSERT(!decimal.isEmpty())
    let base62Chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    for (ch in decimal.toArray()) {
        if (!IsDigit(ch)) {
            return ""
        }
    }
    if (let Some(parsed) <- Stoi(decimal)) {
        var num = parsed - 1
        if (num < 0) {
            return MANGLE_WILDCARD_PREFIX
        }
        var base62 = if (num > 0) { "" } else { "0" }
        while (num > 0) {
            let idx = num % base62Chars.size
            base62 = base62Chars[idx..idx + 1] + base62
            num /= base62Chars.size
        }
        return base62 + MANGLE_WILDCARD_PREFIX
    }
    return ""
}

private func forwardCompressed(mangled: String, idx: Int64, state: ParseState): Int64 {
    if (idx >= mangled.size) {
        return idx
    }
    if (mangled[idx] == MANGLE_COMPRESSED_PREFIX[0]) {
        state.isCompressed = true
        return ForwardNumber(mangled, idx: idx + MANGLE_CHAR_LEN)
    }
    return idx
}

private func isPropName(mangled: String, idx: Int64): Bool {
    if (idx + MANGLE_CHAR_LEN >= mangled.size) {
        return false
    }
    return mangled[idx] == b'p' && (mangled[idx + MANGLE_CHAR_LEN] == b's' || mangled[idx + MANGLE_CHAR_LEN] == b'g')
}

private func isSpecialName(mangled: String, idx: Int64, stdPkg!: Bool = false): Bool {
    if (idx + MANGLE_CHAR_LEN >= mangled.size) {
        return false
    }
    if (mangled[idx] < b'a' || mangled[idx] > b'y' || mangled[idx + MANGLE_CHAR_LEN] < b'a' ||
        mangled[idx + MANGLE_CHAR_LEN] > b'y') {
        return false
    }
    let code = mangled[idx..idx + MANGLE_SPECIAL_NAME_LEN]
    if (stdPkg) {
        return IsStdPackageMangleCode(code)
    }
    return IsOperatorMangleCode(code)
}

private func needCompressed(identifier: String): Bool {
    var pos: Int64 = 0
    var found = identifier.indexOf(MANGLE_COMPRESSED_PREFIX, pos)
    while (let Some(cur) <- found) {
        let nextIdx = ForwardNumber(identifier, idx: cur + MANGLE_CHAR_LEN)
        if (nextIdx != cur + MANGLE_CHAR_LEN) {
            return true
        }
        pos = cur + MANGLE_CHAR_LEN
        found = identifier.indexOf(MANGLE_COMPRESSED_PREFIX, pos)
    }
    return false
}

private func isGlobalEncode(mangled: String): Bool {
    return StartsWith(mangled, MANGLE_GLOBAL_VARIABLE_INIT_PREFIX) ||
        StartsWith(mangled, MANGLE_GLOBAL_PACKAGE_INIT_PREFIX) ||
        StartsWith(mangled, MANGLE_GLOBAL_FILE_INIT_PREFIX)
}

public func IsVarDeclEncode(mangled: String): Bool {
    let n = mangled.size
    if (n == 0) {
        return false
    }
    var idx: Int64 = 0
    if (mangled[0] == b'E') {
        return true
    } else if (IsDigit(mangled[0])) {
        let state = ParseState()
        idx = ForwardName(mangled, state, idx: 0)
        if (idx < n && mangled[idx] == b'K') {
            idx = ForwardNumber(mangled, idx: idx + MANGLE_CHAR_LEN)
            return idx < n && mangled[idx] == b'E'
        } else if (idx < n && mangled[idx] == b'E') {
            return true
        }
    } else if (mangled[0] == b'K') {
        idx = ForwardNumber(mangled, idx: idx + MANGLE_CHAR_LEN)
        if (idx < n && mangled[idx] == b'E') {
            return true
        }
    }
    return false
}

public func IsDefaultParamFuncEncode(mangled: String): Bool {
    return StartsWith(mangled, MANGLE_FUNC_PARA_INIT_PREFIX)
}

public func ForwardName(mangled: String, state: ParseState, idx!: Int64 = 0): Int64 {
    let cIdx = forwardCompressed(mangled, idx, state)
    if (state.isCompressed) {
        return cIdx
    }
    if (cIdx >= mangled.size) {
        return cIdx
    }
    if (isSpecialName(mangled, cIdx) || isPropName(mangled, cIdx)) {
        return cIdx + MANGLE_SPECIAL_NAME_LEN
    }
    if (!IsDigit(mangled[cIdx])) {
        return cIdx
    }
    if (mangled[cIdx] == MANGLE_ANONYMOUS_VARIABLE_PREFIX[0]) {
        return idx + MANGLE_CHAR_LEN
    }
    var numberLen: Int64 = 0
    while (idx + numberLen < mangled.size && IsDigit(mangled[idx + numberLen])) {
        numberLen++
    }
    if (let Some(number) <- Stoi(mangled[idx..idx + numberLen])) {
        return idx + numberLen + number
    }
    return idx
}

public func ForwardNumber(mangled: String, idx!: Int64 = 0): Int64 {
    var curIdx = idx
    while (curIdx < mangled.size && IsAlnum(mangled[curIdx])) {
        curIdx++
    }
    if (curIdx < mangled.size && mangled[curIdx] == b'_') {
        return curIdx + MANGLE_CHAR_LEN
    }
    return idx
}

private func forwardFileNameNumber(mangled: String, idx: Int64): Int64 {
    var curIdx = idx
    var isValid = false
    while (true) {
        if (curIdx >= mangled.size) {
            return idx
        }
        if (mangled[curIdx] == b'$') {
            return curIdx + 1
        }
        if (curIdx + 1 - idx == FILE_HASH_LEN) {
            isValid = true
            break
        }
        curIdx++
    }
    if (isValid) {
        var i = idx
        while (i <= curIdx) {
            if (!IsAlnum(mangled[i])) {
                return idx
            }
            i++
        }
        return curIdx + 1
    }
    return idx
}

private func forwardUnitPackageName(mangled: String, idx: Int64, state: ParseState): Int64 {
    var curIdx = idx
    if (isSpecialName(mangled, curIdx, stdPkg: true)) {
        curIdx += MANGLE_SPECIAL_NAME_LEN
    }
    if (curIdx != idx + MANGLE_SPECIAL_NAME_LEN) {
        curIdx = ForwardName(mangled, state, idx: idx)
        let cIdx = forwardCompressed(mangled, curIdx, state)
        if (state.isCompressed) {
            return cIdx
        }
    }
    return curIdx
}

private func forwardPackageName(mangled: String, idx: Int64, state: ParseState): Int64 {
    let curIdx = forwardUnitPackageName(mangled, idx, state)
    if (curIdx < mangled.size && mangled[curIdx] == b'U') {
        return forwardFileNameNumber(mangled, curIdx + MANGLE_CHAR_LEN)
    }
    return curIdx
}

private func forwardPrimitiveType(mangled: String, idx: Int64): Int64 {
    let n = mangled.size
    if (mangled[idx] != b'D' && IsPrimitivePrefix(mangled[idx])) {
        return idx + MANGLE_CHAR_LEN
    }
    if (mangled[idx] == b'D' && idx + MANGLE_CHAR_LEN < n && mangled[idx + MANGLE_CHAR_LEN] == b'h') {
        return idx + MANGLE_SPECIAL_NAME_LEN
    }
    return idx
}

private func forwardGenericTypes(mangled: String, tys: ArrayList<CJType>, state: ParseState, idx: Int64): Int64 {
    let curIdx = ForwardTypes(mangled, tys, state, startId: idx + MANGLE_CHAR_LEN)
    if (state.isCompressed) {
        return idx
    }
    if (curIdx < mangled.size && mangled[curIdx] == b'E') {
        return curIdx + MANGLE_CHAR_LEN
    }
    return idx
}

private func forwardGenericType(mangled: String, idx: Int64): Int64 {
    return ForwardNumber(mangled, idx: idx + MANGLE_CHAR_LEN)
}

private func forwardClassType(mangled: String, bt: BaseType, tys: ArrayList<CJType>, idx: Int64,
    state: ParseState): Int64 {
    forwardCompressed(mangled, idx, state)
    if (state.isCompressed) {
        return idx
    }
    var curIdx = idx
    let n = mangled.size
    var mangledName = ""
    let genericTys = ArrayList<CJType>()
    var pkg = ""
    var name = ""
    if (idx + MANGLE_PREFIX_LEN < n && (mangled[idx] == b'C' || mangled[idx] == b'R' || mangled[idx] == b'N') &&
        mangled[idx + MANGLE_CHAR_LEN] == b'N') {
        curIdx += MANGLE_PREFIX_LEN
    } else {
        tys.add(CompositeType(mangledName, BaseType.ERROR_BASE_TYPE, genericTys, pkg, name))
        return idx
    }
    let pIdx = curIdx
    curIdx = forwardPackageName(mangled, curIdx, state)
    if (state.isCompressed) {
        return idx
    }
    if (pIdx < n) {
        pkg = mangled[pIdx..curIdx]
    }
    let nIdx = curIdx
    curIdx = ForwardName(mangled, state, idx: curIdx)
    if (state.isCompressed) {
        return idx
    }
    if (nIdx < n) {
        name = mangled[nIdx..curIdx]
    }
    if (curIdx < n && mangled[curIdx] == b'I') {
        let genericIdx = forwardGenericTypes(mangled, genericTys, state, curIdx)
        if (state.isCompressed) {
            return idx
        }
        if (curIdx != genericIdx) {
            mangledName = mangled[idx..genericIdx]
            tys.add(CompositeType(mangledName, bt, genericTys, pkg, name))
            return genericIdx
        }
    } else if (curIdx < n && mangled[curIdx] == b'E') {
        mangledName = mangled[idx..curIdx + MANGLE_CHAR_LEN]
        tys.add(CompositeType(mangledName, bt, genericTys, pkg, name))
        return curIdx + MANGLE_CHAR_LEN
    }
    tys.add(CompositeType(mangledName, BaseType.ERROR_BASE_TYPE, genericTys, pkg, name))
    return idx
}

private func forwardFunctionType(mangled: String, tys: ArrayList<CJType>, idx: Int64, state: ParseState): Int64 {
    forwardCompressed(mangled, idx, state)
    if (state.isCompressed) {
        return idx
    }
    let retTy = ArrayList<CJType>()
    let paramTys = ArrayList<CJType>()
    var mangledName = ""
    var curIdx = ForwardTypeInternal(mangled, retTy, state, idx: idx + MANGLE_PREFIX_LEN)
    if (state.isCompressed) {
        return idx
    }
    curIdx = ForwardTypes(mangled, paramTys, state, startId: curIdx)
    if (state.isCompressed) {
        return idx
    }
    let ret = if (!retTy.isEmpty()) { retTy[0] } else { CJType("", BaseType.ERROR_BASE_TYPE) }
    if (curIdx < mangled.size && mangled[curIdx] == b'E') {
        mangledName = mangled[idx..curIdx + MANGLE_CHAR_LEN]
        tys.add(CompressionFunctionType(mangledName, BaseType.FUNCTION_TYPE, ret, paramTys))
        return curIdx + MANGLE_CHAR_LEN
    }
    tys.add(CompressionFunctionType(mangledName, BaseType.ERROR_BASE_TYPE, ret, paramTys))
    return idx
}

private func forwardTupleType(mangled: String, tys: ArrayList<CJType>, idx: Int64, state: ParseState): Int64 {
    forwardCompressed(mangled, idx, state)
    if (state.isCompressed) {
        return idx
    }
    let elementTys = ArrayList<CJType>()
    var mangledName = ""
    var curIdx = idx + MANGLE_CHAR_LEN
    if (curIdx < mangled.size) {
        curIdx = ForwardNumber(mangled, idx: curIdx)
    }
    if (curIdx < mangled.size) {
        let endIdx = ForwardTypes(mangled, elementTys, state, startId: curIdx)
        if (state.isCompressed) {
            return idx
        }
        if (curIdx != endIdx && endIdx < mangled.size && mangled[endIdx] == b'E') {
            mangledName = mangled[idx..endIdx + MANGLE_CHAR_LEN]
            tys.add(CompressionTupleType(mangledName, BaseType.TUPLE_TYPE, elementTys))
            return endIdx + MANGLE_CHAR_LEN
        }
    }
    tys.add(CompressionTupleType(mangledName, BaseType.ERROR_BASE_TYPE, elementTys))
    return idx
}

private func forwardCPointer(mangled: String, idx: Int64, state: ParseState): Int64 {
    forwardCompressed(mangled, idx, state)
    if (state.isCompressed) {
        return idx
    }
    let ty = ArrayList<CJType>()
    return ForwardTypeInternal(mangled, ty, state, idx: idx + MANGLE_CHAR_LEN)
}

private func forwardArrayType(mangled: String, idx: Int64, state: ParseState): Int64 {
    forwardCompressed(mangled, idx, state)
    if (state.isCompressed) {
        return idx
    }
    var curIdx = idx + MANGLE_CHAR_LEN
    if (curIdx < mangled.size) {
        curIdx = ForwardNumber(mangled, idx: curIdx)
    }
    if (curIdx < mangled.size) {
        let ty = ArrayList<CJType>()
        let endIdx = ForwardTypeInternal(mangled, ty, state, idx: curIdx)
        if (state.isCompressed) {
            return idx
        }
        if (endIdx != curIdx) {
            return endIdx
        }
    }
    return idx
}

private func ForwardTypeInternal(mangled: String, tys: ArrayList<CJType>, state: ParseState, idx!: Int64 = 0): Int64 {
    if (idx >= mangled.size) {
        return idx
    }
    let ch = mangled[idx]
    var bt = BaseType.ERROR_BASE_TYPE
    var nextIdx = idx
    if (ch == b'C') {
        bt = BaseType.CLASS_TYPE
        return forwardClassType(mangled, bt, tys, idx, state)
    } else if (ch == b'R') {
        bt = BaseType.STRUCT_TYPE
        return forwardClassType(mangled, bt, tys, idx, state)
    } else if (ch == b'N') {
        bt = BaseType.ENUM_TYPE
        return forwardClassType(mangled, bt, tys, idx, state)
    } else if (ch == b'F') {
        if (idx + MANGLE_CHAR_LEN < mangled.size &&
            (mangled[idx + MANGLE_CHAR_LEN] == b'0' || mangled[idx + MANGLE_CHAR_LEN] == b'C')) {
            nextIdx = forwardFunctionType(mangled, tys, idx, state)
        }
        return nextIdx
    } else if (ch == b'T') {
        return forwardTupleType(mangled, tys, idx, state)
    } else if (ch == b'P') {
        bt = BaseType.CPOINTER_TYPE
        nextIdx = forwardCPointer(mangled, idx, state)
    } else if (ch == b'A') {
        bt = BaseType.RAWARRAY_TYPE
        nextIdx = forwardArrayType(mangled, idx, state)
    } else if (ch == b'V') {
        bt = BaseType.VARRAY_TYPE
        nextIdx = forwardArrayType(mangled, idx, state)
    } else if (ch == b'k') {
        bt = BaseType.CSTRING_TYPE
        nextIdx = idx + MANGLE_CHAR_LEN
    } else if (ch == b'G') {
        bt = BaseType.GENERIC_TYPE
        nextIdx = forwardGenericType(mangled, idx)
    } else if (IsPrimitivePrefix(ch)) {
        bt = BaseType.PRIMITIVE_TYPE
        nextIdx = forwardPrimitiveType(mangled, idx)
    }
    if (state.isCompressed) {
        return idx
    }
    var mangledTy = ""
    if (nextIdx != idx) {
        mangledTy = mangled[idx..nextIdx]
        if (isGeneralType(bt)) {
            tys.add(CJType(mangledTy, bt))
        }
        return nextIdx
    }
    tys.add(CJType(mangledTy, bt))
    return idx
}

public func ForwardType(mangled: String, tys: ArrayList<CJType>, idx!: Int64 = 0): (Int64, Bool) {
    let state = ParseState()
    let endIdx = ForwardTypeInternal(mangled, tys, state, idx: idx)
    return (endIdx, state.isCompressed)
}

private func ForwardTypes(mangled: String, tys: ArrayList<CJType>, state: ParseState, startId!: Int64 = 0): Int64 {
    if (mangled.size - startId <= 0) {
        return startId
    }
    var idx = startId
    while (idx < mangled.size && mangled[idx] != b'E') {
        let curIdx = ForwardTypeInternal(mangled, tys, state, idx: idx)
        if (curIdx == idx || state.isCompressed) {
            return curIdx
        }
        idx = curIdx
    }
    return idx
}

public func ForwardTypes(mangled: String, tys: ArrayList<CJType>, startId!: Int64 = 0): (Int64, Bool) {
    let state = ParseState()
    let endIdx = ForwardTypes(mangled, tys, state, startId: startId)
    return (endIdx, state.isCompressed)
}

public func CJMangledCompression(mangled: String, isType!: Bool = false): String {
    let preIdx = IntRef(0)
    var cMangled = mangled
    cMangled = stripCangjieAt(cMangled, preIdxRef: preIdx)
    if (cMangled.isEmpty() || isType || !StartsWith(cMangled, MANGLE_CANGJIE_PREFIX) || needCompressed(cMangled)) {
        return mangled
    }
    cMangled = stripCangjiePrefix(cMangled, preIdxRef: preIdx)
    if (isGlobalEncode(cMangled)) {
        return mangled
    }
    let rest = StringRef("")
    let state = ParseState()
    if (IsDefaultParamFuncEncode(cMangled)) {
        let compressed = StringRef("")
        let nestedName = cMangled[MANGLE_PREFIX_LEN..]
        preIdx.value += MANGLE_PREFIX_LEN
        let entities = TryParsePath(nestedName, restRef: rest, state: state)
        if (state.isCompressed) {
            return mangled
        }
        if (SpanningDefaultParamFuncDeclTree(entities, rest.value, compressedRef: compressed)) {
            return mangled
        }
        return if (preIdx.value == 0) { compressed.value } else { mangled[0..preIdx.value] + compressed.value }
    }
    if (!cMangled.isEmpty() && cMangled[0] == b'N') {
        let compressed = StringRef("")
        let nestedName = cMangled[MANGLE_CHAR_LEN..]
        preIdx.value += MANGLE_CHAR_LEN
        let entities = TryParsePath(nestedName, restRef: rest, state: state)
        if (state.isCompressed) {
            return mangled
        }
        let failed = if (IsVarDeclEncode(rest.value)) {
            SpanningVarDeclTree(entities, rest.value, compressedRef: compressed)
        } else {
            SpanningFuncDeclTree(entities, rest.value, compressedRef: compressed)
        }
        if (failed) {
            return mangled
        }
        return if (preIdx.value == 0) { compressed.value } else { mangled[0..preIdx.value] + compressed.value }
    }
    return mangled
}

private func stripCangjieAt(identifier: String, preIdxRef!: IntRef): String {
    if (!identifier.isEmpty() && identifier[0] == b'@') {
        preIdxRef.value += MANGLE_CHAR_LEN
        return identifier[MANGLE_CHAR_LEN..]
    }
    return identifier
}

private func stripCangjiePrefix(identifier: String, preIdxRef!: IntRef): String {
    if (identifier.size > MANGLE_PREFIX_LEN) {
        preIdxRef.value += MANGLE_PREFIX_LEN
        return identifier[MANGLE_PREFIX_LEN..]
    }
    return identifier
}

private func isGeneralEntity(entityTy: EntityType): Bool {
    return !(entityTy == EntityType.GENERAL_FUNCTION || entityTy == EntityType.GENERIC_FUNCTION ||
        entityTy == EntityType.GENERIC_DATA || entityTy == EntityType.EXTEND)
}

private func isGeneralType(bt: BaseType): Bool {
    return !(bt == BaseType.TUPLE_TYPE || bt == BaseType.FUNCTION_TYPE || bt == BaseType.ENUM_TYPE ||
        bt == BaseType.STRUCT_TYPE || bt == BaseType.CLASS_TYPE)
}

private func tryGenericPrefixPath(mangled: String, state: ParseState, entities: ArrayList<Entity>, idx: Int64,
    startNextIdx: Int64, startEntityTy: EntityType): (Int64, EntityType, String, Bool) {
    let n = mangled.size
    var entityName = ""
    var entityTy = startEntityTy
    let genericTys = ArrayList<CJType>()
    var nextIdx = ForwardTypes(mangled, genericTys, state, startId: startNextIdx + MANGLE_CHAR_LEN)
    if (state.isCompressed) {
        return (nextIdx, entityTy, entityName, true)
    }
    if (nextIdx < n && mangled[nextIdx] == b'E') {
        entityTy = EntityType.GENERIC_DATA
        entityName = mangled[idx..nextIdx]
        entities.add(DataEntity(entityName, entityTy, genericTys))
        nextIdx += MANGLE_CHAR_LEN
    } else if (nextIdx < n && mangled[nextIdx] == b'H') {
        let paramTys = ArrayList<CJType>()
        nextIdx = ForwardTypes(mangled, paramTys, state, startId: nextIdx + MANGLE_CHAR_LEN)
        if (state.isCompressed) {
            return (nextIdx, entityTy, entityName, true)
        }
        if (nextIdx < n && mangled[nextIdx] == b'E') {
            nextIdx++
            entityTy = EntityType.GENERIC_FUNCTION
            entityName = mangled[idx..nextIdx]
            entities.add(FunctionEntity(entityName, entityTy, paramTys, genericTys))
        } else {
            nextIdx = idx
        }
    } else {
        nextIdx = idx
    }
    return (nextIdx, entityTy, entityName, false)
}

private func tryNamePrefixPath(mangled: String, state: ParseState, entities: ArrayList<Entity>, idx: Int64):
    (Int64, EntityType, String, Bool) {
    let n = mangled.size
    var entityName = ""
    var entityTy = EntityType.NAME
    var nextIdx = ForwardName(mangled, state, idx: idx)
    if (state.isCompressed) {
        return (nextIdx, entityTy, entityName, true)
    }
    let nameIdx = nextIdx
    if (nextIdx < n && mangled[nextIdx] == b'K') {
        nextIdx = ForwardNumber(mangled, idx: nextIdx + MANGLE_CHAR_LEN)
    }
    if (nextIdx < n) {
        if (mangled[nextIdx] == b'U') {
            nextIdx = forwardFileNameNumber(mangled, nameIdx + MANGLE_CHAR_LEN)
            entityTy = if (nextIdx == nameIdx + MANGLE_CHAR_LEN) { EntityType.ERROR_ENTITY_TYPE } else { EntityType.PACKAGE }
            nextIdx = if (nextIdx == nameIdx + MANGLE_CHAR_LEN) { nameIdx } else { nextIdx }
        } else if (mangled[nextIdx] == b'I') {
            return tryGenericPrefixPath(mangled, state, entities, idx, nextIdx, entityTy)
        } else if (mangled[nextIdx] == b'H') {
            let paramTys = ArrayList<CJType>()
            let genericTys = ArrayList<CJType>()
            nextIdx = ForwardTypes(mangled, paramTys, state, startId: nameIdx + MANGLE_CHAR_LEN)
            if (state.isCompressed) {
                return (nextIdx, entityTy, entityName, true)
            }
            if (nextIdx < n && mangled[nextIdx] == b'E') {
                nextIdx++
                entityTy = EntityType.GENERAL_FUNCTION
                entityName = mangled[idx..nextIdx]
                entities.add(FunctionEntity(entityName, entityTy, paramTys, genericTys))
            } else {
                nextIdx = idx
            }
        } else {
            nextIdx = nameIdx
        }
    }
    return (nextIdx, entityTy, entityName, false)
}

private func tryLambdaPath(mangled: String, idx: Int64): (Int64, EntityType) {
    var entityTy = EntityType.ERROR_ENTITY_TYPE
    var nextIdx = ForwardNumber(mangled, idx: idx + MANGLE_CHAR_LEN)
    if (nextIdx == mangled.size - MANGLE_CHAR_LEN && mangled[nextIdx] == b'E') {
        nextIdx = idx
    } else {
        entityTy = if (nextIdx == idx + MANGLE_CHAR_LEN) { EntityType.ERROR_ENTITY_TYPE } else { EntityType.LAMBDA }
        nextIdx = if (nextIdx == idx + MANGLE_CHAR_LEN) { idx } else { nextIdx }
    }
    return (nextIdx, entityTy)
}

private func tryExtendPath(mangled: String, state: ParseState, entities: ArrayList<Entity>, idx: Int64):
    (Int64, EntityType, String, Bool) {
    let n = mangled.size
    var entityTy = EntityType.ERROR_ENTITY_TYPE
    var entityName = ""
    let baseTy = ArrayList<CJType>()
    var nextIdx = ForwardTypeInternal(mangled, baseTy, state, idx: idx + MANGLE_CHAR_LEN)
    if (state.isCompressed) {
        return (nextIdx, entityTy, entityName, true)
    }
    let tyId = nextIdx
    var fileId = ""
    var localId = ""
    if (nextIdx < n && mangled[nextIdx] == b'U') {
        let fileIdx = nextIdx
        nextIdx = forwardFileNameNumber(mangled, nextIdx + MANGLE_CHAR_LEN)
        fileId = mangled[fileIdx..nextIdx]
        if (nextIdx < n && mangled[nextIdx] == b'K') {
            let localIdx = nextIdx
            nextIdx = ForwardNumber(mangled, idx: nextIdx)
            localId = mangled[localIdx..nextIdx]
            entityName = mangled[idx..nextIdx]
            entityTy = EntityType.EXTEND
            entities.add(ExtendEntity(entityName, entityTy, baseTy[0], fileId, localId))
        } else {
            nextIdx = idx
        }
    } else {
        nextIdx = tyId
        entityTy = EntityType.EXTEND
        entityName = mangled[idx..nextIdx]
        if (!baseTy.isEmpty()) {
            entities.add(ExtendEntity(entityName, entityTy, baseTy[0], fileId, localId))
        }
    }
    return (nextIdx, entityTy, entityName, false)
}

public func TryParsePath(mangled: String, restRef!: StringRef, state!: ParseState = ParseState()): ArrayList<Entity> {
    let n = mangled.size
    let entities = ArrayList<Entity>()
    var idx: Int64 = 0
    while (idx < n) {
        let ch = mangled[idx]
        var nextIdx = idx
        var entityTy = EntityType.ERROR_ENTITY_TYPE
        if (ch == b'0') {
            nextIdx = ForwardNumber(mangled, idx: nextIdx + MANGLE_CHAR_LEN)
            entityTy = if (nextIdx == idx + MANGLE_CHAR_LEN) { EntityType.ERROR_ENTITY_TYPE } else { EntityType.ANONYMOUS }
            nextIdx = if (nextIdx == idx + MANGLE_CHAR_LEN) { idx } else { nextIdx }
        } else if (IsDigit(ch) || isSpecialName(mangled, idx) || isPropName(mangled, idx)) {
            let parsed = tryNamePrefixPath(mangled, state, entities, idx)
            nextIdx = parsed[0]
            entityTy = parsed[1]
            if (parsed[3]) {
                return entities
            }
        } else if (ch == b'X') {
            let parsed = tryExtendPath(mangled, state, entities, idx)
            nextIdx = parsed[0]
            entityTy = parsed[1]
            if (parsed[3]) {
                return entities
            }
        } else if (ch == b'L') {
            let parsed = tryLambdaPath(mangled, idx)
            nextIdx = parsed[0]
            entityTy = parsed[1]
        } else if (isSpecialName(mangled, idx, stdPkg: true)) {
            nextIdx = forwardPackageName(mangled, idx, state)
            entityTy = EntityType.PACKAGE
        }
        if (idx != nextIdx && entityTy != EntityType.ERROR_ENTITY_TYPE) {
            if (isGeneralEntity(entityTy)) {
                let mangledName = mangled[idx..nextIdx]
                entities.add(Entity(mangledName, entityTy))
            }
            idx = nextIdx
        } else {
            break
        }
    }
    if (idx < n) {
        restRef.value = mangled[idx..]
    } else {
        restRef.value = ""
    }
    return entities
}

public func SpanningVarDeclTree(entities: ArrayList<Entity>, mangled: String, compressedRef!: StringRef): Bool {
    let treeIdMap = HashMap<String, Int64>()
    let mid = IntRef(0)
    for (entity in entities) {
        RecursionEntity(entity, treeIdMap, midRef: mid, compressedRef: compressedRef)
    }
    if (mangled.size > 0 && IsDigit(mangled[0])) {
        let state = ParseState()
        let idx = ForwardName(mangled, state, idx: 0)
        if (state.isCompressed) {
            return true
        }
        var name = mangled[0..idx]
        RecursionHelper(name, treeIdMap, midRef: mid, compressedRef: compressedRef, isReplaced: false)
        if (idx < mangled.size) {
            compressedRef.value += mangled[idx..]
        }
    } else if (mangled.size > 0 && !IsDigit(mangled[0])) {
        compressedRef.value += mangled
    }
    return false
}

private func spanningFuncSubTree(treeIdMap: HashMap<String, Int64>, mangled: String, compressed: String,
    idx: Int64, midRef!: IntRef): (Bool, Int64, String) {
    let n = mangled.size
    var out = compressed
    var curIdx = idx
    let state = ParseState()
    if (curIdx < n && mangled[curIdx] == b'I') {
        out += MANGLE_GENERIC_PREFIX
        let genericTys = ArrayList<CJType>()
        let nextIdx = ForwardTypes(mangled, genericTys, state, startId: curIdx + MANGLE_CHAR_LEN)
        if (state.isCompressed) {
            return (true, curIdx, out)
        }
        if (nextIdx != curIdx + MANGLE_CHAR_LEN) {
            curIdx = nextIdx
        }
        for (ty in genericTys) {
            let outRef = StringRef(out)
            RecursionType(ty, treeIdMap, midRef: midRef, compressedRef: outRef, isReplaced: false)
            out = outRef.value
        }
    }
    if (curIdx < n && mangled[curIdx] == b'H') {
        let paramTys = ArrayList<CJType>()
        let nextIdx = ForwardTypes(mangled, paramTys, state, startId: curIdx + MANGLE_CHAR_LEN)
        if (state.isCompressed) {
            return (true, curIdx, out)
        }
        if (nextIdx != curIdx + MANGLE_CHAR_LEN && !paramTys.isEmpty()) {
            out += MANGLE_FUNC_PARAM_TYPE_PREFIX
            for (ty in paramTys) {
                let outRef = StringRef(out)
                RecursionType(ty, treeIdMap, midRef: midRef, compressedRef: outRef, isReplaced: false)
                out = outRef.value
            }
            curIdx = nextIdx
        }
    }
    return (false, curIdx, out)
}

public func SpanningFuncDeclTree(entities: ArrayList<Entity>, mangled: String, compressedRef!: StringRef): Bool {
    let mid = IntRef(0)
    let n = mangled.size
    let treeIdMap = HashMap<String, Int64>()
    for (entity in entities) {
        RecursionEntity(entity, treeIdMap, midRef: mid, compressedRef: compressedRef)
    }
    if (n == 0 || (n > 0 && mangled[0] == b'L')) {
        compressedRef.value += mangled
        return false
    }
    var idx: Int64 = 0
    let state = ParseState()
    if (IsDigit(mangled[idx]) || isSpecialName(mangled, idx) || isPropName(mangled, idx)) {
        idx = ForwardName(mangled, state, idx: 0)
        if (state.isCompressed) {
            return true
        }
        var funcName = mangled[0..idx]
        if (idx != 0) {
            var whole = mangled
            RecursionHelper(whole, treeIdMap, midRef: mid, compressedRef: compressedRef, isReplaced: true)
            RecursionHelper(funcName, treeIdMap, midRef: mid, compressedRef: compressedRef, isReplaced: false)
        }
    }
    let sub = spanningFuncSubTree(treeIdMap, mangled, compressedRef.value, idx, midRef: mid)
    if (sub[0]) {
        return true
    }
    idx = sub[1]
    compressedRef.value = sub[2]
    if (idx < n) {
        compressedRef.value += mangled[idx..]
    }
    return false
}

public func SpanningDefaultParamFuncDeclTree(entities: ArrayList<Entity>, mangled: String,
    compressedRef!: StringRef): Bool {
    let mid = IntRef(0)
    let n = mangled.size
    let treeIdMap = HashMap<String, Int64>()
    for (entity in entities) {
        RecursionEntity(entity, treeIdMap, midRef: mid, compressedRef: compressedRef)
    }
    if (n == 0) {
        return false
    }
    var idx: Int64 = 0
    let state = ParseState()
    if (IsDigit(mangled[idx]) || isSpecialName(mangled, idx) || isPropName(mangled, idx)) {
        idx = ForwardName(mangled, state, idx: 0)
        if (state.isCompressed) {
            return true
        }
        var funcName = mangled[0..idx]
        if (idx != 0) {
            var whole = mangled
            RecursionHelper(whole, treeIdMap, midRef: mid, compressedRef: compressedRef, isReplaced: true)
            RecursionHelper(funcName, treeIdMap, midRef: mid, compressedRef: compressedRef, isReplaced: false)
        }
        let sub = spanningFuncSubTree(treeIdMap, mangled, compressedRef.value, idx, midRef: mid)
        if (sub[0]) {
            return true
        }
        idx = sub[1]
        compressedRef.value = sub[2]
    }
    if (idx < n) {
        compressedRef.value += mangled[idx..]
    }
    return false
}

public func RecursionHelper(nameRef: String, treeIdMap: HashMap<String, Int64>, midRef!: IntRef,
    compressedRef!: StringRef, isReplaced!: Bool, isLeaf!: Bool = true): Bool {
    var name = nameRef
    if (name.isEmpty()) {
        return false
    }
    if (!treeIdMap.contains(name)) {
        treeIdMap[name] = midRef.value
        midRef.value++
        if (!isReplaced && isLeaf) {
            compressedRef.value += name
        }
    } else {
        if (!isReplaced) {
            let cid = MANGLE_COMPRESSED_PREFIX + CompressionDecimalToManglingNumber("${treeIdMap[name]}")
            if (name.size > cid.size) {
                compressedRef.value += cid
            } else {
                compressedRef.value += name
            }
            return true
        }
    }
    return false
}

private func recursionFuncEntity(entity: Entity, treeIdMap: HashMap<String, Int64>, midRef!: IntRef,
    compressed!: String, isGeneric!: Bool, isReplaced!: Bool): String {
    let state = ParseState()
    let idx = ForwardName(entity.mangledName, state, idx: 0)
    var out = compressed
    var funcName = entity.mangledName[0..idx]
    var outRef = StringRef(out)
    RecursionHelper(funcName, treeIdMap, midRef: midRef, compressedRef: outRef, isReplaced: isReplaced)
    out = outRef.value
    if (let Some(fe) <- (entity as FunctionEntity)) {
        if (isGeneric) {
            if (!fe.genericTys.isEmpty()) {
                out += MANGLE_GENERIC_PREFIX
            }
            for (gty in fe.genericTys) {
                outRef = StringRef(out)
                RecursionType(gty, treeIdMap, midRef: midRef, compressedRef: outRef, isReplaced: isReplaced)
                out = outRef.value
            }
        }
        if (!fe.paramTys.isEmpty()) {
            out += MANGLE_FUNC_PARAM_TYPE_PREFIX
        }
        for (pty in fe.paramTys) {
            outRef = StringRef(out)
            RecursionType(pty, treeIdMap, midRef: midRef, compressedRef: outRef, isReplaced: isReplaced)
            out = outRef.value
        }
        if (!fe.paramTys.isEmpty()) {
            out += MANGLE_SUFFIX
        }
    }
    return out
}

public func RecursionEntity(entity: Entity, treeIdMap: HashMap<String, Int64>, midRef!: IntRef,
    compressedRef!: StringRef): Unit {
    if (entity.mangledName.isEmpty()) {
        return
    }
    var isReplaced = false
    if (entity.entityTy == EntityType.PACKAGE ||
        (EntityTypeIndex(entity.entityTy) >= EntityTypeIndex(EntityType.GENERAL_FUNCTION) &&
            EntityTypeIndex(entity.entityTy) <= EntityTypeIndex(EntityType.EXTEND))) {
        isReplaced = RecursionHelper(entity.mangledName, treeIdMap, midRef: midRef, compressedRef: compressedRef,
            isReplaced: false, isLeaf: false)
        if (isReplaced) {
            return
        }
    }
    match (entity.entityTy) {
        case EntityType.NAME | EntityType.LAMBDA | EntityType.ANONYMOUS =>
            RecursionHelper(entity.mangledName, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                isReplaced: false)
        case EntityType.PACKAGE =>
            let state = ParseState()
            let idx = forwardUnitPackageName(entity.mangledName, 0, state)
            var pkg = entity.mangledName[0..idx]
            RecursionHelper(pkg, treeIdMap, midRef: midRef, compressedRef: compressedRef, isReplaced: isReplaced)
            var fid = entity.mangledName[idx..]
            RecursionHelper(fid, treeIdMap, midRef: midRef, compressedRef: compressedRef, isReplaced: isReplaced)
        case EntityType.GENERAL_FUNCTION =>
            compressedRef.value = recursionFuncEntity(entity, treeIdMap, midRef: midRef,
                compressed: compressedRef.value, isGeneric: false, isReplaced: isReplaced)
        case EntityType.GENERIC_FUNCTION =>
            compressedRef.value = recursionFuncEntity(entity, treeIdMap, midRef: midRef,
                compressed: compressedRef.value, isGeneric: true, isReplaced: isReplaced)
        case EntityType.GENERIC_DATA =>
            let state = ParseState()
            let idx = ForwardName(entity.mangledName, state, idx: 0)
            var name = entity.mangledName[0..idx]
            RecursionHelper(name, treeIdMap, midRef: midRef, compressedRef: compressedRef, isReplaced: isReplaced)
            if (let Some(de) <- (entity as DataEntity)) {
                if (!de.genericTys.isEmpty()) {
                    compressedRef.value += MANGLE_GENERIC_PREFIX
                }
                for (gty in de.genericTys) {
                    RecursionType(gty, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                        isReplaced: isReplaced)
                }
                if (!de.genericTys.isEmpty()) {
                    compressedRef.value += MANGLE_SUFFIX
                }
            }
        case EntityType.EXTEND =>
            if (let Some(ee) <- (entity as ExtendEntity)) {
                compressedRef.value += MANGLE_EXTEND_PREFIX
                RecursionType(ee.extendTy, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                    isReplaced: isReplaced)
                var fileId = ee.fileId
                RecursionHelper(fileId, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                    isReplaced: isReplaced)
                var localId = ee.localId
                RecursionHelper(localId, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                    isReplaced: isReplaced)
            }
        case _ =>
            RecursionHelper(entity.mangledName, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                isReplaced: false)
    }
}

public func RecursionType(ty: CJType, treeIdMap: HashMap<String, Int64>, midRef!: IntRef, compressedRef!: StringRef,
    isReplaced!: Bool): Unit {
    var replaced = isReplaced
    if (replaced || ty.mangledName.isEmpty()) {
        return
    }
    if ((BaseTypeIndex(ty.baseTy) >= BaseTypeIndex(BaseType.RAWARRAY_TYPE) &&
            BaseTypeIndex(ty.baseTy) <= BaseTypeIndex(BaseType.CPOINTER_TYPE)) ||
        (BaseTypeIndex(ty.baseTy) >= BaseTypeIndex(BaseType.ENUM_TYPE) &&
            BaseTypeIndex(ty.baseTy) <= BaseTypeIndex(BaseType.FUNCTION_TYPE))) {
        replaced = RecursionHelper(ty.mangledName, treeIdMap, midRef: midRef, compressedRef: compressedRef,
            isReplaced: replaced, isLeaf: false)
        if (replaced) {
            return
        }
    }
    match (ty.baseTy) {
        case BaseType.PRIMITIVE_TYPE =>
            compressedRef.value += ty.mangledName
        case BaseType.CSTRING_TYPE | BaseType.GENERIC_TYPE =>
            RecursionHelper(ty.mangledName, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                isReplaced: replaced)
        case BaseType.RAWARRAY_TYPE | BaseType.VARRAY_TYPE =>
            let idx = ForwardNumber(ty.mangledName, idx: MANGLE_CHAR_LEN)
            compressedRef.value += ty.mangledName[0..idx]
            let state = ParseState()
            let vty = ArrayList<CJType>()
            ForwardTypeInternal(ty.mangledName, vty, state, idx: idx)
            if (!vty.isEmpty()) {
                RecursionType(vty[0], treeIdMap, midRef: midRef, compressedRef: compressedRef, isReplaced: replaced)
            }
        case BaseType.TUPLE_TYPE =>
            let idx = ForwardNumber(ty.mangledName, idx: MANGLE_CHAR_LEN)
            compressedRef.value += ty.mangledName[0..idx]
            if (let Some(tty) <- (ty as CompressionTupleType)) {
                for (param in tty.elementTys) {
                    RecursionType(param, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                        isReplaced: replaced)
                }
            }
            compressedRef.value += MANGLE_SUFFIX
        case BaseType.CPOINTER_TYPE =>
            compressedRef.value += MANGLE_POINTER_PREFIX
            let state = ParseState()
            let pty = ArrayList<CJType>()
            ForwardTypeInternal(ty.mangledName, pty, state, idx: MANGLE_CHAR_LEN)
            if (!pty.isEmpty()) {
                RecursionType(pty[0], treeIdMap, midRef: midRef, compressedRef: compressedRef, isReplaced: replaced)
            }
        case BaseType.ENUM_TYPE | BaseType.STRUCT_TYPE | BaseType.CLASS_TYPE =>
            compressedRef.value += ty.mangledName[0..MANGLE_PREFIX_LEN]
            if (let Some(ct) <- (ty as CompositeType)) {
                let state = ParseState()
                let idx = forwardPackageName(ct.pkg, 0, state)
                var pkg = ct.pkg[0..idx]
                RecursionHelper(pkg, treeIdMap, midRef: midRef, compressedRef: compressedRef, isReplaced: replaced)
                if (idx < ct.pkg.size) {
                    var fid = ct.pkg[idx..]
                    RecursionHelper(fid, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                        isReplaced: replaced)
                }
                var name = ct.name
                RecursionHelper(name, treeIdMap, midRef: midRef, compressedRef: compressedRef, isReplaced: replaced)
                if (!ct.genericTys.isEmpty()) {
                    compressedRef.value += MANGLE_GENERIC_PREFIX
                }
                for (gty in ct.genericTys) {
                    RecursionType(gty, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                        isReplaced: replaced)
                }
                if (!replaced) {
                    compressedRef.value += MANGLE_SUFFIX
                }
            }
        case BaseType.FUNCTION_TYPE =>
            compressedRef.value += ty.mangledName[0..MANGLE_PREFIX_LEN]
            if (let Some(ft) <- (ty as CompressionFunctionType)) {
                RecursionType(ft.retTy, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                    isReplaced: replaced)
                for (param in ft.paramTys) {
                    RecursionType(param, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                        isReplaced: replaced)
                }
            }
            compressedRef.value += MANGLE_SUFFIX
        case _ =>
            RecursionHelper(ty.mangledName, treeIdMap, midRef: midRef, compressedRef: compressedRef,
                isReplaced: false)
    }
}
