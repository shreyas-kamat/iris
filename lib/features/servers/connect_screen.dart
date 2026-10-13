/// Connecting to a server.
///
/// This is the first screen anyone sees, and the one most likely to fail: the
/// person is typing an address for a machine on their own network, over a
/// tunnel they set up themselves, possibly with a certificate they signed
/// themselves. Every one of those has a distinct failure, and a single "could
/// not connect" would leave them guessing which.
///
/// So the flow probes before it commits: find out whether the address answers,
/// whether it wants a password, and whether its certificate is trusted, then
/// ask for exactly what is missing. Nothing is saved until it is known to work.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/net/server_config.dart';
import '../../data/net/session_auth.dart';
import '../../design/components/aperture.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

/// Where the wizard is.
enum _Step {
  /// Typing an address.
  address,

  /// Contacting it.
  probing,

  /// It wants a password.
  password,

  /// Saving and signing in.
  joining,
}

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({this.onConnected, super.key});

  /// Called once a server is saved and reachable.
  final ValueChanged<ServerConfig>? onConnected;

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _label = TextEditingController();

  _Step _step = _Step.address;
  IrisFailure? _failure;
  String? _serverVersion;
  bool _allowSelfSigned = false;

  @override
  void dispose() {
    _address.dispose();
    _password.dispose();
    _label.dispose();
    super.dispose();
  }

  bool get _busy => _step == _Step.probing || _step == _Step.joining;

  Future<void> _probe() async {
    setState(() {
      _step = _Step.probing;
      _failure = null;
    });

    final attempt = await ref
        .read(serverRepositoryProvider)
        .testConnection(_address.text, allowSelfSigned: _allowSelfSigned);
    if (!mounted) return;

    if (!attempt.reachable) {
      setState(() {
        _step = _Step.address;
        _failure = attempt.failure;
      });
      return;
    }

    if (attempt.requirement == AuthRequirement.externalIdentityProvider) {
      setState(() {
        _step = _Step.address;
        _failure = const IrisFailure(
          FailureKind.rejected,
          message:
              'This server signs in through an identity provider, which Iris '
              'cannot complete yet. Use a password-protected or private '
              'endpoint for now.',
        );
      });
      return;
    }

    setState(() {
      _serverVersion = attempt.serverVersion;
      _step = attempt.needsPassword ? _Step.password : _Step.joining;
    });

    if (!attempt.needsPassword) await _join();
  }

  Future<void> _join() async {
    setState(() {
      _step = _Step.joining;
      _failure = null;
    });

    final result = await ref
        .read(serverRepositoryProvider)
        .addServer(
          baseUrl: _address.text,
          label: _label.text,
          password: _password.text.isEmpty ? null : _password.text,
          allowSelfSigned: _allowSelfSigned,
        );
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        ref.read(activeServerIdProvider.notifier).select(value.id);
        widget.onConnected?.call(value);
      case Err(:final failure):
        setState(() {
          // Back to whichever step can actually fix this. A rejected password
          // returns to the password field; anything else returns to the
          // address, because that is what was probably wrong.
          _step = failure.kind == FailureKind.unauthorized
              ? _Step.password
              : _Step.address;
          _failure = failure;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final window = context.window;

    return IrisScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: window.gutter),
        child: ReadableColumn(
          maxWidth: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: window.isCramped ? IrisSpace.lg : IrisSpace.huge),
              Aperture(
                state: switch (_step) {
                  _Step.address => AgentState.idle,
                  _Step.probing => AgentState.thinking,
                  _Step.password => AgentState.waiting,
                  _Step.joining => AgentState.working,
                },
                size: 40,
              ),
              const SizedBox(height: IrisSpace.lg),
              Text('Connect to your agent', style: theme.typography.display),
              const SizedBox(height: IrisSpace.sm),
              Text(
                'Iris talks directly to a hermes-webui server on your own '
                'hardware. Nothing goes through anyone else.',
                style: theme.typography.body.copyWith(
                  color: theme.palette.inkMuted,
                ),
              ),
              const SizedBox(height: IrisSpace.xl),
              ..._fields(context),
              if (_failure case final failure?) ...[
                const SizedBox(height: IrisSpace.lg),
                _FailureNote(
                  failure: failure,
                  onAllowSelfSigned: failure.kind == FailureKind.tls
                      ? () {
                          setState(() => _allowSelfSigned = true);
                          unawaited(_probe());
                        }
                      : null,
                ),
              ],
              const SizedBox(height: IrisSpace.xl),
              _primaryAction(),
              const SizedBox(height: IrisSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _fields(BuildContext context) => switch (_step) {
    // The address stays visible and editable once a password is being asked
    // for, because "wrong password" and "right password, wrong server" look
    // identical from here and the user may need to correct either.
    _Step.password || _Step.joining => [
      IrisField(
        label: 'Server address',
        controller: _address,
        mono: true,
        hint: 'https://hermes.example.com',
        keyboardType: TextInputType.url,
      ),
      const SizedBox(height: IrisSpace.sm),
      // Confirmation that the address reached a real Hermes server before the
      // password is typed. Without it, a wrong address and a wrong password
      // produce the same dead end.
      IrisChip.state(
        _serverVersion == null
            ? 'Server found'
            : 'Server found, version $_serverVersion',
        AgentState.done,
        context.palette,
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Password',
        controller: _password,
        obscure: true,
        hint: 'Required by this server',
        autofocus: true,
        onSubmitted: (_) => _join(),
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Name (optional)',
        controller: _label,
        hint: 'Home server',
      ),
    ],
    _ => [
      IrisField(
        label: 'Server address',
        controller: _address,
        mono: true,
        hint: 'https://hermes.example.com',
        keyboardType: TextInputType.url,
        autofocus: true,
        onSubmitted: (_) => _probe(),
      ),
      const SizedBox(height: IrisSpace.md),
      _AddressHint(allowSelfSigned: _allowSelfSigned),
    ],
  };

  Widget _primaryAction() => IrisButton(
    label: switch (_step) {
      _Step.address => 'Continue',
      _Step.probing => 'Contacting the server',
      _Step.password => 'Sign in',
      _Step.joining => 'Connecting',
    },
    tone: IrisButtonTone.primary,
    expand: true,
    busy: _busy,
    onPressed: _busy
        ? null
        : switch (_step) {
            _Step.address => _probe,
            _Step.password => _join,
            _ => null,
          },
  );
}

/// Guidance under the address field.
///
/// Written to answer the question people actually have at this moment, which is
/// "what do I type", not "what is a reverse proxy".
class _AddressHint extends StatelessWidget {
  const _AddressHint({required this.allowSelfSigned});

  final bool allowSelfSigned;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Use the same address you open in a browser. A tunnel or Tailscale '
          'address works; so does a plain local address if your phone is on '
          'the same network.',
          style: theme.typography.caption.copyWith(
            color: theme.palette.inkMuted,
          ),
        ),
        if (allowSelfSigned) ...[
          const SizedBox(height: IrisSpace.sm),
          IrisChip.state(
            'Trusting this certificate',
            AgentState.waiting,
            theme.palette,
          ),
        ],
      ],
    );
  }
}

/// What went wrong, and what to do about it.
class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.failure, this.onAllowSelfSigned});

  final IrisFailure failure;
  final VoidCallback? onAllowSelfSigned;

  /// Plain-language cause and remedy per failure kind.
  ///
  /// The server's own message is appended rather than replacing this, because
  /// it is usually accurate but rarely actionable on its own.
  (String, String) get _advice => switch (failure.kind) {
    FailureKind.offline => (
      'No answer from that address',
      'Check the address, and that the server is running and reachable from '
          'this phone. A local address only works on the same network.',
    ),
    FailureKind.tls => (
      'The certificate is not trusted',
      'This is normal for a server using a self-signed certificate. Only '
          'continue if this is your own machine and you recognise the address.',
    ),
    FailureKind.timeout => (
      'The server took too long',
      'It may be waking up, or the tunnel may be slow. Try again.',
    ),
    FailureKind.unauthorized => (
      'That password was not accepted',
      'Check the password set on the server. Some servers rate-limit repeated '
          'attempts for a minute.',
    ),
    _ => (
      'Could not connect',
      failure.message ?? 'Something went wrong reaching that server.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final (title, detail) = _advice;

    return IrisCard(
      accent: palette.colorFor(AgentState.failed),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IrisLabel(title, color: palette.colorFor(AgentState.failed)),
          const SizedBox(height: IrisSpace.sm),
          Text(detail, style: theme.typography.body),
          if (failure.message case final message?
              when failure.kind != FailureKind.unknown) ...[
            const SizedBox(height: IrisSpace.sm),
            Text(
              message,
              style: theme.typography.codeSmall.copyWith(
                color: palette.inkMuted,
              ),
            ),
          ],
          if (onAllowSelfSigned case final allow?) ...[
            const SizedBox(height: IrisSpace.md),
            IrisButton(label: 'Trust it and continue', onPressed: allow),
          ],
        ],
      ),
    );
  }
}
