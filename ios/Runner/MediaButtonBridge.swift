import Flutter
import MediaPlayer

/// Bridges iOS media remote-command events (e.g. AirPods play/pause)
/// to Dart via platform channels.
///
/// - MethodChannel `com.voiceagent/media_button` handles `activate` /
///   `deactivate` calls from Dart.
/// - EventChannel `com.voiceagent/media_button/events` streams toggle
///   events back to Dart.
///
/// Pattern mirrors `AudioSessionBridge`.
class MediaButtonBridge: NSObject, FlutterStreamHandler {
    static let shared = MediaButtonBridge()

    private let methodChannelName = "com.voiceagent/media_button"
    private let eventChannelName = "com.voiceagent/media_button/events"

    private var methodChannel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?

    private override init() {
        super.init()
    }

    /// Call from AppDelegate after the Flutter engine is available.
    func configure(with messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        methodChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }

        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(self)
    }

    // MARK: - MethodChannel handler

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "activate":
            activateRemoteCommands()
            result(nil)
        case "deactivate":
            deactivateRemoteCommands()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Remote command management

    private func activateRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.eventSink?("togglePlayPause")
            return .success
        }

        // Set minimal now-playing info so the system recognizes this app
        // as an active media participant (required for AirPods routing).
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Voice Agent"
        ]
    }

    private func deactivateRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.isEnabled = false
        center.togglePlayPauseCommand.removeTarget(nil)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - FlutterStreamHandler

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
