package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func AttachCommentToFile(file: File): Unit {
        let comments = lexer.GetComments()
        commentsMap.Put(file.fileID, comments)
    }

    public func AttachCommentToNodes(nodes: ArrayList<Node>): Unit {
        let comments = lexer.GetComments()
        commentsMap.Put(lexer.GetFileID(), comments)
        for (node in nodes) {
            node.curFile = if (let Some(file) <- currentFile) { file } else { None }
        }
    }
}
