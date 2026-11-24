import AppKit

final class MenuBarController: NSObject {
    private static let iconHiddenKey = "menuBarIconHidden"
    private static let hideIconAlertSuppressedKey = "hideMenuBarIconAlertSuppressed"

    private let statusItem: NSStatusItem
    private let keyInterceptor: KeyInterceptor
    private let loginItemManager: LoginItemManager
    private let soundFeedbackManager: SoundFeedbackManager
    private let hudController: HUDController
    private let supportManager: SupportManager
    private let updateChecker: UpdateChecker
    private let aboutWindowController: AboutWindowController
    private let defaults: UserDefaults

    private let statusMenuItem = NSMenuItem(title: L10n.string("menu.status.initializing"), action: nil, keyEquivalent: "")
    private let enableMenuItem = NSMenuItem(title: L10n.string("menu.enable"), action: #selector(toggleEnabled), keyEquivalent: "")
    private let cancelCutMenuItem = NSMenuItem(title: L10n.string("menu.cancelCut"), action: #selector(cancelPendingCut), keyEquivalent: "")
    private let hudFeedbackMenuItem = NSMenuItem(title: L10n.string("menu.hudFeedback"), action: #selector(toggleHUDFeedback), keyEquivalent: "")
    private let soundFeedbackMenuItem = NSMenuItem(title: L10n.string("menu.soundFeedback"), action: #selector(toggleSoundFeedback), keyEquivalent: "")
    private let languageMenuItem = NSMenuItem(title: L10n.string("menu.language"), action: nil, keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: L10n.string("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let hideMenuBarIconMenuItem = NSMenuItem(title: L10n.string("menu.hideMenuBarIcon"), action: #selector(hideMenuBarIcon), keyEquivalent: "")
    private let accessibilityMenuItem = NSMenuItem(title: L10n.string("menu.openAccessibility"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let checkForUpdatesMenuItem = NSMenuItem(title: L10n.string("menu.checkForUpdates"), action: #selector(checkForUpdates), keyEquivalent: "")
    private let aboutMenuItem = NSMenuItem(title: L10n.string("menu.about"), action: #selector(showAboutWindow), keyEquivalent: "")
    private let supportMenuItem = NSMenuItem(title: L10n.string("menu.support"), action: #selector(openSupportPage), keyEquivalent: "")
    private let quitMenuItem = NSMenuItem(title: L10n.string("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")

    private var languageOptionItems: [(AppLanguage, NSMenuItem)] = []
    private var hasPermission = false
    private var currentCutState: CutState = .idle

    static func isIconHidden(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: iconHiddenKey)
    }

    static func setIconHidden(_ hidden: Bool, in defaults: UserDefaults) {
        defaults.set(hidden, forKey: iconHiddenKey)
    }

    init(
        keyInterceptor: KeyInterceptor,
        loginItemManager: LoginItemManager,
        soundFeedbackManager: SoundFeedbackManager,
        hudController: HUDController,
        supportManager: SupportManager,
        updateChecker: UpdateChecker,
        aboutWindowController: AboutWindowController,
        defaults: UserDefaults = .standard
    ) {
        self.keyInterceptor = keyInterceptor
        self.loginItemManager = loginItemManager
        self.soundFeedbackManager = soundFeedbackManager
        self.hudController = hudController
        self.supportManager = supportManager
        self.updateChecker = updateChecker
        self.aboutWindowController = aboutWindowController
        self.defaults = defaults
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setupMenu()
        refreshUI()
        statusItem.isVisible = !Self.isIconHidden(in: defaults)
    }

    func showMenuBarIcon(openMenuIfRestored: Bool = true) {
        let wasHidden = Self.isIconHidden(in: defaults) || !statusItem.isVisible
        Self.setIconHidden(false, in: defaults)
        statusItem.isVisible = true
        refreshUI()

        if wasHidden && openMenuIfRestored {
            DispatchQueue.main.async { [weak self] in
                guard let button = self?.statusItem.button, button.window != nil else { return }
                button.performClick(nil)
            }
        }
    }

    func updatePermissionState(hasPermission: Bool) {
        self.hasPermission = hasPermission
        refreshUI()
    }

    func updateCutState(_ state: CutState) {
        self.currentCutState = state
        refreshUI()
    }

    private func setupMenu() {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        enableMenuItem.target = self
        menu.addItem(enableMenuItem)

        cancelCutMenuItem.target = self
        menu.addItem(cancelCutMenuItem)
        menu.addItem(.separator())

        hudFeedbackMenuItem.target = self
        menu.addItem(hudFeedbackMenuItem)

        soundFeedbackMenuItem.target = self
        menu.addItem(soundFeedbackMenuItem)

        let languageSubmenu = NSMenu()
        let systemLanguageItem = NSMenuItem(
            title: L10n.string("menu.language.system"),
            action: #selector(selectLanguage(_:)),
            keyEquivalent: ""
        )
        systemLanguageItem.target = self
        systemLanguageItem.representedObject = AppLanguage.system.rawValue
        languageSubmenu.addItem(systemLanguageItem)
        languageOptionItems.append((.system, systemLanguageItem))
        languageSubmenu.addItem(.separator())

        for lang in AppLanguage.allCases where lang != .system {
            let item = NSMenuItem(
                title: lang.nativeDisplayName ?? lang.rawValue,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lang.rawValue
            languageSubmenu.addItem(item)
            languageOptionItems.append((lang, item))
        }
        languageMenuItem.submenu = languageSubmenu
        menu.addItem(languageMenuItem)

        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        hideMenuBarIconMenuItem.target = self
        menu.addItem(hideMenuBarIconMenuItem)

        accessibilityMenuItem.target = self
        menu.addItem(.separator())
        menu.addItem(accessibilityMenuItem)

        checkForUpdatesMenuItem.target = self
        menu.addItem(checkForUpdatesMenuItem)

        aboutMenuItem.target = self
        menu.addItem(aboutMenuItem)

        supportMenuItem.target = self
        menu.addItem(supportMenuItem)

        menu.addItem(.separator())
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
    }

    private func refreshUI() {
        enableMenuItem.title = L10n.string("menu.enable")
        cancelCutMenuItem.title = L10n.string("menu.cancelCut")
        hudFeedbackMenuItem.title = L10n.string("menu.hudFeedback")
        soundFeedbackMenuItem.title = L10n.string("menu.soundFeedback")
        languageMenuItem.title = L10n.string("menu.language")
        loginMenuItem.title = L10n.string("menu.launchAtLogin")
        hideMenuBarIconMenuItem.title = L10n.string("menu.hideMenuBarIcon")
        accessibilityMenuItem.title = L10n.string("menu.openAccessibility")
        checkForUpdatesMenuItem.title = L10n.string("menu.checkForUpdates")
        aboutMenuItem.title = L10n.string("menu.about")
        supportMenuItem.title = L10n.string("menu.support")
        quitMenuItem.title = L10n.string("menu.quit")

        let activeLanguage = L10n.currentLanguage
        for (lang, item) in languageOptionItems {
            if lang == .system {
                item.title = L10n.string("menu.language.system")
            }
            item.state = (lang == activeLanguage) ? .on : .off
        }

        enableMenuItem.state = keyInterceptor.isEnabled ? .on : .off
        hudFeedbackMenuItem.state = hudController.isEnabled ? .on : .off
        soundFeedbackMenuItem.state = soundFeedbackManager.isEnabled ? .on : .off
        loginMenuItem.state = loginItemManager.isEnabled ? .on : .off
        accessibilityMenuItem.isHidden = hasPermission

        let isPending: Bool
        if case .pending = currentCutState {
            isPending = true
        } else {
            isPending = false
        }
        cancelCutMenuItem.isEnabled = isPending

        if !hasPermission {
            statusMenuItem.title = L10n.string("menu.status.waitingAccessibility")
        } else if !keyInterceptor.isEnabled {
            statusMenuItem.title = L10n.string("menu.status.paused")
        } else if case .pending(let count) = currentCutState {
            statusMenuItem.title = count == 1
                ? L10n.string("menu.status.pending.single")
                : L10n.format("menu.status.pending.multiple", count)
        } else {
            statusMenuItem.title = L10n.string("menu.status.running")
        }

        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "scissors", accessibilityDescription: "FinderCut")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.appearsDisabled = (!hasPermission || !keyInterceptor.isEnabled)

            if isPending && hasPermission && keyInterceptor.isEnabled {
                button.title = " ⌘X"
            } else {
                button.title = ""
            }
        }
    }

    @objc private func toggleEnabled() {
        keyInterceptor.isEnabled.toggle()
        refreshUI()
    }

    @objc private func cancelPendingCut() {
        keyInterceptor.clearCutState()
        refreshUI()
    }

    @objc private func toggleHUDFeedback() {
        hudController.isEnabled.toggle()
        refreshUI()
    }

    @objc private func toggleSoundFeedback() {
        let next = !soundFeedbackManager.isEnabled
        soundFeedbackManager.isEnabled = next
        if next {
            soundFeedbackManager.playPreview()
        }
        refreshUI()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let selected = AppLanguage(rawValue: raw) else {
            return
        }
        L10n.currentLanguage = selected
        refreshUI()
        aboutWindowController.refreshLocalization()
    }

    @objc private func toggleLaunchAtLogin() {
        let target = !loginItemManager.isEnabled
        let result = loginItemManager.setEnabled(target)
        refreshUI()

        switch result {
        case .success:
            break
        case .requiresApproval:
            presentLoginItemAlert(
                title: L10n.string("alert.loginItem.approval.title"),
                message: L10n.string("alert.loginItem.approval.message")
            )
        case .failed(let detail):
            presentLoginItemAlert(
                title: L10n.string("alert.loginItem.failed.title"),
                message: L10n.format("alert.loginItem.failed.message", detail)
            )
        }
    }

    private func presentLoginItemAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.string("alert.loginItem.openSettings"))
        alert.addButton(withTitle: L10n.string("alert.ok"))
        if alert.runModal() == .alertFirstButtonReturn {
            loginItemManager.openLoginItemsSettings()
        }
    }

    @objc private func hideMenuBarIcon() {
        if !defaults.bool(forKey: Self.hideIconAlertSuppressedKey) {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n.string("alert.hideMenuBarIcon.title")
            alert.informativeText = L10n.string("alert.hideMenuBarIcon.message")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = L10n.string("alert.dontShowAgain")
            alert.addButton(withTitle: L10n.string("alert.hideMenuBarIcon.confirm"))
            alert.addButton(withTitle: L10n.string("alert.cancel"))

            if alert.runModal() != .alertFirstButtonReturn {
                return
            }
            if alert.suppressionButton?.state == .on {
                defaults.set(true, forKey: Self.hideIconAlertSuppressedKey)
            }
        }

        Self.setIconHidden(true, in: defaults)
        statusItem.isVisible = false
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkForUpdates() {
        updateChecker.checkForUpdates(interactive: true)
    }

    @objc private func showAboutWindow() {
        aboutWindowController.show()
    }

    @objc private func openSupportPage() {
        supportManager.openSupportPage()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
