/// Profiles, conversation pages, models and slash commands, in the shapes
/// Hermes 0.18.2 sends.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/catalog_parser.dart';
import 'package:iris/data/chat/chat_models.dart';

void main() {
  test('profiles', () {
    final profiles = CatalogParser.profiles(
      Json.of({
        'profiles': [
          {
            'name': 'default',
            'is_default': true,
            'model': 'gpt-6.1-sol',
            'provider': 'openai-codex',
            'gateway_running': true,
          },
          {'name': 'ananta', 'is_default': false},
          {'is_default': false},
        ],
      }),
    );
    expect(profiles.map((p) => p.name), ['default', 'ananta']);
    expect(profiles.first.isDefault, isTrue);
    expect(profiles.first.model, 'gpt-6.1-sol');
    expect(profiles.first.running, isTrue);
    expect(profiles.last.isDefault, isFalse);
  });

  test('a conversation page keeps its total and each row its profile', () {
    final page = CatalogParser.conversationPage(
      Json.of({
        'sessions': [
          {'id': 'a', 'title': null, 'preview': 'Hello', 'profile': 'ananta'},
        ],
        'total': 12,
        'limit': 50,
        'offset': 0,
      }),
    );
    expect(page.total, 12);
    expect(page.items.single.title, 'Hello');
    expect(page.items.single.profile, 'ananta');
  });

  test('model options keep only usable providers in usable', () {
    final options = CatalogParser.modelOptions(
      Json.of({
        'model': 'gpt-6.1-sol',
        'provider': 'openai-codex',
        'providers': [
          {
            'slug': 'openai-codex',
            'name': 'OpenAI Codex',
            'is_current': true,
            'authenticated': true,
            'models': ['gpt-6.1-sol', 'gpt-6-luna'],
          },
          {
            'slug': 'omniroute',
            'name': 'omniroute',
            'authenticated': false,
            'models': ['x'],
          },
          {'slug': 'empty', 'name': 'Empty', 'models': <String>[]},
          {
            'slug': 'objects',
            'models': [
              {'id': 'm-1'},
            ],
          },
        ],
      }),
    );
    expect(options.model, 'gpt-6.1-sol');
    expect(options.provider, 'openai-codex');
    expect(options.providers, hasLength(4));
    expect(options.usable.map((p) => p.slug), ['openai-codex', 'objects']);
    expect(options.usable.first.isCurrent, isTrue);
    expect(options.usable.last.name, 'objects');
    expect(options.usable.last.models, ['m-1']);
  });

  test('the current provider is usable even when it reports unauthenticated', () {
    // Hermes 0.18.2 reports openai-codex, the configured provider in use, as
    // authenticated: false (source: configured-current).
    final options = CatalogParser.modelOptions(
      Json.of({
        'providers': [
          {
            'slug': 'openai-codex',
            'is_current': true,
            'authenticated': false,
            'models': ['gpt-6.1-sol'],
          },
          {'slug': 'other', 'authenticated': false, 'models': ['x']},
        ],
      }),
    );
    expect(options.usable.map((p) => p.slug), ['openai-codex']);
  });

  test('a model switch strips echoed flags and reads confirmation', () {
    final echoed = CatalogParser.modelSwitch(
      Json.of({'value': 'gpt-6-luna --provider openai-codex --session'}),
      requested: 'gpt-6-luna',
    );
    expect(echoed.model, 'gpt-6-luna');
    expect(echoed.confirmRequired, isFalse);

    final guarded = CatalogParser.modelSwitch(
      Json.of({'confirm_required': true, 'warning': 'Costly.'}),
      requested: 'big-model',
    );
    expect(guarded.model, 'big-model');
    expect(guarded.confirmRequired, isTrue);
    expect(guarded.confirmMessage, 'Costly.');

    final later = CatalogParser.modelSwitch(
      Json.of({'value': 'x', 'deferred': true}),
      requested: 'x',
    );
    expect(later.deferred, isTrue);
  });

  test('commands keep order, drop duplicates and gain a slash', () {
    final commands = CatalogParser.commands(
      Json.of({
        'pairs': [
          ['/new', 'Start a new session'],
          ['model', 'Switch model'],
          ['/new', 'duplicate'],
          [''],
        ],
      }),
    );
    expect(commands.map((c) => c.name), ['/new', '/model']);
    expect(commands.first.description, 'Start a new session');
  });

  group('slash outcomes', () {
    SlashOutcome parse(Object? result) =>
        CatalogParser.slashOutcome(Json.of(result));

    test('exec and plugin show their output', () {
      expect(parse({'type': 'exec', 'output': 'Tokens: 12k'}).kind, SlashKind.exec);
      expect(parse({'type': 'exec', 'output': 'Tokens: 12k'}).text, 'Tokens: 12k');
      expect(parse({'type': 'plugin', 'message': 'ok'}).text, 'ok');
    });

    test('send and skill carry a prompt', () {
      final send = parse({'type': 'skill', 'message': 'Plan the week'});
      expect(send.kind, SlashKind.send);
      expect(send.text, 'Plan the week');
    });

    test('prefill carries text and a notice', () {
      final prefill = parse({
        'type': 'prefill',
        'message': 'Write ',
        'notice': 'Finish the prompt',
      });
      expect(prefill.kind, SlashKind.prefill);
      expect(prefill.text, 'Write ');
      expect(prefill.notice, 'Finish the prompt');
    });

    test('alias names its target', () {
      final alias = parse({'type': 'alias', 'target': '/new'});
      expect(alias.kind, SlashKind.alias);
      expect(alias.target, '/new');
    });

    test('an unknown type or a bare string is shown as output', () {
      expect(parse({'type': 'mystery', 'output': 'x'}).kind, SlashKind.exec);
      expect(parse('plain text').text, 'plain text');
    });
  });

  test('model capabilities are read per model, and absent means unknown', () {
    final options = CatalogParser.modelOptions(Json.of({
      'providers': [
        {
          'slug': 'anthropic',
          'name': 'Anthropic',
          'models': ['opus', 'haiku'],
          'capabilities': {
            'opus': {'reasoning': true, 'fast': true},
            'haiku': {'reasoning': false, 'fast': false},
          },
        },
        {'slug': 'local', 'models': ['llama']},
      ],
    }));
    expect(options.capsFor('opus')?.reasoning, isTrue);
    expect(options.capsFor('opus')?.fast, isTrue);
    expect(options.capsFor('haiku')?.reasoning, isFalse);
    expect(options.capsFor('llama'), isNull);
    expect(options.capsFor('opus', provider: 'local'), isNull);
  });

}
