import Foundation

enum FlagImportError: Error, Equatable, LocalizedError {
    case expectedObject

    var errorDescription: String? {
        switch self {
        case .expectedObject:
            "Imported JSON must be an object of flag names and values."
        }
    }
}

enum FlagImporting {
    static func rows(from data: Data) throws -> [FlagRow] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw FlagImportError.expectedObject
        }

        return object.keys.sorted().map { key in
            FlagRow(name: key, rawValue: rawValueText(from: object[key] ?? ""), isEnabled: true)
        }
    }

    private static func rawValueText(from value: Any) -> String {
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return "\(number)"
        case let string as String:
            return string
        default:
            if JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return String(describing: value)
        }
    }
}
