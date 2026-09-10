import Combine
import RightKitShared
import SwiftUI

/// The sections of the main window, in sidebar order.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case general, menu, actions, market, about

    var id: String { rawValue }

    /// Everything above the sidebar's divider; `about` sits below it.
    static let primary: [AppSection] = [.general, .menu, .actions, .market]

    var title: String {
        switch self {
        case .general: return Strings.sectionGeneral
        case .menu: return Strings.sectionMenu
        case .actions: return Strings.Custom.myActions
        case .market: return Strings.Custom.market
        case .about: return Strings.sectionAbout
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .menu: return "contextualmenu.and.cursorarrow"
        case .actions: return "square.stack.3d.up"
        case .market: return "storefront"
        case .about: return "info.circle"
        }
    }
}

/// Which section the main window shows. Everything that wants to land the user
/// somewhere — the menu bar, a notification click, a `rightkit://` link — goes
/// through ``show(_:)`` so there is exactly one place that opens the window.
@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    @Published var section: AppSection = .menu

    private init() {}

    func show(_ section: AppSection) {
        self.section = section
        AppWindows.main.show()
    }
}
