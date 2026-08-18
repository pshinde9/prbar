import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let notifier = Notifier()
    private var timer: Timer?
    private var lists = PRLists(mine: [], toReview: [])
    private var lastError: String?
    private var lastUpdated: Date?

    private static let pollInterval: TimeInterval = 300

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let icon = NSImage(named: "MenuBarIconTemplate")
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
            button.image = icon
            button.image?.accessibilityDescription = "GitHub pull requests"
        }
        enableLaunchAtLoginOnFirstRun()
        rebuildMenu()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // Timers don't fire while the Mac is asleep, so without this the first
        // poll after a lid-open could be a full interval away.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refresh),
            name: NSWorkspace.didWakeNotification,
            object: nil)
    }

    @objc private func refresh() {
        GitHubClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let lists):
                    self.lists = PRLists(mine: lists.mine, toReview: self.fresh(lists.toReview))
                    self.lastError = nil
                    self.lastUpdated = Date()
                    self.notifier.process(mine: lists.mine)
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
                self.rebuildMenu()
            }
        }
    }

    /// Review requests that haven't moved in three months are effectively
    /// abandoned, and they crowd out the ones that still matter.
    private func fresh(_ prs: [PullRequest]) -> [PullRequest] {
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -3, to: Date()) else { return prs }
        return prs.filter { $0.updatedAt > cutoff }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        if let lastError {
            menu.addItem(disabled("⚠️  \(lastError)"))
            menu.addItem(.separator())
        }

        addSection(to: menu, title: "MINE", prs: lists.mine)
        menu.addItem(.separator())
        addSection(to: menu, title: "TO REVIEW", prs: lists.toReview, showsAuthor: true)
        menu.addItem(.separator())

        if let lastUpdated {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            menu.addItem(disabled("Updated \(formatter.string(from: lastUpdated))"))
        }

        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem(title: "Quit PRBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func addSection(to menu: NSMenu, title: String, prs: [PullRequest], showsAuthor: Bool = false) {
        menu.addItem(header("\(title)  (\(prs.count))"))

        guard !prs.isEmpty else {
            menu.addItem(disabled("    Nothing here"))
            return
        }

        let byRepo = Dictionary(grouping: prs) { $0.repository.nameWithOwner }
        for repo in byRepo.keys.sorted() {
            menu.addItem(disabled("  \(repo)"))
            let sorted = byRepo[repo]!.sorted { $0.updatedAt > $1.updatedAt }
            for pr in sorted {
                var label = "    \(pr.glyph)  #\(pr.number)"
                if showsAuthor, let login = pr.author?.login { label += "  @\(login)" }
                label += "  \(pr.title)"

                let item = NSMenuItem(title: label, action: #selector(openPR(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pr.url
                item.toolTip = pr.title
                menu.addItem(item)
            }
        }
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func disabled(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    @objc private func openPR(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Launch at login

    /// Registers on first launch only. If you later switch it off from the
    /// menu, that choice sticks instead of being re-applied on next launch.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didRegisterLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Left unflagged so the next launch tries again.
            lastError = "Couldn't enable launch at login: \(error.localizedDescription)"
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
        rebuildMenu()
    }
}
