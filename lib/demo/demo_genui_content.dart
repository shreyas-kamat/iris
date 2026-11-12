/// The demo's generated displays (plan 7.1): a card, a reply kit, and a study
/// result. Each program is an Iris Lang program and each call's arguments are
/// what `iris_ui` and the study tools take. `test/demo/demo_genui_test.dart`
/// checks them against the Iris library, so they cannot drift.
library;

import 'dart:convert';

import 'demo_script.dart';

/// What `iris_ui` answers when the plugin accepts a display.
const _accepted = '{"ok":true,"rev":1}';

String _display({
  required String surface,
  required String code,
  required String fallback,
  String placement = 'inline',
}) => jsonEncode({
  'surface_id': surface,
  'placement': placement,
  'fallback': fallback,
  'code': code,
});

final List<DemoScript> demoGenUiScripts = [
  DemoScript(
    prompt: 'Show me my deploy status',
    title: 'Deploy status',
    steps: [
      ThinkStep(
        'Pull the last deploy of each service and draw them as a card.',
      ),
      ToolStep(
        'iris_ui',
        input: _display(
          surface: 'deploy-status',
          fallback:
              'Deploy status: api deployed, p95 120 ms (ok); web deployed, '
              'p95 640 ms (slow); docs site deployed 2 hours ago (ok).',
          code: '''
root = Stack([title, card])
title = Text("Deploy status", "title")
card = Card([api, web, docs], "Production")
api = ListRow("api", "v2.14.0 · p95 120 ms", "ok")
web = ListRow("web", "v2.14.0 · p95 640 ms", "slow")
docs = ListRow("docs site", "deployed 2 hours ago", "ok")''',
        ),
        output: _accepted,
        duration: Duration(milliseconds: 1200),
      ),
      SayStep(
        'All three services are deployed. The API is healthy. The web app is '
        'the one to watch: its p95 is 640 ms, about five times the API.',
      ),
    ],
  ),
  DemoScript(
    prompt: 'Should I deploy the API to production?',
    title: 'Deploy the API?',
    steps: [
      ThinkStep('The staging run is green. Ask before I touch production.'),
      SayStep(
        'Staging passed every check for the API build 2.14.0. Do you want it '
        'in production now, or should I hold it?',
      ),
      ToolStep(
        'iris_ui',
        input: _display(
          surface: 'deploy-decision',
          placement: 'reply_kit',
          fallback: 'Deploy the API now, or hold off.',
          code: '''
root = Stack([now, hold], "row")
now = Button("Deploy now", @Ask("Deploy the API to production now"), "primary")
hold = Button("Hold off", @Ask("Hold off on deploying the API"), "secondary")''',
        ),
        output: _accepted,
        duration: Duration(milliseconds: 900),
      ),
    ],
  ),
  DemoScript(
    prompt: 'Set up my work profile',
    title: 'Iris setup',
    steps: [
      ThinkStep(
        'Read the recent work and see which displays would help: deploys, '
        'the daily plan. Propose them; the person keeps what they want.',
      ),
      ToolStep(
        'iris_profile_propose',
        input: jsonEncode({
          'summary':
              'Ships the API and web app to production most weekdays, and '
              'checks the services after each deploy.',
          'chips': ['Deploys', 'Daily plan'],
        }),
        output: '{"ok":true,"status":"proposed"}',
        duration: Duration(milliseconds: 900),
      ),
      ToolStep(
        'iris_template_propose',
        input: jsonEncode({
          'id': 'deploy-status',
          'name': 'Deploy status',
          'when': 'When you ask how the services are doing after a deploy',
          'data_schema': {
            'title': 'string',
            'rows': [
              {'name': 'string', 'detail': 'string', 'state': 'string'},
            ],
          },
          'program': '''
root = Stack([head, list])
head = Text(data.title, "title")
list = Stack(@Each(data.rows, "r", ListRow(r.name, r.detail, r.state)))''',
          'sample_data': {
            'title': 'Deploys this week',
            'rows': [
              {'name': 'api', 'detail': 'p95 120 ms', 'state': 'ok'},
              {'name': 'web', 'detail': 'p95 640 ms', 'state': 'slow'},
            ],
          },
        }),
        output: '{"ok":true,"status":"proposed"}',
        duration: Duration(milliseconds: 1100),
      ),
      ToolStep(
        'iris_template_propose',
        input: jsonEncode({
          'id': 'daily-plan',
          'name': 'Daily plan',
          'when': 'When you ask what is on today',
          'data_schema': {
            'title': 'string',
            'items': [
              {'task': 'string', 'when': 'string', 'state': 'string'},
            ],
          },
          'program': '''
root = Stack([head, list])
head = Text(data.title, "title")
list = Stack(@Each(data.items, "i", ListRow(i.task, i.when, i.state)))''',
          'sample_data': {
            'title': 'Today',
            'items': [
              {
                'task': 'Review the web latency',
                'when': '10:00',
                'state': 'open',
              },
              {
                'task': 'Ship the release notes',
                'when': '16:00',
                'state': 'open',
              },
            ],
          },
        }),
        output: '{"ok":true,"status":"proposed"}',
        duration: Duration(milliseconds: 1100),
      ),
      SayStep(
        'I have written a short profile of your work and two displays '
        'drawn from it: **Deploy status** and **Daily plan**. They are waiting '
        'for you to keep, rename or drop. Nothing changes until you do.',
      ),
    ],
  ),
];
