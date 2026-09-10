import AppKit
import RightKitShared
import SwiftUI

/// The market: a searchable grid of cards, one sheet per action.
struct MarketPane: View {
    @EnvironmentObject private var model: CustomActionsModel
    @ObservedObject private var market = MarketService.shared
    @State private var query = ""
    @State private var language = "all"
    @State private var updatesOnly = false
    @State private var showingSettings = false
    @State private var page = 1
    @State private var pageSize = MarketQuery.defaultPageSize

    private var items: [MarketEntry] { market.items() }
    private var hasFilters: Bool { !query.isEmpty || language != "all" || updatesOnly }
    private var title: String {
        if let name = market.source?.name, !name.isEmpty { return name }
        return Strings.Custom.market
    }
    private var request: BrowseRequest {
        BrowseRequest(sourceURL: market.source?.url,
                      query: MarketQuery(page: page, pageSize: pageSize, search: query, language: language),
                      installed: updatesOnly ? model.actions.compactMap(MarketInstalledAction.tracked) : nil)
    }

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            if market.source != nil && !items.isEmpty {
                Divider()
                paginationControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingSettings) { MarketSettingsSheet() }
        .onChange(of: query) { _ in page = 1 }
        .onChange(of: language) { _ in page = 1 }
        .onChange(of: updatesOnly) { _ in page = 1 }
        .onChange(of: pageSize) { _ in page = 1 }
        .onChange(of: market.source?.url) { _ in page = 1 }
        .task(id: request) {
            let request = request
            do {
                if !request.query.search.isEmpty { try await Task.sleep(nanoseconds: 250_000_000) }
                try Task.checkCancellation()
                await market.browse(request.query, installed: request.installed)
            } catch { }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                PageHeader(title: title)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if market.isRefreshing { ProgressView().controlSize(.small) }
                    Button { Task { await market.browse(request.query, installed: request.installed) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(Strings.Custom.refreshMarket)
                    .accessibilityLabel(Strings.Custom.refreshMarket)
                    .disabled(market.isRefreshing || market.source == nil)
                    .accessibilityIdentifier("market.refresh")
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help(Strings.Custom.marketSettings)
                    .accessibilityLabel(Strings.Custom.marketSettings)
                    .accessibilityIdentifier("market.settings")
                }
                .padding(.top, 2)
            }
            HStack(spacing: 10) {
                SearchField(placeholder: Strings.Custom.marketSearch, text: $query, clearLabel: Strings.Custom.clearSearch)
                    .frame(maxWidth: 360)
                    .accessibilityIdentifier("market.search")
                Picker(Strings.Custom.allLanguages, selection: $language) {
                    Text(Strings.Custom.allLanguages).tag("all")
                    Text("Python").tag("python")
                    Text("zsh").tag("zsh")
                    Text("bash").tag("bash")
                    Text("sh").tag("sh")
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                Toggle(Strings.Custom.updatesOnly, isOn: $updatesOnly).toggleStyle(.checkbox)
                Spacer()
                if market.source != nil {
                    Text(Strings.Custom.marketActionCount(market.pagination.total))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if let error = market.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled)
            } else if market.source?.lastError != nil {
                Label(Strings.Custom.marketOffline, systemImage: "wifi.exclamationmark")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            if market.isRefreshing {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if market.source == nil {
                EmptyStateView(symbol: "storefront", title: Strings.Custom.marketEmptyTitle,
                               detail: Strings.Custom.marketEmpty, tint: .accentColor) {
                    Button(Strings.Custom.marketSettings) { showingSettings = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                EmptyStateView(symbol: "magnifyingglass", title: Strings.Custom.marketNoResultsTitle,
                               detail: Strings.Custom.noMarketResults) {
                    if hasFilters {
                        Button(Strings.Custom.clearFilters) {
                            query = ""; language = "all"; updatesOnly = false
                        }
                    }
                }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(items) { entry in
                        MarketCard(entry: entry, installed: model.installedAction(for: entry)?.packageMetadata) {
                            model.previewMarketEntry(entry)
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var paginationControls: some View {
        HStack(spacing: 8) {
            Picker(Strings.Custom.pageSize, selection: $pageSize) {
                ForEach(MarketQuery.pageSizes, id: \.self) { size in Text(Strings.Custom.perPage(size)).tag(size) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
            .accessibilityIdentifier("market.pageSize")
            Spacer()
            Button { page = market.pagination.page - 1 } label: {
                Image(systemName: "chevron.left").frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(Strings.Custom.previousPage).accessibilityLabel(Strings.Custom.previousPage)
            .accessibilityIdentifier("market.previousPage")
            .disabled(market.isRefreshing || market.pagination.page <= 1)
            Text(Strings.Custom.pagePosition(market.pagination.page, market.pagination.totalPages))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button { page = market.pagination.page + 1 } label: {
                Image(systemName: "chevron.right").frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(Strings.Custom.nextPage).accessibilityLabel(Strings.Custom.nextPage)
            .accessibilityIdentifier("market.nextPage")
            .disabled(market.isRefreshing || market.pagination.page >= market.pagination.totalPages)
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
    }

    private struct BrowseRequest: Equatable {
        let sourceURL: URL?
        let query: MarketQuery
        let installed: [MarketInstalledAction]?
    }
}

// MARK: - Card

private struct MarketCard: View {
    let entry: MarketEntry
    let installed: CustomAction.PackageMetadata?
    let open: () -> Void

    private var item: MarketCatalog.Item { entry.item }
    private var isNewer: Bool { installed.map { MarketProtocol.isNewer(item.version, than: $0.version) } ?? false }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    MarketItemIcon(entry: entry)
                    Spacer()
                    if installed != nil {
                        StatusPill(text: isNewer ? Strings.Custom.updateAvailable : Strings.Custom.installed,
                                   symbol: isNewer ? "arrow.up.circle.fill" : "checkmark.circle.fill",
                                   tint: isNewer ? .accentColor : .green)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(item.summary).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(item.language.title.replacingOccurrences(of: "Shell · ", with: ""))
                    Text("·").foregroundStyle(.tertiary)
                    Text("v\(item.version)").monospacedDigit()
                    if !item.tags.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        Text(item.tags.prefix(2).joined(separator: " · ")).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 12)
        .accessibilityLabel(item.title)
        .accessibilityHint(Strings.Custom.viewDetails)
        .accessibilityIdentifier("market.action.\(entry.id)")
    }
}

private struct MarketItemIcon: View {
    let entry: MarketEntry
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().renderingMode(.template).scaledToFit().foregroundStyle(.primary) }
            else {
                Image(systemName: NSImage(systemSymbolName: entry.item.symbol, accessibilityDescription: nil) == nil ? "terminal" : entry.item.symbol)
                    .resizable().scaledToFit()
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 22, height: 22)
        .frame(width: 40, height: 40)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .task(id: entry.item.iconSHA256) {
            image = nil
            if let data = try? await MarketService.shared.client.icon(entry.item, origin: entry.source.url), !Task.isCancelled {
                image = NSImage(data: data)
            }
        }
    }
}
