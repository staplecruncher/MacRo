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

    @MainActor
    func testMenuBarItemsAreStable() {
        let descriptors = StatusItemController.menuItemDescriptors

        XCTAssertEqual(
            descriptors.map(\.title),
            ["Launch Roblox", "Launch Roblox Studio", "", "Open App", "", AppConstants.quitButtonTitle]
        )
        XCTAssertEqual(
            descriptors.map(\.isSeparator),
            [false, false, true, false, true, false]
        )
    }
}
