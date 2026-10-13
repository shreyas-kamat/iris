import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/models/stream_event.dart';
import 'package:iris/data/sse/sse_frame.dart';

/// Builds the frame the parser would have produced for this wire event.
StreamEvent decode(String event, [Object? payload]) => StreamEvent.fromFrame(
  SseFrame(event: event, data: payload == null ? '' : jsonEncode(payload)),
);

/// Every wire name in the `session-sse-contract-v1` authoritative table, plus
/// the legacy `error` alias and the `session_snapshot` resume fallback.
const authoritativeWireNames = <String>[
  'token',
  'reasoning',
  'tool',
  'tool_complete',
  'interim_assistant',
  'approval',
  'clarify',
  'compressing',
  'compressed',
  'title',
  'title_status',
  'warning',
  'apperror',
  'cancel',
  'done',
  'stream_end',
  'metering',
  'context_status',
  'goal',
  'goal_continue',
  'pending_steer_leftover',
  'state_saved',
  'todo_state',
];

void main() {
  group('contract coverage', () {
    test('every authoritative wire name decodes to a typed event', () {
      for (final name in authoritativeWireNames) {
        expect(
          decode(name, const <String, Object?>{}),
          isNot(isA<UnknownEvent>()),
          reason: '$name fell through to UnknownEvent',
        );
      }
      expect(authoritativeWireNames, hasLength(23));
    });

    test('every authoritative event survives an empty payload', () {
      // A field-less frame must never throw: upstream uses payload-free events
      // as fences, and a proxy can truncate any body.
      for (final name in authoritativeWireNames) {
        expect(() => decode(name), returnsNormally, reason: name);
      }
    });

    test('exactly the relay-closing events are terminal', () {
      const closing = {'stream_end', 'cancel', 'apperror', 'error'};
      for (final name in [...authoritativeWireNames, 'error']) {
        expect(
          decode(name, const <String, Object?>{}).isTerminal,
          closing.contains(name),
          reason: name,
        );
      }
    });

    test('done is not terminal — title and stream_end may still follow', () {
      // The classic bug against this contract. Guarded explicitly.
      expect(decode('done', const <String, Object?>{}).isTerminal, isFalse);
    });
  });

  group('unknown events', () {
    test('an unrecognised wire name is kept, not dropped', () {
      final event = decode('subagent_spawned', {'agent': 'reviewer'});
      expect(event, isA<UnknownEvent>());
      expect(event.wireName, 'subagent_spawned');
      expect(event.raw['agent'].string(), 'reviewer');
    });

    test('a malformed payload does not throw', () {
      final event = StreamEvent.fromFrame(
        const SseFrame(event: 'token', data: 'not json at all'),
      );
      expect(event, isA<TokenEvent>());
      expect((event as TokenEvent).text, isEmpty);
    });
  });

  group('text events', () {
    test('token reads any of the delta field spellings', () {
      for (final key in ['text', 'delta', 'content']) {
        expect((decode('token', {key: 'hi'}) as TokenEvent).text, 'hi');
      }
    });

    test('reasoning is distinct from token', () {
      expect(decode('reasoning', {'text': 'thinking'}), isA<ReasoningEvent>());
    });
  });

  group('tools', () {
    test('a tool call carries its name, preview and arguments', () {
      final event =
          decode('tool', {
                'id': 'call_1',
                'name': 'terminal',
                'preview': 'ls -la',
                'args': {'cmd': 'ls -la'},
              })
              as ToolStartedEvent;
      expect(event.callId, 'call_1');
      expect(event.name, 'terminal');
      expect(event.preview, 'ls -la');
      expect(event.arguments['cmd'].string(), 'ls -la');
    });

    test('a renamed tool field is still found', () {
      final event = decode('tool', {'tool_name': 'grep'}) as ToolStartedEvent;
      expect(event.name, 'grep');
    });

    test('a nameless tool falls back rather than rendering empty', () {
      expect(
        (decode('tool', const <String, Object?>{}) as ToolStartedEvent).name,
        'tool',
      );
    });

    test('completion distinguishes output from error', () {
      final ok =
          decode('tool_complete', {'name': 'grep', 'result': 'found'})
              as ToolCompletedEvent;
      final bad =
          decode('tool_complete', {'name': 'grep', 'error': 'no such file'})
              as ToolCompletedEvent;
      expect(ok.failed, isFalse);
      expect(ok.output, 'found');
      expect(bad.failed, isTrue);
      expect(bad.error, 'no such file');
    });
  });

  group('interaction gates', () {
    test('approval exposes the exact scope an always-allow would grant', () {
      final event =
          decode('approval', {
                'command': 'rm -rf build',
                'description': 'Deletes a directory',
                'pattern_keys': ['rm', 'rm -rf'],
              })
              as ApprovalEvent;
      expect(event.command, 'rm -rf build');
      expect(event.description, 'Deletes a directory');
      expect(event.patternKeys, ['rm', 'rm -rf']);
    });

    test('clarify reads options from label, value or id', () {
      final event =
          decode('clarify', {
                'question': 'Which branch?',
                'options': [
                  {'label': 'main'},
                  {'value': 'develop'},
                  {'id': 'feature'},
                ],
              })
              as ClarifyEvent;
      expect(event.question, 'Which branch?');
      expect(event.options, ['main', 'develop', 'feature']);
    });
  });

  group('checklists', () {
    test('a plan of plain strings decodes as pending steps', () {
      final event =
          decode('goal', {
                'title': 'Ship the parser',
                'steps': ['write it', 'test it'],
              })
              as GoalEvent;
      expect(event.title, 'Ship the parser');
      expect(event.steps.map((s) => s.label), ['write it', 'test it']);
      expect(
        event.steps.map((s) => s.status),
        everyElement(ChecklistStatus.pending),
      );
    });

    test('status vocabularies collapse onto one enum', () {
      final event =
          decode('todo_state', {
                'todos': [
                  {'text': 'a', 'status': 'in_progress'},
                  {'text': 'b', 'status': 'completed'},
                  {'text': 'c', 'status': 'blocked'},
                  {'text': 'd', 'done': true},
                  {'text': 'e', 'status': 'nonsense'},
                ],
              })
              as TodoStateEvent;
      expect(event.items.map((i) => i.status), [
        ChecklistStatus.active,
        ChecklistStatus.done,
        ChecklistStatus.failed,
        ChecklistStatus.done,
        ChecklistStatus.pending,
      ]);
    });

    test('unlabelled items are dropped, not rendered blank', () {
      final event =
          decode('todo_state', {
                'todos': [
                  {'text': 'keep'},
                  {'status': 'done'},
                  'also keep',
                  '',
                ],
              })
              as TodoStateEvent;
      expect(event.items.map((i) => i.label), ['keep', 'also keep']);
    });
  });

  group('telemetry', () {
    test('metering totals only what was reported', () {
      final full =
          decode('metering', {'input_tokens': 100, 'output_tokens': 40})
              as MeteringEvent;
      final none =
          decode('metering', const <String, Object?>{}) as MeteringEvent;
      expect(full.totalTokens, 140);
      expect(none.totalTokens, isNull, reason: 'absent is not zero');
    });

    test('context fill accepts a fraction, a percentage, or raw counts', () {
      double? fill(Object payload) =>
          (decode('context_status', payload) as ContextStatusEvent).fraction;
      expect(fill({'percent': 0.5}), 0.5);
      expect(fill({'percent': 50}), 0.5);
      expect(fill({'used': 1000, 'window': 4000}), 0.25);
      expect(fill(const <String, Object?>{}), isNull);
    });

    test('context fill is clamped and survives a zero window', () {
      double? fill(Object payload) =>
          (decode('context_status', payload) as ContextStatusEvent).fraction;
      expect(fill({'percent': 140}), 1.0);
      expect(fill({'used': 10, 'window': 0}), isNull);
    });
  });

  group('lifecycle', () {
    test('done carries the authoritative session snapshot', () {
      final event =
          decode('done', {
                'session': {'session_id': 'abc', 'title': 'Hello'},
              })
              as DoneEvent;
      expect(event.session['session_id'].string(), 'abc');
    });

    test('compressing and compressed share a type but differ in phase', () {
      final start = decode('compressing') as CompressionEvent;
      final end =
          decode('compressed', {'before': 100000, 'after': 20000})
              as CompressionEvent;
      expect(start.finished, isFalse);
      expect(end.finished, isTrue);
      expect(end.tokensBefore, 100000);
      expect(end.tokensAfter, 20000);
    });

    test('the legacy error alias maps onto apperror', () {
      final event = decode('error', {'message': 'boom'}) as AppErrorEvent;
      expect(event.message, 'boom');
      expect(event.isTerminal, isTrue);
    });

    test('an errorless apperror still has something to show', () {
      expect((decode('apperror') as AppErrorEvent).message, 'Agent error');
    });

    test('session_snapshot carries state for a broken cursor', () {
      final event =
          decode('session_snapshot', {
                'session': {'session_id': 'abc'},
              })
              as SessionSnapshotEvent;
      expect(event.session['session_id'].string(), 'abc');
    });
  });

  test('the event id is carried through for resume', () {
    final event = StreamEvent.fromFrame(
      const SseFrame(event: 'token', data: '{}', id: 'stream-7:42'),
    );
    expect(event.eventId, 'stream-7:42');
  });
}
