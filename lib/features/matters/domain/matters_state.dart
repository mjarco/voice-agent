import 'package:voice_agent/core/models/matter.dart';

sealed class MattersListState {
  const MattersListState();
}

class MattersListLoading extends MattersListState {
  const MattersListLoading();
}

class MattersListLoaded extends MattersListState {
  const MattersListLoaded({required this.proposed, required this.matters});

  /// Matters the review proposed, awaiting the owner's yes or no.
  final List<MatterSummary> proposed;

  /// Every other matter, in the server's order.
  final List<MatterSummary> matters;
}

class MattersListError extends MattersListState {
  const MattersListError({required this.message});
  final String message;
}

sealed class MatterDetailState {
  const MatterDetailState();
}

class MatterDetailLoading extends MatterDetailState {
  const MatterDetailLoading();
}

class MatterDetailLoaded extends MatterDetailState {
  const MatterDetailLoaded({required this.detail});
  final MatterDetail detail;
}

class MatterDetailError extends MatterDetailState {
  const MatterDetailError({required this.message, this.gone = false});
  final String message;

  /// The server has no such matter: retrying cannot help.
  final bool gone;
}
