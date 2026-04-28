import Foundation

protocol AssetDownloading {
    func download(from url: URL, progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void) async throws -> URL
}

protocol SignatureVerifying {
    func verify(appBundle: URL) throws
}

enum ManagedAppInstallerError: Error, LocalizedError {
    case extractionFailed(String)
    case signatureInvalid(String)
    case bundleNotFoundAfterExtraction(String)
    case moveFailed(String)
    case insufficientDiskSpace(available: Int64, required: Int64)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let message):
            "The download was incomplete. Please retry. (\(message))"
        case .signatureInvalid(let message):
            "Verification of the downloaded Roblox bundle failed. (\(message))"
        case .bundleNotFoundAfterExtraction(let name):
            "The downloaded archive did not contain \(name)."
        case .moveFailed(let message):
            "Could not install the downloaded Roblox bundle. (\(message))"
        case .insufficientDiskSpace(let available, let required):
            "Not enough disk space. \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available, \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) needed."
        }
    }
}

struct ManagedAppInstaller: @unchecked Sendable {
    let location: ManagedAppLocation
    let cdnClient: RobloxCdnClient
    let downloader: AssetDownloading
    let signatureVerifier: SignatureVerifying
    let processTerminator: ManagedAppProcessTerminating
    let fileManager: FileManager

    init(
        location: ManagedAppLocation = ManagedAppLocation(),
        cdnClient: RobloxCdnClient = RobloxCdnClient(),
        downloader: AssetDownloading = URLSessionAssetDownloader(),
        signatureVerifier: SignatureVerifying = CodesignVerifier(),
        processTerminator: ManagedAppProcessTerminating = NSWorkspaceManagedAppProcessTerminator(),
        fileManager: FileManager = .default
    ) {
        self.location = location
        self.cdnClient = cdnClient
        self.downloader = downloader
        self.signatureVerifier = signatureVerifier
        self.processTerminator = processTerminator
        self.fileManager = fileManager
    }

    func fetchCurrentVersionUpload(for target: TargetKind) async throws -> String {
        try await cdnClient.fetchCurrentVersionUpload(for: target)
    }

    func fetchCurrentVersion(for target: TargetKind) async throws -> RobloxClientVersion {
        try await cdnClient.fetchCurrentVersion(for: target)
    }

    func install(
        _ target: TargetKind,
        clientVersionUpload: String,
        progress: @Sendable @escaping (InstallProgress) -> Void
    ) async throws -> String {
        let installedVersion = try await install(
            target,
            clientVersion: RobloxClientVersion(clientVersionUpload: clientVersionUpload, channel: nil),
            progress: progress
        )
        return installedVersion.clientVersionUpload
    }

    func install(
        _ target: TargetKind,
        clientVersion: RobloxClientVersion? = nil,
        progress: @Sendable @escaping (InstallProgress) -> Void
    ) async throws -> RobloxClientVersion {
        try location.ensureApplicationsDirectoryExists()
        try checkDiskSpace()
        let version = try await {
            if let clientVersion {
                return clientVersion
            }
            return try await fetchCurrentVersion(for: target)
        }()
        let assetURL = cdnClient.assetURL(for: target, version: version)

        let snapshotBox = LatestSnapshotBox()
        let zipURL = try await downloader.download(from: assetURL) { snapshot in
            snapshotBox.set(snapshot)
            progress(
                InstallProgress(
                    target: target,
                    phase: .downloading,
                    fraction: snapshot.fraction,
                    bytesReceived: snapshot.bytesReceived,
                    totalBytesExpected: snapshot.totalBytesExpected,
                    bytesPerSecond: snapshot.bytesPerSecond
                )
            )
        }
        defer { try? fileManager.removeItem(at: zipURL) }

        let finalSnapshot = snapshotBox.get()
        progress(
            InstallProgress(
                target: target,
                phase: .installing,
                fraction: 1.0,
                bytesReceived: finalSnapshot.bytesReceived,
                totalBytesExpected: finalSnapshot.totalBytesExpected,
                bytesPerSecond: finalSnapshot.bytesPerSecond
            )
        )

        let staging = fileManager.temporaryDirectory.appendingPathComponent("managed-install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        runStripQuarantine(at: zipURL)
        try runExtract(zipURL: zipURL, destination: staging)

        let extracted = staging.appendingPathComponent(target.appBundleName, isDirectory: true)
        guard fileManager.fileExists(atPath: extracted.path) else {
            throw ManagedAppInstallerError.bundleNotFoundAfterExtraction(target.appBundleName)
        }

        try signatureVerifier.verify(appBundle: extracted)

        if fileManager.fileExists(atPath: location.appURL(for: target).path) {
            processTerminator.terminateRunningApplications(
                bundleIdentifier: target.bundleIdentifier,
                matchingBundleURLs: [location.appURL(for: target)]
            )
        }
        try replaceInstalledApp(with: extracted, at: location.appURL(for: target))

        return version
    }

    private func replaceInstalledApp(with extracted: URL, at destination: URL) throws {
        let backup = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).backup-\(UUID().uuidString)", isDirectory: true)
        let hadExistingApp = fileManager.fileExists(atPath: destination.path)

        do {
            if hadExistingApp {
                try fileManager.moveItem(at: destination, to: backup)
            }

            try fileManager.moveItem(at: extracted, to: destination)

            if hadExistingApp {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            if hadExistingApp,
               !fileManager.fileExists(atPath: destination.path),
               fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw ManagedAppInstallerError.moveFailed(error.localizedDescription)
        }
    }

    private func runExtract(zipURL: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ManagedAppInstallerError.extractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static let minimumDiskSpace: Int64 = 4_000_000_000

    private func checkDiskSpace() throws {
        let attrs = try fileManager.attributesOfFileSystem(forPath: NSTemporaryDirectory())
        guard let freeSpace = attrs[.systemFreeSize] as? Int64 else { return }
        if freeSpace < Self.minimumDiskSpace {
            throw ManagedAppInstallerError.insufficientDiskSpace(available: freeSpace, required: Self.minimumDiskSpace)
        }
    }

    private func runStripQuarantine(at file: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", file.path]
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}

private final class LatestSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = DownloadProgressSnapshot(
        fraction: nil,
        bytesReceived: 0,
        totalBytesExpected: nil,
        bytesPerSecond: nil
    )

    func set(_ snapshot: DownloadProgressSnapshot) {
        lock.withLock { self.snapshot = snapshot }
    }

    func get() -> DownloadProgressSnapshot {
        lock.withLock { snapshot }
    }
}

struct CodesignVerifier: SignatureVerifying {
    func verify(appBundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-v", appBundle.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ManagedAppInstallerError.signatureInvalid(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

struct URLSessionAssetDownloader: AssetDownloading {
    let configuration: URLSessionConfiguration
    private let fileManager: FileManager

    init(configuration: URLSessionConfiguration = .default, fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    func download(
        from url: URL,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> URL {
        let destination = fileManager.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString).zip")
        let delegate = DownloadProgressDelegate(destination: destination, fileManager: fileManager, progress: progress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await delegate.download(from: url, session: session)
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let fileManager: FileManager
    private let progress: @Sendable (DownloadProgressSnapshot) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var tracker = DownloadProgressTracker()
    private var lastProgressReport = Date.distantPast

    init(
        destination: URL,
        fileManager: FileManager,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) {
        self.destination = destination
        self.fileManager = fileManager
        self.progress = progress
    }

    func download(from url: URL, session: URLSession) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
            }
            progress(
                DownloadProgressSnapshot(
                    fraction: nil,
                    bytesReceived: 0,
                    totalBytesExpected: nil,
                    bytesPerSecond: nil
                )
            )
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let (snapshot, shouldReport) = lock.withLock {
            let s = tracker.record(
                bytesReceived: totalBytesWritten,
                totalBytesExpected: totalBytesExpectedToWrite
            )
            let now = Date()
            guard now.timeIntervalSince(lastProgressReport) >= 0.1 else {
                return (s, false)
            }
            lastProgressReport = now
            return (s, true)
        }
        if shouldReport {
            progress(snapshot)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            resume(with: .failure(ManagedAppInstallerError.extractionFailed("HTTP \((downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1)")))
            return
        }
        do {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: location, to: destination)
            resume(with: .success(destination))
        } catch {
            resume(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            resume(with: .failure(error))
        }
    }

    private func resume(with result: Result<URL, Error>) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }

        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}
