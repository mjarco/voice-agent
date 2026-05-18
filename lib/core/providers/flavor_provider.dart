// Routes the build-time `appFlavor` through a provider so widgets can
// observe + tests can override it without touching `package:flutter/services.dart`.
//
// The runtime check is a pure UX gate (e.g. "show the dev-only Telemetry
// section in Settings"). The hard isolation between dev and stable
// builds remains the flavor-specific entrypoints (ADR-OBS-001 §2) —
// stable AOT never reaches the dev-only code paths regardless of what
// this provider says.

import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` when running the `dev` flavor build, `false` otherwise.
/// Overridable in tests.
final isDevFlavorProvider = Provider<bool>((_) => appFlavor == 'dev');
