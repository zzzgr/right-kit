import RightKitShared
import SwiftUI

struct MarketSettingsSheet: View {
    @ObservedObject private var market: MarketService
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL = ""
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false

    @MainActor init(market: MarketService? = nil) {
        self.market = market ?? .shared
    }

    private var hasChanges: Bool {
        let raw = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        guard let url = try? MarketProtocol.catalogURL(raw) else { return true }
        return url != market.source?.url
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Strings.Custom.marketSettings).font(.title3.weight(.semibold))
                Spacer()
                Button(Strings.Custom.close) { dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(saving)
            }
            .padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.Custom.marketLink).font(.callout.weight(.medium))
                    TextField(Strings.Custom.marketURL, text: Binding(
                        get: { sourceURL },
                        set: { sourceURL = $0; saved = false; error = nil }
                    ))
                        .textFieldStyle(.roundedBorder).controlSize(.regular)
                        .disabled(saving).onSubmit(save)
                        .accessibilityIdentifier("market.source-url")
                    Text(Strings.Custom.marketLinkHint).font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                } else if saved {
                    Label(Strings.Custom.marketSaved, systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                } else if let source = market.source {
                    Label(source.lastError ?? source.name,
                          systemImage: source.lastError == nil ? "globe" : "wifi.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 12)
                if let date = market.source?.refreshedAt {
                    Text(Strings.Custom.marketLastRefreshed(date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if market.source != nil {
                        Button(Strings.Custom.clearMarket, role: .destructive, action: remove)
                            .disabled(saving)
                            .accessibilityIdentifier("market.clear-source")
                    }
                    Spacer()
                    Button(action: save) {
                        HStack(spacing: 7) {
                            if saving { ProgressView().controlSize(.small) }
                            Text(saving ? Strings.Custom.marketVerifying : Strings.Custom.save)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || !hasChanges)
                    .accessibilityIdentifier("market.save-source")
                }
            }
            .padding(20)
        }
        .controlSize(.small)
        .frame(width: 480, height: 310)
        .interactiveDismissDisabled(saving)
        .onAppear(perform: loadAddress)
    }

    private func loadAddress() {
        guard let source = market.source else { sourceURL = ""; return }
        var components = URLComponents(url: source.url, resolvingAgainstBaseURL: false)
        if components?.path == "/.well-known/rightkit-market.json", components?.query == nil {
            components?.path = ""
        }
        sourceURL = components?.string ?? source.url.absoluteString
    }

    private func save() {
        guard !saving, hasChanges else { return }
        saving = true
        error = nil
        Task {
            do {
                try await market.saveSource(sourceURL)
                loadAddress()
                saved = true
            } catch is CancellationError {
                self.error = Strings.Custom.marketSourceMissing
            } catch { self.error = error.localizedDescription }
            saving = false
        }
    }

    private func remove() {
        guard let source = market.source else { return }
        market.removeSource(source.id)
        if market.source != nil { error = market.error }
        else {
            sourceURL = ""
            error = nil
            saved = false
        }
    }
}
