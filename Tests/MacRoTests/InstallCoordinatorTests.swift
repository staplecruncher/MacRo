import Foundation
import XCTest
@testable import MacRo

@MainActor
final class InstallCoordinatorTests: XCTestCase {
    func testEnsureInstalledReturnsTrueWithoutReinstallWhenVersionMatches() async throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try makeInstalledApp(location: location, target: .roblox, marker: "existing")
        let versionStore = ManagedAppVersionStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        try versionStore.saveVersionUpload("version-current", for: .roblox)
        let installer = ManagedAppInstaller(
            location: location,
            cdnClient: stubCdnClient(upload: "version-current"),
            downloader: FixtureDownloader(fixtureURL: try makeFixtureZip(target: .roblox, marker: "downloaded")),
            signatureVerifier: AlwaysValidSignatureVerifier()
        )
        let coordinator = InstallCoordinator(installer: installer, versionStore: versionStore)

        let ensured = await coordinator.ensureInstalled(.roblox, location: location)

        XCTAssertTrue(ensured)
        let data = try Data(contentsOf: location.executableURL(for: .roblox))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "existing")
    }

    func testEnsureInstalledReinstallsWhenVersionChanged() async throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try makeInstalledApp(location: location, target: .roblox, marker: "old")
        let versionStore = ManagedAppVersionStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        try versionStore.saveVersionUpload("version-old", for: .roblox)
        let installer = ManagedAppInstaller(
            location: location,
            cdnClient: stubCdnClient(upload: "version-new"),
            downloader: FixtureDownloader(fixtureURL: try makeFixtureZip(target: .roblox, marker: "new")),
            signatureVerifier: AlwaysValidSignatureVerifier()
        )
        let coordinator = InstallCoordinator(installer: installer, versionStore: versionStore)

        let ensured = await coordinator.ensureInstalled(.roblox, location: location)

        XCTAssertTrue(ensured)
        let data = try Data(contentsOf: location.executableURL(for: .roblox))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "new")
        XCTAssertEqual(try versionStore.loadVersionUpload(for: .roblox), "version-new")
    }

    func testEnsureInstalledReinstallsWhenPlayerChannelDiffersEvenIfUploadMatches() async throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try makeInstalledApp(location: location, target: .roblox, marker: "default-channel")
        let versionStore = ManagedAppVersionStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        try versionStore.saveVersionUpload("version-current", for: .roblox)
        let installer = ManagedAppInstaller(
            location: location,
            cdnClient: stubCdnClient(upload: "version-current", channel: "zcurl8190test2"),
            downloader: FixtureDownloader(fixtureURL: try makeFixtureZip(target: .roblox, marker: "channel-install")),
            signatureVerifier: AlwaysValidSignatureVerifier()
        )
        let coordinator = InstallCoordinator(installer: installer, versionStore: versionStore)

        let ensured = await coordinator.ensureInstalled(.roblox, location: location)

        XCTAssertTrue(ensured)
        let data = try Data(contentsOf: location.executableURL(for: .roblox))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "channel-install")
        XCTAssertEqual(try versionStore.loadVersionUpload(for: .roblox), "version-current\nchannel=zcurl8190test2")
    }

    private func stubCdnClient(upload: String, channel: String? = nil) -> RobloxCdnClient {
        RobloxCdnClient(versionFetcher: StubFetcher(upload: upload), channelProvider: StubInstallChannelProvider(channel: channel))
    }

    private func makeInstalledApp(location: ManagedAppLocation, target: TargetKind, marker: String) throws {
        let exec = location.executableURL(for: target)
        try FileManager.default.createDirectory(at: exec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: exec)
    }

    private func makeFixtureZip(target: TargetKind, marker: String) throws -> URL {
        let staging = try temporaryDirectory(named: "fixture-staging")
        let appDir = staging.appendingPathComponent(target.appBundleName, isDirectory: true)
        let exec = appDir.appendingPathComponent(target.executableRelativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: exec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: exec)
        let zipURL = staging.appendingPathComponent("fixture.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", appDir.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zipURL
    }
}

private struct StubFetcher: RobloxVersionFetching {
    let upload: String

    func fetchVersionJSON(for target: TargetKind, channel: String?) async throws -> Data {
        Data(#"{"clientVersionUpload":"\#(upload)"}"#.utf8)
    }
}

private struct StubInstallChannelProvider: RobloxChannelProviding {
    let channel: String?

    func channel(for target: TargetKind) -> String? {
        channel
    }
}

private struct FixtureDownloader: AssetDownloading {
    let fixtureURL: URL

    func download(
        from url: URL,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> URL {
        progress(
            DownloadProgressSnapshot(
                fraction: 1.0,
                bytesReceived: 0,
                totalBytesExpected: nil,
                bytesPerSecond: nil
            )
        )
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).zip")
        try FileManager.default.copyItem(at: fixtureURL, to: destination)
        return destination
    }
}

private struct AlwaysValidSignatureVerifier: SignatureVerifying {
    func verify(appBundle: URL) throws {
        // no-op
    }
}
