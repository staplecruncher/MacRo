import AppKit
import Foundation

protocol WorkspaceLaunching {
    func openApplication(at applicationURL: URL) async throws -> NSRunningApplication
    func openApplication(at applicationURL: URL, arguments: [String]) async throws -> NSRunningApplication
    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws -> NSRunningApplication
    func openFiles(_ urls: [URL], withApplicationAt applicationURL: URL) async throws -> NSRunningApplication
}

struct AppKitWorkspaceLauncher: WorkspaceLaunching {
    func openApplication(at applicationURL: URL) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        return try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }

    func openApplication(at applicationURL: URL, arguments: [String]) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        return try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }

    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws -> NSRunningApplication {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", applicationURL.path] + urls.map(\.absoluteString)
            let errPipe = Pipe()
            process.standardError = errPipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw LaunchServiceError.fileOpenFailed(urls.first ?? applicationURL, message)
            }
        }.value

        return try await waitForRunningApplication(at: applicationURL)
    }

    func openFiles(_ urls: [URL], withApplicationAt applicationURL: URL) async throws -> NSRunningApplication {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", applicationURL.path] + urls.map(\.path)
            let errPipe = Pipe()
            process.standardError = errPipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw LaunchServiceError.fileOpenFailed(urls.first ?? applicationURL, message)
            }
        }.value

        return try await waitForRunningApplication(at: applicationURL)
    }

    private func waitForRunningApplication(at applicationURL: URL) async throws -> NSRunningApplication {
        for _ in 0..<10 {
            if let app = runningApplication(at: applicationURL) {
                return app
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw LaunchServiceError.applicationDidNotLaunch(applicationURL)
    }

    private func runningApplication(at applicationURL: URL) -> NSRunningApplication? {
        let expectedPath = applicationURL.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first { app in
            app.bundleURL?.standardizedFileURL.path == expectedPath
        }
    }
}

enum LaunchServiceError: Error, LocalizedError {
    case targetMissing(TargetKind)
    case invalidRobloxPlayerURL(URL)
    case launchedProcessExitedImmediately(TargetKind)
    case fileOpenFailed(URL, String)
    case applicationDidNotLaunch(URL)

    var errorDescription: String? {
        switch self {
        case .targetMissing(let target):
            "\(target.displayName) is not installed."
        case .invalidRobloxPlayerURL(let url):
            "Unsupported Roblox launch URL: \(url.absoluteString)"
        case .launchedProcessExitedImmediately(let target):
            "\(target.displayName) exited immediately after launch. If macOS asked to install Rosetta, please approve it and try again."
        case .fileOpenFailed(let url, let message):
            "Could not open \(url.lastPathComponent): \(message)"
        case .applicationDidNotLaunch(let url):
            "Could not confirm launch of \(url.lastPathComponent)."
        }
    }
}

struct LaunchService: @unchecked Sendable {
    let location: ManagedAppLocation
    let workspace: WorkspaceLaunching
    let shouldProbeLaunchedProcess: Bool

    init(
        location: ManagedAppLocation = ManagedAppLocation(),
        workspace: WorkspaceLaunching = AppKitWorkspaceLauncher(),
        shouldProbeLaunchedProcess: Bool = true
    ) {
        self.location = location
        self.workspace = workspace
        self.shouldProbeLaunchedProcess = shouldProbeLaunchedProcess
    }

    func launch(_ target: TargetKind) async throws {
        guard case .ready = location.state(for: target) else {
            throw LaunchServiceError.targetMissing(target)
        }
        let app = try await workspace.openApplication(at: location.appURL(for: target))
        try await probeProcess(app, target: target)
    }

    func forwardRobloxPlayerURL(_ url: URL) async throws {
        guard url.scheme == AppConstants.robloxPlayerScheme else {
            throw LaunchServiceError.invalidRobloxPlayerURL(url)
        }
        try await forward(.robloxPlayer(url))
    }

    func forward(_ request: RoutedLaunchRequest) async throws {
        let target = request.target
        guard case .ready = location.state(for: target) else {
            throw LaunchServiceError.targetMissing(target)
        }
        let app: NSRunningApplication
        switch request {
        case .studioDocument:
            app = try await workspace.openFiles([request.url], withApplicationAt: location.appURL(for: target))
        case .robloxStudioPlace:
            app = try await workspace.openApplication(
                at: location.appURL(for: target),
                arguments: [request.url.absoluteString]
            )
        case .robloxPlayer, .robloxStudioAuth:
            app = try await workspace.openURLs([request.url], withApplicationAt: location.appURL(for: target))
        }
        try await probeProcess(app, target: target)
    }

    private func probeProcess(_ app: NSRunningApplication, target: TargetKind) async throws {
        guard shouldProbeLaunchedProcess else { return }
        try await Task.sleep(for: .seconds(1))
        if app.isTerminated {
            throw LaunchServiceError.launchedProcessExitedImmediately(target)
        }
    }
}
