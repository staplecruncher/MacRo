import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, ObservableObject {
    struct MenuItemDescriptor: Equatable {
        let title: String
        let action: Selector?
        let keyEquivalent: String
        let isSeparator: Bool

        static func item(_ title: String, action: Selector, keyEquivalent: String = "") -> MenuItemDescriptor {
            MenuItemDescriptor(title: title, action: action, keyEquivalent: keyEquivalent, isSeparator: false)
        }

        static let separator = MenuItemDescriptor(title: "", action: nil, keyEquivalent: "", isSeparator: true)
    }

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
        Self.menuItemDescriptors.forEach { descriptor in
            if descriptor.isSeparator {
                menu.addItem(.separator())
            } else if let action = descriptor.action {
                menu.addItem(NSMenuItem(title: descriptor.title, action: action, keyEquivalent: descriptor.keyEquivalent))
            }
        }
        menu.items.forEach { $0.target = self }
        return menu
    }

    static let menuItemDescriptors: [MenuItemDescriptor] = [
        .item("Launch Roblox", action: #selector(launchRoblox)),
        .item("Launch Roblox Studio", action: #selector(launchRobloxStudio)),
        .separator,
        .item("Open App", action: #selector(openMacRo)),
        .separator,
        .item(AppConstants.quitButtonTitle, action: #selector(quitMacRo), keyEquivalent: "q")
    ]

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
