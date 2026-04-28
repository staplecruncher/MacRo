import Foundation

final class ManagedAppVersionStore {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL = FlagStore.defaultRootDirectory(), fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func loadVersionUpload(for target: TargetKind) throws -> String? {
        let url = fileURL(for: target)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveVersionUpload(_ versionUpload: String, for target: TargetKind) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try versionUpload.write(to: fileURL(for: target), atomically: true, encoding: .utf8)
    }

    func removeVersionUpload(for target: TargetKind) throws {
        let url = fileURL(for: target)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(for target: TargetKind) -> URL {
        rootDirectory.appendingPathComponent(target.versionStoreFileName, isDirectory: false)
    }
}
