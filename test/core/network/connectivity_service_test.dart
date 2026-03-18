import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';

class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> _current = [ConnectivityResult.wifi];

  void emit(List<ConnectivityResult> results) {
    _current = results;
    _controller.add(results);
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeConnectivity fakeConnectivity;
  late ConnectivityService service;

  setUp(() {
    fakeConnectivity = FakeConnectivity();
    service = ConnectivityService(connectivity: fakeConnectivity);
  });

  group('ConnectivityService', () {
    test('currentStatus returns online when wifi connected', () async {
      fakeConnectivity._current = [ConnectivityResult.wifi];
      final status = await service.currentStatus;
      expect(status, ConnectivityStatus.online);
    });

    test('currentStatus returns online when mobile connected', () async {
      fakeConnectivity._current = [ConnectivityResult.mobile];
      final status = await service.currentStatus;
      expect(status, ConnectivityStatus.online);
    });

    test('currentStatus returns offline when none', () async {
      fakeConnectivity._current = [ConnectivityResult.none];
      final status = await service.currentStatus;
      expect(status, ConnectivityStatus.offline);
    });

    test('currentStatus returns offline when empty', () async {
      fakeConnectivity._current = [];
      final status = await service.currentStatus;
      expect(status, ConnectivityStatus.offline);
    });

    test('statusStream emits online/offline transitions', () async {
      final statuses = <ConnectivityStatus>[];
      final sub = service.statusStream.listen(statuses.add);

      fakeConnectivity.emit([ConnectivityResult.wifi]);
      fakeConnectivity.emit([ConnectivityResult.none]);
      fakeConnectivity.emit([ConnectivityResult.mobile]);

      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(statuses, [
        ConnectivityStatus.online,
        ConnectivityStatus.offline,
        ConnectivityStatus.online,
      ]);
    });
  });
}
