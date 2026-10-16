/// The demo behaves like a small Hermes server that lives in memory.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/demo/demo_chat_backend.dart';
import 'package:iris/demo/demo_content.dart';
import 'package:iris/demo/demo_world.dart';

Future<void> instant(Duration _) async {}

Future<void> drain() async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late DemoWorld world;
  late List<ChatEvent> events;

  setUp(() {
    world = DemoWorld(clock: () => DateTime(2026, 10, 15, 20), delay: instant);
    events = [];
    world.events.listen(events.add);
  });
  tearDown(() => world.dispose());

  test('each profile has its own conversations; archived are apart', () {
    final home = world.page('default', 0, archived: false);
    final lab = world.page('homelab', 0, archived: false);
    expect(home.items, isNotEmpty);
    expect(lab.items, isNotEmpty);
    expect(
      home.items
          .map((c) => c.id)
          .toSet()
          .intersection(lab.items.map((c) => c.id).toSet()),
      isEmpty,
    );
    expect(world.page('default', 0, archived: true).items, hasLength(1));
    expect(home.total, home.items.length);
  });

  test(
    'a suggested prompt in a new chat plays its script and names it',
    () async {
      final created = world.create('default');
      final script = demoScripts.firstWhere(
        (s) => s.prompt == "Summarise this week's GitHub issues",
      );
      world.submit(created.runtimeId, script.prompt);
      await drain();
      expect(events.whereType<TitleChanged>().single.title, script.title);
      expect(events.whereType<MessageCompleted>(), hasLength(1));
      final stored = world.history(created.storedId).items;
      expect(stored.first, isA<UserTurn>());
      expect(
        stored.whereType<AssistantTurn>().last.text,
        contains('acme/homelab-scripts'),
      );
      expect(
        world.page('default', 0, archived: false).items.first.id,
        created.storedId,
      );
    },
  );

  test('free text gets the honest fallback', () async {
    final created = world.create('default');
    world.submit(created.runtimeId, 'what is the meaning of life');
    await drain();
    expect(events.whereType<MessageCompleted>().single.content, demoFallback);
    expect(demoFallback, contains(leaveDemoLink));
  });

  test('the media server fails once; retry replays it and succeeds', () async {
    final created = world.create('default');
    final run = created.runtimeId;
    world.submit(run, 'Restart the media server');
    await drain();
    world.answerApproval(
      events.whereType<ApprovalAsked>().last.request,
      'once',
    );
    await drain();
    expect(events.whereType<TurnFailed>(), hasLength(1));

    final outcome = world.slash(run, '/retry');
    expect(outcome.kind, SlashKind.send);
    expect(outcome.text, 'Restart the media server');
    // Hermes drops the failed exchange; the controller then sends the prompt.
    expect(world.history(created.storedId).items, isEmpty);
    world.submit(run, outcome.text);
    await drain();
    world.answerApproval(
      events.whereType<ApprovalAsked>().last.request,
      'once',
    );
    await drain();
    expect(events.whereType<TurnFailed>(), hasLength(1));
    expect(
      events.whereType<MessageCompleted>().last.content,
      contains('Jellyfin is back up'),
    );
  });

  test('other slash commands are not available', () {
    final run = world.create('default').runtimeId;
    final outcome = world.slash(run, '/cron list');
    expect(outcome.kind, SlashKind.exec);
    expect(outcome.text, 'Not available in the demo.');
  });

  test('rename and archive change the lists', () {
    final first = world.page('default', 0, archived: false).items.first;
    world.rename(first.id, 'Renamed');
    expect(
      world.page('default', 0, archived: false).items.first.title,
      'Renamed',
    );
    world.setArchived(first.id, archived: true);
    expect(
      world
          .page('default', 0, archived: false)
          .items
          .any((c) => c.id == first.id),
      isFalse,
    );
    expect(
      world
          .page('default', 0, archived: true)
          .items
          .any((c) => c.id == first.id),
      isTrue,
    );
  });

  test('search finds message text and marks the match', () {
    final hits = world.search('default', 'fail2ban');
    expect(hits, hasLength(1));
    expect(
      hits.single.snippet.where((run) => run.matched).single.text.toLowerCase(),
      'fail2ban',
    );
    expect(world.search('default', 'zzz-nothing'), isEmpty);
  });

  test('a steer while running is accepted, otherwise rejected', () async {
    final created = world.create('default');
    expect(world.steer(created.runtimeId, 'hi'), SteerOutcome.rejected);
    world.submit(created.runtimeId, 'Check disk space on my server');
    await drain();
    expect(
      world.steer(created.runtimeId, 'only images'),
      SteerOutcome.accepted,
    );
    world.interrupt(created.runtimeId);
    await drain();
    expect(events.whereType<TurnInterrupted>(), hasLength(1));
  });

  test(
    'switching profile while a script runs in the other one is safe',
    () async {
      final created = world.create('default');
      world.submit(created.runtimeId, "Why did last night's backup fail?");
      final lab = DemoChatBackend(world, profile: 'homelab');
      final page = await lab.conversations(0);
      expect(page, isA<Ok<ConversationPage>>());
      expect(
        (page as Ok<ConversationPage>).value.items.every(
          (c) => c.profile == 'homelab',
        ),
        isTrue,
      );
      await drain();
      expect(events.whereType<MessageCompleted>(), hasLength(1));
      expect(events.whereType<TurnFailed>(), isEmpty);
    },
  );

  test('model options report usage, and a switch is remembered', () async {
    final options = world.modelOptions;
    expect(options.usable.where((p) => p.usage != null), hasLength(2));
    final run = world.create('default').runtimeId;
    final change = world.switchModel(run, 'gpt-6.1', 'openai-codex');
    expect(change.model, 'gpt-6.1');
    expect(world.modelOptions.model, 'gpt-6.1');
    await drain();
    expect(events.whereType<ModelChanged>().single.model, 'gpt-6.1');
  });

  test('the backend answers everything with Ok', () async {
    final chat = DemoChatBackend(world, profile: 'default');
    expect(await chat.profiles(), isA<Ok<List<AgentProfile>>>());
    expect(await chat.commands(), isA<Ok<List<SlashCommand>>>());
    expect(await chat.archivedConversations(0), isA<Ok<ConversationPage>>());
    expect(await chat.search('backup'), isA<Ok<List<SearchHit>>>());
  });

  test('the deploy script waits at each password-manager prompt', () async {
    final chat = DemoChatBackend(world, profile: 'default');
    final run = world.create('default').runtimeId;
    world.submit(run, 'Deploy the docs site');
    await drain();
    final unlock = events.whereType<InputAsked>().single.request;
    expect(unlock.kind, InputKind.vaultUnlock);
    await chat.answerInput(unlock, 'typed');
    await drain();
    final code = events.whereType<InputAsked>().last.request;
    expect(code.kind, InputKind.vaultCode);
    await chat.answerInput(code, '123456');
    await drain();
    final login = events.whereType<LoginAsked>().single.request;
    await chat.answerLogin(login, identifier: 'me', password: 'typed');
    await drain();
    final card = events.whereType<ConnectionAsked>().single.request;
    expect(card.targets, hasLength(3));
    await chat.answerConnection(card, const [], settle: true);
    await drain();
    expect(events.whereType<TurnFailed>(), isEmpty);
    expect(events.whereType<BusyChanged>().last.busy, isFalse);
  });
}
