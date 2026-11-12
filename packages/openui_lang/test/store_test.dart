import 'package:openui_lang/openui_lang.dart';
import 'package:test/test.dart';

/// The state store (language.md §5.1, §4 rule 6).
void main() {
  test('defaults apply when a key has no value', () {
    final s = StateStore()..initialize({r'$a': 1.0});
    expect(s.get(r'$a'), 1.0);
    expect(s.snapshot, {r'$a': 1.0});
  });

  test('a later parse replaces a default the user has not changed', () {
    final s = StateStore()..initialize({r'$t': 'Hel'});
    s.initialize({r'$t': 'Hello'});
    expect(s.get(r'$t'), 'Hello');
  });

  test('a later parse never clobbers a value the user changed', () {
    final s = StateStore()..initialize({r'$t': 'a'});
    s.set(r'$t', 'mine');
    s.initialize({r'$t': 'b'});
    expect(s.get(r'$t'), 'mine');
  });

  test('persisted state wins over defaults and is not replaced later', () {
    final s = StateStore()..initialize({r'$t': 'a'}, persisted: {r'$t': 'saved'});
    expect(s.get(r'$t'), 'saved');
    s.initialize({r'$t': 'b'});
    expect(s.get(r'$t'), 'saved');
  });

  test('parsing again never deletes a key', () {
    final s = StateStore()..initialize({r'$a': 1.0, r'$b': 2.0});
    s.initialize({r'$a': 1.0});
    expect(s.snapshot.keys, containsAll([r'$a', r'$b']));
  });

  test('reset restores the declared default, or null', () {
    final s = StateStore()..initialize({r'$a': 1.0});
    s.set(r'$a', 5.0);
    s.set(r'$x', 'free');
    s.reset([r'$a', r'$x']);
    expect(s.get(r'$a'), 1.0);
    expect(s.get(r'$x'), isNull);
    s.initialize({r'$a': 2.0});
    expect(s.get(r'$a'), 2.0, reason: 'a reset value is a default again');
  });

  test('listeners hear changes, not no-ops', () {
    final s = StateStore()..initialize({r'$a': 1.0});
    var calls = 0;
    final off = s.listen(() => calls++);
    s.set(r'$a', 1.0);
    expect(calls, 0);
    s.set(r'$a', 2.0);
    expect(calls, 1);
    off();
    s.set(r'$a', 3.0);
    expect(calls, 1);
  });
}
