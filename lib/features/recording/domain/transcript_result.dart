class TranscriptResult {
  const TranscriptResult({
    required this.text,
    required this.segments,
    required this.detectedLanguage,
    required this.audioDurationMs,
  });

  final String text;
  final List<TranscriptSegment> segments;
  final String detectedLanguage;
  final int audioDurationMs;
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String text;
  final int startMs;
  final int endMs;
}
