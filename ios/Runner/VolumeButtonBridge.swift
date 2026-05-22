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
        observing = true
        NSLog("[VolumeBtnDbg] startObserving — initial volume=\(lastVolume)")
    }

    private func stopObserving() {
        guard observing else { return }
        AVAudioSession.sharedInstance().removeObserver(self,
                                                      forKeyPath: "outputVolume")
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
