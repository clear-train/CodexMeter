import Combine
import Foundation

/// Presents the quota source the popover is showing.
///
/// Every provider keeps polling in the background so a tab switch is instant and
/// history stays continuous for both. Only the viewed provider owns the visible
/// history partition; the others keep recording under their own account key.
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
        self.codex = CodexUsageService(settings: settings, history: history)
        self.openCodeGo = OpenCodeGoUsageService(settings: settings, history: history)

        // Activate after StateObject construction completes on the main run loop.
        Task { @MainActor [weak self] in
            self?.activateSources()
        }
    }

    /// Providers the popover can show, in tab order.
    var providers: [UsageProvider] { UsageProvider.allCases }

    func source(for provider: UsageProvider) -> any UsageSource {
        switch provider {
        case .codex: codex
        case .openCodeGo: openCodeGo
        }
    }

    var activeSource: any UsageSource { source(for: provider) }

    func remainingPercent(for provider: UsageProvider) -> Int? {
        source(for: provider).mostConstrainedRemainingPercent
    }

    func attentionLevel(for provider: UsageProvider) -> QuotaAttentionLevel? {
        source(for: provider).mostConstrainedWindow?.attentionLevel(at: Date())
    }

    func select(_ provider: UsageProvider) {
        guard provider != self.provider else { return }
        self.provider = provider
        settings.usageProvider = provider
        applyHistoryViewOwnership()
        // The other provider may not have polled since the popover opened.
        activeSource.refreshIfNeeded(maxAge: 10)
    }

    private func activateSources() {
        guard !hasActivated else { return }
        hasActivated = true
        openCodeGo.updateChannel(settings.openCodeGoChannel)
        // Both services autostart; the coordinator only decides who owns the
        // visible history partition.
        applyHistoryViewOwnership()
        bindForwarding()
    }

    /// Exactly one source may own the visible history partition; deactivating
    /// the outgoing one first keeps the store from briefly mixing partitions.
    private func applyHistoryViewOwnership() {
        for candidate in providers {
            source(for: candidate).setHistoryViewActive(candidate == provider)
        }
    }

    /// SwiftUI observes the coordinator only, so relay changes from *both*
    /// providers: the inactive tab still shows a live percentage.
    private func bindForwarding() {
        forwarder = Publishers.Merge(
            codex.objectWillChange,
            openCodeGo.objectWillChange
        ).sink { [weak self] _ in
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
