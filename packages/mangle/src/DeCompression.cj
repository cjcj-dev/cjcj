package cjcj::mangle

import std.collection.*

private let NPOS: Int64 = -1
private let MANGLE_COMPRESS_PREFIX: Byte = b'Y'
private let MANGLE_ANONYMOUS_PREFIX: Byte = b'0'
private let PREFIX_LEN: Int64 = 2
private let PRIMITIVE_PREFIX_SET: String = "nucbfdasilqhtjmrDv"

private func StripCangjieAt(identifier: String, idx: Int64): Int64 {
    if (idx < identifier.size && identifier[idx] == b'@') {
        return idx + MANGLE_CHAR_LEN
    }
    return idx
}

private func StripCangjiePrefix(identifier: String, idx: Int64): Int64 {
    if (idx + MANGLE_CHAR_LEN < identifier.size && identifier[idx] == b'_' &&
        identifier[idx + MANGLE_CHAR_LEN] == b'C') {
        if (idx + MANGLE_CHAR_LEN * 2 < identifier.size && identifier[idx + MANGLE_CHAR_LEN * 2] == b'V') {
            return idx + PREFIX_LEN + MANGLE_CHAR_LEN
        } else {
            return idx + PREFIX_LEN
        }
    }
    return idx
}

private func GetNumber(base62: String): Int64 {
    let base62Chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    let n: Int64 = 62
    if (base62 == "_") {
        return 0
    }
    let newBase62 = base62[0..base62.size - 1]
    var decimal: Int64 = 0
    var power: Int64 = 1
    var i = newBase62.size - 1
    while (i != NPOS) {
        var baseIndex: Int64 = 0
        while (baseIndex < base62Chars.size) {
            if (base62Chars[baseIndex] == newBase62[i]) {
                decimal += baseIndex * power
                break
            }
            baseIndex++
        }
        power *= n
        i--
    }
    return decimal + 1
}

private func IsStdPkgName(mangled: String, idx: Int64): Bool {
    if (idx + MANGLE_CHAR_LEN >= mangled.size) {
        return false
    }
    return MANGLE_STDPKG_MAP(mangled[idx..idx + MANGLE_SPECIAL_NAME_LEN]).isSome()
}

private func IsOperatorName(mangled: String, idx: Int64): Bool {
    if (idx + MANGLE_CHAR_LEN >= mangled.size) {
        return false
    }
    if (!((mangled[idx] >= b'a' && mangled[idx] <= b'z') &&
        (mangled[idx + MANGLE_CHAR_LEN] >= b'a' && mangled[idx + MANGLE_CHAR_LEN] <= b'z'))) {
        return false
    }
    let operatorIndex = ((Int64(mangled[idx]) - Int64(b'a')) << 5) +
        Int64(mangled[idx + MANGLE_CHAR_LEN]) - Int64(b'a')
    return match (operatorIndex) {
        case 279 => true
        case 435 => true
        case 422 => true
        case 502 => true
        case 395 => true
        case 117 => true
        case 556 => true
        case 491 => true
        case 370 => true
        case 562 => true
        case 371 => true
        case 211 => true
        case 356 => true
        case 196 => true
        case 144 => true
        case 420 => true
        case 13 => true
        case 142 => true
        case 465 => true
        case 75 => true
        case _ => false
    }
}

private func IsPrimitiveType(ch: Byte): Bool {
    var i: Int64 = 0
    while (i < PRIMITIVE_PREFIX_SET.size) {
        if (ch == PRIMITIVE_PREFIX_SET[i]) {
            return true
        }
        i++
    }
    return false
}

private func IsPropName(mangled: String, idx: Int64): Bool {
    if (idx + MANGLE_CHAR_LEN >= mangled.size) {
        return false
    }
    if (mangled[idx] == b'p' && (mangled[idx + MANGLE_CHAR_LEN] == b's' ||
        mangled[idx + MANGLE_CHAR_LEN] == b'g')) {
        return true
    }
    return false
}

private func ForwardPrimitiveType(mangled: String, idx: Int64): Int64 {
    if (mangled[idx] != b'D' && IsPrimitiveType(mangled[idx])) {
        return idx + MANGLE_CHAR_LEN
    }
    if (idx + MANGLE_CHAR_LEN < mangled.size && mangled[idx] == b'D' &&
        mangled[idx + MANGLE_CHAR_LEN] == b'h') {
        return idx + MANGLE_SPECIAL_NAME_LEN
    }
    return idx
}

private func ForwardFileNameNumber(mangled: String, idx: Int64): Int64 {
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

class DeCompression {
    private var pid: Int64 = 0
    private var isRecord: Bool
    private var mangledName: String
    private var currentIndex: Int64 = 0
    private var decompressed: String = ""
    private let treeIdMap: ArrayList<(Int64, Int64)> = ArrayList<(Int64, Int64)>()

    init(mangled: String) {
        isRecord = false
        mangledName = mangled
    }

    func IsGlobalEncode(mangled: StringRef): Bool {
        if (IsSamePrefix(mangled, "GV", 0) || IsSamePrefix(mangled, "GP", 0) ||
            IsSamePrefix(mangled, "GF", 0)) {
            return true
        }
        return false
    }

    func IsSamePrefix(first: StringRef, second: String, idx: Int64): Bool {
        var i = idx
        while (i < idx + PREFIX_LEN) {
            if (i < first.value.size && i < second.size && first.value[i] != second[i]) {
                return false
            }
            i++
        }
        return true
    }

    func IsVarDeclEncode(mangled: StringRef): Bool {
        this.isRecord = false
        let n = mangled.value.size
        if (n == 0) {
            return false
        }
        var idx: Int64 = 0
        if (mangled.value[0] == b'E') {
            return true
        } else if (mangled.value[0] == MANGLE_COMPRESS_PREFIX) {
            idx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
            if (idx < n && mangled.value[idx] == b'E') {
                return true
            }
        } else if (IsDigit(mangled.value[0])) {
            idx = ForwardName(mangled, idx: 0)
            if (idx < n && mangled.value[idx] == b'K') {
                idx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
                if (idx < n && mangled.value[idx] == b'E') {
                    return true
                } else {
                    return false
                }
            } else if (idx < n && mangled.value[idx] == b'E') {
                return true
            }
        } else if (mangled.value[0] == b'K') {
            idx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
            if (idx < n && mangled.value[idx] == b'E') {
                return true
            }
        }
        return false
    }

    func IsDefaultParamFuncEncode(mangled: StringRef): Bool {
        if (IsSamePrefix(mangled, "PI", 0)) {
            return true
        }
        return false
    }

    func HasDuplicates(mangled: StringRef, pos: (Int64, Int64)): Bool {
        let posStr = mangled.value[pos[0]..pos[0] + pos[1]]
        for (item in treeIdMap) {
            let itStr = mangled.value[item[0]..item[0] + item[1]]
            if (itStr.isEmpty()) {
                continue
            }
            if (itStr == posStr) {
                return true
            }
        }
        return false
    }

    func HasDuplicates(mangled: StringRef, mid: Int64): Bool {
        if (mid >= treeIdMap.size) {
            return false
        }
        let cur = treeIdMap[mid]
        let curStr = mangled.value[cur[0]..cur[0] + cur[1]]
        var tid: Int64 = 0
        for (item in treeIdMap) {
            if (tid == mid) {
                tid++
                continue
            }
            let itStr = mangled.value[item[0]..item[0] + item[1]]
            if (itStr.isEmpty()) {
                tid++
                continue
            }
            if (itStr == curStr) {
                return true
            }
            tid++
        }
        return false
    }

    func ForwardPackageName(mangled: StringRef, cnt: IntRef, idx: Int64): Int64 {
        var curIdx = idx
        if (IsStdPkgName(mangled.value, curIdx)) {
            curIdx += MANGLE_SPECIAL_NAME_LEN
        } else {
            curIdx = ForwardName(mangled, idx: idx)
        }
        if (this.isRecord && curIdx != idx) {
            let pos = (idx, curIdx - idx)
            let isPush = TreeIdMapPushBack(mangled, pos)
            cnt.value = if (isPush) { cnt.value + 1 } else { cnt.value }
        }
        if (curIdx < mangled.value.size && mangled.value[curIdx] == b'U') {
            let fid = ForwardFileNameNumber(mangled.value, curIdx + MANGLE_CHAR_LEN)
            if (this.isRecord && fid != curIdx + MANGLE_CHAR_LEN) {
                let pos = (curIdx, fid - curIdx)
                let isPush = TreeIdMapPushBack(mangled, pos)
                cnt.value = if (isPush) { cnt.value + 1 } else { cnt.value }
            }
            curIdx = fid
        }
        return curIdx
    }

    func ForwardGenericTypes(mangled: StringRef, cnt: IntRef, idx: Int64): Int64 {
        let curCnt = cnt.value
        let curIdx = ForwardTypes(mangled, cnt, startId: idx + MANGLE_CHAR_LEN)
        if (curIdx < mangled.value.size && mangled.value[curIdx] == b'E') {
            return curIdx + MANGLE_CHAR_LEN
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    func ForwardClassType(mangled: StringRef, cnt: IntRef, idx: Int64): Int64 {
        var curIdx = idx
        let curCnt = cnt.value
        if (idx + PREFIX_LEN < mangled.value.size &&
            (mangled.value[idx] == b'C' || mangled.value[idx] == b'R' || mangled.value[idx] == b'N') &&
            mangled.value[idx + MANGLE_CHAR_LEN] == b'N') {
            curIdx += PREFIX_LEN
        } else {
            return idx
        }
        UpdateCompressedName(mangled, curIdx)
        curIdx = ForwardPackageName(mangled, cnt, curIdx)
        let fid = curIdx
        UpdateCompressedName(mangled, fid)
        curIdx = ForwardName(mangled, idx: fid)
        if (this.isRecord && curIdx != fid) {
            let pos = (fid, curIdx - fid)
            let isPush = TreeIdMapPushBack(mangled, pos)
            cnt.value = if (isPush) { cnt.value + 1 } else { cnt.value }
        }
        if (curIdx < mangled.value.size && mangled.value[curIdx] == b'I') {
            let genericIdx = ForwardGenericTypes(mangled, cnt, curIdx)
            if (curIdx != genericIdx) {
                return genericIdx
            }
        } else if (curIdx < mangled.value.size && mangled.value[curIdx] == b'E') {
            return curIdx + MANGLE_CHAR_LEN
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    func ForwardFunctionType(mangled: StringRef, cnt: IntRef, idx: Int64): Int64 {
        let curCnt = cnt.value
        var curIdx = ForwardType(mangled, cnt, idx: idx + PREFIX_LEN)
        curIdx = ForwardTypes(mangled, cnt, startId: curIdx)
        if (curIdx < mangled.value.size && mangled.value[curIdx] == b'E') {
            return curIdx + MANGLE_CHAR_LEN
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    func ForwardTupleType(mangled: StringRef, cnt: IntRef, idx: Int64): Int64 {
        let curIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
        if (curIdx == idx + MANGLE_CHAR_LEN || curIdx >= mangled.value.size ||
            idx + MANGLE_CHAR_LEN >= mangled.value.size) {
            return idx
        }
        let curCnt = cnt.value
        var tyCnt = GetNumber(mangled.value[idx + MANGLE_CHAR_LEN..curIdx])
        var endIdx = curIdx
        while (endIdx < mangled.value.size && mangled.value[endIdx] != b'E' && tyCnt != 0) {
            let tyIdx = ForwardType(mangled, cnt, idx: endIdx)
            if (tyIdx == endIdx) {
                break
            }
            endIdx = tyIdx
            tyCnt--
        }
        if (curIdx != endIdx && endIdx < mangled.value.size && mangled.value[endIdx] == b'E') {
            return endIdx + MANGLE_CHAR_LEN
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    func ForwardCPointer(mangled: StringRef, cnt: IntRef, idx: Int64): Int64 {
        return ForwardType(mangled, cnt, idx: idx + MANGLE_CHAR_LEN)
    }

    func ForwardArrayType(mangled: StringRef, cnt: IntRef, idx: Int64): Int64 {
        let curCnt = cnt.value
        var curIdx = idx + MANGLE_CHAR_LEN
        if (curIdx < mangled.value.size) {
            curIdx = ForwardNumber(mangled, curIdx)
            if (curIdx < mangled.value.size) {
                let endIdx = ForwardType(mangled, cnt, idx: curIdx)
                if (endIdx != curIdx) {
                    return endIdx
                }
            }
        }
        if (this.isRecord) {
            TreeIdMapPop(cnt, curCnt)
        }
        return idx
    }

    func ForwardGenericType(mangled: StringRef, cnt: IntRef, idx: Int64): Int64 {
        let nextIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
        if (nextIdx != idx + MANGLE_CHAR_LEN) {
            return nextIdx
        }
        return idx
    }

    func ForwardNumber(mangled: StringRef, idx: Int64): Int64 {
        var curIdx = idx
        while (curIdx < mangled.value.size && IsAlnum(mangled.value[curIdx])) {
            curIdx++
        }
        if (curIdx < mangled.value.size && mangled.value[curIdx] == b'_') {
            return curIdx + MANGLE_CHAR_LEN
        }
        return idx
    }

    func ForwardName(mangled: StringRef, idx!: Int64 = 0): Int64 {
        if (idx >= mangled.value.size) {
            return idx
        }
        if (IsOperatorName(mangled.value, idx) || IsPropName(mangled.value, idx)) {
            return idx + MANGLE_SPECIAL_NAME_LEN
        }
        if (!IsDigit(mangled.value[idx])) {
            return idx
        }
        if (mangled.value[idx] == MANGLE_ANONYMOUS_PREFIX) {
            return idx + MANGLE_CHAR_LEN
        }
        var numberLen: Int64 = 0
        while (idx + numberLen < mangled.value.size && IsDigit(mangled.value[idx + numberLen])) {
            numberLen++
        }
        var number: Int64 = 0
        var numberIdx: Int64 = 0
        while (numberIdx < numberLen) {
            number = number * 10 + Int64(mangled.value[idx + numberIdx] - b'0')
            if (number > 4294967295) {
                return idx
            }
            numberIdx++
        }
        if (idx + numberLen + number > mangled.value.size) {
            return idx
        }
        return idx + numberLen + number
    }

    func TreeIdMapPop(from: IntRef, to: Int64): Unit {
        while (from.value > to) {
            treeIdMap.remove(at: treeIdMap.size - 1)
            from.value--
        }
    }

    func TreeIdMapErase(mangled: StringRef, cnt: IntRef, entityId: Int64, sid: Int64): String {
        treeIdMap.remove(at: entityId)
        UpdateCompressedName(mangled, sid, mangled.value.size)
        cnt.value--
        return mangled.value
    }

    func TreeIdMapPushBack(mangled: StringRef, pos: (Int64, Int64)): Bool {
        if (pos[1] == 0) {
            treeIdMap.add(pos)
            return true
        } else if (pos[1] != 0 && !HasDuplicates(mangled, pos)) {
            treeIdMap.add(pos)
            return true
        }
        return false
    }

    func TreeIdMapAssign(mangled: StringRef, mangledCopy: String, mapId: Int64, cnt: IntRef,
        eleInfo: (Int64, Int64)): Unit {
        let idx = eleInfo[0]
        let nextIdx = eleInfo[1]
        if (mapId >= treeIdMap.size) {
            return
        }
        let old = treeIdMap[mapId]
        treeIdMap[mapId] = (old[0], nextIdx - idx)
        if (HasDuplicates(mangled, mapId)) {
            let copyRef = StringRef(mangledCopy)
            TreeIdMapErase(copyRef, cnt, mapId, idx)
            mangled.value = copyRef.value
        }
    }

    func ForwardType(mangled: StringRef, cnt: IntRef, idx!: Int64 = 0): Int64 {
        if (idx >= mangled.value.size) {
            return idx
        }
        let ch = mangled.value[idx]
        var nextIdx = idx
        let curCnt = cnt.value
        let mangledCopy = mangled.value
        let mapId = treeIdMap.size
        if (this.isRecord) {
            let pos = (idx, 0)
            let isPush = TreeIdMapPushBack(mangled, pos)
            cnt.value = if (isPush) { cnt.value + 1 } else { cnt.value }
        }
        match (ch) {
            case b'C' =>
                nextIdx = ForwardClassType(mangled, cnt, idx)
            case b'R' =>
                nextIdx = ForwardClassType(mangled, cnt, idx)
            case b'N' =>
                nextIdx = ForwardClassType(mangled, cnt, idx)
            case b'F' =>
                if (idx + MANGLE_CHAR_LEN < mangled.value.size &&
                    (mangled.value[idx + MANGLE_CHAR_LEN] == b'0' ||
                    mangled.value[idx + MANGLE_CHAR_LEN] == b'C')) {
                    nextIdx = ForwardFunctionType(mangled, cnt, idx)
                } else {
                    nextIdx = idx
                }
            case b'T' =>
                nextIdx = ForwardTupleType(mangled, cnt, idx)
            case b'P' =>
                nextIdx = ForwardCPointer(mangled, cnt, idx)
            case b'A' =>
                nextIdx = ForwardArrayType(mangled, cnt, idx)
            case b'V' =>
                nextIdx = ForwardArrayType(mangled, cnt, idx)
            case b'k' =>
                nextIdx = idx + MANGLE_CHAR_LEN
                if (this.isRecord) {
                    TreeIdMapPop(cnt, curCnt)
                }
                return nextIdx
            case b'G' =>
                nextIdx = ForwardGenericType(mangled, cnt, idx)
            case b'Y' =>
                nextIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
            var updateRes = (0, nextIdx, mangled.value)
                if (nextIdx != idx) {
                    updateRes = UpdateCompressedName(mangled, idx)
                }
                if (this.isRecord) {
                    TreeIdMapPop(cnt, curCnt)
                }
                return if (updateRes[0] == 0) { idx } else { updateRes[1] }
            case _ =>
                if (IsPrimitiveType(ch)) {
                    nextIdx = ForwardPrimitiveType(mangled.value, idx)
                    if (this.isRecord) {
                        TreeIdMapPop(cnt, curCnt)
                    }
                    return nextIdx
                } else {
                    nextIdx = idx
                }
        }
        if (this.isRecord && nextIdx != idx) {
            let eleInfo = (idx, nextIdx)
            TreeIdMapAssign(mangled, mangledCopy, mapId, cnt, eleInfo)
        } else if (this.isRecord && nextIdx == idx) {
            TreeIdMapPop(cnt, curCnt)
        }
        return nextIdx
    }

    func ForwardTypes(mangled: StringRef, cnt: IntRef, startId!: Int64 = 0): Int64 {
        var idx = startId
        while (idx < mangled.value.size && mangled.value[idx] != b'E') {
            let curIdx = ForwardType(mangled, cnt, idx: idx)
            if (curIdx == idx) {
                return curIdx
            }
            idx = curIdx
        }
        return idx
    }

    func IsCompressed(mangled: StringRef): Bool {
        if (mangled.value.isEmpty()) {
            return false
        }
        var pos: Int64 = 0
        var found = mangled.value.indexOf("Y", pos)
        while (let Some(foundPos) <- found) {
            pos = foundPos
            let nextIdx = ForwardNumber(mangled, pos + MANGLE_CHAR_LEN)
            if (nextIdx != pos + MANGLE_CHAR_LEN) {
                return true
            } else {
                pos += 1
            }
            found = mangled.value.indexOf("Y", pos)
        }
        return false
    }

    func SpanningVarDeclTree(): Unit {
        this.isRecord = true
        var idx = this.currentIndex
        let updateRes = UpdateCompressedName(StringRef(this.decompressed), idx)
        this.decompressed = updateRes[2]
        let change = updateRes[0]
        if (this.decompressed.size > 0 && IsDigit(this.decompressed[idx])) {
            let decompressedRef = StringRef(this.decompressed)
            idx = ForwardName(decompressedRef, idx: idx)
            this.decompressed = decompressedRef.value
            if (idx != this.currentIndex && change == 0) {
                let pos = (this.currentIndex, idx - this.currentIndex)
                TreeIdMapPushBack(StringRef(this.decompressed), pos)
            }
        }
        this.isRecord = false
    }

    func SpanningFuncDeclTree(): Unit {
        var idx = this.currentIndex
        if (this.decompressed.size == 0 || (this.decompressed.size > 0 && this.decompressed[idx] == b'L')) {
            return
        }
        this.isRecord = true
        var decompressedRef = StringRef(this.decompressed)
        var updateRes = UpdateCompressedName(decompressedRef, idx)
        this.decompressed = decompressedRef.value
        var change = updateRes[0]
        decompressedRef = StringRef(this.decompressed)
        if (IsDigit(this.decompressed[idx]) || IsOperatorName(this.decompressed, idx) || IsPropName(this.decompressed, idx)) {
            idx = ForwardName(decompressedRef, idx: idx)
            this.decompressed = decompressedRef.value
            if (idx != this.currentIndex && change == 0) {
                let funcPos = (this.currentIndex, this.decompressed.size - this.currentIndex)
                TreeIdMapPushBack(StringRef(this.decompressed), funcPos)
                let pos = (this.currentIndex, idx - this.currentIndex)
                TreeIdMapPushBack(StringRef(this.decompressed), pos)
            }
        }
        decompressedRef = StringRef(this.decompressed)
        updateRes = UpdateCompressedName(decompressedRef, idx)
        this.decompressed = decompressedRef.value
        change = updateRes[0]
        if (idx < this.decompressed.size && this.decompressed[idx] == b'K') {
            let nextIdx = ForwardNumber(StringRef(this.decompressed), idx + MANGLE_CHAR_LEN)
            if (nextIdx != idx + MANGLE_CHAR_LEN && change == 0) {
                let pos = (idx, nextIdx - idx)
                TreeIdMapPushBack(StringRef(this.decompressed), pos)
                idx = nextIdx
            }
        }
        if (idx < this.decompressed.size && this.decompressed[idx] == b'I') {
            let cnt = IntRef(0)
            let nextIdx = ForwardTypes(StringRef(this.decompressed), cnt, startId: idx + MANGLE_CHAR_LEN)
            if (nextIdx != idx + MANGLE_CHAR_LEN) {
                idx = nextIdx
            }
        }
        if (idx < this.decompressed.size && this.decompressed[idx] == b'H') {
            let cnt = IntRef(0)
            let nextIdx = ForwardTypes(StringRef(this.decompressed), cnt, startId: idx + MANGLE_CHAR_LEN)
            if (nextIdx != idx + MANGLE_CHAR_LEN) {
                idx = nextIdx
            }
        }
        this.isRecord = false
    }

    func CJMangledDeCompression(isType!: Bool = false): String {
        if (!IsCompressed(StringRef(this.mangledName)) || this.mangledName.isEmpty()) {
            return this.mangledName
        }
        this.pid = 0
        var demangled = this.mangledName[0..]
        this.pid = StripCangjieAt(demangled, this.pid)
        if (demangled.isEmpty() || isType || !IsSamePrefix(StringRef(demangled), MANGLE_CANGJIE_PREFIX, this.pid)) {
            return this.mangledName
        }
        this.pid = StripCangjiePrefix(demangled, this.pid)
        demangled = this.mangledName[this.pid..]
        if (IsGlobalEncode(StringRef(demangled))) {
            return this.mangledName
        }

        if (IsDefaultParamFuncEncode(StringRef(demangled))) {
            this.pid += PREFIX_LEN
            demangled = demangled[PREFIX_LEN..]
            this.currentIndex = TryParsePath(demangled)
            if (IsCompressed(StringRef(this.decompressed))) {
                SpanningFuncDeclTree()
            }
            return if (this.pid == 0) { this.decompressed } else { this.mangledName[0..this.pid] + this.decompressed }
        }
        if (!demangled.isEmpty() && demangled[0] == b'N') {
            this.pid += MANGLE_CHAR_LEN
            demangled = demangled[MANGLE_CHAR_LEN..]
            this.currentIndex = TryParsePath(demangled)
            let rest = if (this.currentIndex >= decompressed.size) { "" } else { this.decompressed[this.currentIndex..] }
            if (!IsCompressed(StringRef(rest))) {
                return if (this.pid == 0) { this.decompressed } else { this.mangledName[0..this.pid] + this.decompressed }
            }
            if (IsVarDeclEncode(StringRef(rest))) {
                SpanningVarDeclTree()
            } else {
                SpanningFuncDeclTree()
            }
            return if (this.pid == 0) { this.decompressed } else { this.mangledName[0..this.pid] + this.decompressed }
        }
        return demangled
    }

    func UpdateCompressedName(compressed: StringRef, idx: Int64): (Int64, Int64, String) {
        var change: Int64 = 0
        var curScanIdx = idx
        if (curScanIdx >= compressed.value.size) {
            return (change, curScanIdx, compressed.value)
        }
        var ch = compressed.value[curScanIdx]
        while (ch == MANGLE_COMPRESS_PREFIX && !this.treeIdMap.isEmpty()) {
            let curIdx = ForwardNumber(compressed, curScanIdx + MANGLE_CHAR_LEN)
            if (curIdx != curScanIdx + MANGLE_CHAR_LEN) {
                let numberStr = compressed.value[curScanIdx + MANGLE_CHAR_LEN..curIdx]
                let mapIdx = GetNumber(numberStr)
                if (mapIdx >= this.treeIdMap.size || this.treeIdMap[mapIdx][1] == 0) {
                    break
                }
                let curRest = if (curIdx < compressed.value.size) { compressed.value[curIdx..] } else { "" }
                let mapped = this.treeIdMap[mapIdx]
                compressed.value = compressed.value[0..curScanIdx] +
                    compressed.value[mapped[0]..mapped[0] + mapped[1]] + curRest
                change++
                curScanIdx += mapped[1]
                if (curScanIdx >= compressed.value.size) {
                    break
                }
                ch = compressed.value[curScanIdx]
            } else {
                break
            }
        }
        return (change, curScanIdx, compressed.value)
    }

    func UpdateCompressedName(compressed: StringRef, sid: Int64, eid: Int64): Int64 {
        var idx = sid
        var endId = eid
        while (idx < endId) {
            if (idx >= compressed.value.size) {
                break
            }
            if (compressed.value[idx] == MANGLE_COMPRESS_PREFIX && !this.treeIdMap.isEmpty() &&
                idx + MANGLE_CHAR_LEN < compressed.value.size) {
                let curIdx = ForwardNumber(compressed, idx + MANGLE_CHAR_LEN)
                if (curIdx == idx + MANGLE_CHAR_LEN) {
                    idx++
                    continue
                }
                let numberStr = compressed.value[idx + MANGLE_CHAR_LEN..curIdx]
                let mapIdx = GetNumber(numberStr)
                if (mapIdx >= this.treeIdMap.size) {
                    return 0
                }
                if (this.treeIdMap[mapIdx][1] == 0) {
                    idx++
                    continue
                }
                let curRest = if (curIdx < compressed.value.size) { compressed.value[curIdx..] } else { "" }
                let mapped = this.treeIdMap[mapIdx]
                compressed.value = compressed.value[0..idx] +
                    compressed.value[mapped[0]..mapped[0] + mapped[1]] + curRest
                endId = compressed.value.size
                idx += mapped[1]
            } else {
                idx++
            }
        }
        return 0
    }

    func TryExtendPath(mangled: StringRef, count: IntRef, idx: Int64, entityId: Int64, curMangled: String): Int64 {
        var isPush = false
        let mangledCopy = mangled.value
        var nextIdx = ForwardType(mangled, count, idx: idx + MANGLE_CHAR_LEN)
        var change = UpdateCompressedName(mangled, nextIdx)[0]
        let tyId = nextIdx
        if (nextIdx < mangled.value.size && mangled.value[nextIdx] == b'U') {
            let fid = nextIdx
            nextIdx = ForwardFileNameNumber(mangled.value, fid + MANGLE_CHAR_LEN)
            if (nextIdx != fid + MANGLE_CHAR_LEN && change == 0) {
                let pos = (fid, nextIdx - fid)
                isPush = TreeIdMapPushBack(mangled, pos)
                count.value = if (isPush) { count.value + 1 } else { count.value }
            }
            change = UpdateCompressedName(mangled, nextIdx)[0]
            if (nextIdx < mangled.value.size && mangled.value[nextIdx] == b'K') {
                let lid = nextIdx
                nextIdx = ForwardNumber(mangled, nextIdx + MANGLE_CHAR_LEN)
                let eleInfo = (idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
                if (nextIdx != lid + MANGLE_CHAR_LEN && change == 0) {
                    let pos = (lid, nextIdx - lid)
                    isPush = TreeIdMapPushBack(mangled, pos)
                    count.value = if (isPush) { count.value + 1 } else { count.value }
                }
            } else {
                nextIdx = idx
            }
        } else {
            nextIdx = tyId
        }
        return nextIdx
    }

    func TryLambdaPath(mangled: StringRef, count: IntRef, idx: Int64, entityId: Int64, change: Int64): Int64 {
        let mangledCopy = mangled.value
        var nextIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
        if (nextIdx == mangled.value.size - 1 && mangled.value[nextIdx] == b'E') {
            nextIdx = idx
        } else {
            nextIdx = if (nextIdx == idx + MANGLE_CHAR_LEN) { idx } else { nextIdx }
            if (nextIdx != idx || change > 0) {
                let eleInfo = (idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
            }
        }
        return nextIdx
    }

    func TryGenericPrefixPath(mangled: StringRef, count: IntRef, curMangled: String,
        rParams: (Int64, Int64, Int64)): Int64 {
        let mangledCopy = mangled.value
        let idx = rParams[0]
        let entityId = rParams[1]
        var nextIdx = rParams[2]
        nextIdx = ForwardTypes(mangled, count, startId: nextIdx + MANGLE_CHAR_LEN)
        if (nextIdx < mangled.value.size && mangled.value[nextIdx] == b'E') {
            nextIdx++
            let eleInfo = (idx, nextIdx)
            TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
        } else if (nextIdx < mangled.value.size && mangled.value[nextIdx] == b'H') {
            nextIdx = ForwardTypes(mangled, count, startId: nextIdx + MANGLE_CHAR_LEN)
            if (nextIdx < mangled.value.size && mangled.value[nextIdx] == b'E') {
                nextIdx++
                let eleInfo = (idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
            } else if (nextIdx == mangled.value.size) {
                let eleInfo = (idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
            } else {
                nextIdx = idx
            }
        } else {
            nextIdx = idx
        }
        return nextIdx
    }

    func TryNamePrefixPath(mangled: StringRef, count: IntRef, curMangled: String,
        rParams: (Int64, Int64, Int64)): Int64 {
        let mangledCopy = mangled.value
        let idx = rParams[0]
        let entityId = rParams[1]
        var change = rParams[2]
        var idFlag: Int64 = 0
        var nextIdx = ForwardName(mangled, idx: idx)
        let nameIdx = nextIdx
        if (nextIdx < mangled.value.size && mangled.value[nextIdx] == b'K') {
            idFlag = nextIdx
            nextIdx = ForwardNumber(mangled, nextIdx + MANGLE_CHAR_LEN)
        }
        if (nextIdx != idx && change == 0) {
            let pos = (idx, nextIdx - idx)
            let isPush = TreeIdMapPushBack(mangled, pos)
            count.value = if (isPush) { count.value + 1 } else { count.value }
        }
        if (nextIdx < mangled.value.size) {
            idFlag = nextIdx
            change = UpdateCompressedName(mangled, idFlag)[0]
            nextIdx = idFlag
            if (mangled.value[nextIdx] == b'U') {
                nextIdx = ForwardFileNameNumber(mangled.value, nameIdx + MANGLE_CHAR_LEN)
                let eleInfo = (idx, nextIdx)
                TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
                if (nextIdx != idFlag + MANGLE_CHAR_LEN && change == 0) {
                    let pos = (idFlag, nextIdx - idFlag)
                    let isPush = TreeIdMapPushBack(mangled, pos)
                    count.value = if (isPush) { count.value + 1 } else { count.value }
                }
                nextIdx = if (nextIdx == nameIdx + 1) { nameIdx } else { nextIdx }
            } else if (mangled.value[nextIdx] == b'I') {
                let genericParams = (idx, entityId, nextIdx)
                nextIdx = TryGenericPrefixPath(mangled, count, curMangled, genericParams)
            } else if (mangled.value[nextIdx] == b'H') {
                nextIdx = ForwardTypes(mangled, count, startId: nameIdx + MANGLE_CHAR_LEN)
                if (nextIdx < mangled.value.size && mangled.value[nextIdx] == b'E') {
                    nextIdx++
                    let eleInfo = (idx, nextIdx)
                    TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
                } else if (nextIdx == mangled.value.size) {
                    let eleInfo = (idx, nextIdx)
                    TreeIdMapAssign(mangled, mangledCopy, entityId, count, eleInfo)
                } else {
                    nextIdx = idx
                }
            } else {
                nextIdx = nameIdx
            }
        }
        if (nextIdx == nameIdx) {
            let old = this.treeIdMap[entityId]
            this.treeIdMap[entityId] = (old[0], nameIdx - idx)
            TreeIdMapPop(count, 1)
        }
        return nextIdx
    }

    func TryParsePath(mangledValue: String): Int64 {
        this.isRecord = true
        let mangled = StringRef(mangledValue)
        var idx: Int64 = 0
        while (idx < mangled.value.size) {
            let ch = mangled.value[idx]
            var nextIdx = idx
            let updateRes = UpdateCompressedName(mangled, nextIdx)
            let change = updateRes[0]
            let curMangled = mangled.value
            let pos = (idx, 0)
            let isPush = TreeIdMapPushBack(mangled, pos)
            let count = IntRef(if (isPush) { 1 } else { 0 })
            let entityId = this.treeIdMap.size - 1
            if (ch == MANGLE_ANONYMOUS_PREFIX) {
                nextIdx = ForwardNumber(mangled, idx + MANGLE_CHAR_LEN)
                if (nextIdx != idx + MANGLE_CHAR_LEN) {
                    let eleInfo = (idx, nextIdx)
                    TreeIdMapAssign(mangled, curMangled, entityId, count, eleInfo)
                }
                if (nextIdx == idx + MANGLE_CHAR_LEN || change > 0) {
                    nextIdx = idx
                }
            } else if (IsDigit(ch) || IsOperatorName(mangled.value, idx) || IsPropName(mangled.value, idx)) {
                let rParams = (idx, entityId, change)
                nextIdx = TryNamePrefixPath(mangled, count, curMangled, rParams)
            } else if (ch == b'X') {
                nextIdx = TryExtendPath(mangled, count, idx, entityId, curMangled)
            } else if (ch == b'L') {
                nextIdx = TryLambdaPath(mangled, count, idx, entityId, change)
            } else if (IsStdPkgName(mangled.value, idx)) {
                nextIdx = ForwardPackageName(mangled, count, idx)
                if (nextIdx != idx || change == 0) {
                    let eleInfo = (idx, nextIdx)
                    TreeIdMapAssign(mangled, curMangled, entityId, count, eleInfo)
                }
            }
            if (nextIdx != idx) {
                idx = nextIdx
            } else {
                TreeIdMapPop(count, 0)
                break
            }
        }
        this.decompressed = mangled.value
        this.isRecord = false
        return idx
    }
}
