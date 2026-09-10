import RightKitShared
import SwiftUI

/// Keep the popover open while checking several groups.
struct MarketGroupFilter: View {
    let groups: [String]
    @Binding var selection: Set<String>
    @State private var isPresented = false

    private var choices: [String] {
        Array(Set(groups).union(selection))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var title: String {
        if selection.count == 1, let group = selection.first { return name(group) }
        return selection.isEmpty ? Strings.Custom.allGroups : Strings.Custom.selectedGroupCount(selection.count)
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: 140)
            .fixedSize(horizontal: true, vertical: false)
        }
        .disabled(choices.isEmpty)
        .help(Strings.Custom.marketGroupsHelp)
        .accessibilityLabel(Strings.Custom.marketGroups)
        .accessibilityValue(selection.isEmpty ? Strings.Custom.allGroups : selection.sorted().map(name).joined(separator: ", "))
        .accessibilityIdentifier("market.groups")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Strings.Custom.marketGroups).font(.headline)
                    Spacer()
                    Button(Strings.Custom.allGroups) { selection.removeAll() }
                        .buttonStyle(.link)
                        .disabled(selection.isEmpty)
                        .accessibilityIdentifier("market.groups.clear")
                }
                Text(Strings.Custom.marketGroupsHelp).font(.caption).foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(choices, id: \.self) { group in
                            Toggle(name(group), isOn: Binding(
                                get: { selection.contains(group) },
                                set: { selected in
                                    if selected { selection.insert(group) }
                                    else { selection.remove(group) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("market.group.\(group)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: min(240, CGFloat(choices.count) * 30))
            }
            .padding(16)
            .frame(width: 260)
        }
    }

    private func name(_ group: String) -> String {
        group.isEmpty ? Strings.Custom.ungrouped : group
    }
}
