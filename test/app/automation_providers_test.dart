import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/automation_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/net/capabilities.dart';

import '../support/fake_automation.dart';

Future<void> until(bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ok(), isTrue, reason: 'timed out waiting');
}

ServerCapabilities probed(Set<ServerCapability> available) =>
    ServerCapabilities(available: available, probedAt: DateTime(2026, 10, 17));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('home tabs', () {
    Future<ProviderContainer> container(ServerCapabilities caps) async {
      final c = ProviderContainer(
        overrides: [
          activeCapabilitiesProvider.overrideWith((ref) => Stream.value(caps)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(activeCapabilitiesProvider, (_, _) {});
      await c.read(activeCapabilitiesProvider.future);
      return c;
    }

    test('an unprobed server offers no extra tabs', () async {
      final c = await container(const ServerCapabilities.unknown());
      expect(c.read(homeTabsProvider), isEmpty);
    });

    test('a server with neither capability offers none', () async {
      final c = await container(probed({ServerCapability.profiles}));
      expect(c.read(homeTabsProvider), isEmpty);
      expect(c.read(visibleHomeTabProvider), HomeTab.sessions);
    });

    test('cron only offers Sessions and Scheduled', () async {
      final c = await container(probed({ServerCapability.cronJobs}));
      expect(c.read(homeTabsProvider), [HomeTab.sessions, HomeTab.scheduled]);
    });

    test('both offer three, and a chosen tab sticks', () async {
      final c = await container(
        probed({ServerCapability.cronJobs, ServerCapability.kanban}),
      );
      expect(c.read(homeTabsProvider), HomeTab.values);
      c.read(homeTabProvider.notifier).select(HomeTab.tasks);
      expect(c.read(visibleHomeTabProvider), HomeTab.tasks);
    });

    test('a chosen tab the server lacks falls back to Sessions', () async {
      final c = await container(probed({ServerCapability.cronJobs}));
      c.read(homeTabProvider.notifier).select(HomeTab.tasks);
      expect(c.read(visibleHomeTabProvider), HomeTab.sessions);
    });
  });

  group('polling', () {
    test('keeps the last good list when a poll fails', () async {
      final cron = FakeCronRepository()..jobsResult = Ok([fakeJob('a')]);
      final c = ProviderContainer(
        overrides: [
          cronRepositoryProvider.overrideWith((ref) async => cron),
          liveIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(cronJobsProvider, (_, _) {});
      await until(() => c.read(cronJobsProvider).value?.length == 1);

      cron.jobsResult = const Err(IrisFailure.offline());
      await until(() => c.read(cronJobsProvider).hasError);
      expect(c.read(cronJobsProvider).value, hasLength(1));

      cron.jobsResult = Ok([fakeJob('a'), fakeJob('b')]);
      await until(() => c.read(cronJobsProvider).value?.length == 2);
      expect(c.read(cronJobsProvider).hasError, isFalse);
    });

    test('stops polling once nothing listens', () async {
      final cron = FakeCronRepository()..jobsResult = Ok([fakeJob('a')]);
      final c = ProviderContainer(
        overrides: [
          cronRepositoryProvider.overrideWith((ref) async => cron),
          liveIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(cronJobsProvider, (_, _) {});
      await until(() => cron.calls.length >= 2);
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final settled = cron.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cron.calls.length, settled);
    });

    test('no repository means an empty list, not an error', () async {
      final c = ProviderContainer(
        overrides: [cronRepositoryProvider.overrideWith((ref) async => null)],
      );
      addTearDown(c.dispose);
      c.listen(cronJobsProvider, (_, _) {});
      await until(() => c.read(cronJobsProvider).hasValue);
      expect(c.read(cronJobsProvider).value, isEmpty);
    });
  });

  group('overrides', () {
    test('set and clear', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(cronEnabledOverridesProvider.notifier).set('a', false);
      expect(c.read(cronEnabledOverridesProvider), {'a': false});
      c.read(cronEnabledOverridesProvider.notifier).clear('a');
      expect(c.read(cronEnabledOverridesProvider), isEmpty);
      c.read(taskMoveOverridesProvider.notifier).set('t', 'todo');
      expect(c.read(taskMoveOverridesProvider), {'t': 'todo'});
    });
  });

  test('delivery targets fall back to empty on a failure', () async {
    final cron = FakeCronRepository()
      ..targetsResult = const Err(IrisFailure(FailureKind.notFound));
    final c = ProviderContainer(
      overrides: [cronRepositoryProvider.overrideWith((ref) async => cron)],
    );
    addTearDown(c.dispose);
    c.listen(deliveryTargetsProvider, (_, _) {});
    expect(await c.read(deliveryTargetsProvider.future), isEmpty);
  });
}
