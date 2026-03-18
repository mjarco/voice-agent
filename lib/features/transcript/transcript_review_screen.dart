import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/recording/domain/transcript_result.dart';
import 'package:voice_agent/features/transcript/widgets/metadata_row.dart';

class TranscriptReviewScreen extends ConsumerStatefulWidget {
  const TranscriptReviewScreen({
    super.key,
    required this.transcriptResult,
  });

  final TranscriptResult transcriptResult;

  @override
  ConsumerState<TranscriptReviewScreen> createState() =>
      _TranscriptReviewScreenState();
}

class _TranscriptReviewScreenState
    extends ConsumerState<TranscriptReviewScreen> {
  late final TextEditingController _textController;
  bool _isEdited = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _textController =
        TextEditingController(text: widget.transcriptResult.text);
    _textController.addListener(() {
      if (!_isEdited) {
        setState(() => _isEdited = true);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final storage = ref.read(storageServiceProvider);
      final deviceId = await storage.getDeviceId();
      final now = DateTime.now().millisecondsSinceEpoch;

      final transcript = Transcript(
        id: const Uuid().v4(),
        text: _textController.text,
        language: widget.transcriptResult.detectedLanguage,
        audioDurationMs: widget.transcriptResult.audioDurationMs,
        deviceId: deviceId,
        createdAt: now,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue(transcript.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transcript saved')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _discard() async {
    if (_isEdited) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content:
              const Text('You have edited the transcript. Discard changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (mounted) context.pop();
  }

  void _reRecord() {
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review Transcript')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _textController,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Transcript text...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  MetadataRow(
                    language: widget.transcriptResult.detectedLanguage,
                    durationMs: widget.transcriptResult.audioDurationMs,
                    timestamp: DateTime.now(),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _reRecord,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Re-record'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _isSubmitting ? null : _discard,
                    icon: const Icon(Icons.close),
                    label: const Text('Discard'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : _approve,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
