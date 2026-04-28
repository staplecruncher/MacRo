import Foundation

struct RobloxClientVersion: Equatable, Sendable {
    let clientVersionUpload: String
    let channel: String?

    init(clientVersionUpload: String, channel: String?) {
        self.clientVersionUpload = clientVersionUpload
        self.channel = Self.normalizedChannel(channel)
    }

    var installIdentity: String {
        guard let channel else {
            return clientVersionUpload
        }
        return "\(clientVersionUpload)\nchannel=\(channel)"
    }

    static func normalizedChannel(_ channel: String?) -> String? {
        guard let channel = channel?.trimmingCharacters(in: .whitespacesAndNewlines), !channel.isEmpty else {
            return nil
        }
        return channel
    }
}

protocol RobloxVersionFetching {
    func fetchVersionJSON(for target: TargetKind, channel: String?) async throws -> Data
}

protocol RobloxChannelProviding {
    func channel(for target: TargetKind) -> String?
}

struct PreferencesRobloxChannelProvider: RobloxChannelProviding {
    func channel(for target: TargetKind) -> String? {
        guard let value = CFPreferencesCopyAppValue(
            "www.roblox.com" as CFString,
            target.channelPreferencesDomain as CFString
        ) as? String else {
            return nil
        }
        return RobloxClientVersion.normalizedChannel(value)
    }
}

enum RobloxCdnClientError: Error, LocalizedError {
    case invalidVersionResponse

    var errorDescription: String? {
        switch self {
        case .invalidVersionResponse:
            "Roblox's download service returned an unexpected response."
        }
    }
}

struct RobloxCdnClient {
    let versionFetcher: RobloxVersionFetching
    let channelProvider: RobloxChannelProviding
    let setupCdnBase: URL
    let channelSetupCdnBase: URL

    static let clientSettingsBase = URL(string: "https://clientsettings.roblox.com/v2/client-version/")!
    static let clientSettingsCdnBase = URL(string: "https://clientsettingscdn.roblox.com/v2/client-version/")!

    init(
        versionFetcher: RobloxVersionFetching = URLSessionVersionFetcher(),
        channelProvider: RobloxChannelProviding = PreferencesRobloxChannelProvider(),
        setupCdnBase: URL = Self.defaultSetupCdnBase,
        channelSetupCdnBase: URL = Self.defaultChannelSetupCdnBase
    ) {
        self.versionFetcher = versionFetcher
        self.channelProvider = channelProvider
        self.setupCdnBase = setupCdnBase
        self.channelSetupCdnBase = channelSetupCdnBase
    }

    func fetchCurrentVersion(for target: TargetKind) async throws -> RobloxClientVersion {
        let channel = RobloxClientVersion.normalizedChannel(channelProvider.channel(for: target))
        let data = try await versionFetcher.fetchVersionJSON(for: target, channel: channel)
        return try parseVersion(from: data, channel: channel)
    }

    func fetchCurrentVersionUpload(for target: TargetKind) async throws -> String {
        try await fetchCurrentVersion(for: target).clientVersionUpload
    }

    func assetURL(for target: TargetKind, version: RobloxClientVersion) -> URL {
        let baseURL = version.channel == nil ? setupCdnBase : channelSetupCdnBase
        return baseURL.appendingPathComponent("\(version.clientVersionUpload)-\(target.cdnAssetSuffix)")
    }

    func assetURL(for target: TargetKind, clientVersionUpload: String) -> URL {
        assetURL(for: target, version: RobloxClientVersion(clientVersionUpload: clientVersionUpload, channel: nil))
    }

    private func parseVersion(from data: Data, channel: String?) throws -> RobloxClientVersion {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let upload = object["clientVersionUpload"] as? String,
              !upload.isEmpty
        else {
            throw RobloxCdnClientError.invalidVersionResponse
        }
        return RobloxClientVersion(clientVersionUpload: upload, channel: channel)
    }

    private static var defaultSetupCdnBase: URL {
        #if arch(arm64)
        URL(string: "https://setup.rbxcdn.com/mac/arm64/")!
        #elseif arch(x86_64)
        URL(string: "https://setup.rbxcdn.com/mac/")!
        #else
        URL(string: "https://setup.rbxcdn.com/mac/")!
        #endif
    }

    private static var defaultChannelSetupCdnBase: URL {
        #if arch(arm64)
        URL(string: "https://setup.rbxcdn.com/channel/common/mac/arm64/")!
        #elseif arch(x86_64)
        URL(string: "https://setup.rbxcdn.com/channel/common/mac/")!
        #else
        URL(string: "https://setup.rbxcdn.com/channel/common/mac/")!
        #endif
    }
}

extension TargetKind {
    var versionIdentifier: String {
        switch self {
        case .roblox: "MacPlayer"
        case .studio: "MacStudio"
        }
    }

    var cdnAssetSuffix: String {
        switch self {
        case .roblox: "RobloxPlayer.zip"
        case .studio: "RobloxStudioApp.zip"
        }
    }

    var channelPreferencesDomain: String {
        switch self {
        case .roblox: "com.roblox.RobloxPlayerChannel"
        case .studio: "com.roblox.RobloxStudioChannel"
        }
    }
}

struct URLSessionVersionFetcher: RobloxVersionFetching {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchVersionJSON(for target: TargetKind, channel: String?) async throws -> Data {
        let url = versionURL(for: target, channel: channel)
        var lastError: Error = RobloxCdnClientError.invalidVersionResponse
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(pow(2.0, Double(attempt - 1))))
            }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastError = RobloxCdnClientError.invalidVersionResponse
                    continue
                }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func versionURL(for target: TargetKind, channel: String?) -> URL {
        guard let channel else {
            return RobloxCdnClient.clientSettingsBase.appendingPathComponent(target.versionIdentifier)
        }
        return RobloxCdnClient.clientSettingsCdnBase
            .appendingPathComponent(target.versionIdentifier)
            .appendingPathComponent("channel")
            .appendingPathComponent(channel)
    }
}
