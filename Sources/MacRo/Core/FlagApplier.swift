import Foundation

enum ReplacementDecision: Equatable {
    case ask
    case replace
}

enum ApplyResult: Equatable {
    case applied
    case needsReplacementDecision(URL)
}

enum FlagApplierError: Error, LocalizedError {
    case targetMissing(TargetKind)
    case verificationFailed(URL)
    case bundleSigningFailed(String)
    case bundleRepairFailed(String)

    var errorDescription: String? {
        switch self {
        case .targetMissing(let target):
            "\(target.displayName) is not installed."
        case .verificationFailed(let url):
            "Could not verify generated flags at \(url.path)."
        case .bundleSigningFailed(let message):
            "Could not prepare the modified Roblox bundle for launch. (\(message))"
        case .bundleRepairFailed(let message):
            "Could not repair the managed Roblox bundle. (\(message))"
        }
    }
}

protocol BundleSigning: Sendable {
    func signAdHoc(appBundle: URL) throws
}

struct FlagApplier: @unchecked Sendable {
    let location: ManagedAppLocation
    let backupRoot: URL
    let bundleSigner: BundleSigning
    private let fileManager: FileManager

    init(
        location: ManagedAppLocation = ManagedAppLocation(),
        backupRoot: URL = FlagStore.defaultRootDirectory().appendingPathComponent("Backups", isDirectory: true),
        bundleSigner: BundleSigning = CodesignBundleSigner(),
        fileManager: FileManager = .default
    ) {
        self.location = location
        self.backupRoot = backupRoot
        self.bundleSigner = bundleSigner
        self.fileManager = fileManager
    }

    func apply(data: Data, to target: TargetKind, replacementDecision: ReplacementDecision) async throws -> ApplyResult {
        guard case .ready = location.state(for: target) else {
            throw FlagApplierError.targetMissing(target)
        }

        let destination = location.clientAppSettingsURL(for: target)
        let desiredHash = FileHashing.sha256Hex(data: data)
        var manifest = try loadManifest()
        let existingHash = fileManager.fileExists(atPath: destination.path)
            ? try FileHashing.sha256Hex(of: destination)
            : nil
        let existingFileIsManaged = existingHash == desiredHash || existingHash == manifest[target.rawValue]

        if existingHash == desiredHash {
            return .applied
        }

        if existingHash != nil, !existingFileIsManaged {
            if replacementDecision == .ask {
                return .needsReplacementDecision(destination)
            }
            try backupExistingFile(destination, target: target)
        }

        try await Task.detached {
            try self.writeFlagsAndPrepareBundle(data: data, desiredHash: desiredHash, destination: destination, target: target)
        }.value

        manifest[target.rawValue] = desiredHash
        try saveManifest(manifest)

        return .applied
    }

    private func writeFlagsAndPrepareBundle(data: Data, desiredHash: String, destination: URL, target: TargetKind) throws {
        do {
            try writeFlags(data, desiredHash: desiredHash, destination: destination)
            try signBundleIfNeeded(for: target, appBundle: location.appURL(for: target))
        } catch {
            try prepareBundleViaStagedCopy(data: data, desiredHash: desiredHash, target: target)
        }
    }

    private func writeFlags(_ data: Data, desiredHash: String, destination: URL) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [.atomic])

        let writtenHash = try FileHashing.sha256Hex(of: destination)
        guard writtenHash == desiredHash else {
            throw FlagApplierError.verificationFailed(destination)
        }
    }

    private func prepareBundleViaStagedCopy(data: Data, desiredHash: String, target: TargetKind) throws {
        let originalApp = location.appURL(for: target)
        let stagingRoot = location.applicationsDirectory
            .appendingPathComponent(".macro-\(UUID().uuidString)", isDirectory: true)
        let stagedApp = stagingRoot.appendingPathComponent(target.appBundleName, isDirectory: true)
        let backupApp = location.applicationsDirectory
            .appendingPathComponent(".\(target.appBundleName)-backup-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingRoot)
            try? fileManager.removeItem(at: backupApp)
        }

        try copyBundle(from: originalApp, to: stagedApp)
        let stagedLocation = ManagedAppLocation(applicationsDirectory: stagingRoot, fileManager: fileManager)
        let stagedDestination = stagedLocation.clientAppSettingsURL(for: target)
        try writeFlags(data, desiredHash: desiredHash, destination: stagedDestination)
        try signBundleIfNeeded(for: target, appBundle: stagedApp)

        do {
            try fileManager.moveItem(at: originalApp, to: backupApp)
            try fileManager.moveItem(at: stagedApp, to: originalApp)
        } catch {
            if !fileManager.fileExists(atPath: originalApp.path), fileManager.fileExists(atPath: backupApp.path) {
                try? fileManager.moveItem(at: backupApp, to: originalApp)
            }
            throw FlagApplierError.bundleRepairFailed(error.localizedDescription)
        }
    }

    private func copyBundle(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path, destination.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FlagApplierError.bundleRepairFailed(message)
        }
    }

    private func signBundleIfNeeded(for target: TargetKind, appBundle: URL) throws {
        guard target.requiresBundleSigningAfterFlagEdit else {
            return
        }
        try bundleSigner.signAdHoc(appBundle: appBundle)
    }

    private func backupExistingFile(_ url: URL, target: TargetKind) throws {
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let backupURL = backupRoot.appendingPathComponent("\(target.rawValue)-ClientAppSettings-\(UUID().uuidString).json")
        try fileManager.copyItem(at: url, to: backupURL)
    }

    private func manifestURL() -> URL {
        backupRoot.deletingLastPathComponent().appendingPathComponent("generated-manifest.json", isDirectory: false)
    }

    private func loadManifest() throws -> [String: String] {
        let url = manifestURL()
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func saveManifest(_ manifest: [String: String]) throws {
        let url = manifestURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }
}

struct CodesignBundleSigner: BundleSigning {
    func signAdHoc(appBundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", appBundle.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FlagApplierError.bundleSigningFailed(message)
        }
    }
}
