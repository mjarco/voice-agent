class RecordingResult {
  const RecordingResult({
    required this.filePath,
    required this.duration,
    required this.sampleRate,
  });

  final String filePath;
  final Duration duration;
  final int sampleRate;
}
