/// Updating a display in place (plan 4.5): a later `iris_ui` call on the same id replaces the display where it first
/// appeared, keeps what the person has typed, is tagged "Updated", and a refused update leaves the last good version.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/history_parser.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/chat_state.dart';
import 'package:iris/features/genui/surface_block.dart';

const _v1 = 'root = Stack([Text("Deploy status", "title"), Text("Building")])';
const _v2 = 'root = Stack([Text("Deploy status", "title"), Text("Done")])';

String _args(String code, {String id = 'status'}) => jsonEncode({
  'surface_id': id,
  'code': code,
  'fallback': 'Deploy status',
  'placement': 'inline',
});

String _ok(int rev, {String id = 'status'}) =>
    jsonEncode({'ok': true, 'surface_id': id, 'rev': rev});

final _refused = jsonEncode({
  'ok': false,
  'errors': ['root is missing'],
});

Map<String, Object?> _call(String rowId, String callId, String arguments) => {
  'id': rowId,
  'role': 'assistant',
  'content': '',
  'tool_calls': [
    {
      'id': callId,
      'type': 'function',
      'function': {'name': 'iris_ui', 'arguments': arguments},
    },
  ],
};

Map<String, Object?> _text(String rowId, String content) => {
  'id': rowId,
  'role': 'assistant',
  'content': content,
};

Map<String, Object?> _answer(String rowId, String callId, String content) => {
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
    test(
      'an update takes the first one\'s place and carries the new program',
      () {
        final items = _parse([
          _call('a1', 'c1', _args(_v1)),
          _answer('t1', 'c1', _ok(1)),
          _text('a2', 'Building now.'),
          _call('a3', 'c2', _args(_v2)),
          _answer('t2', 'c2', _ok(2)),
          _text('a4', 'All done.'),
        ]);
        expect(items.map((i) => i.runtimeType), [
          UiSurfaceItem,
          AssistantTurn,
          AssistantTurn,
        ]);
        final surface = items.first as UiSurfaceItem;
        expect(surface.ref.code, _v2);
        expect(surface.ref.rev, 2);
        expect(surface.updated, isTrue);
        expect(surface.isUpdated, isTrue);
      },
    );

    test('its key does not change when it is updated', () {
      final first = _parse([_call('a1', 'c1', _args(_v1))]);
      final updated = _parse([
        _call('a1', 'c1', _args(_v1)),
        _call('a2', 'c2', _args(_v2)),
      ]);
      expect(updated.first.id, first.first.id);
    });

    test('a display shown once is not tagged', () {
      final items = _parse([
        _call('a1', 'c1', _args(_v1)),
        _answer('t1', 'c1', _ok(1)),
      ]);
      expect((items.single as UiSurfaceItem).isUpdated, isFalse);
    });

    test(
      'a revision above one is an update even when the earlier call is gone',
      () {
        final items = _parse([
          _call('a1', 'c1', _args(_v2)),
          _answer('t1', 'c1', _ok(4)),
        ]);
        expect((items.single as UiSurfaceItem).isUpdated, isTrue);
      },
    );

    test(
      'the first call\'s late answer does not overwrite the update\'s revision',
      () {
        final items = _parse([
          _call('a1', 'c1', _args(_v1)),
          _call('a2', 'c2', _args(_v2)),
          _answer('t2', 'c2', _ok(2)),
          _answer('t1', 'c1', _ok(1)),
        ]);
        expect((items.single as UiSurfaceItem).ref.rev, 2);
        expect(items.whereType<ToolCall>(), isEmpty);
      },
    );

    test(
      'a refused update leaves the last good version and shows the failure',
      () {
        final items = _parse([
          _call('a1', 'c1', _args(_v1)),
          _answer('t1', 'c1', _ok(1)),
          _call('a2', 'c2', _args('root = ???')),
          _answer('t2', 'c2', _refused),
        ]);
        final surface = items.whereType<UiSurfaceItem>().single;
        expect(surface.ref.code, _v1);
        expect(surface.isUpdated, isFalse);
        final card = items.whereType<ToolCall>().single;
        expect(card.status, ToolStatus.failed);
        expect(card.output, contains('root is missing'));
      },
    );

    test('a refused first display is only a failed card', () {
      final items = _parse([
        _call('a1', 'c1', _args('root = ???')),
        _answer('t1', 'c1', _refused),
      ]);
      expect(items.whereType<UiSurfaceItem>(), isEmpty);
      expect(items.whereType<ToolCall>().single.status, ToolStatus.failed);
    });

    test('an update after a delete is a new display, not an update', () {
      final items = _parse([
        _call('a1', 'c1', _args(_v1)),
        _call('a2', 'c2', jsonEncode({'surface_id': 'status', 'delete': true})),
        _call('a3', 'c3', _args(_v2)),
      ]);
      expect((items.single as UiSurfaceItem).updated, isFalse);
    });
  });

  group('live events', () {
    const ready = ChatState(phase: ChatPhase.ready);

    ChatState call(ChatState s, String callId, String code) => s.apply(
      ToolStarted('r', toolId: callId, name: 'iris_ui', input: _args(code)),
    );

    ChatState done(ChatState s, String callId, String output) => s.apply(
      ToolCompleted('r', toolId: callId, name: 'iris_ui', output: output),
    );

    ChatState open() => ready.apply(const MessageStarted('r'));

    test('a second call replaces the display where it is, tagged updated', () {
      var s = call(open(), 'c1', _v1);
      s = done(s, 'c1', _ok(1));
      final key = s.items.single.id;
      s = s.apply(const TextDelta('r', 'Now it is done.'));
      s = call(s, 'c2', _v2);
      final surfaces = s.items.whereType<UiSurfaceItem>().toList();
      expect(surfaces, hasLength(1));
      expect(surfaces.single.ref.code, _v2);
      expect(surfaces.single.updated, isTrue);
      expect(surfaces.single.id, key);
      // It stays above the text that came after it.
      expect(s.items.first, isA<UiSurfaceItem>());
    });

    test('the update\'s answer records its revision', () {
      var s = call(open(), 'c1', _v1);
      s = done(s, 'c1', _ok(1));
      s = call(s, 'c2', _v2);
      s = done(s, 'c2', _ok(2));
      final surface = s.items.whereType<UiSurfaceItem>().single;
      expect(surface.ref.rev, 2);
      expect(surface.ref.accepted, isTrue);
    });

    test('a refused update brings back the last good version', () {
      var s = call(open(), 'c1', _v1);
      s = done(s, 'c1', _ok(1));
      s = call(s, 'c2', 'root = ???');
      s = done(s, 'c2', _refused);
      final surface = s.items.whereType<UiSurfaceItem>().single;
      expect(surface.ref.code, _v1);
      expect(surface.isUpdated, isFalse);
      final card = s.items.whereType<ToolCall>().single;
      expect(card.status, ToolStatus.failed);
      expect(card.output, contains('root is missing'));
    });

    test('the first call\'s late answer cannot touch the update', () {
      var s = call(open(), 'c1', _v1);
      s = call(s, 'c2', _v2);
      s = done(s, 'c2', _ok(2));
      s = done(s, 'c1', _ok(1));
      expect(s.items.whereType<UiSurfaceItem>().single.ref.rev, 2);
      expect(s.items.whereType<ToolCall>(), isEmpty);
    });
  });

  group('SurfaceBlock', () {
    Widget host(Widget child) {
      final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
      return IrisTheme(
        data: theme,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: theme.materialTheme,
            home: Material(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 390,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    UiSurfaceItem item(String code, {bool updated = false, int? rev}) =>
        UiSurfaceItem(
          id: 'c1',
          updated: updated,
          ref: UiSurfaceRef(surfaceId: 'status', code: code, rev: rev),
        );

    testWidgets('an updated display says so', (tester) async {
      await tester.pumpWidget(host(SurfaceBlock(item(_v2, updated: true))));
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('a revision above one says so too', (tester) async {
      await tester.pumpWidget(host(SurfaceBlock(item(_v2, rev: 3))));
      expect(find.text('Updated'), findsOneWidget);
    });

    testWidgets('a first display has no tag', (tester) async {
      await tester.pumpWidget(host(SurfaceBlock(item(_v1, rev: 1))));
      expect(find.text('Updated'), findsNothing);
    });

    testWidgets(
      'an update keeps what the person typed, whatever the model rewrote',
      (tester) async {
        const form = r'''
$note = "from the model"
root = Stack([Input("Note", $note), Text("v1: " + $note)])
''';
        const revised = r'''
$note = "from the model, again"
root = Stack([Input("Note", $note), Text("v2: " + $note), Text("New line")])
''';
        await tester.pumpWidget(host(SurfaceBlock(item(form))));
        await tester.enterText(find.byType(EditableText), 'my own words');
        await tester.pump();
        expect(find.text('v1: my own words'), findsOneWidget);

        await tester.pumpWidget(
          host(SurfaceBlock(item(revised, updated: true))),
        );
        expect(find.text('v2: my own words'), findsOneWidget);
        expect(find.text('New line'), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          'my own words',
        );
      },
    );

    testWidgets('the docked kit is never tagged', (tester) async {
      await tester.pumpWidget(
        host(SurfaceBlock(item(_v2, updated: true), docked: true)),
      );
      expect(find.text('Updated'), findsNothing);
    });
  });
}
