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
  }
}
