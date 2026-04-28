import Foundation

enum ManagedAppState: Equatable {
    case absent
    case installing
    case ready
    case broken(reason: String)
}

struct ManagedAppLocation {
    let applicationsDirectory: URL
    let legacyApplicationsDirectory: URL
    private let fileManager: FileManager

    init(
        applicationsDirectory: URL = ManagedAppLocation.defaultApplicationsDirectory(),
        legacyApplicationsDirectory: URL = ManagedAppLocation.defaultLegacyApplicationsDirectory(),
        fileManager: FileManager = .default
    ) {
        self.applicationsDirectory = applicationsDirectory
        self.legacyApplicationsDirectory = legacyApplicationsDirectory
        self.fileManager = fileManager
    }

    static func defaultApplicationsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(AppConstants.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("ManagedApps", isDirectory: true)
    }

    static func defaultLegacyApplicationsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    }

    func appURL(for target: TargetKind) -> URL {
        applicationsDirectory.appendingPathComponent(target.appBundleName, isDirectory: true)
    }

    func executableURL(for target: TargetKind) -> URL {
        appURL(for: target).appendingPathComponent(target.executableRelativePath, isDirectory: false)
    }

    func clientSettingsDirectoryURL(for target: TargetKind) -> URL {
        appURL(for: target).appendingPathComponent(target.clientSettingsRelativePath, isDirectory: true)
    }

    func clientAppSettingsURL(for target: TargetKind) -> URL {
        appURL(for: target).appendingPathComponent(target.clientAppSettingsRelativePath, isDirectory: false)
    }

    func ensureApplicationsDirectoryExists() throws {
        try fileManager.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
    }

    func legacyAppURL(for target: TargetKind) -> URL {
        legacyApplicationsDirectory.appendingPathComponent(target.appBundleName, isDirectory: true)
    }

    func state(for target: TargetKind) -> ManagedAppState {
        let app = appURL(for: target)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: app.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .absent
        }

        let exec = executableURL(for: target)
        if !fileManager.fileExists(atPath: exec.path) {
            return .broken(reason: "Missing executable at \(exec.path)")
        }

        if !bundleContainsNativeArchitecture(at: app) {
            return .broken(reason: "\(target.displayName) does not contain a native build for this Mac.")
        }

        return .ready
    }

    private func bundleContainsNativeArchitecture(at appURL: URL) -> Bool {
        guard let bundle = Bundle(url: appURL),
              let architectures = bundle.executableArchitectures else {
            return true
        }
        #if arch(arm64)
        return architectures.contains(NSNumber(value: 0x0100000c)) // CPU_TYPE_ARM64
        #elseif arch(x86_64)
        return architectures.contains(NSNumber(value: 0x01000007)) // CPU_TYPE_X86_64
        #else
        return true
        #endif
    }
}
