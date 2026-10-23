import XCTest

final class PageInteractionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ page: String, longList: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-ui", "--preview-page", page]
        if longList { app.launchArguments.append("--preview-long-list") }
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
        let surface = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'schedule-surface' OR identifier == 'schedule-scroll'"
        )).firstMatch
        let exists = surface.waitForExistence(timeout: 5)
        capture(app, "cold-loading")
        if !exists { print(app.debugDescription) }
        XCTAssertTrue(exists)
        XCTAssertGreaterThan(surface.frame.width, app.frame.width * 0.95,
                             "Loading must fill the page instead of collapsing to a narrow strip")
    }

    func testDeviceCornersResolveOnRoundedPhone() {
        let app = launch("interactions")
        let radius = app.staticTexts["device-corner-radius"]
        XCTAssertTrue(radius.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(Double(radius.label) ?? 0, 0)
    }

    func testSemesterAndWeekdaysMoveWithCourses() {
        let app = launch("interactions")
        let semester = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2026")).firstMatch
        XCTAssertTrue(semester.waitForExistence(timeout: 5))
        let weekday = app.staticTexts.matching(NSPredicate(format: "label == %@", "周一")).firstMatch
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
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertLessThan(back.frame.midX, app.frame.width * 0.25)
            capture(app, "academic-\(title)")
            back.tap()
            XCTAssertTrue(app.buttons["账号"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars.firstMatch.exists)
        }
    }

    func testAcademicDetailsSupportEdgeSwipeBack() {
        let app = launch("academic")
        for title in ["成绩查询", "考试安排", "选课"] {
            let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            XCTAssertTrue(app.buttons["page-refresh"].waitForExistence(timeout: 5))
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
            let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
            edge.press(forDuration: 0.05, thenDragTo: destination)
            capture(app, "edge-back-\(title)")
            XCTAssertTrue(app.buttons["账号"].waitForExistence(timeout: 5),
                          "Each academic detail must support interactive edge swipe back")
        }
    }

    func testAcademicTitlesAndTermStripsRemainStableWhenPinned() {
        var stripWidths: [CGFloat] = []
        for (page, title) in [("scores", "成绩单"), ("exams", "考试")] {
            let app = launch(page, longList: true)
            let navigationTitle = app.navigationBars.staticTexts[title]
            XCTAssertTrue(navigationTitle.waitForExistence(timeout: 5))
            let titleFrame = navigationTitle.frame
            XCTAssertEqual(titleFrame.midX, app.frame.midX, accuracy: 6)
            let header = app.descendants(matching: .any).matching(identifier: "term-header-2026-2027-1").firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            stripWidths.append(header.frame.width)
            XCTAssertEqual(header.frame.width, app.frame.width - 32, accuracy: 2)
            XCTAssertEqual(header.value as? String, "inline")
            app.swipeUp()
            XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == 'floating'"), evaluatedWith: header)], timeout: 5) == .completed)
            capture(app, "floating-term-\(page)")
            XCTAssertTrue(navigationTitle.isHittable)
            XCTAssertEqual(navigationTitle.frame.midY, titleFrame.midY, accuracy: 2)
            XCTAssertEqual(header.frame.width, stripWidths.last!, accuracy: 2)
            app.terminate()
        }
        XCTAssertEqual(stripWidths[0], stripWidths[1], accuracy: 2)
    }
}
