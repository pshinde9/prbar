# PRBar

A macOS menu bar app that keeps your GitHub pull requests in front of you — the ones
you opened, and the ones waiting on your review — and tells you when someone replies.

## What it shows

Click the menu bar icon and you get two sections:

- **MINE** — your open pull requests
- **TO REVIEW** — pull requests where your review has been requested

Both are grouped by repository and sorted with the most recently updated first. Each
row carries a status glyph:

| | |
|---|---|
| 📝 | draft |
| ⏳ | waiting on review |
| ✅ | approved and ready to merge |
| 🔴 | changes requested |

After the status glyph, a row may carry one or two more marks:

| | |
|---|---|
| 💬 | unresolved review threads |
| 🐛 | unresolved Bugbot findings |

These count review threads only — the inline conversations attached to lines of code.
Resolving a thread on GitHub clears its mark on the next poll, which is what makes the
marks worth glancing at. Timeline comments and review summaries have no resolved state
on GitHub, so they deliberately never mark a row: a mark that can't be cleared would
only ever mean "someone once commented here".

Clicking a row opens that pull request in your browser.

## Notifications

It posts a notification the moment one of your own pull requests satisfies its
required approvals, so you find out it's mergeable without going looking. Each PR is
announced once; clicking the notification opens it.

It also tells you when a conversation moves:

- **Someone comments on a pull request you opened** — timeline comments, inline code
  comments, and the summary body of a review all count. Approving without writing
  anything doesn't, since there's nothing to read.
- **Someone replies to one of your comments on their pull request** — replies inside a
  review thread you've already posted in. GitHub's timeline comments have no threading,
  so only inline threads can tell a reply from an unrelated remark.

Each notification carries the first 140 characters of the message, and clicking it
opens that comment rather than the top of the pull request. Bots are left out, with
one exception: Cursor's Bugbot, whose banners open with a 🐛 so you can tell its
findings from a colleague's at a glance.

The first poll after installing only records where the conversation stands — it won't
replay everything you're already in the middle of. If a batch arrives at once, say
after your Mac wakes from a night's sleep, the five most recent get banners and the
rest are counted in a single summary.

A few smaller things: it polls every 5 minutes and again whenever your Mac wakes, so
the list isn't stale after a lid-open. Review requests that haven't moved in three
months are hidden, since they crowd out the ones that still matter. The bottom of the
menu shows when it last refreshed, plus **Refresh Now** (⌘R) and an **Open at Login**
toggle. If a fetch fails, the reason appears at the top of the menu instead of
silently showing an empty list.

## Requirements

- macOS 13 or later
- Xcode command line tools (for `swiftc`) — `xcode-select --install`
- The [GitHub CLI](https://cli.github.com) (`gh`), **installed and logged in**

PRBar has no token of its own and no login screen. It runs `gh auth token` and uses
whatever credentials the CLI already holds, which means it sees exactly the
repositories you do. If you haven't authenticated, run:

```bash
gh auth login
```

Without that, the menu shows *"Couldn't read a token from `gh auth token`"* — that's
the one thing that goes wrong on a first run. PRBar looks for `gh` in
`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and `~/.local/bin`; an install
somewhere else won't be found, because an app launched from Finder doesn't inherit
your shell's `PATH`.

## Install

```bash
git clone https://github.com/pshinde9/prbar.git
cd prbar
./install.sh
```

That compiles the app and installs it to `/Applications/PRBar.app`. Open it from
Applications and an icon appears in your menu bar. On first launch it registers
itself to open at login, and macOS asks whether to allow notifications — say yes, or
the approval alerts won't arrive.

It installs to `/Applications` rather than running from the source folder on purpose:
launch-at-login registration is tied to the bundle path, so a stable location matters.
Re-run `./install.sh` any time to rebuild and replace it.

## Uninstall

Switch **Open at Login** off in the menu first, then quit PRBar. That deregisters the
login item, which deleting the app alone won't do. Then:

```bash
rm -rf /Applications/PRBar.app
rm -rf ~/Library/Application\ Support/PRBar
```

The second path is just what it has already announced — approved pull requests, and
the timestamp of the newest comment you've been shown — kept so a restart doesn't
replay old notifications.

## Customizing

Two things people tend to want to change, both in `Sources/AppDelegate.swift`:

- **Poll interval** — `pollInterval` (line 12), in seconds. GitHub's GraphQL API allows
  5,000 points per hour, and each poll costs 1, so polling more often is fine.
- **Stale review cutoff** — the three-month window in `fresh()` (line 61).

Run `./install.sh` again after editing.

The menu bar icon is generated from `Resources/menubar.svg`. If you change the SVG,
run `Resources/make-icons.sh` to regenerate the PNGs and the `.icns`; `install.sh`
only copies the results.

## How it works

Five files, about 700 lines of Swift, no dependencies:

| | |
|---|---|
| `Sources/GitHubClient.swift` | one GraphQL query for every list, and the `gh auth token` lookup |
| `Sources/AppDelegate.swift` | polling, and building the menu |
| `Sources/CommentWatcher.swift` | which comments deserve a notification — pure rules, no I/O |
| `Sources/Notifier.swift` | tracking what's been announced, and posting the banners |
| `Sources/main.swift` | starts it as an accessory app (no Dock icon) |

The query also searches for open pull requests you've commented on that aren't yours.
Those never appear in the menu; they exist so replies to you can be spotted.

`./test.sh` runs the `CommentWatcher` rules against fixtures — self-authored comments,
the bot allowlist, reply detection, the watermark boundary, and the batch cap.

`install.sh` ad-hoc signs the bundle, which is required for both notification delivery
and `SMAppService` launch-at-login to work at all.

## License

MIT
