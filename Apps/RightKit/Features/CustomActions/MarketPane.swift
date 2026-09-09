import AppKit
import RightKitShared
import SwiftUI

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
    private var request: BrowseRequest {
        BrowseRequest(sourceURL: market.source?.url,
                      query: MarketQuery(page: page, pageSize: pageSize, search: query, language: language),
                      installed: updatesOnly ? model.actions.compactMap(MarketInstalledAction.tracked) : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(Strings.Custom.market).font(.title3.weight(.semibold))
                    Text(Strings.Custom.marketActionCount(market.pagination.total)).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if market.isRefreshing { ProgressView().controlSize(.small) }
                    Button { Task { await market.browse(request.query, installed: request.installed) } } label: {
                        Label(Strings.Custom.refreshMarket, systemImage: "arrow.clockwise")
                    }
                    .disabled(market.isRefreshing || market.source == nil)
                    .accessibilityIdentifier("market.refresh")
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help(Strings.Custom.marketSettings)
                    .accessibilityLabel(Strings.Custom.marketSettings)
                    .accessibilityIdentifier("market.settings")
                }
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(Strings.Custom.marketSearch, text: $query)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("market.search")
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .accessibilityLabel(Strings.Custom.clearSearch)
                        }
                    }
                    .padding(.horizontal, 9).frame(height: 28)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                    Picker(Strings.Custom.allLanguages, selection: $language) {
                        Text(Strings.Custom.allLanguages).tag("all")
                        Text("Python").tag("python")
                        Text("zsh").tag("zsh")
                        Text("bash").tag("bash")
                        Text("sh").tag("sh")
                    }
                    .pickerStyle(.menu).labelsHidden().frame(width: 100)
                    Toggle(Strings.Custom.updatesOnly, isOn: $updatesOnly).toggleStyle(.checkbox)
                }
                if let error = market.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                } else if market.source?.lastError != nil {
                    Label(Strings.Custom.marketOffline, systemImage: "wifi.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            Divider()
            content
            if market.source != nil {
                Divider()
                paginationControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .controlSize(.small)
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

    private var paginationControls: some View {
        HStack(spacing: 8) {
            Picker(Strings.Custom.pageSize, selection: $pageSize) {
                ForEach(MarketQuery.pageSizes, id: \.self) { size in Text(Strings.Custom.perPage(size)).tag(size) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
            .accessibilityIdentifier("market.pageSize")
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
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private struct BrowseRequest: Equatable {
        let sourceURL: URL?
        let query: MarketQuery
        let installed: [MarketInstalledAction]?
    }

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            VStack(spacing: 12) {
                if market.isRefreshing { ProgressView() }
                else {
                    Image(systemName: market.source == nil ? "globe" : "magnifyingglass")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                    Text(market.source == nil ? Strings.Custom.marketEmptyTitle : Strings.Custom.marketNoResultsTitle)
                        .font(.headline)
                    Text(market.source == nil ? Strings.Custom.marketEmpty : Strings.Custom.noMarketResults)
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                    if market.source == nil {
                        Button(Strings.Custom.marketSettings) { showingSettings = true }
                    } else if !query.isEmpty || language != "all" || updatesOnly {
                        Button(Strings.Custom.clearFilters) {
                            query = ""; language = "all"; updatesOnly = false
                        }
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            List(items) { entry in
                Button { model.previewMarketEntry(entry) } label: { row(entry) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.item.title)
                    .accessibilityIdentifier("market.action.\(entry.id)")
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ entry: MarketEntry) -> some View {
        HStack(spacing: 12) {
            MarketItemIcon(entry: entry)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.item.title).fontWeight(.medium)
                    if let installed = model.installedAction(for: entry)?.packageMetadata {
                        let newer = MarketProtocol.isNewer(entry.item.version, than: installed.version)
                        Label(newer ? Strings.Custom.updateAvailable : Strings.Custom.installed, systemImage: newer ? "arrow.up.circle" : "checkmark")
                            .font(.caption).foregroundStyle(newer ? Color.primary : .secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(entry.item.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            Text("v\(entry.item.version)").font(.caption.monospaced()).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
}

private struct MarketItemIcon: View {
    let entry: MarketEntry
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().renderingMode(.original).scaledToFit() }
            else { Image(systemName: NSImage(systemSymbolName: entry.item.symbol, accessibilityDescription: nil) == nil ? "terminal" : entry.item.symbol).resizable().scaledToFit() }
        }
        .frame(width: 24, height: 24).foregroundStyle(Color.black)
        .padding(8)
        .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 8))
        .task(id: entry.item.iconSHA256) {
            image = nil
            if let data = try? await MarketService.shared.client.icon(entry.item, origin: entry.source.url), !Task.isCancelled {
                image = NSImage(data: data)
            }
        }
    }
}
