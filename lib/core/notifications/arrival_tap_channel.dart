import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Taps on the arrival alerts, which Kotlin posts natively (ADR-NOTIF-003),
/// over `com.voiceagent/arrival_tap`, in the pattern of ADR-PLATFORM-008:
/// [takeInitialRoute] gives the route of the tap that launched the app, and
/// [routes] every tap after it. Only routes a trigger may open come out.
class ArrivalTapChannel {
  ArrivalTapChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.voiceagent/arrival_tap');

  final MethodChannel _channel;

  /// Single subscription: a tap during boot waits for the app to listen.
  final _routes = StreamController<String>();

  Stream<String> get routes => _routes.stream;

  /// Call once, before `runApp`. The warm path opens only after this read, so
  /// one tap never reaches both channels.
  Future<String?> takeInitialRoute() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return arrivalRoute(
        await _channel.invokeMethod<String>('takeInitialRoute'),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } finally {
      _channel.setMethodCallHandler(_onCall);
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'tapped') return;
    final route = arrivalRoute(call.arguments as String? ?? '');
    if (route != null) _routes.add(route);
  }
}

/// A store type id as personal-agent writes them (`diy`, `home_garden`).
final _storeTypeId = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// The start screen, which a route a trigger may not open gives instead.
const arrivalStartRoute = '/record';

/// The routes a trigger may open (04, section 6): only `/shopping`, with an
/// optional `store=` list of type ids. Ids of another shape are dropped; with
/// none left it is plain `/shopping`. Any other route, or none, opens the
/// start screen. Null only when there was no tap. The catalogue's own check
/// is Shopping's, which has the catalogue.
String? arrivalRoute(String? open) {
  if (open == null) return null;
  final Uri uri;
  try {
    uri = Uri.parse(open);
  } on FormatException {
    return arrivalStartRoute;
  }
  if (uri.hasScheme || uri.hasAuthority || uri.path != '/shopping') {
    return arrivalStartRoute;
  }
  final store = uri.queryParameters['store'];
  final types = <String>[
    for (final t in (store ?? '').split(','))
      if (_storeTypeId.hasMatch(t)) t,
  ];
  final unique = types.toSet().toList();
  if (unique.isEmpty) return '/shopping';
  return '/shopping?store=${unique.join(',')}';
}
