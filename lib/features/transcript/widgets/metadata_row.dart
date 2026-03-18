import 'package:flutter/material.dart';

class MetadataRow extends StatelessWidget {
  const MetadataRow({
    super.key,
    required this.language,
    required this.durationMs,
    required this.timestamp,
  });

  final String language;
  final int durationMs;
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final durationSec = (durationMs / 1000).round();
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Icon(Icons.language, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 4),
        Text(
          language.toUpperCase(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 16),
        Icon(Icons.timer, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 4),
        Text(
          '${durationSec}s',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 16),
        Icon(Icons.access_time, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 4),
        Text(
          timeStr,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
