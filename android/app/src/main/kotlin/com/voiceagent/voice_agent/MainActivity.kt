package com.voiceagent.voice_agent

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val ACTION_TOGGLE_ACTIVATION = "com.voiceagent.ACTION_TOGGLE_ACTIVATION"
        private const val CHANNEL = "com.voiceagent/activation"
    }

    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleActivationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleActivationIntent(intent)
    }

    private fun handleActivationIntent(intent: Intent?) {
        if (intent?.action == ACTION_TOGGLE_ACTIVATION) {
            methodChannel?.invokeMethod("toggleFromIntent", null)
        }
    }
}
