import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/features/settings/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  String? _urlError;
  _TestStatus _testStatus = _TestStatus.idle;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _urlController = TextEditingController(text: settings.apiUrl ?? '');
    _tokenController = TextEditingController(text: settings.apiToken ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
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
      ref.read(appSettingsProvider.notifier).updateApiUrl(url);
    }
  }

  void _onTokenFocusLost() {
    final token = _tokenController.text;
    ref.read(appSettingsProvider.notifier).updateApiToken(token);
  }

  Future<void> _testConnection() async {
    final url = _urlController.text;
    if (!_isValidUrl(url)) return;

    setState(() => _testStatus = _TestStatus.testing);

    final apiClient = ref.read(apiClientProvider);
    final token = _tokenController.text;

    final result = await apiClient.post(
      Transcript(
        id: 'test',
        text: 'test',
        deviceId: 'test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
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
    final settings = ref.watch(appSettingsProvider);

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
          ListTile(
            title: const Text('Language'),
            trailing: DropdownButton<String>(
              value: settings.language,
              onChanged: (v) {
                if (v != null) {
                  ref.read(appSettingsProvider.notifier).updateLanguage(v);
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
            value: settings.autoSend,
            onChanged: (v) {
              ref.read(appSettingsProvider.notifier).updateAutoSend(v);
            },
          ),
          SwitchListTile(
            title: const Text('Keep history'),
            subtitle: const Text('Store transcripts locally'),
            value: settings.keepHistory,
            onChanged: (v) {
              ref.read(appSettingsProvider.notifier).updateKeepHistory(v);
            },
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
