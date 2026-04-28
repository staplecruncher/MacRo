import Foundation

enum RoutedLaunchRequest: Equatable, Sendable {
    case robloxPlayer(URL)
    case robloxStudioAuth(URL)
    case robloxStudioPlace(URL)
    case studioDocument(URL)

    var target: TargetKind {
        switch self {
        case .robloxPlayer:
            .roblox
        case .robloxStudioAuth, .robloxStudioPlace, .studioDocument:
            .studio
        }
    }

    var url: URL {
        switch self {
        case .robloxPlayer(let url), .robloxStudioAuth(let url), .robloxStudioPlace(let url), .studioDocument(let url):
            url
        }
    }

    static func parse(url: URL) -> RoutedLaunchRequest? {
        if url.isFileURL {
            return parse(fileURL: url)
        }
        return parse(openURL: url)
    }

    static func parse(openURL url: URL) -> RoutedLaunchRequest? {
        switch url.scheme?.lowercased() {
        case AppConstants.robloxPlayerScheme:
            return .robloxPlayer(url)
        case AppConstants.robloxStudioAuthScheme:
            return .robloxStudioAuth(url)
        case AppConstants.robloxStudioScheme:
            return .robloxStudioPlace(url)
        default:
            return nil
        }
    }

    static func parse(fileURL url: URL) -> RoutedLaunchRequest? {
        switch url.pathExtension.lowercased() {
        case "rbxl", "rbxlx":
            return .studioDocument(url)
        default:
            return nil
        }
    }
}
