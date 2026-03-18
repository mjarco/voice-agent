import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_service.dart';

final appConfigServiceProvider = Provider<AppConfigService>((ref) {
  return AppConfigService();
});

final appConfigProvider =
    StateNotifierProvider<AppConfigNotifier, AppConfig>((ref) {
  return AppConfigNotifier(ref.watch(appConfigServiceProvider));
});

class AppConfigNotifier extends StateNotifier<AppConfig> {
  AppConfigNotifier(this._service) : super(const AppConfig()) {
    _load();
  }

  final AppConfigService _service;

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
