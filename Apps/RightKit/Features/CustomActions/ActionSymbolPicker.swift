import AppKit
import RightKitShared
import SwiftUI

struct ActionSymbolPicker: View {
    @Binding var icon: CustomActionIcon
    @State private var isPresented = false
    @State private var category = Category.all
    @State private var search = ""

    private var symbols: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = category.symbols
        return candidates.filter { name in
            NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil &&
            (query.isEmpty || name.localizedCaseInsensitiveContains(query) || Strings.Custom.iconName(name).localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        Button(Strings.Custom.iconLibrary) { isPresented = true }
            .accessibilityIdentifier("actions.iconLibrary")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField(Strings.Custom.searchIcons, text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("actions.iconSearch")
                    Picker(Strings.Custom.iconCategory, selection: $category) {
                        ForEach(Category.allCases) { category in Text(category.title).tag(category) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(symbols, id: \.self) { name in
                                Button {
                                    icon = .symbol(name)
                                    isPresented = false
                                } label: {
                                    Image(systemName: name)
                                        .font(.system(size: 20))
                                        .frame(width: 40, height: 40)
                                        .background(icon == .symbol(name) ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(icon == .symbol(name) ? Color.accentColor : .clear))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(Strings.Custom.iconName(name))
                                .accessibilityLabel(Strings.Custom.iconName(name))
                                .accessibilityIdentifier("actions.icon.\(name)")
                            }
                        }
                        if symbols.isEmpty { Text(Strings.Custom.noIcons).foregroundStyle(.secondary).padding(.top, 20) }
                    }
                }
                .padding(16).frame(width: 450, height: 240)
            }
    }

    private enum Category: String, CaseIterable, Identifiable {
        case all, files, images, office, development, network, utilities
        var id: Self { self }
        var title: String { Strings.Custom.iconCategoryName(rawValue) }
        var symbols: [String] {
            switch self {
            case .all: return Self.allCases.filter { $0 != .all }.flatMap(\.symbols)
            case .files: return ["folder", "folder.badge.plus", "doc", "doc.badge.plus", "doc.on.doc", "doc.zipper", "archivebox", "tray.full", "tag", "pencil", "line.3.horizontal.decrease.circle", "list.bullet"]
            case .images: return ["photo", "photo.on.rectangle", "crop", "scissors", "arrow.up.left.and.arrow.down.right", "arrow.down.right.and.arrow.up.left", "rectangle.split.2x2", "rectangle.split.1x2", "rotate.right", "paintbrush", "drop", "wand.and.stars"]
            case .office: return ["doc.richtext", "doc.text", "text.viewfinder", "textformat", "tablecells", "chart.bar", "list.bullet.clipboard", "calendar", "envelope", "printer"]
            case .development: return ["terminal", "curlybraces", "chevron.left.forwardslash.chevron.right", "hammer", "wrench.and.screwdriver", "gearshape", "ant", "shippingbox", "externaldrive", "flowchart"]
            case .network: return ["globe", "link", "cloud", "icloud.and.arrow.up", "icloud.and.arrow.down", "arrow.up.doc", "arrow.down.doc", "arrow.triangle.2.circlepath", "network", "server.rack"]
            case .utilities: return ["magnifyingglass", "bolt", "play.circle", "checkmark.seal", "lock.shield", "key", "trash", "clock", "square.grid.2x2", "qrcode"]
            }
        }
    }
}
