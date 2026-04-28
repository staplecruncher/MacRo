import Foundation

enum JSONFlagValue: Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    var foundationObject: Any {
        switch self {
        case .bool(let value):
            value
        case .int(let value):
            value
        case .double(let value):
            value
        case .string(let value):
            value
        }
    }
}
