import Foundation
import SwiftUI

enum InstallPhase: Equatable {
    case downloading
    case installing
}

struct InstallProgress: Equatable {
    let target: TargetKind
    let phase: InstallPhase
    let fraction: Double?
    let bytesReceived: Int64
    let totalBytesExpected: Int64?
    let bytesPerSecond: Double?

    init(
        target: TargetKind,
        phase: InstallPhase = .downloading,
        fraction: Double?,
        bytesReceived: Int64 = 0,
        totalBytesExpected: Int64? = nil,
        bytesPerSecond: Double? = nil
    ) {
        self.target = target
        self.phase = phase
        self.fraction = fraction
        self.bytesReceived = bytesReceived
        self.totalBytesExpected = totalBytesExpected
        self.bytesPerSecond = bytesPerSecond
    }
}

@MainActor
class InstallCoordinator: ObservableObject {
    @Published var progress: InstallProgress?
    @Published var errorMessage: String?
    @Published var updateCheckFailed: Bool = false
    private let installer: ManagedAppInstaller
    private let versionStore: ManagedAppVersionStore

    init(
        installer: ManagedAppInstaller = ManagedAppInstaller(),
        versionStore: ManagedAppVersionStore = ManagedAppVersionStore()
    ) {
        self.installer = installer
        self.versionStore = versionStore
    }

    func ensureInstalled(_ target: TargetKind, location: ManagedAppLocation) async -> Bool {
        errorMessage = nil
        updateCheckFailed = false

        if case .ready = location.state(for: target) {
            do {
                let currentVersion = try await installer.fetchCurrentVersion(for: target)
                let installedVersion = try versionStore.loadVersionUpload(for: target)
                if installedVersion == currentVersion.installIdentity {
                    return true
                }
                return await install(target, clientVersion: currentVersion)
            } catch {
                updateCheckFailed = true
                return true
            }
        }

        do {
            let currentVersion = try await installer.fetchCurrentVersion(for: target)
            return await install(target, clientVersion: currentVersion)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func install(_ target: TargetKind, clientVersion: RobloxClientVersion) async -> Bool {
        errorMessage = nil
        progress = InstallProgress(target: target, phase: .downloading, fraction: 0)
        do {
            let installedVersion = try await installer.install(target, clientVersion: clientVersion) { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.progress = snapshot
                }
            }
            try versionStore.saveVersionUpload(installedVersion.installIdentity, for: target)
            progress = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            progress = nil
            return false
        }
    }
}
