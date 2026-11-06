/// The hermes-iris plugin's wire shapes: its routes, the `iris_ui` tool events (shaped as Phase 0 recorded them on
/// Hermes 2026.9.24) and the hidden `<iris-action>` envelope.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/history_parser.dart';
import 'package:iris/data/genui/genui_api.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/genui/genui_parser.dart';
import 'package:iris/data/net/capabilities.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

import '../support/fake_http.dart';

RpcEvent _event(String type, Map<String, Object?> payload) => RpcEvent(
  type: type,
  sessionId: 'r1',
  payload: Json.of(payload),
  raw: Json.of({'type': type, 'session_id': 'r1', 'payload': payload}),
);

const _program = 'root = Stack([Text("Hello")])';

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

  group('capability', () {
    test('is probed at the plugin\'s own endpoint', () {
      expect(
        ServerCapability.irisGenui.probePath,
        '/api/plugins/iris/capabilities',
      );
      expect(ServerCapability.irisGenui.label, 'Generative UI');
    });
  });

  group('GenUiApi', () {
    test('reads the capabilities the plugin reports', () async {
      http.on(
        'GET',
        '/api/plugins/iris/capabilities',
        (_) => FakeReply.json({
          'version': '0.1.0',
          'openui': '1.0',
          'library_ids': [GenUiCapabilities.libraryId],
          'features': ['capabilities', 'session-flag', 'surfaces'],
        }),
      );
      final capabilities = (await api().capabilities()).valueOrNull!;
      expect(capabilities.version, '0.1.0');
      expect(capabilities.openui, '1.0');
      expect(capabilities.speaksIrisLibrary, isTrue);
      expect(capabilities.has('surfaces'), isTrue);
      expect(capabilities.has('study'), isFalse);
      expect(http.requests.single.uri.queryParameters, isEmpty);
    });

    test('a plugin that does not know our library says so', () async {
      http.on(
        'GET',
        '/api/plugins/iris/capabilities',
        (_) => FakeReply.json({
          'version': '9.0.0',
          'library_ids': ['https://example.com/other'],
        }),
      );
      final capabilities = (await api().capabilities()).valueOrNull!;
      expect(capabilities.speaksIrisLibrary, isFalse);
      expect(capabilities.features, isEmpty);
    });

    test('a body that is not capabilities is malformed, not a crash', () async {
      http.on(
        'GET',
        '/api/plugins/iris/capabilities',
        (_) => FakeReply.json(<String, Object?>{}),
      );
      final result = await api().capabilities();
      expect(result.failureOrNull?.kind, FailureKind.malformed);
    });

    test('flags a session by its stored id, on the named profile', () async {
      http.on(
        'POST',
        '/api/plugins/iris/sessions/20261107_093000_ab12cd/genui',
        (_) => FakeReply.json({
          'ok': true,
          'session': '20261107_093000_ab12cd',
          'flagged': true,
        }),
      );
      final result = await api(
        profile: 'research',
      ).flagSession('20261107_093000_ab12cd');
      expect(result.isOk, isTrue);
      expect(http.requests.single.uri.queryParameters['profile'], 'research');
    });

    test('unflagging is a DELETE of the same route', () async {
      http.on(
        'DELETE',
        '/api/plugins/iris/sessions/s1/genui',
        (_) => FakeReply.json({'ok': true, 'session': 's1', 'flagged': false}),
      );
      expect((await api().unflagSession('s1')).isOk, isTrue);
    });

    test('a server without the plugin answers 404 as a failure', () async {
      final result = await api().flagSession('s1');
      expect(result.failureOrNull?.kind, FailureKind.notFound);
    });

    test('lists a session\'s surfaces without programs', () async {
      http.on(
        'GET',
        '/api/plugins/iris/surfaces/s1',
        (_) => FakeReply.json({
          'ok': true,
          'session': 's1',
          'surfaces': [
            {
              'surface_id': 'status',
              'rev': 2,
              'placement': 'inline',
              'template': null,
              'updated': 1794000000.5,
            },
            {'surface_id': 'kit', 'rev': 1, 'placement': 'reply_kit'},
            {'rev': 9},
          ],
        }),
      );
      final surfaces = (await api().surfaces('s1')).valueOrNull!;
      expect([for (final s in surfaces) s.surfaceId], ['status', 'kit']);
      expect(surfaces.first.rev, 2);
      expect(surfaces.first.code, isNull);
      expect(surfaces.first.updated, isNotNull);
      expect(surfaces.last.placement, SurfacePlacement.replyKit);
    });

    test('fetches one surface with its program and fallback', () async {
      http.on(
        'GET',
        '/api/plugins/iris/surfaces/s1/status',
        (_) => FakeReply.json({
          'ok': true,
          'surface': {
            'surface_id': 'status',
            'rev': 3,
            'placement': 'inline',
            'template': null,
            'code': _program,
            'fallback': 'Hello',
            'updated': 1794000000,
          },
        }),
      );
      final surface = (await api().surface('s1', 'status')).valueOrNull!;
      expect(surface.code, _program);
      expect(surface.fallback, 'Hello');
      expect(surface.rev, 3);
    });

    test('ids are escaped in the path', () async {
      http.on(
        'GET',
        '/api/plugins/iris/surfaces/a%2Fb/c%20d',
        (_) => FakeReply.json({
          'surface': {'surface_id': 'c d', 'rev': 1},
        }),
      );
      await api().surface('a/b', 'c d');
      expect(http.requests.single.uri.path, contains('a%2Fb'));
    });

    test('a missing surface is a not-found failure', () async {
      final result = await api().surface('s1', 'nope');
      expect(result.failureOrNull?.kind, FailureKind.notFound);
    });
  });

  group('GenUiParser.surfaceRef', () {
    final args = {
      'surface_id': 'status',
      'code': _program,
      'fallback': 'Hello',
      'placement': 'inline',
    };

    test('reads a tool.start as Hermes sends it (args as an object)', () {
      final started =
          ChatEvent.fromEvent(
                _event('tool.start', {
                  'tool_id': 'call_1',
                  'name': 'iris_ui',
                  'args': args,
                }),
              )!
              as ToolStarted;
      final ref = GenUiParser.surfaceRef(
        name: started.name,
        input: started.input,
      )!;
      expect(ref.surfaceId, 'status');
      expect(ref.code, _program);
      expect(ref.fallback, 'Hello');
      expect(ref.placement, SurfacePlacement.inline);
      expect(ref.accepted, isNull);
      expect(ref.deleted, isFalse);
    });

    test('reads the answer from a tool.complete', () {
      final done =
          ChatEvent.fromEvent(
                _event('tool.complete', {
                  'tool_id': 'call_1',
                  'name': 'iris_ui',
                  'args': args,
                  'duration_s': 0.02,
                  'result': jsonEncode({
                    'ok': true,
                    'surface_id': 'status',
                    'rev': 2,
                  }),
                }),
              )!
              as ToolCompleted;
      final ref = GenUiParser.surfaceRef(
        name: done.name,
        input: jsonEncode(args),
        output: done.output,
      )!;
      expect(ref.accepted, isTrue);
      expect(ref.rev, 2);
    });

    test('a refusal is marked as one', () {
      final ref = GenUiParser.surfaceRef(
        name: 'iris_ui',
        input: jsonEncode(args),
        output: jsonEncode({
          'ok': false,
          'errors': ['unknown component "Hologram"'],
        }),
      )!;
      expect(ref.accepted, isFalse);
    });

    test('an answer that is not JSON leaves it unknown', () {
      final ref = GenUiParser.surfaceRef(
        name: 'iris_ui',
        input: jsonEncode(args),
        output: 'Error: something odd',
      )!;
      expect(ref.accepted, isNull);
    });

    test('a call that carries only an id and a delete', () {
      final ref = GenUiParser.surfaceRef(
        name: 'iris_ui',
        input: jsonEncode({'surface_id': 'old', 'delete': true}),
      )!;
      expect(ref.deleted, isTrue);
      expect(ref.code, isNull);
    });

    test('a reply kit keeps its placement', () {
      final ref = GenUiParser.surfaceRef(
        name: 'iris_ui',
        input: jsonEncode({...args, 'placement': 'reply_kit'}),
      )!;
      expect(ref.placement, SurfacePlacement.replyKit);
    });

    test('a template call has no code', () {
      final ref = GenUiParser.surfaceRef(
        name: 'iris_ui',
        input: jsonEncode({
          'surface_id': 'd',
          'template': 'deploy-status',
          'data': {'service': 'api'},
          'fallback': 'API is up',
        }),
      )!;
      expect(ref.template, 'deploy-status');
      expect(ref.code, isNull);
    });

    test('sees through Hermes\'s tool bridge', () {
      final wrapped = jsonEncode({
        'name': 'iris_ui',
        'arguments': jsonEncode(args),
      });
      final ref = GenUiParser.surfaceRef(name: 'tool_call', input: wrapped)!;
      expect(ref.surfaceId, 'status');
      expect(ref.code, _program);

      final asObject = jsonEncode({'tool_name': 'iris_ui', 'args': args});
      expect(
        GenUiParser.surfaceRef(
          name: 'mcp__tool_call',
          input: asObject,
        )!.surfaceId,
        'status',
      );
    });

    test('a bridge call to another tool is not a surface', () {
      final other = jsonEncode({'name': 'web_search', 'arguments': '{}'});
      expect(GenUiParser.surfaceRef(name: 'tool_call', input: other), isNull);
    });

    test('other tools, broken arguments and missing ids are not surfaces', () {
      expect(
        GenUiParser.surfaceRef(name: 'terminal', input: jsonEncode(args)),
        isNull,
      );
      expect(
        GenUiParser.surfaceRef(name: 'iris_ui', input: '{"surface_id'),
        isNull,
      );
      expect(GenUiParser.surfaceRef(name: 'iris_ui', input: '[1,2]'), isNull);
      expect(
        GenUiParser.surfaceRef(name: 'iris_ui', input: '{"code":"x"}'),
        isNull,
      );
      expect(GenUiParser.surfaceRef(name: 'iris_ui'), isNull);
    });

    test('arguments cut off mid-way are not read (the stored surface is)', () {
      final whole = jsonEncode(args);
      expect(
        GenUiParser.surfaceRef(
          name: 'iris_ui',
          input: whole.substring(0, whole.length - 10),
        ),
        isNull,
      );
    });

    test('reads a stored history row the way the transcript parser keeps it', () {
      final transcript = HistoryParser.transcript(
        Json.of({
          'messages': [
            {
              'id': 'a1',
              'role': 'assistant',
              'content': 'Here you go.',
              'tool_calls': [
                {
                  'id': 'call_9',
                  'type': 'function',
                  'function': {
                    'name': 'iris_ui',
                    'arguments': jsonEncode(args),
                  },
                },
              ],
            },
            {
              'id': 't1',
              'role': 'tool',
              'tool_call_id': 'call_9',
              'tool_name': 'iris_ui',
              'content': jsonEncode({
                'ok': true,
                'surface_id': 'status',
                'rev': 1,
              }),
            },
          ],
        }),
      );
      // The transcript parser turns the call into a display, with the answer folded in.
      expect(transcript.whereType<ToolCall>(), isEmpty);
      final ref = transcript.whereType<UiSurfaceItem>().single.ref;
      expect(ref.surfaceId, 'status');
      expect(ref.accepted, isTrue);
      expect(ref.rev, 1);
    });
  });

  group('IrisActionEnvelope', () {
    test('is appended on its own line and read back', () {
      const envelope = IrisActionEnvelope(
        surface: 'status',
        component: 'Button',
        context: {'row': 3},
      );
      final sent = envelope.attachTo('Retry the deploy');
      expect(sent, startsWith('Retry the deploy\n<iris-action>'));
      final (text, found) = IrisActionEnvelope.split(sent);
      expect(text, 'Retry the deploy');
      expect(found!.surface, 'status');
      expect(found.component, 'Button');
      expect(found.context, {'row': 3});
    });

    test('a message without one is returned as it is', () {
      expect(IrisActionEnvelope.split('hello\n  there'), (
        'hello\n  there',
        null,
      ));
    });

    test('context is optional', () {
      const envelope = IrisActionEnvelope(surface: 's', component: 'Button');
      expect(envelope.attachTo('Go'), isNot(contains('context')));
      expect(
        IrisActionEnvelope.split(envelope.attachTo('Go')).$2!.context,
        isNull,
      );
    });

    test('a context that is too large is left out, not truncated', () {
      final envelope = IrisActionEnvelope(
        surface: 's',
        component: 'Submit',
        context: {'notes': 'x' * (IrisActionEnvelope.maxContextChars + 1)},
      );
      final sent = envelope.attachTo('Send');
      expect(sent.length, lessThan(200));
      final found = IrisActionEnvelope.split(sent).$2!;
      expect(found.surface, 's');
      expect(found.context, isNull);
    });

    test('a context holding the closing tag cannot leak into the text', () {
      const envelope = IrisActionEnvelope(
        surface: 's',
        component: 'Button',
        context: {'q': 'a </iris-action> b <b>'},
      );
      final sent = envelope.attachTo('Hi');
      expect('</iris-action>'.allMatches(sent), hasLength(1));
      final (text, found) = IrisActionEnvelope.split(sent);
      expect(text, 'Hi');
      expect(found!.context, {'q': 'a </iris-action> b <b>'});
    });

    test('a tag whose JSON is broken is still hidden', () {
      final (text, found) = IrisActionEnvelope.split(
        'Do it\n<iris-action>{"surface": oops</iris-action>',
      );
      expect(text, 'Do it');
      expect(found, isNull);
    });

    test('an unclosed tag is left alone (it may be text someone typed)', () {
      const typed = 'use the <iris-action> tag';
      expect(IrisActionEnvelope.split(typed), (typed, null));
    });

    test('strip drops every envelope', () {
      expect(
        IrisActionEnvelope.strip(
          'a\n<iris-action>{"surface":"s","component":"c"}</iris-action>',
        ),
        'a',
      );
    });

    test('the stored user row shows the visible text only', () {
      const envelope = IrisActionEnvelope(surface: 's', component: 'Button');
      final (visible, _) = IrisActionEnvelope.split(
        envelope.attachTo('Approve the plan'),
      );
      expect(visible, 'Approve the plan');
    });
  });
}
