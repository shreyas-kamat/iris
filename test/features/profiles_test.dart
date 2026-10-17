import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/automation_providers.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/automation/profile_repository.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/features/profiles/profile_form_screen.dart';
import 'package:iris/features/profiles/profiles_screen.dart';

import '../support/fake_automation.dart';
import '../support/harness.dart';

void main() {
  late FakeProfileRepository repo;
  setUp(() => repo = FakeProfileRepository());

  const profiles = [
    AgentProfile(name: 'default', isDefault: true, model: 'opus-4.5'),
    AgentProfile(name: 'research', model: 'gpt-5.2'),
    AgentProfile(name: 'homelab', model: 'sonnet-4.5'),
  ];

  Widget app(Widget screen) => ProviderScope(
    overrides: [
      activeServerProvider.overrideWithValue(
        const ServerConfig(
          id: 's',
          baseUrl: 'https://hermes.local',
          label: 'H',
        ),
      ),
      profileRepositoryProvider.overrideWith((ref) async => repo),
      profilesProvider.overrideWith((ref) async => profiles),
    ],
    child: themed(screen),
  );

  ProviderContainer containerOf(WidgetTester tester, Type screen) =>
      ProviderScope.containerOf(tester.element(find.byType(screen)));

  Finder field(String label) =>
      find.byWidgetPredicate((w) => w is IrisField && w.label == label);

  group('list', () {
    testWidgets('names every profile with its model and the default tag', (
      tester,
    ) async {
      await tester.pumpWidget(app(const ProfilesScreen()));
      await tester.pumpAndSettle();
      for (final name in ['default', 'research', 'homelab']) {
        expect(find.text(name), findsWidgets);
      }
      expect(find.text('opus-4.5'), findsOneWidget);
      expect(find.text('gpt-5.2'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('New profile'), findsOneWidget);
      expect(find.textContaining('hermes.local'), findsOneWidget);
    });

    testWidgets('the circle switches to that profile', (tester) async {
      await tester.pumpWidget(app(const ProfilesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Switch to research'));
      await tester.pumpAndSettle();
      expect(
        containerOf(tester, ProfilesScreen).read(activeProfileProvider),
        'research',
      );
      expect(find.bySemanticsLabel('Current profile'), findsOneWidget);
    });

    testWidgets('tapping the row opens its editor', (tester) async {
      await tester.pumpWidget(app(const ProfilesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gpt-5.2'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileFormScreen), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);
    });

    testWidgets('the switch target is at least 44 pt', (tester) async {
      await tester.pumpWidget(app(const ProfilesScreen()));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.bySemanticsLabel('Switch to research'));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('new profile', () {
    bool createEnabled(WidgetTester tester) =>
        tester
            .widget<IrisButton>(find.widgetWithText(IrisButton, 'Create'))
            .onPressed !=
        null;

    testWidgets('Create waits for a valid name, and says what is wrong', (
      tester,
    ) async {
      await tester.pumpWidget(app(const ProfileFormScreen()));
      await tester.pumpAndSettle();
      expect(createEnabled(tester), isFalse);
      await tester.enterText(field('Name'), 'Work Notes');
      await tester.pump();
      expect(
        find.text('Lowercase letters, digits, - and _ only'),
        findsWidgets,
      );
      expect(createEnabled(tester), isFalse);
      await tester.enterText(field('Name'), 'work-notes');
      await tester.pump();
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('a blank profile sends the name and the SOUL', (tester) async {
      await tester.pumpWidget(app(const ProfileFormScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(field('Name'), 'notes');
      await tester.enterText(field('SOUL · optional'), 'You keep notes.');
      await tester.pump();
      await tester.tap(find.widgetWithText(IrisButton, 'Create'));
      await tester.pumpAndSettle();
      final draft = repo.drafts.single;
      expect(draft.name, 'notes');
      expect(draft.start, ProfileStart.blank);
      expect(draft.soul, 'You keep notes.');
    });

    testWidgets('a full copy of another profile', (tester) async {
      await tester.pumpWidget(app(const ProfileFormScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(field('Name'), 'clone');
      await tester.tap(find.text('Full copy'));
      await tester.pump();
      await tester.tap(find.text('Copy from'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('research'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(IrisButton, 'Create'));
      await tester.pumpAndSettle();
      final draft = repo.drafts.single;
      expect(draft.start, ProfileStart.full);
      expect(draft.source, 'research');
    });

    testWidgets('a refused create keeps the form and says why', (tester) async {
      repo.createResult = const Err(
        IrisFailure(FailureKind.rejected, message: 'profile exists'),
      );
      await tester.pumpWidget(app(const ProfileFormScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(field('Name'), 'research');
      await tester.pump();
      await tester.tap(find.widgetWithText(IrisButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.text('profile exists'), findsOneWidget);
      expect(find.byType(ProfileFormScreen), findsOneWidget);
    });
  });

  group('edit profile', () {
    bool saveEnabled(WidgetTester tester) =>
        tester
            .widget<IrisButton>(find.widgetWithText(IrisButton, 'Save'))
            .onPressed !=
        null;

    testWidgets('the default profile has no rename and no Delete', (
      tester,
    ) async {
      repo.soulResult = const Ok('# Default');
      await tester.pumpWidget(app(const ProfileFormScreen(editing: 'default')));
      await tester.pumpAndSettle();
      expect(field('Name'), findsNothing);
      expect(find.text('Delete profile'), findsNothing);
      expect(find.text('opus-4.5'), findsOneWidget);
    });

    testWidgets('Save waits for a change, then renames and writes the SOUL', (
      tester,
    ) async {
      repo.soulResult = const Ok('# Research');
      await tester.pumpWidget(
        app(const ProfileFormScreen(editing: 'research')),
      );
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(field('Name'), 'papers');
      await tester.enterText(field('SOUL.md'), '# Papers');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      await tester.tap(find.widgetWithText(IrisButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.calls, [
        'soul research',
        'rename research papers',
        'setSoul papers',
      ]);
      expect(repo.writtenSouls['papers'], '# Papers');
    });

    testWidgets('a SOUL that has not loaded is not overwritten', (
      tester,
    ) async {
      repo.soulResult = const Err(IrisFailure(FailureKind.server));
      await tester.pumpWidget(
        app(const ProfileFormScreen(editing: 'research')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Name'), 'papers');
      await tester.pump();
      await tester.tap(find.widgetWithText(IrisButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.calls.any((c) => c.startsWith('setSoul')), isFalse);
    });

    testWidgets('the Monospace switch changes the SOUL font', (tester) async {
      repo.soulResult = const Ok('# Research');
      await tester.pumpWidget(
        app(const ProfileFormScreen(editing: 'research')),
      );
      await tester.pumpAndSettle();
      final before = tester.widget<IrisField>(field('SOUL.md')).mono;
      await tester.tap(find.byType(IrisSwitch));
      await tester.pump();
      expect(tester.widget<IrisField>(field('SOUL.md')).mono, !before);
    });
  });

  group('delete profile', () {
    Future<void> openDelete(WidgetTester tester) async {
      repo.soulResult = const Ok('# Research');
      await tester.pumpWidget(
        app(const ProfileFormScreen(editing: 'research')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete profile'));
      await tester.tap(find.text('Delete profile'));
      await tester.pumpAndSettle();
    }

    bool deleteEnabled(WidgetTester tester) =>
        tester
            .widget<IrisButton>(find.widgetWithText(IrisButton, 'Delete'))
            .onPressed !=
        null;

    testWidgets('names what is lost and waits for the exact name', (
      tester,
    ) async {
      await openDelete(tester);
      expect(find.textContaining('removed from hermes.local'), findsOneWidget);
      expect(deleteEnabled(tester), isFalse);
      await tester.enterText(field('Type research to confirm'), 'Research');
      await tester.pump();
      expect(deleteEnabled(tester), isFalse);
      await tester.enterText(field('Type research to confirm'), 'research');
      await tester.pump();
      expect(deleteEnabled(tester), isTrue);
    });

    testWidgets(
      'deleting calls the server, and the current profile falls back to default',
      (tester) async {
        await openDelete(tester);
        final container = containerOf(tester, ProfileFormScreen);
        container.read(activeProfileProvider.notifier).select('research');
        await tester.enterText(field('Type research to confirm'), 'research');
        await tester.pump();
        await tester.tap(find.widgetWithText(IrisButton, 'Delete'));
        await tester.pumpAndSettle();
        expect(repo.calls, contains('delete research'));
        expect(container.read(activeProfileProvider), 'default');
      },
    );

    testWidgets('a refused delete keeps the profile and says why', (
      tester,
    ) async {
      repo.deleteResult = const Err(
        IrisFailure(FailureKind.rejected, message: 'gateway is running'),
      );
      await openDelete(tester);
      await tester.enterText(field('Type research to confirm'), 'research');
      await tester.pump();
      await tester.tap(find.widgetWithText(IrisButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('gateway is running'), findsOneWidget);
    });
  });
}
