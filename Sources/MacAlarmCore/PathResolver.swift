import Foundation

public enum PathResolver {
    public static func expandedPath(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" {
            return home
        }

        return home + String(path.dropFirst())
    }

    public static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: expandedPath(path))
    }
}
