/// What the person did with a generated display, reported to the plugin so it can learn which displays earn their
/// place (plan 6.1). Only ids and the signal's name are ever sent: never the display's content or the person's words.
library;

import 'dart:async';

import 'genui_api.dart';

enum DisplaySignal {
  /// The display stayed in view for a couple of seconds.
  used('used'),

  /// "Show all" was opened.
  expanded('expanded'),

  /// A reply kit was closed without using it.
  dismissed('dismissed'),

  /// The person said so, from the long-press menu.
  notUseful('not_useful');

  const DisplaySignal(this.wire);
  final String wire;
}

final class SignalEvent {
  const SignalEvent(this.signal, {this.surface, this.template, this.session});

  final DisplaySignal signal;
  final String? surface;
  final String? template;

  /// The stored conversation id.
  final String? session;

  Map<String, Object?> toJson() => {
    'signal': signal.wire,
    'surface': ?surface,
    'template': ?template,
    'session': ?session,
  };
}

/// Where a display reports what happened to it. The host fills in the conversation.
typedef SignalSink =
    void Function(DisplaySignal signal, {String? surface, String? template});

/// Collects signals and sends them in small batches: when ten are waiting, or twenty seconds after the first. It is
/// best effort: a batch that fails is dropped, and nothing here throws or waits for anything to be sent.
class SignalReporter {
  SignalReporter({
    required Future<GenUiApi?> Function() api,
    this.batchSize = 10,
    this.interval = const Duration(seconds: 20),
  }) : _api = api;

  final Future<GenUiApi?> Function() _api;
  final int batchSize;
  final Duration interval;

  final _queue = <SignalEvent>[];
  final _used = <String>{};
  Timer? _timer;
  bool _closed = false;

  void record(
    DisplaySignal signal, {
    String? surface,
    String? template,
    String? session,
  }) {
    if (_closed) return;
    // A display counts as used once in a conversation, however often it scrolls in and out of view.
    if (signal == DisplaySignal.used && !_used.add('$session/$surface')) return;
    _queue.add(
      SignalEvent(
        signal,
        surface: surface,
        template: template,
        session: session,
      ),
    );
    if (_queue.length >= batchSize) {
      unawaited(flush());
    } else {
      _timer ??= Timer(interval, () => unawaited(flush()));
    }
  }

  /// Sends what is waiting. Never throws.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;
    final batch = List.of(_queue);
    _queue.clear();
    try {
      final api = await _api();
      await api?.sendSignals(batch);
    } on Object {
      // Dropped: a missed signal costs nothing but a little learning.
    }
  }

  /// Sends what is left and stops taking more.
  void dispose() {
    if (_closed) return;
    unawaited(flush());
    _closed = true;
  }
}
