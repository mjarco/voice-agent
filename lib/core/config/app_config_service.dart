import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config.dart';

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
  static const _autoSendKey = 'auto_send';
  static const _languageKey = 'language';
  static const _keepHistoryKey = 'keep_history';

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<AppConfig> load() async {
    final prefs = await _preferences;
    String? token;
    try {
      token = await _secureStorage.read(key: _apiTokenKey);
    } catch (_) {
      // Secure storage may fail on some devices — treat as absent
    }

    return AppConfig(
      apiUrl: prefs.getString(_apiUrlKey),
      apiToken: token,
      autoSend: prefs.getBool(_autoSendKey) ?? true,
      language: prefs.getString(_languageKey) ?? 'auto',
      keepHistory: prefs.getBool(_keepHistoryKey) ?? true,
    );
  }

  Future<void> saveApiUrl(String url) async {
    final prefs = await _preferences;
    await prefs.setString(_apiUrlKey, url);
  }

  Future<void> saveApiToken(String token) async {
    await _secureStorage.write(key: _apiTokenKey, value: token);
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
}
