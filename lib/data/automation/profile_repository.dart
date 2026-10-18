/// Profile management: create, rename, edit the SOUL, delete.
///
/// Listing stays on `ChatBackend.profiles()` and `profilesProvider`, which
/// already read `GET /api/profiles`.
library;

import '../../core/result.dart';
import '../net/api_client.dart';

/// What a new profile starts from.
enum ProfileStart { blank, copy, full }

abstract final class ProfileName {
  static final _valid = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  /// An error to show under the field, or null when [name] is acceptable.
  /// An empty name is not an error: nothing has been typed yet.
  static String? problem(String name) {
    if (name.isEmpty) return null;
    if (_valid.hasMatch(name)) return null;
    return 'Lowercase letters, digits, - and _ only';
  }

  static bool isValid(String name) => _valid.hasMatch(name);
}

final class ProfileDraft {
  const ProfileDraft({
    required this.name,
    this.start = ProfileStart.blank,
    this.source = 'default',
    this.soul,
  });

  final String name;
  final ProfileStart start;

  /// The profile copied from when [start] is not blank.
  final String source;
  final String? soul;

  Map<String, Object?> toBody() => {
    'name': name,
    if (soul != null && soul!.trim().isNotEmpty) 'soul': soul!.trim(),
    if (start != ProfileStart.blank)
      if (source == 'default')
        'clone_from_default': true
      else
        'clone_from': source,
    if (start == ProfileStart.full) 'clone_all': true,
  };
}

abstract interface class ProfileRepository {
  Future<Result<void>> create(ProfileDraft draft);
  Future<Result<void>> rename(String name, String newName);
  Future<Result<String>> soul(String name);
  Future<Result<void>> setSoul(String name, String content);
  Future<Result<void>> delete(String name);
}

final class DashboardProfileRepository implements ProfileRepository {
  DashboardProfileRepository(this._client);

  final ApiClient _client;

  /// Creating a profile copies skills, which can take a while.
  static const createTimeout = Duration(seconds: 90);

  static String _path(String name, [String suffix = '']) =>
      '/api/profiles/${Uri.encodeComponent(name)}$suffix';

  @override
  Future<Result<void>> create(ProfileDraft draft) async => (await _client.post(
    '/api/profiles',
    body: draft.toBody(),
    receiveTimeout: createTimeout,
  )).map((_) {});

  @override
  Future<Result<void>> rename(String name, String newName) async =>
      (await _client.patch(_path(name), body: {'new_name': newName})).map(
        (_) {},
      );

  @override
  Future<Result<String>> soul(String name) async =>
      (await _client.get(_path(name, '/soul'))).map(
        (body) => body['content'].string(),
      );

  @override
  Future<Result<void>> setSoul(String name, String content) async =>
      (await _client.put(_path(name, '/soul'), body: {'content': content}))
          .map((_) {});

  @override
  Future<Result<void>> delete(String name) async =>
      (await _client.delete(_path(name))).map((_) {});
}
