/// Conversation lists and stored transcripts, in the shapes Hermes 0.18.2
/// actually sends.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/chat/history_parser.dart';

void main() {
  group('conversations', () {
    test('reads session.list rows', () {
      final list = HistoryParser.conversations(
        Json.of({
          'sessions': [
            {
              'id': 'abc',
              'title': 'Fix the build',
              'preview': 'Fix the build',
              'started_at': 1760340000.5,
              'message_count': 12,
              'source': 'telegram',
            },
          ],
        }),
      );
      final row = list.single;
      expect(row.id, 'abc');
      expect(row.title, 'Fix the build');
      expect(row.messageCount, 12);
      expect(row.source, 'telegram');
      expect(row.startedAt, isNotNull);
    });

    test('a row without a title falls back to its preview, then a placeholder', () {
      final list = HistoryParser.conversations(
        Json.of({
          'sessions': [
            {'id': 'a', 'title': '', 'preview': 'hello there'},
            {'id': 'b'},
          ],
        }),
      );
      expect(list.map((c) => c.title), ['hello there', 'Untitled conversation']);
    });

    test('a row without an id is dropped, not fatal', () {
      final list = HistoryParser.conversations(
        Json.of({
          'sessions': [
            {'title': 'orphan'},
            {'id': 'ok'},
          ],
        }),
      );
      expect(list.single.id, 'ok');
    });
  });

  group('transcript', () {
    Json page(List<Map<String, Object?>> rows) => Json.of({
      'session_id': 's',
      'messages': rows,
      'pagination': {'limit': 120, 'offset': 0, 'returned': rows.length},
    });

    test('user and assistant turns, oldest first', () {
      final items = HistoryParser.transcript(
        page([
          {'id': 1, 'role': 'user', 'content': 'hi'},
          {
            'id': 2,
            'role': 'assistant',
            'content': 'hello',
            'reasoning': 'be nice',
          },
        ]),
      );
      expect(items, hasLength(2));
      expect(items[0], isA<UserTurn>().having((t) => t.text, 'text', 'hi'));
      expect(items[0].id, '1');
      final reply = items[1] as AssistantTurn;
      expect(reply.text, 'hello');
      expect(reply.reasoning, 'be nice');
      expect(reply.streaming, isFalse);
    });

    test('a tool call gets its result attached by call id', () {
      final items = HistoryParser.transcript(
        page([
          {
            'id': 3,
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'call_1',
                'call_id': 'call_1',
                'type': 'function',
                'function': {
                  'name': 'terminal',
                  'arguments': '{"command":"ls"}',
                },
              },
            ],
          },
          {
            'id': 4,
            'role': 'tool',
            'content': 'a.txt',
            'tool_call_id': 'call_1',
            'tool_name': 'terminal',
          },
          {'id': 5, 'role': 'assistant', 'content': 'Done.'},
        ]),
      );
      expect(items, hasLength(2));
      final call = items[0] as ToolCall;
      expect(call.name, 'terminal');
      expect(call.arguments, '{"command":"ls"}');
      expect(call.output, 'a.txt');
      expect(call.status, ToolStatus.done);
      expect(items[1], isA<AssistantTurn>().having((t) => t.text, 'text', 'Done.'));
    });

    test('a tool result with no matching call still shows', () {
      final items = HistoryParser.transcript(
        page([
          {
            'id': 7,
            'role': 'tool',
            'content': 'out',
            'tool_call_id': 'gone',
            'tool_name': 'web',
          },
        ]),
      );
      final call = items.single as ToolCall;
      expect(call.name, 'web');
      expect(call.output, 'out');
    });

    test('hidden, system and empty rows are skipped', () {
      final items = HistoryParser.transcript(
        page([
          {'id': 1, 'role': 'system', 'content': 'You are Hermes.'},
          {
            'id': 2,
            'role': 'user',
            'content': 'compaction handoff',
            'display_kind': 'hidden',
          },
          {'id': 3, 'role': 'assistant', 'content': '   '},
          {'id': 4, 'role': 'user', 'content': 'real'},
        ]),
      );
      expect(items.single, isA<UserTurn>().having((t) => t.text, 'text', 'real'));
    });

    test('content as a list of parts is joined', () {
      final items = HistoryParser.transcript(
        page([
          {
            'id': 1,
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'one'},
              {'type': 'text', 'text': 'two'},
            ],
          },
        ]),
      );
      expect(items.single, isA<UserTurn>().having((t) => t.text, 'text', 'one\ntwo'));
    });

    test('display_content wins over the stored content', () {
      final items = HistoryParser.transcript(
        page([
          {
            'id': 1,
            'role': 'user',
            'content': '[marker] steer',
            'display_content': 'steer',
          },
        ]),
      );
      expect(items.single, isA<UserTurn>().having((t) => t.text, 'text', 'steer'));
    });
  });

  group('requests', () {
    test('a clarify request drops answered questions', () {
      const request = ClarifyRequest(
        requestId: 'srq-1',
        sessionId: 'r',
        questions: [
          ClarifyQuestion(id: 'a', text: 'One?'),
          ClarifyQuestion(id: 'b', text: 'Two?'),
        ],
      );
      expect(request.isServerRequest, isTrue);
      expect(request.without('a').questions.single.id, 'b');
    });

    test('approval choices read as button labels', () {
      expect(ApprovalRequest.labelFor('once'), 'Allow once');
      expect(ApprovalRequest.labelFor('deny'), 'Deny');
      expect(ApprovalRequest.labelFor('custom'), 'custom');
    });
  });
}
