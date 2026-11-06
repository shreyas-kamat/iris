# Worked examples

Every program below is checked against the Iris library by the plugin's tests, so each one is valid. Adapt them; do not
copy their data.

## 1. A status card

```openui
root = Stack([title, card])
title = Text("Cron jobs", "title")
card = Card([status, last, next], "backup")
status = StatusPill("Healthy", "good")
last = KeyValue("Last run", "03:00, took 42 s")
next = KeyValue("Next run", "tomorrow 03:00")
```

## 2. Numbers at a glance

```openui
root = Stack([title, stats])
title = Text("This week", "title")
stats = StatRow([Stat("Sessions", "42", "+6", "up"), Stat("Errors", "3", "-2", "down"), Stat("Spend", "$4.10", null, "flat")])
```

## 3. A list of things

```openui
root = Card([row1, row2, row3], "Open pull requests")
row1 = ListRow("Fix reconnect loop", "#212 · you", "review")
row2 = ListRow("Add usage widget", "#215 · you", "draft")
row3 = ListRow("Bump Flutter", "#219 · dependabot", "green")
```

## 4. Progress

```openui
root = Stack([title, bar, note])
title = Text("Migration", "title")
bar = Progress(@Percent(340, 500), "340 of 500 rows")
note = Text("About four minutes left.", "caption")
```

## 5. Sections

```openui
root = Stack([overview, details])
overview = Section("Overview", [summary])
summary = Text("Everything deployed; web is slower than usual.")
details = Section("Services", [api, web])
api = ListRow("api", "p95 120 ms", "ok")
web = ListRow("web", "p95 640 ms", "slow")
```

## 6. Two things side by side

```openui
root = Stack([left, right], "row")
left = Card([a1, a2], "Plan A")
a1 = KeyValue("Cost", "$12")
a2 = KeyValue("Time", "2 days")
right = Card([b1, b2], "Plan B")
b1 = KeyValue("Cost", "$30")
b2 = KeyValue("Time", "4 hours")
```

## 7. A reply kit (the person taps their answer)

Send with `placement: "reply_kit"`. Your text still asks the question.

```openui
root = Stack([yes, later, no], "row")
yes = Button("Restart it", @Ask("Yes, restart the sync job"), "primary")
later = Button("Tomorrow", @Ask("Remind me about the sync job tomorrow"), "secondary")
no = Button("Leave it", @Ask("No, leave the sync job alone"), "secondary")
```

## 8. A template with data

With a template whose program reads `data.title` and `data.rows`, send only the data:

```
iris_ui(surface_id="jobs", template="job-list", fallback="...",
        data={"title": "Jobs", "rows": [{"name": "backup", "state": "ok"}, {"name": "sync", "state": "failed"}]})
```

The plugin expands it to this program, which you can also write by hand:

```openui
data = {"title": "Jobs", "rows": [{"name": "backup", "state": "ok"}, {"name": "sync", "state": "failed"}]}
root = Stack([head, list])
head = Text(data.title, "title")
list = Stack(@Each(data.rows, "r", ListRow(r.name, null, r.state)))
```

## 9. Totals computed from the data

```openui
data = {"items": [{"name": "api", "ms": 120}, {"name": "web", "ms": 640}, {"name": "db", "ms": 35}]}
root = Stack([title, stats])
title = Text("Latency", "title")
stats = StatRow([Stat("Slowest", "" + @Max(data.items.ms) + " ms"), Stat("Average", "" + @Round(@Avg(data.items.ms)) + " ms"), Stat("Services", "" + @Count(data.items))])
```

## 10. Updating a display

Call `iris_ui` again with the same `surface_id` and the new program; the old one is replaced and `rev` goes up. Delete
one with `iris_ui(surface_id="deploys", delete=true)`.
