import AppKit

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    var shouldRevealMainWindow = false
    var isQuittingFromExplicitAction = false
    var isHandlingExternalLaunch = false
    var externalLaunchHadVisibleWindow = false
    private(set) var backgroundActivityCount = 0
    var hasActiveBackgroundActivity: Bool { backgroundActivityCount > 0 }
    var viewModel: AppViewModel? {
        didSet { flushPending() }
    }
    private var pendingRequests: [RoutedLaunchRequest] = []

    func enqueue(_ request: RoutedLaunchRequest) {
        if let viewModel {
            viewModel.handleRoutedLaunch(request)
        } else {
            pendingRequests.append(request)
        }
    }

    func beginExternalLaunch(mainWindowWasVisible: Bool) {
        isHandlingExternalLaunch = true
        externalLaunchHadVisibleWindow = mainWindowWasVisible
        shouldRevealMainWindow = mainWindowWasVisible
    }

    func finishExternalLaunch() {
        isHandlingExternalLaunch = false
        externalLaunchHadVisibleWindow = false
        terminateIfIdle()
    }

    func beginBackgroundActivity() {
        backgroundActivityCount += 1
    }

    func finishBackgroundActivity() {
        backgroundActivityCount = max(0, backgroundActivityCount - 1)
        terminateIfIdle()
    }

    func terminateIfIdle() {
        guard let app = NSApp,
              !UserDefaults.standard.bool(forKey: AppConstants.showMenuBarIconDefaultsKey),
              !isHandlingExternalLaunch,
              !shouldRevealMainWindow,
              !hasActiveBackgroundActivity
        else {
            return
        }
        let hasVisibleWindow = app.windows.contains { $0.title == AppConstants.displayName && $0.isVisible }
        guard !hasVisibleWindow else { return }
        app.terminate(nil)
    }

    private func flushPending() {
        guard let viewModel else { return }
        let requests = pendingRequests
        pendingRequests.removeAll()
        for request in requests {
            viewModel.handleRoutedLaunch(request)
        }
    }

    func resetTransientStateForTests() {
        shouldRevealMainWindow = false
        isQuittingFromExplicitAction = false
        isHandlingExternalLaunch = false
        externalLaunchHadVisibleWindow = false
        backgroundActivityCount = 0
        pendingRequests.removeAll()
    }
}
