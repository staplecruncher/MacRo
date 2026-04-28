import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private weak var viewModel: AppViewModel?
    private var openMainWindowAction: (() -> Void)?

    func setVisible(_ isVisible: Bool, viewModel: AppViewModel, openMainWindow: @escaping () -> Void) {
        self.viewModel = viewModel
        self.openMainWindowAction = openMainWindow

        if isVisible {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = makeIcon()
        item.button?.imagePosition = .imageOnly
        item.menu = makeMenu()
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func makeIcon() -> NSImage? {
        let image = NSImage(named: "StatusIcon")
            ?? Bundle.main.url(forResource: "StatusIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = false
        return image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Launch Roblox", action: #selector(launchRoblox), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Launch Roblox Studio", action: #selector(launchRobloxStudio), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open MacRo", action: #selector(openMacRo), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: AppConstants.quitButtonTitle, action: #selector(quitMacRo), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func launchRoblox() {
        viewModel?.applyAndLaunch(.roblox)
    }

    @objc private func launchRobloxStudio() {
        viewModel?.applyAndLaunch(.studio)
    }

    @objc private func openMacRo() {
        openMainWindowAction?()
    }

    @objc private func quitMacRo() {
        AppRuntime.shared.isQuittingFromExplicitAction = true
        NSApp.terminate(nil)
    }
}
