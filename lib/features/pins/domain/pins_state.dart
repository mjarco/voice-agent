import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';

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
  const PinsListLoaded({required this.pins, required this.view});
  final List<PinSummary> pins;
  final PinView view;
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
  const PinDetailError({required this.message});
  final String message;
}
