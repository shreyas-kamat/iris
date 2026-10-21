/// The checks a chained call makes before it listens: the agent, then
/// speech-to-text, then text-to-speech, each against the real provider, so a
/// call never starts that cannot hear or speak.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/voice/speak_stream.dart';
import '../../data/voice/voice_backend.dart';
import '../chat/chat_controller.dart';
import 'chained_engine.dart';
import 'voice_call.dart';

/// Named in the failure copy when the server has no label.
const defaultServerName = 'your Hermes server';

const _phrase = 'Ready.';

/// 300 ms of 16 kHz silence: speech-to-text answers it with `ok ""`.
Uint8List silentWav() => wavOf(Uint8List(16000 * 2 * 3 ~/ 10));

/// Ok when all three pass. The failure's message is B10b's line naming the
/// part that did not answer: "Iris can't reach speech-to-text on {server}".
/// Each check has [budget]; nothing is recorded meanwhile.
Future<Result<void>> chainedPreflight({
  required ChatController chat,
  required VoiceBackend voice,
  required void Function(PreflightStep step) onStep,
  String server = defaultServerName,
  Duration budget = const Duration(seconds: 20),
}) async {
  final checks = <(PreflightStep, String, Future<bool> Function())>[
    (PreflightStep.agent, 'the agent', chat.ensureLive),
    (PreflightStep.speechToText, 'speech-to-text', () => _hears(voice)),
    (PreflightStep.textToSpeech, 'text-to-speech', () => _speaks(voice)),
  ];
  for (final (step, part, check) in checks) {
    onStep(step);
    var late = false;
    final passed = await check().timeout(
      budget,
      onTimeout: () {
        late = true;
        return false;
      },
    );
    if (!passed) {
      return Err(
        IrisFailure(
          late ? FailureKind.timeout : FailureKind.server,
          message: "Iris can't reach $part on $server",
        ),
      );
    }
  }
  return const Ok(null);
}

/// Any `ok` passes; an empty transcript is the expected answer. The lease
/// only warms the provider, so its own answer does not matter.
Future<bool> _hears(VoiceBackend voice) async {
  await voice.lease(speech: false, active: true);
  return (await voice.transcribe(silentWav())).isOk;
}

/// A `start` and some audio from the speak stream pass; the audio is
/// discarded. Otherwise one-shot speech must work.
Future<bool> _speaks(VoiceBackend voice) async {
  await voice.lease(speech: true, active: true);
  final opened = await voice.openSocket('/api/audio/speak-stream');
  if (opened case Ok(value: final socket)) {
    final speak = SpeakStream(socket)
      ..add(_phrase)
      ..done();
    final heard = Completer<bool>();
    var started = false;
    // Not `await for`: leaving one early waits on the cancel.
    final frames = speak.frames.listen(
      (frame) {
        if (frame is SpeakStart) {
          started = true;
        } else if (frame is SpeakPcm && started && !heard.isCompleted) {
          heard.complete(true);
        }
      },
      onDone: () {
        if (!heard.isCompleted) heard.complete(false);
      },
    );
    final passed = await heard.future;
    unawaited(frames.cancel());
    if (passed) {
      unawaited(speak.stop());
      return true;
    }
  }
  return (await voice.speakOnce(_phrase)).isOk;
}
