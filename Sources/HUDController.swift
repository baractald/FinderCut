import AppKit

final class HUDController {
    private static let enabledKey = "cutHUDEnabled"
    private static let iconToShortcutSpacing: CGFloat = 16
    private let cornerRadius: CGFloat = 20
    private let glassCornerRadius: CGFloat = 28

    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var iconView: NSImageView?
    private var subtitleLabel: NSTextField?
    private var hideWorkItem: DispatchWorkItem?

    var isEnabled: Bool {
        get {
            if defaults.object(forKey: Self.enabledKey) == nil {
                return true
            }
            return defaults.bool(forKey: Self.enabledKey)
        }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue {
                hideWorkItem?.cancel()
                panel?.orderOut(nil)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func showCutHUD(itemCount: Int) {
        guard isEnabled else { return }
        hideWorkItem?.cancel()

        let hudPanel = ensurePanel()
        iconView?.image?.accessibilityDescription = L10n.string("hud.icon.accessibility")
        subtitleLabel?.stringValue = itemCount > 1
            ? L10n.format("hud.cut.multiple", itemCount)
            : L10n.string("hud.cut.single")

        positionInCenterOfActiveScreen(hudPanel)

        hudPanel.alphaValue = 0
        hudPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hudPanel.animator().alphaValue = 1.0
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
    }

    private func fadeOut() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            if self?.panel?.alphaValue == 0.0 {
                self?.panel?.orderOut(nil)
            }
        })
    }

    private func ensurePanel() -> NSPanel {
        if let existing = panel {
            return existing
        }

        let size = NSSize(width: 164, height: 164)
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.ignoresMouseEvents = true
        newPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 44, weight: .light)
        let symbol = NSImage(
            systemSymbolName: "scissors",
            accessibilityDescription: L10n.string("hud.icon.accessibility")
        )?
            .withSymbolConfiguration(symbolConfig)
        iconView.image = symbol
        iconView.contentTintColor = .labelColor

        let shortcutLabel = NSTextField(labelWithString: "⌘X")
        shortcutLabel.font = NSFont.systemFont(ofSize: 24, weight: .medium)
        shortcutLabel.textColor = .labelColor
        shortcutLabel.alignment = .center

        let subLabel = NSTextField(labelWithString: L10n.string("hud.cut.single"))
        subLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subLabel.textColor = .secondaryLabelColor
        subLabel.alignment = .center
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.maximumNumberOfLines = 1

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(shortcutLabel)
        stack.addArrangedSubview(subLabel)
        stack.setCustomSpacing(Self.iconToShortcutSpacing, after: iconView)

        let bounds = NSRect(origin: .zero, size: size)
        if #available(macOS 26.0, *) {
            subLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)

            let contentContainer = NSView(frame: bounds)
            contentContainer.autoresizingMask = [.width, .height]
            contentContainer.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainer.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -12)
            ])

            let glassView = NSGlassEffectView(frame: bounds)
            glassView.autoresizingMask = [.width, .height]
            glassView.style = .clear
            glassView.cornerRadius = glassCornerRadius
            glassView.contentView = contentContainer
            newPanel.contentView = glassView
        } else {
            let visualEffect = NSVisualEffectView(frame: bounds)
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.maskImage = Self.makeCornerMaskImage(cornerRadius: cornerRadius)

            let outlineView = HUDOutlineView(frame: visualEffect.bounds, cornerRadius: cornerRadius)
            outlineView.autoresizingMask = [.width, .height]
            visualEffect.addSubview(outlineView)

            visualEffect.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: visualEffect.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: visualEffect.trailingAnchor, constant: -12)
            ])

            newPanel.contentView = visualEffect
        }

        newPanel.invalidateShadow()
        self.panel = newPanel
        self.iconView = iconView
        self.subtitleLabel = subLabel
        return newPanel
    }

    static func makeCornerMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 2
        let imageSize = NSSize(width: edge, height: edge)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }

    private func positionInCenterOfActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - window.frame.width / 2
        let y = frame.midY - window.frame.height / 2
        window.setFrameOrigin(NSPoint(x: round(x), y: round(y)))
    }
}

private final class HUDOutlineView: NSView {
    private let cornerRadius: CGFloat

    init(frame frameRect: NSRect, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 0.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let radius = max(0, cornerRadius - inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.stroke()
    }
}
