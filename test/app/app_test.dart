import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';

void main() {
  testWidgets('App renders without crashing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );

    expect(find.text('Voice Agent'), findsWidgets);
  });

  testWidgets('App uses Material 3', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );

    final materialApp = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(materialApp.theme?.useMaterial3, isTrue);
  });
}
