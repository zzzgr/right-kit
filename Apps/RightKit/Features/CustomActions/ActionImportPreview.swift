import AppKit
import RightKitShared
import SwiftUI

/// Detail sheet for an action from the market or a direct link: description,
/// source, version history, then the import decision.
struct ActionImportPreview: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: CustomActionsModel
    let preview: PackageImportPreview
    @State private var tab = 0
    @State private var preferLocal = true
    @State private var error: String?
    @State private var historyError: String?
    @State private var releases: [MarketVersions.Release] = []
    @State private var nextVersionsURL: URL?
    @State private var loadedPages = Set<URL>()
    @State private var loadingHistory = false

    private var package: ActionPackage { preview.package }
    private var installed: CustomAction.PackageMetadata? { model.installedAction(for: preview)?.packageMetadata }
    private var compatibilityError: String? {
        do { try package.checkCompatibility(); return nil }
        catch { return error.localizedDescription }
    }
    private var importTitle: String {
        guard let installed else { return Strings.Custom.importAction }
        return installed.version == package.version ? Strings.Custom.openInstalled : Strings.Custom.updateAsDraft
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
            Picker(Strings.Custom.importAction, selection: $tab) {
                Text(Strings.Custom.actionDescription).tag(0)
                Text(Strings.Custom.sourceCode).tag(1)
                Text(Strings.Custom.versionHistory).tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            .padding(.horizontal, 22).padding(.bottom, 12)
            Divider()
            Group {
                if tab == 1 {
                    source
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if tab == 0 { description }
                            else { history }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            Divider()
            footer
                .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 680, height: 640)
        .task(id: preview.id) { if let url = preview.versionsURL { await loadVersions(url) } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            packageIcon
                .frame(width: 28, height: 28)
                .frame(width: 52, height: 52)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(package.action.title).font(.title2.weight(.semibold)).lineLimit(2)
                HStack(spacing: 8) {
                    Text("v\(package.version)").monospacedDigit()
                    Text("·")
                    Text(package.publisher.name)
                    Text("·")
                    Text(package.action.language.title)
                    if let installed {
                        StatusPill(text: MarketProtocol.isNewer(package.version, than: installed.version)
                                        ? Strings.Custom.updateAvailable : Strings.Custom.installedVersion(installed.version),
                                   symbol: "checkmark.circle.fill", tint: .green)
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                Text(package.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Strings.Custom.dismiss)
        }
    }

    @ViewBuilder private var packageIcon: some View {
        if case .png(let data) = package.action.icon, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().renderingMode(.template).scaledToFit().foregroundStyle(Color.primary)
        } else if case .symbol(let name) = package.action.icon {
            Image(systemName: NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? "terminal" : name)
                .resizable().scaledToFit()
        }
    }

    // MARK: - Tabs

    private var description: some View {
        VStack(alignment: .leading, spacing: 16) {
            MarkdownView(package.description.isEmpty ? package.summary : package.description)
            if let selected = releases.first(where: { $0.version == package.version }) {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("v\(selected.version)").font(.headline)
                        MarkdownView(selected.notes)
                    }
                }
            }
            requirements
        }
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Custom.runRequirements).font(.headline)
            SurfaceCard {
                VStack(alignment: .leading, spacing: 6) {
                    if package.requirements.python == nil && package.requirements.pythonPackages.isEmpty
                        && package.requirements.commands.isEmpty {
                        Text(Strings.Custom.noRequirements).foregroundStyle(.secondary)
                    }
                    if let python = package.requirements.python { requirementRow("Python \(python)", symbol: "chevron.left.forwardslash.chevron.right") }
                    ForEach(package.requirements.pythonPackages, id: \.name) { dependency in
                        requirementRow("\(dependency.name) \(dependency.version ?? "")", symbol: "shippingbox")
                    }
                    ForEach(package.requirements.commands, id: \.self) { command in
                        requirementRow(command, symbol: "terminal")
                    }
                }
                .font(.callout)
            }
            if let prompt = package.action.workingDirectory.prompt {
                InlineNotice(message: prompt, symbol: "folder")
            }
            if !package.action.environment.isEmpty {
                Text(Strings.Custom.environment).font(.headline).padding(.top, 6)
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(package.action.environment, id: \.name) { variable in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(variable.name).font(.system(.callout, design: .monospaced))
                                    if variable.isSecret {
                                        StatusPill(text: Strings.Custom.configurationNeeded, symbol: "key.fill", tint: .orange)
                                    } else if let value = variable.value, !value.isEmpty {
                                        Text(value).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                if let hint = variable.hint {
                                    Text(hint).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func requirementRow(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
    }

    private var source: some View {
        VStack(spacing: 0) {
            HStack {
                Text(package.action.language.title).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                CopyCodeButton(code: package.action.script.content)
            }
            .padding(.horizontal, 22).padding(.vertical, 10)
            Divider()
            ScriptTextView(text: .constant(package.action.script.content), isEditable: false,
                           language: .init(package.action.language.rawValue))
                .accessibilityIdentifier("market.source")
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(releases) { release in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("v\(release.version)").font(.headline).monospacedDigit()
                        Spacer()
                        Text(Strings.day(release.createdAt)).font(.callout).foregroundStyle(.secondary)
                    }
                    MarkdownView(release.notes)
                }
                Divider()
            }
            if releases.isEmpty && !loadingHistory && historyError == nil {
                Text(Strings.Custom.noVersionHistory).foregroundStyle(.secondary)
            }
            if loadingHistory { ProgressView().controlSize(.small) }
            if let historyError {
                Text(historyError).foregroundStyle(.red)
                if let url = nextVersionsURL ?? preview.versionsURL {
                    Button(Strings.Custom.retry) { Task { await loadVersions(url) } }
                }
            } else if let nextVersionsURL {
                Button(Strings.Custom.loadMoreVersions) { Task { await loadVersions(nextVersionsURL) } }.disabled(loadingHistory)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let installed, installed.version != package.version {
                if MarketProtocol.isNewer(installed.version, than: package.version) {
                    Label(Strings.Custom.olderVersion(installed.version, package.version), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                Toggle(isOn: $preferLocal) {
                    Text(Strings.Custom.preserveLocalEdits)
                    Text(Strings.Custom.localConfigurationKept)
                }
                .toggleStyle(.checkbox)
            }
            if let message = compatibilityError ?? error {
                Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if let url = preview.detailURL {
                    Link(Strings.Custom.viewOnMarket, destination: url)
                }
                Spacer()
                if installed != nil {
                    Button(Strings.Custom.importCopy) { stage(asCopy: true) }.disabled(compatibilityError != nil)
                }
                Button(importTitle) { stage() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(compatibilityError != nil || !model.canEdit)
            }
        }
    }

    // MARK: - Data

    private func loadVersions(_ url: URL) async {
        guard !loadingHistory, let origin = preview.marketURL ?? preview.sourceURL else { return }
        loadingHistory = true
        historyError = nil
        defer { loadingHistory = false }
        do {
            guard !loadedPages.contains(url), loadedPages.count < 100 else { throw MarketCatalogError.invalid }
            let page = try await MarketService.shared.client.versions(url, packageID: package.id, origin: origin)
            try Task.checkCancellation()
            let existing = Set(releases.map(\.version))
            guard page.versions.allSatisfy({ !existing.contains($0.version) }) else { throw MarketCatalogError.invalid }
            if let release = page.versions.first(where: { $0.version == package.version }), let hash = preview.sha256, release.sha256 != hash {
                throw MarketCatalogError.hashMismatch
            }
            releases.append(contentsOf: page.versions)
            loadedPages.insert(url)
            nextVersionsURL = page.next
        } catch { if !Task.isCancelled { historyError = error.localizedDescription } }
    }

    private func stage(asCopy: Bool = false) {
        do {
            if try model.stage(package, source: preview.source, sourceURL: preview.sourceURL, marketURL: preview.marketURL,
                               sha256: preview.sha256, preferLocal: preferLocal, asCopy: asCopy) { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
