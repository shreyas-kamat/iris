/// What home's extra tabs and the profile tools read: the repositories, the
/// polled lists, and the optimistic overrides.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/failure.dart';
import '../core/result.dart';
import '../data/automation/cron_models.dart';
import '../data/automation/cron_repository.dart';
import '../data/automation/kanban_models.dart';
import '../data/automation/kanban_repository.dart';
import '../data/automation/profile_repository.dart';
import '../data/chat/chat_models.dart';
import '../data/net/capabilities.dart';
import '../demo/demo_mode.dart';
import 'providers.dart';

/// The tabs on home.
enum HomeTab {
  sessions('Sessions'),
  scheduled('Scheduled'),
  tasks('Tasks');

  const HomeTab(this.label);
  final String label;
}

/// The tab the person picked. Lasts for the app session; a cold start opens on
/// Sessions.
final homeTabProvider = NotifierProvider<HomeTabState, HomeTab>(
  HomeTabState.new,
);

class HomeTabState extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.sessions;

  void select(HomeTab tab) => state = tab;
}

/// The tabs this server offers. Empty unless the probe confirmed at least one
/// extra capability: a server that has neither Scheduled nor Tasks gets the
/// home it has always had, with no control drawn.
final homeTabsProvider = Provider<List<HomeTab>>((ref) {
  final capabilities =
      ref.watch(activeCapabilitiesProvider).value ??
      const ServerCapabilities.unknown();
  final extra = [
    if (capabilities.confirmed(ServerCapability.cronJobs)) HomeTab.scheduled,
    if (capabilities.confirmed(ServerCapability.kanban)) HomeTab.tasks,
  ];
  return extra.isEmpty ? const [] : [HomeTab.sessions, ...extra];
});

/// The picked tab, or Sessions when the server does not offer it.
final visibleHomeTabProvider = Provider<HomeTab>((ref) {
  final tabs = ref.watch(homeTabsProvider);
  final picked = ref.watch(homeTabProvider);
  return tabs.contains(picked) ? picked : HomeTab.sessions;
});

/// Cron jobs for the active profile. Null until the link is live, and in the
/// demo until Task 13 gives it a repository.
final cronRepositoryProvider = FutureProvider<CronRepository?>((ref) async {
  if (ref.watch(demoModeProvider)) return null;
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) return null;
  return DashboardCronRepository(
    session.connection.client,
    profile: ref.watch(activeProfileProvider),
  );
});

final kanbanRepositoryProvider = FutureProvider<KanbanRepository?>((ref) async {
  if (ref.watch(demoModeProvider)) return null;
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) return null;
  return DashboardKanbanRepository(session.connection.client);
});

final profileRepositoryProvider = FutureProvider<ProfileRepository?>((
  ref,
) async {
  if (ref.watch(demoModeProvider)) return null;
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) return null;
  return DashboardProfileRepository(session.connection.client);
});

/// Asks [fetch] now and every `liveIntervalProvider` after, until the provider
/// is disposed. A failed poll is reported as a stream error and the next poll
/// still runs, so a list that was on screen stays on screen. Nothing is asked
/// while the app is in the background.
Stream<T> pollEvery<T>(Ref ref, Future<Result<T>> Function() fetch) {
  final interval = ref.watch(liveIntervalProvider);
  final controller = StreamController<T>();
  Timer? next;
  var disposed = false;

  Future<void> tick() async {
    if (disposed) return;
    final state = WidgetsBinding.instance.lifecycleState;
    final background =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (!background) {
      final result = await fetch();
      if (disposed) return;
      switch (result) {
        case Ok(:final value):
          controller.add(value);
        case Err(:final failure):
          controller.addError(failure);
      }
    }
    if (!disposed) next = Timer(interval, () => unawaited(tick()));
  }

  ref.onDispose(() {
    disposed = true;
    next?.cancel();
    unawaited(controller.close());
  });
  unawaited(tick());
  return controller.stream;
}

/// The active profile's jobs, polled while a screen watches this.
final cronJobsProvider = StreamProvider.autoDispose<List<CronJob>>((
  ref,
) async* {
  final repository = await ref.watch(cronRepositoryProvider.future);
  if (repository == null) {
    yield const [];
    return;
  }
  yield* pollEvery(ref, repository.jobs);
});

/// The server's current Kanban board, polled while a screen watches this.
final kanbanBoardProvider = StreamProvider.autoDispose<KanbanBoard>((
  ref,
) async* {
  final repository = await ref.watch(kanbanRepositoryProvider.future);
  if (repository == null) {
    yield const KanbanBoard(columns: []);
    return;
  }
  yield* pollEvery(ref, repository.board);
});

/// One job's past runs, newest first.
final cronRunsProvider = FutureProvider.autoDispose
    .family<List<ConversationSummary>, String>((ref, jobId) async {
      final repository = await ref.watch(cronRepositoryProvider.future);
      if (repository == null) return const [];
      return switch (await repository.runs(jobId)) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };
    });

/// Where a job's reply can be sent. A server that cannot say has none, and the
/// form hides the row.
final deliveryTargetsProvider = FutureProvider.autoDispose<List<DeliveryTarget>>((
  ref,
) async {
  final repository = await ref.watch(cronRepositoryProvider.future);
  if (repository == null) return const [];
  return (await repository.deliveryTargets()).or(const []);
});

/// A pause or resume that is on screen before the server has answered.
final cronEnabledOverridesProvider =
    NotifierProvider<CronEnabledOverrides, Map<String, bool>>(
      CronEnabledOverrides.new,
    );

class CronEnabledOverrides extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  // ignore: avoid_positional_boolean_parameters
  void set(String id, bool enabled) => state = {...state, id: enabled};

  void clear(String id) => state = {...state}..remove(id);
}

/// A move that is on screen before the server has answered.
final taskMoveOverridesProvider =
    NotifierProvider<TaskMoveOverrides, Map<String, String>>(
      TaskMoveOverrides.new,
    );

class TaskMoveOverrides extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void set(String id, String status) => state = {...state, id: status};

  void clear(String id) => state = {...state}..remove(id);
}

/// One task with its comments, runs and links.
final kanbanTaskDetailProvider = FutureProvider.autoDispose
    .family<KanbanTaskDetail, String>((ref, id) async {
      final repository = await ref.watch(kanbanRepositoryProvider.future);
      if (repository == null) {
        throw const IrisFailure(FailureKind.notFound);
      }
      return switch (await repository.task(id)) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };
    });
