import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';

/// Provider for ApiClient — lives here to avoid settings importing api_sync.
final _apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _groqKeyController;
  String? _urlError;
  _TestStatus _testStatus = _TestStatus.idle;
  ProviderSubscription<AppConfig>? _configSubscription;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider);
    _urlController = TextEditingController(text: config.apiUrl ?? '');
    _tokenController = TextEditingController(text: config.apiToken ?? '');
    _groqKeyController = TextEditingController(text: config.groqApiKey ?? '');
    // listenManual is the correct API for initState — keeps controllers in sync
    // when appConfigProvider emits the loaded value after async secure-storage read.
    _configSubscription = ref.listenManual(appConfigProvider, (_, next) {
      if (_urlController.text.isEmpty) {
        _urlController.text = next.apiUrl ?? '';
      }
      if (_tokenController.text.isEmpty) {
        _tokenController.text = next.apiToken ?? '';
      }
      if (_groqKeyController.text.isEmpty) {
        _groqKeyController.text = next.groqApiKey ?? '';
      }
    });
  }

  @override
  void dispose() {
    _configSubscription?.close();
    _urlController.dispose();
    _tokenController.dispose();
    _groqKeyController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  void _onUrlChanged() {
    final url = _urlController.text;
    setState(() {
      if (url.isNotEmpty && !_isValidUrl(url)) {
        _urlError = 'Enter a valid URL starting with http:// or https://';
      } else {
        _urlError = null;
      }
      _testStatus = _TestStatus.idle;
    });
    if (url.isNotEmpty && _isValidUrl(url)) {
      ref.read(appConfigProvider.notifier).updateApiUrl(url);
    }
  }

  void _onTokenFocusLost() {
    final token = _tokenController.text;
    ref.read(appConfigProvider.notifier).updateApiToken(token);
  }

  void _onGroqKeyFocusLost() {
    final key = _groqKeyController.text;
    ref.read(appConfigProvider.notifier).updateGroqApiKey(key);
  }

  Future<void> _testConnection() async {
    final url = _urlController.text;
    if (!_isValidUrl(url)) return;

    setState(() => _testStatus = _TestStatus.testing);

    final apiClient = ref.read(_apiClientProvider);
    final token = _tokenController.text;

    final result = await apiClient.testConnection(
      url: url,
      token: token.isNotEmpty ? token : null,
    );

    if (!mounted) return;

    setState(() {
      _testStatus = switch (result) {
        ApiSuccess() => _TestStatus.success,
        ApiPermanentFailure() => _TestStatus.error,
        ApiTransientFailure() => _TestStatus.error,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _buildSectionHeader('API Configuration'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'API URL',
                hintText: 'https://your-api.com/endpoint',
                border: const OutlineInputBorder(),
                errorText: _urlError,
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) => _onUrlChanged(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) _onTokenFocusLost();
              },
              child: TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'API Token',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _urlController.text.isNotEmpty &&
                          _urlError == null &&
                          _testStatus != _TestStatus.testing
                      ? _testConnection
                      : null,
                  child: _testStatus == _TestStatus.testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test Connection'),
                ),
                const SizedBox(width: 12),
                if (_testStatus == _TestStatus.success)
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 4),
                      Text('Connection successful'),
                    ],
                  ),
                if (_testStatus == _TestStatus.error)
                  const Row(
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 20),
                      SizedBox(width: 4),
                      Text('Could not reach server'),
                    ],
                  ),
              ],
            ),
          ),
          _buildSectionHeader('Transcription'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) _onGroqKeyFocusLost();
              },
              child: TextField(
                controller: _groqKeyController,
                decoration: const InputDecoration(
                  labelText: 'Groq API Key',
                  hintText: 'gsk_...',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ),
          ),
          ListTile(
            title: const Text('Language'),
            trailing: DropdownButton<String>(
              value: config.language,
              onChanged: (v) {
                if (v != null) {
                  ref.read(appConfigProvider.notifier).updateLanguage(v);
                }
              },
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto')),
                DropdownMenuItem(value: 'pl', child: Text('Polish')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
            ),
          ),
          _buildSectionHeader('General'),
          SwitchListTile(
            title: const Text('Auto-send'),
            subtitle: const Text('Send transcripts automatically'),
            value: config.autoSend,
            onChanged: (v) {
              ref.read(appConfigProvider.notifier).updateAutoSend(v);
            },
          ),
          SwitchListTile(
            title: const Text('Keep history'),
            subtitle: const Text('Store transcripts locally'),
            value: config.keepHistory,
            onChanged: (v) {
              ref.read(appConfigProvider.notifier).updateKeepHistory(v);
            },
          ),
          _buildSectionHeader('Voice Activity Detection'),
          ListTile(
            key: const Key('advanced-vad-tile'),
            title: const Text('Advanced (VAD)'),
            subtitle: const Text('Speech detection tuning'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/advanced'),
          ),
          _buildSectionHeader('About'),
          ListTile(
            title: const Text('Version'),
            trailing: const Text('1.0.0'),
          ),
          FutureBuilder<String>(
            future: ref.read(storageServiceProvider).getDeviceId(),
            builder: (context, snapshot) {
              final deviceId = snapshot.data ?? '...';
              return ListTile(
                title: const Text('Device ID'),
                subtitle: Text(deviceId),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: deviceId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Device ID copied')),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

enum _TestStatus { idle, testing, success, error }
