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

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        switch call.method {
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
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )
                try session.setActive(true)
                NSLog("[AudioSessionDbg] setPlayAndRecord applied — category=\(session.category.rawValue) options=\(session.categoryOptions.rawValue) active=true")
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
