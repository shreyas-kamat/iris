# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Report it privately, in either of these ways:

- Use GitHub's private reporting: the **Security** tab of this repository, then **Report a vulnerability**.
- Or email <shreyaskamat13@gmail.com> with "Iris security" in the subject.

Please include what you found, how to reproduce it, which version or commit you tested, and what you think
the impact is. Do not include real passwords, tokens or server addresses; a throwaway test server is fine.

Iris is maintained by one person. I aim to acknowledge a report within 7 days and to tell you what I plan to
do about it within 30. If a fix is warranted I will publish it and credit you, unless you prefer not to be
named. Please give me time to fix an issue before you disclose it publicly.

## Supported versions

Only the latest release, and the `main` branch, receive security fixes.

## How Iris handles sensitive data

Knowing the design helps you judge what is and is not a vulnerability.

- **Secrets.** The Hermes password and a Cloudflare Access service token are stored in the platform keystore
  (Android Keystore through `flutter_secure_storage`; iOS Keychain with the "first unlock, this device only"
  accessibility). They are read only when a request needs them. They are never written to the app's
  database, preferences or logs; the logger redacts them.
- **What leaves the device.** Iris talks only to the server address the user entered. It has no analytics, no
  crash reporting, no advertising and no other network endpoints. The offline demo makes no network
  requests at all.
- **Local storage.** The server's address and label, and settings such as theme and profile, are in a local
  database. Conversations are held in memory while shown and are not copied into it. Android backup is
  disabled so none of this is uploaded to cloud backups.
- **Transport.** `https` is always allowed. Plain `http` is allowed only for private addresses (loopback,
  RFC 1918 ranges, Tailscale's `100.64.0.0/10`, `.local`, `.ts.net`, single-label names); Iris refuses it for
  anything else before sending a request. The Cloudflare Access token is only ever sent over `https`.
- **Certificates.** A certificate that does not chain to a trusted root is rejected unless the user
  explicitly chooses to trust it, and then only for that one server's host.
- **Links.** A link in a reply opens in the system browser, and only for `http`, `https` and `mailto`;
  `javascript:`, `file:`, `intent:` and the like are ignored.
- **Prompts from the agent.** A `sudo` or secret prompt is answered into the connection and kept nowhere,
  not even in the transcript.

## In scope

- Anything that exposes a stored secret, or sends one somewhere it should not go.
- A way to make Iris connect to, or trust, a server the user did not choose.
- Bypassing the rules for plain `http` or for certificates.
- A crafted server response, or a message from the agent, that crashes the app, runs unintended actions, or
  opens something it should not.

## Out of scope

- Vulnerabilities in the Hermes dashboard or agent themselves; please report those to
  [Hermes Agent](https://github.com/NousResearch/hermes-agent).
- Problems that need a rooted or jailbroken device, or physical access to an unlocked phone.
- A server operator reading the traffic to a server they run; Iris trusts the server the user points it at.
- Findings from automated scanners with no demonstrated impact.
