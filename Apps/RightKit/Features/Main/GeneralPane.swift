import RightKitShared
import SwiftUI

/// Extension health, launch behaviour and appearance.
///
/// The extension card is the important one: it is the only permission the app
/// ever needs, and it shows a verified state ("has served a menu"), not just the
/// system toggle — see ``SetupStatus``.
struct GeneralPane: View {
    @EnvironmentObject private var status: SetupStatus
    @EnvironmentObject private var model: SettingsModel
    @ObservedObject private var appearance = AppAppearance.shared

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: Strings.sectionGeneral)
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 8)
            Form {
                extensionSection
                launchSection
                appearanceSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refresh() }
    }

    // MARK: - Extension

    private var extensionSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 26))
                    .foregroundStyle(statusTint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle).font(.headline)
                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !status.extensionEnabled {
                    Button(Strings.openExtensionSettings) { status.openExtensionSettings() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(Strings.openExtensionSettings) { status.openExtensionSettings() }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            LabeledContent {
                Button(Strings.reopenSetup) {
                    // Clear the recorded proof so the checklist re-verifies this build
                    // rather than showing a ✓ earned by an earlier copy.
                    status.resetVerification()
                    AppWindows.setup.show()
                }
            } label: {
                Text(Strings.setupRowTitle)
            }
        } header: {
            Text(Strings.extensionRowTitle)
        }
    }

    private var statusSymbol: String {
        if status.isVerified && status.extensionEnabled { return "checkmark.seal.fill" }
        if status.extensionEnabled { return "checkmark.circle" }
        return "exclamationmark.triangle.fill"
    }

    private var statusTint: Color {
        if status.isVerified && status.extensionEnabled { return .green }
        if status.extensionEnabled { return .secondary }
        return .orange
    }

    private var statusTitle: String {
        if status.isVerified && status.extensionEnabled { return Strings.statusWorking }
        if status.extensionEnabled { return Strings.statusEnabled }
        return Strings.statusDisabled
    }

    private var statusDetail: String {
        if status.isVerified && status.extensionEnabled { return Strings.extensionWorkingDetail }
        if status.extensionEnabled { return Strings.extensionEnabledDetail }
        return Strings.extensionDisabledDetail
    }

    // MARK: - Launch at login

    /// The toggle mirrors System Settings → Login Items. When macOS has accepted the
    /// registration but the user (or a policy) switched it off there, the toggle reads
    /// off and a one-line hint with a button to the right pane appears beneath it.
    private var launchSection: some View {
        Section {
            Toggle(Strings.launchAtLoginTitle, isOn: $model.launchAtLogin)
                .toggleStyle(.switch)
            if let message = model.loginItemError {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if model.loginItemState == .requiresApproval {
                HStack(spacing: 8) {
                    Text(Strings.launchAtLoginNeedsApproval)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(Strings.openLoginItems) { LoginItem.openSystemSettings() }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker(Strings.appearance, selection: $appearance.mode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance")
        }
    }
}
