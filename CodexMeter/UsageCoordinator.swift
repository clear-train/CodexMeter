import Combine
import Foundation

/// Presents one active quota source to the UI.
///
/// Both sources stay alive so switching providers keeps warm state, but only the
/// active source may own the visible history partition and refresh timer.
@MainActor
final class UsageCoordinator: ObservableObject {
    let codex: CodexUsageService
    let openCodeGo: OpenCodeGoUsageService
    @Published private(set) var provider: UsageProvider

    private let settings: AppSettings
    private var forwarder: AnyCancellable?
    private var hasActivated = false

    init(settings: AppSettings, history: UsageHistoryModel) {
        self.settings = settings
        self.provider = settings.usageProvider
        self.codex = CodexUsageService(settings: settings, history: history, autostart: false)
        self.openCodeGo = OpenCodeGoUsageService(settings: settings, history: history, autostart: false)

        // Activate after StateObject construction completes on the main run loop.
        Task { @MainActor [weak self] in
            self?.activateCurrentSource()
        }
    }

    var activeSource: UsageSource {
        switch provider {
        case .codex: codex
        case .openCodeGo: openCodeGo
        }
    }

    func select(_ provider: UsageProvider) {
        guard provider != self.provider else { return }
        self.provider = provider
        settings.usageProvider = provider
        activateCurrentSource()
    }

    private func activateCurrentSource() {
        if hasActivated {
            switch provider {
            case .codex: openCodeGo.deactivate()
            case .openCodeGo: codex.deactivate()
            }
        }
        hasActivated = true
        if provider == .openCodeGo {
            openCodeGo.updateChannel(settings.openCodeGoChannel)
        }
        activeSource.activate()
        rebindForwarding()
    }

    /// SwiftUI must observe the coordinator, so relay the active source's change
    /// notifications through this object.
    private func rebindForwarding() {
        forwarder = activeSource.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Forwarded surface

    /// Token Activity reads Codex App Server usage buckets, which no other
    /// provider can supply.
    var supportsTokenActivity: Bool { provider == .codex }

    var windows: [UsageWindow] { activeSource.windows }
    var planType: String? { activeSource.planType }
    var isLoading: Bool { activeSource.isLoading }
    var isRefreshInFlight: Bool { activeSource.isRefreshInFlight }
    var isStale: Bool { activeSource.isStale }
    var errorMessage: String? { activeSource.errorMessage }
    var lastUpdated: Date? { activeSource.lastUpdated }
    var tokenUsage: TokenUsageSnapshot? { activeSource.tokenUsage }
    var isTokenUsageUnavailable: Bool { activeSource.isTokenUsageUnavailable }
    var tokenUsageErrorMessage: String? { activeSource.tokenUsageErrorMessage }
    var rateLimitResetCredits: CodexRateLimitResetCreditsSummary? { activeSource.rateLimitResetCredits }
    var historyAccountKey: String? { activeSource.historyAccountKey }
    var mostConstrainedRemainingPercent: Int? { activeSource.mostConstrainedRemainingPercent }
    var mostConstrainedWindow: UsageWindow? { activeSource.mostConstrainedWindow }
    var menuBarTitle: String { activeSource.menuBarTitle }
    var accountDescription: String { activeSource.accountDescription }
    var pushNotificationService: PushNotificationService { activeSource.pushNotificationService }

    /// Caption drawn under the menu bar percentage. The shipped caption is the
    /// Codex brand, so the default follows the active source; a caption the user
    /// typed in Developer Options always wins.
    var menuBarCaption: String {
        let configured = settings.developerAppearance.captionText
        guard configured == MenuBarAppearance.defaultCaptionText, provider != .codex else {
            return configured
        }
        return provider.localizedName
    }

    func refresh() { activeSource.refresh() }

    func refreshIfNeeded(maxAge: TimeInterval = 10) {
        activeSource.refreshIfNeeded(maxAge: maxAge)
    }

    func setPopoverVisible(_ visible: Bool) {
        activeSource.setPopoverVisible(visible)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        activeSource.setNotificationsEnabled(enabled)
    }
}
