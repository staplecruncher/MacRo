import Foundation
import XCTest
@testable import MacRo

final class FlagSerializerTests: XCTestCase {
    func testFlexibleValueParsing() throws {
        XCTAssertEqual(try FlagSerializer.parseValue("true"), .bool(true))
        XCTAssertEqual(try FlagSerializer.parseValue("false"), .bool(false))
        XCTAssertEqual(try FlagSerializer.parseValue("120"), .int(120))
        XCTAssertEqual(try FlagSerializer.parseValue("12.5"), .double(12.5))
        XCTAssertEqual(try FlagSerializer.parseValue("\"hello world\""), .string("hello world"))
        XCTAssertEqual(try FlagSerializer.parseValue("plain text"), .string("plain text"))
    }

    func testRejectsMalformedQuotedString() {
        XCTAssertThrowsError(try FlagSerializer.parseValue("\"unterminated")) { error in
            XCTAssertEqual(error as? FlagSerializationError, .malformedQuotedString("\"unterminated"))
        }
    }

    func testRejectsArraysObjectsAndNonFiniteNumbers() {
        XCTAssertThrowsError(try FlagSerializer.parseValue("[true]")) { error in
            XCTAssertEqual(error as? FlagSerializationError, .unsupportedJSONContainer("[true]"))
        }
        XCTAssertThrowsError(try FlagSerializer.parseValue("{\"x\":1}")) { error in
            XCTAssertEqual(error as? FlagSerializationError, .unsupportedJSONContainer("{\"x\":1}"))
        }
        XCTAssertThrowsError(try FlagSerializer.parseValue("NaN")) { error in
            XCTAssertEqual(error as? FlagSerializationError, .nonFiniteNumber("NaN"))
        }
        XCTAssertThrowsError(try FlagSerializer.parseValue("Infinity")) { error in
            XCTAssertEqual(error as? FlagSerializationError, .nonFiniteNumber("Infinity"))
        }
    }

    func testValidationRejectsEmptyAndDuplicateEnabledNames() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let rows = [
            FlagRow(id: firstID, name: "FFlagOne", rawValue: "true", isEnabled: true),
            FlagRow(id: secondID, name: "FFlagOne", rawValue: "false", isEnabled: true),
            FlagRow(id: thirdID, name: "   ", rawValue: "text", isEnabled: true)
        ]

        let errors = FlagSerializer.validate(rows)
        XCTAssertTrue(errors.contains(.duplicateName("FFlagOne")))
        XCTAssertTrue(errors.contains(.emptyName(rowID: thirdID)))
    }

    func testDisabledRowsAreIgnored() throws {
        let rows = [
            FlagRow(name: "FFlagEnabled", rawValue: "true", isEnabled: true),
            FlagRow(name: "", rawValue: "\"ignored\"", isEnabled: false)
        ]

        let data = try FlagSerializer.serialize(rows)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["FFlagEnabled"] as? Bool, true)
        XCTAssertNil(object[""])
    }

    func testSerializationIsPrettyPrintedAndSorted() throws {
        let rows = [
            FlagRow(name: "ZFlag", rawValue: "plain", isEnabled: true),
            FlagRow(name: "AFlag", rawValue: "12", isEnabled: true)
        ]

        let data = try FlagSerializer.serialize(rows)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\n"))
        XCTAssertLessThan(
            try XCTUnwrap(json.range(of: "\"AFlag\"")?.lowerBound),
            try XCTUnwrap(json.range(of: "\"ZFlag\"")?.lowerBound)
        )
    }
}
