import Foundation

struct FlagRow: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var rawValue: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, rawValue: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.rawValue = rawValue
        self.isEnabled = isEnabled
    }
}
