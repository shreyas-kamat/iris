/// The state store (language.md §5.1): a flat map from `$name` to value, scoped to one rendered program.
library;

/// Keys holding their declared default are *pristine*: a later parse may replace them (a default read from a
/// truncated statement, rule 6 of §4). A value the user or an action wrote, or one persisted by the host, is never
/// overwritten by a parse, and no parse deletes a key.
class StateStore {
  final _state = <String, Object?>{};
  final _pristine = <String>{};
  final _defaults = <String, Object?>{};
  final _listeners = <void Function()>[];

  Object? get(String name) => _state[name];

  bool has(String name) => _state.containsKey(name);

  /// A copy of the current values.
  Map<String, Object?> get snapshot => Map.unmodifiable(_state);

  /// Writes a value the user or an action produced. Listeners hear only real changes.
  void set(String name, Object? value) {
    _pristine.remove(name);
    _write(name, value);
  }

  /// Applies [defaults] from a parse and, first, [persisted] values from the host.
  void initialize(Map<String, Object?> defaults, {Map<String, Object?> persisted = const {}}) {
    var changed = false;
    for (final e in persisted.entries) {
      _pristine.remove(e.key);
      changed |= _put(e.key, e.value);
    }
    for (final e in defaults.entries) {
      _defaults[e.key] = e.value;
      if (!_state.containsKey(e.key)) {
        _pristine.add(e.key);
        changed |= _put(e.key, e.value);
      } else if (_pristine.contains(e.key)) {
        changed |= _put(e.key, e.value);
      }
    }
    if (changed) _notify();
  }

  /// `@Reset`: restores each declared default, or null when there is none. A reset value is a default again.
  void reset(Iterable<String> names) {
    var changed = false;
    for (final n in names) {
      _pristine.add(n);
      changed |= _put(n, _defaults[n]);
    }
    if (changed) _notify();
  }

  /// Calls [listener] after every change. Returns a function that removes it.
  void Function() listen(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _write(String name, Object? value) {
    if (_put(name, value)) _notify();
  }

  bool _put(String name, Object? value) {
    if (_state.containsKey(name) && _same(_state[name], value)) return false;
    _state[name] = value;
    return true;
  }

  static bool _same(Object? a, Object? b) {
    if (identical(a, b) || a == b) return true;
    if (a is Map && b is Map && a.length == b.length) {
      return a.keys.every((k) => b.containsKey(k) && (identical(a[k], b[k]) || a[k] == b[k]));
    }
    return false;
  }

  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
