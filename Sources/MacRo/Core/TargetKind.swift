import Foundation

enum TargetKind: String, CaseIterable, Codable, Identifiable {
    case roblox
    case studio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .roblox:
            "Roblox"
        case .studio:
            "Roblox Studio"
        }
    }

    var appBundleName: String {
        switch self {
        case .roblox:
            "RobloxPlayer.app"
        case .studio:
            "RobloxStudio.app"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .roblox:
            "com.roblox.RobloxPlayer"
        case .studio:
            "com.Roblox.RobloxStudio"
        }
    }

    var storeFileName: String {
        switch self {
        case .roblox:
            "roblox-flags.json"
        case .studio:
            "studio-flags.json"
        }
    }

    var versionStoreFileName: String {
        switch self {
        case .roblox:
            "roblox-version.txt"
        case .studio:
            "studio-version.txt"
        }
    }

    var executableRelativePath: String {
        switch self {
        case .roblox:
            "Contents/MacOS/RobloxPlayer"
        case .studio:
            "Contents/MacOS/RobloxStudio"
        }
    }

    var clientSettingsRelativePath: String {
        "Contents/MacOS/ClientSettings"
    }

    var clientAppSettingsRelativePath: String {
        "Contents/MacOS/ClientSettings/ClientAppSettings.json"
    }

    var requiresBundleSigningAfterFlagEdit: Bool {
        switch self {
        case .roblox:
            false
        case .studio:
            true
        }
    }
}
