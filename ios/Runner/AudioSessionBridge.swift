import AVFoundation
import Flutter

/// Manages the app-level AVAudioSession category via a MethodChannel.
///
/// Methods:
///   - `setPlayAndRecord`: switches to `.playAndRecord` with `.defaultToSpeaker`
///     to keep the app alive in background and allow simultaneous input/output.
///   - `setAmbient`: reverts to `.ambient` (respects silent switch, mixes with
///     other audio, standard foreground-only behavior per ADR-AUDIO-007).
class AudioSessionBridge {
    static let shared = AudioSessionBridge()

    private let channelName = "com.voiceagent/audio_session"
    private var methodChannel: FlutterMethodChannel?

    private init() {}

    /// Call from AppDelegate after the Flutter engine is available.
    func configure(with messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )
        methodChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    /// Saved category when transitioning into TTS playback. Used by
    /// restoreAudioSession() to flip back to whatever the app had set
    /// before TTS started. Nil means "no saved state — caller must
    /// explicitly pick a category".
    private var savedCategoryBeforeTtsPlayback: AVAudioSession.Category?
    private var savedCategoryOptionsBeforeTtsPlayback: AVAudioSession.CategoryOptions?

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        switch call.method {
        case "setPlayback":
            // P034 follow-up: during TTS playback, switch to .playback (no
            // microphone). With .playAndRecord active, iOS treats the
            // session as a "call/voice" mode and rejects hardware media
            // button presses — user hears the iOS rejection sound when
            // pressing AirPods. Switching to .playback during TTS makes
            // iOS route the press as media play/pause normally.
            // Saves the prior category so restoreAudioSession can flip back.
            do {
                NSLog("[AudioSessionDbg] setPlayback requested (current=\(session.category.rawValue))")
                self.savedCategoryBeforeTtsPlayback = session.category
                self.savedCategoryOptionsBeforeTtsPlayback = session.categoryOptions
                try session.setCategory(.playback, mode: .spokenAudio, options: [])
                try session.setActive(true)
                NSLog("[AudioSessionDbg] setPlayback applied — category=\(session.category.rawValue) options=\(session.categoryOptions.rawValue)")
                result(nil)
            } catch {
                NSLog("[AudioSessionDbg] setPlayback FAILED: \(error.localizedDescription)")
                result(FlutterError(
                    code: "AUDIO_SESSION_ERROR",
                    message: "Failed to set playback: \(error.localizedDescription)",
                    details: nil
                ))
            }
        case "restoreAudioSession":
            // Restore the category captured by the most recent setPlayback
            // call. If none was captured (caller never set playback or
            // restore was already called), this is a no-op.
            do {
                guard let savedCategory = self.savedCategoryBeforeTtsPlayback else {
                    NSLog("[AudioSessionDbg] restoreAudioSession called but nothing was saved — no-op")
                    result(nil)
                    return
                }
                let savedOptions = self.savedCategoryOptionsBeforeTtsPlayback ?? []
                NSLog("[AudioSessionDbg] restoreAudioSession requested (target=\(savedCategory.rawValue) options=\(savedOptions.rawValue))")
                try session.setCategory(savedCategory, mode: .default, options: savedOptions)
                try session.setActive(true)
                self.savedCategoryBeforeTtsPlayback = nil
                self.savedCategoryOptionsBeforeTtsPlayback = nil
                NSLog("[AudioSessionDbg] restoreAudioSession applied — category=\(session.category.rawValue) options=\(session.categoryOptions.rawValue)")
                result(nil)
            } catch {
                NSLog("[AudioSessionDbg] restoreAudioSession FAILED: \(error.localizedDescription)")
                result(FlutterError(
                    code: "AUDIO_SESSION_ERROR",
                    message: "Failed to restore: \(error.localizedDescription)",
                    details: nil
                ))
            }
        case "setPlayAndRecord":
            do {
                NSLog("[AudioSessionDbg] setPlayAndRecord requested")
                // NOTE: .mixWithOthers was removed (P034 follow-up). With it set,
                // iOS does NOT route hardware media-button events
                // (togglePlayPause from AirPods etc.) to this app — the
                // currently "now playing" app (Spotify, podcasts, …) keeps
                // the focus, so the user's headset button cannot interrupt
                // TTS or pause/resume the hands-free recording. Without
                // mixWithOthers, the app claims exclusive media focus when
                // playAndRecord is activated; iOS pauses other audio and
                // routes media-button events here. Trade-off: other apps'
                // audio is interrupted during hands-free sessions, which is
                // the intended behaviour for an assistant.
                // P034 follow-up experiment B: mode .spokenAudio (instead of
                // .default) signals to iOS that this is podcast/audiobook-style
                // content, NOT a call. With .default mode + .playAndRecord,
                // iOS treats the session as call-like and rejects hardware
                // media-button presses (audible "boop" rejection sound on
                // AirPods click). .spokenAudio explicitly tells iOS to treat
                // play/pause hardware events as media controls.
                try session.setCategory(
                    .playAndRecord,
                    mode: .spokenAudio,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )
                try session.setActive(true)
                NSLog("[AudioSessionDbg] setPlayAndRecord applied — category=\(session.category.rawValue) mode=\(session.mode.rawValue) options=\(session.categoryOptions.rawValue) active=true")
                result(nil)
            } catch {
                NSLog("[AudioSessionDbg] setPlayAndRecord FAILED: \(error.localizedDescription)")
                result(FlutterError(
                    code: "AUDIO_SESSION_ERROR",
                    message: "Failed to set playAndRecord: \(error.localizedDescription)",
                    details: nil
                ))
            }
        case "setAmbient":
            do {
                NSLog("[AudioSessionDbg] setAmbient requested")
                try session.setCategory(
                    .ambient,
                    mode: .default,
                    options: [.mixWithOthers]
                )
                NSLog("[AudioSessionDbg] setAmbient applied — category=\(session.category.rawValue) options=\(session.categoryOptions.rawValue)")
                result(nil)
            } catch {
                result(FlutterError(
                    code: "AUDIO_SESSION_ERROR",
                    message: "Failed to set ambient: \(error.localizedDescription)",
                    details: nil
                ))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
