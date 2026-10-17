/// What the demo shows: made-up conversations, profiles, models and the
/// scripted turns behind the suggested prompts. Data only, so the content can
/// be rewritten without touching how it plays.
library;

import '../data/chat/chat_models.dart';
import 'demo_script.dart';

/// The link in the fallback reply that leaves the demo.
const leaveDemoLink = 'iris://leave-demo';

/// The reply to anything that is not a suggested prompt.
const demoFallback =
    "This is a demo, so replies are pre-written and I can't act on that. Try "
    'one of the suggestions, or [connect your own Hermes server]'
    '($leaveDemoLink) to talk to your agent.';

const demoProfiles = [
  AgentProfile(
    name: 'default',
    isDefault: true,
    model: 'claude-sonnet-5-5',
    provider: 'anthropic',
  ),
  AgentProfile(name: 'homelab', model: 'gpt-6.1', provider: 'openai-codex'),
  AgentProfile(name: 'research', model: 'gpt-5.2', provider: 'openai-codex'),
];

const demoCommands = [
  SlashCommand(name: '/retry', description: 'Run the last turn again'),
  SlashCommand(name: '/model', description: 'Switch the model'),
  SlashCommand(name: '/help', description: 'What commands there are'),
];

/// A stored conversation to seed the demo with.
final class DemoSeed {
  const DemoSeed({
    required this.id,
    required this.title,
    required this.profile,
    required this.age,
    required this.items,
    this.source,
    this.archived = false,
  });

  final String id;
  final String title;
  final String profile;

  /// How long before "now" it started.
  final Duration age;
  final List<TranscriptItem> items;
  final String? source;
  final bool archived;
}

const demoSeeds = [
  DemoSeed(
    id: 'backup-ok',
    title: 'Nightly backup to B2',
    profile: 'default',
    age: Duration(hours: 2),
    source: 'telegram',
    items: [
      UserTurn(id: 'backup-ok-1', text: 'Did the nightly backup run?'),
      ToolCall(
        id: 'backup-ok-2',
        name: 'terminal',
        arguments: 'systemctl status restic-backup.timer',
        output:
            '● restic-backup.timer - Nightly restic backup\n'
            '   Active: active (waiting) since Wed 03:00:02 IST\n'
            '  Trigger: Thu 2026-10-16 03:00:00 IST',
      ),
      AssistantTurn(
        id: 'backup-ok-3',
        text:
            'Yes. The timer fired at 03:00 and the run finished in 6 min 12 s. '
            '214 MB was added; the repository is 48.3 GB across 31 snapshots.',
      ),
    ],
  ),
  DemoSeed(
    id: 'caddy',
    title: 'Caddy certificate renewal',
    profile: 'default',
    age: Duration(hours: 5),
    source: 'cli',
    items: [
      UserTurn(
        id: 'caddy-1',
        text: 'When does the certificate for photos.home.example renew?',
      ),
      AssistantTurn(
        id: 'caddy-2',
        reasoning:
            'Caddy manages this on its own; check its certificate store.',
        text:
            'Caddy renews it automatically about 30 days before it expires. '
            'The current certificate is valid until **12 December 2026**, so '
            'renewal starts around 12 November. Nothing to do.',
      ),
    ],
  ),
  DemoSeed(
    id: 'grafana',
    title: 'Grafana dashboard for the NAS',
    profile: 'default',
    age: Duration(days: 1),
    items: [
      UserTurn(
        id: 'grafana-1',
        text: 'Add a panel for disk temperatures to the NAS dashboard',
      ),
      ToolCall(
        id: 'grafana-2',
        name: 'write_file',
        arguments: 'dashboards/nas.json',
        output: 'Wrote 4.1 KB',
      ),
      AssistantTurn(
        id: 'grafana-3',
        text:
            'Added a **Disk temperatures** panel: a time series with one line '
            'per drive and a warning at 50 °C. Reload the dashboard to see it.',
      ),
    ],
  ),
  DemoSeed(
    id: 'morning',
    title: 'Morning summary',
    profile: 'default',
    age: Duration(days: 1, hours: 3),
    source: 'telegram',
    items: [
      UserTurn(id: 'morning-1', text: 'Summarise what happened overnight'),
      AssistantTurn(
        id: 'morning-2',
        text:
            'A quiet night:\n\n'
            '- The backup finished at 03:06\n'
            '- Two failed SSH logins from 203.0.113.7, blocked by fail2ban\n'
            '- Jellyfin updated to 10.11.2 and restarted cleanly',
      ),
    ],
  ),
  DemoSeed(
    id: 'postgres',
    title: 'Upgrade Postgres 15 to 16',
    profile: 'default',
    age: Duration(days: 9),
    archived: true,
    items: [
      UserTurn(id: 'postgres-1', text: 'Plan the Postgres 15 to 16 upgrade'),
      AssistantTurn(
        id: 'postgres-2',
        text:
            'Done last week: dumped with `pg_dumpall`, restored into 16 and '
            'switched the app over. The 15 cluster is still in '
            '`/var/lib/postgresql/15` if you want to keep it a little longer.',
      ),
    ],
  ),
  DemoSeed(
    id: 'proxmox',
    title: 'Proxmox host load',
    profile: 'homelab',
    age: Duration(hours: 3),
    items: [
      UserTurn(id: 'proxmox-1', text: 'Why is pve1 so busy?'),
      ToolCall(
        id: 'proxmox-2',
        name: 'terminal',
        arguments: 'top -b -n 1 | head -12',
        output:
            'load average: 7.92, 6.40, 5.11\n'
            '  PID USER   %CPU COMMAND\n'
            ' 2211 root    310 kvm (vm 104: media)',
      ),
      AssistantTurn(
        id: 'proxmox-3',
        text:
            'VM 104 (media) is transcoding and using about three cores. It is '
            'the scheduled library scan and should settle within the hour.',
      ),
    ],
  ),
  DemoSeed(
    id: 'pihole',
    title: 'Pi-hole blocklists',
    profile: 'homelab',
    age: Duration(days: 2),
    items: [
      UserTurn(id: 'pihole-1', text: 'Add the OISD blocklist to Pi-hole'),
      AssistantTurn(
        id: 'pihole-2',
        text:
            'Added **OISD big** and updated gravity: 312,904 domains are now '
            'blocked, up from 187,330.',
      ),
    ],
  ),
  DemoSeed(
    id: 'wireguard',
    title: 'Old VPN peer',
    profile: 'homelab',
    age: Duration(days: 20),
    archived: true,
    items: [
      UserTurn(
        id: 'wireguard-1',
        text: 'Remove the old WireGuard peer for the laptop',
      ),
      AssistantTurn(
        id: 'wireguard-2',
        text:
            'Removed peer `laptop-2023` from wg0 and reloaded. Two peers '
            'remain: phone and work.',
      ),
    ],
  ),
];

/// The model in use when the demo starts.
const demoModel = ('claude-sonnet-5-5', 'anthropic');

/// Models and usage, built at [now] so the reset times read sensibly.
ModelOptions demoModelOptions(
  DateTime now, {
  required String model,
  required String provider,
}) => ModelOptions(
  model: model,
  provider: provider,
  providers: [
    ModelProvider(
      slug: 'anthropic',
      name: 'Anthropic',
      models: const [
        'claude-sonnet-5-5',
        'claude-opus-5-5',
        'claude-haiku-5-5',
      ],
      isCurrent: provider == 'anthropic',
      usage: ProviderUsage(
        windows: [
          UsageWindow(
            label: 'Current session',
            usedPercent: 34,
            resetsAt: now.add(const Duration(hours: 3)),
          ),
          UsageWindow(
            label: 'Current week',
            usedPercent: 61,
            resetsAt: now.add(const Duration(days: 4)),
          ),
        ],
      ),
    ),
    ModelProvider(
      slug: 'openai-codex',
      name: 'OpenAI Codex',
      models: const ['gpt-6.1', 'gpt-6.1-mini'],
      isCurrent: provider == 'openai-codex',
      usage: ProviderUsage(
        windows: [
          UsageWindow(
            label: 'Session',
            usedPercent: 12,
            resetsAt: now.add(const Duration(hours: 1)),
          ),
          UsageWindow(
            label: 'Weekly',
            usedPercent: 45,
            resetsAt: now.add(const Duration(days: 2)),
          ),
        ],
      ),
    ),
  ],
);

const demoScripts = [
  DemoScript(
    prompt: 'Check disk space on my server',
    title: 'Disk space on the server',
    steps: [
      ContextStep(18),
      ThinkStep(
        'Start with df to see which filesystem is tight, then look at what '
        'is using the space.',
      ),
      ToolStep(
        'terminal',
        input: 'df -h -x tmpfs -x devtmpfs',
        output:
            'Filesystem      Size  Used Avail Use% Mounted on\n'
            '/dev/nvme0n1p2  468G  431G   14G  97% /\n'
            '/dev/sda1       3.6T  2.1T  1.5T  59% /mnt/media',
        duration: Duration(milliseconds: 1600),
      ),
      ToolStep(
        'terminal',
        input: 'docker system df',
        output:
            'TYPE          TOTAL  ACTIVE  SIZE     RECLAIMABLE\n'
            'Images        41     12      58.3GB   39.7GB (68%)\n'
            'Containers    14     12      1.2GB    0B (0%)\n'
            'Build Cache   96     0       11.4GB   11.4GB',
        duration: Duration(milliseconds: 1400),
      ),
      ThinkStep(
        'The root disk is at 97%. Old Docker images are most of what can be '
        'freed.',
      ),
      ApprovalStep(
        command: 'docker image prune -a --filter "until=720h"',
        description: 'Remove Docker images unused for 30 days',
        ifApproved: [
          SecretStep('sudo docker image prune -a --filter "until=720h"'),
          ToolStep(
            'terminal',
            input: 'sudo docker image prune -a --filter "until=720h"',
            output:
                'Deleted Images:\n'
                'untagged: ghcr.io/example/photos-server:v1.118.0\n'
                '… and 27 more\n\n'
                'Total reclaimed space: 37.9GB',
            duration: Duration(milliseconds: 2400),
          ),
          ContextStep(31),
          SayStep(
            'Freed **37.9 GB**. The root disk is now at **89%**, with 52 GB '
            'free.\n\n'
            '| Filesystem | Before | After |\n'
            '|---|---|---|\n'
            '| `/` | 97% | 89% |\n'
            '| `/mnt/media` | 59% | 59% |\n\n'
            'The build cache holds another 11.4 GB; `docker builder prune` '
            'clears it if you want more room.',
          ),
        ],
        ifDenied: [
          SayStep(
            'Left everything in place. If you want room later without '
            'touching images, these are safe to clear:\n\n'
            '- **Build cache**: 11.4 GB (`docker builder prune`)\n'
            '- **Journal logs** older than two weeks: about 2.1 GB '
            '(`journalctl --vacuum-time=2weeks`)',
          ),
        ],
      ),
    ],
  ),
  DemoScript(
    prompt: "Why did last night's backup fail?",
    title: "Last night's backup",
    steps: [
      ContextStep(22),
      ThinkStep("Check the backup unit's journal for the last run."),
      ToolStep(
        'terminal',
        input: 'journalctl -u restic-backup --since yesterday | tail -3',
        output:
            'Oct 15 03:00:02 nas restic[4121]: Fatal: unable to open repository '
            'at b2:homelab-backup:\n'
            'Oct 15 03:00:02 nas restic[4121]: B2 returned 401: bad_auth_token '
            '(application key expired)\n'
            'Oct 15 03:00:02 nas systemd[1]: restic-backup.service: Failed with '
            "result 'exit-code'.",
      ),
      ThinkStep(
        'The B2 application key expired. A new key goes into the environment '
        'file, then one manual run confirms it.',
      ),
      SayStep(
        'The backup failed because the **Backblaze B2 application key '
        'expired** on 14 October. Restic never reached the repository, so '
        'nothing was written and the existing snapshots are intact.\n\n'
        'Create a new application key for the `homelab-backup` bucket in the '
        'B2 console, then update the environment file:\n\n'
        '```bash\n'
        '# /etc/restic/b2.env\n'
        'B2_ACCOUNT_ID=00a1b2c3d4e5f60000000003\n'
        'B2_ACCOUNT_KEY=<new application key>\n'
        'RESTIC_REPOSITORY=b2:homelab-backup:\n'
        '```\n\n'
        'Then run it once by hand to confirm:\n\n'
        '```bash\n'
        'sudo systemctl start restic-backup.service\n'
        'journalctl -u restic-backup -f\n'
        '```',
      ),
    ],
  ),
  DemoScript(
    prompt: "Summarise this week's GitHub issues",
    title: "This week's GitHub issues",
    steps: [
      ContextStep(26),
      ToolStep(
        'github',
        input: 'list issues in acme/homelab-scripts updated since Oct 8',
        output: '9 issues: 3 bug, 4 enhancement, 2 question',
        duration: Duration(milliseconds: 1800),
      ),
      ThinkStep(
        'Group them by label and pick out anything that could lose data.',
      ),
      SayStep(
        'Nine issues moved this week in **acme/homelab-scripts**:\n\n'
        '| Label | Open | Closed | Notable |\n'
        '|---|---|---|---|\n'
        '| bug | 2 | 1 | #142: the backup script ignores `--dry-run` |\n'
        '| enhancement | 3 | 1 | #139: support Podman as well as Docker |\n'
        '| question | 1 | 1 | #145: how to restore one file |\n\n'
        '**Needs attention:** #142, because a dry run actually deletes old '
        'snapshots. It has a reproduction and a suggested fix.',
      ),
    ],
  ),
  DemoScript(
    prompt: 'Restart the media server',
    title: 'Restart the media server',
    firstRun: [
      ThinkStep('Jellyfin runs as a Docker container on the media VM.'),
      ApprovalStep(
        command: 'docker restart jellyfin',
        description: 'Restart the Jellyfin container',
        ifApproved: [
          ToolStep(
            'terminal',
            input: 'docker restart jellyfin',
            output:
                'Error response from daemon: Cannot restart container '
                'jellyfin: port 8096 is already allocated',
            duration: Duration(milliseconds: 1300),
            failed: true,
          ),
          FailStep('Restarting Jellyfin failed: port 8096 is already in use.'),
        ],
        ifDenied: [SayStep('Left Jellyfin running as it is.')],
      ),
    ],
    steps: [
      ThinkStep('Something still holds port 8096. Find it before restarting.'),
      ApprovalStep(
        command: 'docker restart jellyfin',
        description: 'Restart the Jellyfin container',
        ifApproved: [
          ToolStep(
            'terminal',
            input: 'ss -ltnp "sport = :8096"',
            output: 'LISTEN 0 4096 *:8096 *:* users:(("jellyfin",pid=1882))',
            duration: Duration(milliseconds: 1200),
          ),
          ToolStep(
            'terminal',
            input: 'kill 1882 && docker restart jellyfin',
            output: 'jellyfin',
            duration: Duration(milliseconds: 1800),
          ),
          SayStep(
            'Jellyfin is back up. A stale process from the last update was '
            'still holding port 8096; I stopped it and restarted the '
            'container. It answered on **http://media.home.example:8096** '
            'within four seconds.',
          ),
        ],
        ifDenied: [SayStep('Left Jellyfin running as it is.')],
      ),
    ],
  ),
  DemoScript(
    prompt: 'Deploy the docs site',
    title: 'Deploy the docs site',
    steps: [
      ContextStep(31),
      ThinkStep(
        'Pushing needs the GitHub login, which lives in the password manager.',
      ),
      ToolStep(
        'browser.open',
        input: 'https://github.com/login',
        output: 'Login page open',
      ),
      VaultStep(VaultKind.unlock, name: '1Password'),
      VaultStep(
        VaultKind.code,
        site: 'GitHub',
        hint: '6 digits from your authenticator app',
      ),
      VaultStep(VaultKind.login, site: 'GitHub'),
      ConnectStep([
        {
          'name': 'Linear',
          'kind': 'connector',
          'action': 'authorize',
          'state': 'pending',
          'connect_url': 'https://linear.app/oauth',
        },
        {
          'name': 'release-notes',
          'kind': 'skill',
          'action': 'enable',
          'state': 'pending',
        },
        {
          'name': 'security-scan',
          'kind': 'plugin',
          'action': 'install',
          'state': 'pending',
        },
      ]),
      SayStep(
        'Signed in and pushed the build to the docs branch. The site is live.',
      ),
    ],
  ),
];

/// The script for [text], if it is one of the suggested prompts.
DemoScript? demoScriptFor(String text) {
  final wanted = text.trim().toLowerCase();
  for (final script in demoScripts) {
    if (script.prompt.toLowerCase() == wanted) return script;
  }
  return null;
}
