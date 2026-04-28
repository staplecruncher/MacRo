import AppKit
import Foundation
import XCTest
@testable import MacRo

final class LaunchProtocolServiceTests: XCTestCase {
    func testRoutedLaunchRequestParsesStudioDocumentFileURLFromOpenURLPath() {
        let fileURL = URL(fileURLWithPath: "/tmp/test.rbxl")

        XCTAssertEqual(RoutedLaunchRequest.parse(url: fileURL), .studioDocument(fileURL))
    }

    func testRoutedLaunchRequestParsesStudioPlaceURLSeparatelyFromStudioAuth() throws {
        let url = try XCTUnwrap(URL(string: "roblox-studio:1+launchmode:play+gameinfo:test"))

        XCTAssertEqual(RoutedLaunchRequest.parse(url: url), .robloxStudioPlace(url))
    }

    func testRobloxURLForwardingUsesSpecificApplicationURL() async throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root)
        try makeFakeApp(location: location, target: .roblox)
        let workspace = RecordingWorkspaceLauncher()
        let launcher = LaunchService(location: location, workspace: workspace, shouldProbeLaunchedProcess: false)
        let url = try XCTUnwrap(URL(string: "roblox-player:1+launchmode:play+gameinfo:test"))

        try await launcher.forwardRobloxPlayerURL(url)

        XCTAssertEqual(workspace.openedURLs, [url])
        XCTAssertEqual(workspace.applicationURL, location.appURL(for: .roblox))
    }

    func testDirectLaunchUsesTargetApplicationURL() async throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root)
        try makeFakeApp(location: location, target: .studio)
        let workspace = RecordingWorkspaceLauncher()
        let launcher = LaunchService(location: location, workspace: workspace, shouldProbeLaunchedProcess: false)

        try await launcher.launch(.studio)

        XCTAssertEqual(workspace.launchedApplicationURL, location.appURL(for: .studio))
    }

    func testProtocolRepairCallsRegistrarAndVerifies() {
        let registrar = RecordingProtocolRegistrar(currentHandler: "com.roblox.Roblox")
        let service = ProtocolHandlerService(registrar: registrar, bundleIdentifier: "com.staplecruncher.MacRo")

        XCTAssertTrue(service.repairRegistrationIfNeeded())
        let touchedSchemes = registrar.setSchemeCalls.map(\.0)
        XCTAssertTrue(touchedSchemes.contains("roblox-player"))
        XCTAssertTrue(touchedSchemes.contains("roblox-studio-auth"))
        let touchedTypes = registrar.setContentTypeCalls.map(\.0)
        XCTAssertTrue(touchedTypes.contains("com.Roblox.RobloxStudio-document"))
    }

    func testStudioAuthURLForwardingUsesStudioApplicationURL() async throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root)
        try makeFakeApp(location: location, target: .studio)
        let workspace = RecordingWorkspaceLauncher()
        let launcher = LaunchService(location: location, workspace: workspace, shouldProbeLaunchedProcess: false)
        let url = try XCTUnwrap(URL(string: "roblox-studio-auth:foo"))

        try await launcher.forward(.robloxStudioAuth(url))

        XCTAssertEqual(workspace.openedURLs, [url])
        XCTAssertEqual(workspace.applicationURL, location.appURL(for: .studio))
    }

    func testStudioPlaceURLForwardingUsesStudioApplicationURL() async throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root)
        try makeFakeApp(location: location, target: .studio)
        let workspace = RecordingWorkspaceLauncher()
        let launcher = LaunchService(location: location, workspace: workspace, shouldProbeLaunchedProcess: false)
        let url = try XCTUnwrap(URL(string: "roblox-studio:1+launchmode:play+gameinfo:test"))

        try await launcher.forward(.robloxStudioPlace(url))

        XCTAssertEqual(workspace.launchedApplicationURL, location.appURL(for: .studio))
        XCTAssertEqual(workspace.launchedArguments, [url.absoluteString])
    }

    func testStudioDocumentForwardingUsesStudioApplicationURL() async throws {
        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root)
        try makeFakeApp(location: location, target: .studio)
        let workspace = RecordingWorkspaceLauncher()
        let launcher = LaunchService(location: location, workspace: workspace, shouldProbeLaunchedProcess: false)
        let fileURL = URL(fileURLWithPath: "/tmp/test.rbxl")

        try await launcher.forward(.studioDocument(fileURL))

        XCTAssertEqual(workspace.openedFiles, [fileURL])
        XCTAssertEqual(workspace.openedURLs, [])
        XCTAssertEqual(workspace.applicationURL, location.appURL(for: .studio))
    }

    private func makeFakeApp(location: ManagedAppLocation, target: TargetKind) throws {
        let exec = location.executableURL(for: target)
        try FileManager.default.createDirectory(at: exec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: exec)
    }
}

private final class RecordingWorkspaceLauncher: WorkspaceLaunching {
    var openedURLs: [URL] = []
    var openedFiles: [URL] = []
    var applicationURL: URL?
    var launchedApplicationURL: URL?
    var launchedArguments: [String] = []

    func openApplication(at applicationURL: URL) async throws -> NSRunningApplication {
        launchedApplicationURL = applicationURL
        return NSRunningApplication.current
    }

    func openApplication(at applicationURL: URL, arguments: [String]) async throws -> NSRunningApplication {
        launchedApplicationURL = applicationURL
        launchedArguments = arguments
        return NSRunningApplication.current
    }

    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws -> NSRunningApplication {
        openedURLs = urls
        self.applicationURL = applicationURL
        return NSRunningApplication.current
    }

    func openFiles(_ urls: [URL], withApplicationAt applicationURL: URL) async throws -> NSRunningApplication {
        openedFiles = urls
        self.applicationURL = applicationURL
        return NSRunningApplication.current
    }
}

private final class RecordingProtocolRegistrar: ProtocolRegistering {
    var schemeHandlers: [String: String] = [:]
    var contentTypeHandlers: [String: String] = [:]
    var setSchemeCalls: [(String, String)] = []
    var setContentTypeCalls: [(String, String)] = []

    init(currentHandler: String?) {
        if let currentHandler {
            schemeHandlers["roblox-player"] = currentHandler
        }
    }

    func defaultHandler(for scheme: String) -> String? {
        schemeHandlers[scheme]
    }

    func setDefaultHandler(_ bundleIdentifier: String, for scheme: String) -> Bool {
        setSchemeCalls.append((scheme, bundleIdentifier))
        schemeHandlers[scheme] = bundleIdentifier
        return true
    }

    func defaultHandler(forContentType contentType: String) -> String? {
        contentTypeHandlers[contentType]
    }

    func setDefaultHandler(_ bundleIdentifier: String, forContentType contentType: String) -> Bool {
        setContentTypeCalls.append((contentType, bundleIdentifier))
        contentTypeHandlers[contentType] = bundleIdentifier
        return true
    }
}
