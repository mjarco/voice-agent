import AVFoundation
import Flutter
import MediaPlayer

private func logAudioSession(_ tag: String) {
    let s = AVAudioSession.sharedInstance()
    NSLog("[MediaButtonDbg] \(tag) category=\(s.category.rawValue) options=\(s.categoryOptions.rawValue) mode=\(s.mode.rawValue) otherAudioPlaying=\(s.isOtherAudioPlaying)")
}

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
        NSLog("[MediaButtonDbg] activateRemoteCommands called")
        logAudioSession("activate")
        let center = MPRemoteCommandCenter.shared()

        // The hardware press is routed by iOS to one of these three commands
        // depending on the inferred playback state (and headset hardware).
        // togglePlayPause is the canonical case; play/pause are how iOS
        // disambiguates when nowPlayingInfo's playbackRate is 0.0 vs 1.0.
        // Register the same target on all three so we never miss the press.
        let toggleHandler: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
            let hasSink = (self?.eventSink != nil)
            NSLog("[MediaButtonDbg] togglePlayPause TARGET FIRED hasEventSink=\(hasSink)")
            logAudioSession("targetFired")
            self?.eventSink?("togglePlayPause")
            return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget(handler: toggleHandler)
        center.playCommand.isEnabled = true
        center.playCommand.addTarget(handler: toggleHandler)
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget(handler: toggleHandler)

        // Now-playing info must signal "actively playing" so iOS treats this
        // app as the foreground media participant. Setting playbackRate=1.0
        // and a non-zero duration is the standard pattern; without it, iOS
        // may route the hardware button to the lock-screen default player
        // (or the prior "now playing" app) instead.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Voice Agent",
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: 1.0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: 0.0),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: 1.0),
        ]
        NSLog("[MediaButtonDbg] activateRemoteCommands DONE (3 targets, nowPlayingInfo with rate=1)")
    }

    private func deactivateRemoteCommands() {
        NSLog("[MediaButtonDbg] deactivateRemoteCommands called")
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.isEnabled = false
        center.togglePlayPauseCommand.removeTarget(nil)
        center.playCommand.isEnabled = false
        center.playCommand.removeTarget(nil)
        center.pauseCommand.isEnabled = false
        center.pauseCommand.removeTarget(nil)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - FlutterStreamHandler

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        NSLog("[MediaButtonDbg] onListen — eventSink attached")
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NSLog("[MediaButtonDbg] onCancel — eventSink DETACHED")
        eventSink = nil
        return nil
    }
}
