import XCTest

final class PageInteractionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ page: String, longList: Bool = false, transition: Bool = false, withoutUpcoming: Bool = false,
                        refresh: Bool = false, empty: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-ui", "--preview-page", page]
        if longList { app.launchArguments.append("--preview-long-list") }
        if transition { app.launchArguments.append("--preview-transition") }
        if withoutUpcoming { app.launchArguments.append("--preview-no-upcoming") }
        if refresh { app.launchArguments.append("--preview-refresh") }
        if empty { app.launchArguments.append("--preview-empty") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
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
        XCTAssertTrue(app.buttons["本周"].exists)
        capture(app, "current-week-initial")
        XCTAssertEqual(app.buttons["本周"].frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertFalse(app.buttons["page-refresh"].exists)
        for (index, times) in ["8:20 至 10:00", "10:20 至 12:00", "14:00 至 15:40", "16:00 至 17:40"].enumerated() {
            let period = app.descendants(matching: .any).matching(identifier: "schedule-period-\(index + 1)").firstMatch
            XCTAssertTrue(period.label.contains(times))
        }
        let nextWeek = app.buttons["第 8 周"]
        nextWeek.tap()
        XCTAssertEqual(nextWeek.frame.midX, app.frame.midX, accuracy: 2)
        app.buttons["回到本周"].tap()
        XCTAssertEqual(app.buttons["本周"].frame.midX, app.frame.midX, accuracy: 2)
        capture(app, "current-week-returned")
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
            let back = app.buttons["返回教务"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertLessThan(back.frame.midX, app.frame.width * 0.25)
            capture(app, "academic-\(title)")
            back.tap()
            XCTAssertTrue(app.buttons["账号"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars.firstMatch.exists)
            XCTAssertFalse(app.buttons["page-refresh"].exists)
        }
    }

    func testAcademicDetailsSupportEdgeSwipeBack() {
        let app = launch("academic")
        for title in ["成绩查询", "考试安排", "选课"] {
            let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            XCTAssertTrue(app.buttons["返回教务"].waitForExistence(timeout: 5))
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
            let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
            edge.press(forDuration: 0.05, thenDragTo: destination)
            capture(app, "edge-back-\(title)")
            XCTAssertTrue(app.buttons["账号"].waitForExistence(timeout: 5),
                          "Each academic detail must support interactive edge swipe back")
            XCTAssertTrue(app.buttons["账号"].isHittable)
            XCTAssertFalse(app.navigationBars.firstMatch.exists)
            XCTAssertFalse(app.buttons["page-refresh"].exists)
        }
    }

    func testAcademicCancelledSwipeKeepsHeaderAttachedToPage() {
        for page in ["scores", "exams", "electives"] {
            let app = launch("academic", transition: true)
            let entry = app.buttons["academic-\(page)"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            let back = app.buttons["返回教务"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            let before = back.frame
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.45))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.5)
            capture(app, "cancelled-pop-\(page)")
            let sampleCount = Int(app.staticTexts["transition-samples"].label) ?? 0
            let drift = Double(app.staticTexts["transition-drift"].label) ?? 999
            add(XCTAttachment(string: "\(page): \(sampleCount) interactive samples, maximum local title drift \(drift)pt"))
            XCTAssertGreaterThan(sampleCount, 3, "Must measure actual in-flight interactive frames")
            XCTAssertLessThanOrEqual(drift, 2, "Title must travel with the detail page during a cancelled swipe")
            XCTAssertTrue(back.isHittable)
            XCTAssertEqual(back.frame.midX, before.midX, accuracy: 2)
            app.terminate()
        }
    }

    func testAcademicHomeWithoutReminderHasStableSpacedEntries() {
        let app = launch("academic", withoutUpcoming: true)
        let first = app.buttons["academic-scores"]
        let last = app.buttons["academic-electives"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let before = first.frame
        let account = app.buttons["账号"]
        XCTAssertGreaterThanOrEqual(before.minY - account.frame.maxY, 24)
        XCTAssertGreaterThanOrEqual(before.height, 96, "Preserve the existing 96-point entry cards")
        XCTAssertTrue(last.isHittable)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(first.frame.minY, before.minY, accuracy: 2)
        XCTAssertEqual(first.frame.height, before.height, accuracy: 2)
        capture(app, "academic-home-no-reminder-pulled")
    }

    func testAcademicDetailSupportsContentSwipeBack() {
        let app = launch("scores", longList: true)
        XCTAssertTrue(app.buttons["返回教务"].waitForExistence(timeout: 5))
        let header = app.descendants(matching: .any).matching(identifier: "term-header-2026-2027-1").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == 'floating'"), evaluatedWith: header)], timeout: 5) == .completed,
                      "Native content-pop recognition must not steal a vertical scroll")
        XCTAssertTrue(app.buttons["返回教务"].isHittable)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.buttons["账号"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["账号"].isHittable)
        XCTAssertFalse(app.buttons["page-refresh"].exists)
        capture(app, "content-swipe-back")
    }

    func testAcademicPagesPullToRefreshIncludingEmptyStates() {
        for empty in [false, true] {
            for page in ["scores", "exams", "electives"] {
                let app = launch(page, refresh: true, empty: empty)
                let counter = app.staticTexts["academic-refresh-count"]
                XCTAssertTrue(counter.waitForExistence(timeout: 5))
                XCTAssertEqual(counter.label, "0")
                XCTAssertFalse(app.buttons["page-refresh"].exists)
                XCTAssertFalse(app.buttons["刷新"].exists)
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.35))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.85))
                start.press(forDuration: 0.1, thenDragTo: end)
                XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '1'"), evaluatedWith: counter)], timeout: 5) == .completed,
                              "\(page) must refresh via its scroll surface even when empty=\(empty)")
                capture(app, "pull-refresh-\(page)-empty-\(empty)")
                app.terminate()
            }
        }
    }

    func testAcademicTitlesAndTermStripsRemainStableWhenPinned() {
        var stripWidths: [CGFloat] = []
        for (page, title) in [("scores", "成绩单"), ("exams", "考试")] {
            let app = launch(page, longList: true)
            let navigationTitle = app.staticTexts["academic-detail-title"]
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

    func testScoreBreakdownExpandsAndHomeReusesLoadedSummary() {
        let app = launch("scores")
        let disclosure = app.buttons["score-breakdown-1"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["平时(40%)"].exists)
        disclosure.tap()
        XCTAssertTrue(app.staticTexts["平时(40%)"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["期末(60%)"].exists)
        capture(app, "score-breakdown-expanded")
        disclosure.tap()
        XCTAssertFalse(app.staticTexts["平时(40%)"].exists)
        app.buttons["返回教务"].tap()
        XCTAssertTrue(app.buttons["academic-scores"].label.contains("已公布 3 门成绩"))
    }

    func testSemesterMenusReachHistoricalContent() {
        for (page, course) in [("scores", "历史学期课程"), ("exams", "历史学期考试")] {
            let app = launch(page, longList: true)
            let menu = app.buttons.matching(identifier: "academic-term-jump-menu").firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.tap()
            let target = app.buttons["academic-term-jump-2025-2026-2"]
            XCTAssertTrue(target.waitForExistence(timeout: 3))
            target.tap()
            let historical = app.staticTexts[course]
            XCTAssertTrue(historical.waitForExistence(timeout: 3))
            XCTAssertTrue(historical.isHittable)
            XCTAssertTrue(app.buttons["返回教务"].isHittable)
            capture(app, "semester-jump-\(page)")
            app.terminate()
        }
    }

    func testElectiveEmptySearchCanResetAndDisabledReasonIsVisible() {
        let app = launch("electives")
        let reason = app.staticTexts.matching(identifier: "找不到这条课程所属的选课批次，请下拉刷新后重试").firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        let field = app.textFields["课程名 / 教师"]
        field.tap()
        field.typeText("no-matching-course-123")
        XCTAssertTrue(app.staticTexts["未找到课程"].waitForExistence(timeout: 3))
        capture(app, "elective-empty-search")
        app.buttons["重置搜索与筛选"].tap()
        XCTAssertFalse(app.staticTexts["未找到课程"].exists)
        XCTAssertTrue(app.staticTexts["工程制图"].exists)
        capture(app, "elective-reset-search")
    }

    func testLargeTextKeepsAcademicControlsAccessible() {
        for page in ["schedule", "scores", "exams"] {
            let app = launch(page, largeText: true)
            let control = page == "schedule" ? app.buttons["本周"] : app.buttons["返回教务"]
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertTrue(control.isHittable)
            capture(app, "large-text-\(page)")
            app.terminate()
        }
    }
}
