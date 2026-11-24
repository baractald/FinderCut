import AppKit

/// Tracks local usage milestones to trigger sparse support prompts and opens the Stripe support page.
final class SupportManager {
    static let supportURL = URL(string: "https://buy.stripe.com/7sY7sL8EKemcegG4ERbMQ00")!
    static let minimumDaysBeforeFirstPrompt: Double = 14
    static let minimumMovesBeforeFirstPrompt: Int = 30
    static let minimumDaysBetweenPrompts: Double = 45
    static let minimumMovesBetweenPrompts: Int = 50
    static let maxPromptCount: Int = 3

    private static let firstLaunchTimestampKey = "supportFirstLaunchTimestamp"
    private static let completedMoveCountKey = "supportCompletedMoveCount"
    private static let promptCountKey = "supportPromptCount"
    private static let lastPromptTimestampKey = "supportLastPromptTimestamp"
    private static let lastPromptMoveCountKey = "supportLastPromptMoveCount"
    private static let dismissedPermanentlyKey = "supportPromptDismissedPermanently"
    private static let secondsPerDay: TimeInterval = 86_400

    private let defaults: UserDefaults
    private var scheduledPromptWorkItem: DispatchWorkItem?
    private var isPresentingPrompt = false

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        if defaults.object(forKey: Self.firstLaunchTimestampKey) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: Self.firstLaunchTimestampKey)
        }
    }

    var completedMoveCount: Int {
        defaults.integer(forKey: Self.completedMoveCountKey)
    }

    var promptCount: Int {
        defaults.integer(forKey: Self.promptCountKey)
    }

    var isDismissedPermanently: Bool {
        defaults.bool(forKey: Self.dismissedPermanentlyKey)
    }

    /// Records a completed Finder cut-and-move action and optionally schedules an eligible prompt.
    func recordCompletedMove(now: Date = Date(), canPromptNow: (() -> Bool)? = nil) {
        defaults.set(completedMoveCount + 1, forKey: Self.completedMoveCountKey)
        if let canPromptNow {
            schedulePromptIfEligible(delay: 6.0, now: now, canPromptNow: canPromptNow)
        }
    }

    /// Returns whether enough time and usage have accumulated without exceeding prompt limits.
    func isEligibleForPrompt(now: Date = Date()) -> Bool {
        guard !isDismissedPermanently else { return false }
        let shown = promptCount
        guard shown < Self.maxPromptCount else { return false }

        let nowTimestamp = now.timeIntervalSince1970
        let moves = completedMoveCount

        if shown == 0 {
            let firstLaunch = defaults.double(forKey: Self.firstLaunchTimestampKey)
            let elapsedDays = (nowTimestamp - firstLaunch) / Self.secondsPerDay
            return elapsedDays >= Self.minimumDaysBeforeFirstPrompt
                && moves >= Self.minimumMovesBeforeFirstPrompt
        }

        let lastPrompt = defaults.double(forKey: Self.lastPromptTimestampKey)
        let lastMoveCount = defaults.integer(forKey: Self.lastPromptMoveCountKey)
        let elapsedDays = (nowTimestamp - lastPrompt) / Self.secondsPerDay
        return elapsedDays >= Self.minimumDaysBetweenPrompts
            && (moves - lastMoveCount) >= Self.minimumMovesBetweenPrompts
    }

    /// Marks that a support prompt was displayed so cooldown and total caps apply immediately.
    func recordPromptShown(now: Date = Date()) {
        defaults.set(promptCount + 1, forKey: Self.promptCountKey)
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastPromptTimestampKey)
        defaults.set(completedMoveCount, forKey: Self.lastPromptMoveCountKey)
    }

    /// Permanently disables future support prompts and cancels any pending scheduled prompt.
    func markDismissedPermanently() {
        defaults.set(true, forKey: Self.dismissedPermanentlyKey)
        cancelScheduledPrompt()
    }

    /// Opens the configured Stripe support page and suppresses future automatic prompts.
    func openSupportPage() {
        markDismissedPermanently()
        NSWorkspace.shared.open(Self.supportURL)
    }

    func cancelScheduledPrompt() {
        scheduledPromptWorkItem?.cancel()
        scheduledPromptWorkItem = nil
    }

    func schedulePromptIfEligible(
        delay: TimeInterval,
        now: Date = Date(),
        canPromptNow: @escaping () -> Bool
    ) {
        cancelScheduledPrompt()
        guard !isPresentingPrompt && isEligibleForPrompt(now: now) else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.scheduledPromptWorkItem = nil
            guard !self.isPresentingPrompt,
                  canPromptNow(),
                  self.isEligibleForPrompt(now: Date()) else {
                return
            }
            self.presentSupportPrompt()
        }
        scheduledPromptWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func presentSupportPrompt() {
        guard !isPresentingPrompt && isEligibleForPrompt(now: Date()) else { return }
        isPresentingPrompt = true
        defer { isPresentingPrompt = false }

        // Record before showing so re-entrant events cannot schedule a duplicate dialog.
        recordPromptShown(now: Date())

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = L10n.string("alert.support.title")
        alert.informativeText = L10n.format("alert.support.message", completedMoveCount)
        alert.addButton(withTitle: L10n.string("alert.support.confirm"))
        alert.addButton(withTitle: L10n.string("alert.support.later"))
        alert.addButton(withTitle: L10n.string("alert.support.never"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSupportPage()
        case .alertThirdButtonReturn:
            markDismissedPermanently()
        default:
            break
        }
    }
}
