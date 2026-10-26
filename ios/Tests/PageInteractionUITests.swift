import XCTest

// Pure sampling contract, also exercised by the local observation regression probe.
private struct RefreshObservationSample {
    let report: String
    private let fields: [String: String]

    init?(_ report: String) {
        // activeNative is historical evidence, never the current native geometry.
        let current = report.components(separatedBy: "; activeNative=[")[0]
        var fields: [String: String] = [:]
        for field in current.components(separatedBy: ";") {
            let pair = field.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard pair.count == 2, fields[String(pair[0])] == nil else { return nil }
            fields[String(pair[0])] = String(pair[1])
        }
        for key in ["entered", "completed"] {
            guard let value = fields[key], let number = Int(value), number >= 0 else { return nil }
        }
        for key in ["cancelled", "active", "refreshingSeen", "prematurelyStopped", "refreshing", "hidden"] {
            guard let value = fields[key], ["true", "false"].contains(value) else { return nil }
        }
        for key in ["alpha", "controlY", "controlH", "maxPull", "scrollY", "offsetY", "adjustedTop", "insetTop"] {
            guard let value = fields[key], let number = Double(value), number.isFinite else { return nil }
        }
        guard let control = fields["control"], !control.isEmpty, control != "nil" else { return nil }
        self.report = report
        self.fields = fields
    }

    func value(_ key: String) -> Double { Double(fields[key] ?? "") ?? .nan }

    var isInitialRest: Bool {
        fields["entered"] == "0" && fields["completed"] == "0" &&
        fields["cancelled"] == "false" && fields["active"] == "false" && fields["refreshing"] == "false" &&
        abs(value("offsetY") + value("adjustedTop")) < 1
    }

    func isHeld(restingInset: Double) -> Bool {
        fields["entered"] == "1" && fields["completed"] == "0" &&
        fields["cancelled"] == "false" && fields["active"] == "true" && fields["refreshing"] == "true" &&
        fields["refreshingSeen"] == "true" && fields["prematurelyStopped"] == "false" &&
        fields["hidden"] == "false" && value("alpha") > 0 &&
        value("adjustedTop") - restingInset > 40 && -value("offsetY") - restingInset > 40 &&
        value("controlH") > 0 && value("controlY") + 1 >= value("scrollY") + restingInset
    }

    func hasReturned(restingInset: Double) -> Bool {
        fields["entered"] == "1" && fields["completed"] == "1" &&
        fields["cancelled"] == "false" && fields["active"] == "false" && fields["refreshing"] == "false" &&
        fields["refreshingSeen"] == "true" && fields["prematurelyStopped"] == "false" &&
        abs(value("adjustedTop") - restingInset) < 1 && abs(value("offsetY") + restingInset) < 1
    }
}

private struct RefreshObservationPoll {
    private(set) var attempts = 0
    private(set) var lastReport = "not sampled"
    private(set) var matched: RefreshObservationSample?

    mutating func evaluate(read: () -> String?, matching: (RefreshObservationSample) -> Bool) -> Bool {
        attempts += 1
        lastReport = read() ?? "missing observation"
        guard let sample = RefreshObservationSample(lastReport), matching(sample) else { return false }
        matched = sample
        return true
    }
}

final class PageInteractionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCompleteSelectedIncludesClosedBatch() {
        let app = launch("electives", arguments:["--preview-complete-selected"])
        XCTAssertTrue(app.staticTexts["示例线上已选课"].waitForExistence(timeout:8))
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","已选")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["示例线下已选课"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["示例配课课程"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","仅供查看")).firstMatch.exists)
        let search = app.textFields["课程名 / 教师"]
        search.tap(); search.typeText("示例线下")
        XCTAssertTrue(app.staticTexts["示例线下已选课"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["正常修读"].exists)
        XCTAssertFalse(app.buttons["退课"].exists)
        capture(app,"complete-selected-closed-batch")
    }

    func testClosedElectiveChannelPreservesControlsAndEnrolledResults() {
        let app = launch("electives", arguments: ["--preview-closed-catalog", "--preview-complete-selected"])
        let closed = app.staticTexts["选课通道暂未开启"]
        XCTAssertTrue(closed.waitForExistence(timeout: 8))
        let search = app.textFields["课程名 / 教师"]
        XCTAssertTrue(search.isHittable)
        let anchoredY = search.frame.minY
        XCTAssertLessThan(anchoredY, app.frame.height * 0.3, "Closed state controls stay at the top")
        XCTAssertEqual(closed.frame.midX, app.frame.midX, accuracy: 3)
        XCTAssertGreaterThan(closed.frame.midY, app.frame.height * 0.42, "Empty message should be centered, not attached to the filters")
        XCTAssertLessThan(closed.frame.midY, app.frame.height * 0.65)
        for title in ["全部", "可选", "有余量"] {
            app.buttons[title].tap()
            XCTAssertTrue(closed.exists)
            XCTAssertEqual(search.frame.minY, anchoredY, accuracy: 2)
            XCTAssertFalse(app.staticTexts["加载失败，请重试"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "接口返回错误")).firstMatch.exists)
        }
        capture(app, "electives-closed-channel")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "已选")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["示例线下已选课"].waitForExistence(timeout: 5))
        XCTAssertFalse(closed.exists)
        XCTAssertEqual(search.frame.minY, anchoredY, accuracy: 2)
        capture(app, "electives-closed-enrolled-results")
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
        reason.tap()
        // First input removes validation messages and reflows the form. Send
        // every literal character once and acknowledge it before continuing;
        // never repair or retry missing input to conceal a failed interaction.
        var acknowledged = ""
        for character in "reason" {
            reason.typeText(String(character))
            acknowledged.append(character)
            let expected = acknowledged
            let received = NSPredicate { _, _ in (reason.value as? String ?? "") == expected }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: received, evaluatedWith: reason)], timeout: 3), .completed,
                           "Literal input must be acknowledged without correction: \(reason.value as? String ?? "missing")")
        }
        reason.typeText(" 18000000000")
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
        XCTAssertTrue(review.isHittable)
        XCTAssertGreaterThanOrEqual(review.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(review.frame.maxX, app.frame.maxX + 1,
                                 "Large text cannot push the primary capsule beyond the physical screen")
        XCTAssertEqual(review.frame.minX - app.frame.minX, app.frame.maxX - review.frame.maxX, accuracy: 2,
                       "The primary capsule retains symmetric concentric side insets")
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
        let building = app.buttons["选择楼栋"]
        XCTAssertTrue(building.waitForExistence(timeout: 8))
        XCTAssertEqual(building.value as? String, "示例宿舍 1 栋")
        XCTAssertEqual(app.buttons["选择房间"].value as? String, "101 室")
        func digit(_ place: Int) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "meter-digit-\(place)").firstMatch
        }
        let increase = app.buttons["meter-digit-100-increase"]
        XCTAssertTrue(increase.waitForExistence(timeout: 8))
        revealMeterControl(increase, in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "剩余金额").firstMatch.exists)
        for _ in 0..<4 { increase.tap() }
        XCTAssertEqual(digit(100).value as? String, "4")
        XCTAssertEqual(digit(10).value as? String, "0")
        XCTAssertEqual(digit(1).value as? String, "0")
        XCTAssertFalse(increase.isEnabled)
        let preset = app.buttons["充值100元"]
        revealMeterControl(preset, in: app)
        preset.tap()
        let decrease = app.buttons["meter-digit-100-decrease"]
        revealMeterControl(decrease, in: app, upwards: false)
        decrease.tap()
        XCTAssertEqual(digit(100).value as? String, "0")
        XCTAssertEqual(digit(10).value as? String, "1")
        XCTAssertEqual(digit(1).value as? String, "0")
        XCTAssertFalse(app.buttons["meter-digit-10-decrease"].isEnabled)
        XCTAssertFalse(app.buttons["meter-digit-1-decrease"].isEnabled)
        app.buttons["meter-digit-1-increase"].tap()
        XCTAssertEqual(digit(1).value as? String, "1")
        app.buttons["meter-digit-1-decrease"].tap()
        XCTAssertEqual(digit(1).value as? String, "0")
        let start = digit(1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = digit(1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(digit(1).value as? String, "1", "A short upward turn advances the physical thumbwheel once")
        XCTAssertFalse(app.buttons["立即缴费"].isEnabled, "Synthetic previews must never enable a real payment")
        capture(app, "campus-electricity-amount")
    }

    private func revealMeterControl(_ control: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<8 where !control.isHittable {
            // Scroll on the housing edge, away from the adjustable thumbwheels.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.75 : 0.25))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.25 : 0.75))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(control.isHittable)
    }

    func testPhysicalMeterAdaptiveControls() {
        defer { XCUIDevice.shared.orientation = .portrait }
        for large in [false, true] {
            XCUIDevice.shared.orientation = .portrait
            let app = launch("campus-electricity", largeText: large)
            if !large {
                XCUIDevice.shared.orientation = .landscapeLeft
                let landscape = NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }
                XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: landscape, evaluatedWith: app)], timeout: 8), .completed)
            }
            func screen(_ name: String) {
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            }
            let building = app.buttons["选择楼栋"]
            XCTAssertTrue(building.waitForExistence(timeout: 8))
            revealMeterControl(building, in: app)
            screen("physical-meter-top-\(large ? "large" : "landscape")")
            let increase = app.buttons["meter-digit-1-increase"]
            revealMeterControl(increase, in: app)
            XCTAssertGreaterThanOrEqual(increase.frame.height, 44)
            increase.tap()
            let ones = app.descendants(matching: .any).matching(identifier: "meter-digit-1").firstMatch
            XCTAssertEqual(ones.value as? String, "1")
            let pay = app.buttons["立即缴费"]
            revealMeterControl(pay, in: app)
            XCTAssertGreaterThanOrEqual(pay.frame.height, 44)
            XCTAssertFalse(pay.isEnabled)
            XCTAssertTrue(app.buttons["返回"].isHittable, "Return remains available after scrolling the meter")
            screen("physical-meter-payment-\(large ? "large" : "landscape")")
            app.terminate()
        }
    }

    func testPhysicalMeterReturnsToCampus() {
        let app = launch("campus")
        let entry = app.buttons["campus-electricity"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        let back = app.buttons["返回"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertTrue(back.isHittable)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertTrue(app.buttons["选择楼栋"].exists)
        let pay = app.buttons["立即缴费"]
        XCTAssertTrue(pay.isHittable, "The standard meter opens with its embedded payment key visible")
        XCTAssertLessThanOrEqual(pay.frame.maxY, app.windows.firstMatch.frame.maxY,
                                "The initial viewport must show the whole payment key")
        capture(app, "physical-meter-initial-viewport")
        revealMeterControl(app.buttons["立即缴费"], in: app)
        XCTAssertTrue(back.isHittable)
        capture(app, "physical-meter-from-campus")
        back.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
    }

    func testPhysicalMeterConfirmationRemainsExplicit() {
        let app = launch("campus-electricity-confirmation")
        let confirm = app.buttons["确认支付 50 元"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        revealMeterControl(confirm, in: app)
        XCTAssertTrue(app.staticTexts["示例宿舍 1 栋 · 101 室"].exists)
        capture(app, "physical-meter-confirmation")
        let close = app.buttons["关闭确认缴费"]
        revealMeterControl(close, in: app, upwards: false)
        close.tap()
        XCTAssertFalse(confirm.exists)
        XCTAssertTrue(app.buttons["立即缴费"].exists)
    }

    func testPhysicalMeterSameSelectionKeepsRoomAndBalance() {
        let app = launch("campus-electricity")
        for (label, field) in [("选择楼栋", "building"), ("选择房间", "room")] {
            let selector = app.buttons[label]
            XCTAssertTrue(selector.waitForExistence(timeout: 8))
            revealMeterControl(selector, in: app)
            selector.tap()
            let current = app.buttons["meter-option-\(field)-0"]
            XCTAssertTrue(current.waitForExistence(timeout: 5))
            XCTAssertEqual(current.value as? String, "已选择")
            capture(app, "physical-meter-\(field)-selector")
            current.tap()
            XCTAssertTrue(selector.waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["选择房间"].value as? String, "101 室")
            let balance = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@ AND value == %@", "剩余金额", "36.80 元")).firstMatch
            XCTAssertTrue(balance.exists, "Choosing the checked row must preserve dependent room and verified balance")
        }
    }

    func testDetailTabsHideAndReturnWithHome() {
        let app = launch("academic")
        let scores = app.buttons["academic-scores"]
        XCTAssertTrue(scores.waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        scores.tap()
        let back = app.buttons["返回"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        let hiddenTabs = NSPredicate { _, _ in !app.tabBars.firstMatch.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: hiddenTabs, evaluatedWith: app)], timeout: 5), .completed)
        back.tap()
        XCTAssertTrue(scores.waitForExistence(timeout: 5))
        let visibleTabs = NSPredicate { _, _ in app.tabBars.firstMatch.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: visibleTabs, evaluatedWith: app)], timeout: 5), .completed)
        app.tabBars.buttons["校园"].tap()
        let leave = app.buttons["campus-leave"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        leave.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: hiddenTabs, evaluatedWith: app)], timeout: 5), .completed)
        back.tap()
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: visibleTabs, evaluatedWith: app)], timeout: 5), .completed)
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
            if page == "campus-electricity" { revealMeterControl(action, in: app) }
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            capture(app, "campus-largest-type-\(page)")
            app.terminate()
            app = launch(page)
            XCUIDevice.shared.orientation = .landscapeLeft
            var previousWindow: CGRect?
            var stableSamples = 0
            let landscape = NSPredicate { _, _ in
                let window = app.windows.firstMatch.frame
                guard app.frame.width > app.frame.height, window.width > window.height else {
                    stableSamples = 0; previousWindow = nil; return false
                }
                stableSamples = previousWindow == window ? stableSamples + 1 : 0
                previousWindow = window
                return stableSamples >= 3
            }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: landscape, evaluatedWith: app)], timeout: 10), .completed)
            let landscapeAction = app.buttons[page == "campus-electricity" ? "立即缴费" : "campus-form-review"]
            if page == "campus-electricity" { revealMeterControl(landscapeAction, in: app) }
            XCTAssertTrue(landscapeAction.isHittable)
            add(XCTAttachment(string: "orientation=\(XCUIDevice.shared.orientation.rawValue) app=\(app.frame) window=\(app.windows.firstMatch.frame) action=\(landscapeAction.frame)"))
            let deviceCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            deviceCapture.name = "campus-landscape-device-\(page)"
            deviceCapture.lifetime = .keepAlways
            add(deviceCapture)
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

    func testBackgroundRoundTripRetainsVisibleContent() {
        for (page, title) in [("schedule", "高等数学"), ("scores", "高等数学"), ("campus-leave", "示例请假记录")] {
            let app = launch(page)
            let content = app.staticTexts.matching(identifier: title).firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 8))
            capture(app, "background-before-\(page)")
            // A real Home gesture plus pause exposes the actual app-switcher
            // snapshot. Capture it separately from the foreground AX checks.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
            let switcher = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            switcher.name = "background-switcher-\(page)"
            switcher.lifetime = .keepAlways
            add(switcher)
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(content.waitForExistence(timeout: 5), "Previously loaded content must survive foreground restoration")
            XCTAssertTrue(content.isHittable)
            capture(app, "background-restored-\(page)")
            app.terminate()
        }
    }

    func testDetailSheetsKeepContentAndCloseReachable() {
        for page in ["course", "account", "elective-detail", "enrolled-detail"] {
            for large in [false, true] {
              let edges: [CGVector] = page == "course"
                  ? [CGVector(dx: -21, dy: 0), CGVector(dx: 21, dy: 0),
                     CGVector(dx: 0, dy: -21), CGVector(dx: 0, dy: 21)]
                  : [CGVector(dx: 0, dy: 21)]
              for (edgeIndex, edge) in edges.enumerated() {
                let app = launch(page, largeText: large)
                let close = app.buttons[page == "account" ? "关闭账号" : "关闭课程详情"]
                XCTAssertTrue(close.waitForExistence(timeout: 8))
                XCTAssertTrue(close.isHittable)
                if page == "account" {
                    XCTAssertTrue(app.staticTexts["预览同学"].isHittable)
                    if !large {
                        let account = app.staticTexts["示例账号"]
                        XCTAssertTrue(account.isHittable)
                        XCTAssertLessThanOrEqual(account.frame.maxY, app.buttons["退出登录"].frame.minY,
                                                 "The collapsed account sheet must keep the identity above its footer")
                    }
                }
                capture(app, "detail-sheet-\(page)-\(large ? "large" : "standard")-edge\(edgeIndex)")
                // Exercise real near-edge touches with a 1pt interior margin
                // around the recommended 44pt target, rather than glyph bounds.
                add(XCTAttachment(string: "close=\(close.frame) edge=\(edge)"))
                close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .withOffset(edge).tap()
                let dismissed = NSPredicate { _, _ in !close.exists }
                XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: dismissed, evaluatedWith: app)], timeout: 5), .completed,
                               "The close control must dismiss for near-edge touches 21pt from center")
                app.terminate()
              }
            }
        }
    }

    func testTodayCoursesSwitchesToAllTimetables() {
        let app = launch("today")
        let mode = app.buttons["schedule-mode-switch"]
        XCTAssertTrue(mode.waitForExistence(timeout: 8))
        XCTAssertEqual(mode.label, "今日课程")
        let first = app.buttons["today-course-0"]
        let second = app.buttons["today-course-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("大学物理"))
        XCTAssertTrue(second.label.contains("高等数学"))
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        XCTAssertFalse(app.buttons["本周"].exists)
        capture(app, "today-course-timeline")
        first.tap()
        let close = app.buttons["关闭课程详情"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        mode.tap()
        XCTAssertEqual(mode.label, "所有课表")
        let currentWeek = app.buttons["本周"]
        XCTAssertTrue(currentWeek.waitForExistence(timeout: 5))
        XCTAssertTrue(currentWeek.isHittable)
        XCTAssertFalse(app.staticTexts["第 7 周"].exists,
                       "All mode keeps the original capsules without the added current-week heading")
        capture(app, "all-timetables-capsules")
        app.buttons["第 8 周"].tap()
        mode.tap()
        XCTAssertEqual(mode.label, "今日课程")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("大学物理"))
    }

    func testTodayCoursesDistinguishesEmptyFromUnknownWeek() {
        let empty = launch("today-empty")
        XCTAssertTrue(empty.staticTexts["今天没有课程"].waitForExistence(timeout: 8))
        XCTAssertFalse(empty.buttons["today-course-0"].exists)
        capture(empty, "today-empty")
        empty.terminate()
        let unknown = launch("today-unverified")
        XCTAssertTrue(unknown.staticTexts["暂时无法确认今日课程"].waitForExistence(timeout: 8))
        XCTAssertFalse(unknown.staticTexts["今天没有课程"].exists)
        XCTAssertTrue(unknown.buttons["schedule-mode-switch"].isHittable)
        capture(unknown, "today-unverified")
    }

    func testTodayCoursesLargeTextKeepsModeAndDetailsReachable() {
        let app = launch("today", largeText: true)
        let mode = app.buttons["schedule-mode-switch"]
        XCTAssertTrue(mode.waitForExistence(timeout: 8))
        XCTAssertTrue(mode.isHittable)
        XCTAssertTrue(app.buttons["账号"].isHittable)
        let first = app.buttons["today-course-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
        capture(app, "today-largest-type")
        first.tap()
        XCTAssertTrue(app.buttons["关闭课程详情"].waitForExistence(timeout: 5))
    }

    func testWebLoginControlsUseMatchingNativeGeometry() {
        let app = launch("web-login")
        let close = app.buttons["关闭网页登录"]
        let refresh = app.buttons["刷新网页"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertTrue(refresh.isHittable)
        XCTAssertGreaterThanOrEqual(refresh.frame.width, 44)
        XCTAssertEqual(close.frame.width, refresh.frame.width, accuracy: 1)
        XCTAssertEqual(close.frame.height, refresh.frame.height, accuracy: 1)
        XCTAssertEqual(close.frame.midY, refresh.frame.midY, accuracy: 1)
        refresh.tap()
        XCTAssertTrue(close.isHittable)
        capture(app, "web-login-native-controls")
    }

    func testRecordInitialLoadingIsCentered() {
        for (page, title) in [("campus-leave", "正在读取请假记录…"), ("campus-travel", "正在读取离校记录…")] {
            let app = launch(page, arguments: ["--preview-record-loading"])
            let message = app.staticTexts[title]
            XCTAssertTrue(message.waitForExistence(timeout: 8))
            XCTAssertEqual(message.frame.midX, app.frame.midX, accuracy: 3)
            XCTAssertGreaterThan(message.frame.midY, app.frame.height * 0.44)
            XCTAssertLessThan(message.frame.midY, app.frame.height * 0.60)
            XCTAssertTrue(app.buttons["campus-record-add"].isHittable)
            capture(app, "initial-loading-\(page)")
            app.terminate()
        }
    }

    func testCampusEmptyStatesStayCenteredWithLargerAddControl() {
        for (page, title) in [("campus-leave", "暂无请假记录"), ("campus-travel", "暂无离校记录")] {
            let app = launch(page, empty: true)
            let message = app.staticTexts[title]
            XCTAssertTrue(message.waitForExistence(timeout: 8))
            XCTAssertEqual(message.frame.midX, app.frame.midX, accuracy: 3)
            XCTAssertGreaterThan(message.frame.midY, app.frame.height * 0.42)
            XCTAssertLessThan(message.frame.midY, app.frame.height * 0.65)
            let addControl = app.buttons["campus-record-add"]
            XCTAssertTrue(addControl.isHittable)
            XCTAssertEqual(addControl.frame.width, 64, accuracy: 1)
            XCTAssertEqual(addControl.frame.height, 64, accuracy: 1)
            capture(app, "empty-centered-\(page)")
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
                let control = app.buttons[page == "schedule" || page == "academic" ? "账号" : "返回"]
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
            let back = app.buttons["返回"]
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
            XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 5))
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
        func motionSamples(_ key: String, in report: String) -> Int {
            let prefix = key + "="
            guard let field = report.split(separator: " ").first(where: { $0.hasPrefix(prefix) }) else { return 0 }
            return Int(field.dropFirst(prefix.count)) ?? 0
        }
        for page in ["scores", "exams", "electives"] {
            let app = launch("academic", transition: true)
            let entry = app.buttons["academic-\(page)"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            let back = app.buttons["返回"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            // The cold simulator can expose the back button before the page's
            // loading branch and native appearance transition have settled.
            let contentReady = page == "electives"
                ? app.textFields["课程名 / 教师"]
                : app.descendants(matching: .any).matching(identifier: "term-header-2026-2027-1").firstMatch
            XCTAssertTrue(contentReady.waitForExistence(timeout: 8))
            XCTAssertTrue(contentReady.isHittable)
            let diagnostic = app.staticTexts["transition-diagnostics"]
            let pushed = NSPredicate { _, _ in motionSamples("tabDown", in: diagnostic.label) > 0 }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: pushed, evaluatedWith: diagnostic)], timeout: 5), .completed,
                           "Push must contain actual simultaneous tab-bar sinking and fading: \(diagnostic.label)")
            let travel = diagnostic.label.split(separator: " ").first { $0.hasPrefix("tabYRange=") }
                .flatMap { Double($0.dropFirst("tabYRange=".count)) } ?? 999
            XCTAssertGreaterThan(travel, 5, "The tab bar must visibly sink")
            XCTAssertLessThanOrEqual(travel, 24, "Use short 20pt travel, not a whole tab-bar height")
            let before = back.frame
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.45))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.5)
            capture(app, "cancelled-pop-\(page)")
            let reversed = NSPredicate { _, _ in motionSamples("tabUp", in: diagnostic.label) > 0 }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: reversed, evaluatedWith: diagnostic)], timeout: 5), .completed,
                           "Pop must contain actual simultaneous rising and fading in: \(diagnostic.label)")
            let sampleCount = Int(app.staticTexts["transition-samples"].label) ?? 0
            let drift = Double(app.staticTexts["transition-drift"].label) ?? 999
            print("Transition diagnostic \(page): \(app.staticTexts["transition-diagnostics"].label)")
            add(XCTAttachment(string: "\(page): \(sampleCount) interactive samples, maximum local title drift \(drift)pt"))
            XCTAssertGreaterThan(sampleCount, 3, "Must measure actual in-flight interactive frames")
            XCTAssertLessThanOrEqual(drift, 2, "Title must travel with the detail page during a cancelled swipe")
            XCTAssertTrue(back.isHittable)
            XCTAssertFalse(app.tabBars.firstMatch.isHittable, "Cancelled pop keeps the detail tab bar hidden")
            XCTAssertEqual(back.frame.midX, before.midX, accuracy: 2)
            app.terminate()
        }
    }

    func testAcademicHomeWithoutReminderHasStableSpacedEntries() {
        let app = launch("academic")
        let first = app.buttons["academic-scores"]
        let last = app.buttons["academic-electives"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["接下来的考试"].exists)
        let before = first.frame
        let account = app.buttons["账号"]
        XCTAssertGreaterThanOrEqual(before.minY - account.frame.maxY, 24)
        XCTAssertGreaterThanOrEqual(before.height, 88, "Grouped service rows keep a generous touch target")
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
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 5))
        let header = app.descendants(matching: .any).matching(identifier: "term-header-2026-2027-1").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == 'floating'"), evaluatedWith: header)], timeout: 5) == .completed,
                      "Native content-pop recognition must not steal a vertical scroll")
        XCTAssertTrue(app.buttons["返回"].isHittable)
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
                guard waitForPublication(in:app, expected:"1", stage:stage) else { app.terminate(); continue }
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
                guard let restingInset = waitForNativeRefreshAtRest(in:app, stage:stage) else { app.terminate(); continue }
                logPageRefreshDiagnostic(app, "\(page)-empty-\(empty)-before-pull")
                // Use the native proof's body gesture, below the pinned term header.
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
                start.press(forDuration: 0.1, thenDragTo: end)
                let refreshed = waitForPublication(in:app, expected:"2", stage:stage)
                let returned = waitForRefreshObservation(in:app, stage:"\(stage) returned") {
                    $0.hasReturned(restingInset:restingInset)
                }
                logPageRefreshDiagnostic(app, "\(page)-empty-\(empty)-after-pull")
                XCTAssertTrue(refreshed, "\(page) must publish exactly one refreshed snapshot even when empty=\(empty)")
                XCTAssertNotNil(returned, "\(stage): the single pull must complete exactly once and return to its native rest")
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
        assertPagesRetainTimetableRefreshAnimation(["exams", "electives", "campus-leave", "campus-travel"])
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
            guard let restingInset = waitForNativeRefreshAtRest(in:app, stage:page) else { app.terminate(); continue }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
            start.press(forDuration: 0.1, thenDragTo: end)
            guard let held = waitForRefreshObservation(in:app, stage:"\(page) held", matching:{
                $0.isHeld(restingInset:restingInset)
            }) else { app.terminate(); continue }
            assertNativeHeldRefresh(held.report, restingInset: restingInset, page: page)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(page)-held-refresh"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons["complete-controlled-refresh"].tap()
            _ = waitForRefreshObservation(in:app, stage:"\(page) returned") {
                $0.hasReturned(restingInset:restingInset)
            }
            app.terminate()
        }
    }

    private func assertScoreRefreshFeedback() {
        let mode = "with-top-bar"
        let app = launch("scores", arguments:["--preview-refresh", "--preview-long-list", "--preview-slow-refresh", "--preview-controlled-refresh"])
        defer { app.terminate() }
        let counter = app.descendants(matching: .any).matching(identifier: "academic-publication-count").firstMatch
        guard waitForPublication(in:app, expected:"1", stage:"score-\(mode)") else { return }
        guard let restingInset = waitForNativeRefreshAtRest(in:app, stage:"score-\(mode)") else { return }
        let topContent = app.staticTexts["学业概览"]
        XCTAssertTrue(topContent.exists)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        start.press(forDuration: 0.1, thenDragTo: end)
        guard let held = waitForRefreshObservation(in:app, stage:"score-\(mode) held", matching:{
            $0.isHeld(restingInset:restingInset)
        }) else { return }
        XCTAssertEqual(counter.label, "1", "The controlled read cannot publish before the test releases it")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "score-controlled-refresh-\(mode)-before-completion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("[RefreshFeedback] \(mode) after-release: \(held.report)")
        assertNativeHeldRefresh(held.report, restingInset: restingInset, page: "scores")
        let completion = app.buttons["complete-controlled-refresh"]
        XCTAssertTrue(completion.isHittable)
        completion.tap()
        XCTAssertTrue(waitForPublication(in:app, expected:"2", stage:"score-\(mode)"))
        guard let returned = waitForRefreshObservation(in:app, stage:"score-\(mode) returned", matching:{
            $0.hasReturned(restingInset:restingInset)
        }) else { return }
        print("[RefreshFeedback] \(mode) after-publication: \(returned.report)")
        capture(app, "score-slow-refresh-\(mode)-after-publication")
    }

    /// These are AX delivery bounds, not refresh-performance deadlines. The
    /// native controlled gate stays held until the single explicit tap.
    private func waitForPublication(in app: XCUIApplication, expected: String, stage: String) -> Bool {
        var lastExactMatch = false
        var attempts = 0
        let started = Date()
        // Match both attributes in one AX query. An exists check followed by
        // label can re-resolve the element and exhaust the delivery window.
        let exactPublication = NSPredicate(format:"identifier == %@ AND label == %@",
                                           "academic-publication-count", expected)
        let predicate = NSPredicate { _, _ in
            attempts += 1
            lastExactMatch = app.descendants(matching:.any).matching(exactPublication).firstMatch.exists
            return lastExactMatch
        }
        let result = XCTWaiter.wait(for:[expectation(for:predicate,evaluatedWith:app)],timeout:30)
        let diagnostic = "\(stage): expected publication=\(expected); result=\(result.rawValue); polls=\(attempts); elapsed=\(Date().timeIntervalSince(started)); lastExactMatch=\(lastExactMatch)"
        print("[RefreshPublication] \(diagnostic)")
        XCTAssertEqual(result,.completed,diagnostic)
        return result == .completed
    }

    private func waitForNativeRefreshAtRest(in app: XCUIApplication, stage: String) -> Double? {
        waitForRefreshObservation(in:app, stage:"\(stage) initial-rest", matching:{ $0.isInitialRest })?.value("adjustedTop")
    }

    /// Re-query at every poll and retain the exact satisfying sample. Re-reading
    /// a captured element after success can resolve a different SwiftUI AX proxy.
    /// Each native state is stable until the next test action; no action is retried.
    private func waitForRefreshObservation(in app: XCUIApplication, stage: String,
                                           matching: @escaping (RefreshObservationSample) -> Bool) -> RefreshObservationSample? {
        var poll = RefreshObservationPoll()
        let started = Date()
        let predicate = NSPredicate { _, _ in
            poll.evaluate(read:{
                let current = app.descendants(matching:.any).matching(identifier:"refresh-feedback-observation").firstMatch
                return current.exists ? current.label : nil
            }, matching:matching)
        }
        let result = XCTWaiter.wait(for:[expectation(for:predicate,evaluatedWith:app)],timeout:30)
        let diagnostic = "\(stage): result=\(result.rawValue); polls=\(poll.attempts); elapsed=\(Date().timeIntervalSince(started)); last-sample=\(poll.lastReport)"
        print("[RefreshObservation] \(diagnostic)")
        XCTAssertEqual(result,.completed,diagnostic)
        return result == .completed ? poll.matched : nil
    }

    // SwiftUI AX frames can remain unchanged while UIKit adjusts the refresh
    // inset. Check the native region/indicator from the SAME matched sample;
    // retain a screenshot separately for the visible result.
    private func nativeRefreshValue(_ report: String, _ key: String) -> Double {
        RefreshObservationSample(report)?.value(key) ?? .nan
    }

    private func assertNativeHeldRefresh(_ report: String, restingInset: Double, page: String) {
        XCTAssertGreaterThan(nativeRefreshValue(report, "adjustedTop") - restingInset, 40, "\(page): reserve the native refresh region")
        XCTAssertGreaterThan(-nativeRefreshValue(report, "offsetY") - restingInset, 40, "\(page): content stays below the refresh region")
        XCTAssertGreaterThan(nativeRefreshValue(report, "controlH"), 0, "\(page): indicator has visible height")
        XCTAssertGreaterThanOrEqual(nativeRefreshValue(report, "controlY") + 1,
                                   nativeRefreshValue(report, "scrollY") + restingInset,
                                   "\(page): indicator is below the page header")
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

    func testScoreBreakdownExpandsAndHomeKeepsOnlyEntryTitles() {
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
        app.buttons["返回"].tap()
        XCTAssertEqual(app.buttons["academic-scores"].label, "成绩查询")
        XCTAssertEqual(app.buttons["academic-exams"].label, "考试安排")
        XCTAssertEqual(app.buttons["academic-electives"].label, "选课")
    }

    func testSemesterMenusReachHistoricalContent() {
        for (page, course) in [("scores", "历史学期课程"), ("exams", "历史学期考试")] {
            let app = launch(page, longList: true)
            let menu = app.buttons[page == "scores" ? "score-term-filter" : "exam-term-filter"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(menu.frame.width, 44)
            XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
            let back = app.buttons["返回"]
            XCTAssertEqual(menu.frame.width, back.frame.width, accuracy: 1, "Filter and back circles have the same rendered diameter")
            XCTAssertEqual(menu.frame.height, back.frame.height, accuracy: 1)
            menu.tap()
            let target = app.buttons["2025–2026 学年 · 第二学期"]
            XCTAssertTrue(target.waitForExistence(timeout: 3))
            target.tap()
            let historical = app.staticTexts[course]
            XCTAssertTrue(historical.waitForExistence(timeout: 3))
            XCTAssertTrue(historical.isHittable)
            XCTAssertTrue(app.buttons["返回"].isHittable)
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
            let control = page == "schedule" ? app.buttons["本周"] : app.buttons["返回"]
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

                let menu = app.buttons[page == "scores" ? "score-term-filter" : "exam-term-filter"]
                XCTAssertTrue(reveal(menu, in: app, movingForward: false), "Large-text semester menu must be reachable")
                menu.tap()
                let target = app.buttons["2025–2026 学年 · 第二学期"]
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                XCTAssertTrue(target.isHittable)
                target.tap()
                let historical = app.staticTexts["机械设计基础"]
                XCTAssertTrue(historical.waitForExistence(timeout: 5))
                XCTAssertTrue(historical.isHittable, "Historical score must be visible after the large-text jump")
                capture(app, "large-text-scores-historical-term")
            } else if page == "exams" {
                let menu = app.buttons[page == "scores" ? "score-term-filter" : "exam-term-filter"]
                XCTAssertTrue(reveal(menu, in: app, movingForward: true), "Large-text exam semester menu must be reachable")
                menu.tap()
                let target = app.buttons["2025–2026 学年 · 第二学期"]
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                XCTAssertTrue(target.isHittable)
                target.tap()
                let historical = app.staticTexts["历史学期考试"]
                XCTAssertTrue(historical.waitForExistence(timeout: 5))
                XCTAssertTrue(historical.isHittable, "Historical exam must be visible after the large-text jump")
                let examDay = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "考试日期", "6月20日")).firstMatch
                XCTAssertTrue(examDay.waitForExistence(timeout: 5))
                XCTAssertTrue(examDay.isHittable, "Historical ExamRow date rail must be visible at large text")
                capture(app, "large-text-exams-historical-date-rail")
            }
            app.terminate()
        }
    }
}
