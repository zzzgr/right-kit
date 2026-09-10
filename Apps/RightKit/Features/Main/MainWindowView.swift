import RightKitShared
import SwiftUI

/// The main window: a System-Settings-style sidebar on the left, one section on
/// the right. Every section is its own view; this file only wires them together.
struct MainWindowView: View {
    /// Chosen so every section fits without clipping when the sidebar is at its
    /// widest: 240 (sidebar) + 800 (My Actions list 240 + editor 560).
    static let minimumSize = NSSize(width: 1040, height: 700)

    @ObservedObject private var navigation = AppNavigation.shared
    @EnvironmentObject private var status: SetupStatus
    @EnvironmentObject private var actions: CustomActionsModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        // One sheet for every import entry point (market card, rightkit:// link),
        // attached here so switching sections never tears it down mid-flow.
        .sheet(item: $actions.importRequest, onDismiss: {
            if actions.importRequest == nil { actions.cancelImport() }
        }) { request in
            ActionImportSheet(requestID: request.id)
        }
        .onAppear { status.addWatcher() }
        .onDisappear { status.removeWatcher() }
    }

    // MARK: - Sidebar

    /// The brand block sits *outside* the list on purpose: a sidebar `Section`
    /// header becomes a collapsible outline group on macOS and can swallow the rows.
    private var sidebar: some View {
        VStack(spacing: 0) {
            brand
            List(selection: Binding(
                get: { navigation.section },
                set: { if let section = $0 { navigation.section = section } }
            )) {
                ForEach(AppSection.primary) { section in
                    row(section)
                }
                Section {
                    row(.about)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("main.sidebar")
            if actions.activeCount > 0 {
                runningTasks
            }
        }
    }

    private func row(_ section: AppSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.symbolName)
        }
        .tag(section)
        .accessibilityIdentifier("main.section.\(section.rawValue)")
    }

    /// App icon, name and a one-line health summary — the sidebar doubles as the
    /// status indicator so the user never has to hunt for "is it working?".
    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.appName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                healthLine
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var healthLine: some View {
        if status.extensionEnabled {
            Label(status.isVerified ? Strings.statusWorking : Strings.statusEnabled,
                  systemImage: status.isVerified ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(status.isVerified ? Color.green : Color.secondary)
        } else {
            Label(Strings.statusDisabled, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var runningTasks: some View {
        Button {
            actions.showRuns()
        } label: {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Strings.Custom.activeTasks(actions.activeCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch navigation.section {
        case .general: GeneralPane()
        case .menu: MenuPane()
        case .actions: CustomActionsView()
        case .market: MarketPane()
        case .about: AboutPane()
        }
    }
}
