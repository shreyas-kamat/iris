/// Small lists the phone remembers for the person, none of which sync:
/// pinned conversations, where a branch came from, recent searches, and the
/// hosts whose Markdown images load without a tap.
///
/// Stored on the Preferences table like every other setting, and written
/// through the same controller, so a failed write is logged and never blocks
/// the screen that made it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prefs/json_list.dart';
import '../data/prefs/preferences_store.dart';
import 'preferences.dart';
import 'providers.dart';

/// `<server>/<profile>`: pins and branch links are per profile because a
/// conversation id belongs to one profile's database.
String? _profileScope(Ref ref, {bool watch = true}) {
  final server = watch
      ? ref.watch(activeServerIdProvider)
      : ref.read(activeServerIdProvider);
  if (server == null) return null;
  final profile = watch
      ? ref.watch(activeProfileProvider)
      : ref.read(activeProfileProvider);
  return '$server/$profile';
}

final pinsProvider = NotifierProvider<Pins, List<String>>(Pins.new);

/// Pinned conversation ids, newest pin first.
class Pins extends Notifier<List<String>> {
  String? _scope;

  @override
  List<String> build() {
    _scope = _profileScope(ref);
    if (_scope == null) return const [];
    return decodeStringList(
      ref.read(preferencesProvider)[(_scope!, PreferenceKeys.pins)],
    );
  }

  bool isPinned(String id) => state.contains(id);

  void pin(String id) => _set([id, ...state.where((p) => p != id)]);

  void unpin(String id) => _set([...state.where((p) => p != id)]);

  void toggle(String id) => isPinned(id) ? unpin(id) : pin(id);

  void _set(List<String> next) {
    state = next;
    final scope = _scope;
    if (scope == null) return;
    ref
        .read(preferencesProvider.notifier)
        .set(scope, PreferenceKeys.pins, encodeStringList(next));
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearches, List<String>>(RecentSearches.new);

/// The last few searches on this server, newest first.
class RecentSearches extends Notifier<List<String>> {
  static const limit = 6;

  String? _server;

  @override
  List<String> build() {
    _server = ref.watch(activeServerIdProvider);
    if (_server == null) return const [];
    return decodeStringList(
      ref.read(preferencesProvider)[(_server!, PreferenceKeys.searchRecent)],
    );
  }

  void add(String query) {
    final text = query.trim();
    if (text.isEmpty) return;
    final lowered = text.toLowerCase();
    _set(
      [
        text,
        ...state.where((q) => q.toLowerCase() != lowered),
      ].take(limit).toList(),
    );
  }

  void clear() => _set(const []);

  void _set(List<String> next) {
    state = next;
    final server = _server;
    if (server == null) return;
    ref
        .read(preferencesProvider.notifier)
        .set(server, PreferenceKeys.searchRecent, encodeStringList(next));
  }
}

final imageHostsProvider = NotifierProvider<ImageHosts, Set<String>>(
  ImageHosts.new,
);

/// Hosts the person said to load Markdown images from without asking.
class ImageHosts extends Notifier<Set<String>> {
  String? _server;

  @override
  Set<String> build() {
    _server = ref.watch(activeServerIdProvider);
    if (_server == null) return const {};
    return decodeStringList(
      ref.read(preferencesProvider)[(_server!, PreferenceKeys.imageHosts)],
    ).toSet();
  }

  void allow(String host) {
    final name = host.trim().toLowerCase();
    if (name.isEmpty || state.contains(name)) return;
    state = {...state, name};
    final server = _server;
    if (server == null) return;
    ref
        .read(preferencesProvider.notifier)
        .set(
          server,
          PreferenceKeys.imageHosts,
          encodeStringList(state.toList()),
        );
  }
}

/// Where a branch came from, kept so the new chat can say so after a
/// restart. Hermes's own `parent_session_id` also links context-compaction
/// chains, so it cannot tell a branch from a compaction.
@immutable
final class BranchRecord {
  const BranchRecord({
    required this.parentId,
    required this.parentTitle,
    required this.count,
  });

  /// Null for a value that is not a record.
  static BranchRecord? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final parent = decoded['parent'];
      if (parent is! String || parent.isEmpty) return null;
      final title = decoded['parentTitle'];
      final count = decoded['count'];
      return BranchRecord(
        parentId: parent,
        parentTitle: title is String ? title : '',
        count: count is int ? count : 0,
      );
    } on FormatException {
      return null;
    }
  }

  final String parentId;
  final String parentTitle;

  /// Messages copied from the parent.
  final int count;

  String toJson() => jsonEncode({
    'parent': parentId,
    'parentTitle': parentTitle,
    'count': count,
  });
}

/// The branch record for the conversation `childId` in the active profile.
final branchRecordProvider = Provider.family<BranchRecord?, String>((
  ref,
  childId,
) {
  final scope = _profileScope(ref);
  if (scope == null) return null;
  return BranchRecord.tryParse(
    ref.watch(preferencesProvider)[(scope, PreferenceKeys.branch(childId))],
  );
});

final branchRecordsProvider = Provider<BranchRecords>(BranchRecords.new);

/// Writes and removes branch records for the active profile.
final class BranchRecords {
  BranchRecords(this._ref);

  final Ref _ref;

  void save(String childId, BranchRecord record) {
    final scope = _profileScope(_ref, watch: false);
    if (scope == null) return;
    _ref
        .read(preferencesProvider.notifier)
        .set(scope, PreferenceKeys.branch(childId), record.toJson());
  }

  void forget(String childId) {
    final scope = _profileScope(_ref, watch: false);
    if (scope == null) return;
    _ref
        .read(preferencesProvider.notifier)
        .set(scope, PreferenceKeys.branch(childId), null);
  }
}
