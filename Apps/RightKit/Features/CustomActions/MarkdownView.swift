import RightKitShared
import SwiftUI

struct MarkdownView: View {
    private let document: MarkdownDocument

    init(_ source: String) {
        document = MarkdownDocument(source)
    }

    var body: some View {
        MarkdownBlocks(blocks: document.blocks)
            .font(.system(size: 13))
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlocks: View {
    let blocks: [MarkdownDocument.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownDocument.Block

    @ViewBuilder var body: some View {
        switch block.kind {
        case .header(let level):
            MarkdownText(value: block.text)
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case .paragraph, .tableCell:
            MarkdownText(value: block.text)
        case .orderedList:
            MarkdownList(items: block.children, ordered: true)
        case .unorderedList:
            MarkdownList(items: block.children, ordered: false)
        case .blockQuote:
            MarkdownBlocks(blocks: block.children)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.2)).frame(width: 2)
                }
        case .codeBlock(let language):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                ScrollView(.horizontal) {
                    Text(verbatim: block.plainText.hasSuffix("\n") ? String(block.plainText.dropLast()) : block.plainText)
                        .font(.system(size: 12, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
        case .thematicBreak:
            Divider().padding(.vertical, 2)
        case .table(let columns):
            MarkdownTable(rows: block.children, columns: columns)
        case .listItem, .tableHeaderRow, .tableRow:
            MarkdownBlocks(blocks: block.children)
        @unknown default:
            MarkdownText(value: block.text)
            MarkdownBlocks(blocks: block.children)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 18
        case 3: return 16
        case 4: return 14
        default: return 13
        }
    }
}

private struct MarkdownText: View {
    let value: AttributedString
    var alignment: Alignment = .leading

    private var styled: AttributedString {
        var result = value
        for run in value.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                var font = Font.system(size: 12, design: .monospaced)
                if intent.contains(.stronglyEmphasized) { font = font.bold() }
                if intent.contains(.emphasized) { font = font.italic() }
                result[run.range].font = font
                result[run.range].backgroundColor = Color.primary.opacity(0.07)
            }
            if run.link != nil { result[run.range].underlineStyle = .single }
        }
        return result
    }

    var body: some View {
        Text(styled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private struct MarkdownList: View {
    let items: [MarkdownDocument.Block]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Group {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .accessibilityLabel(checked ? Strings.Custom.markdownTaskDone : Strings.Custom.markdownTaskPending)
                        } else if ordered, case .listItem(let ordinal) = item.kind {
                            Text("\(ordinal).").monospacedDigit()
                        } else {
                            Text("•")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16, alignment: .trailing)
                    .textSelection(.disabled)
                    MarkdownBlocks(blocks: item.children)
                }
            }
        }
    }
}

private struct MarkdownTable: View {
    let rows: [MarkdownDocument.Block]
    let columns: [PresentationIntent.TableColumn]
    @State private var availableWidth: CGFloat = 0

    private var columnWidth: CGFloat {
        max(130, availableWidth / CGFloat(max(columns.count, 1)))
    }

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    let header = row.kind == .tableHeaderRow
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(columns.indices, id: \.self) { index in
                            let value = row.children.first { $0.kind == .tableCell(columnIndex: index) }?.text ?? AttributedString()
                            MarkdownText(value: value, alignment: alignment(columns[index]))
                                .font(.system(size: 13, weight: header ? .semibold : .regular))
                                .multilineTextAlignment(textAlignment(columns[index]))
                                .frame(width: columnWidth - 20, alignment: alignment(columns[index]))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color.primary.opacity(header ? 0.05 : 0))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { availableWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { availableWidth = $0 }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func alignment(_ column: PresentationIntent.TableColumn) -> Alignment {
        switch column.alignment {
        case .center: return .top
        case .right: return .topTrailing
        default: return .topLeading
        }
    }

    private func textAlignment(_ column: PresentationIntent.TableColumn) -> TextAlignment {
        switch column.alignment {
        case .center: return .center
        case .right: return .trailing
        default: return .leading
        }
    }
}
