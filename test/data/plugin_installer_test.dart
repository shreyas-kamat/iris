/// The pinned plugin release and the installer that puts it on a Hermes server through Hermes's own plugin route.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/genui/genui_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/plugin/plugin_installer.dart';
import 'package:iris/data/plugin/plugin_release.dart';

import '../support/fake_http.dart';

const _sha = '0123456789abcdef0123456789abcdef01234567';

const _release = PluginRelease(
  version: '0.4.0',
  tag: 'hermes-iris-v0.4.0',
  sha: _sha,
  repo: 'shreyas-kamat/iris',
  subdir: 'server/hermes-iris',
);

const _installPath = '/api/dashboard/agent-plugins/install';
const _capsPath = '/api/plugins/iris/capabilities';

FakeReply _caps(String version) => FakeReply.json({
  'version': version,
  'openui': '1.0',
  'library_ids': <String>[],
  'features': <String>['capabilities'],
});

GenUiCapabilities _plugin(String version) => GenUiCapabilities(
  version: version,
  openui: '1.0',
  libraryIds: const [],
  features: const {},
);

void main() {
  late FakeHttp http;

  setUp(() => http = FakeHttp());

  PluginInstaller installer([PluginRelease release = _release]) {
    final connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'S'),
      adapter: http,
    );
    addTearDown(connection.close);
    return PluginInstaller(connection.client, release: release);
  }

  group('PluginRelease', () {
    test('names its source and the command to do it by hand', () {
      expect(_release.identifier, 'shreyas-kamat/iris#server/hermes-iris');
      expect(
        _release.fallbackCommand,
        'hermes plugins install shreyas-kamat/iris#server/hermes-iris '
        '--force --ref $_sha',
      );
      expect(_release.released, isTrue);
    });

    test('is released only with a full commit sha', () {
      for (final sha in ['', 'abc', _sha.toUpperCase(), '${_sha}0']) {
        final release = PluginRelease(
          version: '0.4.0',
          tag: 't',
          sha: sha,
          repo: 'a/b',
          subdir: 'c',
        );
        expect(release.released, isFalse, reason: sha);
      }
    });

    test('this build pins a released commit', () {
      expect(PluginRelease.current.released, isTrue);
    });

    test('is never behind the plugin in this repository', () {
      final yaml = File('server/hermes-iris/plugin.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(yaml)!.group(1)!;
      expect(
        compareVersions(PluginRelease.current.version, version),
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('compareVersions', () {
    test('compares numerically, not as text', () {
      expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
      expect(compareVersions('0.3.0', '0.4.0'), lessThan(0));
    });

    test('treats missing parts as zero and ignores a pre-release suffix', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('0.4.0-rc1', '0.4.0'), 0);
    });
  });

  group('status', () {
    test('absent without a plugin', () {
      expect(installer().statusOf(null), isA<PluginAbsent>());
    });

    test('current when the versions match', () {
      final status = installer().statusOf(_plugin('0.4.0'));
      expect(status, isA<PluginInstalled>());
      expect((status as PluginInstalled).updateTo, isNull);
    });

    test('an older plugin offers the release', () {
      final status = installer().statusOf(_plugin('0.3.0')) as PluginInstalled;
      expect(status.version, '0.3.0');
      expect(status.updateTo, '0.4.0');
    });

    test('status ahead: a newer plugin is up to date, never a downgrade', () {
      final status = installer().statusOf(_plugin('0.5.0')) as PluginInstalled;
      expect(status.updateTo, isNull);
    });

    test('a version that cannot be read offers the release', () {
      final status = installer().statusOf(_plugin('dev')) as PluginInstalled;
      expect(status.updateTo, '0.4.0');
    });
  });

  group('install', () {
    test('posts the pinned release, then reads the version back', () async {
      http
        ..on('POST', _installPath, (_) => FakeReply.json({'ok': true}))
        ..on('GET', _capsPath, (_) => _caps('0.4.0'));

      final result = await installer().install();

      expect(result.ok, isTrue);
      expect(result.installedVersion, '0.4.0');
      expect(result.recheckFailed, isFalse);
      final data = http.to(_installPath).single.data;
      expect(data is String ? jsonDecode(data) : data, {
        'identifier': 'shreyas-kamat/iris#server/hermes-iris',
        'ref': _sha,
        'force': true,
        'enable': true,
      });
    });

    test('an unreleased build makes no request', () async {
      final result = await installer(
        const PluginRelease(
          version: '0.4.0',
          tag: 't',
          sha: '',
          repo: 'a/b',
          subdir: 'c',
        ),
      ).install();

      expect(result.ok, isFalse);
      expect(result.showCommand, isTrue);
      expect(result.error, 'This build of Iris has no released plugin yet.');
      expect(http.requests, isEmpty);
    });

    test(
      'ok false body: the reason from the server, and the command',
      () async {
        http.on(
          'POST',
          _installPath,
          (_) => FakeReply.json({'ok': false, 'error': 'scan blocked'}),
        );
        final result = await installer().install();
        expect(result.ok, isFalse);
        expect(result.error, 'scan blocked');
        expect(result.showCommand, isTrue);
      },
    );

    test('ok false without a reason still fails', () async {
      http.on('POST', _installPath, (_) => FakeReply.json({'ok': false}));
      final result = await installer().install();
      expect(result.ok, isFalse);
      expect(result.error, isNotEmpty);
    });

    test('a server without the route gets the command', () async {
      for (final status in [404, 405]) {
        http.on(
          'POST',
          _installPath,
          (_) => FakeReply.json({'detail': 'nope'}, status: status),
        );
        final result = await installer().install();
        expect(result.ok, isFalse, reason: '$status');
        expect(result.showCommand, isTrue, reason: '$status');
      }
    });

    test('a refused login says so and gets the command', () async {
      for (final status in [401, 403]) {
        http.on(
          'POST',
          _installPath,
          (_) => FakeReply.json({'detail': 'no'}, status: status),
        );
        final result = await installer().install();
        expect(result.error, 'Your login cannot install plugins.');
        expect(result.showCommand, isTrue, reason: '$status');
      }
    });

    test('a server error shows its message, without the command', () async {
      http.on(
        'POST',
        _installPath,
        (_) => FakeReply.json({'detail': 'git failed'}, status: 500),
      );
      final result = await installer().install();
      expect(result.ok, isFalse);
      expect(result.error, 'git failed');
      expect(result.showCommand, isFalse);
    });

    test('install ok, reprobe fails: installed, checked later', () async {
      http.on('POST', _installPath, (_) => FakeReply.json({'ok': true}));
      final result = await installer().install();
      expect(result.ok, isTrue);
      expect(result.recheckFailed, isTrue);
      expect(result.installedVersion, isNull);
    });
  });
}
