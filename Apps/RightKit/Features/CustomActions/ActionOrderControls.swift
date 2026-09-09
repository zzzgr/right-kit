import RightKitShared
import SwiftUI

struct ActionOrderControls: View {
    let selectedIndex: Int?
    let totalCount: Int
    let enabled: Bool
    let onMove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(Strings.Custom.menuOrder)
                Spacer()
                if let selectedIndex {
                    Text("\(selectedIndex + 1) / \(totalCount)").monospacedDigit()
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Button { onMove(-1) } label: {
                    Label(Strings.Custom.moveUp, systemImage: "chevron.up")
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .help(Strings.Custom.moveUp)
                .accessibilityIdentifier("actions.move-up")
                .disabled((selectedIndex ?? 0) <= 0 || !enabled)
                Divider().frame(height: 16)
                Button { onMove(1) } label: {
                    Label(Strings.Custom.moveDown, systemImage: "chevron.down")
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .help(Strings.Custom.moveDown)
                .accessibilityIdentifier("actions.move-down")
                .disabled(selectedIndex == nil || selectedIndex == totalCount - 1 || !enabled)
            }
            .buttonStyle(ActionOrderButtonStyle())
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        }
    }
}

private struct ActionOrderButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 30)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
            .background(Color.primary.opacity(isEnabled && (hovering || configuration.isPressed) ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(isFocused ? 0.8 : 0)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
