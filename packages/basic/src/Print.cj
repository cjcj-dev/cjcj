package cangjie_compiler::basic

public enum DiagColor {
    | NO_COLOR
    | RESET
    | BLACK
    | RED
    | GREEN
    | YELLOW
    | BLUE
    | MAGENTA
    | CYAN
    | WHITE
    | REVERSE
}

private func DiagColorIndex(color: DiagColor): Int64 {
    return match (color) {
        case DiagColor.NO_COLOR => 0
        case DiagColor.RESET => 1
        case DiagColor.BLACK => 2
        case DiagColor.RED => 3
        case DiagColor.GREEN => 4
        case DiagColor.YELLOW => 5
        case DiagColor.BLUE => 6
        case DiagColor.MAGENTA => 7
        case DiagColor.CYAN => 8
        case DiagColor.WHITE => 9
        case DiagColor.REVERSE => 10
    }
}

extend DiagColor <: Equatable<DiagColor> {
    public operator func ==(right: DiagColor): Bool {
        return DiagColorIndex(this) == DiagColorIndex(right)
    }

    public operator func !=(right: DiagColor): Bool {
        return !(this == right)
    }
}

public let RED_ERROR_MARK: String = ANSI_COLOR_RED + "error" + ANSI_COLOR_RESET + ": "
public let YELLOW_WARNING_MARK: String = ANSI_COLOR_YELLOW + "warning" + ANSI_COLOR_RESET + ": "
public let GREEN_INFO_MARK: String = ANSI_COLOR_GREEN + "info" + ANSI_COLOR_RESET + ": "
public let GREEN_DEBUG_MARK: String = ANSI_COLOR_GREEN + "debug" + ANSI_COLOR_RESET + ": "

public func colorToAnsi(color: DiagColor): String {
    return match (color) {
        case DiagColor.NO_COLOR => ANSI_NO_COLOR
        case DiagColor.RESET => ANSI_COLOR_RESET
        case DiagColor.BLACK => ANSI_COLOR_BLACK
        case DiagColor.RED => ANSI_COLOR_RED
        case DiagColor.GREEN => ANSI_COLOR_GREEN
        case DiagColor.YELLOW => ANSI_COLOR_YELLOW
        case DiagColor.BLUE => ANSI_COLOR_BLUE
        case DiagColor.MAGENTA => ANSI_COLOR_MAGENTA
        case DiagColor.CYAN => ANSI_COLOR_CYAN
        case DiagColor.WHITE => ANSI_COLOR_WHITE
        case DiagColor.REVERSE => ANSI_COLOR_WHITE_BACKGROUND_BLACK_FOREGROUND
    }
}

public func coloredString(color: DiagColor, content: String, isBright!: Bool = false): String {
    if (color == DiagColor.NO_COLOR) {
        return content
    }
    let bright = if (isBright) { ANSI_COLOR_BRIGHT } else { "" }
    return colorToAnsi(color) + bright + content + ANSI_COLOR_RESET
}

public func Println(value!: String = ""): Unit {
    println(value)
}

public func Print(value: String): Unit {
    print(value)
}

public func PrintNoSplit(value: String): Unit {
    print(value)
}

public func PrintIndentOnly(indent: UInt64, numSpaces!: UInt64 = 2): Unit {
    print(repeatString(" ", Int64(indent * numSpaces)))
}

public func PrintIndent(indent: UInt64, value: String): Unit {
    PrintIndentOnly(indent)
    println(value)
}

public func PrintCommandDesc(option: String, desc: String, optionWidth: Int64): Unit {
    let padding = if (optionWidth > option.size) { repeatString(" ", optionWidth - option.size) } else { "" }
    println("  " + option + padding + desc)
}

public func WriteError(value: String): Unit {
    eprint(value)
}

public func Error(value: String): Unit {
    eprint(RED_ERROR_MARK + value)
}

public func Errorln(value: String): Unit {
    eprintln(RED_ERROR_MARK + value)
}

public func Warning(value: String): Unit {
    eprint(YELLOW_WARNING_MARK + value)
}

public func Warningln(value: String): Unit {
    eprintln(YELLOW_WARNING_MARK + value)
}

public func Info(value: String): Unit {
    print(GREEN_INFO_MARK + value)
}

public func Infoln(value: String): Unit {
    println(GREEN_INFO_MARK + value)
}

@When[debug]
public func Debug(value: String): Unit {
    print(GREEN_DEBUG_MARK + value)
}

@When[!debug]
public func Debug(value: String): Unit {
    let _ = value
}

@When[debug]
public func Debugln(value: String): Unit {
    println(GREEN_DEBUG_MARK + value)
}

@When[!debug]
public func Debugln(value: String): Unit {
    let _ = value
}

public func ErrorWithColor(color: DiagColor, content: String, isBright!: Bool = false): Unit {
    let bright = if (isBright) { ANSI_COLOR_BRIGHT } else { "" }
    let reset = if (color == DiagColor.NO_COLOR) { "" } else { ANSI_COLOR_RESET }
    eprint(bright + colorToAnsi(color) + content + reset)
}
