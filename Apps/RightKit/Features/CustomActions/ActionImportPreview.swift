import AppKit
import RightKitShared
import SwiftUI

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                packageIcon.frame(width: 32, height: 32).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.action.title).font(.title3.weight(.semibold)).lineLimit(2)
                    Text("v\(package.version) · \(package.publisher.name)").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel(Strings.Custom.dismiss)
            }
            Text(package.summary).foregroundStyle(.secondary).lineLimit(3)
            Picker(Strings.Custom.importAction, selection: $tab) {
                Text(Strings.Custom.actionDescription).tag(0)
                Text(Strings.Custom.sourceCode).tag(1)
                Text(Strings.Custom.versionHistory).tag(2)
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == 0 { description }
                    else if tab == 1 {
                        Text(verbatim: package.action.script.content).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } else { history }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let installed {
                VStack(alignment: .leading, spacing: 7) {
                    if MarketProtocol.isNewer(installed.version, than: package.version) {
                        Text(Strings.Custom.olderVersion(installed.version, package.version)).foregroundStyle(.orange)
                    } else { Text(Strings.Custom.installedVersion(installed.version)).foregroundStyle(.secondary) }
                    if installed.version != package.version {
                        Toggle(Strings.Custom.preserveLocalEdits, isOn: $preferLocal).toggleStyle(.checkbox)
                        Text(Strings.Custom.localConfigurationKept).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let message = compatibilityError ?? error { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            Text(Strings.Custom.importReview).font(.caption).foregroundStyle(.secondary)
            HStack {
                if let url = preview.detailURL { Link(Strings.Custom.viewOnMarket, destination: url) }
                Spacer()
                if installed != nil { Button(Strings.Custom.importCopy) { stage(asCopy: true) }.disabled(compatibilityError != nil) }
                Button(importTitle) { stage() }.buttonStyle(.borderedProminent).disabled(compatibilityError != nil || !model.canEdit)
            }
        }.controlSize(.small).padding(20).frame(width: 620, height: 620)
            .task(id: preview.id) { if let url = preview.versionsURL { await loadVersions(url) } }
    }

    @ViewBuilder private var packageIcon: some View {
        if case .png(let data) = package.action.icon, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().renderingMode(.original).scaledToFit()
        } else if case .symbol(let name) = package.action.icon {
            Image(systemName: NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? "terminal" : name)
                .resizable().scaledToFit()
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 14) {
            MarkdownView(package.description.isEmpty ? package.summary : package.description)
            if let selected = releases.first(where: { $0.version == package.version }) {
                Divider()
                Text("v\(selected.version)").font(.headline)
                MarkdownView(selected.notes)
            }
            Divider()
            Text(Strings.Custom.runRequirements).font(.headline)
            Text(package.action.language.title).font(.callout)
            if let python = package.requirements.python { Text("Python \(python)") }
            ForEach(package.requirements.pythonPackages, id: \.name) { dependency in
                Text("\(dependency.name) \(dependency.version ?? "")")
            }
            ForEach(package.requirements.commands, id: \.self) { command in Text(command) }
            if package.requirements.python == nil && package.requirements.pythonPackages.isEmpty && package.requirements.commands.isEmpty {
                Text(Strings.Custom.noRequirements).foregroundStyle(.secondary)
            }
            if let prompt = package.action.workingDirectory.prompt { Text(prompt).foregroundStyle(.secondary) }
            ForEach(package.action.environment, id: \.name) { variable in
                VStack(alignment: .leading, spacing: 4) {
                    Text(variable.name).font(.system(.callout, design: .monospaced))
                    Text(variable.isSecret ? Strings.Custom.configurationNeeded : variable.value ?? "").foregroundStyle(.secondary)
                    if let hint = variable.hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(releases) { release in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("v\(release.version)").font(.headline)
                        Spacer()
                        Text(release.createdAt.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                    }
                    MarkdownView(release.notes)
                }
                Divider()
            }
            if releases.isEmpty && !loadingHistory && historyError == nil { Text(Strings.Custom.noVersionHistory).foregroundStyle(.secondary) }
            if loadingHistory { ProgressView() }
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
