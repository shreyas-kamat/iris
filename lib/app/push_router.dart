/// Opens the right screen for a tap on a notification: a chat for a reply or an approval, a job's page for a finished
/// job. The native side (Tasks 9 and 10) calls [PushRouter.open] with the tap it read from the notification.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../data/push/push_intents.dart';
import '../design/platform/platform_feel.dart';
import '../features/chat/chat_route.dart';
import '../features/scheduled/job_detail_screen.dart';
import 'automation_providers.dart';
import 'providers.dart';

/// The navigator the app's `MaterialApp` uses, so a notification can open a screen from outside any widget.
final GlobalKey<NavigatorState> irisNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'iris',
);

final pushRouterProvider = Provider<PushRouter>(PushRouter.new);

class PushRouter {
  PushRouter(this._ref);

  static const _log = IrisLog('push');

  final Ref _ref;

  /// Shows what [tap] is about, over home. Whatever was open is closed first, so a notification never stacks a second
  /// copy of the chat the person is already in. A tap that names nothing Iris can open does nothing.
  Future<void> open(PushTap tap) async {
    switch (tap.kind) {
      case 'reply' || 'approval':
        await _openChat(tap);
      case 'job':
        await _openJob(tap);
      default:
        return;
    }
  }

  /// Opens [tap] once the app has a server and a screen to open it on: a cold start from a notification has neither
  /// at first. Gives up after about ten seconds.
  void openWhenReady(PushTap tap) {
    Future<void> attempt(int tries) async {
      final ready =
          _ref.read(activeServerProvider) != null &&
          irisNavigatorKey.currentState != null;
      if (ready) {
        await open(tap);
      } else if (tries < 40) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await attempt(tries + 1);
      } else {
        _log.warn('a notification tap found nothing to open');
      }
    }

    unawaited(attempt(0));
  }

  Future<void> _openChat(PushTap tap) async {
    final chat = await _ref.read(activeChatProvider.future);
    final navigator = irisNavigatorKey.currentState;
    if (chat == null || navigator == null) {
      _log.warn('a notification arrived with no server or screen to open');
      return;
    }
    navigator
      ..popUntil((route) => route.isFirst)
      ..push(chatRoute(chat, conversationId: tap.sessionId, pushTap: tap));
  }

  Future<void> _openJob(PushTap tap) async {
    final id = tap.jobId;
    final repository = await _ref.read(cronRepositoryProvider.future);
    final navigator = irisNavigatorKey.currentState;
    if (id == null || repository == null || navigator == null) return;
    final job = (await repository.job(id)).valueOrNull;
    if (job == null) return;
    navigator
      ..popUntil((route) => route.isFirst)
      ..push(
        IrisPageRoute<void>(builder: (_) => JobDetailScreen(initial: job)),
      );
  }
}
