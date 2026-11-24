import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showMenuBarIconNotification = Notification.Name("com.local.FinderCut.showMenuBarIcon")

    private var menuBarController: MenuBarController!
    private var keyInterceptor: KeyInterceptor!
    private var hudController: HUDController!
    private var soundFeedbackManager: SoundFeedbackManager!
    private var permissionTimer: Timer?
    private var healthTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var reopenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let existingInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
            if !existingInstances.isEmpty {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.showMenuBarIconNotification,
                    object: bundleID,
                    userInfo: nil,
                    deliverImmediately: true
                )
                NSApp.terminate(nil)
                return
            }
        }

        NSApp.setActivationPolicy(.accessory)

        hudController = HUDController()
        soundFeedbackManager = SoundFeedbackManager()
        keyInterceptor = KeyInterceptor()
        menuBarController = MenuBarController(
            keyInterceptor: keyInterceptor,
            loginItemManager: LoginItemManager(),
            soundFeedbackManager: soundFeedbackManager,
            hudController: hudController
        )

        if let bundleID = Bundle.main.bundleIdentifier {
            reopenObserver = DistributedNotificationCenter.default().addObserver(
                forName: Self.showMenuBarIconNotification,
                object: bundleID,
                queue: .main
            ) { [weak self] _ in
                self?.menuBarController?.showMenuBarIcon()
            }
        }

        keyInterceptor.onCutStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.menuBarController.updateCutState(state)
                if case .pending(let count) = state {
                    self?.hudController.showCutHUD(itemCount: count)
                    self?.soundFeedbackManager.playCutSuccessIfEnabled()
                }
            }
        }

        keyInterceptor.onTapStateChanged = { [weak self] active in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.menuBarController.updatePermissionState(hasPermission: active)
                if !active {
                    self.stopHealthMonitor()
                    self.startInterceptorOrPollPermission(promptUser: false)
                }
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.keyInterceptor.verifyHealth() {
                self.startInterceptorOrPollPermission(promptUser: false)
            }
        }

        startInterceptorOrPollPermission(promptUser: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController?.showMenuBarIcon()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        stopHealthMonitor()
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let reopenObserver = reopenObserver {
            DistributedNotificationCenter.default().removeObserver(reopenObserver)
            self.reopenObserver = nil
        }
        keyInterceptor?.stop()
    }

    private func startInterceptorOrPollPermission(promptUser: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptUser] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted {
            let started = keyInterceptor.start()
            menuBarController.updatePermissionState(hasPermission: started)
            if started {
                permissionTimer?.invalidate()
                permissionTimer = nil
                startHealthMonitor()
                return
            }
        } else {
            menuBarController.updatePermissionState(hasPermission: false)
        }

        // Poll silently until the user grants Accessibility permission in System Settings.
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if AXIsProcessTrusted() {
                if self.keyInterceptor.start() {
                    self.menuBarController.updatePermissionState(hasPermission: true)
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.startHealthMonitor()
                }
            }
        }
    }

    private func startHealthMonitor() {
        guard healthTimer == nil else { return }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            _ = self?.keyInterceptor.verifyHealth()
        }
    }

    private func stopHealthMonitor() {
        healthTimer?.invalidate()
        healthTimer = nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
