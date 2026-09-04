import RightKitShared
import SwiftUI

/// First-run checklist.
///
/// Three properties matter here, and they are what the old flow got wrong:
///
/// * **It verifies instead of assuming.** The last step goes green only when the
///   extension has really served a menu in Finder — see ``ExtensionHeartbeat``.
/// * **It shows one thing at a time.** A finished step collapses to a single ✓ line
///   and a step that does not apply (app already in /Applications) never appears.
/// * **It never traps the user.** No hard gate: detection can be wrong, and a window
///   you cannot leave because a system API misreported is worse than a warning in
///   the menu bar.
struct SetupView: View {
    @EnvironmentObject private var status: SetupStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            checklist
            footer
            HStack {
                Spacer()
                Button(status.isReady ? Strings.setupFinish : Strings.setupLater) {
                    Preferences.shared.didCompleteSetup = true
                    AppWindows.setup.close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { status.addWatcher() }
        .onDisappear { status.removeWatcher() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.appName)
                    .font(.title2.bold())
                Text(Strings.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if index > 0 {
                    Divider().padding(.leading, 40)
                }
                SetupStepRow(number: index + 1, step: step)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private var steps: [SetupStep] {
        var steps: [SetupStep] = []

        // Only shown when it is actually a problem — most installs skip straight to
        // step 1 = enable the extension.
        let location = status.location
        if !location.isFine {
            steps.append(
                SetupStep(
                    id: "location",
                    title: Strings.stepLocationTitle,
                    detail: locationDetail(location),
                    isDone: false,
                    actionTitle: Strings.stepLocationAction,
                    action: { status.revealInFinder() }
                )
            )
        }

        steps.append(
            SetupStep(
                id: "extension",
                title: Strings.stepExtensionTitle,
                detail: Strings.stepExtensionDetail,
                isDone: status.extensionEnabled,
                actionTitle: Strings.stepExtensionAction,
                action: { status.openExtensionSettings() }
            )
        )

        steps.append(
            SetupStep(
                id: "verify",
                title: status.isVerified ? Strings.stepVerifyDone : Strings.stepVerifyTitle,
                detail: Strings.stepVerifyDetail,
                isDone: status.isVerified,
                actionTitle: nil,
                action: nil
            )
        )

        return steps
    }

    private func locationDetail(_ location: SetupStatus.Location) -> String {
        switch location {
        case .diskImage: return Strings.stepLocationDetailDiskImage
        case .elsewhere(let name): return Strings.stepLocationDetail(name)
        case .applications: return ""
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status.isReady {
                Label(Strings.setupReady, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            Text(Strings.setupPrivacyHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Step

private struct SetupStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let isDone: Bool
    let actionTitle: String?
    let action: (() -> Void)?
}

private struct SetupStepRow: View {
    let number: Int
    let step: SetupStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.isDone ? "checkmark.circle.fill" : "\(number).circle")
                .font(.system(size: 15))
                .foregroundStyle(step.isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.title)
                        .font(.callout.weight(step.isDone ? .regular : .medium))
                        .foregroundStyle(step.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    Spacer(minLength: 8)
                    // A finished step keeps neither its explanation nor its button:
                    // what is left is the one thing still to do.
                    if !step.isDone, let title = step.actionTitle, let action = step.action {
                        Button(title, action: action)
                            .controlSize(.small)
                    }
                }
                if !step.isDone {
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
