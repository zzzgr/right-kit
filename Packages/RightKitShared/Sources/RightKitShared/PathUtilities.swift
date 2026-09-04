import Foundation

public enum PathUtilities {
    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
    }

    /// Next free name in `directory`: `未命名.txt`, `未命名 2.txt`, `未命名 3.txt`…
    /// (Finder's own numbering style.)
    public static func uniqueURL(in directory: URL, baseName: String, isDirectory: Bool) -> URL {
        let name = baseName as NSString
        let ext = isDirectory ? "" : name.pathExtension
        let stem = ext.isEmpty ? baseName : name.deletingPathExtension

        func candidate(_ index: Int) -> URL {
            let fileName: String
            if index == 1 {
                fileName = baseName
            } else if ext.isEmpty {
                fileName = "\(stem) \(index)"
            } else {
                fileName = "\(stem) \(index).\(ext)"
            }
            return directory.appendingPathComponent(fileName, isDirectory: isDirectory)
        }

        // Bounded: a directory with 1000 "未命名" siblings gets a timestamp instead
        // of a hang.
        for index in 1...1000 {
            let url = candidate(index)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let fileName = ext.isEmpty ? "\(stem) \(stamp)" : "\(stem) \(stamp).\(ext)"
        return directory.appendingPathComponent(fileName, isDirectory: isDirectory)
    }
}
