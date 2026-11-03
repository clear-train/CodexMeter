import XCTest
@testable import CodexMeterCore

final class PopoverContentConfigurationTests: XCTestCase {
    func testDefaultsShowEverySectionWhileKeepingReserveQuotaHidden() {
        let configuration = PopoverContentConfiguration.defaultValue
        let fiveHour = makeWindow(id: "codex-primary", name: "5h", duration: 300, used: 20)
        let weekly = makeWindow(
            id: "codex-secondary",
            name: "Weekly quota",
            duration: 10_080,
            used: 30
        )
        let reserve = makeWindow(
            id: "base_model_inference-primary",
            name: "Gpt-Reserve · Weekly quota",
            duration: 10_080,
            used: 0
        )

        XCTAssertTrue(configuration.isSectionVisible(.quotaWindows))
        XCTAssertTrue(configuration.isSectionVisible(.resetCredits))
        XCTAssertTrue(configuration.isSectionVisible(.quotaHistory))
        XCTAssertTrue(configuration.isSectionVisible(.tokenActivity))
        XCTAssertEqual(
            configuration.sectionOrder,
            [.quotaWindows, .resetCredits, .quotaHistory, .tokenActivity]
        )
        XCTAssertTrue(configuration.isQuotaWindowVisible(fiveHour))
        XCTAssertTrue(configuration.isQuotaWindowVisible(weekly))
        XCTAssertFalse(configuration.isQuotaWindowVisible(reserve))
        XCTAssertNil(configuration.menuBarWindowID(for: .codex))
        XCTAssertNil(configuration.menuBarWindowID(for: .openCodeGo))
    }

    func testQuotaWindowsCanBeHiddenIndependentlyByStableIdentity() {
        var configuration = PopoverContentConfiguration.defaultValue
        let fiveHour = makeWindow(id: "codex-primary", name: "5h", duration: 300, used: 20)
        let weekly = makeWindow(id: "codex-secondary", name: "Weekly", duration: 10_080, used: 30)

        configuration.setQuotaWindow(fiveHour, visible: false)

        XCTAssertFalse(configuration.isQuotaWindowVisible(fiveHour))
        XCTAssertTrue(configuration.isQuotaWindowVisible(weekly))
        XCTAssertEqual(configuration.visibleQuotaWindows(from: [fiveHour, weekly]), [weekly])
    }

    func testSelectedMenuBarWindowUsesPersistedStableIdentity() {
        var configuration = PopoverContentConfiguration.defaultValue
        let fiveHour = makeWindow(id: "codex-primary", name: "5h", duration: 300, used: 80)
        let weekly = makeWindow(id: "codex-secondary", name: "Weekly", duration: 10_080, used: 20)

        configuration.setMenuBarWindowID(weekly.historyID, provider: .codex)

        XCTAssertEqual(
            configuration.selectedMenuBarWindow(from: [fiveHour, weekly], provider: .codex),
            weekly
        )
    }

    func testMissingMenuBarSelectionFallsBackToLowestRemainingQuota() {
        var configuration = PopoverContentConfiguration.defaultValue
        configuration.setMenuBarWindowID("duration:999:missing", provider: .codex)
        let fiveHour = makeWindow(id: "codex-primary", name: "5h", duration: 300, used: 80)
        let weekly = makeWindow(id: "codex-secondary", name: "Weekly", duration: 10_080, used: 20)

        XCTAssertEqual(configuration.selectedMenuBarWindow(from: [weekly, fiveHour], provider: .codex), fiveHour)
    }

    func testAutomaticSelectionUsesWeeklyQuotaWhenItHasLessRemaining() {
        let configuration = PopoverContentConfiguration.defaultValue
        let fiveHour = makeWindow(id: "codex-primary", name: "5h", duration: 300, used: 20)
        let weekly = makeWindow(
            id: "codex-secondary",
            name: "Weekly quota",
            duration: 10_080,
            used: 90
        )

        XCTAssertEqual(configuration.selectedMenuBarWindow(from: [fiveHour, weekly], provider: .codex), weekly)
    }

    func testAutomaticSelectionUsesLowestRemainingAcrossWeeklyBuckets() {
        let configuration = PopoverContentConfiguration.defaultValue
        let reserve = makeWindow(
            id: "base_model_inference-primary",
            name: "Gpt-Reserve · Weekly quota",
            duration: 10_080,
            used: 90
        )
        let weekly = makeWindow(
            id: "codex-secondary",
            name: "Weekly quota",
            duration: 10_080,
            used: 76
        )

        XCTAssertEqual(configuration.selectedMenuBarWindow(from: [reserve, weekly], provider: .codex), reserve)
    }

    func testHistoryDefaultIgnoresOtherWeeklyBuckets() {
        let reserve = QuotaHistoryWindow(
            id: "duration:10080:base_model_inference",
            name: "Gpt-Reserve · Weekly quota",
            windowDurationMins: 10_080,
            resetsAt: nil
        )
        let weekly = QuotaHistoryWindow(
            id: "duration:10080:codex",
            name: "Weekly quota",
            windowDurationMins: 10_080,
            resetsAt: nil
        )

        XCTAssertEqual(QuotaWindowSelection.preferredDefault(from: [reserve, weekly]), weekly)
    }

    func testMovingSectionChangesOnlyItsStoredOrder() {
        var configuration = PopoverContentConfiguration.defaultValue

        configuration.moveSection(.tokenActivity, by: -1)

        XCTAssertEqual(
            configuration.sectionOrder,
            [.quotaWindows, .resetCredits, .tokenActivity, .quotaHistory]
        )
        XCTAssertTrue(configuration.isSectionVisible(.resetCredits))
        XCTAssertTrue(configuration.isSectionVisible(.tokenActivity))
    }

    func testDecodingOlderEmptyPreferencesUsesCurrentDefaults() throws {
        let configuration = try JSONDecoder().decode(
            PopoverContentConfiguration.self,
            from: Data("{}".utf8)
        )

        XCTAssertEqual(configuration, .defaultValue)
    }

    func testMenuBarWindowSelectionIsStoredPerProvider() {
        var configuration = PopoverContentConfiguration.defaultValue
        let codexWeekly = makeWindow(id: "codex-secondary", name: "Weekly", duration: 10_080, used: 20)
        let goWeekly = makeWindow(id: "opencode-go-weekly", name: "Weekly", duration: 10_080, used: 60)
        let goRolling = makeWindow(id: "opencode-go-rolling", name: "5h", duration: 300, used: 5)

        configuration.setMenuBarWindowID(codexWeekly.historyID, provider: .codex)
        configuration.setMenuBarWindowID(goRolling.historyID, provider: .openCodeGo)

        XCTAssertEqual(
            configuration.selectedMenuBarWindow(from: [codexWeekly], provider: .codex),
            codexWeekly
        )
        XCTAssertEqual(
            configuration.selectedMenuBarWindow(from: [goWeekly, goRolling], provider: .openCodeGo),
            goRolling
        )
        XCTAssertEqual(
            configuration.selectedMenuBarWindow(from: [goWeekly, goRolling], provider: .openCodeGo)?.id,
            "opencode-go-rolling"
        )
    }

    func testMenuBarWindowSelectionCanBeClearedPerProvider() {
        var configuration = PopoverContentConfiguration.defaultValue
        let weekly = makeWindow(id: "opencode-go-weekly", name: "Weekly", duration: 10_080, used: 90)
        let rolling = makeWindow(id: "opencode-go-rolling", name: "5h", duration: 300, used: 10)

        configuration.setMenuBarWindowID(weekly.historyID, provider: .openCodeGo)
        configuration.setMenuBarWindowID(nil, provider: .openCodeGo)

        XCTAssertNil(configuration.menuBarWindowID(for: .openCodeGo))
        // Automatic mode follows the most constrained window.
        XCTAssertEqual(
            configuration.selectedMenuBarWindow(from: [rolling, weekly], provider: .openCodeGo),
            weekly
        )
    }

    func testDecodingLegacyMenuBarSelectionAssignsItToCodex() throws {
        let payload = Data(
            #"{"hiddenSections":[],"hiddenQuotaWindowIDs":[],"menuBarQuotaWindowID":"codex-secondary","sectionOrder":["quotaWindows","resetCredits","quotaHistory","tokenActivity"]}"#.utf8
        )

        let configuration = try JSONDecoder().decode(PopoverContentConfiguration.self, from: payload)

        XCTAssertEqual(configuration.menuBarWindowID(for: .codex), "codex-secondary")
        XCTAssertNil(configuration.menuBarWindowID(for: .openCodeGo))
    }

    private func makeWindow(
        id: String,
        name: String,
        duration: Int,
        used: Int
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            name: name,
            usedPercent: used,
            windowDurationMins: duration,
            resetsAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }
}
