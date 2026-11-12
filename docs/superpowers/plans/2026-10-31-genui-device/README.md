# GenUI device pass (task 7.4)

Device: Moto G45 5G (Android, 720x1600), debug build of `feat/genui`, plugin `hermes-iris` 0.3.0 on the user's server.
Light mode and 320 pt were captured by turning system dark mode off and raising the density to 360 dpi (720 px / 2.25 = 320 dp).

| Screenshot | Shows |
|---|---|
| `android-settings-dark.png` | Generated displays group on 0.3.0: Study, Displays, Refine every week, plugin version |
| `android-card-dark.png` | Native card from a live turn; an empty BarChart degrades to a quiet "Can't show this part" |
| `android-charts-form-dark.png` | Bar and line charts with real numbers, environment chips, a replicas slider, a Submit button |
| `android-reply-kit-dark.png` | A reply kit docked above the composer |
| `android-card-light-320pt.png` | The card read back from history, light, 320 pt: **"Unknown" breaks mid-word in a three-stat row** |
| `android-home-light-320pt.png` | Home, light, 320 pt |

## TalkBack checklist (for the person holding the phone)

Turn on TalkBack (Settings, Accessibility), open the chat "Create deploy status card with stat row..." and swipe right one item at a time.

1. Each part of the card is reached and read with a meaningful label: title, status pill, each stat (name then value), each checklist item.
2. A checklist item says whether it is done or not done.
3. The charts say something useful (a summary, not "image" or silence).
4. The environment chips read as options and say which one is selected after a double tap.
5. The Replicas slider announces its value and changes with a swipe up or down.
6. "Submit for review" is reached and a double tap sends the message.
7. "Show all" is reached, a double tap expands the card, and the new content is reachable.
8. In a chat with a reply kit (the "Alpha Beta Gamma" one), the group is announced as "Suggested replies", each button is reachable, and "Dismiss suggested replies" works.
9. Nothing is announced twice, and focus does not jump to the top after an update.

Write down any item that fails and what TalkBack said.

VoiceOver (iOS): not done, no iPhone was available. Same list, plus the iOS date picker sheet.
