import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voice_agent/core/storage/sqlite_storage_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
  });

  test('getDeviceId returns a valid UUID on first call', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('voice_agent_test_');
    final storage = await SqliteStorageService.initialize(
      databaseFactory: databaseFactoryFfi,
      path: '${tempDir.path}/test.db',
    );

    final deviceId = await storage.getDeviceId();

    expect(deviceId, isNotEmpty);
    // UUID v4 format: 8-4-4-4-12
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(deviceId),
      isTrue,
      reason: 'Expected UUID v4 format, got: $deviceId',
    );
  });

  test('getDeviceId returns same value on repeated calls', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('voice_agent_test_');
    final storage = await SqliteStorageService.initialize(
      databaseFactory: databaseFactoryFfi,
      path: '${tempDir.path}/test.db',
    );

    final first = await storage.getDeviceId();
    final second = await storage.getDeviceId();

    expect(first, equals(second));
  });
}
