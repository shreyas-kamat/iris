/// The design gallery.
///
/// Every token and component in one scroll, in whichever skin and brightness is
/// selected. It exists because a design system is only coherent if you can see
/// all of it at once — a component that looks right on its own screen and wrong
/// beside its siblings is the normal failure mode, and it is invisible until
/// they are on the same page.
///
/// It is also the golden-test surface: the same widgets, captured per skin.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme_controller.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/iris_voice_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/oklch.dart';
import '../../design/tokens/palette.dart';

class DesignGallery extends ConsumerWidget {
  const DesignGallery({super.key});

  /// Sections, as builders rather than instances, so the sliver can build them
  /// lazily instead of constructing every showcase on first frame.
  static const List<(String, Widget)> _sections = [
    ('Iris orb', _OrbShowcase()),
    ('Voice orb', _VoiceOrbShowcase()),
    ('Type', _TypeShowcase()),
    ('Palette', _PaletteShowcase()),
    ('Ramp', _RampShowcase()),
    ('Buttons', _ButtonShowcase()),
    ('Chips and status', _ChipShowcase()),
    ('Surfaces', _SurfaceShowcase()),
    ('Fields', _FieldShowcase()),
    ('Gauges', _GaugeShowcase()),
    ('Loading', _SkeletonShowcase()),
    ('Empty state', _EmptyShowcase()),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IrisScaffold(
      body: ReadableColumn(
        // Wide windows get a measured column rather than full-bleed rows: a
        // swatch grid 1200pt wide has the same problem as a 1200pt line of text.
        maxWidth: 720,
        child: IrisScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _GalleryHeader()),
            const SliverToBoxAdapter(child: _SkinPicker()),
            SliverList.builder(
              itemCount: _sections.length,
              itemBuilder: (context, index) {
                final (title, child) = _sections[index];
                return _Section(title, child: child);
              },
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: IrisSpace.huge),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryHeader extends ConsumerWidget {
  const _GalleryHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.iris;
    final preference = ref.watch(themeControllerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IrisSpace.lg,
        IrisSpace.xl,
        IrisSpace.lg,
        IrisSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IrisOrb(state: AgentState.streaming),
              const SizedBox(width: IrisSpace.md),
              Expanded(
                child: Text('Iris', style: theme.typography.displayLarge),
              ),
              _ModeToggle(mode: preference.mode),
            ],
          ),
          const SizedBox(height: IrisSpace.xs),
          Text(
            'Design system. ${theme.skin.label}, '
            '${theme.isDark ? 'dark' : 'light'}.',
            style: theme.typography.body.copyWith(
              color: theme.palette.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends ConsumerWidget {
  const _ModeToggle({required this.mode});

  final BrightnessMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IrisChip(
    mode.label,
    onTap: () => ref.read(themeControllerProvider.notifier).cycleMode(),
  );
}

class _SkinPicker extends ConsumerWidget {
  const _SkinPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeControllerProvider).skin;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: IrisSpace.lg),
        itemCount: IrisSkin.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: IrisSpace.sm),
        itemBuilder: (context, index) {
          final skin = IrisSkin.values[index];
          return _SkinSwatch(
            skin: skin,
            selected: skin == selected,
            onTap: () =>
                ref.read(themeControllerProvider.notifier).setSkin(skin),
          );
        },
      ),
    );
  }
}

/// A skin swatch that previews the skin it selects rather than the current one,
/// so the picker shows what you are choosing between.
class _SkinSwatch extends StatelessWidget {
  const _SkinSwatch({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final IrisSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = context.iris;
    final preview = skin.palette(isDark: current.isDark);
    return IrisPressable(
      onTap: onTap,
      semanticLabel: skin.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: preview.canvas,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? current.palette.ink : current.palette.line,
                width: selected ? IrisStroke.thick : IrisStroke.thin,
              ),
            ),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: preview.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(height: IrisSpace.xs),
          IrisLabel(
            skin.label,
            small: true,
            color: selected ? current.palette.ink : current.palette.inkFaint,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = context.window;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        window.gutter,
        // Sections tighten up in landscape and when the keyboard is open,
        // where vertical room is the scarce resource.
        window.isCramped ? IrisSpace.lg : IrisSpace.xl,
        window.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IrisLabel(title),
          const SizedBox(height: IrisSpace.sm),
          const IrisDivider(),
          const SizedBox(height: IrisSpace.lg),
          child,
        ],
      ),
    );
  }
}

class _OrbShowcase extends StatelessWidget {
  const _OrbShowcase();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // One large orb to judge the mark at the size the hero uses.
      const IrisOrb(state: AgentState.idle, size: 84),
      const SizedBox(height: IrisSpace.lg),
      Wrap(
        spacing: IrisSpace.xl,
        runSpacing: IrisSpace.lg,
        children: [
          for (final state in AgentState.values)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IrisOrb(state: state, size: 40),
                const SizedBox(height: IrisSpace.sm),
                IrisLabel(state.label, small: true),
                const SizedBox(height: IrisSpace.xs),
                IrisOrb(state: state, size: 20),
              ],
            ),
        ],
      ),
    ],
  );
}

/// O1: the voice orb in every mode, at the size a call opens on, and at the
/// composer's size.
class _VoiceOrbShowcase extends StatelessWidget {
  const _VoiceOrbShowcase();

  static String _name(VoiceOrbMode mode) => switch (mode) {
    VoiceOrbMode.needs => 'Needs you',
    _ => '${mode.name[0].toUpperCase()}${mode.name.substring(1)}',
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: IrisSpace.xl,
    runSpacing: IrisSpace.lg,
    children: [
      for (final mode in VoiceOrbMode.values)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IrisVoiceOrb(mode: mode, size: 96),
            const SizedBox(height: IrisSpace.sm),
            IrisLabel(_name(mode), small: true),
            const SizedBox(height: IrisSpace.xs),
            IrisVoiceOrb(mode: mode, size: 46),
          ],
        ),
    ],
  );
}

class _TypeShowcase extends StatelessWidget {
  const _TypeShowcase();

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final palette = context.palette;
    // Sample text chosen to exercise the thing each style is actually for:
    // prose reads as prose, mono reads as machine output.
    const samples = {
      'displayLarge': 'Watching from here',
      'display': 'Nothing running',
      'title': 'Streaming parser',
      'heading': 'Session settings',
      'bodyLarge': 'The agent is reading your workspace.',
      'body':
          'I looked through the SSE parser and found the frame boundary bug. '
          'It only shows up when a heartbeat lands mid-frame.',
      'caption': 'Updated 4 minutes ago',
      'label': 'Tool call',
      'labelSmall': 'Pending',
      'code': 'grep -rn stream_end api/streaming.py',
      'codeSmall': '0 */6 * * *',
      'numeric': '14,208 tokens · \$0.0412',
      'serif': 'Good evening.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in type.all.entries) ...[
          IrisLabel(entry.key, small: true, color: palette.inkFaint),
          const SizedBox(height: IrisSpace.xxs),
          Text(
            entry.key.startsWith('label')
                ? samples[entry.key]!.toUpperCase()
                : samples[entry.key]!,
            style: entry.value,
          ),
          const SizedBox(height: IrisSpace.lg),
        ],
      ],
    );
  }
}

class _PaletteShowcase extends StatelessWidget {
  const _PaletteShowcase();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Short labels: the swatch is 62pt wide and the long role names were
    // breaking mid-word into "LINESTRO / NG".
    final roles = <String, Color>{
      'canvas': p.canvas,
      'surface': p.surface,
      'raised': p.surfaceRaised,
      'sunken': p.surfaceSunken,
      'ink': p.ink,
      'muted': p.inkMuted,
      'faint': p.inkFaint,
      'line': p.line,
      'line+': p.lineStrong,
      'accent': p.accent,
      'accent-': p.accentQuiet,
      'danger': p.danger,
    };
    return Wrap(
      spacing: IrisSpace.sm,
      runSpacing: IrisSpace.sm,
      children: [
        for (final entry in roles.entries)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                height: 40,
                decoration: BoxDecoration(
                  color: entry.value,
                  borderRadius: const BorderRadius.all(IrisRadius.xs),
                  border: Border.all(color: p.line, width: IrisStroke.hairline),
                ),
              ),
              const SizedBox(height: IrisSpace.xxs),
              SizedBox(
                width: 62,
                child: IrisLabel(entry.key, small: true, color: p.inkFaint),
              ),
            ],
          ),
      ],
    );
  }
}

/// Proves the ramp steps evenly in whatever hue the skin uses.
class _RampShowcase extends StatelessWidget {
  const _RampShowcase();

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final ramp = ColorRamp.fromHue(
      theme.skin.accentHue,
      chroma: theme.skin.chroma,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.all(IrisRadius.sm),
          child: SizedBox(
            height: 44,
            child: Row(
              // Stretch, not the default centre: a ColoredBox with no child
              // has no intrinsic height and would collapse to nothing.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final stop in ColorRamp.stops)
                  Expanded(child: ColoredBox(color: ramp.color(stop))),
              ],
            ),
          ),
        ),
        const SizedBox(height: IrisSpace.sm),
        Row(
          children: [
            for (final stop in ColorRamp.stops)
              Expanded(
                child: Center(
                  child: IrisLabel(
                    '$stop',
                    small: true,
                    color: theme.palette.inkFaint,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ButtonShowcase extends StatelessWidget {
  const _ButtonShowcase();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: IrisSpace.sm,
        runSpacing: IrisSpace.sm,
        children: [
          for (final tone in IrisButtonTone.values)
            IrisButton(label: tone.name, tone: tone, onPressed: () {}),
        ],
      ),
      const SizedBox(height: IrisSpace.md),
      Wrap(
        spacing: IrisSpace.sm,
        runSpacing: IrisSpace.sm,
        children: const [
          IrisButton(label: 'Disabled'),
          IrisButton(label: 'Working', busy: true),
        ],
      ),
      const SizedBox(height: IrisSpace.md),
      IrisButton(
        label: 'Send to agent',
        tone: IrisButtonTone.primary,
        expand: true,
        onPressed: () {},
      ),
    ],
  );
}

class _ChipShowcase extends StatelessWidget {
  const _ChipShowcase();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Wrap(
      spacing: IrisSpace.sm,
      runSpacing: IrisSpace.sm,
      children: [
        for (final state in AgentState.values)
          IrisChip.state(state.name, state, palette),
        const IrisChip('terminal'),
        const IrisChip('claude-opus-5'),
      ],
    );
  }
}

class _SurfaceShowcase extends StatelessWidget {
  const _SurfaceShowcase();

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return Column(
      children: [
        for (final plane in IrisPlane.values) ...[
          IrisCard(
            plane: plane,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IrisLabel(plane.name),
                      const SizedBox(height: IrisSpace.xs),
                      Text(switch (plane) {
                        IrisPlane.ground => 'The conversation itself.',
                        IrisPlane.raised => 'A tool call, grouped output.',
                        IrisPlane.overlay => 'A sheet you can dismiss.',
                      }, style: theme.typography.body),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: IrisSpace.md),
        ],
        IrisCard(
          accent: theme.palette.colorFor(AgentState.failed),
          child: Row(
            children: [
              IrisOrb(state: AgentState.failed, size: IrisSize.orbSmall),
              const SizedBox(width: IrisSpace.sm),
              Expanded(
                child: Text(
                  'grep exited 2: no such file or directory',
                  style: theme.typography.code,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldShowcase extends StatelessWidget {
  const _FieldShowcase();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      IrisField(
        label: 'Server address',
        hint: 'https://hermes.local:8787',
        mono: true,
      ),
      SizedBox(height: IrisSpace.md),
      IrisField(
        label: 'Password',
        hint: 'Required by this server',
        obscure: true,
      ),
      SizedBox(height: IrisSpace.md),
      IrisField(
        label: 'Schedule',
        hint: '0 */6 * * *',
        mono: true,
        errorText: 'That is five fields; cron needs five or six.',
      ),
      SizedBox(height: IrisSpace.md),
      IrisField(hint: 'Ask the agent to do something…', maxLines: 4),
    ],
  );
}

class _GaugeShowcase extends StatelessWidget {
  const _GaugeShowcase();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IrisGauge(value: 0.18, label: 'context'),
      SizedBox(height: IrisSpace.md),
      IrisGauge(value: 0.62, label: 'context'),
      SizedBox(height: IrisSpace.md),
      IrisGauge(value: 0.83, label: 'context'),
      SizedBox(height: IrisSpace.md),
      IrisGauge(value: 0.97, label: 'context'),
    ],
  );
}

class _SkeletonShowcase extends StatelessWidget {
  const _SkeletonShowcase();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IrisSkeleton(width: 180, height: 16),
      SizedBox(height: IrisSpace.sm),
      IrisSkeleton(height: 12),
      SizedBox(height: IrisSpace.sm),
      IrisSkeleton(width: 240, height: 12),
    ],
  );
}

class _EmptyShowcase extends StatelessWidget {
  const _EmptyShowcase();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 280,
    child: IrisEmptyState(
      icon: const IrisOrb(state: AgentState.idle, size: 44),
      title: 'No conversations yet',
      message: 'Your agent is connected and waiting. Ask it something.',
      action: IrisButton(
        label: 'Start a conversation',
        tone: IrisButtonTone.primary,
        onPressed: () {},
      ),
    ),
  );
}
