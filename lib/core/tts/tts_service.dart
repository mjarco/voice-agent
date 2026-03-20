abstract class TtsService {
  Future<void> speak(String text, {String? languageCode});
  Future<void> stop();
  void dispose();
}
