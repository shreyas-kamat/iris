import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/features/chat/prompt_records.dart';

void main() {
  final at = DateTime(2026, 10, 16, 14, 2);

  InputRequest input(
    InputKind kind, {
    String command = '',
    String envVar = '',
    String displayName = '',
    String site = '',
  }) => InputRequest(
    requestId: 'srq',
    sessionId: 's',
    kind: kind,
    command: command,
    envVar: envVar,
    displayName: displayName,
    site: site,
  );

  test('the clock is two-digit hours and minutes', () {
    expect(clock(DateTime(2026, 1, 1, 7, 5)), '07:05');
  });

  test('sudo names the command, never the password', () {
    final done = recordForInput(
      input(InputKind.sudo, command: 'systemctl restart hermes-worker'),
      PromptOutcome.answered,
      at,
      id: 'p1',
    );
    expect(done.title, 'Ran with sudo');
    expect(done.detail, 'systemctl restart hermes-worker · 14:02');
    expect(
      recordForInput(
        input(InputKind.sudo, command: 'x'),
        PromptOutcome.skipped,
        at,
        id: 'p',
      ).title,
      'Denied sudo',
    );
  });

  test('a secret names the variable and says the value is hidden', () {
    final done = recordForInput(
      input(InputKind.secret, envVar: 'OPENAI_API_KEY'),
      PromptOutcome.answered,
      at,
      id: 'p',
    );
    expect(done.title, 'Saved OPENAI_API_KEY');
    expect(done.detail, 'value hidden · 14:02');
    expect(
      recordForInput(
        input(InputKind.secret, envVar: 'K'),
        PromptOutcome.skipped,
        at,
        id: 'p',
      ).title,
      'Skipped K',
    );
  });

  test('an unlock and a code', () {
    expect(
      recordForInput(
        input(InputKind.vaultUnlock, displayName: '1Password'),
        PromptOutcome.answered,
        at,
        id: 'p',
      ).title,
      'Unlocked 1Password',
    );
    expect(
      recordForInput(
        input(InputKind.vaultUnlock, displayName: '1Password'),
        PromptOutcome.skipped,
        at,
        id: 'p',
      ).title,
      'Skipped the 1Password unlock',
    );
    expect(
      recordForInput(
        input(InputKind.vaultCode, site: 'GitHub'),
        PromptOutcome.answered,
        at,
        id: 'p',
      ).title,
      'Sent the code for GitHub',
    );
  });

  test('a withdrawn prompt says Hermes stopped waiting', () {
    final expired = recordForInput(
      input(InputKind.vaultUnlock, displayName: '1Password'),
      PromptOutcome.expired,
      at,
      id: 'p',
    );
    expect(expired.title, '1Password request withdrawn');
    expect(expired.detail, 'expired 14:02 · Hermes stopped waiting');
    expect(expired.outcome, PromptOutcome.expired);
  });

  test('a login', () {
    const login = LoginRequest(
      requestId: 'r',
      sessionId: 's',
      origin: 'https://github.com',
      site: 'GitHub',
    );
    expect(
      recordForLogin(login, PromptOutcome.answered, at, id: 'p').title,
      'Saved GitHub login',
    );
    expect(
      recordForLogin(login, PromptOutcome.answered, at, id: 'p').detail,
      'value hidden · 14:02',
    );
    expect(
      recordForLogin(login, PromptOutcome.skipped, at, id: 'p').title,
      'Skipped saving the GitHub login',
    );
  });
}
