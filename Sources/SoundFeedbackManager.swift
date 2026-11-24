import AppKit

final class SoundFeedbackManager {
    private static let enabledKey = "cutSoundFeedbackEnabled"
    private static let preferredSoundNames = ["Tink", "Pop"]
    private static let defaultVolume: Float = 0.45

    private let defaults: UserDefaults
    private var cachedSound: NSSound?

    var isEnabled: Bool {
        get {
            if defaults.object(forKey: Self.enabledKey) == nil {
                return true
            }
            return defaults.bool(forKey: Self.enabledKey)
        }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cachedSound = Self.loadSound()
    }

    func playCutSuccessIfEnabled() {
        guard isEnabled else { return }
        playSound()
    }

    func playPreview() {
        playSound()
    }

    private func playSound() {
        guard let sound = cachedSound ?? Self.loadSound() else { return }
        cachedSound = sound
        sound.volume = Self.defaultVolume
        sound.stop()
        sound.currentTime = 0
        sound.play()
    }

    private static func loadSound() -> NSSound? {
        for name in preferredSoundNames {
            if let sound = NSSound(named: NSSound.Name(name)) {
                return sound
            }
        }
        return NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)
    }
}
