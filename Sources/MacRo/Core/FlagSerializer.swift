import CoreFoundation
import Foundation

enum FlagSerializationError: Error, Equatable, LocalizedError {
    case emptyName(rowID: UUID)
    case duplicateName(String)
    case malformedQuotedString(String)
    case unsupportedJSONContainer(String)
    case nonFiniteNumber(String)
    case jsonEncodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Enabled flag names cannot be empty."
        case .duplicateName(let name):
            "Duplicate enabled flag name: \(name)"
        case .malformedQuotedString(let value):
            "Malformed quoted string: \(value)"
        case .unsupportedJSONContainer(let value):
            "Arrays and objects are not supported for v1 flag values: \(value)"
        case .nonFiniteNumber(let value):
            "JSON does not support non-finite numbers: \(value)"
        case .jsonEncodingFailed(let reason):
            "Could not encode ClientAppSettings.json: \(reason)"
        }
    }
}

enum FlagSerializer {
    static func validate(_ rows: [FlagRow]) -> [FlagSerializationError] {
        var errors: [FlagSerializationError] = []
        var seenNames = Set<String>()

        for row in rows where row.isEnabled {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                errors.append(.emptyName(rowID: row.id))
                continue
            }

            if seenNames.contains(name) {
                errors.append(.duplicateName(name))
            } else {
                seenNames.insert(name)
            }

            do {
                _ = try parseValue(row.rawValue)
            } catch let error as FlagSerializationError {
                errors.append(error)
            } catch {
                errors.append(.jsonEncodingFailed(error.localizedDescription))
            }
        }

        return errors
    }

    static func parseValue(_ rawValue: String) throws -> JSONFlagValue {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if lowercased == "true" {
            return .bool(true)
        }

        if lowercased == "false" {
            return .bool(false)
        }

        if lowercased == "nan" || lowercased == "infinity" || lowercased == "-infinity" {
            throw FlagSerializationError.nonFiniteNumber(trimmed)
        }

        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            throw FlagSerializationError.unsupportedJSONContainer(trimmed)
        }

        if trimmed.hasPrefix("\"") {
            guard trimmed.hasSuffix("\""),
                  let data = trimmed.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(String.self, from: data)
            else {
                throw FlagSerializationError.malformedQuotedString(trimmed)
            }
            return .string(decoded)
        }

        if let intValue = Int(trimmed), String(intValue) == trimmed {
            return .int(intValue)
        }

        if let data = trimmed.data(using: .utf8),
           let number = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(),
           number.doubleValue.isFinite {
            return .double(number.doubleValue)
        }

        return .string(trimmed)
    }

    static func serialize(_ rows: [FlagRow]) throws -> Data {
        let validationErrors = validate(rows)
        if let firstError = validationErrors.first {
            throw firstError
        }

        var output: [String: Any] = [:]

        for row in rows where row.isEnabled {
            let key = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = try parseValue(row.rawValue)
            output[key] = value.foundationObject
        }

        do {
            return try JSONSerialization.data(
                withJSONObject: output,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw FlagSerializationError.jsonEncodingFailed(error.localizedDescription)
        }
    }
}
