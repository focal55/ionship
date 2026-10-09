# Waiting on you: design

Approved in conversation on 2026-10-09.

## Goal

Ode's home screen answers one question: **who needs to hear from me?** It replaces opening on the first person's thread. Success means Joe opens Ode, works down one list, and sends replies that start from it.

## What the list holds

One list across every tracked conversation, in this priority order:

| Kind | Rule | Row text |
|---|---|---|
| Asked you | 1:1 only. Their last message came after your last message and contains `?`. | Their message |
| Unanswered | 1:1 only. Their last message came after your last message and is not a closer. | Their message |
| Promised | Any conversation. A confirmed open loop (existing `OpenLoops` judging). | "You said you'd {task}" |
| Gone quiet | 1:1 only. `RelationshipMetrics.Observation.overdue` is present. | "You usually talk every {usual}; it's been {since}" |

Within a kind, the oldest item comes first. A conversation appears at most once, under its highest-priority kind.

### Unanswered rules (new, in OdeCore)

- Only text and attachment messages count as spoken messages. A **reaction from you** after their last spoken message counts as an answer.
- **Window:** their message must be at least 1 hour old and at most 21 days old. Newer messages aren't waiting yet; older ones are left to "gone quiet".
- **Closers** never count as unanswered. A closer is a message whose whole text, after trimming and lowercasing, ignoring trailing punctuation and emoji, is one of: ok, okay, k, kk, thanks, thank you, thx, ty, lol, haha, hahaha, lmao, nice, cool, sounds good, got it, np, no problem, you too, will do, perfect, great, 👍, ❤️. A message that contains `?` is never a closer.
- If they sent several messages after your last one, the row shows the latest, and the kind is "asked you" if any of them contains `?`.

## Screen

- **Sidebar:** a "Waiting on you" entry above Pinned, showing a count. The app opens on it.
- **Center:** a list of rows, each with the avatar, name, kind label, the row text (two lines at most), how long ago, and three actions:
  - **Reply** opens `DraftComposerView` with a steer. Asked you: "answer their question". Unanswered: "reply to their last message". Promised: "follow up on: {task}". Gone quiet: "reconnect".
  - **Open thread** selects the person on the Thread tab.
  - **Done** hides the row until a newer message arrives in that conversation. The hidden set is stored in UserDefaults as a map of conversation id to the id of the newest message at the time.
- **Empty state:** "Nobody's waiting on you", plus how many conversations Ode is watching.
- The Lens is hidden on this screen.
- Promises fill in asynchronously; until open-loop judging finishes, a quiet "checking promises" line shows at the bottom of the list.

## Behavior

- At launch, after analysis, open-loop judging runs in the background for every tracked person, using the existing per-person cache. With Apple Intelligence off, unchecked candidates are not shown on this list.
- Live sync updates the list as messages arrive: a new message from them adds or refreshes a row, a new message from you removes it.

## Out of scope

Notifications, a menu-bar list, unanswered messages in group chats, and the check-my-draft coach.

## Testing

- **OdeCore, test-first:** each unanswered rule (window bounds, closers, `?`, reactions as answers, multiple trailing messages, groups excluded), plus ranking and de-duplication across kinds.
- **App:** a manual check against real data, and a preview with sample rows of every kind.
