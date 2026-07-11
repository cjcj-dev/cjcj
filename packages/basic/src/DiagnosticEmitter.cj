package cjcj::basic

import std.collection.*
import std.sort.*

private let BITOR: String = "|"
private let BITXOR: String = "^"
private let TILDE: String = "~"
private let SPACE: String = " "
private let COLON: String = ":"
private let MAIN_HINT_SYMBOL: String = BITXOR
private let OTHER_HINT_SYMBOL: String = TILDE
private let MULTI_LINE_KEY_SYMBOL: String = BITOR
private let MULTI_LINE_SYMBOL: String = "_"
private let WITHOUT_SOURCE_SYMBOL: String = "#"
private let COMPRESS_LEN: Int64 = 2
private let LENGTH_OF_DELAY: Int64 = 7

private type ColorTuple = (Int64, Int64, DiagColor)
private type SourceCombinedVec = ArrayList<CombinedLine>
private type CollectedInfoMap = TreeMap<Int64, ArrayList<CollectedInfo>>
private type SubstitutionMap = TreeMap<Int64, ArrayList<Substitution>>
private type HangingStr = ArrayList<ArrayList<String>>

private func GetNewLine(): String {
    return "\n"
}

private func GetLineSymbol(): String {
    return "==>"
}

private func CharacterOfNum(n: Int64, c: String): String {
    return repeatString(c, n)
}

private func g_spaceOfNum(n: Int64): String {
    return CharacterOfNum(n, SPACE)
}

private func GetColoredString(color: DiagColor, str: String, isBright!: Bool = false): String {
    if (color == DiagColor.NO_COLOR) {
        return str
    }
    return colorToAnsi(color) + if (isBright) { ANSI_COLOR_BRIGHT } else { "" } + str + colorToAnsi(DiagColor.RESET)
}

private func severityName(severity: DiagSeverity): String {
    return match (severity) {
        case DiagSeverity.DS_ERROR => "error"
        case DiagSeverity.DS_WARNING => "warning"
        case DiagSeverity.DS_NOTE => "note"
        case DiagSeverity.DS_HINT => "hint"
    }
}

private func IsTextOnlyWarning(warnGroup: WarnGroup): Bool {
    return warnGroup == WarnGroup.DRIVER_ARG || warnGroup == WarnGroup.UNSUPPORT_COMPILE_SOURCE
}

private func sourceDisplayName(source: Source): String {
    if (let Some(name) <- source.packageName) {
        return "(package " + name + ")" + BasicGetFileName(source.path)
    }
    return source.path
}

private struct CombinedLine {
    public var meta: String
    public var line: Int64
    public var hasSourceFile: Bool
    public let colors: ArrayList<ColorTuple> = ArrayList<ColorTuple>()

    public init(meta: String, line: Int64, hasSourceFile: Bool) {
        this.meta = meta
        this.line = line
        this.hasSourceFile = hasSourceFile
    }

    public init(meta: String, line: Int64, hasSourceFile: Bool, colors: ArrayList<ColorTuple>) {
        this.meta = meta
        this.line = line
        this.hasSourceFile = hasSourceFile
        for (color in colors) {
            this.colors.add(color)
        }
    }
}

private struct CollectedInfo <: Hashable & Equatable<CollectedInfo> {
    public var range: Range = MakeRange(DEFAULT_POSITION, DEFAULT_POSITION)
    public var isMain: Bool = false
    public var isMultiLine: Bool = false
    public var isEnd: Bool = false
    public var hint: String = ""
    public var color: DiagColor = DiagColor.RESET

    public init() {}

    public init(range: Range, isMain: Bool, isMultiLine: Bool, isEnd: Bool, hint: String, color: DiagColor) {
        this.range = range
        this.isMain = isMain
        this.isMultiLine = isMultiLine
        this.isEnd = isEnd
        this.hint = hint
        this.color = color
    }

    public func IsDefault(): Bool {
        return range.begin == DEFAULT_POSITION
    }

    public operator func ==(right: CollectedInfo): Bool {
        return range == right.range && isMain == right.isMain && isMultiLine == right.isMultiLine &&
            isEnd == right.isEnd
    }

    public operator func !=(right: CollectedInfo): Bool {
        return !(this == right)
    }

    @OverflowWrapping
    public func hashCode(): Int64 {
        let mainBit = if (isMain) { 1u64 } else { 0u64 }
        let multiBit = if (isMultiLine) { 1u64 } else { 0u64 }
        return Int64((range.Hash() << 2u64) ^ (mainBit << 1u64) ^ multiBit)
    }
}

private func StoreInfoToMap(errorInfos: ArrayList<CollectedInfo>): CollectedInfoMap {
    let lineToInfoMap = CollectedInfoMap()
    for (info in errorInfos) {
        let line = info.range.begin.line
        if (let Some(infos) <- lineToInfoMap.get(line)) {
            infos.add(info)
        } else {
            let infos = ArrayList<CollectedInfo>()
            infos.add(info)
            lineToInfoMap.add(line, infos)
        }
    }
    return lineToInfoMap
}

private func GetMaxLineColumn(errorInfos: ArrayList<CollectedInfo>): Int64 {
    var maxLineColumn: Int64 = 0
    for (info in errorInfos) {
        if (info.range.end.line > maxLineColumn) {
            maxLineColumn = info.range.end.line
        }
    }
    return "${maxLineColumn}".size
}

private func HandleSpecialCharacters(str: String): String {
    return str.replace("\t", g_spaceOfNum(HORIZONTAL_TAB_LEN))
}

public class DiagnosticEmitter {
    private let diagnostic: Diagnostic
    private let noColor: Bool
    private let checkRange: Bool
    private let sourceManager: SourceManager
    private var macroNoteSwapped: Bool = false
    private var rangeCheckError: Bool = false
    private var maxLineNum: Int64 = 0
    private let multiLineRecordMap: HashMap<CollectedInfo, Int64> = HashMap<CollectedInfo, Int64>()
    private let multiLineHangingPtrVec: ArrayList<(Int64, Int64)> = ArrayList<(Int64, Int64)>()
    private let multiLineHangingVec: ArrayList<ArrayList<ColorTuple>> = ArrayList<ArrayList<ColorTuple>>()

    public init(diagnostic: Diagnostic, noColor: Bool, checkRange: Bool, sourceManager: SourceManager) {
        this.diagnostic = diagnostic
        this.noColor = noColor
        this.checkRange = checkRange
        this.sourceManager = sourceManager
    }

    public func Emit(): Bool {
        WriteError(Render())
        return !HasRangeError()
    }

    public func HasRangeError(): Bool {
        if (rangeCheckError) {
            return true
        }
        if (!checkRange) {
            return false
        }
        if (diagnostic.mainHint.range.HasZero()) {
            return true
        }
        for (hint in diagnostic.otherHints) {
            if (hint.range.HasZero()) {
                return true
            }
        }
        for (subDiag in diagnostic.subDiags) {
            if (!subDiag.mainHint.IsDefault() && subDiag.mainHint.range.HasZero()) {
                return true
            }
            for (hint in subDiag.otherHints) {
                if (hint.range.HasZero()) {
                    return true
                }
            }
        }
        for (help in diagnostic.helps) {
            for (substitution in help.substitutions) {
                if (substitution.range.HasZero()) {
                    return true
                }
            }
        }
        return false
    }

    public func Render(showSourceOnly!: Bool = false): String {
        swapErrorMessageWithNote()
        let builder = StringBuilder()
        if (!showSourceOnly) {
            EmitErrorMessage(builder, diagnostic.mainHint.color, severityName(diagnostic.diagSeverity),
                diagnostic.errorMessage)
        }
        if (IsTextOnlyWarning(diagnostic.warnGroup)) {
            EmitNote(builder)
        }
        if (diagnostic.mainHint.range.begin == DEFAULT_POSITION) {
            return builder.toString()
        }
        let errorInfo = ArrayList<CollectedInfo>()
        CollectInformation(errorInfo, diagnostic.mainHint, true)
        for (str in diagnostic.otherHints) {
            CollectInformation(errorInfo, str, false)
        }
        SortAndCheck(errorInfo)
        maxLineNum = GetMaxLineColumn(errorInfo)
        EmitErrorLocation(builder, diagnostic.mainHint.range.begin)
        ConstructAndEmitSourceCode(builder, errorInfo)
        EmitNote(builder)
        EmitHelp(builder, diagnostic.helps)
        builder.append("\n")
        return builder.toString()
    }

    private func CollectInformation(vec: ArrayList<CollectedInfo>, str: IntegratedString, isMain: Bool): Unit {
        var info = CollectedInfo()
        info.hint = str.str
        info.color = str.color
        info.isMain = isMain
        if (str.range.begin.line == str.range.end.line) {
            info.range = str.range
        } else {
            let startRange = MakeRange(str.range.begin, str.range.begin + 1)
            let startInfo = CollectedInfo(startRange, info.isMain, true, false, "", str.color)
            vec.add(startInfo)
            multiLineRecordMap.add(startInfo, multiLineHangingPtrVec.size)
            let start = if (str.range.end.column > 1) {
                str.range.end - 1
            } else {
                Position(str.range.end.fileID, str.range.end.line, 1)
            }
            let end = if (str.range.end.column > 1) {
                str.range.end
            } else {
                Position(str.range.end.fileID, str.range.end.line, 2)
            }
            info.range = MakeRange(start, end)
            info.isMultiLine = true
            info.isEnd = true
            info.hint = str.str
            multiLineRecordMap.add(info, multiLineHangingPtrVec.size)
            multiLineHangingPtrVec.add((-1, -1))
        }
        vec.add(info)
    }

    private func SortAndCheck(errorInfo: ArrayList<CollectedInfo>): Unit {
        sort(errorInfo, by: { left: CollectedInfo, right: CollectedInfo =>
            if (left.range.begin < right.range.begin) {
                Ordering.LT
            } else if (right.range.begin < left.range.begin) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
    }

    private func GetSourceCode(errorInfo: ArrayList<CollectedInfo>): String {
        if (errorInfo.isEmpty()) {
            return ""
        }
        let start = errorInfo[0].range.begin
        let end = errorInfo[errorInfo.size - 1].range.end
        if (start.fileID == end.fileID) {
            return sourceManager.GetContentBetween(start.fileID, Position(start.line, 1), Position(end.line, Int64.Max))
        }
        let fileID = start.fileID
        let source = StringBuilder()
        for (info in errorInfo) {
            let range = info.range
            if (range.begin.fileID < fileID) {
                if (!source.toString().isEmpty()) {
                    source.append("\n")
                }
                continue
            }
            source.append(sourceManager.GetContentBetween(range.begin.fileID, Position(range.begin.line, 1),
                Position(range.end.line, Int64.Max)))
        }
        return source.toString()
    }

    private func GetDisplayedWidthFromSource(source: String, range: Range): Int64 {
        let defaultWidth: Int64 = 1
        if (source.isEmpty()) {
            return defaultWidth
        }
        var start = range.begin.column
        var end = range.end.column
        let len = source.size
        if (start > len) {
            start = len
        }
        if (end > len + 1) {
            end = len + 1
        }
        if (start < 1) {
            start = 1
        }
        if (end < start) {
            end = start
        }
        let substr = source[start - 1..end - 1]
        let disWidth = DisplayWidth(substr)
        return if (disWidth > 0) { disWidth } else { defaultWidth }
    }

    private func InsertSymbolInFirstLine(combinedLine: CombinedLine, loc: Int64, info: CollectedInfo,
        sourceLine: String): CombinedLine {
        let sym = if (info.isMain) { MAIN_HINT_SYMBOL } else { OTHER_HINT_SYMBOL }
        let len = GetDisplayedWidthFromSource(sourceLine, info.range)
        let repStr = CharacterOfNum(len, sym)
        let end = if (loc + len > combinedLine.meta.size) { combinedLine.meta.size } else { loc + len }
        var line = combinedLine
        line.meta = line.meta[0..loc] + repStr + line.meta[end..]
        line.colors.add((loc, loc + len, info.color))
        return line
    }

    private func InsertSymbolNotFirstLine(combinedLine: CombinedLine, loc: Int64, info: CollectedInfo): CombinedLine {
        let len: Int64 = 1
        let repStr = CharacterOfNum(len, BITOR)
        let end = if (loc + len > combinedLine.meta.size) { combinedLine.meta.size } else { loc + len }
        var line = combinedLine
        line.meta = line.meta[0..loc] + repStr + line.meta[end..]
        line.colors.add((loc, loc + len, info.color))
        return line
    }

    private func InsertSymbolToUpperLine(insertedStr: SourceCombinedVec, loc: Int64, info: CollectedInfo,
        sourceLine: String): Unit {
        var idx: Int64 = 0
        while (idx < insertedStr.size) {
            if (idx == 0) {
                insertedStr[idx] = InsertSymbolInFirstLine(insertedStr[idx], loc, info, sourceLine)
            } else {
                insertedStr[idx] = InsertSymbolNotFirstLine(insertedStr[idx], loc, info)
            }
            idx++
        }
    }

    private func CompressLineCode(infoMap: CollectedInfoMap, bindLineCodes: SourceCombinedVec): Unit {
        if (infoMap.isEmpty()) {
            return
        }
        var base: Int64 = 0
        for (key in infoMap.keys()) {
            base = key
            break
        }
        var second: Int64 = 0
        var lastKey = base
        for (key in infoMap.keys()) {
            lastKey = key
        }
        let lineNum = lastKey - base + 1
        if (lineNum > bindLineCodes.size) {
            return
        }
        let keys = ArrayList<Int64>()
        for (key in infoMap.keys()) {
            keys.add(key)
        }
        var idx = keys.size - 1
        while (idx >= 0) {
            let key = keys[idx]
            if (second == 0) {
                second = key
                idx--
                continue
            }
            if (second - key > COMPRESS_LEN) {
                let targetIndex = key - base + COMPRESS_LEN
                var targetLine = bindLineCodes[targetIndex]
                targetLine.line = 0
                targetLine.meta = "..."
                bindLineCodes[targetIndex] = targetLine
                let removeEnd = second - base
                let removeCount = removeEnd - (targetIndex + 1)
                var removed: Int64 = 0
                while (removed < removeCount) {
                    bindLineCodes.remove(at: targetIndex + 1)
                    removed++
                }
            }
            second = key
            idx--
        }
    }

    private func CombineErrorPrintSingleLineHelper(sourceLine: String, info: CollectedInfo,
        isFirstLine!: Bool = false): CombinedLine {
        let str = sourceLine + GetNewLine()
        let space = GetSpaceBeforeTarget(str, info.range.begin.column)
        var line = space
        let charSize = GetDisplayedWidthFromSource(str, info.range)
        let symbol = if (info.isMain) { MAIN_HINT_SYMBOL } else { OTHER_HINT_SYMBOL }
        let begin = line.size
        if (isFirstLine) {
            line += CharacterOfNum(charSize, symbol) + g_spaceOfNum(1)
        }
        line += info.hint
        let colors = ArrayList<ColorTuple>()
        colors.add((begin, line.size, info.color))
        return CombinedLine(line, 0, false, colors)
    }

    private func CombineErrorPrintSingleLine(insertedStr: SourceCombinedVec, info: CollectedInfo,
        sourceLine: String): Unit {
        let isFirstLine = insertedStr.isEmpty()
        if (isFirstLine) {
            insertedStr.add(CombineErrorPrintSingleLineHelper(sourceLine, info, isFirstLine: isFirstLine))
        } else if (info.hint.isEmpty()) {
            let str = sourceLine + GetNewLine()
            let spaceSize = GetSpaceBeforeTarget(str, info.range.begin.column).size
            if (insertedStr.isEmpty()) {
                return
            }
            insertedStr[0] = InsertSymbolInFirstLine(insertedStr[0], spaceSize, info, str)
        } else {
            let tl = CombineErrorPrintSingleLineHelper(sourceLine, info, isFirstLine: isFirstLine)
            var spaceSize: Int64 = 0
            while (spaceSize < tl.meta.size && tl.meta[spaceSize] == b' ') {
                spaceSize++
            }
            let blackLine = g_spaceOfNum(spaceSize + 1)
            let str = sourceLine + GetNewLine()
            insertedStr.add(CombinedLine(blackLine, 0, false))
            InsertSymbolToUpperLine(insertedStr, spaceSize, info, str)
            insertedStr.add(tl)
        }
    }

    private func AnalyseMultiLineHanging(info: CollectedInfo, combinedVecSize: Int64): Unit {
        if (let None <- multiLineRecordMap.get(info)) {
            return
        }
        let loc = multiLineRecordMap.get(info).getOrThrow()
        if (loc >= multiLineHangingPtrVec.size) {
            return
        }
        if (!info.isEnd) {
            let tup: ColorTuple = (combinedVecSize, 0, info.color)
            if (multiLineHangingVec.isEmpty()) {
                let vec = ArrayList<ColorTuple>()
                vec.add(tup)
                multiLineHangingVec.add(vec)
                multiLineHangingPtrVec[loc] = (0, 0)
            } else {
                var found: Int64 = -1
                var reverseIndex = multiLineHangingVec.size - 1
                while (reverseIndex >= 0) {
                    let vec = multiLineHangingVec[reverseIndex]
                    if (!vec.isEmpty() && vec[vec.size - 1][1] == 0) {
                        found = reverseIndex
                        break
                    }
                    reverseIndex--
                }
                if (found == multiLineHangingVec.size - 1) {
                    let vec = ArrayList<ColorTuple>()
                    vec.add(tup)
                    multiLineHangingVec.add(vec)
                    multiLineHangingPtrVec[loc] = (0, multiLineHangingVec.size - 1)
                } else {
                    let index = if (found < 0) { 0 } else { found + 1 }
                    multiLineHangingVec[index].add(tup)
                    multiLineHangingPtrVec[loc] = (multiLineHangingVec[index].size - 1, index)
                }
            }
        } else {
            let ptr = multiLineHangingPtrVec[loc]
            let line = ptr[0]
            let column = ptr[1]
            if (column >= multiLineHangingVec.size || line >= multiLineHangingVec[column].size) {
                return
            }
            let old = multiLineHangingVec[column][line]
            multiLineHangingVec[column][line] = (old[0], combinedVecSize + 1, old[2])
        }
    }

    private func CombineErrorPrintMultiLineHelper(sourceLine: String, info: CollectedInfo, isFirstLine: Bool,
        combinedVecSize: Int64): CombinedLine {
        if (info.IsDefault()) {
            rangeCheckError = true
            return CombinedLine(info.hint, 0, false)
        }
        AnalyseMultiLineHanging(info, combinedVecSize)
        let str = sourceLine + GetNewLine()
        let space = GetSpaceBeforeTarget(str, info.range.begin.column)
        var line = CharacterOfNum(space.size, MULTI_LINE_SYMBOL)
        let symbol = if (info.isMain) { MAIN_HINT_SYMBOL } else { OTHER_HINT_SYMBOL }
        if (isFirstLine) {
            line += symbol
            if (info.isEnd && !info.hint.isEmpty()) {
                line += g_spaceOfNum(1) + info.hint
            }
        } else {
            line += MULTI_LINE_KEY_SYMBOL
        }
        let colors = ArrayList<ColorTuple>()
        colors.add((0, line.size, info.color))
        return CombinedLine(line, 0, false, colors)
    }

    private func CombineErrorPrintMultiLine(insertedStr: SourceCombinedVec, info: CollectedInfo, sourceLine: String,
        combinedVecSize: Int64): Unit {
        let isFirstLine = insertedStr.isEmpty()
        if (isFirstLine) {
            insertedStr.add(CombineErrorPrintMultiLineHelper(sourceLine, info, isFirstLine, combinedVecSize))
        } else {
            let tl = CombineErrorPrintMultiLineHelper(sourceLine, info, isFirstLine, combinedVecSize + insertedStr.size)
            let len = tl.meta.size
            let str = sourceLine + GetNewLine()
            InsertSymbolToUpperLine(insertedStr, len - 1, info, str)
            insertedStr.add(tl)
            if (!info.hint.isEmpty()) {
                insertedStr.add(CombinedLine(g_spaceOfNum(len - 1), 0, false))
            }
        }
    }

    private func CombineErrorPrint(infoMap: CollectedInfoMap, combinedVec: SourceCombinedVec): Bool {
        if (!combinedVec.isEmpty() && combinedVec[0].hasSourceFile) {
            CompressLineCode(infoMap, combinedVec)
        }
        for ((lineNumber, infos) in infoMap) {
            var lineIndex: Int64 = 0
            while (lineIndex < combinedVec.size) {
                if (combinedVec[lineIndex].line == lineNumber) {
                    break
                }
                lineIndex++
            }
            if (lineIndex >= combinedVec.size) {
                return false
            }
            let sourceLine = combinedVec[lineIndex].meta
            let insertedStr = SourceCombinedVec()
            var infoIndex = infos.size - 1
            while (infoIndex >= 0) {
                let info = infos[infoIndex]
                if (info.isMultiLine) {
                    CombineErrorPrintMultiLine(insertedStr, info, sourceLine, lineIndex + 1)
                } else {
                    CombineErrorPrintSingleLine(insertedStr, info, sourceLine)
                }
                infoIndex--
            }
            var insertIndex = lineIndex + 1
            for (inserted in insertedStr) {
                combinedVec.add(inserted, at: insertIndex)
                insertIndex++
            }
        }
        return true
    }

    private func HandleUnprintableChar(combinedVec: SourceCombinedVec): Unit {
        var combinedIndex: Int64 = 0
        while (combinedIndex < combinedVec.size) {
            var combinedLine = combinedVec[combinedIndex]
            let sourceCode = combinedLine.meta
            let bytes = sourceCode.toArray()
            let result = StringBuilder()
            var forwardIndex: Int64 = 0
            while (forwardIndex < bytes.size) {
                let forwardChar = bytes[forwardIndex]
                if (forwardChar <= 0x08u8 || (forwardChar >= 0x0bu8 && forwardChar <= 0x1fu8) ||
                    forwardChar == 0x7fu8) {
                    result.append("\\u{" + ToHexString(forwardChar, len: NORMAL_CODEPOINT_LEN) + "}")
                } else {
                    result.append(sourceCode[forwardIndex..forwardIndex + 1])
                }
                forwardIndex++
            }
            var backwardOffset: Int64 = 0
            while (backwardOffset < bytes.size) {
                let index = bytes.size - (backwardOffset + 1)
                let backwardChar = bytes[index]
                if (backwardChar <= 0x08u8 || (backwardChar >= 0x0bu8 && backwardChar <= 0x1fu8) ||
                    backwardChar == 0x7fu8) {
                    var colorIndex: Int64 = 0
                    while (colorIndex < combinedLine.colors.size) {
                        let color = combinedLine.colors[colorIndex]
                        let begin = if (color[0] > index) { color[0] + LENGTH_OF_DELAY } else { color[0] }
                        let end = if (color[1] > index) { color[1] + LENGTH_OF_DELAY } else { color[1] }
                        combinedLine.colors[colorIndex] = (begin, end, color[2])
                        colorIndex++
                    }
                    combinedLine.colors.add((index, index + LENGTH_OF_DELAY + 1, DiagColor.REVERSE))
                }
                backwardOffset++
            }
            combinedLine.meta = result.toString()
            combinedVec[combinedIndex] = combinedLine
            combinedIndex++
        }
    }

    private func EmitErrorMessage(builder: StringBuilder, color: DiagColor, err: String, mes: String): Unit {
        let finalColor = if (noColor) { DiagColor.NO_COLOR } else { color }
        builder.append(GetColoredString(finalColor, err) + COLON + g_spaceOfNum(1) + mes + "\n")
    }

    private func EmitErrorLocation(builder: StringBuilder, pos: Position): Unit {
        if (!sourceManager.IsSourceFileExist(pos.fileID)) {
            return
        }
        var prefix = CharacterOfNum(maxLineNum, SPACE)
        let color = if (noColor) { DiagColor.NO_COLOR } else { OTHER_HINT_COLOR }
        prefix += GetColoredString(color, GetLineSymbol())
        prefix += g_spaceOfNum(1)
        let source = sourceManager.GetSource(pos.fileID)
        let path = sourceDisplayName(source)
        builder.append(prefix + path + COLON + "${pos.line}" + COLON + "${pos.column}" + COLON + "\n")
    }

    private func ConvertHangingContentsHelper(hanging: HangingStr, i: Int64, begin: Int64, end: Int64,
        color: DiagColor): Unit {
        var k = i + 1
        while (k < hanging.size) {
            if (begin >= hanging[k].size) {
                break
            }
            if (hanging[k][begin] == g_spaceOfNum(1)) {
                hanging[k][begin] = GetColoredString(color, MULTI_LINE_SYMBOL)
            }
            if (end - 1 >= hanging[k].size) {
                break
            }
            if (hanging[k][end - 1] == g_spaceOfNum(1)) {
                hanging[k][end - 1] = GetColoredString(color, MULTI_LINE_SYMBOL)
            }
            k++
        }
        k = begin + 1
        while (k < end) {
            if (k >= hanging[i].size) {
                break
            }
            if (hanging[i][k] == g_spaceOfNum(1)) {
                hanging[i][k] = GetColoredString(color, MULTI_LINE_KEY_SYMBOL)
            }
            k++
        }
    }

    private func ConvertHangingContents(line: Int64): HangingStr {
        if (multiLineHangingVec.isEmpty()) {
            return HangingStr()
        }
        let hanging = HangingStr()
        var rowIndex: Int64 = 0
        while (rowIndex < multiLineHangingVec.size + 1) {
            let row = ArrayList<String>()
            var lineIndex: Int64 = 0
            while (lineIndex < line) {
                row.add(g_spaceOfNum(1))
                lineIndex++
            }
            hanging.add(row)
            rowIndex++
        }
        var i: Int64 = 0
        while (i < multiLineHangingVec.size) {
            var j: Int64 = 0
            while (j < multiLineHangingVec[i].size) {
                let item = multiLineHangingVec[i][j]
                let color = if (noColor) { DiagColor.NO_COLOR } else { item[2] }
                ConvertHangingContentsHelper(hanging, i, item[0], item[1], color)
                j++
            }
            i++
        }
        multiLineHangingVec.clear()
        multiLineHangingPtrVec.clear()
        multiLineRecordMap.clear()
        return hanging
    }

    private func EmitSourceCode(builder: StringBuilder, combinedVec: SourceCombinedVec): Unit {
        let hanging = ConvertHangingContents(combinedVec.size)
        var line = g_spaceOfNum(maxLineNum + 1)
        var color = if (noColor) { DiagColor.NO_COLOR } else { OTHER_HINT_COLOR }
        line += GetColoredString(color, BITOR + g_spaceOfNum(1), isBright: false)
        builder.append(line + "\n")
        var idx: Int64 = 0
        while (idx < combinedVec.size) {
            let sourceLine = HandleSpecialCharacters(combinedVec[idx].meta)
            let lineHere = combinedVec[idx].line
            let hasSourceFile = combinedVec[idx].hasSourceFile
            var str = ""
            if (lineHere != 0 && hasSourceFile) {
                color = if (noColor) { DiagColor.NO_COLOR } else { OTHER_HINT_COLOR }
                str += GetColoredString(color, "${lineHere}")
                str += CharacterOfNum(maxLineNum - "${lineHere}".size + 1, SPACE)
            } else {
                str += CharacterOfNum(maxLineNum + 1, SPACE)
            }
            color = if (noColor) { DiagColor.NO_COLOR } else { OTHER_HINT_COLOR }
            str += GetColoredString(color, BITOR + g_spaceOfNum(1), isBright: false)
            if (!hanging.isEmpty()) {
                for (vec in hanging) {
                    str += vec[idx]
                }
            }
            str += sourceLine
            builder.append(str + "\n")
            idx++
        }
        builder.append(line + "\n")
    }

    private func EmitSingleNoteWithSource(builder: StringBuilder, note: SubDiagnostic): Unit {
        EmitErrorMessage(builder, note.mainHint.color, "note", note.subDiagMessage)
        let errorInfo = ArrayList<CollectedInfo>()
        CollectInformation(errorInfo, note.mainHint, true)
        for (str in note.otherHints) {
            CollectInformation(errorInfo, str, false)
        }
        SortAndCheck(errorInfo)
        maxLineNum = GetMaxLineColumn(errorInfo)
        if (note.mainHint.range.begin != DEFAULT_POSITION) {
            EmitErrorLocation(builder, note.mainHint.range.begin)
        }
        ConstructAndEmitSourceCode(builder, errorInfo)
        let hs = ArrayList<DiagHelp>()
        hs.add(note.help)
        if (!GetSourceCode(errorInfo).isEmpty() && !note.help.IsDefault()) {
            EmitHelp(builder, hs)
        }
    }

    private func HelpSubstitutionToMap(help: DiagHelp): SubstitutionMap {
        sort(help.substitutions, by: { left: Substitution, right: Substitution =>
            if (left.range.begin < right.range.begin) {
                Ordering.LT
            } else if (right.range.begin < left.range.begin) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        let subMap = SubstitutionMap()
        for (info in help.substitutions) {
            let line = info.range.begin.line
            if (let Some(items) <- subMap.get(line)) {
                items.add(info)
            } else {
                let items = ArrayList<Substitution>()
                items.add(info)
                subMap.add(line, items)
            }
        }
        return subMap
    }

    private func HelpSubstituteConvertHelper(subMap: SubstitutionMap, rawStr: String, line: Int64,
        infos: ArrayList<CollectedInfo>): String {
        var result = rawStr
        if (let None <- subMap.get(line)) {
            return result
        }
        for (sub in subMap.get(line).getOrThrow()) {
            var info = CollectedInfo()
            let range = sub.range
            let size = range.end.column - range.begin.column
            let replaceBegin = range.begin.column - 1
            let replaceEnd = replaceBegin + size
            result = result[0..replaceBegin] + sub.str + result[replaceEnd..]
            info.range = MakeRange(range.begin, range.begin + sub.str.size)
            info.color = HELP_COLOR
            infos.add(info)
        }
        return result
    }

    private func HelpSubstituteConvert(help: DiagHelp, combinedVec: SourceCombinedVec): ArrayList<CollectedInfo> {
        let subMap = HelpSubstitutionToMap(help)
        let infos = ArrayList<CollectedInfo>()
        var idx: Int64 = 0
        while (idx < combinedVec.size) {
            let line = combinedVec[idx].line
            if (subMap.contains(line)) {
                var combinedLine = combinedVec[idx]
                combinedLine.meta = HelpSubstituteConvertHelper(subMap, combinedLine.meta, line, infos)
                combinedVec[idx] = combinedLine
            }
            idx++
        }
        return infos
    }

    private func GetHelpSubstituteSource(help: DiagHelp): SourceCombinedVec {
        if (help.substitutions.isEmpty()) {
            return SourceCombinedVec()
        }
        let start = help.substitutions[0].range.begin
        var source = sourceManager.GetContentBetween(start.fileID, Position(start.line, 1),
            Position(start.line, Int64.Max))
        if (source.isEmpty()) {
            return SourceCombinedVec()
        }
        if (source.size >= 2 && source[source.size - 2] == b'\r' && source[source.size - 1] == b'\n') {
            source = source[0..source.size - 2]
        } else if (source[source.size - 1] == b'\n' || source[source.size - 1] == b'\r') {
            source = source[0..source.size - 1]
        }
        let hasSourceFile = sourceManager.IsSourceFileExist(start.fileID)
        let combined = SourceCombinedVec()
        combined.add(CombinedLine(source, start.line, hasSourceFile))
        return combined
    }

    private func EmitSingleHelpWithSource(builder: StringBuilder, help: DiagHelp): Unit {
        let color = if (noColor) { DiagColor.NO_COLOR } else { HELP_COLOR }
        var message = GetColoredString(color, "help")
        message += CharacterOfNum(1, COLON)
        message += g_spaceOfNum(1)
        message += help.helpMes
        builder.append(message + COLON + "\n")
        let source = GetHelpSubstituteSource(help)
        if (source.isEmpty()) {
            return
        }
        if (source[source.size - 1].meta.size < help.substitutions[help.substitutions.size - 1].range.begin.column) {
            return
        }
        let collectedInfos = HelpSubstituteConvert(help, source)
        let infoMap = StoreInfoToMap(collectedInfos)
        if (!CombineErrorPrint(infoMap, source)) {
            return
        }
        HandleUnprintableChar(source)
        if (!noColor) {
            ColorizeCombinedVec(source)
        }
        EmitSourceCode(builder, source)
    }

    private func EmitSingleMessageWithoutSource(builder: StringBuilder, str: String, host: String): Unit {
        var combined = g_spaceOfNum(maxLineNum + 1)
        var color = if (noColor) { DiagColor.NO_COLOR } else { OTHER_HINT_COLOR }
        combined += GetColoredString(color, WITHOUT_SOURCE_SYMBOL)
        combined += g_spaceOfNum(1)
        color = if (noColor) { DiagColor.NO_COLOR } else { DiagColor.RESET }
        combined += GetColoredString(color, host, isBright: false)
        combined += CharacterOfNum(1, COLON)
        combined += g_spaceOfNum(1)
        combined += str
        builder.append(combined + "\n")
    }

    private func EmitNote(builder: StringBuilder): Unit {
        if (diagnostic.subDiags.isEmpty()) {
            return
        }
        for (subDiag in diagnostic.subDiags) {
            if (subDiag.IsShowSource()) {
                continue
            }
            if (let Some(info) <- diagnostic.macroDiagInfo) {
                if (subDiag.subDiagMessage == MACROCALL_CODE) {
                    if (info.hasShownCode) {
                        continue
                    }
                    info.hasShownCode = true
                }
            }
            EmitSingleMessageWithoutSource(builder, subDiag.subDiagMessage, "note")
        }
        for (subDiag in diagnostic.subDiags) {
            if (!subDiag.IsShowSource()) {
                continue
            }
            if (let Some(info) <- diagnostic.macroDiagInfo) {
                if (subDiag.subDiagMessage == MACROCALL_CODE) {
                    if (info.hasShownCode) {
                        continue
                    }
                    info.hasShownCode = true
                }
            }
            EmitSingleNoteWithSource(builder, subDiag)
        }
    }

    private func EmitHelp(builder: StringBuilder, helps: ArrayList<DiagHelp>): Unit {
        if (helps.isEmpty()) {
            return
        }
        for (help in helps) {
            if (!help.IsShowSource()) {
                EmitSingleMessageWithoutSource(builder, help.helpMes, "help")
            }
        }
        for (help in helps) {
            if (help.IsShowSource()) {
                EmitSingleHelpWithSource(builder, help)
            }
        }
    }

    private func ColorizeCombinedVec(combinedVec: SourceCombinedVec): Unit {
        var combinedIndex: Int64 = 0
        while (combinedIndex < combinedVec.size) {
            var combinedLine = combinedVec[combinedIndex]
            sort(combinedLine.colors, by: { left: ColorTuple, right: ColorTuple =>
                if (left[0] == right[0]) {
                    if (left[1] > right[1]) {
                        Ordering.LT
                    } else if (right[1] > left[1]) {
                        Ordering.GT
                    } else {
                        Ordering.EQ
                    }
                } else if (left[0] < right[0]) {
                    Ordering.LT
                } else {
                    Ordering.GT
                }
            })
            let vec = ArrayList<DiagColor>()
            var idx: Int64 = 0
            while (idx < combinedLine.meta.size) {
                vec.add(DiagColor.RESET)
                idx++
            }
            for (color in combinedLine.colors) {
                var colorIndex = color[0]
                while (colorIndex < color[1]) {
                    vec[colorIndex] = color[2]
                    colorIndex++
                }
            }
            let raw = combinedLine.meta
            let colorized = StringBuilder()
            if (!vec.isEmpty() && vec[0] != DiagColor.RESET) {
                colorized.append(colorToAnsi(vec[0]))
            }
            idx = 0
            while (idx < raw.size) {
                if (idx > 0 && vec[idx - 1] != vec[idx]) {
                    colorized.append(colorToAnsi(vec[idx]))
                }
                colorized.append(raw[idx..idx + 1])
                idx++
            }
            colorized.append(colorToAnsi(DiagColor.RESET))
            combinedLine.meta = colorized.toString()
            combinedVec[combinedIndex] = combinedLine
            combinedIndex++
        }
    }

    private func ConstructAndEmitSourceCode(builder: StringBuilder, errorInfo: ArrayList<CollectedInfo>): Unit {
        if (errorInfo.isEmpty()) {
            return
        }
        let hasSourceFile = sourceManager.IsSourceFileExist(errorInfo[0].range.begin.fileID)
        let infoMap = StoreInfoToMap(errorInfo)
        let lineCodes = ArrayList<String>()
        for (line in SplitLines(GetSourceCode(errorInfo))) {
            lineCodes.add(line)
        }
        if (lineCodes.isEmpty()) {
            return
        }
        if (lineCodes[lineCodes.size - 1].isEmpty()) {
            lineCodes.remove(at: lineCodes.size - 1)
        }
        if (infoMap.isEmpty()) {
            return
        }
        var base: Int64 = 0
        for (key in infoMap.keys()) {
            base = key
            break
        }
        let combinedVec = SourceCombinedVec()
        for (line in lineCodes) {
            combinedVec.add(CombinedLine(line, base, hasSourceFile))
            base++
        }
        if (!CombineErrorPrint(infoMap, combinedVec)) {
            return
        }
        HandleUnprintableChar(combinedVec)
        if (!noColor) {
            ColorizeCombinedVec(combinedVec)
        }
        EmitSourceCode(builder, combinedVec)
    }

    private func swapErrorMessageWithNote(): Unit {
        if (macroNoteSwapped || diagnostic.subDiags.isEmpty()) {
            return
        }
        if (let Some(info) <- diagnostic.macroDiagInfo) {
            let mainHint = diagnostic.mainHint
            if (info.isCurFile || mainHint.range.begin.isCurFile ||
                (diagnostic.start != INVALID_POSITION && diagnostic.start.isCurFile) ||
                !sourceManager.IsInMacroCallSourceFile(mainHint.range.begin) ||
                (diagnostic.start != INVALID_POSITION && !sourceManager.IsInMacroCallSourceFile(diagnostic.start))) {
                return
            }
            let subDiag = diagnostic.subDiags[0]
            if (diagnostic.isRefactor) {
                swapRefactorMacroNote(subDiag, mainHint)
            } else {
                swapLegacyMacroNote(subDiag)
            }
            macroNoteSwapped = true
        }
    }

    private func swapRefactorMacroNote(subDiag: SubDiagnostic, mainHint: IntegratedString): Unit {
        let newSubDiag = SubDiagnostic(diagnostic.errorMessage)
        newSubDiag.AddMainHint(mainHint.range, mainHint.str)
        for (hint in diagnostic.otherHints) {
            newSubDiag.otherHints.add(hint)
        }
        diagnostic.subDiags[0] = newSubDiag
        diagnostic.errorMessage = subDiag.subDiagMessage
        diagnostic.mainHint = IntegratedString(subDiag.mainHint.range, "", mainHint.color)
        diagnostic.otherHints.clear()
        for (hint in subDiag.otherHints) {
            diagnostic.otherHints.add(hint)
        }
    }

    private func swapLegacyMacroNote(subDiag: SubDiagnostic): Unit {
        let newSubDiag = SubDiagnostic(diagnostic.diagMessage)
        newSubDiag.AddMainHint(MakeRange(diagnostic.start, diagnostic.end), "")
        diagnostic.subDiags.add(newSubDiag, at: 0)
        diagnostic.diagMessage = subDiag.subDiagMessage
        diagnostic.errorMessage = subDiag.subDiagMessage
        diagnostic.start = subDiag.mainHint.range.begin
        diagnostic.end = subDiag.mainHint.range.end
        diagnostic.mainHint = IntegratedString(subDiag.mainHint.range, "", diagnostic.mainHint.color)
        diagnostic.otherHints.clear()
        for (hint in subDiag.otherHints) {
            diagnostic.otherHints.add(hint)
        }
    }
}
