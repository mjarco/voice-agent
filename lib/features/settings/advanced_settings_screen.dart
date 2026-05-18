import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/providers/flavor_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';

class AdvancedSettingsScreen extends ConsumerStatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  ConsumerState<AdvancedSettingsScreen> createState() =>
      _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState
    extends ConsumerState<AdvancedSettingsScreen> {
  late VadConfig _draft;
  bool _userHasEdited = false;
  ProviderSubscription<VadConfig>? _sub;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(appConfigProvider).vadConfig;
    // listenManual keeps _draft in sync with async config load, but only
    // until the user starts editing.
    _sub = ref.listenManual(
      appConfigProvider.select((c) => c.vadConfig),
      (_, next) {
        if (!_userHasEdited) {
          setState(() => _draft = next);
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  void _onChangeEnd(VadConfig updated) {
    _userHasEdited = true;
    setState(() => _draft = updated);
    ref.read(appConfigProvider.notifier).updateVadConfig(updated);
  }

  void _resetToDefaults() {
    const defaults = VadConfig.defaults();
    _userHasEdited = true;
    setState(() => _draft = defaults);
    ref.read(appConfigProvider.notifier).updateVadConfig(defaults);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced (VAD)')),
      body: ListView(
        children: [
          _VadSlider(
            label: 'Speech threshold (positive)',
            value: _draft.positiveSpeechThreshold,
            min: 0.1,
            max: 0.9,
            divisions: 16,
            format: (v) => v.toStringAsFixed(2),
            onChangeEnd: (v) => _onChangeEnd(
              _draft.copyWith(positiveSpeechThreshold: v),
            ),
          ),
          _VadSlider(
            label: 'Non-speech threshold (negative)',
            value: _draft.negativeSpeechThreshold,
            min: 0.1,
            max: 0.8,
            divisions: 14,
            format: (v) => v.toStringAsFixed(2),
            onChangeEnd: (v) => _onChangeEnd(
              _draft.copyWith(negativeSpeechThreshold: v),
            ),
          ),
          _VadSlider(
            label: 'Hangover (ms)',
            value: _draft.hangoverMs.toDouble(),
            min: 100,
            max: 2000,
            divisions: 19,
            format: (v) => '${v.round()}ms',
            onChangeEnd: (v) => _onChangeEnd(
              _draft.copyWith(hangoverMs: v.round()),
            ),
          ),
          _VadSlider(
            label: 'Min speech (ms)',
            value: _draft.minSpeechMs.toDouble(),
            min: 100,
            max: 1000,
            divisions: 9,
            format: (v) => '${v.round()}ms',
            onChangeEnd: (v) => _onChangeEnd(
              _draft.copyWith(minSpeechMs: v.round()),
            ),
          ),
          _VadSlider(
            label: 'Pre-roll (ms)',
            value: _draft.preRollMs.toDouble(),
            min: 100,
            max: 800,
            divisions: 7,
            format: (v) => '${v.round()}ms',
            onChangeEnd: (v) => _onChangeEnd(
              _draft.copyWith(preRollMs: v.round()),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              key: const Key('reset-defaults'),
              onPressed: _resetToDefaults,
              child: const Text('Reset to defaults'),
            ),
          ),
          const SizedBox(height: 24),
          // P039 T5c — telemetry section is rendered only on the dev
          // flavor. Conditional on a runtime check is fine here because
          // the dev/stable gate is at the BUILD level (different
          // entrypoints, see ADR-OBS-001 §2); this conditional is just
          // for UI cleanliness. Test-overridable via [isDevFlavorProvider].
          if (ref.watch(isDevFlavorProvider))
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _TelemetrySection(),
            ),
        ],
      ),
    );
  }
}

class _TelemetrySection extends ConsumerStatefulWidget {
  const _TelemetrySection();

  @override
  ConsumerState<_TelemetrySection> createState() => _TelemetrySectionState();
}

class _TelemetrySectionState extends ConsumerState<_TelemetrySection> {
  late final TextEditingController _urlController;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: ref.read(appConfigProvider).otelCollectorUrl,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _markRestartRequired() {
    ref.read(telemetryRestartRequiredProvider.notifier).state = true;
  }

  void _onToggle(bool value) {
    // Flip the banner flag synchronously so the UI updates immediately;
    // persistence happens in the background.
    _markRestartRequired();
    unawaited(
      ref.read(appConfigProvider.notifier).updateDevTelemetryEnabled(value),
    );
  }

  void _onUrlSubmit(String value) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.isAbsolute || trimmed.isEmpty) {
      setState(() {
        _urlError = 'Invalid URL — must be absolute (http:// or https://).';
      });
      return;
    }
    setState(() => _urlError = null);
    _markRestartRequired();
    unawaited(
      ref.read(appConfigProvider.notifier).updateOtelCollectorUrl(trimmed),
    );
  }

  Future<void> _onClearBuffer() async {
    final storage = ref.read(storageServiceProvider);
    final n = await storage.clearTelemetryOutbox();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cleared $n telemetry rows.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final restartRequired = ref.watch(telemetryRestartRequiredProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Telemetry (dev)',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('telemetry-enabled-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable telemetry'),
          subtitle: const Text(
            'Send spans to the OTel Collector. Off = no network traffic.',
          ),
          value: config.devTelemetryEnabled,
          onChanged: _onToggle,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('telemetry-collector-url'),
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Collector URL',
            helperText:
                _urlError == null ? 'e.g. http://laptop.lan:4318' : null,
            errorText: _urlError,
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: _onUrlSubmit,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('telemetry-clear-buffer'),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear telemetry buffer'),
          onPressed: _onClearBuffer,
        ),
        if (restartRequired)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              key: const Key('telemetry-restart-banner'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.restart_alt,
                      color: theme.colorScheme.onTertiaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Restart the app to apply telemetry changes.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _VadSlider extends StatefulWidget {
  const _VadSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_VadSlider> createState() => _VadSliderState();
}

class _VadSliderState extends State<_VadSlider> {
  late double _current;

  @override
  void initState() {
    super.initState();
    _current = widget.value;
  }

  @override
  void didUpdateWidget(_VadSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _current = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(widget.label)),
          Text(
            widget.format(_current),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
      subtitle: Slider(
        value: _current,
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        onChanged: (v) => setState(() => _current = v),
        onChangeEnd: widget.onChangeEnd,
      ),
    );
  }
}
