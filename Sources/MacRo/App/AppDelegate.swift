import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        installWindowDelegates()
        hideMainWindowIfNeededOnColdStart()
    }

    func installWindowDelegates() {
        NSApp.windows
            .filter { $0.title == AppConstants.displayName }
            .forEach { $0.delegate = self }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: AppConstants.showMenuBarIconDefaultsKey)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if UserDefaults.standard.bool(forKey: AppConstants.showMenuBarIconDefaultsKey),
           !AppRuntime.shared.isQuittingFromExplicitAction {
            sender.hide(nil)
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            let request = RoutedLaunchRequest.parse(url: url)
        else {
            return
        }

        prepareForExternalLaunch()
        Task { @MainActor in
            AppRuntime.shared.enqueue(request)
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        var requests: [RoutedLaunchRequest] = []
        for filename in filenames {
            let fileURL = URL(fileURLWithPath: filename)
            if let request = RoutedLaunchRequest.parse(url: fileURL) {
                requests.append(request)
            }
        }
        if !requests.isEmpty {
            prepareForExternalLaunch()
            for request in requests {
                Task { @MainActor in
                    AppRuntime.shared.enqueue(request)
                }
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        var requests: [RoutedLaunchRequest] = []
        for url in urls {
            if let request = RoutedLaunchRequest.parse(url: url) {
                requests.append(request)
            }
        }
        if !requests.isEmpty {
            prepareForExternalLaunch()
            for request in requests {
                Task { @MainActor in
                    AppRuntime.shared.enqueue(request)
                }
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let fileURL = URL(fileURLWithPath: filename)
        guard let request = RoutedLaunchRequest.parse(url: fileURL) else {
            return false
        }

        prepareForExternalLaunch()
        Task { @MainActor in
            AppRuntime.shared.enqueue(request)
        }
        return true
    }

    private func prepareForExternalLaunch() {
        let hadVisibleWindow = NSApp.windows.contains { window in
            window.title == AppConstants.displayName && window.isVisible
        }

        AppRuntime.shared.beginExternalLaunch(mainWindowWasVisible: hadVisibleWindow)

        guard !hadVisibleWindow,
              UserDefaults.standard.bool(forKey: AppConstants.showMenuBarIconDefaultsKey)
        else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        NSApp.windows
            .filter { $0.title == AppConstants.displayName }
            .forEach { $0.orderOut(nil) }
    }

    private func hideMainWindowIfNeededOnColdStart() {
        guard UserDefaults.standard.bool(forKey: AppConstants.showMenuBarIconDefaultsKey),
              !AppRuntime.shared.shouldRevealMainWindow
        else {
            return
        }

        NSApp.windows
            .filter { $0.title == AppConstants.displayName }
            .forEach { $0.orderOut(nil) }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard UserDefaults.standard.bool(forKey: AppConstants.showMenuBarIconDefaultsKey) else {
            return true
        }

        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}
