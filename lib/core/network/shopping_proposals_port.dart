import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';

/// Port for shopping proposals (voice-agent#372).
///
/// Chat and Shopping both read and answer proposals, and features do not import
/// each other (ADR-ARCH-003), so this lives in `core/`. The adapter is
/// `ApiShoppingProposals` in `features/shopping/data/`, bound by an override in
/// `app_main.dart`: the seam of [PinWriter] (ADR-ARCH-006).
abstract class ShoppingProposalsPort {
  /// The proposals of [conversationId] in any state, oldest first; without it,
  /// all the waiting ones. Throws [ShoppingProposalsException] on failure.
  Future<List<ShoppingProposal>> list({String? conversationId});

  /// Never throws: a failure is a [ProposalAnswerFailed].
  Future<ShoppingProposalAnswer> accept(String id);

  /// Never throws: a failure is a [ProposalAnswerFailed].
  Future<ShoppingProposalAnswer> skip(String id);
}

class ShoppingProposalsException implements Exception {
  ShoppingProposalsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Default-throws provider (ADR-ARCH-004): bound on the root `ProviderScope` in
/// `app_main.dart`; tests override it with a fake.
final shoppingProposalsPortProvider = Provider<ShoppingProposalsPort>((ref) {
  throw UnimplementedError(
    'shoppingProposalsPortProvider must be overridden in the app composition '
    'root',
  );
});
