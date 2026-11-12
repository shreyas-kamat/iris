# The study, step by step

You are building a small, personal set of displays. Three or four good templates beat eight vague ones, so stop at what
the evidence supports: between 3 and 8 templates, 2 to 4 of which are reply kits, and one profile.

## 1. Gather

Read-only. Use whichever of these you have, and **never fabricate** what you did not read: if a source is not
available, skip it and say so at the end.

- **Memory**: what the person has told you about their work, tools and habits.
- **Past sessions**: `session_search` over about 90 days. Look for what they ask for again and again, the questions
  they put to you at the same time of day, and the shapes of the answers they liked.
- **Skills** they have installed or written: these show the work they have automated.
- **Scheduled jobs** (cron): what runs for them every day or week, and what they read the results of.
- **Kanban** boards or task lists, if present: what they track.
- **Toolsets** that are enabled: the systems they connect (deploys, calendars, finance, mail).

Keep notes as you go in your own words (topic, how often, what the answer looked like). Do not paste message text.

## 2. Infer the profile

`iris_profile_propose(summary, chips)`: one or two sentences about what they do (at most 600 characters), and up to 12
short chips (topics, tools, roles; at most 40 characters each). Describe the work, not the person: "Backend engineer who
ships and watches an API" rather than anything identifying.

```json profile
{
  "summary": "Backend engineer who ships a small API, watches deploys and cron jobs, and reviews pull requests most days.",
  "chips": ["APIs", "Deploys", "Cron jobs", "Pull requests", "On call"]
}
```

## 3. Propose templates

`iris_template_propose(id, name, when, data_schema, program, sample_data, kind?)`.

- A template is an OpenUI Lang **program that reads a top-level `data` object**. Never write `data = ...` yourself:
  Iris adds it from the data a reply gives. Write `data.title`, `@Each(data.rows, "r", ...)` and so on.
- `data_schema` is a JSON Schema with `"type": "object"` (at most 4 KB). Use `required`, `enum`, `maxLength` and
  `maxItems` so a reply cannot send something the display cannot hold.
- `sample_data` is **made-up** values that fit the schema (at most 4 KB). The person sees your template drawn with it.
- `name` is a short title (at most 60 characters). `when` is one line saying when to use it (at most 200).
- `kind` is `display` (a card in the reply, the default) or `reply_kit` (buttons or choices that dock above the
  composer). A reply kit usually ends in `ApproveReject`, `ChoiceChips` or `Submit`.
- It is checked before it is stored: the sample must fit the schema, and the program must validate with the sample.
  Fix any `errors` it returns, one line each.

Choose templates by what you saw repeated, for example:

- a status card for something they check often (deploys, jobs, builds, balances);
- a short list for something they scan (pull requests, tasks, meetings);
- a numbers strip for a daily figure, with a comparison;
- a reply kit for a decision you ask them over and over (approve or hold, which option, how long).

```json
{
  "id": "deploy-status",
  "name": "Deploy status",
  "when": "When reporting the state of a deploy or a service",
  "data_schema": {
    "type": "object",
    "properties": {
      "service": {"type": "string", "maxLength": 40},
      "state": {"type": "string", "enum": ["good", "warn", "bad"]},
      "label": {"type": "string", "maxLength": 30},
      "since": {"type": "string", "maxLength": 40},
      "checks": {"type": "array", "maxItems": 6, "items": {"type": "object"}}
    },
    "required": ["service", "state", "label", "since"]
  },
  "program": "root = Card([pill, since, checks], data.service)\npill = StatusPill(data.label, data.state)\nsince = KeyValue(\"Since\", data.since)\nchecks = Stack(@Each(data.checks, \"c\", ListRow(c.name, c.detail, c.result)))",
  "sample_data": {
    "service": "api",
    "state": "good",
    "label": "Healthy",
    "since": "09:12",
    "checks": [{"name": "Tests", "detail": "412 passed", "result": "ok"}, {"name": "Smoke", "detail": "3 routes", "result": "ok"}]
  }
}
```

```json
{
  "id": "decide-deploy",
  "name": "Deploy decision",
  "kind": "reply_kit",
  "when": "When asking whether to deploy, hold or look at something first",
  "data_schema": {
    "type": "object",
    "properties": {"question": {"type": "string", "maxLength": 120}},
    "required": ["question"]
  },
  "program": "root = Stack([q, choice])\nq = Text(data.question)\nchoice = ApproveReject(\"Deploy\", \"Hold\", \"Show me first\")",
  "sample_data": {"question": "The checks are green. Deploy the API now?"}
}
```

## What not to propose

- **Secrets and identifiers.** No tokens, keys, passwords, account numbers, private URLs, real names or addresses, in
  the program, the schema or the sample. Redact before you write; if the real value mattered to the shape, invent one
  of the same shape.
- **One-offs.** If you saw it once, it is not a template.
- **Duplicates.** Two templates with the same shape and the same use are one template; check
  `iris_template_list` first, and merge them in your head before you propose.
- **Decoration.** A display must beat the same text. If a plain sentence does the job, do not make a template of it.
- **Anything the library cannot draw.** Use only the components in the library reference; the check will reject the rest.

## 4. Finish

Reply in plain text: what you read (and what you could not), the profile you proposed, and the templates by name with a
line each on when they will be used. Say that nothing is used until they approve it in Iris. Do not show the
templates with `iris_ui` and do not claim anything was approved.
