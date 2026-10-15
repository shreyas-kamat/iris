/// Connecting to a Hermes dashboard.
///
/// This is the first screen anyone sees, and the one most likely to fail: the
/// person is typing an address for a machine on their own network or behind
/// Cloudflare Access, possibly with a certificate they signed themselves. Every
/// one of those has a distinct failure, and a single "could not connect" would
/// leave them guessing which.
///
/// So the flow probes before it commits: find out whether the address answers,
/// whether an access proxy stands in front, and whether the dashboard wants a
/// login, then ask for exactly what is missing. Nothing is saved until the
/// dashboard has issued a live-connection ticket.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/net/connection_mode.dart';
import '../../data/net/credentials.dart';
import '../../data/net/dashboard_auth.dart';
import '../../data/net/private_host.dart';
import '../../data/net/server_config.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'connection_mode_copy.dart';

/// Where the flow is.
enum _Step {
  /// Typing an address.
  address,

  /// Contacting it.
  probing,

  /// Cloudflare Access is in front; asking for a service token.
  accessToken,

  /// The dashboard wants a username and password.
  login,

  /// Signing in, proving a ticket, saving.
  joining,
}

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({required this.mode, this.onConnected, super.key});

  /// How the user said they reach the server; it changes the wording only.
  final ConnectionMode mode;

  /// Called once a server is saved and reachable.
  final ValueChanged<ServerConfig>? onConnected;

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _address = TextEditingController();
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _label = TextEditingController();

  _Step _step = _Step.address;
  IrisFailure? _failure;
  String? _version;
  bool _allowSelfSigned = false;

  @override
  void dispose() {
    for (final controller in [
      _address,
      _clientId,
      _clientSecret,
      _username,
      _password,
      _label,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The address to use, with the scheme this mode implies for a bare one.
  String get _addressText => addressFor(_address.text, widget.mode);

  /// Refuses plain http to anything but a private address. True if refused.
  bool _refusedPlainHttp() {
    final uri = Uri.tryParse(_addressText);
    if (uri == null || plainHttpAllowed(uri)) return false;
    setState(() {
      _step = _Step.address;
      _failure = const IrisFailure(
        FailureKind.rejected,
        message: 'Use https for an address on the internet.',
      );
    });
    return true;
  }

  bool get _busy => _step == _Step.probing || _step == _Step.joining;

  static String? _text(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  /// What has been typed so far. The password is not trimmed: a leading or
  /// trailing space can be part of it.
  ServerSecrets get _secrets => ServerSecrets(
    username: _text(_username),
    password: _password.text.isEmpty ? null : _password.text,
    accessClientId: _text(_clientId),
    accessClientSecret: _text(_clientSecret),
  );

  Future<void> _probe() async {
    if (_refusedPlainHttp()) return;
    setState(() {
      _step = _Step.probing;
      _failure = null;
    });

    final probe = await ref
        .read(serverRepositoryProvider)
        .testConnection(
          _addressText,
          allowSelfSigned: _allowSelfSigned,
          secrets: _secrets,
        );
    if (!mounted) return;

    switch (probe.access) {
      case DashboardAccess.accessGate:
        setState(() {
          _step = _Step.accessToken;
          // A token was entered and still bounced: say it was rejected, not
          // that one is needed.
          _failure = _secrets.hasAccessToken
              ? const IrisFailure(
                  FailureKind.accessGate,
                  message: 'Cloudflare did not accept this service token.',
                )
              : null;
        });
      case DashboardAccess.password:
        setState(() {
          _version = probe.version;
          _step = _Step.login;
        });
      case DashboardAccess.open:
        setState(() => _version = probe.version);
        await _join();
      case DashboardAccess.browserOnly:
        setState(() {
          _step = _Step.address;
          _failure = const IrisFailure(
            FailureKind.rejected,
            message:
                'This dashboard only offers browser sign-in, which Iris does '
                'not support yet. Turn on password login for the dashboard to '
                'connect.',
          );
        });
      case DashboardAccess.notHermes:
        setState(() {
          _step = _Step.address;
          _failure = const IrisFailure(FailureKind.notFound);
        });
      case DashboardAccess.unreachable:
        setState(() {
          _step = _Step.address;
          _failure = probe.failure;
        });
    }
  }

  Future<void> _join() async {
    setState(() {
      _step = _Step.joining;
      _failure = null;
    });

    final result = await ref
        .read(serverRepositoryProvider)
        .addServer(
          baseUrl: _addressText,
          label: _label.text,
          secrets: _secrets,
          allowSelfSigned: _allowSelfSigned,
          mode: widget.mode,
        );
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        ref.read(activeServerIdProvider.notifier).select(value.id);
        widget.onConnected?.call(value);
      case Err(:final failure):
        setState(() {
          // Back to whichever step can actually fix this.
          _step = switch (failure.kind) {
            FailureKind.unauthorized => _Step.login,
            FailureKind.accessGate => _Step.accessToken,
            _ => _Step.address,
          };
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
              SizedBox(
                height: window.isCramped ? IrisSpace.lg : IrisSpace.huge,
              ),
              Row(
                children: [
                  IrisOrb(
                    state: switch (_step) {
                      _Step.address => AgentState.idle,
                      _Step.probing => AgentState.thinking,
                      _Step.accessToken || _Step.login => AgentState.waiting,
                      _Step.joining => AgentState.working,
                    },
                    size: 40,
                  ),
                  const Spacer(),
                  IrisChip(widget.mode.title),
                  const SizedBox(width: IrisSpace.xs),
                  Semantics(
                    label: 'Change how you connect',
                    button: true,
                    excludeSemantics: true,
                    child: IrisButton(
                      label: 'Change',
                      tone: IrisButtonTone.ghost,
                      onPressed: _busy
                          ? null
                          : () => unawaited(Navigator.of(context).maybePop()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: IrisSpace.lg),
              Text('Connect to your agent', style: theme.typography.display),
              const SizedBox(height: IrisSpace.sm),
              Text(
                'Iris talks directly to the Hermes dashboard on your own '
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

  Widget _addressField({bool autofocus = false}) => IrisField(
    label: 'Server address',
    controller: _address,
    mono: true,
    hint: widget.mode.example,
    keyboardType: TextInputType.url,
    autofocus: autofocus,
    onSubmitted: autofocus ? (_) => _probe() : null,
  );

  List<Widget> _fields(BuildContext context) => switch (_step) {
    _Step.address || _Step.probing => [
      _addressField(autofocus: true),
      const SizedBox(height: IrisSpace.md),
      _AddressHint(allowSelfSigned: _allowSelfSigned, help: widget.mode.help),
    ],
    // The address stays visible and editable on later steps, because "wrong
    // token" and "right token, wrong server" look identical from here.
    _Step.accessToken => [
      _addressField(),
      const SizedBox(height: IrisSpace.md),
      Text(
        'Cloudflare Access protects this address. Iris needs a service token '
        'to pass it: in Cloudflare Zero Trust, create one under Access → '
        'Service credentials, then add a Service Auth policy for it on this '
        'application.',
        style: context.type.caption.copyWith(color: context.palette.inkMuted),
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Client ID',
        controller: _clientId,
        mono: true,
        hint: '….access',
        autofocus: true,
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Client secret',
        controller: _clientSecret,
        mono: true,
        obscure: true,
        onSubmitted: (_) => _probe(),
      ),
    ],
    _Step.login || _Step.joining => [
      _addressField(),
      const SizedBox(height: IrisSpace.sm),
      // Confirmation that the address reached a real dashboard before the
      // password is typed. Without it, a wrong address and a wrong password
      // produce the same dead end.
      IrisChip.state(
        _version == null
            ? 'Hermes dashboard found'
            : 'Hermes dashboard found, version $_version',
        AgentState.done,
        context.palette,
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Username',
        controller: _username,
        autofocus: _step == _Step.login,
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Password',
        controller: _password,
        obscure: true,
        onSubmitted: (_) => _join(),
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Name (optional)',
        controller: _label,
        hint: 'Home server',
      ),
    ],
  };

  Widget _primaryAction() => IrisButton(
    label: switch (_step) {
      _Step.address || _Step.accessToken => 'Continue',
      _Step.probing => 'Contacting the server',
      _Step.login => 'Sign in',
      _Step.joining => 'Connecting',
    },
    tone: IrisButtonTone.primary,
    expand: true,
    busy: _busy,
    onPressed: _busy
        ? null
        : switch (_step) {
            _Step.address || _Step.accessToken => _probe,
            _Step.login => _join,
            _ => null,
          },
  );
}

/// Guidance under the address field.
///
/// Written to answer the question people actually have at this moment, which is
/// "what do I type", not "what is a reverse proxy".
class _AddressHint extends StatelessWidget {
  const _AddressHint({required this.allowSelfSigned, required this.help});

  final bool allowSelfSigned;
  final String help;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          help,
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
      'That login was not accepted',
      'Use the username and password set for the Hermes dashboard. Some '
          'servers rate-limit repeated attempts for a minute.',
    ),
    FailureKind.accessGate => (
      'Cloudflare Access is in the way',
      'Check the service token’s Client ID and secret, and that this '
          'application has a Service Auth policy that includes the token.',
    ),
    FailureKind.notFound => (
      'Not a Hermes dashboard',
      'Check the address and port. Iris connects to the Hermes dashboard '
          '(usually port 9119), not to hermes-webui.',
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
              when failure.kind != FailureKind.unknown &&
                  message != detail) ...[
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
