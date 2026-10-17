import Foundation

public struct SubstitutionRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String { input }
    public let input: String
    public let replacement: String
    public var automatic: Bool
    public init(input: String, replacement: String, automatic: Bool = false) {
        self.input = input; self.replacement = replacement; self.automatic = automatic
    }
    public var explicitSequence: String { "|" + input.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "|", with: "\\|") + "|" }
}

public struct SmartSubstitutionSettings: Codable, Hashable {
    public var enabled = false
    public var automaticOverrides: [String: Bool] = [:]
    public var custom: [SubstitutionRule] = []
    public init() {}
    public var rules: [SubstitutionRule] {
        Self.builtIns.map { rule in
            var rule = rule
            rule.automatic = automaticOverrides[rule.input] ?? rule.automatic
            return rule
        } + custom
    }
    /// Input is stored verbatim. Bounds also limit pathological combining sequences and output payloads.
    public static func validation(input: String, replacement: String, otherInputs: [String]) -> String? {
        if input.isEmpty || input.count > 10 { return "Input must contain 1–10 characters." }
        if input.utf16.count > 256 { return "Input must use at most 256 UTF-16 units." }
        if input.contains("|") { return "Input cannot contain the delimiter |." }
        if input.contains("`") { return "Input cannot contain backticks, which mark protected inline code." }
        if input.first?.isWhitespace == true || input.last?.isWhitespace == true || input.contains(where: { $0.isNewline || $0 == "\t" }) {
            return "Input cannot start or end with whitespace, or contain tabs or line breaks."
        }
        if input.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) { return "Input cannot contain control characters." }
        if otherInputs.contains(input) { return "This input already exists." }
        if replacement.isEmpty { return "Replacement cannot be empty." }
        if replacement.utf16.count > 16_384 { return "Replacement must use at most 16,384 UTF-16 units." }
        if input == replacement { return "Input and replacement must differ." }
        return nil
    }
    public static let builtIns: [SubstitutionRule] = [
        .init(input: ":)", replacement: "🙂", automatic: true),
        .init(input: ":-)", replacement: "🙂", automatic: true),
        .init(input: ":(", replacement: "🙁", automatic: true),
        .init(input: ":-(", replacement: "🙁", automatic: true),
        .init(input: ";)", replacement: "😉", automatic: true),
        .init(input: ";-)", replacement: "😉", automatic: true),
        .init(input: ":D", replacement: "😃", automatic: true),
        .init(input: ":-D", replacement: "😃", automatic: true),
        .init(input: ":P", replacement: "😛", automatic: true),
        .init(input: ":-P", replacement: "😛", automatic: true),
        .init(input: ":O", replacement: "😮", automatic: true),
        .init(input: ":-O", replacement: "😮", automatic: true),
        .init(input: ":'(", replacement: "😢", automatic: true),
        .init(input: ":-/", replacement: "😕", automatic: true),
        .init(input: ":-|", replacement: "😐", automatic: true),
        .init(input: "8-)", replacement: "😎", automatic: true),
        .init(input: "(c)", replacement: "©", automatic: true),
        .init(input: "(r)", replacement: "®", automatic: true),
        .init(input: "(tm)", replacement: "™", automatic: true),
        .init(input: "<3", replacement: "❤️", automatic: true),
        .init(input: "->", replacement: "→", automatic: false),
        .init(input: "<-", replacement: "←", automatic: false),
        .init(input: "<->", replacement: "↔", automatic: false),
        .init(input: "=>", replacement: "⇒", automatic: false),
        .init(input: "<=", replacement: "≤", automatic: false),
        .init(input: ">=", replacement: "≥", automatic: false),
        .init(input: "<=>", replacement: "⇔", automatic: false),
        .init(input: "-->", replacement: "⟶", automatic: false),
        .init(input: "<--", replacement: "⟵", automatic: false),
        .init(input: "==>", replacement: "⟹", automatic: false),
        .init(input: "!=", replacement: "≠", automatic: false),
        .init(input: "~=", replacement: "≈", automatic: false),
        .init(input: "===", replacement: "≡", automatic: false),
        .init(input: "+-", replacement: "±", automatic: false),
        .init(input: "+/-", replacement: "±", automatic: false),
        .init(input: "-+", replacement: "∓", automatic: false),
        .init(input: "...", replacement: "…", automatic: false),
        .init(input: "--", replacement: "–", automatic: false),
        .init(input: "---", replacement: "—", automatic: false),
        .init(input: "1/2", replacement: "½", automatic: false),
        .init(input: "1/4", replacement: "¼", automatic: false),
        .init(input: "3/4", replacement: "¾", automatic: false),
        .init(input: "sqrt", replacement: "√", automatic: false),
        .init(input: "&&", replacement: "∧", automatic: false),
        .init(input: "||", replacement: "∨", automatic: false),
        .init(input: ":=", replacement: "≔", automatic: false),
        .init(input: "::=", replacement: "≔", automatic: false),
        .init(input: "~~>", replacement: "⇝", automatic: false),
        .init(input: "|->", replacement: "↦", automatic: false),
        .init(input: ":|", replacement: "😐", automatic: false),
        .init(input: ":/", replacement: "😕", automatic: false),
        .init(input: "8)", replacement: "😎", automatic: false),
        .init(input: "</3", replacement: "💔", automatic: false),
        .init(input: "(p)", replacement: "℗", automatic: false),
        .init(input: "(x)", replacement: "☒", automatic: false),
        .init(input: "( )", replacement: "☐", automatic: false),
        .init(input: "(*)", replacement: "★", automatic: false),
        .init(input: "(+)", replacement: "⊕", automatic: false),
        .init(input: "(i)", replacement: "ℹ️", automatic: false),
        .init(input: "(!)", replacement: "❗", automatic: false),
        .init(input: "(?)", replacement: "❓", automatic: false),
    ]
}

/// Compiled only when settings change. Each edit uses dictionary lookups over a bounded suffix.
public struct SmartSubstitutionMatcher {
    public struct Match: Equatable {
        public let range: NSRange
        public let replacement: String
    }
    private let explicit: [String: String]
    private let automatic: [String: String]
    public let maximumWindow: Int
    public init(settings: SmartSubstitutionSettings) {
        var explicit: [String: String] = [:], automatic: [String: String] = [:]
        if settings.enabled {
            for rule in settings.rules {
                explicit[rule.explicitSequence] = rule.replacement
                if rule.automatic { automatic[rule.input] = rule.replacement }
            }
        }
        self.explicit = explicit; self.automatic = automatic
        maximumWindow = max(explicit.keys.map { $0.utf16.count }.max() ?? 0, automatic.keys.map { $0.utf16.count + 1 }.max() ?? 0)
    }
    public func match(in source: NSString, caret: Int, typed: String) -> Match? {
        guard maximumWindow > 0, caret > 0, caret <= source.length,
              typed == "|" || [" ", "\t", "\n", "\r"].contains(typed),
              source.substring(with: NSRange(location: caret - typed.utf16.count, length: typed.utf16.count)) == typed else { return nil }
        let start = max(0, caret - maximumWindow - 1)
        let local = source.substring(with: NSRange(location: start, length: caret - start))
        let end = typed == "|" ? local.endIndex : local.index(before: local.endIndex)
        let candidates = typed == "|" ? explicit : automatic
        // Work from longest to shortest; require a whole whitespace-delimited token for Automatic.
        for index in local.indices where index < end {
            let candidate = String(local[index..<end])
            guard let replacement = candidates[candidate] else { continue }
            let location = start + local[..<index].utf16.count
            if typed != "|" {
                guard location == 0 || String(decoding: [source.character(at: location - 1)], as: UTF16.self).first?.isWhitespace == true else { continue }
            } else if location > 0 {
                let preceding = String(decoding: [source.character(at: location - 1)], as: UTF16.self)
                // Explicit triggers start a token or follow an opening bracket/quote. This also
                // leaves escaped openers, identifiers, paths, and URL components untouched.
                var openingStart = location
                while openingStart > 0 && location - openingStart < 8 && [UInt16(40), 91, 123, 34, 39].contains(source.character(at: openingStart - 1)) { openingStart -= 1 }
                let beforeOpenings = openingStart > 0 ? String(decoding: [source.character(at: openingStart - 1)], as: UTF16.self) : " "
                guard preceding.first?.isWhitespace == true || beforeOpenings.first?.isWhitespace == true else { continue }
            }
            return Match(range: NSRange(location: location, length: candidate.utf16.count), replacement: replacement)
        }
        return nil
    }
}

/// Cached line-boundary Markdown state. Edits invalidate checkpoints at and after the edited line.
/// A trigger scans only the uncached prefix; editing early fences may require rescanning a long prefix.
public final class SubstitutionMarkdownContext {
    private struct State { var fence: UInt16 = 0; var width = 0; var inlineWidth = 0; var quoteDepth = 0; var containerIndent = 0 }
    private var checkpoints: [(offset: Int, state: State)] = [(0, State())]
    public init() {}
    public func invalidate(from offset: Int) {
        while checkpoints.count > 1 && checkpoints.last!.offset >= offset { checkpoints.removeLast() }
        // The checkpoint at an edited line's end depends on that line, too.
    }
    public func allows(_ source: NSString, range: NSRange) -> Bool {
        guard range.location >= 0, NSMaxRange(range) <= source.length else { return false }
        var low = 0, high = checkpoints.count
        while low + 1 < high {
            let mid = (low + high) / 2
            if checkpoints[mid].offset <= range.location { low = mid } else { high = mid }
        }
        var (offset, state) = checkpoints[low]
        while offset <= range.location && offset < source.length {
            let lineRange = source.lineRange(for: NSRange(location: offset, length: 0))
            let line = Array(source.substring(with: lineRange).utf16)
            var p = 0, quoteDepth = 0, indent = 0, containerIndent = 0
            var validClosingIndent = true
            let hadFence = state.fence != 0
            // Closing fences never strip list markers: a code line "- ```" is content,
            // not a closing fence. Quoted fences require their opener's quote depth.
            while p < line.count {
                if [UInt16(32), 9].contains(line[p]) {
                    indent += line[p] == 9 ? 4 - indent % 4 : 1
                    p += 1; continue
                }
                if line[p] == 62 && (!hadFence || quoteDepth < state.quoteDepth) {
                    if hadFence && indent > 3 { validClosingIndent = false }
                    quoteDepth += 1; p += 1; indent = 0; containerIndent = 0
                    if p < line.count && line[p] == 32 { p += 1 }
                    continue
                }
                if hadFence { break }
                if p + 1 < line.count && [UInt16(45), 43, 42].contains(line[p]) && line[p + 1] == 32 {
                    p += 2; indent += 2; containerIndent = indent; continue
                }
                var numberEnd = p
                while numberEnd < line.count && (48...57).contains(line[numberEnd]) { numberEnd += 1 }
                if numberEnd > p && numberEnd + 1 < line.count && [UInt16(46), 41].contains(line[numberEnd]) && line[numberEnd + 1] == 32 {
                    indent += numberEnd + 2 - p; p = numberEnd + 2; containerIndent = indent; continue
                }
                break
            }
            var width = 0
            let marker: UInt16 = p < line.count ? line[p] : 0
            if marker == 96 || marker == 126 { while p + width < line.count && line[p + width] == marker { width += 1 } }
            if hadFence {
                if validClosingIndent && indent <= state.containerIndent + 3 && quoteDepth == state.quoteDepth && marker == state.fence && width >= state.width && line.dropFirst(p + width).allSatisfy({ [UInt16(32), 9, 10, 13].contains($0) }) {
                    state.fence = 0; state.width = 0; state.inlineWidth = 0
                }
            } else if width >= 3 {
                state.fence = marker; state.width = width; state.quoteDepth = quoteDepth; state.containerIndent = containerIndent; state.inlineWidth = 0
            }
            if offset + line.count > range.location {
                if hadFence || state.fence != 0 { return false }
                let limit = min(line.count, NSMaxRange(range) - offset)
                // Unclosed inline spans remain protected, including across lines.
                var i = 0
                var protected = state.inlineWidth > 0 && range.location == offset
                while i < limit {
                    if line[i] == 92 { i += 2; continue }
                    if line[i] == 96 {
                        var run = 1
                        while i + run < line.count && line[i + run] == 96 { run += 1 }
                        if state.inlineWidth == 0 { state.inlineWidth = run }
                        else if state.inlineWidth == run { state.inlineWidth = 0 }
                        i += run
                    } else { i += 1 }
                    if offset + i >= range.location && state.inlineWidth > 0 { protected = true }
                }
                return !protected && state.inlineWidth == 0
            }
            if !hadFence && state.fence == 0 {
                var i = 0
                while i < line.count {
                    if line[i] == 92 { i += 2; continue }
                    if line[i] == 96 {
                        var run = 1
                        while i + run < line.count && line[i + run] == 96 { run += 1 }
                        if state.inlineWidth == 0 { state.inlineWidth = run }
                        else if state.inlineWidth == run { state.inlineWidth = 0 }
                        i += run
                    } else { i += 1 }
                }
            }
            offset += line.count
            if checkpoints.last!.offset < offset { checkpoints.append((offset, state)) }
        }
        return state.fence == 0 && state.inlineWidth == 0
    }
}
