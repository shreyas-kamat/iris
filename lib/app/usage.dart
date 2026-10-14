/// Which providers' subscription usage home shows, and what they report.
///
/// Usage comes from `model.options`, which reads a server-side cache and
/// starts a background fetch when the cache is cold, so a first ask can come
/// back empty and a second, a few seconds later, full. That second ask happens
/// once, here, not in a loop.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/result.dart';
import '../data/chat/chat_models.dart';
import '../data/prefs/preferences_store.dart';
import '../data/rpc/dashboard_session.dart';
import 'preferences.dart';
import 'providers.dart';

/// Stands for the active profile's own provider in the saved list.
const usageFollowsProfile = '@profile';

final usageSelectionProvider = NotifierProvider<UsageSelection, List<String>>(
  UsageSelection.new,
);

/// The providers home shows, in order: Main, then Secondary, then any others.
class UsageSelection extends Notifier<List<String>> {
  static const fallback = [usageFollowsProfile];

  @override
  List<String> build() {
    final server = ref.watch(activeServerIdProvider);
    if (server == null) return fallback;
    final raw = ref.read(preferencesProvider)[(
      server,
      PreferenceKeys.usageProviders,
    )];
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final slugs = [
          for (final slug in decoded)
            if (slug is String && slug.isNotEmpty) slug,
        ];
        if (slugs.isNotEmpty) return slugs;
      }
    } on FormatException {
      // A damaged value is the default, not an error on screen.
    }
    return fallback;
  }

  void setAll(List<String> slugs) {
    final cleaned = <String>[];
    for (final slug in slugs) {
      if (slug.isNotEmpty && !cleaned.contains(slug)) cleaned.add(slug);
    }
    final next = cleaned.isEmpty ? fallback : cleaned;
    state = next;
    final server = ref.read(activeServerIdProvider);
    if (server == null) return;
    ref
        .read(preferencesProvider.notifier)
        .set(
          server,
          PreferenceKeys.usageProviders,
          listEquals(next, fallback) ? null : jsonEncode(next),
        );
  }
}

/// How long to wait before asking again when the gateway had no numbers yet.
final usageRetryDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// The active profile's own provider, from `GET /api/profiles`, when known.
final _profileProviderSlug = Provider<String?>((ref) {
  final name = ref.watch(activeProfileProvider);
  final profiles = ref.watch(profilesProvider).value ?? const <AgentProfile>[];
  for (final profile in profiles) {
    if (profile.name == name) return profile.provider;
  }
  return null;
});

/// What the gateway reports about its providers, asked a second time when
/// the first answer had no usage for a signed-in provider.
final usageOptionsProvider = FutureProvider<ModelOptions?>((ref) async {
  final live = ref.watch(
    activeLinkProvider.select((link) => link.value?.phase == LinkPhase.live),
  );
  if (!live) return null;
  final delay = ref.watch(usageRetryDelayProvider);
  final chat = await ref.watch(activeChatProvider.future);
  if (chat == null) return null;
  final first = switch (await chat.modelOptions()) {
    Ok(:final value) => value,
    Err() => null,
  };
  if (first == null || !_cold(first)) return first;
  await Future<void>.delayed(delay);
  return switch (await chat.modelOptions()) {
    Ok(:final value) => value,
    Err() => first,
  };
});

/// No provider reports usage yet, though one is signed in: the cache was
/// cold, and the first ask started filling it.
bool _cold(ModelOptions options) =>
    options.providers.every((p) => p.usage == null) &&
    options.providers.any((p) => p.authenticated || p.isCurrent);

/// One provider row home shows.
@immutable
final class UsageRow {
  const UsageRow({required this.slug, required this.name, required this.usage});

  final String slug;
  final String name;
  final ProviderUsage usage;
}

/// The rows to show for [wanted], in order, without repeats, leaving out
/// providers that report no usage.
List<UsageRow> resolveUsageRows(
  List<String> wanted,
  ModelOptions options, {
  String? profileProvider,
}) {
  final bySlug = {for (final p in options.providers) p.slug: p};
  final seen = <String>{};
  final rows = <UsageRow>[];
  for (final entry in wanted) {
    final slug = entry == usageFollowsProfile
        ? (profileProvider ?? options.provider)
        : entry;
    if (slug == null || !seen.add(slug)) continue;
    final provider = bySlug[slug];
    final usage = provider?.usage;
    if (provider == null || usage == null) continue;
    rows.add(UsageRow(slug: slug, name: provider.name, usage: usage));
  }
  return rows;
}

/// The rows home shows.
final providerUsageProvider = Provider<AsyncValue<List<UsageRow>>>((ref) {
  final wanted = ref.watch(usageSelectionProvider);
  final profileProvider = ref.watch(_profileProviderSlug);
  return ref
      .watch(usageOptionsProvider)
      .whenData(
        (options) => options == null
            ? const <UsageRow>[]
            : resolveUsageRows(
                wanted,
                options,
                profileProvider: profileProvider,
              ),
      );
});
