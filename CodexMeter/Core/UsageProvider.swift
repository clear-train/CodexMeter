import Foundation

/// A quota source the app can read and visualize.
///
/// Every provider exposes the same window shape so the rings, pace hints and
/// history charts stay provider agnostic. Anything Codex specific (banked
/// resets, token activity) is reported as `nil` by the other providers.
nonisolated enum UsageProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case openCodeGo

    var id: String { rawValue }

    /// Stable namespace that keeps local history separate per provider.
    var historyNamespace: String {
        switch self {
        case .codex: "codex"
        case .openCodeGo: "opencode-go"
        }
    }

    /// Prefixed account key handed to the history store.
    func historyAccountKey(for identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else { return historyNamespace }
        return "\(historyNamespace):\(identifier)"
    }
}

/// The window kinds a provider can report.
nonisolated enum UsageWindowKind: String, CaseIterable, Sendable {
    case rolling
    case weekly
    case monthly

    /// Nominal window length, used for the "remaining time" ring and pace hints.
    var nominalDurationMins: Int? {
        switch self {
        case .rolling: 300
        case .weekly: 7 * 24 * 60
        case .monthly: nil
        }
    }
}
