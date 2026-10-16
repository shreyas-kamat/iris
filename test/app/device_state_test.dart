import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/device_state.dart';
import 'package:iris/app/preferences.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/prefs/preferences_store.dart';

void main() {
  late MemoryPreferencesStore store;
  late ProviderContainer container;

  setUp(() {
    store = MemoryPreferencesStore();
    container = ProviderContainer(
      overrides: [preferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container.read(activeServerIdProvider.notifier).select('srv');
  });

  group('pins', () {
    test('pin puts the newest first and persists per server and profile', () {
      final pins = container.read(pinsProvider.notifier);
      pins.pin('a');
      pins.pin('b');
      expect(container.read(pinsProvider), ['b', 'a']);
      expect(store.values[('srv/default', PreferenceKeys.pins)], '["b","a"]');
    });

    test('pinning twice moves it to the front, unpinning removes it', () {
      final pins = container.read(pinsProvider.notifier)
        ..pin('a')
        ..pin('b')
        ..pin('a');
      expect(container.read(pinsProvider), ['a', 'b']);
      pins.unpin('a');
      expect(container.read(pinsProvider), ['b']);
      pins.unpin('b');
      expect(store.values.containsKey(('srv/default', PreferenceKeys.pins)), isFalse);
    });

    test('pins follow the profile', () {
      container.read(pinsProvider.notifier).pin('a');
      container.read(activeProfileProvider.notifier).select('ananta');
      expect(container.read(pinsProvider), isEmpty);
      container.read(pinsProvider.notifier).pin('z');
      container.read(activeProfileProvider.notifier).select('default');
      expect(container.read(pinsProvider), ['a']);
    });

    test('toggle pins then unpins', () {
      final pins = container.read(pinsProvider.notifier);
      pins.toggle('a');
      expect(pins.isPinned('a'), isTrue);
      pins.toggle('a');
      expect(pins.isPinned('a'), isFalse);
    });
  });

  group('recent searches', () {
    test('newest first, no duplicates ignoring case, at most six', () {
      final recent = container.read(recentSearchesProvider.notifier);
      for (final q in ['one', 'two', 'three', 'four', 'five', 'six', 'seven']) {
        recent.add(q);
      }
      expect(container.read(recentSearchesProvider), ['seven', 'six', 'five', 'four', 'three', 'two']);
      recent.add('SIX');
      expect(container.read(recentSearchesProvider).first, 'SIX');
      expect(container.read(recentSearchesProvider).where((q) => q.toLowerCase() == 'six'), hasLength(1));
    });

    test('blank queries are not remembered, and clear empties the list', () {
      final recent = container.read(recentSearchesProvider.notifier)
        ..add('   ')
        ..add('heartbeat');
      expect(container.read(recentSearchesProvider), ['heartbeat']);
      recent.clear();
      expect(container.read(recentSearchesProvider), isEmpty);
    });
  });

  group('image hosts', () {
    test('allow remembers a host, lower-cased, once', () {
      final hosts = container.read(imageHostsProvider.notifier)
        ..allow('Grafana.Local')
        ..allow('grafana.local');
      expect(container.read(imageHostsProvider), {'grafana.local'});
      expect(hosts.state, {'grafana.local'});
    });
  });

  group('branch records', () {
    test('save, read back and forget', () {
      final records = container.read(branchRecordsProvider);
      records.save('child', const BranchRecord(parentId: 'p', parentTitle: 'Parent', count: 4));
      expect(container.read(branchRecordProvider('child'))?.parentTitle, 'Parent');
      records.forget('child');
      expect(container.read(branchRecordProvider('child')), isNull);
    });

    test('a damaged record reads as none', () {
      container.read(preferencesProvider.notifier).set('srv/default', PreferenceKeys.branch('x'), 'not json');
      expect(container.read(branchRecordProvider('x')), isNull);
    });
  });
}
