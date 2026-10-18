import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/automation/profile_repository.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';

void main() {
  late FakeHttp http;
  setUp(() => http = FakeHttp());

  DashboardProfileRepository repo() {
    final connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'S'),
      adapter: http,
    );
    addTearDown(connection.close);
    return DashboardProfileRepository(connection.client);
  }

  group('ProfileName', () {
    test('accepts lowercase letters, digits, - and _', () {
      for (final name in ['research', 'work-notes', 'a1_b2', 'x']) {
        expect(ProfileName.isValid(name), isTrue, reason: name);
        expect(ProfileName.problem(name), isNull);
      }
    });

    test('rejects capitals, spaces and a leading dash', () {
      for (final name in ['Work Notes', 'Research', '-x', 'a b', 'é']) {
        expect(ProfileName.isValid(name), isFalse, reason: name);
        expect(ProfileName.problem(name), isNotNull);
      }
    });

    test('an empty name is not an error yet, but is not valid', () {
      expect(ProfileName.problem(''), isNull);
      expect(ProfileName.isValid(''), isFalse);
    });
  });

  group('ProfileDraft.toBody', () {
    test('blank sends the name and the SOUL only', () {
      expect(const ProfileDraft(name: 'a', soul: ' hi ').toBody(), {
        'name': 'a',
        'soul': 'hi',
      });
    });

    test('copy of default uses clone_from_default', () {
      expect(
        const ProfileDraft(name: 'a', start: ProfileStart.copy).toBody(),
        {'name': 'a', 'clone_from_default': true},
      );
    });

    test('full copy of another profile uses clone_from and clone_all', () {
      expect(
        const ProfileDraft(
          name: 'a',
          start: ProfileStart.full,
          source: 'research',
        ).toBody(),
        {'name': 'a', 'clone_from': 'research', 'clone_all': true},
      );
    });
  });

  group('DashboardProfileRepository', () {
    test('rename patches new_name', () async {
      http.on('PATCH', '/api/profiles/old', (_) => const FakeReply(200, body: '{}'));
      expect((await repo().rename('old', 'new')).isOk, isTrue);
      expect(http.requests.single.data, {'new_name': 'new'});
    });

    test('soul reads content and setSoul writes it', () async {
      http.on('GET', '/api/profiles/a/soul',
          (_) => const FakeReply(200, body: '{"content":"# A","exists":true}'));
      http.on('PUT', '/api/profiles/a/soul', (_) => const FakeReply(200, body: '{"ok":true}'));
      final r = repo();
      expect((await r.soul('a')).valueOrNull, '# A');
      expect((await r.setSoul('a', '# B')).isOk, isTrue);
      expect(http.requests.last.data, {'content': '# B'});
    });

    test('delete uses DELETE and a refusal keeps its message', () async {
      http.on('DELETE', '/api/profiles/default', (_) => const FakeReply(
            400,
            body: '{"detail":"The default profile cannot be deleted."}',
          ));
      final result = await repo().delete('default');
      expect(result.failureOrNull?.message, contains('cannot be deleted'));
    });
  });
}
