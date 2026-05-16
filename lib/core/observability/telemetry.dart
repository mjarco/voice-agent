// Telemetry facade — abstract API used by call-sites across the app.
//
// The concrete subtype is selected at boot by the flavor-specific entrypoint
// (see ADR-OBS-001 §2). `lib/main_stable.dart` leaves the no-op default;
// `lib/main_dev.dart` reassigns `Telemetry.instance` to an OTel-backed
// implementation that imports `package:opentelemetry`.
//
// Tests inherit the no-op default. No setUp is required.

/// Abstract telemetry facade. Use [Telemetry.instance] from any layer.
///
/// The default implementation is [NoopTelemetry] — a zero-cost stand-in
/// that compiles into the `stable` flavor without any OpenTelemetry
/// dependency.
abstract class Telemetry {
  /// The process-wide singleton. Defaults to [NoopTelemetry] at static
  /// initialisation.
  ///
  /// `lib/main_dev.dart` reassigns this *before* `runApp` to the
  /// OTel-backed implementation. Tests do not need to reassign.
  static Telemetry instance = const NoopTelemetry();

  /// Record an instantaneous event. Events that should pin to a
  /// currently-active long-lived span (e.g. `hf.attach_stream`) are
  /// emitted as a span event when one is open; otherwise as a
  /// stand-alone event in the trace timeline.
  void event(String name, {Map<String, Object?> attrs});

  /// Start a span. The returned [TelemetrySpan] must be ended via
  /// [TelemetrySpan.end] for the span to be exported.
  TelemetrySpan span(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attrs,
  });

  /// Increment a counter by [delta] (default 1).
  void counter(String name, {int delta = 1, Map<String, Object?> attrs});

  /// Record a histogram observation.
  void histogram(String name, num value, {Map<String, Object?> attrs});

  /// Flush any buffered telemetry. Call on app termination if possible
  /// (best-effort).
  Future<void> flush();
}

/// Span semantics. Maps to OTel `SpanKind`.
enum SpanKind { internal, server, client, producer, consumer }

/// A handle to an active span. Subclassed concretely by each backend.
abstract class TelemetrySpan {
  /// Add an attribute to the span.
  void setAttr(String key, Object? value);

  /// Add a discrete event onto this span's timeline.
  void addEvent(String name, {Map<String, Object?> attrs});

  /// Mark the span ended. After `end()` further setAttr/addEvent calls
  /// are silently dropped.
  void end({SpanStatus status = SpanStatus.unset, String? message});
}

enum SpanStatus { unset, ok, error }

/// The default no-op implementation. Always tree-shakeable out of the
/// `stable` AOT snapshot because it imports nothing observability-shaped.
class NoopTelemetry implements Telemetry {
  const NoopTelemetry();

  @override
  void event(String name, {Map<String, Object?> attrs = const {}}) {}

  @override
  TelemetrySpan span(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attrs = const {},
  }) =>
      const _NoopSpan();

  @override
  void counter(String name,
      {int delta = 1, Map<String, Object?> attrs = const {}}) {}

  @override
  void histogram(String name, num value,
      {Map<String, Object?> attrs = const {}}) {}

  @override
  Future<void> flush() async {}
}

class _NoopSpan implements TelemetrySpan {
  const _NoopSpan();

  @override
  void setAttr(String key, Object? value) {}

  @override
  void addEvent(String name, {Map<String, Object?> attrs = const {}}) {}

  @override
  void end({SpanStatus status = SpanStatus.unset, String? message}) {}
}
