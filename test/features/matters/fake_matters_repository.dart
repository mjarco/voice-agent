import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';

/// An in-memory [MattersRepository] for the matters tests: it records each
/// call as a line in [calls] and throws [error] from the next write when set.
class FakeMattersRepository implements MattersRepository {
  FakeMattersRepository({
    List<MatterSummary>? matters,
    Map<String, MatterDetail>? details,
  })  : matters = matters ?? [],
        details = details ?? {};

  List<MatterSummary> matters;
  Map<String, MatterDetail> details;
  final calls = <String>[];
  Object? fetchError;
  Object? error;
  int fetches = 0;

  void _check(String call) {
    calls.add(call);
    final e = error;
    if (e != null) {
      error = null;
      throw e;
    }
  }

  @override
  Future<List<MatterSummary>> fetchMatters({
    MatterFilter filter = MatterFilter.current,
  }) async {
    fetches++;
    if (fetchError != null) throw fetchError!;
    return switch (filter) {
      MatterFilter.proposed =>
        matters.where((m) => m.status == MatterStatus.proposed).toList(),
      _ => matters.where((m) => m.status != MatterStatus.proposed).toList(),
    };
  }

  @override
  Future<MatterDetail> fetchMatter(String id) async {
    fetches++;
    if (fetchError != null) throw fetchError!;
    final d = details[id];
    if (d == null) throw MatterNotFoundException();
    return d;
  }

  @override
  Future<MatterDetail> createMatter({
    required String title,
    String keywords = '',
    String nextStep = '',
  }) async {
    _check('create $title|$keywords|$nextStep');
    final m = MatterSummary(
      id: 'new',
      title: title,
      keywords: keywords,
      nextStep: nextStep,
      status: MatterStatus.active,
    );
    matters = [...matters, m];
    return details['new'] = MatterDetail(matter: m);
  }

  @override
  Future<MatterDetail> editMatter(
    String id, {
    String? title,
    String? keywords,
    MatterStatus? status,
    String? nextStep,
    String? waitingFor,
  }) async {
    _check('edit $id title=$title keywords=$keywords status=${status?.name} '
        'next=$nextStep waiting=$waitingFor');
    final old = details[id]!;
    final m = old.matter;
    return details[id] = MatterDetail(
      matter: MatterSummary(
        id: id,
        title: title ?? m.title,
        keywords: keywords ?? m.keywords,
        status: status ?? m.status,
        nextStep: nextStep ?? m.nextStep,
        waitingFor: waitingFor ?? m.waitingFor,
      ),
      timeline: old.timeline,
      links: old.links,
    );
  }

  @override
  Future<void> deleteMatter(String id) async {
    _check('delete $id');
    details.remove(id);
    matters = matters.where((m) => m.id != id).toList();
  }

  @override
  Future<MatterDetail> accept(String id, MatterStatus status) async {
    _check('accept $id ${status.name}');
    matters = [
      for (final m in matters)
        m.id == id ? MatterSummary(id: id, title: m.title, status: status) : m,
    ];
    final old = details[id];
    return details[id] = MatterDetail(
      matter: MatterSummary(
        id: id,
        title: old?.matter.title ?? id,
        status: status,
      ),
      timeline: old?.timeline ?? const [],
      links: old?.links ?? const [],
    );
  }

  @override
  Future<void> drop(String id) async {
    _check('drop $id');
    details.remove(id);
    matters = matters.where((m) => m.id != id).toList();
  }

  @override
  Future<MatterEntry> addEntry(String id, String text) async {
    _check('entry $id $text');
    final entry =
        MatterEntry(id: 'e-new', kind: MatterEntryKind.note, text: text);
    final old = details[id]!;
    details[id] = MatterDetail(
      matter: old.matter,
      timeline: [entry, ...old.timeline],
      links: old.links,
    );
    return entry;
  }

  @override
  Future<void> deleteEntry(String id, String entryId) async {
    _check('delete-entry $id $entryId');
    final old = details[id]!;
    details[id] = MatterDetail(
      matter: old.matter,
      timeline: old.timeline.where((e) => e.id != entryId).toList(),
      links: old.links,
    );
  }

  @override
  Future<void> unlink(String id, String linkId) async {
    _check('unlink $id $linkId');
    final old = details[id]!;
    details[id] = MatterDetail(
      matter: old.matter,
      timeline: old.timeline,
      links: old.links.where((l) => l.id != linkId).toList(),
    );
  }
}
