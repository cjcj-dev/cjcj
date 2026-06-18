package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    private func CommentList(): ArrayList<Token> {
        let comments = ArrayList<Token>()
        for (comment in lexer.GetComments()) {
            comments.add(comment)
        }
        return comments
    }

    public func AttachCommentToFile(file: File): Unit {
        commentsMap.Put(UInt32(file.fileID), CommentList())
    }

    public func AttachCommentToNodes(nodes: ArrayList<Node>): Unit {
        commentsMap.Put(UInt32(lexer.GetFileID()), CommentList())
        let _ = nodes
    }
}
