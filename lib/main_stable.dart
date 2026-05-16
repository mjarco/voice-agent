// `stable` flavor entrypoint. No telemetry — `Telemetry.instance`
// keeps its no-op default. This file MUST NOT import
// `package:opentelemetry` directly or transitively. The dev-flavor
// entrypoint (`lib/main_dev.dart`) is the only file in this repo that
// reaches `package:opentelemetry`.
//
// Verified by `ops/scripts/verify-stable-tree-shake.sh`.

import 'package:voice_agent/app_main.dart';

Future<void> main() => appMain();
