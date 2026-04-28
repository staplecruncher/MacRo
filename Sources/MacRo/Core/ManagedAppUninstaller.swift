import AppKit
import Foundation

protocol ManagedAppProcessTerminating {
    func terminateRunningApplications(bundleIdentifier: String, matchingBundleURLs bundleURLs: [URL])
}

struct ManagedAppUninstaller {
    let location: ManagedAppLocation
    let processTerminator: ManagedAppProcessTerminating
    let versionStore: ManagedAppVersionStore
    private let fileManager: FileManager

    init(
        location: ManagedAppLocation = ManagedAppLocation(),
        processTerminator: ManagedAppProcessTerminating = NSWorkspaceManagedAppProcessTerminator(),
        versionStore: ManagedAppVersionStore = ManagedAppVersionStore(),
        fileManager: FileManager = .default
    ) {
        self.location = location
        self.processTerminator = processTerminator
        self.versionStore = versionStore
        self.fileManager = fileManager
    }

    func uninstall(_ target: TargetKind) throws {
        let appURL = location.appURL(for: target)
        let legacyAppURL = location.legacyAppURL(for: target)
        processTerminator.terminateRunningApplications(
            bundleIdentifier: target.bundleIdentifier,
            matchingBundleURLs: [appURL, legacyAppURL]
        )
        if fileManager.fileExists(atPath: appURL.path) {
            try fileManager.removeItem(at: appURL)
        }
        if fileManager.fileExists(atPath: legacyAppURL.path) {
            try fileManager.removeItem(at: legacyAppURL)
        }
        try versionStore.removeVersionUpload(for: target)
    }
}

struct NSWorkspaceManagedAppProcessTerminator: ManagedAppProcessTerminating {
    func terminateRunningApplications(bundleIdentifier: String, matchingBundleURLs bundleURLs: [URL]) {
        let allowedPaths = Set(bundleURLs.map { $0.standardizedFileURL.path })
        let applications = NSWorkspace.shared.runningApplications
            .filter { application in
                guard application.bundleIdentifier == bundleIdentifier,
                      let bundleURL = application.bundleURL
                else {
                    return false
                }
                return allowedPaths.contains(bundleURL.standardizedFileURL.path)
            }
        for application in applications {
            application.terminate()
        }
    }
}
