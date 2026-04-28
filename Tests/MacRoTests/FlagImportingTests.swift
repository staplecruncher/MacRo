import Foundation
import XCTest
@testable import MacRo

final class FlagImportingTests: XCTestCase {
    func testImportsObjectKeysAsEnabledRows() throws {
        let data = Data(#"{"B": 12, "A": true, "C": "text"}"#.utf8)

        let rows = try FlagImporting.rows(from: data)

        XCTAssertEqual(rows.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(rows.map(\.rawValue), ["true", "12", "text"])
        XCTAssertEqual(rows.map(\.isEnabled), [true, true, true])
    }

    func testRejectsNonObjectJSONImport() throws {
        let data = Data(#"["Not", "An", "Object"]"#.utf8)

        XCTAssertThrowsError(try FlagImporting.rows(from: data)) { error in
            XCTAssertEqual(error as? FlagImportError, .expectedObject)
        }
    }
}
