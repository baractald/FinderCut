import AppKit

/// Presents a compact native About window displaying app metadata and quick actions.
final class AboutWindowController: NSObject {
    private let updateChecker: UpdateChecker
    private let supportManager: SupportManager

    private var window: NSWindow?
    private var versionLabel: NSTextField?
    private var descriptionLabel: NSTextField?
    private var checkForUpdatesButton: NSButton?
    private var githubButton: NSButton?
    private var supportButton: NSButton?

    init(updateChecker: UpdateChecker, supportManager: SupportManager) {
        self.updateChecker = updateChecker
        self.supportManager = supportManager
        super.init()
    }

    func show() {
        let aboutWindow = ensureWindow()
        let wasVisible = aboutWindow.isVisible
        refreshLocalization()
        if !wasVisible {
            aboutWindow.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow.makeKeyAndOrderFront(nil)
    }

    func refreshLocalization() {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

        window?.title = L10n.string("menu.about")
        versionLabel?.stringValue = L10n.format("about.version", shortVersion)
        descriptionLabel?.stringValue = L10n.string("about.description")
        checkForUpdatesButton?.title = L10n.string("about.checkForUpdates")
        githubButton?.title = L10n.string("about.github")
        supportButton?.title = L10n.string("about.support")
    }

    private func ensureWindow() -> NSWindow {
        if let existing = window {
            return existing
        }

        let contentSize = NSSize(width: 320, height: 310)
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.translatesAutoresizingMaskIntoConstraints = false
        newWindow.contentView = container

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 76),
            iconView.heightAnchor.constraint(equalToConstant: 76)
        ])

        let titleLabel = NSTextField(labelWithString: "FinderCut")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        let verLabel = NSTextField(labelWithString: "")
        verLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        verLabel.textColor = .secondaryLabelColor
        verLabel.alignment = .center

        let descLabel = NSTextField(wrappingLabelWithString: "")
        descLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.preferredMaxLayoutWidth = 264

        let updatesButton = NSButton(title: "", target: self, action: #selector(handleCheckForUpdates))
        updatesButton.bezelStyle = .rounded

        let ghButton = NSButton(title: "", target: self, action: #selector(handleOpenGitHub))
        ghButton.bezelStyle = .rounded

        let supButton = NSButton(title: "", target: self, action: #selector(handleOpenSupport))
        supButton.bezelStyle = .rounded

        let linkRow = NSStackView(views: [ghButton, supButton])
        linkRow.orientation = .horizontal
        linkRow.alignment = .centerY
        linkRow.spacing = 8

        let platformLabel = NSTextField(labelWithString: "macOS 13.0+ · Apple Silicon")
        platformLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        platformLabel.textColor = .tertiaryLabelColor
        platformLabel.alignment = .center

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(verLabel)
        stack.addArrangedSubview(descLabel)
        stack.addArrangedSubview(updatesButton)
        stack.addArrangedSubview(linkRow)
        stack.addArrangedSubview(platformLabel)

        stack.setCustomSpacing(10, after: iconView)
        stack.setCustomSpacing(2, after: titleLabel)
        stack.setCustomSpacing(10, after: verLabel)
        stack.setCustomSpacing(16, after: descLabel)
        stack.setCustomSpacing(8, after: updatesButton)
        stack.setCustomSpacing(14, after: linkRow)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28)
        ])

        self.window = newWindow
        self.versionLabel = verLabel
        self.descriptionLabel = descLabel
        self.checkForUpdatesButton = updatesButton
        self.githubButton = ghButton
        self.supportButton = supButton

        return newWindow
    }

    @objc private func handleCheckForUpdates() {
        updateChecker.checkForUpdates(interactive: true)
    }

    @objc private func handleOpenGitHub() {
        NSWorkspace.shared.open(UpdateChecker.repositoryURL)
    }

    @objc private func handleOpenSupport() {
        supportManager.openSupportPage()
    }
}
