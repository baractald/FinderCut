import AppKit

/// Checks GitHub Releases for newer FinderCut versions using URLSession with zero dependencies.
final class UpdateChecker {
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/baractald/FinderCut/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/baractald/FinderCut/releases")!
    static let repositoryURL = URL(string: "https://github.com/baractald/FinderCut")!

    private static let skippedVersionKey = "skippedUpdateVersion"

    struct ReleaseInfo: Equatable {
        let tagName: String
        let version: String
        let notes: String
        let htmlURL: URL
        let dmgDownloadURL: URL?
    }

    private struct GitHubReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
        }
    }

    private struct SemanticVersion {
        let core: [Int]
        let prerelease: String?
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let currentVersionProvider: () -> String
    private var isChecking = false
    private var startupWorkItem: DispatchWorkItem?

    var onBeforePresentingUpdateAlert: (() -> Void)?

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        currentVersionProvider: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        }
    ) {
        self.defaults = defaults
        self.session = session
        self.currentVersionProvider = currentVersionProvider
    }

    var skippedVersion: String? {
        defaults.string(forKey: Self.skippedVersionKey)
    }

    func skipVersion(_ version: String) {
        let normalized = Self.normalizeVersion(version)
        guard !normalized.isEmpty else { return }
        defaults.set(normalized, forKey: Self.skippedVersionKey)
    }

    static func normalizeVersion(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseSemanticVersion(_ raw: String) -> SemanticVersion? {
        var cleaned = normalizeVersion(raw)
        if let plusIndex = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIndex])
        }
        guard !cleaned.isEmpty else { return nil }

        let coreString: String
        let prerelease: String?
        if let dashIndex = cleaned.firstIndex(of: "-") {
            coreString = String(cleaned[..<dashIndex])
            let suffix = String(cleaned[cleaned.index(after: dashIndex)...])
            prerelease = suffix.isEmpty ? nil : suffix
        } else {
            coreString = cleaned
            prerelease = nil
        }

        let parts = coreString.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var numbers: [Int] = []
        numbers.reserveCapacity(parts.count)
        for part in parts {
            guard !part.isEmpty, let value = Int(part), value >= 0 else {
                return nil
            }
            numbers.append(value)
        }
        return SemanticVersion(core: numbers, prerelease: prerelease)
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        guard let lhs = parseSemanticVersion(candidate),
              let rhs = parseSemanticVersion(current) else {
            return false
        }

        let maxCount = max(lhs.core.count, rhs.core.count)
        for index in 0..<maxCount {
            let l = index < lhs.core.count ? lhs.core[index] : 0
            let r = index < rhs.core.count ? rhs.core[index] : 0
            if l != r {
                return l > r
            }
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, .some):
            return true
        case (.some, nil), (nil, nil):
            return false
        case (.some(let lPre), .some(let rPre)):
            return lPre.compare(rPre, options: [.numeric, .caseInsensitive]) == .orderedDescending
        }
    }

    static func parseLatestRelease(from data: Data) throws -> ReleaseInfo {
        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        let dmgURL = payload.assets?
            .first(where: { $0.name.lowercased().hasSuffix(".dmg") })?
            .browserDownloadURL
        return ReleaseInfo(
            tagName: payload.tagName,
            version: normalizeVersion(payload.tagName),
            notes: payload.body ?? "",
            htmlURL: payload.htmlURL,
            dmgDownloadURL: dmgURL
        )
    }

    static func summarizeReleaseNotes(_ body: String, maxLength: Int = 340) -> String {
        let rawLines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var cleanedLines: [String] = []

        for rawLine in rawLines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            if line.hasPrefix("**Full Changelog**") || line.hasPrefix("Full Changelog:") {
                continue
            }
            while line.hasPrefix("#") {
                line.removeFirst()
            }
            line = line.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.replacingOccurrences(of: "`", with: "")
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
            }
            if !line.isEmpty {
                cleanedLines.append(line)
            }
        }

        let joined = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.count > maxLength else {
            return joined
        }
        let cutoff = joined.index(joined.startIndex, offsetBy: maxLength)
        return String(joined[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    func shouldPromptForRelease(_ release: ReleaseInfo, currentVersion: String, interactive: Bool) -> Bool {
        guard Self.isVersion(release.version, newerThan: currentVersion) else {
            return false
        }
        if !interactive, let skipped = skippedVersion, skipped == release.version {
            return false
        }
        return true
    }

    func scheduleStartupCheck(delay: TimeInterval = 3.0) {
        cancelScheduledStartupCheck()
        let workItem = DispatchWorkItem { [weak self] in
            self?.startupWorkItem = nil
            self?.checkForUpdates(interactive: false)
        }
        startupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelScheduledStartupCheck() {
        startupWorkItem?.cancel()
        startupWorkItem = nil
    }

    func checkForUpdates(interactive: Bool) {
        guard !isChecking else { return }
        isChecking = true

        let current = Self.normalizeVersion(currentVersionProvider())
        var request = URLRequest(
            url: Self.latestReleaseAPIURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FinderCut/\(current)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false

                if let error = error {
                    if interactive {
                        self.presentCheckFailedAlert(detail: error.localizedDescription)
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    if interactive {
                        self.presentCheckFailedAlert(detail: "Invalid server response")
                    }
                    return
                }

                guard httpResponse.statusCode == 200, let data = data else {
                    if interactive {
                        self.presentCheckFailedAlert(detail: "HTTP \(httpResponse.statusCode)")
                    }
                    return
                }

                do {
                    let release = try Self.parseLatestRelease(from: data)
                    if self.shouldPromptForRelease(release, currentVersion: current, interactive: interactive) {
                        self.onBeforePresentingUpdateAlert?()
                        self.presentUpdateAvailableAlert(release: release, currentVersion: current)
                    } else if interactive {
                        self.presentUpToDateAlert(currentVersion: current)
                    }
                } catch {
                    if interactive {
                        self.presentCheckFailedAlert(detail: error.localizedDescription)
                    }
                }
            }
        }
        task.resume()
    }

    private func presentUpdateAvailableAlert(release: ReleaseInfo, currentVersion: String) {
        let summary = Self.summarizeReleaseNotes(release.notes)
        let summaryBlock = summary.isEmpty ? "" : "\n\n\(summary)"
        let messageBody = L10n.format("alert.update.available.message", currentVersion, release.version, summaryBlock)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = L10n.format("alert.update.available.title", release.version)
        alert.informativeText = messageBody
        alert.addButton(withTitle: L10n.string("alert.update.download"))
        alert.addButton(withTitle: L10n.string("alert.update.later"))
        alert.addButton(withTitle: L10n.string("alert.update.skipVersion"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
        case .alertThirdButtonReturn:
            skipVersion(release.version)
        default:
            break
        }
    }

    private func presentUpToDateAlert(currentVersion: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = L10n.string("alert.update.upToDate.title")
        alert.informativeText = L10n.format("alert.update.upToDate.message", currentVersion)
        alert.addButton(withTitle: L10n.string("alert.ok"))
        alert.runModal()
    }

    private func presentCheckFailedAlert(detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.messageText = L10n.string("alert.update.failed.title")
        alert.informativeText = L10n.format("alert.update.failed.message", detail)
        alert.addButton(withTitle: L10n.string("alert.update.openReleases"))
        alert.addButton(withTitle: L10n.string("alert.ok"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }
}
