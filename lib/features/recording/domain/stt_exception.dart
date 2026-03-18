class SttException implements Exception {
  const SttException(this.message);

  final String message;

  @override
  String toString() => 'SttException: $message';
}
