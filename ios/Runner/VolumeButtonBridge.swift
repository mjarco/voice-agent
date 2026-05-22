import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Bridges hardware volume button presses (iPhone, Apple Watch, AirPods
/// stem swipe) to Dart via platform channels.
///
/// Why: P037/P038 established that `MPRemoteCommand` (toggle / next /
/// prev) is uniformly blocked by iOS while the audio session is
/// `.playAndRecord` with an active mic engine. Volume buttons go
/// through a separate iOS routing path (`AVAudioSession.outputVolume`
/// KVO) that does NOT pass through the `MPRemoteCommand` gate, so
/// presses survive the call-mode block.
///
/// Trade-off: the observed volume change is real — the system volume
/// HUD flashes and the device volume actually moves a step. We do NOT
/// attempt to restore the volume here (would be a separate UX layer).
///
/// Channels:
/// - MethodChannel `com.voiceagent/volume_button` — `activate` / `deactivate`
/// - EventChannel  `com.voiceagent/volume_button/events` — emits `"up"` or `"down"`
///
/// Pattern mirrors `MediaButtonBridge`.
class VolumeButtonBridge: NSObject, FlutterStreamHandler {
    static let shared = VolumeButtonBridge()

    private let methodChannelName = "com.voiceagent/volume_button"
    private let eventChannelName = "com.voiceagent/volume_button/events"

    private var methodChannel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?

    private var observing = false
    private var lastVolume: Float = -1.0
    // Threshold for change detection. iOS volume steps are ~0.0625 (16
    // increments). Anything smaller is noise / programmatic restore.
    private let _stepThreshold: Float = 0.001

    // P041 — suppression window. `outputVolume` is tracked per
    // audio-session category context, so a category/route change makes
    // iOS report a different value with no button press involved. While
    // `Date() < suppressUntil` the KVO observer re-baselines silently
    // instead of emitting a phantom press.
    private var suppressUntil = Date.distantPast
    private let suppressionWindow: TimeInterval = 0.6

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
            startObserving()
            result(nil)
        case "deactivate":
            stopObserving()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Suppression (P041)

    /// Suppresses volume-button detection for [suppressionWindow] seconds.
    ///
    /// Called by the app itself (`AudioSessionBridge`) before every
    /// audio-session category change, and by the route-change observer
    /// below. Both events shift the value iOS reports for `outputVolume`
    /// without any hardware button press — this window stops that shift
    /// from being emitted as a phantom `"up"` / `"down"`.
    ///
    /// Safe to call when not observing — it only moves a timestamp.
    func suppressVolumeEvents() {
        suppressUntil = Date().addingTimeInterval(suppressionWindow)
        NSLog("[VolumeBtnDbg] suppressing volume events for \(suppressionWindow)s (audio-session transition)")
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        // A route or category change (mic acquisition, AirPods connect,
        // our own .playAndRecord switch) shifts `outputVolume` because
        // volume is tracked per audio-session context. Suppress briefly
        // so the shift is not misread as a press. Covers category
        // changes made outside AudioSessionBridge (e.g. the `record`
        // plugin's own session setup).
        suppressVolumeEvents()
    }

    // MARK: - KVO on AVAudioSession.outputVolume

    private func startObserving() {
        guard !observing else { return }
        let session = AVAudioSession.sharedInstance()
        // Capture initial value so the first real press has something to
        // diff against.
        lastVolume = session.outputVolume
        session.addObserver(self,
                            forKeyPath: "outputVolume",
                            options: [.new, .old],
                            context: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil)
        observing = true
        NSLog("[VolumeBtnDbg] startObserving — initial volume=\(lastVolume)")
    }

    private func stopObserving() {
        guard observing else { return }
        AVAudioSession.sharedInstance().removeObserver(self,
                                                      forKeyPath: "outputVolume")
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: nil)
        observing = false
        NSLog("[VolumeBtnDbg] stopObserving")
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume",
              let new = change?[.newKey] as? Float else {
            return
        }
        // Compute direction against the most recent observed value
        // rather than `change[.oldKey]` — `oldKey` is sometimes equal
        // to `newKey` for the first observation after registration on
        // some iOS versions.
        let prev = lastVolume
        lastVolume = new
        if prev < 0 {
            // First observation since startObserving — no direction yet.
            return
        }
        // P041 — inside a suppression window the change comes from an
        // audio-session category/route transition, not a button press.
        // `lastVolume` was already updated above, so the post-transition
        // value becomes the new baseline; emit nothing.
        if Date() < suppressUntil {
            NSLog("[VolumeBtnDbg] volume change suppressed (audio-session transition): \(prev) → \(new)")
            return
        }
        let delta = new - prev
        if abs(delta) < _stepThreshold {
            return
        }
        let direction = delta > 0 ? "up" : "down"
        NSLog("[VolumeBtnDbg] volume \(direction): \(prev) → \(new)")
        eventSink?(direction)
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
