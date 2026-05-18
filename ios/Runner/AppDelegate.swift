import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // In UIScene-based apps window?.rootViewController is nil here, so go via
    // the plugin registry to get a reliable binary messenger.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioSessionBridge") {
      AudioSessionBridge.shared.configure(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MediaButtonBridge") {
      MediaButtonBridge.shared.configure(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VolumeButtonBridge") {
      VolumeButtonBridge.shared.configure(with: registrar.messenger())
    }
    // P039 T5a — register the telemetry native-event channel. Idle
    // until `TelemetryNativeBridge` (Dart, dev flavour only)
    // subscribes; stable builds never subscribe so this stays a
    // no-op despite the registration.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TelemetryEventEmitter") {
      TelemetryEventEmitter.shared.configure(with: registrar.messenger())
    }
  }
}
