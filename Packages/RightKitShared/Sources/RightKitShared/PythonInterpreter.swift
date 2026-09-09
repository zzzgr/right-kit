import Foundation

/// Reuse the dedicated environment across actions while keeping an action's
/// explicit interpreter or virtual environment in control.
enum PythonInterpreter {
    static func resolve(
        preferredPath: String,
        environment: [String: String],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> String {
        if !preferredPath.isEmpty {
            guard isExecutable(preferredPath) else {
                throw CustomActionError.message(Strings.Custom.missingInterpreter)
            }
            return preferredPath
        }

        var candidates: [String] = []
        if let virtualEnvironment = environment["VIRTUAL_ENV"], virtualEnvironment.hasPrefix("/") {
            candidates.append(virtualEnvironment + "/bin/python3")
            candidates.append(virtualEnvironment + "/bin/python")
        }
        let dedicatedEnvironment = homeDirectory.appendingPathComponent(".venvs/rightkit", isDirectory: true)
        candidates.append(dedicatedEnvironment.appendingPathComponent("bin/python").path)
        candidates.append(dedicatedEnvironment.appendingPathComponent("bin/python3").path)
        for path in (environment["PATH"] ?? "").split(separator: ":") where path.hasPrefix("/") {
            candidates.append(String(path) + "/python3")
        }
        candidates += [
            "/Library/Developer/CommandLineTools/usr/bin/python3",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"
        ]

        // /usr/bin/python3 can be a CLT installer stub. Resolve links only for
        // this check: returning the venv path is essential to Python's discovery
        // of pyvenv.cfg and the packages installed in that environment.
        if let found = candidates.first(where: {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path != "/usr/bin/python3" && isExecutable($0)
        }) {
            return found
        }
        throw CustomActionError.message(Strings.Custom.missingPython)
    }

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path) && !PathUtilities.isDirectory(URL(fileURLWithPath: path))
    }
}
