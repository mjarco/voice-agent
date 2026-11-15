class Transcript {
  const Transcript({
    required this.id,
    required this.text,
    this.language,
    this.audioDurationMs,
    required this.deviceId,
    required this.createdAt,
    this.subject,
  });

  /// UUIDv4, generated client-side.
  final String id;

  /// Transcript content (user-editable).
  final String text;

  /// ISO 639-1 code, e.g. "pl", "en".
  final String? language;

  /// Original audio length in milliseconds.
  final int? audioDurationMs;

  /// Stable device identifier.
  final String deviceId;

  /// Unix epoch milliseconds.
  final int createdAt;

  /// The subject it was said in, read when it ended (ADR-NET-008): null for
  /// Dzień, `matter:<id>`.
  final String? subject;

  factory Transcript.fromMap(Map<String, dynamic> map) {
    return Transcript(
      id: map['id'] as String,
      text: map['text'] as String,
      language: map['language'] as String?,
      audioDurationMs: map['audio_duration_ms'] as int?,
      deviceId: map['device_id'] as String,
      createdAt: map['created_at'] as int,
      subject: map['subject'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'language': language,
      'audio_duration_ms': audioDurationMs,
      'device_id': deviceId,
      'created_at': createdAt,
      'subject': subject,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transcript &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          language == other.language &&
          audioDurationMs == other.audioDurationMs &&
          deviceId == other.deviceId &&
          createdAt == other.createdAt &&
          subject == other.subject;

  @override
  int get hashCode => Object.hash(
        id,
        text,
        language,
        audioDurationMs,
        deviceId,
        createdAt,
        subject,
      );
}
