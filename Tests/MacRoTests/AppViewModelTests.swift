import Foundation
import XCTest
@testable import MacRo

@MainActor
final class AppViewModelTests: XCTestCase {
    func testLoadsSeparateRowsForTargets() throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root)
        try store.saveRows([FlagRow(name: "RobloxFlag", rawValue: "true")], for: .roblox)
        try store.saveRows([FlagRow(name: "StudioFlag", rawValue: "false")], for: .studio)

        let model = try AppViewModel.makeForTests(store: store, installCoordinator: AlwaysInstalledCoordinator())

        XCTAssertEqual(model.rows(for: .roblox).map(\.name), ["RobloxFlag"])
        XCTAssertEqual(model.rows(for: .studio).map(\.name), ["StudioFlag"])
    }

    func testNewRobloxTargetStartsWithVisibleDefaultDPIRow() throws {
        let root = try temporaryDirectory()
        let model = try AppViewModel.makeForTests(
            store: FlagStore(rootDirectory: root),
            installCoordinator: AlwaysInstalledCoordinator()
        )

        XCTAssertEqual(model.rows(for: .roblox).map(\.name), ["DFFlagDisableDPIScale"])
        XCTAssertEqual(model.rows(for: .roblox).map(\.rawValue), ["true"])
        XCTAssertEqual(model.rows(for: .roblox).map(\.isEnabled), [true])
    }

    func testNewStudioTargetStartsWithVisibleDefaultDPIRow() throws {
        let root = try temporaryDirectory()
        let model = try AppViewModel.makeForTests(
            store: FlagStore(rootDirectory: root),
            installCoordinator: AlwaysInstalledCoordinator()
        )

        XCTAssertEqual(model.rows(for: .studio).map(\.name), ["DFFlagDisableDPIScale"])
        XCTAssertEqual(model.rows(for: .studio).map(\.rawValue), ["true"])
        XCTAssertEqual(model.rows(for: .studio).map(\.isEnabled), [true])
    }

    func testValidationMessageAppearsForDuplicateEnabledRows() throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root)
        let model = try AppViewModel.makeForTests(store: store, installCoordinator: AlwaysInstalledCoordinator())
        model.setRows([
            FlagRow(name: "FFlagSame", rawValue: "true"),
            FlagRow(name: "FFlagSame", rawValue: "false")
        ], for: .roblox)

        XCTAssertTrue(model.validationSummary(for: .roblox).contains("Duplicate enabled flag name: FFlagSame"))
    }

    func testEditingRowsPersistsImmediatelyWithoutLaunch() throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root)
        let model = try AppViewModel.makeForTests(store: store, installCoordinator: AlwaysInstalledCoordinator())

        var edited = model.bindingRows(for: .roblox).wrappedValue
        edited[0].rawValue = "false"
        edited.append(FlagRow(name: "FFlagNewLocal", rawValue: "123", isEnabled: true))
        model.bindingRows(for: .roblox).wrappedValue = edited

        let saved = try store.loadRows(for: .roblox)
        XCTAssertEqual(saved.map(\.name), ["DFFlagDisableDPIScale", "FFlagNewLocal"])
        XCTAssertEqual(saved.map(\.rawValue), ["false", "123"])
    }

    func testUpdatePromptCanBePresentedAndCleared() throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root)
        let model = try AppViewModel.makeForTests(store: store, installCoordinator: AlwaysInstalledCoordinator())

        model.presentRelaunchPrompt(for: .roblox)

        XCTAssertEqual(model.pendingRelaunchTarget, .roblox)
        XCTAssertTrue(model.statusMessage.contains("Roblox updated"))

        model.clearRelaunchPrompt()

        XCTAssertNil(model.pendingRelaunchTarget)
    }

    func testSaveAppliesFlagsWhenManagedAppIsReadyWithoutLaunching() async throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let apps = root.appendingPathComponent("Applications", isDirectory: true)
        let location = ManagedAppLocation(applicationsDirectory: apps)
        try makeFakeApp(location: location, target: .roblox)
        let applier = FlagApplier(
            location: location,
            backupRoot: root.appendingPathComponent("backups", isDirectory: true),
            bundleSigner: RecordingBundleSigner()
        )
        let launcher = RecordingWorkspaceLauncher()
        let model = try AppViewModel.makeForTests(
            store: store,
            applier: applier,
            launcher: LaunchService(location: location, workspace: launcher),
            location: location,
            installCoordinator: AlwaysInstalledCoordinator()
        )
        model.setRows([FlagRow(name: "FFlagSaved", rawValue: "true")], for: .roblox)

        await model.performSaveRows(for: .roblox)

        let written = try Data(contentsOf: location.clientAppSettingsURL(for: .roblox))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(object["FFlagSaved"] as? Bool, true)
        XCTAssertNil(launcher.launchedApplicationURL)
        XCTAssertTrue(model.statusMessage.contains("Saved and applied"))
    }

    func testRoutedLaunchConsumesExternalLaunchStateAfterForwarding() async throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try makeFakeApp(location: location, target: .studio)
        let applier = FlagApplier(
            location: location,
            backupRoot: root.appendingPathComponent("backups", isDirectory: true),
            bundleSigner: RecordingBundleSigner()
        )
        let launcher = RecordingWorkspaceLauncher()
        let forwarded = expectation(description: "forwarded routed launch")
        launcher.didOpen = { forwarded.fulfill() }
        let model = try AppViewModel.makeForTests(
            store: store,
            applier: applier,
            launcher: LaunchService(location: location, workspace: launcher, shouldProbeLaunchedProcess: false),
            location: location,
            installCoordinator: AlwaysInstalledCoordinator()
        )
        AppRuntime.shared.isHandlingExternalLaunch = true
        defer { AppRuntime.shared.isHandlingExternalLaunch = false }

        model.handleRoutedLaunch(.studioDocument(URL(fileURLWithPath: "/tmp/test.rbxl")))

        await fulfillment(of: [forwarded], timeout: 1.0)
        XCTAssertFalse(AppRuntime.shared.isHandlingExternalLaunch)
    }

    func testRoutedLaunchDoesNotMarkWindowForHideWhenWindowWasAlreadyVisible() async throws {
        AppRuntime.shared.isHandlingExternalLaunch = false
        AppRuntime.shared.shouldRevealMainWindow = true
        AppRuntime.shared.externalLaunchHadVisibleWindow = true

        let root = try temporaryDirectory()
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try makeFakeApp(location: location, target: .studio)
        let applier = FlagApplier(
            location: location,
            backupRoot: root.appendingPathComponent("backups", isDirectory: true),
            bundleSigner: RecordingBundleSigner()
        )
        let launcher = RecordingWorkspaceLauncher()
        let forwarded = expectation(description: "forwarded routed launch")
        launcher.didOpen = { forwarded.fulfill() }

        let model = try AppViewModel.makeForTests(
            store: FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true)),
            applier: applier,
            launcher: LaunchService(location: location, workspace: launcher, shouldProbeLaunchedProcess: false),
            location: location,
            installCoordinator: AlwaysInstalledCoordinator()
        )

        model.handleRoutedLaunch(.studioDocument(URL(fileURLWithPath: "/tmp/test.rbxl")))

        await fulfillment(of: [forwarded], timeout: 1.0)
        XCTAssertTrue(AppRuntime.shared.shouldRevealMainWindow)
    }

    func testRoutedLaunchSavesAndAppliesFlagsBeforeForwarding() async throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try makeFakeApp(location: location, target: .studio)
        let applier = FlagApplier(
            location: location,
            backupRoot: root.appendingPathComponent("backups", isDirectory: true),
            bundleSigner: RecordingBundleSigner()
        )
        let launcher = RecordingWorkspaceLauncher()
        let forwarded = expectation(description: "forwarded")
        launcher.didOpen = { forwarded.fulfill() }

        let model = try AppViewModel.makeForTests(
            store: store,
            applier: applier,
            launcher: LaunchService(location: location, workspace: launcher, shouldProbeLaunchedProcess: false),
            location: location,
            installCoordinator: AlwaysInstalledCoordinator()
        )
        model.setRows([FlagRow(name: "FFlagStudioTest", rawValue: "true")], for: .studio)

        model.handleRoutedLaunch(.studioDocument(URL(fileURLWithPath: "/tmp/test.rbxl")))

        await fulfillment(of: [forwarded], timeout: 1.0)
        let written = try Data(contentsOf: location.clientAppSettingsURL(for: .studio))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(object["FFlagStudioTest"] as? Bool, true)
        XCTAssertEqual(try store.loadRows(for: .studio).map(\.name), ["FFlagStudioTest"])
    }

    func testRoutedLaunchMonitorsForUpdatesAndPromptsForRelaunch() async throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try makeFakeApp(location: location, target: .studio)
        let applier = FlagApplier(
            location: location,
            backupRoot: root.appendingPathComponent("backups", isDirectory: true),
            bundleSigner: RecordingBundleSigner()
        )
        let launcher = RecordingWorkspaceLauncher()
        let forwarded = expectation(description: "forwarded")
        launcher.didOpen = {
            try? FileManager.default.removeItem(at: location.clientAppSettingsURL(for: .studio))
            forwarded.fulfill()
        }

        let model = try AppViewModel.makeForTests(
            store: store,
            applier: applier,
            launcher: LaunchService(location: location, workspace: launcher, shouldProbeLaunchedProcess: false),
            updateMonitor: UpdateMonitor(location: location),
            updateMonitorTimeout: Duration.seconds(60),
            location: location,
            installCoordinator: AlwaysInstalledCoordinator()
        )
        model.setRows([FlagRow(name: "FFlagStudioTest", rawValue: "true")], for: TargetKind.studio)

        model.handleRoutedLaunch(RoutedLaunchRequest.studioDocument(URL(fileURLWithPath: "/tmp/test.rbxl")))

        await fulfillment(of: [forwarded], timeout: 1.0)
        for _ in 0..<100 {
            if model.pendingRelaunchTarget == TargetKind.studio {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.pendingRelaunchTarget, TargetKind.studio)
        XCTAssertTrue(model.statusMessage.contains("updated or replaced"))
    }

    func testRoutedLaunchKeepsRuntimeBusyWhileMonitoringForUpdates() async throws {
        AppRuntime.shared.resetTransientStateForTests()
        defer { AppRuntime.shared.resetTransientStateForTests() }

        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try makeFakeApp(location: location, target: .studio)
        let applier = FlagApplier(
            location: location,
            backupRoot: root.appendingPathComponent("backups", isDirectory: true),
            bundleSigner: RecordingBundleSigner()
        )
        let launcher = RecordingWorkspaceLauncher()
        let forwarded = expectation(description: "forwarded")
        launcher.didOpen = { forwarded.fulfill() }
        let model = try AppViewModel.makeForTests(
            store: store,
            applier: applier,
            launcher: LaunchService(location: location, workspace: launcher, shouldProbeLaunchedProcess: false),
            updateMonitor: UpdateMonitor(location: location),
            updateMonitorTimeout: .milliseconds(250),
            location: location,
            installCoordinator: AlwaysInstalledCoordinator()
        )

        AppRuntime.shared.beginExternalLaunch(mainWindowWasVisible: false)
        model.handleRoutedLaunch(.studioDocument(URL(fileURLWithPath: "/tmp/test.rbxl")))

        await fulfillment(of: [forwarded], timeout: 1.0)
        for _ in 0..<100 {
            if AppRuntime.shared.hasActiveBackgroundActivity {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(AppRuntime.shared.hasActiveBackgroundActivity)
        XCTAssertFalse(AppRuntime.shared.isHandlingExternalLaunch)
    }

    func testImmediateRepeatedLaunchOnlyStartsOneOperation() async throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let coordinator = CountingInstallCoordinator()
        let model = try AppViewModel.makeForTests(
            store: store,
            installCoordinator: coordinator
        )

        model.applyAndLaunch(.roblox)
        model.applyAndLaunch(.roblox)

        for _ in 0..<100 {
            if coordinator.ensureInstalledCallCount > 0 {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(coordinator.ensureInstalledCallCount, 1)
    }

    func testBrokenTargetIsRepairableAndStillUninstallable() throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let location = ManagedAppLocation(applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true))
        try FileManager.default.createDirectory(at: location.appURL(for: .studio), withIntermediateDirectories: true)
        let model = try AppViewModel.makeForTests(
            store: store,
            location: location,
            installCoordinator: AlwaysInstalledCoordinator()
        )

        XCTAssertFalse(model.isInstalled(.studio))
        XCTAssertTrue(model.canUninstall(.studio))
    }

    func testUninstallRemovesInstalledManagedAppAndKeepsSavedRows() throws {
        let root = try temporaryDirectory()
        let store = FlagStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        let apps = root.appendingPathComponent("ManagedApps", isDirectory: true)
        let legacyApps = root.appendingPathComponent("Applications", isDirectory: true)
        let location = ManagedAppLocation(applicationsDirectory: apps, legacyApplicationsDirectory: legacyApps)
        try makeFakeApp(location: location, target: .studio)
        try FileManager.default.createDirectory(at: location.legacyAppURL(for: .studio), withIntermediateDirectories: true)
        try store.saveRows([FlagRow(name: "FFlagKeep", rawValue: "true")], for: .studio)
        let versionStore = ManagedAppVersionStore(rootDirectory: root.appendingPathComponent("store", isDirectory: true))
        try versionStore.saveVersionUpload("version-studio", for: .studio)
        let uninstaller = ManagedAppUninstaller(
            location: location,
            processTerminator: RecordingProcessTerminator(),
            versionStore: versionStore
        )
        let model = try AppViewModel.makeForTests(
            store: store,
            location: location,
            uninstaller: uninstaller,
            installCoordinator: AlwaysInstalledCoordinator()
        )

        XCTAssertTrue(model.isInstalled(.studio))

        model.uninstall(.studio)

        XCTAssertFalse(model.isInstalled(.studio))
        XCTAssertEqual(try store.loadRows(for: .studio).map(\.name), ["FFlagKeep"])
        XCTAssertNil(try versionStore.loadVersionUpload(for: .studio))
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.legacyAppURL(for: .studio).path))
        XCTAssertTrue(model.statusMessage.contains("Uninstalled Roblox Studio"))
    }

    private func makeFakeApp(location: ManagedAppLocation, target: TargetKind) throws {
        let exec = location.executableURL(for: target)
        try FileManager.default.createDirectory(at: exec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: exec)
        let contents = exec.deletingLastPathComponent().deletingLastPathComponent()
        let plist: [String: Any] = ["CFBundleShortVersionString": "1.0"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}

private final class AlwaysInstalledCoordinator: InstallCoordinator {
    override func ensureInstalled(_ target: TargetKind, location: ManagedAppLocation) async -> Bool {
        true
    }
}

private final class CountingInstallCoordinator: InstallCoordinator {
    private(set) var ensureInstalledCallCount = 0

    override func ensureInstalled(_ target: TargetKind, location: ManagedAppLocation) async -> Bool {
        ensureInstalledCallCount += 1
        try? await Task.sleep(for: .milliseconds(50))
        return true
    }
}

private final class RecordingBundleSigner: BundleSigning, @unchecked Sendable {
    func signAdHoc(appBundle: URL) throws {}
}

private final class RecordingWorkspaceLauncher: WorkspaceLaunching {
    var launchedApplicationURL: URL?
    var didOpen: (() -> Void)?

    func openApplication(at applicationURL: URL) async throws -> NSRunningApplication {
        launchedApplicationURL = applicationURL
        didOpen?()
        return NSRunningApplication.current
    }

    func openApplication(at applicationURL: URL, arguments: [String]) async throws -> NSRunningApplication {
        launchedApplicationURL = applicationURL
        didOpen?()
        return NSRunningApplication.current
    }

    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws -> NSRunningApplication {
        launchedApplicationURL = applicationURL
        didOpen?()
        return NSRunningApplication.current
    }

    func openFiles(_ urls: [URL], withApplicationAt applicationURL: URL) async throws -> NSRunningApplication {
        launchedApplicationURL = applicationURL
        didOpen?()
        return NSRunningApplication.current
    }
}

private final class RecordingProcessTerminator: ManagedAppProcessTerminating {
    var terminatedRequests: [(bundleIdentifier: String, bundleURLs: [URL])] = []

    func terminateRunningApplications(bundleIdentifier: String, matchingBundleURLs bundleURLs: [URL]) {
        terminatedRequests.append((bundleIdentifier, bundleURLs))
    }
}
