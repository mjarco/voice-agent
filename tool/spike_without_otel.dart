// P039 T1 spike — entrypoint that does NOT import OTel. Compared against
// spike_with_otel.dart to measure the AOT tree-shake delta.

import 'package:flutter/material.dart';

void main() {
  runApp(const _SpikeApp());
}

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('spike without OTel'))),
    );
  }
}
