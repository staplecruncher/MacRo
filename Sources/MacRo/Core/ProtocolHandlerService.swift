import AppKit
import CoreServices
import Foundation

protocol ProtocolRegistering {
    func defaultHandler(for scheme: String) -> String?
    func setDefaultHandler(_ bundleIdentifier: String, for scheme: String) -> Bool
    func defaultHandler(forContentType contentType: String) -> String?
    func setDefaultHandler(_ bundleIdentifier: String, forContentType contentType: String) -> Bool
}

struct LaunchServicesProtocolRegistrar: ProtocolRegistering {
    func defaultHandler(for scheme: String) -> String? {
        guard let url = URL(string: "\(scheme):"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundle = Bundle(url: appURL)
        else {
            return nil
        }

        return bundle.bundleIdentifier
    }

    func setDefaultHandler(_ bundleIdentifier: String, for scheme: String) -> Bool {
        let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleIdentifier as CFString)
        return status == noErr
    }

    func defaultHandler(forContentType contentType: String) -> String? {
        guard let identifier = LSCopyDefaultRoleHandlerForContentType(contentType as CFString, .editor)?.takeRetainedValue() else {
            return nil
        }
        return identifier as String
    }

    func setDefaultHandler(_ bundleIdentifier: String, forContentType contentType: String) -> Bool {
        let status = LSSetDefaultRoleHandlerForContentType(contentType as CFString, .editor, bundleIdentifier as CFString)
        return status == noErr
    }
}

struct ProtocolHandlerService {
    let registrar: ProtocolRegistering
    let bundleIdentifier: String

    init(
        registrar: ProtocolRegistering = LaunchServicesProtocolRegistrar(),
        bundleIdentifier: String = AppConstants.bundleIdentifier
    ) {
        self.registrar = registrar
        self.bundleIdentifier = bundleIdentifier
    }

    func isRegisteredForRobloxPlayer() -> Bool {
        registrar.defaultHandler(for: AppConstants.robloxPlayerScheme) == bundleIdentifier
    }

    func repairRegistrationIfNeeded() -> Bool {
        let schemes = [
            AppConstants.robloxPlayerScheme,
            AppConstants.robloxStudioScheme,
            AppConstants.robloxStudioAuthScheme
        ]
        var allOK = true

        for scheme in schemes {
            if registrar.defaultHandler(for: scheme) == bundleIdentifier {
                continue
            }
            if !registrar.setDefaultHandler(bundleIdentifier, for: scheme) {
                allOK = false
                continue
            }
            if registrar.defaultHandler(for: scheme) != bundleIdentifier {
                allOK = false
            }
        }

        let documentType = AppConstants.robloxStudioDocumentContentType
        if registrar.defaultHandler(forContentType: documentType) != bundleIdentifier {
            if !registrar.setDefaultHandler(bundleIdentifier, forContentType: documentType) {
                allOK = false
            } else if registrar.defaultHandler(forContentType: documentType) != bundleIdentifier {
                allOK = false
            }
        }

        return allOK
    }
}
