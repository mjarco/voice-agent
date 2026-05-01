import AVFoundation
import Flutter
import MediaPlayer
import UIKit

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

    private var interruptionObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

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
        let makeHandler: (String) -> ((MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) = { source in
            return { [weak self] _ in
                let hasSink = (self?.eventSink != nil)
                NSLog("[MediaButtonDbg] \(source) TARGET FIRED hasEventSink=\(hasSink)")
                logAudioSession("targetFired:\(source)")
                self?.eventSink?("togglePlayPause")
                return .success
            }
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget(handler: makeHandler("togglePlayPause"))
        center.playCommand.isEnabled = true
        center.playCommand.addTarget(handler: makeHandler("play"))
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget(handler: makeHandler("pause"))

        // Diagnostic: confirm registration stuck.
        NSLog("[MediaButtonDbg] toggle.enabled=\(center.togglePlayPauseCommand.isEnabled) play.enabled=\(center.playCommand.isEnabled) pause.enabled=\(center.pauseCommand.isEnabled)")
        startStatePolling()

        // Now-playing info must signal "actively playing" so iOS treats this
        // app as the foreground media participant. Setting playbackRate=1.0
        // and a non-zero duration is the standard pattern; without it, iOS
        // may route the hardware button to the lock-screen default player
        // (or the prior "now playing" app) instead.
        refreshNowPlayingInfo()
        installLifecycleObservers()
        NSLog("[MediaButtonDbg] activateRemoteCommands DONE (3 targets, nowPlayingInfo with rate=1)")
    }

    /// (Re)publish the now-playing dictionary so iOS keeps treating us
    /// as the active media participant. Without a fresh entry iOS may
    /// route hardware-button events to whichever app last had a slot,
    /// producing the rejection "boop" sound on AirPods presses.
    private func refreshNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Voice Agent",
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: 1.0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: 0.0),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: 1.0),
        ]
    }

    /// Subscribe to the lifecycle events that drop us out of media-
    /// participant routing without producing a deactivate call:
    ///   • `AVAudioSessionInterruption.ended` — phone call, Siri,
    ///     alarm, screen lock — any of these can suspend our session.
    ///   • `applicationDidBecomeActive` — fired when the app returns
    ///     from the lock screen or background. iOS sometimes drops
    ///     the now-playing slot during the suspension window even
    ///     when no formal interruption fires.
    ///   • `AVAudioSessionRouteChange` — AirPods reconnect, output
    ///     swap, etc. The route change may invalidate the slot.
    /// In all three we reactivate the session and refresh the
    /// now-playing dict so the next AirPods press lands on us.
    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        if interruptionObserver == nil {
            interruptionObserver = center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.handleInterruption(note)
            }
        }
        if didBecomeActiveObserver == nil {
            didBecomeActiveObserver = center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Refresh-only: the audio session may already be owned
                // by the recorder or the ambient player. Calling
                // setActive(true) here races with their activation and
                // surfaces as PlatformException("Failed to start audio")
                // when AudioRecorder later attempts setCategory + setActive.
                NSLog("[MediaButtonDbg] didBecomeActive — refreshing nowPlayingInfo")
                self?.refreshNowPlayingInfo()
            }
        }
        if routeChangeObserver == nil {
            routeChangeObserver = center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let reasonValue = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
                NSLog("[MediaButtonDbg] routeChange reason=\(reasonValue) — refreshing nowPlayingInfo")
                self?.refreshNowPlayingInfo()
            }
        }
    }

    private func removeLifecycleObservers() {
        let center = NotificationCenter.default
        if let o = interruptionObserver { center.removeObserver(o); interruptionObserver = nil }
        if let o = didBecomeActiveObserver { center.removeObserver(o); didBecomeActiveObserver = nil }
        if let o = routeChangeObserver { center.removeObserver(o); routeChangeObserver = nil }
    }

    private func handleInterruption(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let raw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else {
            return
        }
        switch type {
        case .began:
            NSLog("[MediaButtonDbg] interruption began")
        case .ended:
            let optsRaw = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
            NSLog("[MediaButtonDbg] interruption ended (shouldResume=\(opts.contains(.shouldResume)))")
            // Only call setActive(true) when iOS hands back the
            // session via .shouldResume. Forcing reactivation in
            // every case races with the recorder/ambient player and
            // surfaces as PlatformException on the next startSession.
            if opts.contains(.shouldResume) {
                reactivateSession()
            } else {
                refreshNowPlayingInfo()
            }
        @unknown default:
            break
        }
    }

    private func reactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            refreshNowPlayingInfo()
            NSLog("[MediaButtonDbg] session reactivated")
        } catch {
            NSLog("[MediaButtonDbg] reactivateSession FAILED: \(error.localizedDescription)")
        }
    }

    // Diagnostic: every 2s log audio session + nowPlayingInfo state so we
    // can see what iOS sees when the user presses the headset button. The
    // poll auto-stops when deactivateRemoteCommands runs.
    private var statePollTimer: Timer?
    private func startStatePolling() {
        stopStatePolling()
        statePollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let s = AVAudioSession.sharedInstance()
            let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
            let rate = info?[MPNowPlayingInfoPropertyPlaybackRate] ?? "nil"
            let title = info?[MPMediaItemPropertyTitle] ?? "nil"
            NSLog("[MediaButtonDbg] poll category=\(s.category.rawValue) options=\(s.categoryOptions.rawValue) other=\(s.isOtherAudioPlaying) npRate=\(rate) npTitle=\(title)")
        }
    }
    private func stopStatePolling() {
        statePollTimer?.invalidate()
        statePollTimer = nil
    }

    private func deactivateRemoteCommands() {
        stopStatePolling()
        removeLifecycleObservers()
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
