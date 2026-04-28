import Foundation
import XCTest
@testable import MacRo

final class UpdateMonitorTests: XCTestCase {
    func testFingerprintRecordsBundleAndFlagFile() throws {
        let root = try temporaryDirectory()
        try makeFakeApp(root: root, target: .roblox, version: "1.0")
        let location = ManagedAppLocation(applicationsDirectory: root)
        let flagURL = location.clientAppSettingsURL(for: .roblox)
        try FileManager.default.createDirectory(at: flagURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"A\":true}".utf8).write(to: flagURL)
        let monitor = UpdateMonitor(location: location)

        let fingerprint = try monitor.fingerprint(for: .roblox)

        XCTAssertEqual(fingerprint.bundleVersion, "1.0")
        XCTAssertTrue(fingerprint.flagFileExists)
        XCTAssertEqual(fingerprint.flagFileHash, try FileHashing.sha256Hex(of: flagURL))
    }

    func testDetectsMissingFlagFileAsUpdateImpact() throws {
        let root = try temporaryDirectory()
        try makeFakeApp(root: root, target: .studio, version: "1.0")
        let location = ManagedAppLocation(applicationsDirectory: root)
        let flagURL = location.clientAppSettingsURL(for: .studio)
        try FileManager.default.createDirectory(at: flagURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"A\":true}".utf8).write(to: flagURL)
        let monitor = UpdateMonitor(location: location)
        let before = try monitor.fingerprint(for: .studio)
        try FileManager.default.removeItem(at: flagURL)

        let result = try monitor.compare(before: before, target: .studio, desiredFlagData: Data("{\"A\":true}".utf8))

        XCTAssertEqual(result, .flagsMissingOrChanged)
    }

    func testDetectsBundleVersionChange() throws {
        let root = try temporaryDirectory()
        try makeFakeApp(root: root, target: .roblox, version: "1.0")
        let location = ManagedAppLocation(applicationsDirectory: root)
        let monitor = UpdateMonitor(location: location)
        let before = try monitor.fingerprint(for: .roblox)
        try writeInfoPlist(root: root, target: .roblox, version: "2.0")

        let result = try monitor.compare(before: before, target: .roblox, desiredFlagData: Data("{}".utf8))

        XCTAssertEqual(result, .bundleChanged)
    }

    private func makeFakeApp(root: URL, target: TargetKind, version: String) throws {
        let app = root.appendingPathComponent(target.appBundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS", isDirectory: true), withIntermediateDirectories: true)
        try writeInfoPlist(root: root, target: target, version: version)
    }

    private func writeInfoPlist(root: URL, target: TargetKind, version: String) throws {
        let app = root.appendingPathComponent(target.appBundleName, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": version]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
