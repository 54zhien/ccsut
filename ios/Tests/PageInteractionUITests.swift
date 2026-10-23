import XCTest

final class PageInteractionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-ui", "--preview-page", page]
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testColdLoadingFillsPageWidth() {
        let app = launch("loading")
        let surface = app.otherElements["schedule-surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        capture(app, "cold-loading")
        XCTAssertGreaterThan(surface.frame.width, app.frame.width * 0.95,
                             "Loading must fill the page instead of collapsing to a narrow strip")
    }

    func testSemesterAndWeekdaysMoveWithCourses() {
        let app = launch("interactions")
        let semester = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2026")).firstMatch
        XCTAssertTrue(semester.waitForExistence(timeout: 5))
        let weekday = app.staticTexts["周一"]
        let originalTermY = semester.frame.minY
        let originalDayY = weekday.frame.minY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.82))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.30))
        start.press(forDuration: 0.1, thenDragTo: end)
        capture(app, "whole-page-scrolled")
        XCTAssertTrue(!semester.isHittable || semester.frame.minY < originalTermY - 25,
                      "Semester must scroll with the timetable")
        XCTAssertTrue(!weekday.isHittable || weekday.frame.minY < originalDayY - 25,
                      "Weekdays must scroll with the timetable")
    }

    func testPullingTimetableRefreshesWholePageOnce() {
        let app = launch("interactions")
        let counter = app.staticTexts["refresh-count"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "0")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.86))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(NSPredicate(format: "label == '1'").evaluate(with: counter) ||
                      XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '1'"), evaluatedWith: counter)], timeout: 5) == .completed)
        capture(app, "outer-page-refreshed")
        XCTAssertEqual(counter.label, "1")
    }

    func testAcademicNavigationReturnsConsistently() {
        let app = launch("academic")
        for title in ["成绩查询", "考试安排", "选课", "成绩查询"] {
            let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            let back = app.buttons["返回教务"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertLessThan(back.frame.midX, app.frame.width * 0.25)
            capture(app, "academic-\(title)")
            back.tap()
            XCTAssertTrue(app.buttons["账号"].waitForExistence(timeout: 5))
            XCTAssertFalse(back.exists)
        }
    }
}
