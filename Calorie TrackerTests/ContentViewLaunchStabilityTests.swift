import XCTest

final class ContentViewLaunchStabilityTests: XCTestCase {

    func testArchiveFloor_doesNotLowerExistingTodayGoal_whenLaunchFallbackIsLower() {
        let result = CalibrationEngine.floorAgainstArchive(1500, archivedValue: 2200)
        XCTAssertEqual(result, 2200)
    }

    func testArchiveFloor_usesFreshValue_whenArchiveMissing() {
        let result = CalibrationEngine.floorAgainstArchive(1900, archivedValue: nil)
        XCTAssertEqual(result, 1900)
    }
}
