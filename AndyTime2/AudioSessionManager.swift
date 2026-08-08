import AVFoundation
import Foundation
import LiveKit

/// Owns the app's shared `AVAudioSession`.
///
/// LiveKit configures the shared session itself (see `AudioSessionEngineObserver`
/// in client-sdk-swift) every time its audio engine starts or stops. Two of those
/// behaviors silence `AVPlayer` video playback:
///
/// 1. While the mic is published it installs `.playAndRecord` with mode
///    `.videoChat`. That mode puts the whole app on the voice-processing route,
///    where output follows the *call* volume and gets ducked — the video keeps
///    playing frames with no audible sound.
/// 2. When the engine stops (disconnect, unpublish) it calls
///    `setActive(false)` on the shared session, which cuts the audio out from
///    under whatever `AVPlayer` happens to be playing.
///
/// Since the camera page auto-connects and publishes the mic at launch, case 1
/// is the app's steady state — which is why videos lost their sound as soon as
/// LiveKit landed.
///
/// So LiveKit's automatic configuration is turned off and the session is managed
/// here instead: mode stays `.default` so playback uses the media volume and the
/// main speaker, and the session is never deactivated.
final class AudioSessionManager: NSObject {

    static let shared = AudioSessionManager()

    /// `true` while the local mic is being captured, which is the only time
    /// the session needs `.playAndRecord`. Guarded by `lock` — the LiveKit
    /// connect flow runs off the main thread.
    private var isMicrophoneActive = false
    private let lock = NSLock()

    private override init() {
        super.init()
    }

    /// Call once at launch, before connecting to a LiveKit room.
    func start() {
        // Take ownership of the session away from the SDK. Both flags matter:
        // the first stops it reconfiguring the category, the second stops it
        // deactivating the session when the engine winds down.
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        AudioManager.shared.audioSession.isAutomaticDeactivationEnabled = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )

        apply()
    }

    /// Mic capture needs `.playAndRecord`; everything else sounds better under
    /// plain `.playback`. `CameraViewController` calls this around publishing.
    ///
    /// Applies synchronously so the category is in place before the WebRTC
    /// engine starts capturing.
    func setMicrophoneActive(_ active: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard active != isMicrophoneActive else { return }
        isMicrophoneActive = active
        applyLocked()
    }

    // MARK: - Private

    private func apply() {
        lock.lock()
        defer { lock.unlock() }
        applyLocked()
    }

    /// Requires `lock` to be held.
    private func applyLocked() {
        let session = AVAudioSession.sharedInstance()
        do {
            if isMicrophoneActive {
                // Mode `.default` rather than `.videoChat`/`.voiceChat`: recording
                // still works, but playback keeps the media volume instead of the
                // call volume. `.defaultToSpeaker` keeps it off the earpiece.
                try session.setCategory(.playAndRecord,
                                        mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay])
            } else {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            // Never deactivated — a video may be playing at any point.
            try session.setActive(true)
        } catch {
            print("[Audio] session config failed (mic active: \(isMicrophoneActive)): \(error)")
            // Video sound matters more than the mic, so fall back to playback only.
            try? session.setCategory(.playback, mode: .default, options: [])
            try? session.setActive(true)
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw),
              type == .ended else { return }
        // Reactivate; AndyViewController's playback watchdog restarts the video.
        apply()
    }

    @objc private func handleMediaServicesReset() {
        // The session is reset to its defaults, so everything has to be reapplied.
        apply()
    }
}
