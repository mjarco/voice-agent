// P039 T5a — native → Dart event bridge for iOS audio-session events.
//
// One EventChannel: `com.voiceagent/telemetry_native_events`. Native
// callers post structured payloads of the shape
// `{ type, ts_ms, attrs }`; Dart subscribes once at app boot and
// converts the events into Telemetry events via
// `TelemetryNativeBridge`.
//
// Idle when no Dart subscriber is attached: `post(...)` becomes a
// no-op so the existing `MediaButtonBridge` audio-session closures
// can call it unconditionally without flavour checks. The stable
// build never registers a Dart subscriber (`lib/main_stable.dart`
// does not wire `TelemetryNativeBridge`) so emission is a no-op
// even though the Swift code itself is in the binary.
//
// ADR-PLATFORM-005 §"channel-name registry" lists this channel
// alongside `com.voiceagent/audio_session` and
// `com.voiceagent/media_button`.

import Flutter
import Foundation

final class TelemetryEventEmitter: NSObject, FlutterStreamHandler {
    static let shared = TelemetryEventEmitter()

    private var channel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private override init() { super.init() }

    /// Register the EventChannel on the plugin registry's messenger.
    /// Call once from `AppDelegate.didInitializeImplicitFlutterEngine`.
    func configure(with messenger: FlutterBinaryMessenger) {
        let ch = FlutterEventChannel(
            name: "com.voiceagent/telemetry_native_events",
            binaryMessenger: messenger
        )
        ch.setStreamHandler(self)
        channel = ch
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

    // MARK: - Public emit API

    /// Post a structured event to Dart. No-op when no Dart subscriber
    /// is attached. Safe to call from any thread; the dispatch hop to
    /// the main queue lets `eventSink` invocations meet Flutter's
    /// single-isolate contract.
    func post(type: String, attrs: [String: Any] = [:]) {
        guard let sink = eventSink else { return }
        let payload: [String: Any] = [
            "type": type,
            "ts_ms": Int(Date().timeIntervalSince1970 * 1000),
            "attrs": attrs,
        ]
        // FlutterEventSink invocations must be on the platform thread.
        // Posting from the audio session observer queue (`.main` per
        // the existing MediaButtonBridge observers) makes this a
        // direct dispatch, but the asyncAfter wrap is a safety net
        // for any future caller that posts off-main.
        DispatchQueue.main.async {
            sink(payload)
        }
    }
}
