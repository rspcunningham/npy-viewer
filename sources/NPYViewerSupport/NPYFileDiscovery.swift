import Foundation

public enum NPYFileDiscovery {
    public static func npyFiles(in directoryURL: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                isNPYFile(url) && !isDirectory(url)
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    public static func isNPYFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "npy"
    }

    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
