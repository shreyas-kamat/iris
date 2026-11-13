/// How a conversation is opened: the route that builds [ChatScreen] with everything the app gives it (voice, the
/// branch record, generated-display signals). Home's list and a tap on a notification open a chat the same way.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/device_state.dart';
import '../../app/genui_providers.dart';
import '../../app/providers.dart';
import '../../app/voice_providers.dart';
import '../../data/chat/chat_backend.dart';
import '../../data/push/push_intents.dart';
import '../../demo/demo_content.dart';
import '../../demo/demo_mode.dart';
import '../../demo/demo_voice.dart';
import '../../design/platform/platform_feel.dart';
import '../voice/preflight.dart' show defaultServerName;
import '../voice/voice_host.dart';
import 'chat_screen.dart';

/// The host part of the server's address, for the gateway line. A full URL is too long for a line of mono text; the
/// host is what identifies it.
String serverHostOf(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  return host.isEmpty ? baseUrl : host;
}

/// Voice for a chat, once the server's capabilities have been read and say there is something to offer. Null
/// otherwise, so nothing is drawn that might then fail.
VoiceHost? voiceHostFor(WidgetRef ref, String? storedId) {
  final backend = ref.watch(activeVoiceProvider).value;
  final capabilities = ref.watch(voiceCapabilitiesProvider).value;
  final server = ref.watch(activeServerProvider);
  if (backend == null || capabilities == null || !capabilities.voiceMode) {
    return null;
  }
  return VoiceHost(
    backend: backend,
    capabilities: capabilities,
    spans: storedId == null
        ? const []
        : ref.watch(voiceCallSpansProvider(storedId)),
    onCallEnded: (id, span) =>
        ref.read(voiceCallSpansWriterProvider).add(id, span),
    settings: ref.watch(voiceSettingsProvider),
    server: server == null ? defaultServerName : serverHostOf(server.baseUrl),
    parts: ref.watch(demoModeProvider) ? demoCallParts : CallParts.platform,
  );
}

/// The route to the conversation [conversationId] (a new chat when null). [pushTap] is the notification
/// that opened it, if one did; its button is applied once the chat is open.
Route<void> chatRoute(
  ChatBackend chat, {
  String? conversationId,
  String? title,
  BranchRecord? branch,
  ChatMenuHooks? menu,
  PushTap? pushTap,
}) => IrisPageRoute<void>(
  // A consumer, so the voice button appears when the capability read lands even if the chat opened before it did.
  builder: (_) => Consumer(
    builder: (context, ref, _) => ChatScreen(
      suggestions: ref.read(demoModeProvider)
          ? [for (final script in demoScripts) script.prompt]
          : null,
      backend: chat,
      voice: voiceHostFor(ref, conversationId),
      conversationId: conversationId,
      title: title,
      branch:
          branch ??
          (conversationId == null
              ? null
              : ref.read(branchRecordProvider(conversationId))),
      onBranched: (childId, record) =>
          ref.read(branchRecordsProvider).save(childId, record),
      menu: menu,
      signals: ref.watch(signalReporterProvider),
      pushTap: pushTap,
    ),
  ),
);
