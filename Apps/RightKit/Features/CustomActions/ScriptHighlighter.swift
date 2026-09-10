import AppKit
import SwiftUI

/// A display-only lexer. Tokens use UTF-16 ranges for AppKit and never rewrite code.
enum ScriptHighlighter {
    enum Language: Equatable {
        case python, shell, json, plain

        init(_ identifier: String?) {
            switch identifier?.lowercased() {
            case "python", "python3", "py": self = .python
            case "sh", "bash", "zsh", "shell", "shellscript": self = .shell
            case "json", "jsonc": self = .json
            default: self = .plain
            }
        }
    }

    enum Kind: CaseIterable, Hashable {
        case comment, string, keyword, number, function, variable, property
    }

    struct Token: Equatable {
        let range: NSRange
        let kind: Kind
    }

    private struct Grammar {
        let expression: NSRegularExpression
        let kinds: [Kind]

        init(_ rules: [(Kind, String)]) {
            kinds = rules.map(\.0)
            let pattern = rules.enumerated().map { "(?<token\($0.offset)>\($0.element.1))" }.joined(separator: "|")
            // Patterns are fixed application constants, never supplied by an action.
            expression = try! NSRegularExpression(pattern: pattern)
        }
    }

    private static let python = Grammar([
        (.string, #"(?i:\b(?:r|u|b|f|br|rb|fr|rf))?(?:"""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z)|"(?:\\[\s\S]|[^"\\\r\n])*(?:"|(?=\r?\n|\z))|'(?:\\[\s\S]|[^'\\\r\n])*(?:'|(?=\r?\n|\z)))"#),
        (.comment, #"#[^\r\n]*"#),
        (.keyword, #"\b(?:False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|match|case|nonlocal|not|or|pass|raise|return|try|while|with|yield)\b"#),
        (.variable, #"@[\p{L}_][\p{L}\p{N}_.]*"#),
        (.number, #"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|[0-9][0-9_]*(?:\.[0-9_]*)?(?:[eE][+-]?[0-9_]+)?[jJ]?)\b"#),
        (.function, #"(?<![\p{L}\p{N}_])[\p{L}_][\p{L}\p{N}_]*+(?=\s*+\()"#),
    ])

    private static let shell = Grammar([
        (.string, #"(?m:<<-?[ \t]*(?<heredocQuote>['"]?)(?<heredocEnd>[A-Za-z_][A-Za-z0-9_]*)\k<heredocQuote>[^\r\n]*\r?\n[\s\S]*?(?:^[\t]*\k<heredocEnd>(?=\r?$)|\z))"#),
        (.string, #"(?:"(?:\\[\s\S]|[^"\\])*(?:"|\z)|'(?:[^'])*(?:'|\z)|\x60(?:\\[\s\S]|[^\x60\\])*(?:\x60|\z))"#),
        (.comment, #"(?<![^\s;|&()])#[^\r\n]*"#),
        (.variable, #"\$(?:\{[^}\r\n]*\}|[A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!_-])"#),
        (.keyword, #"\b(?:if|then|else|elif|fi|for|while|until|do|done|case|esac|in|function|select|time|coproc|break|continue|return|export|local|readonly|typeset|declare|unset)\b"#),
        (.function, #"\b(?:echo|printf|cd|pwd|read|exit|exec|test|command|builtin|source|set|shift|trap|true|false)\b"#),
        (.number, #"\b(?:0[xX][\da-fA-F]+|[0-9]+(?:\.[0-9]+)?)\b"#),
    ])

    private static let json = Grammar([
        (.property, #""(?:\\[\s\S]|[^"\\\r\n])*"(?=\s*:)"#),
        (.string, #""(?:\\[\s\S]|[^"\\\r\n])*(?:"|(?=\r?\n|\z))"#),
        (.comment, #"//[^\r\n]*|/\*[\s\S]*?(?:\*/|\z)"#),
        (.keyword, #"\b(?:true|false|null)\b"#),
        (.number, #"-?\b[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\b"#),
    ])

    static func tokens(in source: String, language: Language) -> [Token] {
        let grammar: Grammar
        switch language {
        case .python: grammar = python
        case .shell: grammar = shell
        case .json: grammar = json
        case .plain: return []
        }
        var tokens: [Token] = []
        grammar.expression.enumerateMatches(in: source, range: NSRange(location: 0, length: (source as NSString).length)) { match, _, _ in
            guard let match else { return }
            for index in grammar.kinds.indices {
                let range = match.range(withName: "token\(index)")
                if range.location != NSNotFound {
                    tokens.append(Token(range: range, kind: grammar.kinds[index]))
                    break
                }
            }
        }
        return tokens
    }

    /// Temporary layout attributes preserve plain-text storage, selection and undo.
    static func apply(to editor: NSTextView, language: Language) {
        guard let layout = editor.layoutManager else { return }
        let source = editor.string
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: (source as NSString).length))
        for token in tokens(in: source, language: language) {
            layout.addTemporaryAttribute(.foregroundColor, value: color(for: token.kind), forCharacterRange: token.range)
        }
    }

    static func attributed(_ source: String, language: Language) -> AttributedString {
        var result = AttributedString(source)
        for token in tokens(in: source, language: language) {
            guard let range = Range(token.range, in: source),
                  let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[start..<end].foregroundColor = Color(nsColor: color(for: token.kind))
        }
        return result
    }

    static func color(for kind: Kind) -> NSColor { palette[kind]! }

    private static let palette: [Kind: NSColor] = Dictionary(uniqueKeysWithValues: Kind.allCases.map { kind in
        (kind, NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex: UInt32
            switch kind {
            case .comment: hex = dark ? 0x8A99A6 : 0x5D6C79
            case .string: hex = dark ? 0xFC6A5D : 0xC41A16
            case .keyword: hex = dark ? 0xFC5FA3 : 0x9B2393
            case .number: hex = dark ? 0xD0BF69 : 0x1C00CF
            case .function: hex = dark ? 0x67B7A4 : 0x326D74
            case .variable: hex = dark ? 0xD0A8FF : 0x6F42C1
            case .property: hex = dark ? 0x82CFFF : 0x005CC5
            }
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    })
}
