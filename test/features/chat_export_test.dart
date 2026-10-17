import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/chat_export.dart';

void main() {
  group('transcriptMarkdown', () {
    test('headings, turns in order, and the title', () {
      final text = transcriptMarkdown('Heartbeat gaps', const [
        UserTurn(id: '1', text: 'Why the gaps?'),
        AssistantTurn(id: '2', text: 'They line up with the backup.'),
      ]);
      expect(text, startsWith('# Heartbeat gaps\n'));
      expect(text.indexOf('## You'), lessThan(text.indexOf('## Hermes')));
      expect(text, contains('Why the gaps?'));
      expect(text, contains('They line up with the backup.'));
    });

    test('attachments are listed by name', () {
      final text = transcriptMarkdown('t', const [
        UserTurn(id: '1', text: 'See these', attachments: ['a.png', 'b.pdf']),
      ]);
      expect(text, contains('_Attached: a.png, b.pdf_'));
    });

    test('a tool call becomes one quoted line, a failed one says so', () {
      final text = transcriptMarkdown('t', const [
        ToolCall(id: '1', name: 'read_logs'),
        ToolCall(id: '2', name: 'restart', status: ToolStatus.failed),
      ]);
      expect(text, contains('> Ran: `read_logs`'));
      expect(text, contains('> Tool failed: `restart`'));
    });

    test('reasoning and empty assistant turns are left out', () {
      final text = transcriptMarkdown('t', const [
        AssistantTurn(id: '1', text: '', reasoning: 'secret thoughts'),
        AssistantTurn(id: '2', text: 'Answer', reasoning: 'more thoughts'),
      ]);
      expect(text, isNot(contains('secret thoughts')));
      expect(text, isNot(contains('more thoughts')));
      expect('## Hermes'.allMatches(text), hasLength(1));
    });

    test('an error notice is included and a plain one is not', () {
      final text = transcriptMarkdown('t', const [
        Notice(id: '1', text: 'Connection lost', isError: true),
        Notice(id: '2', text: 'Stopped'),
      ]);
      expect(text, contains('> Error: Connection lost'));
      expect(text, isNot(contains('Stopped')));
    });

    test('an empty title and an empty chat still produce a document', () {
      expect(transcriptMarkdown('  ', const []), '# Chat\n');
    });
  });

  group('exportFileName', () {
    test('slugs the title', () {
      expect(
        exportFileName('Investigate worker heartbeat gaps'),
        'investigate-worker-heartbeat-gaps.md',
      );
    });

    test('falls back when nothing usable is left', () {
      expect(exportFileName('???'), 'chat.md');
      expect(exportFileName(''), 'chat.md');
    });

    test('is never long', () {
      expect(exportFileName('a' * 200).length, lessThanOrEqualTo(43));
    });
  });
}
