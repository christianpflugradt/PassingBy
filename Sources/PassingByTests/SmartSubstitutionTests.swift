import Foundation
import PassingByCore

func testSmartSubstitutions() throws {
    var settings = SmartSubstitutionSettings()
    func match(_ source: String, _ typed: String = "|") -> SmartSubstitutionMatcher.Match? {
        SmartSubstitutionMatcher(settings: settings).match(in: source as NSString, caret: source.utf16.count, typed: typed)
    }
    expect(match("|sqrt|") == nil && match(":) ", " ") == nil, "global off disables both syntaxes")
    settings.enabled = true
    expect(match("sqrtX", "\n") == nil, "a command without an inserted boundary cannot match")
    expect(match("|sqrt|")?.replacement == "√", "explicit works independently of Automatic")
    expect(match("sqrt ", " ") == nil, "ordinary words default to explicit only")
    settings.automaticOverrides["sqrt"] = true
    expect(match("sqrt ", " ")?.replacement == "√", "per-rule override enables Automatic")
    expect(SmartSubstitutionSettings.builtIns.count == 61 && Set(SmartSubstitutionSettings.builtIns.map(\.input)).count == 61, "catalog has exactly the proposed distinct inputs")
    expect(SmartSubstitutionSettings.builtIns.filter(\.automatic).count == 20, "exactly twenty conservative default Automatic rules")
    for rule in settings.rules {
        expect(match(rule.explicitSequence)?.replacement == rule.replacement, "explicit grammar round-trips catalog input " + rule.input)
    }
    for escaped in [#"\|sqrt|"#, #"\|sqrt|"#, "identifier|sqrt|", "https://example.com/|sqrt|", "/tmp/|sqrt|", "https://x/(|sqrt|", "/tmp/\"|sqrt|"] {
        expect(match(escaped) == nil, "literal/technical sequence is protected: " + escaped)
    }
    for boundary in [" ", "\t", "\n", "\r"] {
        expect(match("hello :)" + boundary, boundary)?.replacement == "🙂", "typed boundary converts and excludes boundary from replacement")
    }
    for token in ["x:)", "https://x/:)", "foo_sqrt", "abc->", "longer-->"] {
        expect(match(token + " ", " ") == nil, "Automatic requires an entire token")
    }
    for input in ["->", "-->", "<->", "<=>", "--", "---"] { settings.automaticOverrides[input] = true }
    for input in ["->", "-->", "<->", "<=>", "--", "---"] {
        let found = match("hi " + input + " ", " ")
        expect(found?.replacement == settings.rules.first(where: { $0.input == input })?.replacement, "longest whole token wins for " + input)
        expect(found?.range == NSRange(location: 3, length: input.utf16.count), "only exact local trigger range changes")
    }
    let unicode = SubstitutionRule(input: "👩🏽‍💻é", replacement: "👨‍👩‍👧‍👦 é and text\nsecond line", automatic: true)
    settings.custom = [unicode]
    expect(match("😀 " + unicode.explicitSequence)?.range.location == 3, "NSRange accounts for UTF-16 prefix")
    expect(match(unicode.input + " ", " ")?.replacement == unicode.replacement, "multi-character Unicode output is preserved")
    for invalid in ["", "12345678901", "x|y", "x`y", " x", "x ", "x\ny", "x\ty", "\u{0}"] {
        expect(SmartSubstitutionSettings.validation(input: invalid, replacement: "output", otherInputs: []) != nil, "invalid input rejected verbatim")
    }
    expect(SmartSubstitutionSettings.validation(input: "sqrt", replacement: "r", otherInputs: settings.rules.map(\.input)) != nil, "built-in duplicates rejected")
    expect(SmartSubstitutionSettings.validation(input: "a", replacement: "a", otherInputs: []) != nil, "identical input/output rejected")
    expect(SmartSubstitutionSettings.validation(input: "a", replacement: "", otherInputs: []) != nil, "empty replacement rejected")
    expect(SmartSubstitutionSettings.validation(input: "a", replacement: String(repeating: "x", count: 16_385), otherInputs: []) != nil, "practical output bound enforced")
    expect(SmartSubstitutionSettings.validation(input: "( )", replacement: "☐", otherInputs: []) == nil, "interior spaces are allowed")
    expect(SmartSubstitutionSettings.validation(input: unicode.input, replacement: unicode.replacement, otherInputs: []) == nil, "input limits count grapheme clusters")

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Substitutions-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("backup")) }
    let persistence = WorkspacePersistence(url: url)
    var workspace = Workspace(notes: [Note(title: "Keep", contentMarkdown: "|sqrt|")])
    workspace.settings.smartSubstitutions = settings
    try persistence.save(workspace)
    let loaded = try persistence.load()
    expect(loaded == workspace, "catalog overrides and custom rules survive restart without rewriting content")
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var oldSettings = json["settings"] as! [String: Any]
    oldSettings.removeValue(forKey: "smartSubstitutions"); json["settings"] = oldSettings
    try JSONSerialization.data(withJSONObject: json).write(to: url)
    var migrated = try persistence.load()
    expect(!migrated.settings.smartSubstitutions.enabled && migrated.notes == workspace.notes, "legacy settings migrate to off without content loss")
    migrated.settings.smartSubstitutions = settings
    try persistence.save(migrated)
    let reloaded = try persistence.load()
    expect(reloaded == migrated, "legacy workspace saves and reloads new settings")
}

func testSubstitutionMarkdownProtectionAndPerformance() {
    let trigger = "|sqrt|"
    func allowed(_ prefix: String, _ suffix: String = "") -> Bool {
        SubstitutionMarkdownContext().allows((prefix + trigger + suffix) as NSString, range: NSRange(location: prefix.utf16.count, length: trigger.utf16.count))
    }
    for prefix in ["```\n", "```swift\n", "````swift\n```\n", "```\nunterminated\n", "   ```swift\n", "    ```\n", "> ```swift\n> ", "- ```swift\n", "1. ```swift\n", "- > ```swift\n> ", "```\n- ```\n", "```\n> ```\n", "```\n    ```\n", "```\n\t```\n", "- ```\n      ```\n", "> ```\n>     ```\n> ", "-    ```swift\n", "~~~swift\n", "`", "``", "`multiline\n"] {
        expect(!allowed(prefix), "fenced/unclosed/inline code excluded: " + prefix)
    }
    for prefix in ["", "```swift\ncode\n```\n", "````swift\n```\n````\n", "~~~\ncode\n~~~\n", "- ```\n     ```\n", "> ```\n>    ```\n", "`code` ", "``code`` ", "\\` "] {
        expect(allowed(prefix), "prose after matching closing delimiters is eligible: " + prefix)
    }
    expect(!allowed("```\n", "\n```"), "closed fence content remains protected")
    let context = SubstitutionMarkdownContext()
    var source = "```\ncode\n```\n|sqrt|"
    var range = NSRange(location: source.utf16.count - 6, length: 6)
    expect(context.allows(source as NSString, range: range), "prime cached fence state")
    source = source.replacingOccurrences(of: "```\ncode", with: "````\ncode")
    context.invalidate(from: 0); range.location = source.utf16.count - 6
    expect(!context.allows(source as NSString, range: range), "editing opening fence invalidates later context")
    source = "plain\ncode\nplain\n|sqrt|"; context.invalidate(from: 0); range.location = source.utf16.count - 6
    expect(context.allows(source as NSString, range: range), "deleting fences restores prose matching")

    var settings = SmartSubstitutionSettings(); settings.enabled = true
    settings.custom = (0..<300).map { SubstitutionRule(input: "rule\($0)", replacement: "output", automatic: true) }
    let matcher = SmartSubstitutionMatcher(settings: settings)
    let large = (String(repeating: "A large line of ordinary prose.\n", count: 40_000) + "rule299 ") as NSString
    let cached = SubstitutionMarkdownContext()
    let triggerRange = NSRange(location: large.length - 8, length: 7)
    let coldStart = Date()
    expect(cached.allows(large, range: triggerRange), "large-note context lookup")
    let cold = Date().timeIntervalSince(coldStart)
    let start = Date()
    for _ in 0..<1_000 {
        expect(matcher.match(in: large, caret: large.length, typed: " ")?.replacement == "output", "300-rule local lookup")
        expect(cached.allows(large, range: triggerRange), "cached large-note lookup")
    }
    let elapsed = Date().timeIntervalSince(start)
    print("Smart substitutions: \(large.length) UTF-16 units, 361 rules; cold context \(cold)s, 1,000 cached trigger checks \(elapsed)s")
    expect(elapsed < 5, "cached matching remains responsive on a large note")
}
