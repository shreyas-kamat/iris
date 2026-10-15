/// Phase 5's two new calls against a real dashboard: stage a file with
/// `file.attach`, and transcribe a clip of silence.
///
/// It creates a conversation on the server, so it runs only when asked for:
///   flutter test --tags live_write --run-skipped test/live/phase5_live_test.dart
/// Prints result shapes only, never content.
@Tags(['live_write'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/attachment.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

/// [seconds] of 16 kHz mono silence as a WAV file.
Uint8List silentWav({required int seconds}) {
  const rate = 16000;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  late DashboardSession session;
  late DashboardChat chat;

  setUp(() async {
    final json = Json.decode(
      File(
        '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}'
        '/.iris-live.json',
      ).readAsStringSync(),
    );
    final connection = ServerConnection.create(
      ServerConfig(
        id: 'live',
        baseUrl: ServerConfig.normaliseBaseUrl(json['base_url'].string()),
        label: 'live',
      ),
      secrets: ServerSecrets(
        username: json['username'].stringOrNull,
        password: json['password'].stringOrNull,
        accessClientId: json['cf_client_id'].stringOrNull,
        accessClientSecret: json['cf_client_secret'].stringOrNull,
      ),
    );
    session = DashboardSession(http: connection);
    chat = DashboardChat(session);
    addTearDown(() async {
      await chat.dispose();
      await session.dispose();
      connection.close();
    });
    await session.start();
    expect(session.state.phase, LinkPhase.live);
  });

  test('file.attach stages a file and returns a reference', () async {
    final created = (await chat.create()).valueOrNull!;
    final ref = await chat.attach(
      created.runtimeId,
      Attachment(
        name: 'iris-live.txt',
        bytes: Uint8List.fromList(utf8.encode('hello')),
      ),
    );
    // ignore: avoid_print
    print('attach -> ${ref.isOk ? 'ok' : 'failed: ${ref.failureOrNull?.message}'}');
    expect(ref.valueOrNull, startsWith('@file:'));
  });

  test('transcribe answers with text or a clear error', () async {
    final result = await chat.transcribe(silentWav(seconds: 1));
    switch (result) {
      case Ok(:final value):
        // ignore: avoid_print
        print('transcribe -> ok (${value.length} chars)');
      case Err(:final failure):
        // ignore: avoid_print
        print('transcribe -> failed: ${failure.message}');
        expect(failure.message, isNotEmpty);
    }
  });
}
