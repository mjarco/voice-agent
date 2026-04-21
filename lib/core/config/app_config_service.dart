import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/vad_config.dart';

/// Sole persistence adapter for app configuration.
/// Knows about SharedPreferences keys and FlutterSecureStorage.
/// No other code should read/write these keys directly.
class AppConfigService {
  AppConfigService({
    SharedPreferences? prefs,
    FlutterSecureStorage? secureStorage,
  })  : _prefs = prefs,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  SharedPreferences? _prefs;
  final FlutterSecureStorage _secureStorage;

  static const _apiUrlKey = 'api_url';
  static const _apiTokenKey = 'api_token';
  static const _groqApiKeyKey = 'groq_api_key';
  static const _autoSendKey = 'auto_send';
  static const _languageKey = 'language';
  static const _keepHistoryKey = 'keep_history';

  static const _ttsEnabledKey = 'tts_enabled';
  static const _audioFeedbackEnabledKey = 'audio_feedback_enabled';

  static const _vadPositiveThresholdKey = 'vad_positive_threshold';
  static const _vadNegativeThresholdKey = 'vad_negative_threshold';
  static const _vadHangoverMsKey = 'vad_hangover_ms';
  static const _vadMinSpeechMsKey = 'vad_min_speech_ms';
  static const _vadPreRollMsKey = 'vad_pre_roll_ms';

  // ── P026 removal migration ──────────────────────────────────────────────
  // Keys retired by P026 (wake word feature + Porcupine). Cleaned up on first
  // launch of the new version, gated by [_wakeWordRemovalMigrationDoneKey].
  // See ADR-DATA-009.
  static const _wakeWordRemovalMigrationDoneKey =
      'wake_word_removal_migration_done';
  static const _retiredPrefsKeys = <String>[
    'background_listening_enabled',
    'wake_word_enabled',
    'wake_word_keyword',
    'wake_word_sensitivity',
    // Legacy IPC keys from the deleted PlatformChannelBridge.
    'activation_state',
    'activation_toggle_requested',
    'activation_stop_requested',
    'foreground_service_running',
  ];
  static const _retiredSecureStorageKeys = <String>[
    'picovoice_access_key',
  ];

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<AppConfig> load() async {
    final prefs = await _preferences;

    // Run the P026 removal migration before constructing the config so that
    // consumers never observe the deleted fields in transient states.
    await _runRemovalMigration(prefs);

    String? token;
    try {
      token = await _secureStorage.read(key: _apiTokenKey);
    } catch (_) {
      // Secure storage may fail on some devices — treat as absent
    }
    String? groqApiKey;
    try {
      groqApiKey = await _secureStorage.read(key: _groqApiKeyKey);
    } catch (_) {
      // Secure storage may fail on some devices — treat as absent
    }

    const defaults = VadConfig.defaults();
    final vadConfig = VadConfig(
      positiveSpeechThreshold: prefs.getDouble(_vadPositiveThresholdKey) ??
          defaults.positiveSpeechThreshold,
      negativeSpeechThreshold: prefs.getDouble(_vadNegativeThresholdKey) ??
          defaults.negativeSpeechThreshold,
      hangoverMs:
          prefs.getInt(_vadHangoverMsKey) ?? defaults.hangoverMs,
      minSpeechMs:
          prefs.getInt(_vadMinSpeechMsKey) ?? defaults.minSpeechMs,
      preRollMs: prefs.getInt(_vadPreRollMsKey) ?? defaults.preRollMs,
    ).clamp();

    return AppConfig(
      apiUrl: prefs.getString(_apiUrlKey),
      apiToken: token,
      groqApiKey: groqApiKey,
      autoSend: prefs.getBool(_autoSendKey) ?? true,
      language: prefs.getString(_languageKey) ?? 'auto',
      keepHistory: prefs.getBool(_keepHistoryKey) ?? true,
      vadConfig: vadConfig,
      ttsEnabled: prefs.getBool(_ttsEnabledKey) ?? true,
      audioFeedbackEnabled: prefs.getBool(_audioFeedbackEnabledKey) ?? true,
    );
  }

  Future<void> _runRemovalMigration(SharedPreferences prefs) async {
    if (prefs.getBool(_wakeWordRemovalMigrationDoneKey) == true) return;
    for (final key in _retiredPrefsKeys) {
      await prefs.remove(key);
    }
    for (final key in _retiredSecureStorageKeys) {
      try {
        await _secureStorage.delete(key: key);
      } catch (_) {
        // Best-effort — log-only; do not block migration on Keychain failure.
      }
    }
    await prefs.setBool(_wakeWordRemovalMigrationDoneKey, true);
  }

  Future<void> saveVadConfig(VadConfig config) async {
    final prefs = await _preferences;
    await prefs.setDouble(
        _vadPositiveThresholdKey, config.positiveSpeechThreshold);
    await prefs.setDouble(
        _vadNegativeThresholdKey, config.negativeSpeechThreshold);
    await prefs.setInt(_vadHangoverMsKey, config.hangoverMs);
    await prefs.setInt(_vadMinSpeechMsKey, config.minSpeechMs);
    await prefs.setInt(_vadPreRollMsKey, config.preRollMs);
  }

  Future<void> saveApiUrl(String url) async {
    final prefs = await _preferences;
    await prefs.setString(_apiUrlKey, url);
  }

  Future<void> saveApiToken(String token) async {
    await _secureStorage.write(key: _apiTokenKey, value: token);
  }

  Future<void> saveGroqApiKey(String key) async {
    await _secureStorage.write(key: _groqApiKeyKey, value: key);
  }

  Future<void> saveAutoSend(bool value) async {
    final prefs = await _preferences;
    await prefs.setBool(_autoSendKey, value);
  }

  Future<void> saveLanguage(String language) async {
    final prefs = await _preferences;
    await prefs.setString(_languageKey, language);
  }

  Future<void> saveKeepHistory(bool value) async {
    final prefs = await _preferences;
    await prefs.setBool(_keepHistoryKey, value);
  }

  Future<void> saveTtsEnabled(bool value) async {
    final prefs = await _preferences;
    await prefs.setBool(_ttsEnabledKey, value);
  }

  Future<void> saveAudioFeedbackEnabled(bool value) async {
    final prefs = await _preferences;
    await prefs.setBool(_audioFeedbackEnabledKey, value);
  }
}
