import Foundation
import XCTest
@testable import MacRo

final class ManagedAppLocationTests: XCTestCase {
    func testDefaultApplicationsDirectoryIsApplicationSupportManagedApps() {
        let location = ManagedAppLocation()
        let expected = FlagStore.defaultRootDirectory()
            .appendingPathComponent("ManagedApps", isDirectory: true).path
        XCTAssertEqual(location.applicationsDirectory.path, expected)
    }

    func testBuildsBundleAndSettingsURLs() {
        let root = URL(fileURLWithPath: "/tmp/Applications", isDirectory: true)
        let location = ManagedAppLocation(applicationsDirectory: root)
        XCTAssertEqual(location.appURL(for: .roblox).path, "/tmp/Applications/RobloxPlayer.app")
        XCTAssertEqual(
            location.clientAppSettingsURL(for: .studio).path,
            "/tmp/Applications/RobloxStudio.app/Contents/MacOS/ClientSettings/ClientAppSettings.json"
        )
    }

    func testLegacyApplicationsDirectoryIsUserHomeApplications() {
        let location = ManagedAppLocation()
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path
        XCTAssertEqual(location.legacyApplicationsDirectory.path, expected)
    }
}

extension ManagedAppLocationTests {
    func testStateAbsentWhenNoAppExists() throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root)
        XCTAssertEqual(location.state(for: .roblox), .absent)
    }

    func testStateReadyWhenExecutablePresent() throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root)
        let exec = location.executableURL(for: .roblox)
        try FileManager.default.createDirectory(at: exec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: exec)
        XCTAssertEqual(location.state(for: .roblox), .ready)
    }

    func testStateBrokenWhenBundleExistsButExecutableMissing() throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root)
        let app = location.appURL(for: .roblox)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let state = location.state(for: .roblox)
        if case .broken = state { return }
        XCTFail("expected .broken, got \(state)")
    }
}
