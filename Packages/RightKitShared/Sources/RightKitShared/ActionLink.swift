import AppKit
import Foundation

/// `rightkit://run?…` — the bridge from the Finder extension to the main app.
///
/// Why a URL at all: the extension is sandboxed and can be suspended the instant a
/// menu handler returns, so anything that touches files or launches apps has to run
/// in the (non-sandboxed, long-lived) main app. The link carries the raw selection
/// so the app derives directories exactly the way the extension would have.
public enum ActionLink {
    public static let scheme = "rightkit"
    public static let host = "run"

    private enum Field {
        static let action = "action"
        static let target = "target"
        static let container = "container"
    }

    public struct Request: Sendable, Equatable {
        public let action: MenuAction
        public let context: ActionContext

        public init(action: MenuAction, context: ActionContext) {
            self.action = action
            self.context = context
        }
    }

    public static func url(for request: Request) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var items = [URLQueryItem(name: Field.action, value: request.action.rawValue)]
        items += request.context.targets.map { URLQueryItem(name: Field.target, value: $0.path) }
        if let container = request.context.container {
            items.append(URLQueryItem(name: Field.container, value: container.path))
        }
        components.queryItems = items
        return components.url
    }

    public static func request(from url: URL) -> Request? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let items = components.queryItems ?? []
        guard let raw = items.first(where: { $0.name == Field.action })?.value,
              let action = MenuAction(rawValue: raw)
        else { return nil }

        let targets = items
            .filter { $0.name == Field.target }
            .compactMap(\.value)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
        let container = items
            .first(where: { $0.name == Field.container })?.value
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }

        return Request(action: action, context: ActionContext(targets: targets, container: container))
    }

    /// Hands the request to the main app, launching it if necessary.
    ///
    /// Lives here rather than in the extension target on purpose: `NSWorkspace.open`
    /// is off-limits to code compiled with `APPLICATION_EXTENSION_API_ONLY`, and the
    /// shared framework is not.
    @discardableResult
    public static func handOff(_ request: Request) -> Bool {
        guard let url = url(for: request) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
