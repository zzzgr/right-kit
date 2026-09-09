import AppKit
import RightKitShared
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return Strings.appearanceSystem
        case .light: return Strings.appearanceLight
        case .dark: return Strings.appearanceDark
        }
    }
}

@MainActor
final class AppAppearance: ObservableObject {
    static let shared = AppAppearance()
    private static let key = "appearanceMode"

    @Published var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.key)
            apply()
        }
    }

    private init() {
        mode = UserDefaults.standard.string(forKey: Self.key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        apply()
    }

    private func apply() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
