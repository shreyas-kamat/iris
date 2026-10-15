/// How this phone reaches a Hermes server. It changes the connect screen's
/// wording, not how Iris connects: the probe works the same for all three.
library;

enum ConnectionMode {
  lan('lan'),
  tailscale('tailscale'),
  cloudflare('cloudflare');

  const ConnectionMode(this.storedName);

  /// What the database stores. Fixed strings, so renaming a case never
  /// orphans a saved server.
  final String storedName;

  /// The mode stored as [name], or null for none or an unknown name.
  static ConnectionMode? fromStoredName(String? name) {
    for (final mode in values) {
      if (mode.storedName == name) return mode;
    }
    return null;
  }
}
