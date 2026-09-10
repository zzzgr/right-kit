import RightKitShared
import SwiftUI

/// Version, principles, supported apps and links.
struct AboutPane: View {
    @EnvironmentObject private var status: SetupStatus

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                links
                supportedApps
            }
            .padding(.horizontal, 28).padding(.vertical, 40)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            Text(Strings.appName).font(.system(size: 26, weight: .bold))
            Text(Strings.tagline).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("\(Strings.versionTitle) \(version)")
                Text("\(Strings.authorTitle) 乌鸡哥")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var links: some View {
        SurfaceCard(padding: 6) {
            VStack(spacing: 0) {
                linkRow(Strings.releasesLink, symbol: "arrow.down.circle",
                        url: URL(string: "https://github.com/zzzgr/right-kit/releases/latest")!)
                Divider().padding(.leading, 40)
                linkRow(Strings.githubLink, symbol: "chevron.left.forwardslash.chevron.right",
                        url: URL(string: "https://github.com/zzzgr/right-kit")!)
                Divider().padding(.leading, 40)
                linkRow(Strings.guideLink, symbol: "book",
                        url: URL(string: "https://github.com/zzzgr/right-kit/blob/main/Docs/CustomActions.md")!)
                Divider().padding(.leading, 40)
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard").frame(width: 20).foregroundStyle(.secondary)
                    Text(Strings.setupRowTitle)
                    Spacer()
                    Button(Strings.reopenSetup) {
                        status.resetVerification()
                        AppWindows.setup.show()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
    }

    private func linkRow(_ title: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 6)
    }

    private var supportedApps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.supportedApps).font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            SurfaceCard {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        Text(Strings.terminalKind).foregroundStyle(.secondary)
                        Text(TerminalApp.autoOrder.map(\.displayName).joined(separator: " · "))
                    }
                    GridRow {
                        Text(Strings.editorKind).foregroundStyle(.secondary)
                        Text(EditorApp.autoOrder.map(\.displayName).joined(separator: " · "))
                    }
                }
                .font(.callout)
            }
        }
    }
}
