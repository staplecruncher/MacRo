import XCTest
@testable import MacRo

final class SmokeTests: XCTestCase {
    func testAppNameIsStable() {
        XCTAssertEqual(AppConstants.displayName, "MacRo")
    }

    func testUILaunchLabelsAreStable() {
        XCTAssertEqual(AppConstants.enabledColumnTitle, "Enabled")
        XCTAssertEqual(AppConstants.quitButtonTitle, "Quit")
    }
}
