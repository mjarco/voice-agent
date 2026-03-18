import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/storage/sqlite_storage_service.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await SqliteStorageService.initialize();

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: const App(),
    ),
  );
}
