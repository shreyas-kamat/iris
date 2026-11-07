/// The study's wire shapes: the work profile and the personal templates the hermes-iris plugin keeps for the person,
/// and the routes that read and change them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/genui/genui_api.dart';
import 'package:iris/data/genui/personal_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';

const _template = {
  'id': 'deploy-status',
  'name': 'Deploy status',
  'when': 'When reporting a deploy',
  'kind': 'display',
  'status': 'proposed',
  'rev': 2,
  'data_schema': {
    'type': 'object',
    'properties': {
      'service': {'type': 'string'},
      'checks': {'type': 'array'},
    },
  },
  'program': 'root = Card([Text(data.service)], "Deploy")',
  'sample_data': {'service': 'api', 'checks': <Object?>[]},
  'created': 1794000000.5,
  'updated': 1794000100.5,
};

void main() {
  late FakeHttp http;

  setUp(() => http = FakeHttp());

  DashboardGenUiApi api({String profile = 'default'}) {
    final connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'S'),
      adapter: http,
    );
    addTearDown(connection.close);
    return DashboardGenUiApi(connection.client, profile: profile);
  }

  group('WorkProfile', () {
    test('reads the plugin\'s record', () {
      final profile = WorkProfile.fromJsonOrNull(
        Json.of({
          'summary': 'Backend engineer',
          'chips': ['APIs', 'On call'],
          'status': 'approved',
          'rev': 3,
          'previous': {
            'summary': 'Before',
            'chips': ['Old'],
          },
        }),
      )!;
      expect(profile.summary, 'Backend engineer');
      expect(profile.chips, ['APIs', 'On call']);
      expect(profile.status, PersonalStatus.approved);
      expect(profile.rev, 3);
      expect(profile.previousSummary, 'Before');
      expect(profile.previousChips, ['Old']);
    });

    test('an unknown status reads as proposed and chips may be missing', () {
      final profile = WorkProfile.fromJsonOrNull(
        Json.of({'summary': 'x', 'status': 'weird'}),
      )!;
      expect(profile.status, PersonalStatus.proposed);
      expect(profile.chips, isEmpty);
      expect(profile.previousSummary, isNull);
    });

    test('a record without a summary is not a profile', () {
      expect(WorkProfile.fromJsonOrNull(Json.of({'chips': <Object?>[]})), isNull);
      expect(WorkProfile.fromJsonOrNull(Json.of(null)), isNull);
    });
  });

  group('UiTemplate', () {
    test('reads the plugin\'s record', () {
      final t = UiTemplate.fromJsonOrNull(Json.of(_template))!;
      expect(t.id, 'deploy-status');
      expect(t.name, 'Deploy status');
      expect(t.when, 'When reporting a deploy');
      expect(t.kind, TemplateKind.display);
      expect(t.status, PersonalStatus.proposed);
      expect(t.rev, 2);
      expect(t.program, startsWith('root = Card('));
      expect(t.sampleData, {'service': 'api', 'checks': <Object?>[]});
      expect(t.dataKeys, ['service', 'checks']);
      expect(t.updated, isNotNull);
    });

    test('a reply kit, and a record from before kinds existed', () {
      expect(
        UiTemplate.fromJsonOrNull(
          Json.of({..._template, 'kind': 'reply_kit'}),
        )!.kind,
        TemplateKind.replyKit,
      );
      final old = {..._template}..remove('kind');
      expect(
        UiTemplate.fromJsonOrNull(Json.of(old))!.kind,
        TemplateKind.display,
      );
    });

    test('a record without an id or a program is skipped', () {
      expect(UiTemplate.fromJsonOrNull(Json.of({'name': 'x'})), isNull);
      final noProgram = {..._template}..remove('program');
      expect(UiTemplate.fromJsonOrNull(Json.of(noProgram)), isNull);
    });

    test('keeps a sample that is not an object as empty', () {
      final t = UiTemplate.fromJsonOrNull(
        Json.of({..._template, 'sample_data': 'nope'}),
      )!;
      expect(t.sampleData, isEmpty);
    });
  });

  group('GenUiApi: the study', () {
    test('reads the profile, and none yet', () async {
      http.on(
        'GET',
        '/api/plugins/iris/profile',
        (_) => FakeReply.json({'ok': true, 'profile': null}),
      );
      expect((await api().workProfile()).valueOrNull, isNull);
      http.on(
        'GET',
        '/api/plugins/iris/profile',
        (_) => FakeReply.json({
          'ok': true,
          'profile': {
            'summary': 'Engineer',
            'chips': ['a'],
            'status': 'proposed',
          },
        }),
      );
      final got = await api().workProfile();
      expect(got, isA<Ok<WorkProfile?>>());
      expect(got.valueOrNull!.summary, 'Engineer');
    });

    test(
      'lists templates, optionally by status, on the named profile',
      () async {
        http.on(
          'GET',
          '/api/plugins/iris/templates',
          (_) => FakeReply.json({
            'ok': true,
            'templates': [
              _template,
              {'name': 'broken'},
            ],
          }),
        );
        final listed = await api(
          profile: 'work',
        ).templates(status: PersonalStatus.proposed);
        expect(listed.valueOrNull!.map((t) => t.id), ['deploy-status']);
        final query = http.requests.single.uri.queryParameters;
        expect(query['profile'], 'work');
        expect(query['status'], 'proposed');
      },
    );

    test('saves a template with only the fields that changed', () async {
      http.on(
        'PUT',
        '/api/plugins/iris/templates/deploy-status',
        (request) => FakeReply.json({
          'ok': true,
          'template': {..._template, 'status': 'approved', 'name': 'Mine'},
        }),
      );
      final saved = await api().saveTemplate(
        'deploy-status',
        name: 'Mine',
        status: PersonalStatus.approved,
      );
      expect(saved.valueOrNull!.status, PersonalStatus.approved);
      expect(saved.valueOrNull!.name, 'Mine');
      final request = http.requests.single;
      expect(request.data, {'name': 'Mine', 'status': 'approved'});
    });

    test('a refused save says why, from the plugin\'s own lines', () async {
      http.on(
        'PUT',
        '/api/plugins/iris/templates/deploy-status',
        (_) => FakeReply.json({
          'ok': false,
          'errors': ['program is required'],
        }, status: 422),
      );
      final saved = await api().saveTemplate('deploy-status', name: 'x');
      expect(saved, isA<Err<UiTemplate>>());
      final failure = (saved as Err<UiTemplate>).failure;
      expect(failure.kind, FailureKind.rejected);
      expect(failure.message, 'program is required');
    });

    test('deletes a template', () async {
      http.on(
        'DELETE',
        '/api/plugins/iris/templates/deploy-status',
        (_) => FakeReply.json({
          'ok': true,
          'id': 'deploy-status',
          'deleted': true,
        }),
      );
      expect((await api().deleteTemplate('deploy-status')).isOk, isTrue);
    });

    test('saves the profile', () async {
      http.on(
        'PUT',
        '/api/plugins/iris/profile',
        (_) => FakeReply.json({
          'ok': true,
          'profile': {
            'summary': 'Mine',
            'chips': ['a'],
            'status': 'approved',
          },
        }),
      );
      final saved = await api().saveWorkProfile(
        summary: 'Mine',
        status: PersonalStatus.approved,
      );
      expect(saved.valueOrNull!.status, PersonalStatus.approved);
      expect(http.requests.single.data, {
        'summary': 'Mine',
        'status': 'approved',
      });
    });
  });
}
