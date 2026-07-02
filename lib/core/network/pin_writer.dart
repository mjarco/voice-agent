import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/pin.dart';

/// Port for creating pins (proposal 046).
///
/// Lives in `core/` so `features/chat` can invoke the pin write path through a
/// core provider instead of importing `features/pins` (ADR-ARCH-003). The
/// adapter is `ApiPinWriter` in `features/pins/data/`, bound by an override in
/// the app composition root (`app_main.dart`) — the same core-port /
/// feature-adapter seam as [HandsFreeControlPort] (ADR-ARCH-006, amended P046).
abstract class PinWriter {
  /// Proposes a name + matching existing topic for a message. Writes nothing.
  Future<PinSuggestion> suggestPin(String conversationId, String eventId);

  /// Pins the message identified by [request].
  Future<PinCreateResult> createPin(PinCreateRequest request);
}

/// Default-throws provider (ADR-ARCH-004): the real [PinWriter] is bound by an
/// override on the root `ProviderScope` in `app_main.dart`; tests override it
/// with a fake. Consumers depend only on this `core` provider.
final pinWriterProvider = Provider<PinWriter>((ref) {
  throw UnimplementedError(
    'pinWriterProvider must be overridden in the app composition root',
  );
});
