import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Toggle Intent

@available(iOS 18.0, *)
struct ToggleVoiceAgentIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Toggle Voice Agent"
    static var description: IntentDescription = "Toggles voice agent background listening"

    /// When true, the system launches the app before performing the intent.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Listening")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.voiceagent.shared")
        defaults?.set(true, forKey: "activation_requested")
        return .result()
    }
}

// MARK: - Control Widget

@available(iOS 18.0, *)
struct VoiceAgentControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.voiceagent.VoiceAgentControl"
        ) {
            ControlWidgetToggle(
                "Voice Agent",
                isOn: isListening(),
                action: ToggleVoiceAgentIntent()
            ) { isOn in
                Label(
                    isOn ? "Listening" : "Voice Agent",
                    systemImage: isOn ? "mic.fill" : "mic.slash"
                )
            }
        }
        .displayName("Voice Agent")
        .description("Toggle voice agent background listening")
    }

    private func isListening() -> Bool {
        let defaults = UserDefaults(suiteName: "group.com.voiceagent.shared")
        return defaults?.string(forKey: "activation_state") == "listening"
    }
}

// MARK: - Widget Bundle

@available(iOS 18.0, *)
@main
struct VoiceAgentControlBundle: WidgetBundle {
    var body: some Widget {
        VoiceAgentControl()
    }
}
