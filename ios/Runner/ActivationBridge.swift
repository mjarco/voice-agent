import Flutter
import UIKit

/// Bridges the iOS Control Center widget extension with Flutter's activation
/// controller via a MethodChannel and App Group UserDefaults.
///
/// On `applicationDidBecomeActive`, checks for a pending `activation_requested`
/// flag in the shared App Group UserDefaults (set by the Control Center widget)
/// and forwards it to Flutter via the `com.voiceagent/activation` MethodChannel.
///
/// Also provides a method for Flutter to write activation state changes back
/// to the shared UserDefaults so the widget can display the current state.
class ActivationBridge {
    static let shared = ActivationBridge()

    private let channelName = "com.voiceagent/activation"
    private let suiteName = "group.com.voiceagent.shared"
    private var methodChannel: FlutterMethodChannel?

    private init() {}

    /// Call from AppDelegate after the Flutter engine is available.
    func configure(with messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )
    }

    /// Check for pending activation requests from the widget extension.
    /// Call on `applicationDidBecomeActive` or `sceneDidBecomeActive`.
    func checkPendingActivation() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        let requested = defaults.bool(forKey: "activation_requested")
        if requested {
            defaults.set(false, forKey: "activation_requested")
            methodChannel?.invokeMethod("toggleFromIntent", arguments: nil)
        }
    }
}
