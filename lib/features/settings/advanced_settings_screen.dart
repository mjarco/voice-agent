import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/vad_config.dart';

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
          const SizedBox(height: 16),
        ],
      ),
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
