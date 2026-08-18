# PRBar

A macOS menu bar app that keeps your GitHub pull requests in front of you — the ones
you opened, and the ones waiting on your review.

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

Clicking a row opens that pull request in your browser.

It also posts a notification the moment one of your own pull requests satisfies its
required approvals, so you find out it's mergeable without going looking. Each PR is
announced once; clicking the notification opens it.

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

The second path is just the list of PRs it has already announced, kept so a restart
doesn't replay old notifications.

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

Four files, about 450 lines of Swift, no dependencies:

| | |
|---|---|
| `Sources/GitHubClient.swift` | one GraphQL query for both lists, and the `gh auth token` lookup |
| `Sources/AppDelegate.swift` | polling, and building the menu |
| `Sources/Notifier.swift` | newly-approved detection and notifications |
| `Sources/main.swift` | starts it as an accessory app (no Dock icon) |

`install.sh` ad-hoc signs the bundle, which is required for both notification delivery
and `SMAppService` launch-at-login to work at all.

## License

MIT
