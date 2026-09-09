import Foundation

/// Foundation parses Markdown blocks, but SwiftUI Text only lays out inline styles.
/// Retain the block hierarchy so headings, lists and tables can use native views.
struct MarkdownDocument {
    struct Block: Identifiable {
        let id: Int
        let kind: PresentationIntent.Kind
        var text: AttributedString
        let children: [Block]
        let checked: Bool?

        var plainText: String { String(text.characters) }
    }

    let blocks: [Block]

    init(_ source: String) {
        let parsed = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(source)
        var roots: [Builder] = []
        var nodes: [Int: Builder] = [:]
        var fallbackID = -1

        for run in parsed.runs {
            let inline = run.inlinePresentationIntent ?? []
            // Match the market website's plain Markdown policy, including HTML in release notes.
            if inline.contains(.inlineHTML) || inline.contains(.blockHTML) { continue }
            var text = AttributedString(parsed[run.range])
            text.presentationIntent = nil
            // Keep image alternative text without loading resources while reviewing an action.
            text.imageURL = nil
            if let link = run.link, !Self.allowsLink(link) { text.link = nil }

            var leaf: Builder?
            for component in run.presentationIntent?.components.reversed() ?? [] {
                if let existing = nodes[component.identity] {
                    leaf = existing
                } else {
                    let node = Builder(id: component.identity, kind: component.kind)
                    if let parent = leaf { parent.children.append(node) }
                    else { roots.append(node) }
                    nodes[node.id] = node
                    leaf = node
                }
            }
            if let leaf { leaf.text.append(text) }
            else {
                let node = Builder(id: fallbackID, kind: .paragraph)
                fallbackID -= 1
                node.text = text
                roots.append(node)
            }
        }
        blocks = roots.map { $0.block() }
    }

    static func allowsLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["https", "http", "mailto"].contains(scheme)
    }

    private final class Builder {
        let id: Int
        let kind: PresentationIntent.Kind
        var text = AttributedString()
        var children: [Builder] = []

        init(id: Int, kind: PresentationIntent.Kind) {
            self.id = id
            self.kind = kind
        }

        func block() -> Block {
            var children = children.map { $0.block() }
            var checked: Bool?
            if case .listItem = kind, children.first?.kind == .paragraph {
                let prefix = String(children[0].text.characters.prefix(4))
                if prefix == "[ ] " || prefix.lowercased() == "[x] " {
                    checked = prefix != "[ ] "
                    let end = children[0].text.characters.index(children[0].text.startIndex, offsetBy: 4)
                    children[0].text.removeSubrange(children[0].text.startIndex..<end)
                }
            }
            return Block(id: id, kind: kind, text: text, children: children, checked: checked)
        }
    }
}
