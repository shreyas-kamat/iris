/// Generated displays in the transcript (plan 3.5): stored history, live tool events, the block widget, and a whole
/// screen against the scripted backend.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/history_parser.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/features/chat/chat_export.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/chat/chat_state.dart';
import 'package:iris/features/genui/render/node_widgets.dart';
import 'package:iris/features/genui/render/open_ui_view.dart';
import 'package:iris/features/genui/surface_block.dart';

import '../support/fake_chat_backend.dart';
import '../support/harness.dart';

const _program =
    'root = Stack([Text("Deploy status", "title"), Text("All good")])';

String _args({
  String id = 'status',
  String code = _program,
  String fallback = 'Deploy status: all good',
  String placement = 'inline',
  bool delete = false,
}) => jsonEncode(
  delete
      ? {'surface_id': id, 'delete': true}
      : {
          'surface_id': id,
          'code': code,
          'fallback': fallback,
          'placement': placement,
        },
);

String _ok(String id, int rev) =>
    jsonEncode({'ok': true, 'surface_id': id, 'rev': rev});

Map<String, Object?> _assistantCall(
  String rowId,
  String callId, {
  String name = 'iris_ui',
  String? arguments,
  String content = '',
}) => {
  'id': rowId,
  'role': 'assistant',
  'content': content,
  'tool_calls': [
    {
      'id': callId,
      'type': 'function',
      'function': {'name': name, 'arguments': arguments ?? _args()},
    },
  ],
};

Map<String, Object?> _toolRow(String rowId, String callId, String content) => {
  'id': rowId,
  'role': 'tool',
  'tool_call_id': callId,
  'tool_name': 'iris_ui',
  'content': content,
};

List<TranscriptItem> _parse(List<Map<String, Object?>> rows) =>
    HistoryParser.transcript(Json.of({'messages': rows}));

void main() {
  group('stored history', () {
    test('an accepted iris_ui call is a display, not a tool card', () {
      final items = _parse([
        {'id': 'u1', 'role': 'user', 'content': 'How is the deploy?'},
        _assistantCall('a1', 'c1', content: 'Here you go.'),
        _toolRow('t1', 'c1', _ok('status', 1)),
      ]);
      expect(items.whereType<ToolCall>(), isEmpty);
      final surface = items.whereType<UiSurfaceItem>().single;
      expect(surface.ref.surfaceId, 'status');
      expect(surface.ref.code, _program);
      expect(surface.ref.accepted, isTrue);
      expect(surface.ref.rev, 1);
      // The reply text stays, before the display.
      expect(items.map((i) => i.runtimeType), [
        UserTurn,
        AssistantTurn,
        UiSurfaceItem,
      ]);
    });

    test('a refused call shows as a failed tool card', () {
      final items = _parse([
        _assistantCall('a1', 'c1'),
        _toolRow(
          't1',
          'c1',
          jsonEncode({
            'ok': false,
            'errors': ['unknown component "Hologram"'],
          }),
        ),
      ]);
      expect(items.whereType<UiSurfaceItem>(), isEmpty);
      final call = items.whereType<ToolCall>().single;
      expect(call.status, ToolStatus.failed);
      expect(call.output, contains('Hologram'));
    });

    test('a call whose answer cannot be read is still drawn', () {
      final items = _parse([
        _assistantCall('a1', 'c1'),
        _toolRow('t1', 'c1', 'something odd'),
      ]);
      expect(items.whereType<UiSurfaceItem>(), hasLength(1));
      expect(items.whereType<ToolCall>(), isEmpty);
    });

    test('a later mention of the same display replaces the earlier', () {
      final items = _parse([
        _assistantCall('a1', 'c1'),
        _toolRow('t1', 'c1', _ok('status', 1)),
        _assistantCall(
          'a2',
          'c2',
          arguments: _args(code: 'root = Text("Rolled back")'),
        ),
        _toolRow('t2', 'c2', _ok('status', 2)),
      ]);
      final surface = items.whereType<UiSurfaceItem>().single;
      expect(surface.ref.code, 'root = Text("Rolled back")');
      expect(surface.ref.rev, 2);
      expect(items.whereType<ToolCall>(), isEmpty);
    });

    test('different displays side by side stay', () {
      final items = _parse([
        _assistantCall('a1', 'c1', arguments: _args()),
        _assistantCall('a2', 'c2', arguments: _args(id: 'other')),
      ]);
      expect(items.whereType<UiSurfaceItem>(), hasLength(2));
    });

    test('a delete removes the display and leaves no card behind', () {
      final items = _parse([
        _assistantCall('a1', 'c1'),
        _toolRow('t1', 'c1', _ok('status', 1)),
        _assistantCall('a2', 'c2', arguments: _args(delete: true)),
        _toolRow(
          't2',
          'c2',
          jsonEncode({'ok': true, 'surface_id': 'status', 'deleted': true}),
        ),
      ]);
      expect(items.whereType<UiSurfaceItem>(), isEmpty);
      expect(items.whereType<ToolCall>(), isEmpty);
    });

    test('the answer to a replaced display leaves no stray card', () {
      final items = _parse([
        _assistantCall('a1', 'c1'),
        _assistantCall('a2', 'c2', arguments: _args(code: 'root = Text("v2")')),
        _toolRow('t1', 'c1', _ok('status', 1)),
        _toolRow('t2', 'c2', _ok('status', 2)),
      ]);
      expect(items.whereType<ToolCall>(), isEmpty);
      expect(items.whereType<UiSurfaceItem>(), hasLength(1));
    });

    test('Hermes\'s tool bridge is seen through', () {
      final items = _parse([
        _assistantCall(
          'a1',
          'c1',
          name: 'tool_call',
          arguments: jsonEncode({'name': 'iris_ui', 'arguments': _args()}),
        ),
      ]);
      expect(items.whereType<UiSurfaceItem>().single.ref.code, _program);
    });

    test('the calls-list bridge shape a real server stores is drawn', () {
      final items = _parse([
        _assistantCall(
          'a1',
          'c1',
          name: 'tool_call',
          arguments: jsonEncode({
            'calls': [
              {'name': 'iris_ui', 'arguments': _args()},
            ],
          }),
        ),
        _toolRow('t1', 'c1', _ok('status', 1)),
      ]);
      expect(items.whereType<ToolCall>(), isEmpty);
      expect(items.whereType<UiSurfaceItem>().single.ref.code, _program);
    });

    test('other tools are untouched', () {
      final items = _parse([
        _assistantCall('a1', 'c1', name: 'terminal', arguments: '{"cmd":"ls"}'),
        {
          'id': 't1',
          'role': 'tool',
          'tool_call_id': 'c1',
          'tool_name': 'terminal',
          'content': 'a\nb',
        },
      ]);
      final call = items.single as ToolCall;
      expect(call.name, 'terminal');
      expect(call.output, 'a\nb');
    });

    test('a template call keeps its template and has no code', () {
      final items = _parse([
        _assistantCall(
          'a1',
          'c1',
          arguments: jsonEncode({
            'surface_id': 'd',
            'template': 'deploy-status',
            'data': {'service': 'api'},
            'fallback': 'API is up',
          }),
        ),
      ]);
      final ref = items.whereType<UiSurfaceItem>().single.ref;
      expect(ref.template, 'deploy-status');
      expect(ref.code, isNull);
    });

    test('the hidden action envelope never shows in a user turn', () {
      final items = _parse([
        {
          'id': 'u1',
          'role': 'user',
          'content':
              'Retry the deploy\n<iris-action>{"surface":"status","component":"Button"}</iris-action>',
        },
      ]);
      expect((items.single as UserTurn).text, 'Retry the deploy');
    });
  });

  group('live events', () {
    const ready = ChatState(phase: ChatPhase.ready);

    ChatState started({String id = 'status', String? input}) => ready
        .apply(const MessageStarted('r'))
        .apply(const TextDelta('r', 'Here you go.'))
        .apply(
          ToolStarted(
            'r',
            toolId: 'call-$id',
            name: 'iris_ui',
            input: input ?? _args(id: id),
          ),
        );

    test('a started call is a display at once, after the reply text', () {
      final state = started();
      expect(state.items.map((i) => i.runtimeType), [
        AssistantTurn,
        UiSurfaceItem,
      ]);
      expect(state.turn, TurnPhase.working);
      expect((state.items.first as AssistantTurn).streaming, isFalse);
    });

    test('an accepted answer keeps it and records the revision', () {
      final state = started().apply(
        ToolCompleted(
          'r',
          toolId: 'call-status',
          name: 'iris_ui',
          output: _ok('status', 3),
        ),
      );
      final surface = state.items.whereType<UiSurfaceItem>().single;
      expect(surface.ref.accepted, isTrue);
      expect(surface.ref.rev, 3);
      expect(state.items.whereType<ToolCall>(), isEmpty);
    });

    test('a refusal swaps it for a failed card', () {
      final state = started().apply(
        ToolCompleted(
          'r',
          toolId: 'call-status',
          name: 'iris_ui',
          output: jsonEncode({
            'ok': false,
            'errors': ['root is missing'],
          }),
        ),
      );
      expect(state.items.whereType<UiSurfaceItem>(), isEmpty);
      final call = state.items.whereType<ToolCall>().single;
      expect(call.status, ToolStatus.failed);
      expect(call.output, contains('root is missing'));
    });

    test('a failed event swaps it too', () {
      final state = started().apply(
        const ToolCompleted(
          'r',
          toolId: 'call-status',
          name: 'iris_ui',
          output: 'boom',
          failed: true,
        ),
      );
      expect(state.items.whereType<UiSurfaceItem>(), isEmpty);
      expect(
        state.items.whereType<ToolCall>().single.status,
        ToolStatus.failed,
      );
    });

    test('an answer that cannot be read leaves the display', () {
      final state = started().apply(
        const ToolCompleted(
          'r',
          toolId: 'call-status',
          name: 'iris_ui',
          output: 'weird',
        ),
      );
      expect(state.items.whereType<UiSurfaceItem>(), hasLength(1));
      expect(state.items.whereType<ToolCall>(), isEmpty);
    });

    test('reusing the id updates the display in place of a second one', () {
      final state = started().apply(
        ToolStarted(
          'r',
          toolId: 'call-2',
          name: 'iris_ui',
          input: _args(code: 'root = Text("v2")'),
        ),
      );
      final surface = state.items.whereType<UiSurfaceItem>().single;
      expect(surface.ref.code, 'root = Text("v2")');
    });

    test('a delete removes it, and its answer adds no card', () {
      final state = started()
          .apply(
            ToolStarted(
              'r',
              toolId: 'call-del',
              name: 'iris_ui',
              input: _args(delete: true),
            ),
          )
          .apply(
            ToolCompleted(
              'r',
              toolId: 'call-del',
              name: 'iris_ui',
              output: jsonEncode({'ok': true, 'surface_id': 'status'}),
            ),
          );
      expect(state.items.whereType<UiSurfaceItem>(), isEmpty);
      expect(state.items.whereType<ToolCall>(), isEmpty);
    });

    test('other tools still make a running card', () {
      final state = ready.apply(
        const ToolStarted('r', toolId: 't', name: 'terminal', input: 'ls'),
      );
      expect((state.items.single as ToolCall).status, ToolStatus.running);
    });

    test('arguments cut short fall back to an ordinary tool card', () {
      final cut = _args().substring(0, 40);
      final state = ready.apply(
        ToolStarted('r', toolId: 't', name: 'iris_ui', input: cut),
      );
      expect(state.items.single, isA<ToolCall>());
    });

    test(
      'a bridged call to another tool finishes its card on an ok answer',
      () {
        final bridged = jsonEncode({
          'calls': [
            {
              'name': 'web_search',
              'arguments': {'q': 'x'},
            },
          ],
        });
        final state = ready
            .apply(
              ToolStarted('r', toolId: 'b1', name: 'tool_call', input: bridged),
            )
            .apply(
              ToolCompleted(
                'r',
                toolId: 'b1',
                name: 'tool_call',
                output: jsonEncode({'ok': true, 'results': <Object?>[]}),
              ),
            );
        expect((state.items.single as ToolCall).status, ToolStatus.done);
      },
    );

    test('a cut-short display call finishes its card on an ok answer', () {
      final cut = _args().substring(0, 40);
      final state = ready
          .apply(ToolStarted('r', toolId: 't', name: 'iris_ui', input: cut))
          .apply(
            ToolCompleted(
              'r',
              toolId: 't',
              name: 'iris_ui',
              output: _ok('status', 1),
            ),
          );
      expect((state.items.single as ToolCall).status, ToolStatus.done);
    });
  });

  group('export', () {
    test('a display exports as its Markdown fallback', () {
      final items = _parse([
        {'id': 'u1', 'role': 'user', 'content': 'Status?'},
        _assistantCall('a1', 'c1'),
      ]);
      final markdown = transcriptMarkdown('Deploys', items);
      expect(markdown, contains('Deploy status: all good'));
      expect(markdown, isNot(contains('root =')));
    });
  });

  group('SurfaceBlock', () {
    Widget host(Widget child) =>
        themed(Material(child: SingleChildScrollView(child: child)));

    UiSurfaceItem item({
      String? code = _program,
      String? template,
      String? fallback = 'Deploy status: all good',
      SurfacePlacement placement = SurfacePlacement.inline,
    }) => UiSurfaceItem(
      id: 'c1',
      ref: UiSurfaceRef(
        surfaceId: 'status',
        code: code,
        template: template,
        fallback: fallback,
        placement: placement,
      ),
    );

    testWidgets('draws the program the call carried, without fetching', (
      tester,
    ) async {
      var fetched = 0;
      await tester.pumpWidget(
        host(
          SurfaceBlock(
            item(),
            loadSurface: (_) async {
              fetched++;
              return null;
            },
          ),
        ),
      );
      expect(find.text('Deploy status'), findsOneWidget);
      expect(find.text('All good'), findsOneWidget);
      expect(fetched, 0);
    });

    testWidgets('a template call is fetched by id, with a skeleton meanwhile', (
      tester,
    ) async {
      final done = Completer<UiSurface?>();
      await tester.pumpWidget(
        host(
          SurfaceBlock(
            item(code: null, template: 'deploy-status'),
            loadSurface: (id) {
              expect(id, 'status');
              return done.future;
            },
          ),
        ),
      );
      expect(find.byType(IrisSurfaceSkeleton), findsOneWidget);
      done.complete(
        const UiSurface(
          surfaceId: 'status',
          rev: 2,
          placement: SurfacePlacement.inline,
          code: 'root = Text("Expanded from a template")',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Expanded from a template'), findsOneWidget);
      expect(find.byType(IrisSurfaceSkeleton), findsNothing);
    });

    testWidgets('a fetch that fails shows the reply\'s own text', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(SurfaceBlock(item(code: null), loadSurface: (_) async => null)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('all good'), findsOneWidget);
    });

    testWidgets('without text either it says so, and offers a retry', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        host(
          SurfaceBlock(
            item(code: null, fallback: null),
            loadSurface: (_) async {
              calls++;
              return calls == 1
                  ? null
                  : const UiSurface(
                      surfaceId: 'status',
                      rev: 1,
                      placement: SurfacePlacement.inline,
                      code: 'root = Text("Second time lucky")',
                    );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(IrisCantShow), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Second time lucky'), findsOneWidget);
    });

    testWidgets('a loader that throws is treated as a failed fetch', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SurfaceBlock(
            item(code: null),
            loadSurface: (_) => Future<UiSurface?>.error(StateError('x')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('all good'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reply kits do not draw in the transcript', (tester) async {
      await tester.pumpWidget(
        host(SurfaceBlock(item(placement: SurfacePlacement.replyKit))),
      );
      expect(find.byType(OpenUiView), findsNothing);
      expect(find.text('Deploy status'), findsNothing);
    });

    testWidgets('a new revision is fetched again', (tester) async {
      var calls = 0;
      Future<UiSurface?> load(String _) async {
        calls++;
        return UiSurface(
          surfaceId: 'status',
          rev: calls,
          placement: SurfacePlacement.inline,
          code: 'root = Text("rev $calls")',
        );
      }

      UiSurfaceItem rev(int n) => UiSurfaceItem(
        id: 'c1',
        ref: UiSurfaceRef(surfaceId: 'status', template: 't', rev: n),
      );

      await tester.pumpWidget(host(SurfaceBlock(rev(1), loadSurface: load)));
      await tester.pump();
      await tester.pump();
      expect(find.text('rev 1'), findsOneWidget);
      await tester.pumpWidget(host(SurfaceBlock(rev(2), loadSurface: load)));
      await tester.pump();
      await tester.pump();
      expect(find.text('rev 2'), findsOneWidget);
    });
  });

  group('ChatScreen', () {
    late FakeChatBackend backend;

    setUp(() => backend = FakeChatBackend());
    tearDown(() => backend.close());

    Future<void> settle(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 50));

    testWidgets('a stored display is drawn among the turns', (tester) async {
      backend.historyResult = Ok(
        _parse([
          {'id': 'u1', 'role': 'user', 'content': 'How is the deploy?'},
          _assistantCall('a1', 'c1', content: 'Here you go.'),
          _toolRow('t1', 'c1', _ok('status', 1)),
        ]),
      );
      await tester.pumpWidget(
        themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
      );
      await settle(tester);
      await settle(tester);
      expect(find.text('Here you go.'), findsOneWidget);
      expect(find.text('Deploy status'), findsOneWidget);
      expect(find.text('All good'), findsOneWidget);
    });

    testWidgets('a template display is fetched from the stored conversation', (
      tester,
    ) async {
      backend.historyResult = Ok(
        _parse([
          _assistantCall(
            'a1',
            'c1',
            arguments: jsonEncode({
              'surface_id': 'd',
              'template': 'deploy-status',
              'data': <String, Object?>{},
              'fallback': 'API is up',
            }),
          ),
        ]),
      );
      backend.surfaces['d'] = const UiSurface(
        surfaceId: 'd',
        rev: 1,
        placement: SurfacePlacement.inline,
        code: 'root = Text("API is up, drawn natively")',
      );
      await tester.pumpWidget(
        themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
      );
      await settle(tester);
      await settle(tester);
      await settle(tester);
      expect(find.text('API is up, drawn natively'), findsOneWidget);
      expect(backend.surfacesFetched, ['stored-1/d']);
    });

    testWidgets('a display arriving live is drawn as it is called', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
      );
      await settle(tester);
      backend
        ..emit(const MessageStarted('run-1'))
        ..emit(const TextDelta('run-1', 'Let me show you.'))
        ..emit(
          ToolStarted(
            'run-1',
            toolId: 'call-1',
            name: 'iris_ui',
            input: _args(),
          ),
        );
      await settle(tester);
      await settle(tester);
      expect(find.text('Deploy status'), findsOneWidget);
      expect(find.text('Let me show you.'), findsOneWidget);
    });

    testWidgets('a display that fails to draw shows the reply\'s text', (
      tester,
    ) async {
      backend.historyResult = Ok(
        _parse([
          _assistantCall('a1', 'c1', arguments: _args(code: 'nonsense')),
        ]),
      );
      await tester.pumpWidget(
        themed(ChatScreen(backend: backend, conversationId: 'stored-1')),
      );
      await settle(tester);
      await settle(tester);
      expect(find.textContaining('all good'), findsOneWidget);
    });
  });
}
