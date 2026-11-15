// Writes each traced action of an integration test as a timeline summary
// (build/<reportKey>.timeline_summary.json); used by the glass spike of
// off-roadmap S2.
import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        for (final entry in data.entries) {
          final timeline = driver.Timeline.fromJson(entry.value as Map<String, dynamic>);
          final summary = driver.TimelineSummary.summarize(timeline);
          await summary.writeTimelineToFile(entry.key, pretty: true, includeSummary: true);
        }
      },
    );
