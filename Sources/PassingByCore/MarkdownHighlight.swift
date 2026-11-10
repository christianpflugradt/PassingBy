import Foundation

public enum MarkdownHighlight {
    public enum Style: Equatable {
        case heading(Int), syntax, code, linkText, linkURL, bold, italic, strike, quote
    }

    public struct Span: Equatable {
        public let range: NSRange
        public let style: Style
        public init(_ range: NSRange, _ style: Style) { self.range = range; self.style = style }
    }

    public struct Link: Equatable {
        public let range: NSRange
        public let url: URL
    }

    public struct Checkbox: Equatable {
        public let range: NSRange
        public let checked: Bool
    }

    public struct Result {
        public let spans: [Span]
        public let links: [Link]
        public let checkboxes: [Checkbox]
    }

    public static func parse(_ source: String) -> Result {
        let chars = Array(source.utf16)
        let count = chars.count
        var spans: [Span] = []
        var links: [Link] = []
        var checkboxes: [Checkbox] = []
        var protected = Array(repeating: false, count: count)
        func add(_ start: Int, _ end: Int, _ style: Style) {
            if start < end { spans.append(Span(NSRange(location: start, length: end - start), style)) }
        }
        func mark(_ start: Int, _ end: Int) {
            if start < end { for i in start..<end { protected[i] = true } }
        }
        func escaped(_ i: Int) -> Bool {
            var slashes = 0; var j = i
            while j > 0 && chars[j - 1] == 92 { slashes += 1; j -= 1 }
            return slashes % 2 == 1
        }
        func prefix(_ at: Int, _ end: Int, _ value: [UInt16]) -> Bool {
            at + value.count <= end && chars[at..<(at + value.count)].elementsEqual(value)
        }
        func url(_ start: Int, _ end: Int) -> URL? {
            guard start < end else { return nil }
            let value = String(decoding: chars[start..<end], as: UTF16.self)
            guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
                ["http", "https"].contains(scheme), url.host != nil
            else { return nil }
            return url
        }
        var line = 0
        var fenceWidth = 0
        while line < count {
            var end = line
            while end < count && chars[end] != 10 { end += 1 }
            let next = end < count ? end + 1 : end
            var p = line
            while p < end && p - line < 3 && chars[p] == 32 { p += 1 }
            var ticks = 0
            while p + ticks < end && chars[p + ticks] == 96 { ticks += 1 }
            if fenceWidth > 0 {
                if ticks >= fenceWidth && chars[(p + ticks)..<end].allSatisfy({ $0 == 32 || $0 == 9 }) {
                    add(p, end, .syntax); fenceWidth = 0
                } else {
                    add(line, end, .code)
                }
                mark(line, next); line = next; continue
            }
            if ticks >= 3 {
                add(p, end, .syntax); mark(line, next); fenceWidth = ticks; line = next; continue
            }
            let trimmed = chars[line..<end].filter { $0 != 32 && $0 != 9 }
            if trimmed.count >= 3 && [UInt16(45), 42, 95].contains(trimmed[0]) && trimmed.allSatisfy({ $0 == trimmed[0] }) {
                add(line, end, .syntax); mark(line, next); line = next; continue
            }
            var hashes = 0
            while p + hashes < end && chars[p + hashes] == 35 { hashes += 1 }
            if (1...6).contains(hashes) && (p + hashes == end || chars[p + hashes] == 32 || chars[p + hashes] == 9) {
                add(line, end, .heading(hashes)); mark(line, next); line = next; continue
            }
            var content = p
            while content < end && chars[content] == 62 {
                content += 1
                if content < end && chars[content] == 32 { content += 1 }
            }
            if content > p { add(content, end, .quote); add(p, content, .syntax) }
            let marker = content
            if content + 1 < end && [UInt16(45), 42, 43].contains(chars[content]) && chars[content + 1] == 32 {
                content += 2
            } else {
                while content < end && chars[content] >= 48 && chars[content] <= 57 { content += 1 }
                if content == marker || content + 1 >= end || chars[content] != 46 || chars[content + 1] != 32 {
                    content = marker
                } else {
                    content += 2
                }
            }
            if content > marker {
                if content + 2 < end && chars[content] == 91 && [UInt16(32), 120, 88].contains(chars[content + 1])
                    && chars[content + 2] == 93 && (content + 3 == end || chars[content + 3] == 32)
                {
                    checkboxes.append(Checkbox(range: NSRange(location: content, length: 3), checked: chars[content + 1] != 32))
                    content += content + 3 == end ? 3 : 4
                }
                add(marker, content, .syntax)
            }
            var i = content
            while i < end {
                if escaped(i) { i += 1; continue }
                if chars[i] == 96 {
                    var width = 0
                    while i + width < end && chars[i + width] == 96 { width += 1 }
                    var j = i + width
                    while j < end {
                        if chars[j] == 96 && !escaped(j) && prefix(j, end, Array(repeating: 96, count: width)) {
                            add(i, i + width, .syntax); add(i + width, j, .code); add(j, j + width, .syntax)
                            mark(i, j + width); i = j + width; break
                        }
                        j += 1
                    }
                    if j == end { i += width }
                    continue
                }
                if chars[i] == 91, let close = ((i + 1)..<end).first(where: { chars[$0] == 93 && !escaped($0) }),
                    close + 1 < end && chars[close + 1] == 40,
                    let finish = ((close + 2)..<end).first(where: { chars[$0] == 41 && !escaped($0) }),
                    close > i + 1, finish > close + 2
                {
                    add(i, i + 1, .syntax); add(i + 1, close, .linkText)
                    add(close, close + 2, .syntax); add(close + 2, finish, .linkURL); add(finish, finish + 1, .syntax)
                    if let target = url(close + 2, finish) {
                        links.append(Link(range: NSRange(location: close + 2, length: finish - close - 2), url: target))
                    }
                    mark(i, finish + 1); i = finish + 1; continue
                }
                if chars[i] == 60, let finish = ((i + 1)..<end).first(where: { chars[$0] == 62 && !escaped($0) }),
                    let target = url(i + 1, finish)
                {
                    add(i, i + 1, .syntax); add(i + 1, finish, .linkURL); add(finish, finish + 1, .syntax)
                    links.append(Link(range: NSRange(location: i + 1, length: finish - i - 1), url: target))
                    mark(i, finish + 1); i = finish + 1; continue
                }
                i += 1
            }
            for (delimiter, style) in [
                ("***", Style.bold), ("___", .bold), ("**", .bold), ("__", .bold), ("~~", .strike), ("*", .italic), ("_", .italic),
            ] {
                let token = Array(delimiter.utf16)
                let width = token.count
                var k = content
                while k + width < end {
                    if protected[k] || escaped(k) || !prefix(k, end, token) || chars[k + width] == 32 || chars[k + width] == 9
                        || (width == 1 && k + 1 < end && chars[k + 1] == token[0]) || (token[0] == 95 && k > line && isWord(chars[k - 1]))
                    {
                        k += 1; continue
                    }
                    var close = k + width + 1
                    while close + width <= end {
                        if protected[close] { break }
                        if !protected[close] && !escaped(close) && chars[close - 1] != 32 && chars[close - 1] != 9
                            && prefix(close, end, token) && !(token[0] == 95 && close + width < end && isWord(chars[close + width]))
                        {
                            break
                        }
                        close += 1
                    }
                    if close + width <= end && !protected[close] && chars[close - 1] != 32 && chars[close - 1] != 9
                        && prefix(close, end, token)
                    {
                        add(k, k + width, .syntax); add(close, close + width, .syntax)
                        if width == 3 { add(k + width, close, .bold); add(k + width, close, .italic) } else { add(k + width, close, style) }
                        mark(k, k + width); mark(close, close + width)
                        k = close + width
                    } else {
                        k += width
                    }
                }
            }
            line = next
        }
        return Result(spans: spans, links: links, checkboxes: checkboxes)
    }

    private static func isWord(_ c: UInt16) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }
}
