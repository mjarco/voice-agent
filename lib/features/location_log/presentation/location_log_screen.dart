import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/location_log/domain/location_log_port.dart';
import 'package:voice_agent/features/location_log/domain/location_log_state.dart';
import 'package:voice_agent/features/location_log/presentation/location_log_providers.dart';

const _foregroundIntervals = <int>[10, 30, 60, 300];

/// Settings of the location log: the switch that doubles as pause, the mode,
/// and a line saying what the pipeline is doing.
class LocationLogScreen extends ConsumerStatefulWidget {
  const LocationLogScreen({super.key});

  @override
  ConsumerState<LocationLogScreen> createState() => _LocationLogScreenState();
}

class _LocationLogScreenState extends ConsumerState<LocationLogScreen>
    with WidgetsBindingObserver {
  static const _refreshEvery = Duration(seconds: 5);

  Timer? _refresh;
  String? _error;

  LocationLogPort get _port => ref.read(locationLogPortProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh = Timer.periodic(_refreshEvery, (_) => _reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may come back from the system's permission page.
    if (state == AppLifecycleState.resumed) _reload();
  }

  void _reload() {
    if (mounted) ref.invalidate(locationLogStateProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = 'Nie udało się: $e');
    }
    _reload();
  }

  /// Turning alerts on runs the log's permission flow: while-in-use,
  /// notifications, then "all the time" on the settings page. Without
  /// "always" the native side writes `geofences_failed`, and the status line
  /// below offers "Nadaj".
  Future<void> _setAlertsEnabled(bool enabled) => _run(() async {
    if (enabled) await _port.requestPermissions();
    await _port.setAlertsEnabled(enabled);
  });

  Future<void> _setEnabled(bool enabled, LocationLogState state) =>
      _run(() async {
        if (enabled && state.permission == LocationLogPermission.none) {
          await _port.requestPermissions();
        }
        await _port.setEnabled(enabled);
      });

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationLogStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Dziennik lokalizacji')),
      body: state.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Błąd: $e')),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(LocationLogState state) {
    return ListView(
      children: [
        SwitchListTile(
          key: const Key('location-log-switch'),
          title: const Text('Zbieraj lokalizację'),
          subtitle: const Text('Wyłączenie to pauza; kolejka dalej się wysyła'),
          value: state.enabled,
          onChanged: (v) => _setEnabled(v, state),
        ),
        RadioGroup<LocationLogMode>(
          groupValue: state.mode,
          onChanged: (mode) {
            if (mode != null) _run(() => _port.setMode(mode));
          },
          child: const Column(
            children: [
              RadioListTile<LocationLogMode>(
                key: Key('location-log-mode-background'),
                title: Text('Tylko w tle'),
                subtitle: Text('Kilka odczytów na godzinę, bez powiadomienia'),
                value: LocationLogMode.background,
              ),
              RadioListTile<LocationLogMode>(
                key: Key('location-log-mode-foreground'),
                title: Text('Usługa pierwszoplanowa'),
                subtitle: Text(
                  'Tak często, jak chcesz, ze stałym powiadomieniem',
                ),
                value: LocationLogMode.foreground,
              ),
            ],
          ),
        ),
        if (state.mode == LocationLogMode.foreground)
          ListTile(
            title: const Text('Odczyt co'),
            trailing: DropdownButton<int>(
              key: const Key('location-log-interval'),
              value: state.foregroundIntervalSeconds,
              items: [
                for (final s in {
                  ..._foregroundIntervals,
                  state.foregroundIntervalSeconds,
                })
                  DropdownMenuItem(value: s, child: Text('$s s')),
              ],
              onChanged: (s) {
                if (s != null) _run(() => _port.setForegroundInterval(s));
              },
            ),
          ),
        const Divider(),
        SwitchListTile(
          key: const Key('arrival-alerts-switch'),
          title: const Text('Alerty w sklepach'),
          subtitle: Text(
            'Na razie tylko zapis w dzienniku · '
            'wyzwalacze: ${state.triggerCount}'
            '${state.triggersCheckedAt == null ? '' : ', sprawdzone ${_time(state.triggersCheckedAt)}'}'
            ' · obszary: ${state.geofenceCount}'
            '${state.geofencesAt == null ? '' : '\nZarejestrowane: ${_time(state.geofencesAt)}'}',
          ),
          value: state.alertsEnabled,
          onChanged: _setAlertsEnabled,
        ),
        const Divider(),
        ListTile(
          key: const Key('location-log-status'),
          title: Text(_permissionLine(state.permission)),
          subtitle: Text(_statusLine(state)),
          trailing: state.permission == LocationLogPermission.always
              ? null
              : TextButton(
                  onPressed: () => _run(() async {
                    if (state.permission == LocationLogPermission.none) {
                      await _port.requestPermissions();
                    } else {
                      await _port.openAppSettings();
                    }
                  }),
                  child: const Text('Nadaj'),
                ),
        ),
        if (state.lastError != null)
          ListTile(
            key: const Key('location-log-last-error'),
            title: const Text('Ostatni błąd wysyłki'),
            subtitle: Text(state.lastError!),
          ),
        if (_error != null)
          ListTile(
            key: const Key('location-log-error'),
            title: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  String _permissionLine(LocationLogPermission permission) =>
      switch (permission) {
        LocationLogPermission.always => 'Uprawnienie: zawsze',
        LocationLogPermission.whileInUse =>
          'Uprawnienie: tylko podczas używania',
        LocationLogPermission.approximate => 'Uprawnienie: przybliżona',
        LocationLogPermission.none => 'Brak uprawnienia',
      };

  String _statusLine(LocationLogState state) =>
      'Ostatni odczyt: ${_time(state.lastReadingAt)}\n'
      'Ostatnia wysyłka: ${_time(state.lastSentAt)}\n'
      'W kolejce: ${state.queueLength}';
}

String _time(DateTime? t) {
  if (t == null) return 'jeszcze nie';
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  final ss = t.second.toString().padLeft(2, '0');
  return '${t.day}.${t.month.toString().padLeft(2, '0')} $hh:$mm:$ss';
}
