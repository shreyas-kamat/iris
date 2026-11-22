/// The one release of the hermes-iris plugin this build of Iris installs.
///
/// Pinned to a commit, never to a branch: a server must not run plugin code newer than the app expects.
library;

/// A released plugin: where Hermes fetches it and which commit it is.
final class PluginRelease {
  const PluginRelease({
    required this.version,
    required this.tag,
    required this.sha,
    required this.repo,
    required this.subdir,
  });

  /// What this build installs: the commit behind the annotated tag `hermes-iris-v0.4.0`
  /// (`git rev-parse hermes-iris-v0.4.0^{commit}`).
  static const current = PluginRelease(
    version: '0.4.0',
    tag: 'hermes-iris-v0.4.0',
    sha: 'fbb076d55a8a796ce8d47b11581d19ebe7483cde',
    repo: 'shreyas-kamat/iris',
    subdir: 'server/hermes-iris',
  );

  final String version;
  final String tag;

  /// The full 40-character commit, lower-case hex. Hermes accepts nothing shorter for a pin.
  final String sha;

  /// `owner/name` on GitHub.
  final String repo;

  /// The plugin's folder inside [repo].
  final String subdir;

  /// The source in the form Hermes's installer takes: `owner/repo#subdir`.
  String get identifier => '$repo#$subdir';

  /// What to run on the server to do the same by hand.
  String get fallbackCommand =>
      'hermes plugins install $identifier --force --ref $sha';

  bool get released => RegExp(r'^[0-9a-f]{40}$').hasMatch(sha);
}

/// Orders two versions by their numeric parts, so `0.10.0` is after `0.9.0`. A missing or non-numeric part counts as 0
/// and a `-suffix` is ignored.
int compareVersions(String a, String b) {
  List<int> parts(String version) => [
    for (final part in version.split('-').first.split('.'))
      int.tryParse(part) ?? 0,
  ];
  final left = parts(a);
  final right = parts(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}
