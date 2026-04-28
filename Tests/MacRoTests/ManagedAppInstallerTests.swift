import Foundation
import XCTest
@testable import MacRo

final class ManagedAppInstallerTests: XCTestCase {
    func testInstallsFixtureZipIntoManagedLocation() async throws {
        let applications = try temporaryDirectory(named: "applications")
        let location = ManagedAppLocation(applicationsDirectory: applications)
        let zipURL = try makeFixtureZip(target: .roblox)
        let installer = ManagedAppInstaller(
            location: location,
            cdnClient: stubCdnClient(upload: "version-test"),
            downloader: FixtureDownloader(fixtureURL: zipURL),
            signatureVerifier: AlwaysValidSignatureVerifier()
        )

        _ = try await installer.install(.roblox, progress: { _ in })

        let exec = location.executableURL(for: .roblox)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exec.path))
        XCTAssertEqual(location.state(for: .roblox), .ready)
    }

    private func stubCdnClient(upload: String) -> RobloxCdnClient {
        RobloxCdnClient(versionFetcher: StubFetcher(upload: upload))
    }

    private func makeFixtureZip(target: TargetKind) throws -> URL {
        let staging = try temporaryDirectory(named: "fixture-staging")
        let appDir = staging.appendingPathComponent(target.appBundleName, isDirectory: true)
        let exec = appDir.appendingPathComponent(target.executableRelativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: exec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake-executable".utf8).write(to: exec)
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

extension ManagedAppInstallerTests {
    func testRejectsUnsignedBundle() async throws {
        let applications = try temporaryDirectory(named: "applications")
        let location = ManagedAppLocation(applicationsDirectory: applications)
        let zipURL = try makeFixtureZip(target: .roblox)
        let installer = ManagedAppInstaller(
            location: location,
            cdnClient: RobloxCdnClient(versionFetcher: StubFetcher(upload: "version-test")),
            downloader: FixtureDownloader(fixtureURL: zipURL),
            signatureVerifier: FailingSignatureVerifier()
        )

        do {
            _ = try await installer.install(.roblox, progress: { _ in })
            XCTFail("expected throw")
        } catch ManagedAppInstallerError.signatureInvalid {
            // ok
        }
        XCTAssertEqual(location.state(for: .roblox), .absent)
    }

    func testRejectsCorruptZip() async throws {
        let applications = try temporaryDirectory(named: "applications")
        let location = ManagedAppLocation(applicationsDirectory: applications)
        let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).zip")
        try Data("not a zip".utf8).write(to: corrupt)
        let installer = ManagedAppInstaller(
            location: location,
            cdnClient: RobloxCdnClient(versionFetcher: StubFetcher(upload: "version-test")),
            downloader: FixtureDownloader(fixtureURL: corrupt),
            signatureVerifier: AlwaysValidSignatureVerifier()
        )

        do {
            _ = try await installer.install(.roblox, progress: { _ in })
            XCTFail("expected throw")
        } catch ManagedAppInstallerError.extractionFailed {
            // ok
        }
    }

    func testExistingInstallIsPreservedWhenFinalMoveFails() async throws {
        let applications = try temporaryDirectory(named: "applications")
        let location = ManagedAppLocation(applicationsDirectory: applications)
        let existingExec = location.executableURL(for: .roblox)
        try FileManager.default.createDirectory(at: existingExec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing-executable".utf8).write(to: existingExec)

        let zipURL = try makeFixtureZip(target: .roblox)
        let installer = ManagedAppInstaller(
            location: location,
            cdnClient: RobloxCdnClient(versionFetcher: StubFetcher(upload: "version-test")),
            downloader: FixtureDownloader(fixtureURL: zipURL),
            signatureVerifier: AlwaysValidSignatureVerifier(),
            fileManager: FinalInstallMoveFailingFileManager()
        )

        do {
            _ = try await installer.install(.roblox, progress: { _ in })
            XCTFail("expected throw")
        } catch ManagedAppInstallerError.moveFailed {
            // ok
        }

        XCTAssertEqual(try String(contentsOf: existingExec, encoding: .utf8), "existing-executable")
        XCTAssertEqual(location.state(for: .roblox), .ready)
    }

    func testInstallerTerminatesRunningTargetBeforeReplacingExistingInstall() async throws {
        let applications = try temporaryDirectory(named: "applications")
        let location = ManagedAppLocation(applicationsDirectory: applications)
        let existingExec = location.executableURL(for: .studio)
        try FileManager.default.createDirectory(at: existingExec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing-executable".utf8).write(to: existingExec)
        let terminator = RecordingProcessTerminator()

        let zipURL = try makeFixtureZip(target: .studio)
        let installer = ManagedAppInstaller(
            location: location,
            cdnClient: RobloxCdnClient(versionFetcher: StubFetcher(upload: "version-test")),
            downloader: FixtureDownloader(fixtureURL: zipURL),
            signatureVerifier: AlwaysValidSignatureVerifier(),
            processTerminator: terminator
        )

        _ = try await installer.install(.studio, progress: { _ in })

        XCTAssertEqual(terminator.terminatedRequests.map(\.bundleIdentifier), [TargetKind.studio.bundleIdentifier])
        XCTAssertEqual(terminator.terminatedRequests.map(\.bundleURLs), [[location.appURL(for: .studio)]])
    }
}

private struct FailingSignatureVerifier: SignatureVerifying {
    func verify(appBundle: URL) throws {
        throw ManagedAppInstallerError.signatureInvalid("test failure")
    }
}

private final class FinalInstallMoveFailingFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL.lastPathComponent == TargetKind.roblox.appBundleName,
           srcURL.lastPathComponent == TargetKind.roblox.appBundleName {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

private final class RecordingProcessTerminator: ManagedAppProcessTerminating {
    var terminatedRequests: [(bundleIdentifier: String, bundleURLs: [URL])] = []

    func terminateRunningApplications(bundleIdentifier: String, matchingBundleURLs bundleURLs: [URL]) {
        terminatedRequests.append((bundleIdentifier, bundleURLs))
    }
}

extension ManagedAppInstallerTests {
    func testURLSessionDownloaderReportsByteProgressWhenContentLengthIsKnown() async throws {
        let payload = Data(repeating: 0x42, count: 128 * 1024)
        let downloader = URLSessionAssetDownloader(configuration: makeStubConfiguration(payload: payload, includeContentLength: true))
        let snapshots = SnapshotCollector()

        let downloaded = try await downloader.download(from: URL(string: "https://example.invalid/Roblox.zip")!) { snapshot in
            snapshots.append(snapshot)
        }

        XCTAssertEqual(try Data(contentsOf: downloaded), payload)
        let fractions = snapshots.fractions
        XCTAssertTrue(fractions.contains { $0 != nil })
        XCTAssertTrue(fractions.contains { $0 == 1.0 })
    }

    func testURLSessionDownloaderReportsIndeterminateProgressWhenContentLengthIsUnknown() async throws {
        let payload = Data(repeating: 0x24, count: 16 * 1024)
        let downloader = URLSessionAssetDownloader(configuration: makeStubConfiguration(payload: payload, includeContentLength: false))
        let snapshots = SnapshotCollector()

        let downloaded = try await downloader.download(from: URL(string: "https://example.invalid/Roblox.zip")!) { snapshot in
            snapshots.append(snapshot)
        }

        XCTAssertEqual(try Data(contentsOf: downloaded), payload)
        XCTAssertTrue(snapshots.fractions.contains(where: { $0 == nil }))
    }

    private func makeStubConfiguration(payload: Data, includeContentLength: Bool) -> URLSessionConfiguration {
        StubURLProtocol.payload = payload
        StubURLProtocol.includeContentLength = includeContentLength

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }
}

private final class SnapshotCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [DownloadProgressSnapshot] = []

    func append(_ snapshot: DownloadProgressSnapshot) {
        lock.withLock { snapshots.append(snapshot) }
    }

    var fractions: [Double?] {
        lock.withLock { snapshots.map(\.fraction) }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var includeContentLength = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        var headers: [String: String] = [:]
        if Self.includeContentLength {
            headers["Content-Length"] = "\(Self.payload.count)"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        let midpoint = Self.payload.count / 2
        client?.urlProtocol(self, didLoad: Self.payload.prefix(midpoint))
        client?.urlProtocol(self, didLoad: Self.payload.suffix(Self.payload.count - midpoint))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
