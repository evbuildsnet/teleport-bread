Teleport Bread is effectively a rethink of how people organize their needs.

The name comes from Team Fortress 2's "Expiration Date" short: Soldier proudly announces "I have done nothing but teleport bread for three days" — three days of diligent, completely pointless work. That's the failure mode this app exists to prevent: mistaking motion for progress. Stop teleporting bread; do what matters.

Motivation: Everyone is so busy and have a lot of things to keep in their head. There are a lot of techniques how to organize your life with a ready to use system. You still need to spend time to organize things around.

We are building an alternative to complex systems. Main idea is to focus your attention to staff that matters for you now. I find it useful to have a place where you can put your immidiate thoughts, set due date when you want to return to it and have a way to "complete".

It also should be in the ecosystem where you spend most of your life: in my case it's Apple. There is no clear UI that is simple and convenient enough to support my need. The closest match is Reminders. However UI-wise it's ugly and slow me down.

Teleport Bread intentionally built as another UI for reminders. It's in Apple ecosystem: means it's Secure and private at zero-cost. It follows inbox zero principles to save your attention to things that matters.

There are few things to clarify for human-agents communication. Let's get acquinted with terms and how they relate to reminders.

- **need** is the concept we are building around. It's a short headline of what you need now or in future. Need is effectively a reminder.
- **note** is message for your future self or just a note that belongs to specific need. It built like a chat to recreate an experience like you message yourself. Best use case is to track how you going and leave small things related to the need in one place. It's might be not the best place to maintain your local database, but it's quite useful to have memos for specific need to come back in future.
- **snooze** need means to change it due date. Snoozed needs are in a separate bucket to keep your focus on things that need immidiate attention.
- **settle** need means you completed it. it should be a moment of glory and that's the target action that should be addictive and motivate people to be more productive.

## Mac distribution

Two Mac targets share one code base (`app/project.yml`, template `MacApp`):

- `TeleportBreadMac` — Mac App Store. Sandboxed, no updater; Apple ships updates.
- `TeleportBreadMacDirect` — notarized download from teleportbread.com. Same sandbox plus Sparkle, compiled in only under the `DIRECT` condition (`app/Mac/Updater.swift`). Automatic update checks are off until the user opts in from Settings, so the app makes no network calls by default.

Releasing the direct build is one action: push a tag `vX.Y.Z`. `.github/workflows/release-direct.yml` archives, notarizes, signs the zip for Sparkle, publishes a GitHub Release, and commits `website/public/appcast.xml` to main. The appcast commit is the moment users can see the update. The private Sparkle key lives in the `SPARKLE_PRIVATE_KEY` secret and in Ev's login Keychain; losing it means shipped apps can never update again.

To rehearse an update locally: build two versions of the Direct target, zip the newer one, run `scripts/appcast.sh` on it with a loopback URL prefix, serve that folder over HTTP, and launch the older build with `TELEPORTBREAD_FEED_URL` pointing at the local appcast (debug builds only).
