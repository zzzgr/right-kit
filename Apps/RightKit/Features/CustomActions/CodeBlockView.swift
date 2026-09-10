import AppKit
import RightKitShared
import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let language, !language.isEmpty {
                    Text(language).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                CopyCodeButton(code: code)
            }
            ScrollView(.horizontal) {
                Text(ScriptHighlighter.attributed(code, language: .init(language)))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
    }
}

struct CopyCodeButton: View {
    let code: String
    @State private var copyID: UUID?

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copyID = UUID()
        } label: {
            Label(copyID == nil ? Strings.Custom.copyCode : Strings.Custom.codeCopied,
                  systemImage: copyID == nil ? "doc.on.doc" : "checkmark")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .task(id: copyID) {
            guard copyID != nil else { return }
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                copyID = nil
            } catch { }
        }
    }
}
