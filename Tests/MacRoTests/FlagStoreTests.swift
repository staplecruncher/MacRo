import Foundation
import XCTest
@testable import MacRo

final class FlagStoreTests: XCTestCase {
    func testLoadReturnsDefaultRowsForMissingStoreFile() throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root)

        let rows = try store.loadRows(for: .roblox)
        XCTAssertEqual(rows.map(\.name), ["DFFlagDisableDPIScale"])
        XCTAssertEqual(rows.map(\.rawValue), ["true"])
        XCTAssertEqual(rows.map(\.isEnabled), [true])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("roblox-flags.json").path))
    }

    func testSaveAndLoadRowsPerTarget() throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root)
        let robloxRows = [
            FlagRow(name: "FFlagRoblox", rawValue: "true", isEnabled: true)
        ]
        let studioRows = [
            FlagRow(name: "FFlagStudio", rawValue: "\"abc\"", isEnabled: false)
        ]

        try store.saveRows(robloxRows, for: .roblox)
        try store.saveRows(studioRows, for: .studio)

        XCTAssertEqual(try store.loadRows(for: .roblox), robloxRows)
        XCTAssertEqual(try store.loadRows(for: .studio), studioRows)
    }

    func testApplicationSupportDefaultContainsBundleIdentifier() {
        let url = FlagStore.defaultRootDirectory()
        XCTAssertTrue(url.path.contains(AppConstants.bundleIdentifier))
    }
}
