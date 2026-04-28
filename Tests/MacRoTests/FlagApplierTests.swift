import Foundation
import XCTest
@testable import MacRo

final class FlagApplierTests: XCTestCase {
    func testAppliesGeneratedFlagsIntoFakeAppBundleWithoutSigningRobloxPlayer() async throws {
        let root = try temporaryDirectory()
        let backupRoot = try temporaryDirectory(named: "backups")
        try makeFakeApp(root: root, target: .roblox)
        let location = ManagedAppLocation(applicationsDirectory: root)
        let signer = RecordingBundleSigner()
        let applier = FlagApplier(location: location, backupRoot: backupRoot, bundleSigner: signer)
        let data = try FlagSerializer.serialize([FlagRow(name: "FFlagTest", rawValue: "true", isEnabled: true)])

        let result = try await applier.apply(data: data, to: .roblox, replacementDecision: .replace)

        XCTAssertEqual(result, .applied)
        let written = try Data(contentsOf: location.clientAppSettingsURL(for: .roblox))
        XCTAssertEqual(try FileHashing.sha256Hex(of: location.clientAppSettingsURL(for: .roblox)), FileHashing.sha256Hex(data: written))
        XCTAssertTrue(signer.signedBundles.isEmpty)
    }

    func testAppliesGeneratedFlagsIntoFakeStudioBundleAndSignsStudio() async throws {
        let root = try temporaryDirectory()
        let backupRoot = try temporaryDirectory(named: "backups")
        try makeFakeApp(root: root, target: .studio)
        let location = ManagedAppLocation(applicationsDirectory: root)
        let signer = RecordingBundleSigner()
        let applier = FlagApplier(location: location, backupRoot: backupRoot, bundleSigner: signer)
        let data = try FlagSerializer.serialize([FlagRow(name: "FFlagStudioTest", rawValue: "true", isEnabled: true)])

        let result = try await applier.apply(data: data, to: .studio, replacementDecision: .replace)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(signer.signedBundles, [location.appURL(for: .studio)])
    }

    func testExistingUnmanagedFileRequiresDecisionAndCreatesBackupWhenReplaced() async throws {
        let root = try temporaryDirectory()
        let backupRoot = try temporaryDirectory(named: "backups")
        try makeFakeApp(root: root, target: .studio)
        let location = ManagedAppLocation(applicationsDirectory: root)
        let existingURL = location.clientAppSettingsURL(for: .studio)
        try FileManager.default.createDirectory(at: existingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"Existing\":true}".utf8).write(to: existingURL)
        let applier = FlagApplier(location: location, backupRoot: backupRoot)
        let newData = try FlagSerializer.serialize([FlagRow(name: "FFlagNew", rawValue: "false")])

        let blocked = try await applier.apply(data: newData, to: .studio, replacementDecision: .ask)
        XCTAssertEqual(blocked, .needsReplacementDecision(existingURL))

        let replaced = try await applier.apply(data: newData, to: .studio, replacementDecision: .replace)
        XCTAssertEqual(replaced, .applied)
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(String(decoding: try Data(contentsOf: backups[0]), as: UTF8.self), "{\"Existing\":true}")
    }

    func testPreviouslyGeneratedFileCanBeReplacedWithoutPrompt() async throws {
        let root = try temporaryDirectory()
        let backupRoot = try temporaryDirectory(named: "backups")
        try makeFakeApp(root: root, target: .roblox)
        let location = ManagedAppLocation(applicationsDirectory: root)
        let applier = FlagApplier(location: location, backupRoot: backupRoot)
        let firstData = try FlagSerializer.serialize([FlagRow(name: "FFlagOld", rawValue: "true")])
        let secondData = try FlagSerializer.serialize([FlagRow(name: "FFlagNew", rawValue: "false")])

        let firstResult = try await applier.apply(data: firstData, to: .roblox, replacementDecision: .replace)
        XCTAssertEqual(firstResult, .applied)
        let secondResult = try await applier.apply(data: secondData, to: .roblox, replacementDecision: .ask)
        XCTAssertEqual(secondResult, .applied)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: location.clientAppSettingsURL(for: .roblox))) as? [String: Any])
        XCTAssertEqual(object["FFlagNew"] as? Bool, false)
    }

    func testFallsBackToStagedBundleCopyWhenDirectSigningFails() async throws {
        let root = try temporaryDirectory()
        let backupRoot = try temporaryDirectory(named: "backups")
        try makeFakeApp(root: root, target: .studio)
        let location = ManagedAppLocation(applicationsDirectory: root)
        let signer = FailingFirstBundleSigner()
        let applier = FlagApplier(location: location, backupRoot: backupRoot, bundleSigner: signer)
        let data = try FlagSerializer.serialize([FlagRow(name: "FFlagStudio", rawValue: "true")])

        let result = try await applier.apply(data: data, to: .studio, replacementDecision: .replace)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(signer.signedBundles.first, location.appURL(for: .studio))
        XCTAssertEqual(signer.signedBundles.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.clientAppSettingsURL(for: .studio).path))
    }

    private func makeFakeApp(root: URL, target: TargetKind) throws {
        let exec = root.appendingPathComponent(target.appBundleName, isDirectory: true)
            .appendingPathComponent(target.executableRelativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: exec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: exec)
    }
}

private final class RecordingBundleSigner: BundleSigning, @unchecked Sendable {
    var signedBundles: [URL] = []

    func signAdHoc(appBundle: URL) throws {
        signedBundles.append(appBundle)
    }
}

private final class FailingFirstBundleSigner: BundleSigning, @unchecked Sendable {
    var signedBundles: [URL] = []

    func signAdHoc(appBundle: URL) throws {
        signedBundles.append(appBundle)
        if signedBundles.count == 1 {
            throw FlagApplierError.bundleSigningFailed("simulated protected bundle")
        }
    }
}
