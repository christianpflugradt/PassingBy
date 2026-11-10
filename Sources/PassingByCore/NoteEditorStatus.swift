import Foundation

public struct NoteEditorStatus: Equatable {
    public let line: Int
    public let column: Int
    public let words: Int
    public let characters: Int

    public init(source: String, caretUTF16Offset: Int) {
        let text = source as NSString
        let offset = min(max(caretUTF16Offset, 0), text.length)
        var lineStart = 0
        var lineNumber = 1
        while lineStart < offset {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getLineStart(
                &start, end: &end, contentsEnd: &contentsEnd,
                for: NSRange(location: lineStart, length: 0))
            if end > offset || end <= lineStart || contentsEnd == end { break }
            lineStart = end
            lineNumber += 1
        }
        let columnText = text.substring(with: NSRange(location: lineStart, length: offset - lineStart))
        line = lineNumber
        column = columnText.count + 1
        characters = source.count
        var wordCount = 0
        source.enumerateSubstrings(in: source.startIndex..<source.endIndex, options: .byWords) { _, _, _, _ in
            wordCount += 1
        }
        words = wordCount
    }
}
