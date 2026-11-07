/// A scripted [GenUiApi] for the study and Displays screens: the profile and templates the plugin "holds", with every
/// change recorded.
library;

import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/genui/genui_api.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/genui/personal_models.dart';

class FakeGenUiApi implements GenUiApi {
  WorkProfile? profile;
  List<UiTemplate> stored = [];

  /// Every call, as `name:argument`, in order.
  final calls = <String>[];

  /// Set to make the next save fail with this line.
  String? refuse;

  @override
  Future<Result<WorkProfile?>> workProfile() async {
    calls.add('workProfile');
    return Ok(profile);
  }

  @override
  Future<Result<WorkProfile>> saveWorkProfile({
    String? summary,
    List<String>? chips,
    PersonalStatus? status,
  }) async {
    calls.add('saveWorkProfile:${status?.wire ?? summary ?? ''}');
    final old = profile;
    if (old == null && summary == null) {
      return const Err(IrisFailure(FailureKind.rejected));
    }
    return Ok(
      profile = WorkProfile(
        summary: summary ?? old!.summary,
        chips: chips ?? old?.chips ?? const [],
        status: status ?? old?.status ?? PersonalStatus.proposed,
        rev: (old?.rev ?? 0) + 1,
      ),
    );
  }

  @override
  Future<Result<List<UiTemplate>>> templates({PersonalStatus? status}) async {
    calls.add('templates:${status?.wire ?? 'all'}');
    return Ok([
      for (final t in stored)
        if (status == null || t.status == status) t,
    ]);
  }

  @override
  Future<Result<UiTemplate>> saveTemplate(
    String id, {
    String? name,
    String? when,
    PersonalStatus? status,
    TemplateKind? kind,
  }) async {
    calls.add('saveTemplate:$id:${status?.wire ?? name ?? ''}');
    final refused = refuse;
    if (refused != null) {
      refuse = null;
      return Err(IrisFailure(FailureKind.rejected, message: refused));
    }
    final index = stored.indexWhere((t) => t.id == id);
    if (index < 0) return const Err(IrisFailure(FailureKind.notFound));
    final t = stored[index];
    return Ok(
      stored[index] = UiTemplate(
        id: t.id,
        name: name ?? t.name,
        when: when ?? t.when,
        kind: kind ?? t.kind,
        status: status ?? t.status,
        rev: t.rev + 1,
        program: t.program,
        dataSchema: t.dataSchema,
        sampleData: t.sampleData,
      ),
    );
  }

  @override
  Future<Result<void>> deleteTemplate(String id) async {
    calls.add('deleteTemplate:$id');
    stored.removeWhere((t) => t.id == id);
    return const Ok(null);
  }

  // The rest of the plugin's routes are not part of the study.
  @override
  Future<Result<GenUiCapabilities>> capabilities() =>
      throw UnimplementedError();

  @override
  Future<Result<void>> flagSession(String sessionId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> unflagSession(String sessionId) =>
      throw UnimplementedError();

  @override
  Future<Result<List<UiSurface>>> surfaces(String sessionId) =>
      throw UnimplementedError();

  @override
  Future<Result<UiSurface>> surface(String sessionId, String surfaceId) =>
      throw UnimplementedError();
}

/// A template with plausible fields, for tests.
UiTemplate sampleTemplate(
  String id, {
  String name = 'Deploy status',
  TemplateKind kind = TemplateKind.display,
  PersonalStatus status = PersonalStatus.proposed,
  String program = 'root = Card([Text(data.service)], "Deploy")',
  Map<String, Object?> sample = const {'service': 'api'},
}) => UiTemplate(
  id: id,
  name: name,
  when: 'When reporting a deploy',
  kind: kind,
  status: status,
  rev: 1,
  program: program,
  dataSchema: const {
    'type': 'object',
    'properties': {
      'service': {'type': 'string'},
    },
  },
  sampleData: sample,
);
