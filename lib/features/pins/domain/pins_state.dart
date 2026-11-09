import 'package:voice_agent/core/models/pin.dart';

sealed class PinsListState {
  const PinsListState();
}

class PinsListInitial extends PinsListState {
  const PinsListInitial();
}

class PinsListLoading extends PinsListState {
  const PinsListLoading();
}

class PinsListLoaded extends PinsListState {
  const PinsListLoaded({required this.pins});
  final List<PinSummary> pins;
}

class PinsListError extends PinsListState {
  const PinsListError({required this.message});
  final String message;
}

sealed class PinDetailState {
  const PinDetailState();
}

class PinDetailLoading extends PinDetailState {
  const PinDetailLoading();
}

class PinDetailLoaded extends PinDetailState {
  const PinDetailLoaded({required this.pin});
  final PinDetail pin;
}

class PinDetailError extends PinDetailState {
  const PinDetailError({required this.message, this.gone = false});
  final String message;

  /// The server has no such pin: retrying cannot help.
  final bool gone;
}
