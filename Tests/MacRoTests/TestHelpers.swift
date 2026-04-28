import Foundation
import XCTest

extension XCTestCase {
    func temporaryDirectory(named name: String = UUID().uuidString) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacRoTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.removeItemIfExists(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
