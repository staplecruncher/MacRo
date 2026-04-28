import AppKit
import SwiftUI

enum AppConstants {
    static let displayName = "MacRo"
    static let bundleIdentifier = "com.staplecruncher.MacRo"
    static let enabledColumnTitle = "Enabled"
    static let quitButtonTitle = "Quit"
    static let robloxPlayerScheme = "roblox-player"
    static let robloxStudioScheme = "roblox-studio"
    static let robloxStudioAuthScheme = "roblox-studio-auth"
    static let robloxStudioDocumentContentType = "com.Roblox.RobloxStudio-document"
    static let showMenuBarIconDefaultsKey = "showMenuBarIcon"
}

@main
struct MacRoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppConstants.showMenuBarIconDefaultsKey) private var showMenuBarIcon = false
    @StateObject private var statusItemController = StatusItemController()
    @StateObject private var viewModel: AppViewModel

    init() {
        do {
            let model = try AppViewModel()
            _viewModel = StateObject(wrappedValue: model)
            AppRuntime.shared.viewModel = model
        } catch {
            let model = AppViewModel.fallback(error: error)
            _viewModel = StateObject(wrappedValue: model)
            AppRuntime.shared.viewModel = model
        }
    }

    var body: some Scene {
        Window(AppConstants.displayName, id: "main") {
            MainView()
                .environmentObject(viewModel)
                .onAppear {
                    _ = ProtocolHandlerService().repairRegistrationIfNeeded()
                    appDelegate.installWindowDelegates()
                    statusItemController.setVisible(showMenuBarIcon, viewModel: viewModel, openMainWindow: openMainWindow)
                    hideMainWindowIfNeeded(force: AppRuntime.shared.isHandlingExternalLaunch)
                    showInDockIfNeeded()
                }
                .onChange(of: showMenuBarIcon) { _, isVisible in
                    statusItemController.setVisible(isVisible, viewModel: viewModel, openMainWindow: openMainWindow)
                }
                .onOpenURL { url in
                    guard let request = RoutedLaunchRequest.parse(url: url) else { return }
                    AppRuntime.shared.enqueue(request)
                }
        }
    }

    private func openMainWindow() {
        AppRuntime.shared.shouldRevealMainWindow = true
        openWindow(id: "main")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideMainWindowIfNeeded(force: Bool = false) {
        guard (showMenuBarIcon || force), !AppRuntime.shared.shouldRevealMainWindow else {
            return
        }
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title == AppConstants.displayName }
                .forEach { $0.orderOut(nil) }
        }
    }

    private func showInDockIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard !showMenuBarIcon,
                  !AppRuntime.shared.isHandlingExternalLaunch || AppRuntime.shared.shouldRevealMainWindow
            else {
                return
            }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension AppViewModel {
    static func fallback(error: Error) -> AppViewModel {
        guard let model = try? AppViewModel.makeForTests(store: FlagStore(rootDirectory: FileManager.default.temporaryDirectory)) else {
            fatalError("MacRo cannot start: \(error.localizedDescription)")
        }
        model.errorMessage = error.localizedDescription
        return model
    }
}
