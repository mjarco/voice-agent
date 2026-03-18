import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/settings/settings_model.dart';
import 'package:voice_agent/features/settings/settings_service.dart';

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

final appSettingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.watch(settingsServiceProvider));
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._service)
      : super(const AppSettings()) {
    _load();
  }

  final SettingsService _service;

  Future<void> _load() async {
    state = await _service.load();
  }

  Future<void> updateApiUrl(String url) async {
    await _service.saveApiUrl(url);
    state = state.copyWith(apiUrl: url);
  }

  Future<void> updateApiToken(String token) async {
    await _service.saveApiToken(token);
    state = state.copyWith(apiToken: token);
  }

  Future<void> updateAutoSend(bool value) async {
    await _service.saveAutoSend(value);
    state = state.copyWith(autoSend: value);
  }

  Future<void> updateLanguage(String language) async {
    await _service.saveLanguage(language);
    state = state.copyWith(language: language);
  }

  Future<void> updateKeepHistory(bool value) async {
    await _service.saveKeepHistory(value);
    state = state.copyWith(keepHistory: value);
  }
}
