import RightKitShared
import SwiftUI

/// Every import entry point shares the same visible loading, failure and preview flow.
struct ActionImportSheet: View {
    @EnvironmentObject private var model: CustomActionsModel
    let requestID: UUID

    var body: some View {
        Group {
            if let request = model.importRequest, request.id == requestID {
                switch request.state {
                case .ready(let preview):
                    ActionImportPreview(preview: preview)
                case .loading:
                    status(error: nil)
                case .failed(let message):
                    status(error: message)
                }
            }
        }
        .accessibilityIdentifier("action.import-sheet")
    }

    private func status(error: String?) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if let error {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32)).foregroundStyle(.orange)
                Text(Strings.Custom.importFailed).font(.title3.weight(.semibold))
                Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().controlSize(.regular)
                Text(Strings.Custom.downloading).font(.headline)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(Strings.Custom.cancel, role: .cancel, action: model.cancelImport)
                    .keyboardShortcut(.cancelAction)
                if error != nil && model.canRetryImport {
                    Button(Strings.Custom.retry, action: model.retryImport)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.small)
        .padding(24)
        .frame(width: 500, height: 280)
    }
}
