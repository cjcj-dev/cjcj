package cangjie_compiler::ast

import std.collection.*

public enum CommentStyle {
    | LEAD_LINE
    | TRAIL_CODE
    | OTHER
}

public enum CommentKind {
    | LINE
    | BLOCK
    | DOCUMENT
}

public class Comment {
    public var style: CommentStyle = CommentStyle.OTHER
    public var kind: CommentKind = CommentKind.LINE
    public var info: Token = Token(TokenKind.ILLEGAL)

    public init() {}

    public init(style: CommentStyle, kind: CommentKind, info: Token) {
        this.style = style
        this.kind = kind
        this.info = info
    }

    public func ToString(): String {
        let styleText = match (style) {
            case CommentStyle.LEAD_LINE => "leadLine"
            case CommentStyle.TRAIL_CODE => "trailCode"
            case CommentStyle.OTHER => "other"
        }
        let kindText = match (kind) {
            case CommentKind.LINE => "line"
            case CommentKind.BLOCK => "block"
            case CommentKind.DOCUMENT => "doc"
        }
        return "{\"style\":\"${styleText}\", \"kind\":\"${kindText}\", \"info\":\"${EscapeToJsonString(info.Value())}\"}"
    }
}

public class CommentGroup {
    public let cms: ArrayList<Comment> = ArrayList<Comment>()

    public init() {}

    public func IsEmpty(): Bool {
        return cms.isEmpty()
    }

    public func ToString(): String {
        if (IsEmpty()) {
            return "{\"cms\":[]}"
        }
        let parts = ArrayList<String>()
        for (comment in cms) {
            parts.add(comment.ToString())
        }
        return "{\"cms\":[" + JoinStrings(parts, ", ") + "]}"
    }
}

public class CommentGroups {
    public let leadingComments: ArrayList<CommentGroup> = ArrayList<CommentGroup>()
    public let innerComments: ArrayList<CommentGroup> = ArrayList<CommentGroup>()
    public let trailingComments: ArrayList<CommentGroup> = ArrayList<CommentGroup>()

    public init() {}

    public func IsEmpty(): Bool {
        return leadingComments.isEmpty() && innerComments.isEmpty() && trailingComments.isEmpty()
    }

    private func groupsToString(name: String, groups: ArrayList<CommentGroup>, delimiter: String): String {
        let values = ArrayList<String>()
        for (group in groups) {
            values.add(group.ToString())
        }
        return "\"${name}\":[" + JoinStrings(values, delimiter) + "]"
    }

    public func ToString(): String {
        if (IsEmpty()) {
            return "{}"
        }
        let parts = ArrayList<String>()
        if (!leadingComments.isEmpty()) {
            parts.add(groupsToString("leadingComments", leadingComments, ", "))
        }
        if (!innerComments.isEmpty()) {
            parts.add(groupsToString("innerComments", innerComments, ","))
        }
        if (!trailingComments.isEmpty()) {
            parts.add(groupsToString("trailingComments", trailingComments, ", "))
        }
        return "{" + JoinStrings(parts, ", ") + "}"
    }
}
