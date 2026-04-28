import Foundation
import XCTest
@testable import MacRo

final class RobloxCdnClientTests: XCTestCase {
    func testConstructsPlayerZipURL() {
        let client = RobloxCdnClient(versionFetcher: StubVersionFetcher(upload: "version-abcdef0123456789"))
        let url = client.assetURL(for: .roblox, clientVersionUpload: "version-abcdef0123456789")
        XCTAssertEqual(url.absoluteString, "https://setup.rbxcdn.com/mac/arm64/version-abcdef0123456789-RobloxPlayer.zip")
    }

    func testConstructsStudioZipURL() {
        let client = RobloxCdnClient(versionFetcher: StubVersionFetcher(upload: "version-abcdef0123456789"))
        let url = client.assetURL(for: .studio, clientVersionUpload: "version-abcdef0123456789")
        XCTAssertEqual(url.absoluteString, "https://setup.rbxcdn.com/mac/arm64/version-abcdef0123456789-RobloxStudioApp.zip")
    }

    func testConstructsIntelPlayerZipURLWhenConfiguredForGenericMacBase() {
        let client = RobloxCdnClient(
            versionFetcher: StubVersionFetcher(upload: "version-abcdef0123456789"),
            setupCdnBase: URL(string: "https://setup.rbxcdn.com/mac/")!
        )
        let url = client.assetURL(for: .roblox, clientVersionUpload: "version-abcdef0123456789")
        XCTAssertEqual(url.absoluteString, "https://setup.rbxcdn.com/mac/version-abcdef0123456789-RobloxPlayer.zip")
    }

    func testConstructsChannelPlayerZipURL() {
        let client = RobloxCdnClient(versionFetcher: StubVersionFetcher(upload: "version-abcdef0123456789"))
        let version = RobloxClientVersion(clientVersionUpload: "version-abcdef0123456789", channel: "zcurl8190test2")
        let url = client.assetURL(for: .roblox, version: version)
        XCTAssertEqual(url.absoluteString, "https://setup.rbxcdn.com/channel/common/mac/arm64/version-abcdef0123456789-RobloxPlayer.zip")
    }

    func testFetchCurrentVersionUploadReturnsStubbedValue() async throws {
        let client = RobloxCdnClient(versionFetcher: StubVersionFetcher(upload: "version-stubvalue"))
        let upload = try await client.fetchCurrentVersionUpload(for: .roblox)
        XCTAssertEqual(upload, "version-stubvalue")
    }

    func testFetchCurrentVersionUsesSavedPlayerChannel() async throws {
        let fetcher = RecordingVersionFetcher(upload: "version-channel")
        let client = RobloxCdnClient(
            versionFetcher: fetcher,
            channelProvider: StubChannelProvider(channel: "zcurl8190test2")
        )

        let version = try await client.fetchCurrentVersion(for: .roblox)

        XCTAssertEqual(version, RobloxClientVersion(clientVersionUpload: "version-channel", channel: "zcurl8190test2"))
        XCTAssertEqual(fetcher.requests, [VersionRequest(target: .roblox, channel: "zcurl8190test2")])
    }

    func testFetchCurrentVersionIgnoresBlankSavedChannel() async throws {
        let fetcher = RecordingVersionFetcher(upload: "version-default")
        let client = RobloxCdnClient(
            versionFetcher: fetcher,
            channelProvider: StubChannelProvider(channel: "  ")
        )

        let version = try await client.fetchCurrentVersion(for: .roblox)

        XCTAssertEqual(version, RobloxClientVersion(clientVersionUpload: "version-default", channel: nil))
        XCTAssertEqual(fetcher.requests, [VersionRequest(target: .roblox, channel: nil)])
    }

    func testFetchCurrentVersionUploadThrowsOnMissingKey() async {
        let fetcher = StubVersionFetcher(upload: "version-stubvalue", payloadOverride: Data(#"{"unexpected":"shape"}"#.utf8))
        let client = RobloxCdnClient(versionFetcher: fetcher)
        do {
            _ = try await client.fetchCurrentVersionUpload(for: .roblox)
            XCTFail("expected throw")
        } catch RobloxCdnClientError.invalidVersionResponse {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

private final class StubVersionFetcher: RobloxVersionFetching {
    let upload: String
    let payloadOverride: Data?

    init(upload: String, payloadOverride: Data? = nil) {
        self.upload = upload
        self.payloadOverride = payloadOverride
    }

    func fetchVersionJSON(for target: TargetKind, channel: String?) async throws -> Data {
        if let payloadOverride { return payloadOverride }
        return Data(#"{"clientVersionUpload":"\#(upload)"}"#.utf8)
    }
}

private struct VersionRequest: Equatable {
    let target: TargetKind
    let channel: String?
}

private final class RecordingVersionFetcher: RobloxVersionFetching {
    let upload: String
    private(set) var requests: [VersionRequest] = []

    init(upload: String) {
        self.upload = upload
    }

    func fetchVersionJSON(for target: TargetKind, channel: String?) async throws -> Data {
        requests.append(VersionRequest(target: target, channel: channel))
        return Data(#"{"clientVersionUpload":"\#(upload)"}"#.utf8)
    }
}

private struct StubChannelProvider: RobloxChannelProviding {
    let channel: String?

    func channel(for target: TargetKind) -> String? {
        channel
    }
}
