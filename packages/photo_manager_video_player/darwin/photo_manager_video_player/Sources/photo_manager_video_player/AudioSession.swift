import AVFoundation

/// The package's only audio-session decision: video sound must not be silenced
/// by the ring/silent switch. Anything beyond that belongs to the app.
enum AudioSession {
    private static var upgraded = false

    /// Raises the default `.soloAmbient` category to `.playback` on the first
    /// player, keeping the app's options. Any category the app set, including
    /// `.ambient` (which mixes with other audio), is left alone.
    static func upgradeForPlaybackOnce() {
        if upgraded { return }
        upgraded = true
        let session = AVAudioSession.sharedInstance()
        guard session.category == .soloAmbient else { return }
        try? session.setCategory(.playback, mode: session.mode, options: session.categoryOptions)
    }
}
