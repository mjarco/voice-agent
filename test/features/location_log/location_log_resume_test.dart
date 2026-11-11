import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/location_log/domain/location_log_port.dart';
import 'package:voice_agent/features/location_log/domain/location_log_state.dart';
import 'package:voice_agent/features/location_log/presentation/location_log_providers.dart';
import 'package:voice_agent/features/location_log/presentation/location_log_sync.dart';

class _FakePort implements LocationLogPort {
  int resumed = 0;
  Object? failure;

  @override
  Future<void> appResumed() async {
    resumed++;
    if (failure != null) throw failure!;
  }

  @override
  Future<LocationLogState> getState() => throw UnimplementedError();
  @override
  Future<void> setCredentials({String? apiUrl, String? token}) async {}
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  Future<void> setAlertsEnabled(bool enabled) async {}
  @override
  Future<void> setMode(LocationLogMode mode) async {}
  @override
  Future<void> setForegroundInterval(int seconds) async {}
  @override
  Future<void> reconcile() async {}
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<bool> requestMotionPermission() async => false;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(_FakePort port, {bool available = true}) {
    final c = ProviderContainer(
      overrides: [
        locationLogPortProvider.overrideWithValue(port),
        locationLogAvailableProvider.overrideWithValue(available),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  void comeBack() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  test('each return to the app tells the native side', () {
    final port = _FakePort();
    container(port).read(locationLogResumeProvider);
    comeBack();
    comeBack();
    expect(port.resumed, 2);
  });

  test('a failure stays here', () async {
    final port = _FakePort()..failure = Exception('no engine');
    container(port).read(locationLogResumeProvider);
    comeBack();
    await pumpEventQueue();
    expect(port.resumed, 1);
  });

  test('does nothing off Android', () {
    final port = _FakePort();
    container(port, available: false).read(locationLogResumeProvider);
    comeBack();
    expect(port.resumed, 0);
  });
}
