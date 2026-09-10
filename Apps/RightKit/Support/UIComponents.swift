import AppKit
import RightKitShared
import SwiftUI

/// Title + one-line description at the top of every main-window section.
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A rounded, bordered surface for content that does not fit a `Form` row —
/// previews, empty states, status summaries.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Centered illustration + copy + optional actions for an empty or failed pane.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var tint: Color = .secondary
    @ViewBuilder var actions: () -> Actions

    init(symbol: String, title: String, detail: String? = nil, tint: Color = .secondary,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.tint = tint
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(tint.opacity(0.08), in: Circle())
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                }
            }
            HStack(spacing: 10) { actions() }
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, detail: String? = nil, tint: Color = .secondary) {
        self.init(symbol: symbol, title: title, detail: detail, tint: tint) { EmptyView() }
    }
}

/// Small coloured pill: "已安装", "可更新", "已停用"…
struct StatusPill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Inline error banner with a dismiss button.
struct InlineErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Strings.Custom.dismiss)
        }
        .font(.callout)
        .padding(10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Inline notice (neutral).
struct InlineNotice: View {
    let message: String
    var symbol = "info.circle"

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A plain search field with a magnifier and a clear button.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var clearLabel: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// Hover highlight for plain-style buttons (cards, list rows).
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 10
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.05 : 0))
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 10) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}
