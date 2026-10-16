/// A prompt to save a login: username, password, Save or Skip (frame A7).
/// Both values go straight to `onSave` and are held nowhere else.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/needs_you_card.dart';
import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

class LoginCard extends StatefulWidget {
  const LoginCard({
    required this.request,
    required this.onSave,
    required this.onSkip,
    super.key,
  });

  final LoginRequest request;
  final Future<void> Function(String identifier, String password) onSave;
  final Future<void> Function() onSkip;

  @override
  State<LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<LoginCard> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _revealed = false;
  bool _sending = false;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final identifier = _identifier.text;
    final password = _password.text;
    // Cleared before the answer leaves, so neither value lives in a widget
    // while it is in flight.
    _identifier.clear();
    _password.clear();
    setState(() => _sending = true);
    await widget.onSave(identifier, password);
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _skip() async {
    setState(() => _sending = true);
    await widget.onSkip();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final request = widget.request;
    final listenable = Listenable.merge([_identifier, _password]);
    return NeedsYouCard(
      eyebrow: 'Needs you · save login',
      title: 'Save to your password manager?',
      actions: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => NeedsYouActions(
          skipLabel: 'Skip',
          primaryLabel: 'Save',
          busy: _sending,
          onSkip: () => unawaited(_skip()),
          onPrimary: _identifier.text.isEmpty || _password.text.isEmpty
              ? null
              : () => unawaited(_save()),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.surfaceSunken,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  request.siteName.isEmpty
                      ? '?'
                      : request.siteName[0].toUpperCase(),
                  style: type.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: palette.ink,
                  ),
                ),
              ),
              const SizedBox(width: IrisSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.siteName,
                      style: type.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    Text(
                      request.origin,
                      style: type.codeSmall.copyWith(
                        fontSize: 11.5,
                        color: palette.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: IrisSpace.md),
          const IrisLabel('Username', small: true),
          const SizedBox(height: IrisSpace.xs),
          IrisField(
            controller: _identifier,
            hint: 'Username or email',
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
          ),
          const SizedBox(height: IrisSpace.md),
          const IrisLabel('Password', small: true),
          const SizedBox(height: IrisSpace.xs),
          IrisField(
            controller: _password,
            hint: 'Password',
            mono: true,
            obscure: !_revealed,
            autocorrect: false,
            enableSuggestions: false,
            trailing: IrisPressable(
              onTap: () => setState(() => _revealed = !_revealed),
              semanticLabel: _revealed ? 'Hide password' : 'Show password',
              child: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: IrisSize.icon,
                color: palette.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
