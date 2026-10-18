/// Everything Iris asks of a server's voice: config, speech in and out, the
/// warm-up leases, the voice write, the GPT-Live session and the two audio
/// sockets.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import '../rpc/dashboard_session.dart';
import 'audio_socket.dart';
import 'voice_capabilities.dart';
import 'voice_catalog.dart';

const _log = IrisLog('voice');

/// One spoken reply, whole.
final class SpokenAudio {
  const SpokenAudio(this.bytes, this.mime);

  final Uint8List bytes;
  final String mime;
}

/// The server's answer to a GPT-Live offer.
final class GptLiveAnswer {
  const GptLiveAnswer({required this.sessionId, required this.sdp});

  final String sessionId;
  final String sdp;
}

abstract interface class VoiceBackend {
  /// What this server and profile can do by voice.
  Future<Result<VoiceCapabilities>> capabilities();

  /// The words in a WAV clip. Silence is `Ok('')`, not an error.
  Future<Result<String>> transcribe(Uint8List wav);

  /// [text] synthesised in one piece; the fallback for a failed speak stream.
  Future<Result<SpokenAudio>> speakOnce(String text);

  /// Warms the speech-to-text ([speech] false) or text-to-speech provider, or
  /// releases it.
  Future<Result<void>> lease({required bool speech, required bool active});

  /// The server's own voice list (ElevenLabs); `Ok([])` when it has none.
  Future<Result<List<VoiceChoice>>> serverVoices();

  /// Writes one dotted config [key] (e.g. `tts.edge.voice`) and nothing else.
  Future<Result<void>> setVoice(String key, String voice);

  /// Offers [sdp] to GPT-Live and returns the server's answer.
  Future<Result<GptLiveAnswer>> startGptLive(
    String sdp,
    List<Map<String, Object?>> history,
  );

  /// Opens `/api/audio/speak-stream` or `/api/audio/transcribe-stream`.
  Future<Result<AudioSocket>> openSocket(String route);
}

/// [VoiceBackend] over the dashboard: REST for the calls, a fresh ticket per
/// audio socket.
final class DashboardVoice implements VoiceBackend {
  DashboardVoice(
    this._session, {
    this.profile = 'default',
    AudioConnector? connector,
  }) : _connector =
           connector ??
           ((uri, headers) => IoAudioSocket.connect(
             uri,
             headers,
             client: _session.connection.socketHttpClient(),
           ));

  final DashboardSession _session;
  final String profile;
  final AudioConnector _connector;

  /// Names this device's hold on a provider, so two devices do not release
  /// each other's warm-up.
  static const _leaseName = 'iris-voice';

  /// A whole reply can take a while to synthesise on a small host.
  static const _speakTimeout = Duration(seconds: 90);
  static const _transcribeTimeout = Duration(seconds: 90);

  /// Every audio and config route is scoped to the profile explicitly, the
  /// default profile included.
  Map<String, Object?> get _query => {'profile': profile};

  @override
  Future<Result<VoiceCapabilities>> capabilities() async {
    final client = _session.connection.client;
    final config = await client.get('/api/config', query: _query);
    if (config case Err(:final failure)) return Err(failure);
    final status = await client.get(
      '/api/audio/voice-live/status',
      query: _query,
    );
    Json? live;
    switch (status) {
      case Ok(:final value):
        live = value;
      case Err(:final failure) when failure.kind == FailureKind.notFound:
        live = null;
      case Err(:final failure):
        return Err(failure);
    }
    return Ok(
      VoiceCapabilities.fromServer(
        config: config.valueOrNull!,
        liveStatus: live,
      ),
    );
  }

  @override
  Future<Result<String>> transcribe(Uint8List wav) async {
    const route = '/api/audio/transcribe';
    final sent = await _session.connection.client.post(
      route,
      body: {
        'data_url': 'data:audio/wav;base64,${base64Encode(wav)}',
        'mime_type': 'audio/wav',
      },
      query: _query,
      receiveTimeout: _transcribeTimeout,
    );
    switch (sent) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final words =
            value['transcript'].stringOrNull ?? value['text'].stringOrNull;
        if (words != null) return Ok(words.trim());
        // `ok` with nothing said is how the server reports silence.
        if (value['ok'].boolOrNull ?? false) return const Ok('');
        return const Err(
          IrisFailure(
            FailureKind.malformed,
            message: 'The server did not return a transcript.',
            endpoint: route,
          ),
        );
    }
  }

  @override
  Future<Result<SpokenAudio>> speakOnce(String text) async {
    const route = '/api/audio/speak';
    final sent = await _session.connection.client.post(
      route,
      body: {'text': text},
      query: _query,
      receiveTimeout: _speakTimeout,
    );
    switch (sent) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final url = value['data_url'].stringOrNull;
        final comma = url?.indexOf(',') ?? -1;
        if (url == null || !url.startsWith('data:') || comma < 0) {
          return const Err(
            IrisFailure(
              FailureKind.malformed,
              message: 'The server did not return any audio.',
              endpoint: route,
            ),
          );
        }
        final header = url.substring(5, comma);
        final mime = value['mime_type'].stringOrNull ?? header.split(';').first;
        try {
          return Ok(
            SpokenAudio(
              base64Decode(url.substring(comma + 1)),
              mime.isEmpty ? 'audio/mpeg' : mime,
            ),
          );
        } on FormatException {
          return const Err(
            IrisFailure(
              FailureKind.malformed,
              message: 'The server returned audio Iris could not read.',
              endpoint: route,
            ),
          );
        }
    }
  }

  @override
  Future<Result<void>> lease({
    required bool speech,
    required bool active,
  }) async {
    final route = '/api/audio/${speech ? 'tts' : 'stt'}-lease';
    final sent = await _session.connection.client.post(
      route,
      body: {'lease': _leaseName, 'active': active},
      query: _query,
    );
    return switch (sent) {
      Err(:final failure) => Err(failure),
      // Lease trouble is reported in the body, never as an HTTP error.
      Ok(:final value) when value['ok'].boolOrNull == false => Err(
        IrisFailure(
          FailureKind.rejected,
          message: value['error'].stringOrNull,
          endpoint: route,
        ),
      ),
      Ok() => const Ok(null),
    };
  }

  @override
  Future<Result<List<VoiceChoice>>> serverVoices() async {
    final sent = await _session.connection.client.get(
      '/api/audio/elevenlabs/voices',
      query: _query,
    );
    switch (sent) {
      case Err(:final failure) when failure.kind == FailureKind.notFound:
        return const Ok([]);
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        if (!(value['available'].boolOrNull ?? false)) return const Ok([]);
        return Ok(
          value['voices'].mapList((voice) {
            final id = voice['voice_id'].stringOrNull;
            if (id == null || id.isEmpty) return null;
            final label =
                voice['label'].stringOrNull ?? voice['name'].stringOrNull;
            return VoiceChoice(id, label == null || label.isEmpty ? id : label);
          }),
        );
    }
  }

  @override
  Future<Result<void>> setVoice(String key, String voice) async {
    final client = _session.connection.client;
    // The server has no single-key write for these settings, so the
    // profile's own document is read (without defaults, which would be
    // written back as if the user had chosen them), one key changed, and the
    // whole thing put back.
    final read = await client.get(
      '/api/config',
      query: {'include_defaults': 'false', ..._query},
    );
    if (read case Err(:final failure)) return Err(failure);

    final document = _copyMap(read.valueOrNull!.raw);
    final parts = key.split('.');
    var node = document;
    for (final part in parts.take(parts.length - 1)) {
      final next = node[part];
      if (next is Map<String, Object?>) {
        node = next;
      } else {
        final created = <String, Object?>{};
        node[part] = created;
        node = created;
      }
    }
    node[parts.last] = voice;

    final written = await client.put(
      '/api/config',
      body: {'config': document},
      query: _query,
    );
    return written.map((_) {});
  }

  @override
  Future<Result<GptLiveAnswer>> startGptLive(
    String sdp,
    List<Map<String, Object?>> history,
  ) async {
    const route = '/api/audio/voice-live/session';
    final sent = await _session.connection.client.post(
      route,
      body: {'sdp': sdp, if (history.isNotEmpty) 'history': history},
      query: _query,
      receiveTimeout: const Duration(seconds: 30),
    );
    switch (sent) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final id = value['session']['id'].stringOrNull;
        final answer = value['transport']['sdp'].stringOrNull;
        if (id == null || answer == null || answer.isEmpty) {
          return const Err(
            IrisFailure(
              FailureKind.malformed,
              message: 'The server did not return a GPT-Live session.',
              endpoint: route,
            ),
          );
        }
        return Ok(GptLiveAnswer(sessionId: id, sdp: answer));
    }
  }

  @override
  Future<Result<AudioSocket>> openSocket(String route) async {
    final ticket = await _session.connection.auth.mintTicket();
    if (ticket case Err(:final failure)) return Err(failure);

    final base = _session.connection.config.uri;
    final path = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$path$route',
      queryParameters: {'ticket': ticket.valueOrNull!, 'profile': profile},
    );
    try {
      return Ok(
        await _connector(uri, _session.connection.accessHeadersFor(uri)),
      );
    } on Object catch (error, stackTrace) {
      final kind = switch (error) {
        TimeoutException() => FailureKind.timeout,
        TlsException() => FailureKind.tls,
        SocketException() => FailureKind.offline,
        WebSocketException() => FailureKind.rejected,
        _ => FailureKind.unknown,
      };
      // The exception text can include the URL, and the URL the ticket.
      _log.warn(
        'audio socket open failed: ${kind.name}',
        data: IrisLog.redact('$error'),
      );
      return Err(
        IrisFailure(
          kind,
          message: kind == FailureKind.rejected
              ? 'The server refused the audio connection.'
              : null,
          endpoint: route,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// A deep copy of a decoded JSON object, so the original is never edited.
  static Map<String, Object?> _copyMap(Object? source) =>
      source is Map ? _copy(source) as Map<String, Object?> : {};

  static Object? _copy(Object? value) => switch (value) {
    Map() => {
      for (final entry in value.entries) '${entry.key}': _copy(entry.value),
    },
    List() => [for (final item in value) _copy(item)],
    _ => value,
  };
}
