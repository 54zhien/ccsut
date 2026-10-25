import XCTest

final class PageInteractionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCompleteSelectedIncludesClosedBatch() {
        let app = launch("electives", arguments:["--preview-complete-selected"])
        XCTAssertTrue(app.staticTexts["示例线上已选课"].waitForExistence(timeout:8))
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","已选")).firstMatch.tap()
        let search = app.textFields["课程名 / 教师"]
        search.tap(); search.typeText("示例线下")
        XCTAssertTrue(app.staticTexts["示例线下已选课"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["正常修读"].exists)
        XCTAssertFalse(app.buttons["退课"].exists)
        capture(app,"complete-selected-closed-batch")
    }

    func testSelectedHistoryIsReadOnlyWithEmptyCatalog() {
        let app = launch("electives", arguments:["--preview-complete-selected","--preview-empty-catalog"])
        let selected = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","已选")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout:8)); selected.tap()
        let menu = app.buttons["enrolled-term-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout:5)); menu.tap()
        app.buttons["enrolled-term-2024-2025-1"].tap()
        XCTAssertTrue(app.staticTexts["历史学期示例课程"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["示例线下已选课"].exists)
        XCTAssertFalse(app.buttons["退课"].exists)
        XCTAssertFalse(app.buttons["选课"].exists)
        capture(app,"complete-selected-history")
    }

    func testSelectedReadFailureDoesNotPretendToBeComplete() {
        let app = launch("electives", arguments:["--preview-complete-selected","--preview-selected-failure"])
        XCTAssertTrue(app.staticTexts["示例线上已选课"].waitForExistence(timeout:8))
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","已选")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["enrolled-read-error"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["示例线上已选课"].exists)
        capture(app,"complete-selected-read-failure")
    }

    func testSelectedHistoryLargeTextAndDarkAppearance() {
        let app = launch("electives", largeText:true, arguments:["--preview-complete-selected","-AppleInterfaceStyle","Dark"])
        let selected = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","已选")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout:8)); selected.tap()
        let menu = app.buttons["enrolled-term-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout:5)); XCTAssertTrue(menu.isHittable); menu.tap()
        app.buttons["enrolled-term-2024-2025-1"].tap()
        let historical = app.staticTexts["历史学期示例课程"]
        XCTAssertTrue(historical.waitForExistence(timeout:5))
        for _ in 0..<3 { if historical.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(historical.isHittable)
        XCTAssertFalse(app.buttons["退课"].exists)
        capture(app,"complete-selected-history-large-dark")
    }

    func testSelectedCatalogFailureShowsNoticeAndReadOnlyResults() {
        let app = launch("electives", arguments:["--preview-complete-selected","--preview-catalog-failure-once"])
        XCTAssertTrue(app.staticTexts["教学班读取失败，请重试核实操作条件"].waitForExistence(timeout:8))
        let selected = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","已选")).firstMatch
        selected.tap()
        XCTAssertTrue(app.staticTexts["示例线上已选课"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["教学班读取失败，请重试核实操作条件"].exists)
        XCTAssertTrue(app.buttons["重试"].exists)
        XCTAssertFalse(app.staticTexts["enrolled-read-error"].exists)
        XCTAssertFalse(app.buttons["退课"].exists)
        XCTAssertFalse(app.buttons["选课"].exists)
        capture(app,"selected-catalog-failure-read-only")
    }

    func testSelectedCatalogRetryRecoversCatalogCard() {
        let app = launch("electives", arguments:["--preview-complete-selected","--preview-catalog-failure-once"])
        XCTAssertTrue(app.staticTexts["教学班读取失败，请重试核实操作条件"].waitForExistence(timeout:8))
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","已选")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["示例线上已选课"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["退课"].exists)
        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.waitForExistence(timeout:5)); retry.tap()
        let drop = app.buttons["退课"]
        XCTAssertTrue(drop.waitForExistence(timeout:8))
        // The fixture supplies no active batch: recovering the catalog must not
        // bypass the existing action permission checks or issue a mutation.
        XCTAssertFalse(drop.isEnabled)
        XCTAssertFalse(app.staticTexts["教学班读取失败，请重试核实操作条件"].exists)
        XCTAssertTrue(app.staticTexts["示例线上已选课"].exists)
        capture(app,"selected-catalog-retry-recovered")
    }

    func testSelectedCatalogRetryPreservesReadOnlyHistory() {
        let app = launch("electives", arguments:["--preview-complete-selected","--preview-catalog-failure-once"])
        XCTAssertTrue(app.staticTexts["教学班读取失败，请重试核实操作条件"].waitForExistence(timeout:8))
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","已选")).firstMatch.tap()
        let menu = app.buttons["enrolled-term-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout:5)); menu.tap()
        app.buttons["enrolled-term-2024-2025-1"].tap()
        XCTAssertTrue(app.staticTexts["历史学期示例课程"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["教学班读取失败，请重试核实操作条件"].exists)
        app.buttons["重试"].tap()
        let notice = app.staticTexts["教学班读取失败，请重试核实操作条件"]
        XCTAssertTrue(notice.waitForNonExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["历史学期示例课程"].exists)
        XCTAssertFalse(app.buttons["退课"].exists)
        XCTAssertFalse(app.buttons["选课"].exists)
        capture(app,"selected-catalog-retry-history")
    }

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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "年")).firstMatch.exists)
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

    func testCampusFormLoadingIsCentered() {
        for page in ["campus-form-leave", "campus-form-departure"] {
            let app = launch(page, arguments:["--preview-form-loading"])
            let message = app.staticTexts["campus-form-loading-message"]
            let indicator = app.activityIndicators["campus-form-loading-indicator"]
            let close = app.buttons[page == "campus-form-leave" ? "关闭申请请假" : "关闭离校登记"]
            XCTAssertTrue(message.waitForExistence(timeout: 8))
            XCTAssertTrue(indicator.exists)
            XCTAssertEqual(message.frame.midX, app.frame.midX, accuracy: 2)
            XCTAssertEqual(indicator.frame.midX, app.frame.midX, accuracy: 2)
            let groupCenter = (indicator.frame.minY + message.frame.maxY) / 2
            XCTAssertEqual(groupCenter, (close.frame.maxY + app.frame.maxY) / 2, accuracy: 60)
            XCTAssertFalse(app.buttons["campus-form-review"].exists)
            capture(app, "campus-centered-loading-\(page)")
            app.terminate()
        }
    }

    func testCampusLeaveDatesUseChinese() {
        let app = launch("campus-form-leave", arguments:["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let dates = app.datePickers
        XCTAssertTrue(dates.firstMatch.waitForExistence(timeout: 8))
        let labels = dates.firstMatch.descendants(matching: .any).allElementsBoundByIndex.map { $0.label }.joined(separator: " ")
        XCTAssertTrue(labels.contains("年") && labels.contains("月"), "Native date controls must retain Chinese units under an English system language: \(labels)")
        capture(app, "campus-chinese-date-picker")
    }

    func testCampusApproversWaitForTypeSelection() {
        let app = launch("campus-form-leave", arguments:["--preview-form-choices"])
        XCTAssertTrue(app.staticTexts["campus-approver-prerequisite"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["campus-approver-retry"].exists)
        app.buttons["campus-form-choice-类型"].tap()
        app.buttons["病假"].tap()
        XCTAssertTrue(app.buttons["campus-form-choice-辅导员"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["示例审批人"].exists)
        XCTAssertFalse(app.staticTexts["campus-approver-prerequisite"].exists)
        XCTAssertFalse(app.buttons["campus-approver-retry"].exists)
        capture(app, "campus-approver-after-type-selection")
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

    func testPaymentRecoveryEntry() {
        for kind in ["read", "version", "corrupt", "missing"] {
            let app = launch("campus-electricity-recovery-" + kind)
            let retry = app.buttons["payment-recovery-retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["立即缴费"].exists)
            XCTAssertFalse(app.textFields["缴费金额，单位元"].exists)
            XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
            retry.tap()
            XCTAssertTrue(retry.exists, "Retry must not dismiss an unresolved recovery state")
            let help = app.buttons["payment-recovery-help"]
            XCTAssertGreaterThanOrEqual(help.frame.height, 44)
            XCTAssertTrue(help.isHittable)
            help.tap()
            let close = app.buttons["payment-recovery-close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields.count, 0, "Phase one must not accept arbitrary order IDs")
            XCTAssertFalse(app.buttons["立即缴费"].exists)
            capture(app, "payment-recovery-help-" + kind)
            close.tap()
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["立即缴费"].exists, "Closing guidance never unlocks payment")
            capture(app, "payment-recovery-" + kind)
            app.terminate()
        }
    }

    func testPaymentRecoveryLargeText() {
        let app = launch("campus-electricity-recovery-corrupt", largeText: true)
        let retry = app.buttons["payment-recovery-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        if !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.isHittable)
        let help = app.buttons["payment-recovery-help"]
        if !help.isHittable { app.swipeUp() }
        XCTAssertTrue(help.isHittable)
        capture(app, "payment-recovery-largest-type")
        help.tap()
        let close = app.buttons["payment-recovery-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        app.swipeUp()
        capture(app, "payment-recovery-help-largest-type")
        close.tap()
        XCTAssertFalse(app.buttons["立即缴费"].exists)
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

    func testCampusReducedMotion() {
        for page in ["campus-form-leave", "campus-form-departure", "campus-electricity"] {
            let app = launch(page, arguments:["--preview-reduce-motion"])
            let probe = app.staticTexts["campus-reduce-motion"]
            XCTAssertTrue(probe.waitForExistence(timeout: 8))
            XCTAssertEqual(probe.label, "reduce-motion-on", "Verify the real simulator preference reaches SwiftUI")
            capture(app, "campus-reduce-motion-\(page)")
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
                        refresh: Bool = false, empty: Bool = false, legacyBlur: Bool = false, largeText: Bool = false,
                        arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-ui", "--preview-page", page] + arguments
        if longList { app.launchArguments.append("--preview-long-list") }
        if transition { app.launchArguments.append("--preview-transition") }
        if withoutUpcoming { app.launchArguments.append("--preview-no-upcoming") }
        if refresh { app.launchArguments.append("--preview-refresh") }
        if empty { app.launchArguments.append("--preview-empty") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        #if CCSUT_TEST_LEGACY_TOP_BLUR
        let useLegacy = true
        #else
        let useLegacy = legacyBlur
        #endif
        if useLegacy { app.launchArguments.append("--legacy-top-blur") }
        print("TOP_BLUR_TEST_MODE \(useLegacy ? "legacy" : "material") page=\(page)")
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

    func testTopBlurPreservesLegacyPageAndControlFrames() {
        for page in ["schedule", "academic", "scores", "exams", "electives"] {
            var referenceControl = CGRect.zero
            var referenceScroll = CGRect.zero
            for legacy in [true, false] {
                let app = launch(page, legacyBlur: legacy)
                let control = app.buttons[page == "schedule" || page == "academic" ? "账号" : "返回教务"]
                XCTAssertTrue(control.waitForExistence(timeout: 5))
                XCTAssertTrue(control.isHittable, "The blur must not block the top control")
                let scroll = app.scrollViews.firstMatch
                XCTAssertTrue(scroll.waitForExistence(timeout: 5))
                capture(app, "top-blur-\(page)-\(legacy ? "legacy" : "material")")
                if legacy {
                    referenceControl = control.frame
                    referenceScroll = scroll.frame
                } else {
                    for (actual, expected) in [(control.frame, referenceControl), (scroll.frame, referenceScroll)] {
                        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1)
                        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1)
                        XCTAssertEqual(actual.width, expected.width, accuracy: 1)
                        XCTAssertEqual(actual.height, expected.height, accuracy: 1)
                    }
                    control.tap()
                    if page == "schedule" || page == "academic" {
                        XCTAssertTrue(app.buttons["退出登录"].waitForExistence(timeout: 5))
                    } else {
                        XCTAssertTrue(app.buttons["账号"].waitForExistence(timeout: 5))
                    }
                }
                app.terminate()
            }
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
                let app = launch(page, refresh: true, empty: empty, arguments:["--preview-refresh-observation"])
                let counter = app.descendants(matching: .any).matching(identifier: "academic-publication-count").firstMatch
                let stage = "\(page)-empty-\(empty)"
                guard waitForInitialPublication(counter, in:app, stage:stage) else { app.terminate(); continue }
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
                let observation = app.descendants(matching: .any).matching(identifier: "refresh-feedback-observation").firstMatch
                guard let restingInset = waitForNativeRefreshAtRest(observation, stage:stage) else { app.terminate(); continue }
                logPageRefreshDiagnostic(app, "\(page)-empty-\(empty)-before-pull")
                // Use the native proof's body gesture, below the pinned term header.
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
                start.press(forDuration: 0.1, thenDragTo: end)
                let refreshed = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '2'"), evaluatedWith: counter)], timeout: 5) == .completed
                let completed = XCTWaiter.wait(for: [expectation(for: NSPredicate(format:"label BEGINSWITH 'entered=1; completed=1;'"), evaluatedWith:observation)], timeout:5) == .completed
                let report = observation.exists ? observation.label : "missing observation"
                print("[RefreshFeedback] \(stage) after-pull: restingInset=\(restingInset); \(report)")
                logPageRefreshDiagnostic(app, "\(page)-empty-\(empty)-after-pull")
                XCTAssertTrue(refreshed, "\(page) must publish exactly one refreshed snapshot even when empty=\(empty)")
                XCTAssertTrue(completed, "\(stage): the single pull must enter and complete exactly once: \(report)")
                XCTAssertTrue(report.contains("cancelled=false"), "\(stage): refresh must complete without cancellation: \(report)")
                assertNativeRefreshReturned(observation, restingInset:restingInset)
                XCTAssertTrue(content.waitForExistence(timeout: 3))
                capture(app, "pull-refresh-\(page)-empty-\(empty)")
                XCTAssertEqual(counter.label, "2")
                app.terminate()
            }
        }
    }

    func testScoreRefreshControlRemainsActiveDuringSlowLoad() { assertScoreRefreshFeedback() }

    func testTimetableControlledRefreshAnimationReference() {
        let app = launch("interactions", arguments:["--preview-refresh", "--preview-slow-refresh", "--preview-controlled-refresh"])
        defer { app.terminate() }
        let counter = app.staticTexts["refresh-count"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "0")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(counter.label, "0")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "timetable-controlled-refresh-before-completion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("[RefreshFeedback] timetable: \(app.descendants(matching: .any).matching(identifier: "refresh-feedback-observation").firstMatch.label)")
        app.buttons["complete-controlled-refresh"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '1'"), evaluatedWith: counter)], timeout: 5), .completed)
    }

    func testOtherPagesRetainTimetableRefreshAnimation() {
        assertPagesRetainTimetableRefreshAnimation(["exams", "electives", "academic", "campus-leave", "campus-travel"])
    }

    func testCampusPagesRetainTimetableRefreshAnimation() {
        assertPagesRetainTimetableRefreshAnimation(["campus-leave", "campus-travel"])
    }

    private func assertPagesRetainTimetableRefreshAnimation(_ pages: [String]) {
        for page in pages {
            let app = launch(page, arguments:["--preview-refresh", "--preview-slow-refresh", "--preview-controlled-refresh"])
            let anchor: XCUIElement
            switch page {
            case "exams": anchor = app.staticTexts.matching(identifier: "机械设计基础").firstMatch
            case "electives": anchor = app.textFields["课程名 / 教师"]
            case "academic": anchor = app.buttons["academic-scores"]
            case "campus-leave": anchor = app.buttons["申请请假"]
            default: anchor = app.segmentedControls.firstMatch
            }
            XCTAssertTrue(anchor.waitForExistence(timeout: 8), page)
            if page == "campus-leave" {
                XCTAssertTrue(app.staticTexts["示例请假记录"].waitForExistence(timeout: 8))
            } else if page == "campus-travel" {
                XCTAssertTrue(app.staticTexts["示例区县"].waitForExistence(timeout: 8))
            }
            let observation = app.descendants(matching: .any).matching(identifier: "refresh-feedback-observation").firstMatch
            XCTAssertTrue(observation.waitForExistence(timeout: 5))
            let restingInset = nativeRefreshValue(observation.label, "adjustedTop")
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
            start.press(forDuration: 0.1, thenDragTo: end)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'entered=1; completed=0'"), evaluatedWith: observation)], timeout: 5), .completed, page)
            assertNativeHeldRefresh(observation.label, restingInset: restingInset, page: page)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(page)-held-refresh"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons["complete-controlled-refresh"].tap()
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'entered=1; completed=1'"), evaluatedWith: observation)], timeout: 8), .completed, page)
            assertNativeRefreshReturned(observation, restingInset: restingInset)
            app.terminate()
        }
    }

    private func assertScoreRefreshFeedback() {
        let mode = "with-top-bar"
        let app = launch("scores", arguments:["--preview-refresh", "--preview-long-list", "--preview-slow-refresh", "--preview-controlled-refresh"])
        defer { app.terminate() }
        let counter = app.descendants(matching: .any).matching(identifier: "academic-publication-count").firstMatch
        guard waitForInitialPublication(counter, in:app, stage:"score-\(mode)") else { return }
        let observation = app.descendants(matching: .any).matching(identifier: "refresh-feedback-observation").firstMatch
        guard let restingInset = waitForNativeRefreshAtRest(observation, stage:"score-\(mode)") else { return }
        let topContent = app.staticTexts["学业概览"]
        XCTAssertTrue(topContent.exists)
        print("[RefreshFeedback] \(mode) before-pull: \(observation.label)")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'entered=1; completed=0'"), evaluatedWith: observation)], timeout: 5), .completed)
        XCTAssertEqual(counter.label, "1", "The controlled read cannot publish before the test releases it")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "score-controlled-refresh-\(mode)-before-completion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("[RefreshFeedback] \(mode) after-release: \(observation.label)")
        assertNativeHeldRefresh(observation.label, restingInset: restingInset, page: "scores")
        let completion = app.buttons["complete-controlled-refresh"]
        XCTAssertTrue(completion.isHittable)
        completion.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '2'"), evaluatedWith: counter)], timeout: 8), .completed)
        let report = observation.label
        print("[RefreshFeedback] \(mode) after-publication: \(report)")
        capture(app, "score-slow-refresh-\(mode)-after-publication")
        XCTAssertTrue(report.contains("entered=1; completed=1"), "The refresh callback must finish exactly once: \(report)")
        XCTAssertTrue(report.contains("refreshingSeen=true"), "The native refresh control must become active: \(report)")
        XCTAssertTrue(report.contains("prematurelyStopped=false"), "The native refresh control must remain active until the awaited load finishes: \(report)")
        assertNativeRefreshReturned(observation, restingInset: restingInset)
    }

    /// Fixture publication has no performance deadline. Bound readiness once,
    /// and report its actual state before deciding whether a gesture is valid.
    private func waitForInitialPublication(_ counter: XCUIElement, in app: XCUIApplication, stage: String) -> Bool {
        let initial = NSPredicate { _, _ in counter.exists && counter.label == "1" }
        let result = XCTWaiter.wait(for:[expectation(for:initial,evaluatedWith:counter)],timeout:30)
        let count = counter.exists ? counter.label : "missing"
        let observation = app.descendants(matching:.any).matching(identifier:"refresh-feedback-observation").firstMatch
        let native = observation.exists ? observation.label : "missing observation"
        print("[RefreshReadiness] \(stage): result=\(result.rawValue); counter=\(count); applicationState=\(app.state.rawValue); \(native)")
        XCTAssertEqual(result,.completed,"\(stage): initial publication must be exactly 1 before any pull; actual counter=\(count), appState=\(app.state.rawValue), \(native)")
        return result == .completed
    }

    private func waitForNativeRefreshAtRest(_ observation: XCUIElement, stage: String) -> Double? {
        let atRest = NSPredicate { _, _ in
            guard observation.exists else { return false }
            let report = observation.label
            return report.contains("control=") && !report.contains("control=nil") &&
                report.contains("refreshing=false") && report.hasPrefix("entered=0; completed=0;") &&
                abs(self.nativeRefreshValue(report,"offsetY") + self.nativeRefreshValue(report,"adjustedTop")) < 1
        }
        let result = XCTWaiter.wait(for:[expectation(for:atRest,evaluatedWith:observation)],timeout:10)
        let report = observation.exists ? observation.label : "missing observation"
        print("[RefreshReadiness] \(stage) native-rest: result=\(result.rawValue); \(report)")
        XCTAssertEqual(result,.completed,"\(stage): wait for an attached native control at its resting offset before one pull: \(report)")
        return result == .completed ? nativeRefreshValue(report,"adjustedTop") : nil
    }

    // SwiftUI AX frames can remain unchanged while UIKit adjusts the refresh
    // inset. Verify the native held space and actual indicator placement, and
    // retain a screen screenshot for the visible result.
    private func nativeRefreshValue(_ report: String, _ key: String) -> Double {
        let prefix = key + "="
        guard let field = report.components(separatedBy: ";")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix(prefix) }) else { return .nan }
        return Double(field.dropFirst(prefix.count)) ?? .nan
    }

    private func assertNativeHeldRefresh(_ report: String, restingInset: Double, page: String) {
        XCTAssertGreaterThan(nativeRefreshValue(report, "adjustedTop") - restingInset, 40, "\(page): reserve the native refresh region")
        XCTAssertGreaterThan(-nativeRefreshValue(report, "offsetY") - restingInset, 40, "\(page): content stays below the refresh region")
        XCTAssertGreaterThan(nativeRefreshValue(report, "controlH"), 0, "\(page): indicator has visible height")
        XCTAssertGreaterThanOrEqual(nativeRefreshValue(report, "controlY") + 1,
                                   nativeRefreshValue(report, "scrollY") + restingInset,
                                   "\(page): indicator is below the page header")
    }

    private func assertNativeRefreshReturned(_ observation: XCUIElement, restingInset: Double) {
        let restored = NSPredicate { _, _ in
            let report = observation.label
            return abs(self.nativeRefreshValue(report, "adjustedTop") - restingInset) < 1 &&
                abs(self.nativeRefreshValue(report, "offsetY") + restingInset) < 1
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: restored, evaluatedWith: observation)], timeout: 5), .completed,
                       "Return to the resting native inset and offset after completion")
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
