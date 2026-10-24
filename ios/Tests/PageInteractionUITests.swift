import XCTest

final class PageInteractionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCampusEntryAndRecords() {
        var app = launch("campus")
        for id in ["campus-leave", "campus-travel", "campus-electricity"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
        }
        capture(app, "campus-home")
        app.buttons["campus-leave"].tap()
        XCTAssertTrue(app.staticTexts["示例请假记录"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["申请请假"].exists)
        capture(app, "campus-leave-records")
        app.terminate()
        app = launch("campus")
        app.buttons["campus-travel"].tap()
        XCTAssertTrue(app.staticTexts["示例区县"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["返校记录"].tap()
        XCTAssertTrue(app.buttons["办理返校登记"].waitForExistence(timeout: 5))
        capture(app, "campus-return-records")
        app.terminate()
        app = launch("academic")
        XCTAssertTrue(app.buttons["academic-scores"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["academic-electricity"].exists)
    }

    func testCampusLargeTextEntries() {
        let app = launch("campus", largeText: true)
        let leave = app.buttons["campus-leave"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(leave.frame.height, 44)
        app.swipeUp()
        let electricity = app.buttons["campus-electricity"]
        XCTAssertTrue(electricity.isHittable)
        XCTAssertGreaterThanOrEqual(electricity.frame.height, 44)
        capture(app, "campus-accessibility-text")
    }

    func testCampusOfficialWebPrivacy() {
        let app = launch("campus-privacy")
        XCTAssertTrue(app.webViews.staticTexts["网页隐私检查通过"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.secureTextFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.staticTexts["18000000000"].exists)
        capture(app, "campus-web-privacy")
    }

    func testCampusNativeLeaveForm() {
        let app = launch("campus-form-leave")
        XCTAssertTrue(app.secureTextFields["campus-form-contact"].waitForExistence(timeout: 8))
        app.segmentedControls.buttons["不离校"].tap()
        app.buttons["campus-form-review"].tap()
        XCTAssertTrue(app.staticTexts["campus-form-error"].waitForExistence(timeout: 5))
        let reason = app.textViews["campus-form-reason"]
        reason.tap(); reason.typeText("reason 18000000000")
        let visible = reason.value as? String ?? ""
        XCTAssertTrue(visible.contains("reason"))
        XCTAssertFalse(visible.contains("18000000000"))
        capture(app, "campus-native-masked-input")
        app.buttons["campus-form-review"].tap()
        XCTAssertTrue(app.buttons["campus-form-confirm"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "18000000000")).firstMatch.exists)
        capture(app, "campus-native-confirmation")
        app.buttons["campus-form-confirm"].tap()
        XCTAssertTrue(app.staticTexts["已提交，等待审核"].waitForExistence(timeout: 5))
    }

    func testCampusNativeDepartureForm() {
        let app = launch("campus-form-departure")
        XCTAssertTrue(app.secureTextFields["campus-form-phone"].waitForExistence(timeout: 8))
        app.segmentedControls.buttons["留校"].tap()
        app.buttons["campus-form-review"].tap()
        XCTAssertTrue(app.buttons["campus-form-confirm"].waitForExistence(timeout: 5))
        capture(app, "campus-native-stay-confirmation")
        app.buttons["campus-form-confirm"].tap()
        XCTAssertTrue(app.staticTexts["已提交，等待审核"].waitForExistence(timeout: 5))
    }

    func testCampusNativeFormLargeText() {
        let app = launch("campus-form-leave", largeText: true)
        let review = app.buttons["campus-form-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(review.frame.height, 44)
        app.swipeUp()
        capture(app, "campus-native-accessibility-form")
    }

    func testCampusFormKeyboardKeepsEditorVisible() {
        let app = launch("campus-form-leave")
        let reason = app.textViews["campus-form-reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 8))
        reason.tap()
        reason.typeText("A short reason")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let visible = NSPredicate { _, _ in reason.frame.maxY <= keyboard.frame.minY + 2 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: visible, evaluatedWith: reason)], timeout: 5), .completed,
                       "The active editor must remain above the keyboard")
        capture(app, "campus-form-keyboard")
    }

    func testCampusElectricityAmountSelection() {
        let app = launch("campus-electricity")
        let amount = app.textFields["缴费金额，单位元"]
        XCTAssertTrue(amount.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["剩余金额"].exists)
        app.buttons["50 元"].tap()
        XCTAssertEqual(amount.value as? String, "50")
        XCTAssertFalse(app.buttons["立即缴费"].isEnabled, "Synthetic previews must never enable a real payment")
        capture(app, "campus-electricity-amount")
    }

    func testCampusAdaptiveLayout() {
        defer { XCUIDevice.shared.orientation = .portrait }
        for page in ["campus-form-leave", "campus-form-departure", "campus-electricity"] {
            XCUIDevice.shared.orientation = .portrait
            var app = launch(page, largeText: true)
            let action = app.buttons[page == "campus-electricity" ? "立即缴费" : "campus-form-review"]
            XCTAssertTrue(action.waitForExistence(timeout: 8))
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            capture(app, "campus-largest-type-\(page)")
            app.terminate()
            app = launch(page)
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: landscape, evaluatedWith: app)], timeout: 5), .completed)
            XCTAssertTrue(app.buttons[page == "campus-electricity" ? "立即缴费" : "campus-form-review"].isHittable)
            capture(app, "campus-landscape-\(page)")
            app.terminate()
        }
    }

    func testCampusRecordsSurviveFormDismissal() {
        for page in ["campus-leave", "campus-travel"] {
            let app = launch(page)
            let isLeave = page == "campus-leave"
            let record = app.staticTexts[isLeave ? "示例请假记录" : "示例区县"]
            XCTAssertTrue(record.waitForExistence(timeout: 8))
            for _ in 0..<2 {
                app.buttons[isLeave ? "申请请假" : "办理离校登记"].tap()
                let close = app.buttons[isLeave ? "关闭申请请假" : "关闭离校登记"]
                XCTAssertTrue(close.waitForExistence(timeout: 5))
                close.tap()
                XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: NSPredicate(format:"exists == false"), evaluatedWith:close)], timeout:5), .completed)
                XCTAssertTrue(record.waitForExistence(timeout: 5), "Cancelling a form must retain existing records without a manual refresh")
            }
            capture(app, "campus-records-after-form-\(page)")
            app.terminate()
        }
    }

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

    private func logPageRefreshDiagnostic(_ app: XCUIApplication, _ stage: String) {
        let probe = app.descendants(matching: .any).matching(identifier: "page-refresh-diagnostic").firstMatch
        if probe.waitForExistence(timeout: 2) {
            print("[PageRefreshDiagnostic] \(stage): \(probe.label)")
        } else {
            print("[PageRefreshDiagnostic] \(stage): missing accessibility probe")
        }
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
        let app = launch("interactions", refresh: true)
        let counter = app.staticTexts["refresh-count"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "0")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.42))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.86))
        start.press(forDuration: 0.1, thenDragTo: end)
        let refreshed = NSPredicate(format: "label == '1'").evaluate(with: counter) ||
            XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '1'"), evaluatedWith: counter)], timeout: 5) == .completed
        XCTAssertTrue(refreshed)
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
            // The cold simulator can expose the back button before the page's
            // loading branch and native appearance transition have settled.
            let contentReady = page == "electives"
                ? app.textFields["课程名 / 教师"]
                : app.descendants(matching: .any).matching(identifier: "term-header-2026-2027-1").firstMatch
            XCTAssertTrue(contentReady.waitForExistence(timeout: 8))
            XCTAssertTrue(contentReady.isHittable)
            let before = back.frame
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.45))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.5)
            capture(app, "cancelled-pop-\(page)")
            let sampleCount = Int(app.staticTexts["transition-samples"].label) ?? 0
            let drift = Double(app.staticTexts["transition-drift"].label) ?? 999
            print("Transition diagnostic \(page): \(app.staticTexts["transition-diagnostics"].label)")
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
        let previousContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousContinueAfterFailure }

        for empty in [false, true] {
            for page in ["scores", "exams", "electives"] {
                let app = launch(page, refresh: true, empty: empty)
                let counter = app.descendants(matching: .any).matching(identifier: "academic-publication-count").firstMatch
                XCTAssertTrue(counter.waitForExistence(timeout: 5))
                XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '1'"), evaluatedWith: counter)], timeout: 5) == .completed,
                              "Wait for the initial snapshot before testing a separate pull refresh")
                let expectedContent: String
                switch (page, empty) {
                case ("scores", true): expectedContent = "暂无成绩"
                case ("exams", true): expectedContent = "暂无考试安排"
                case ("electives", true): expectedContent = "当前没有可选课程"
                case ("scores", false): expectedContent = "高等数学"
                case ("exams", false): expectedContent = "机械设计基础"
                default: expectedContent = "工程制图"
                }
                let content = app.staticTexts.matching(identifier: expectedContent).firstMatch
                XCTAssertTrue(content.waitForExistence(timeout: 3))
                XCTAssertFalse(app.buttons["page-refresh"].exists)
                XCTAssertFalse(app.buttons["刷新"].exists)
                logPageRefreshDiagnostic(app, "\(page)-empty-\(empty)-before-pull")
                // Drag the body away from the semester menu.
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.85))
                start.press(forDuration: 0.1, thenDragTo: end)
                let refreshed = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '2'"), evaluatedWith: counter)], timeout: 5) == .completed
                logPageRefreshDiagnostic(app, "\(page)-empty-\(empty)-after-pull")
                XCTAssertTrue(refreshed, "\(page) must publish exactly one refreshed snapshot even when empty=\(empty)")
                XCTAssertTrue(content.waitForExistence(timeout: 3))
                capture(app, "pull-refresh-\(page)-empty-\(empty)")
                XCTAssertEqual(counter.label, "2")
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
        let emptyState = app.staticTexts["未找到课程"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 3))
        capture(app, "elective-empty-search")
        app.buttons["重置搜索与筛选"].tap()
        let emptyStateDismissed = XCTWaiter.wait(
            for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: emptyState)],
            timeout: 3
        ) == .completed
        XCTAssertTrue(emptyStateDismissed, "Reset should dismiss the empty state after its animated update")
        XCTAssertTrue(app.staticTexts["工程制图"].waitForExistence(timeout: 3))
        capture(app, "elective-reset-search")
    }

    func testLargeTextKeepsAcademicControlsAccessible() {
        func reveal(_ element: XCUIElement, in app: XCUIApplication, movingForward: Bool) -> Bool {
            for _ in 0..<14 {
                if element.isHittable { return true }
                let startY: CGFloat = movingForward ? 0.74 : 0.42
                let endY: CGFloat = movingForward ? 0.56 : 0.62
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
            }
            return element.isHittable
        }

        for page in ["schedule", "scores", "exams"] {
            let app = launch(page, longList: page == "exams", largeText: true)
            let control = page == "schedule" ? app.buttons["本周"] : app.buttons["返回教务"]
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertTrue(control.isHittable)
            capture(app, "large-text-\(page)")
            if page == "scores" {
                let disclosure = app.buttons["score-breakdown-1"]
                for _ in 0..<5 {
                    if disclosure.isHittable { break }
                    app.swipeUp(velocity: .slow)
                }
                XCTAssertTrue(disclosure.isHittable, "Large semester headers must not cover course actions")
                disclosure.tap()
                let detail = app.staticTexts["平时(40%)"]
                XCTAssertTrue(detail.waitForExistence(timeout: 3))
                capture(app, "large-text-score-details")

                let menu = app.buttons.matching(identifier: "academic-term-jump-menu").firstMatch
                XCTAssertTrue(reveal(menu, in: app, movingForward: false), "Large-text semester menu must be reachable")
                menu.tap()
                let target = app.buttons["academic-term-jump-2025-2026-2"]
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                XCTAssertTrue(target.isHittable)
                target.tap()
                let historical = app.staticTexts["机械设计基础"]
                XCTAssertTrue(historical.waitForExistence(timeout: 5))
                XCTAssertTrue(historical.isHittable, "Historical score must be visible after the large-text jump")
                capture(app, "large-text-scores-historical-term")
            } else if page == "exams" {
                let menu = app.buttons.matching(identifier: "academic-term-jump-menu").firstMatch
                XCTAssertTrue(reveal(menu, in: app, movingForward: true), "Large-text exam semester menu must be reachable")
                menu.tap()
                let target = app.buttons["academic-term-jump-2025-2026-2"]
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                XCTAssertTrue(target.isHittable)
                target.tap()
                let historical = app.staticTexts["历史学期考试"]
                XCTAssertTrue(historical.waitForExistence(timeout: 5))
                XCTAssertTrue(historical.isHittable, "Historical exam must be visible after the large-text jump")
                let examDay = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "20", "20日")).firstMatch
                XCTAssertTrue(examDay.waitForExistence(timeout: 5))
                XCTAssertTrue(examDay.isHittable, "Historical ExamRow date rail must be visible at large text")
                capture(app, "large-text-exams-historical-date-rail")
            }
            app.terminate()
        }
    }
}
