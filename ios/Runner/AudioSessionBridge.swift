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
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
                )
                try session.setActive(true)
                result(nil)
            } catch {
                result(FlutterError(
                    code: "AUDIO_SESSION_ERROR",
                    message: "Failed to set playAndRecord: \(error.localizedDescription)",
                    details: nil
                ))
            }
        case "setAmbient":
            do {
                try session.setCategory(
                    .ambient,
                    mode: .default,
                    options: [.mixWithOthers]
                )
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
