import Foundation

struct StoredFlagRows: Codable, Equatable {
    var rows: [FlagRow]
}

final class FlagStore {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootDirectory: URL = FlagStore.defaultRootDirectory(), fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(AppConstants.bundleIdentifier, isDirectory: true)
    }

    static func defaultRows(for target: TargetKind) -> [FlagRow] {
        [
            FlagRow(name: "DFFlagDisableDPIScale", rawValue: "true", isEnabled: true)
        ]
    }

    func loadRows(for target: TargetKind) throws -> [FlagRow] {
        let url = fileURL(for: target)
        guard fileManager.fileExists(atPath: url.path) else {
            return Self.defaultRows(for: target)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(StoredFlagRows.self, from: data).rows
    }

    func saveRows(_ rows: [FlagRow], for target: TargetKind) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(StoredFlagRows(rows: rows))
        try data.write(to: fileURL(for: target), options: [.atomic])
    }

    func fileURL(for target: TargetKind) -> URL {
        rootDirectory.appendingPathComponent(target.storeFileName, isDirectory: false)
    }
}
