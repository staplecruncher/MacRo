import Foundation
import SwiftUI

struct PendingReplacement: Equatable, Identifiable {
    let id = UUID()
    let target: TargetKind
    let shouldLaunchAfterReplacement: Bool
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedTarget: TargetKind = .roblox
    @Published private var robloxRows: [FlagRow]
    @Published private var studioRows: [FlagRow]
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var pendingRelaunchTarget: TargetKind?
    @Published var pendingReplacement: PendingReplacement?
    @Published var isApplying: Bool = false
    let installCoordinator: InstallCoordinator

    private let store: FlagStore
    private let applier: FlagApplier
    private let launcher: LaunchService
    private let protocolHandler: ProtocolHandlerService
    private let updateMonitor: UpdateMonitor
    private let updateMonitorTimeout: Duration
    private let location: ManagedAppLocation
    private let uninstaller: ManagedAppUninstaller
    private var pendingRoutedLaunchRequests: [TargetKind: RoutedLaunchRequest] = [:]

    init(
        store: FlagStore = FlagStore(),
        applier: FlagApplier = FlagApplier(),
        launcher: LaunchService = LaunchService(),
        protocolHandler: ProtocolHandlerService = ProtocolHandlerService(),
        updateMonitor: UpdateMonitor = UpdateMonitor(),
        updateMonitorTimeout: Duration = .seconds(60),
        location: ManagedAppLocation = ManagedAppLocation(),
        uninstaller: ManagedAppUninstaller? = nil,
        installCoordinator: InstallCoordinator = InstallCoordinator()
    ) throws {
        self.store = store
        self.applier = applier
        self.launcher = launcher
        self.protocolHandler = protocolHandler
        self.updateMonitor = updateMonitor
        self.updateMonitorTimeout = updateMonitorTimeout
        self.location = location
        self.uninstaller = uninstaller ?? ManagedAppUninstaller(location: location)
        self.installCoordinator = installCoordinator
        self.robloxRows = try store.loadRows(for: .roblox)
        self.studioRows = try store.loadRows(for: .studio)
    }

    static func makeForTests(
        store: FlagStore,
        applier: FlagApplier = FlagApplier(),
        launcher: LaunchService = LaunchService(),
        updateMonitor: UpdateMonitor? = nil,
        updateMonitorTimeout: Duration = .seconds(60),
        location: ManagedAppLocation = ManagedAppLocation(),
        uninstaller: ManagedAppUninstaller? = nil,
        installCoordinator: InstallCoordinator = InstallCoordinator()
    ) throws -> AppViewModel {
        try AppViewModel(
            store: store,
            applier: applier,
            launcher: launcher,
            protocolHandler: ProtocolHandlerService(registrar: InMemoryProtocolRegistrar(), bundleIdentifier: AppConstants.bundleIdentifier),
            updateMonitor: updateMonitor ?? UpdateMonitor(location: location),
            updateMonitorTimeout: updateMonitorTimeout,
            location: location,
            uninstaller: uninstaller,
            installCoordinator: installCoordinator
        )
    }

    func rows(for target: TargetKind) -> [FlagRow] {
        switch target {
        case .roblox:
            robloxRows
        case .studio:
            studioRows
        }
    }

    func setRows(_ rows: [FlagRow], for target: TargetKind) {
        switch target {
        case .roblox:
            robloxRows = rows
        case .studio:
            studioRows = rows
        }
    }

    func bindingRows(for target: TargetKind) -> Binding<[FlagRow]> {
        Binding(
            get: { self.rows(for: target) },
            set: {
                self.setRows($0, for: target)
                self.persistRowsForEditing(target)
            }
        )
    }

    func saveRows(for target: TargetKind) {
        Task { await performSaveRows(for: target) }
    }

    func performSaveRows(for target: TargetKind) async {
        guard beginApplying() else { return }
        defer { finishApplying() }
        do {
            try store.saveRows(rows(for: target), for: target)
            guard case .ready = location.state(for: target) else {
                statusMessage = "Saved \(target.displayName) flags. They will be applied after install."
                errorMessage = nil
                return
            }
            let data = try FlagSerializer.serialize(rows(for: target))
            let result = try await applier.apply(data: data, to: target, replacementDecision: .ask)
            guard result == .applied else {
                pendingReplacement = PendingReplacement(target: target, shouldLaunchAfterReplacement: false)
                statusMessage = "Existing \(target.displayName) settings need confirmation before replacement."
                errorMessage = nil
                return
            }
            statusMessage = "Saved and applied \(target.displayName) flags."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func validationSummary(for target: TargetKind) -> String {
        FlagSerializer.validate(rows(for: target))
            .compactMap(\.errorDescription)
            .joined(separator: "\n")
    }

    func isInstalled(_ target: TargetKind) -> Bool {
        if case .ready = location.state(for: target) {
            return true
        }
        return false
    }

    func canUninstall(_ target: TargetKind) -> Bool {
        switch location.state(for: target) {
        case .ready, .broken:
            true
        case .absent, .installing:
            false
        }
    }

    func uninstall(_ target: TargetKind) {
        do {
            try uninstaller.uninstall(target)
            statusMessage = "Uninstalled \(target.displayName). Saved flags were kept."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyAndLaunchSelectedTarget() {
        applyAndLaunch(selectedTarget)
    }

    func applyAndLaunch(_ target: TargetKind) {
        applyAndLaunch(target, replacementDecision: .ask)
    }

    private func applyAndLaunch(_ target: TargetKind, replacementDecision: ReplacementDecision) {
        guard beginApplying(showBusyMessage: true) else { return }
        let wasInstalled = isInstalled(target)
        Task { @MainActor in
            AppRuntime.shared.shouldRevealMainWindow = true
            defer { finishApplying() }
            let installed = await installCoordinator.ensureInstalled(target, location: location)
            guard installed else {
                errorMessage = installCoordinator.errorMessage ?? "Install failed."
                return
            }
            if installCoordinator.updateCheckFailed {
                statusMessage = "Update check failed; launching installed version of \(target.displayName)."
            }
            guard wasInstalled else {
                statusMessage = "Installed \(target.displayName)."
                errorMessage = nil
                replayQueuedLaunchRequest(for: target)
                return
            }
            do {
                let data = try await prepareTargetForLaunch(target, replacementDecision: replacementDecision)
                let before = try updateMonitor.fingerprint(for: target)
                let watchSession = try updateMonitor.beginWatching(for: target)
                try await launcher.launch(target)
                statusMessage = "Launched \(target.displayName)."
                errorMessage = nil
                monitorForUpdate(after: before, target: target, desiredFlagData: data, session: watchSession)
                replayQueuedLaunchRequest(for: target)
            } catch is CancellationError {
                statusMessage = "Existing \(target.displayName) settings need confirmation before replacement."
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func handleRoutedLaunch(_ request: RoutedLaunchRequest) {
        selectedTarget = request.target

        if installCoordinator.progress?.target == request.target {
            pendingRoutedLaunchRequests[request.target] = request
            return
        }

        guard !isApplying else {
            pendingRoutedLaunchRequests[request.target] = request
            return
        }
        guard beginApplying() else {
            pendingRoutedLaunchRequests[request.target] = request
            return
        }

        Task { @MainActor in
            defer {
                finishApplying()
                AppRuntime.shared.finishExternalLaunch()
            }

            _ = protocolHandler.repairRegistrationIfNeeded()

            let installed = await installCoordinator.ensureInstalled(request.target, location: location)
            guard installed else {
                errorMessage = installCoordinator.errorMessage ?? "Install failed."
                return
            }
            if installCoordinator.updateCheckFailed {
                statusMessage = "Update check failed; launching installed version of \(request.target.displayName)."
            }

            do {
                let data = try await prepareTargetForLaunch(request.target, replacementDecision: .ask)
                let before = try updateMonitor.fingerprint(for: request.target)
                let watchSession = try updateMonitor.beginWatching(for: request.target)
                try await launcher.forward(request)
                statusMessage = "Opened \(request.target.displayName)."
                errorMessage = nil
                monitorForUpdate(after: before, target: request.target, desiredFlagData: data, session: watchSession)
            } catch is CancellationError {
                statusMessage = "Existing \(request.target.displayName) settings need confirmation before replacement."
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func handleRobloxPlayerURL(_ url: URL) {
        handleRoutedLaunch(.robloxPlayer(url))
    }

    private func replayQueuedLaunchRequest(for target: TargetKind) {
        guard let queued = pendingRoutedLaunchRequests.removeValue(forKey: target) else {
            return
        }
        handleRoutedLaunch(queued)
    }

    private func persistRowsForEditing(_ target: TargetKind) {
        do {
            try store.saveRows(rows(for: target), for: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareTargetForLaunch(
        _ target: TargetKind,
        replacementDecision: ReplacementDecision
    ) async throws -> Data {
        try store.saveRows(rows(for: target), for: target)
        let data = try FlagSerializer.serialize(rows(for: target))
        let result = try await applier.apply(data: data, to: target, replacementDecision: replacementDecision)
        guard result == .applied else {
            pendingReplacement = PendingReplacement(target: target, shouldLaunchAfterReplacement: true)
            throw CancellationError()
        }
        return data
    }

    func presentRelaunchPrompt(for target: TargetKind) {
        pendingRelaunchTarget = target
        statusMessage = "\(target.displayName) updated or replaced its flag file. Flags were reapplied."
    }

    func clearRelaunchPrompt() {
        pendingRelaunchTarget = nil
    }

    func relaunchPendingTarget() {
        guard let target = pendingRelaunchTarget else {
            return
        }
        pendingRelaunchTarget = nil
        applyAndLaunch(target)
    }

    func confirmReplacement() {
        guard let pendingReplacement else {
            return
        }

        self.pendingReplacement = nil
        if pendingReplacement.shouldLaunchAfterReplacement {
            applyAndLaunch(pendingReplacement.target, replacementDecision: .replace)
        } else {
            applySavedRows(pendingReplacement.target, replacementDecision: .replace)
        }
    }

    func cancelReplacement() {
        pendingReplacement = nil
    }

    private func monitorForUpdate(
        after before: LaunchFingerprint,
        target: TargetKind,
        desiredFlagData data: Data,
        session: UpdateWatchSession
    ) {
        AppRuntime.shared.beginBackgroundActivity()
        Task { @MainActor in
            defer { AppRuntime.shared.finishBackgroundActivity() }
            do {
                if let impact = try await updateMonitor.waitForImpact(
                    after: before,
                    target: target,
                    desiredFlagData: data,
                    session: session,
                    timeout: updateMonitorTimeout
                ), impact != .unchanged {
                    _ = try await applier.apply(data: data, to: target, replacementDecision: .replace)
                    presentRelaunchPrompt(for: target)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applySavedRows(_ target: TargetKind, replacementDecision: ReplacementDecision) {
        guard beginApplying() else { return }
        Task { @MainActor in
            defer { finishApplying() }
            do {
                let data = try FlagSerializer.serialize(rows(for: target))
                let result = try await applier.apply(data: data, to: target, replacementDecision: replacementDecision)
                guard result == .applied else {
                    pendingReplacement = PendingReplacement(target: target, shouldLaunchAfterReplacement: false)
                    statusMessage = "Existing \(target.displayName) settings need confirmation before replacement."
                    errorMessage = nil
                    return
                }
                statusMessage = "Applied \(target.displayName) flags."
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func beginApplying(showBusyMessage: Bool = false) -> Bool {
        guard !isApplying else {
            if showBusyMessage {
                statusMessage = "Please wait — another operation is in progress."
            }
            return false
        }
        isApplying = true
        return true
    }

    private func finishApplying() {
        isApplying = false
    }
}

private final class InMemoryProtocolRegistrar: ProtocolRegistering {
    private var schemeHandler: String?
    private var contentTypeHandler: String?

    func defaultHandler(for scheme: String) -> String? {
        schemeHandler
    }

    func setDefaultHandler(_ bundleIdentifier: String, for scheme: String) -> Bool {
        schemeHandler = bundleIdentifier
        return true
    }

    func defaultHandler(forContentType contentType: String) -> String? {
        contentTypeHandler
    }

    func setDefaultHandler(_ bundleIdentifier: String, forContentType contentType: String) -> Bool {
        contentTypeHandler = bundleIdentifier
        return true
    }
}
