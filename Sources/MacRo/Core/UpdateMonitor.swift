import Foundation

struct LaunchFingerprint: Equatable {
    var bundleModificationDate: Date?
    var bundleVersion: String?
    var flagFileExists: Bool
    var flagFileHash: String?
}

enum UpdateImpact: Equatable {
    case unchanged
    case bundleChanged
    case flagsMissingOrChanged
}

final class UpdateWatchSession: @unchecked Sendable {
    private let watcher: FileSystemWatcher

    fileprivate init(watcher: FileSystemWatcher) {
        self.watcher = watcher
    }

    deinit {
        watcher.cancel()
    }

    func waitForChange(timeout: Duration) async -> Bool {
        await watcher.waitForChange(timeout: timeout)
    }

    func cancel() {
        watcher.cancel()
    }
}

struct UpdateMonitor: @unchecked Sendable {
    let location: ManagedAppLocation
    let fileManager: FileManager

    init(location: ManagedAppLocation = ManagedAppLocation(), fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
    }

    func fingerprint(for target: TargetKind) throws -> LaunchFingerprint {
        let appURL = location.appURL(for: target)
        let flagURL = location.clientAppSettingsURL(for: target)
        let attributes = try? fileManager.attributesOfItem(atPath: appURL.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let flagExists = fileManager.fileExists(atPath: flagURL.path)
        let flagHash = flagExists ? try FileHashing.sha256Hex(of: flagURL) : nil

        return LaunchFingerprint(
            bundleModificationDate: modificationDate,
            bundleVersion: bundleVersion(for: appURL),
            flagFileExists: flagExists,
            flagFileHash: flagHash
        )
    }

    func beginWatching(for target: TargetKind) throws -> UpdateWatchSession {
        try UpdateWatchSession(watcher: FileSystemWatcher(urls: watchURLs(for: target)))
    }

    func waitForImpact(
        after before: LaunchFingerprint,
        target: TargetKind,
        desiredFlagData: Data,
        session: UpdateWatchSession,
        timeout: Duration
    ) async throws -> UpdateImpact? {
        defer { session.cancel() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            let remaining = clock.now.duration(to: deadline)
            guard await session.waitForChange(timeout: remaining) else {
                return nil
            }

            let impact = try compare(before: before, target: target, desiredFlagData: desiredFlagData)
            if impact != .unchanged {
                return impact
            }
        }

        return nil
    }

    func compare(before: LaunchFingerprint, target: TargetKind, desiredFlagData: Data) throws -> UpdateImpact {
        let after = try fingerprint(for: target)

        if before.bundleVersion != after.bundleVersion {
            return .bundleChanged
        }

        guard after.flagFileExists else {
            return .flagsMissingOrChanged
        }

        if after.flagFileHash != FileHashing.sha256Hex(data: desiredFlagData) {
            return .flagsMissingOrChanged
        }

        return .unchanged
    }

    private func bundleVersion(for appURL: URL) -> String? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }

        return plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String
    }

    private func watchURLs(for target: TargetKind) -> [URL] {
        let candidates = [
            location.appURL(for: target).deletingLastPathComponent(),
            location.clientAppSettingsURL(for: target).deletingLastPathComponent()
        ]

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let watchURL = nearestExistingAncestor(for: candidate)
            let path = watchURL.standardizedFileURL.path
            guard seen.insert(path).inserted else {
                return nil
            }
            return watchURL
        }
    }

    private func nearestExistingAncestor(for url: URL) -> URL {
        var current = url.standardizedFileURL
        while current.path != "/" && !fileManager.fileExists(atPath: current.path) {
            current.deleteLastPathComponent()
        }
        return current
    }
}

private final class FileSystemWatcher: @unchecked Sendable {
    private let signal = FileChangeSignal()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var didCancel = false

    init(urls: [URL]) throws {
        for url in urls {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                throw CocoaError(.fileReadNoSuchFile)
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [signal] in
                Task {
                    await signal.signal()
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            sources.append(source)
        }
    }

    func waitForChange(timeout: Duration) async -> Bool {
        await signal.wait(timeout: timeout)
    }

    func cancel() {
        guard !didCancel else {
            return
        }
        didCancel = true
        sources.forEach { $0.cancel() }
        sources.removeAll()
        Task {
            await signal.cancel()
        }
    }
}

private actor FileChangeSignal {
    private var bufferedChanges = 0
    private var waiter: CheckedContinuation<Bool, Never>?

    func signal() {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: true)
        } else {
            bufferedChanges += 1
        }
    }

    func wait(timeout: Duration) async -> Bool {
        if bufferedChanges > 0 {
            bufferedChanges -= 1
            return true
        }

        return await withCheckedContinuation { continuation in
            waiter = continuation
            Task {
                try? await Task.sleep(for: timeout)
                timeoutWait()
            }
        }
    }

    func cancel() {
        guard let waiter else {
            return
        }
        self.waiter = nil
        waiter.resume(returning: false)
    }

    private func timeoutWait() {
        guard let waiter else {
            return
        }
        self.waiter = nil
        waiter.resume(returning: false)
    }
}
