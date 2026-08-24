import AppKit
import UserNotifications

/// Posts a notification the moment one of your PRs satisfies its required
/// approvals, and when someone comments on your work. Remembers what it has
/// already announced so a restart doesn't replay it.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var announced: Set<String>
    private let stateURL: URL

    /// Newest comment already announced. Nil until the first poll seeds it, so
    /// installing the feature doesn't replay every conversation you're in.
    private var watermark: Date?
    private let watermarkURL: URL

    private static let notificationCap = 5

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PRBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        stateURL = support.appendingPathComponent("announced.json")
        watermarkURL = support.appendingPathComponent("comments.json")

        let saved = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        announced = Set(saved ?? [])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        watermark = (try? Data(contentsOf: watermarkURL))
            .flatMap { try? decoder.decode(Watermark.self, from: $0) }?
            .seen
        super.init()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func process(lists: PRLists) {
        processApprovals(in: lists.mine)
        processComments(in: lists)
    }

    /// Compares this poll's approved set against the last one. Anything newly
    /// approved gets announced; anything that closed or fell back out of the
    /// approved state is forgotten, so it can announce again if it returns.
    private func processApprovals(in mine: [PullRequest]) {
        let approved = mine.filter(\.isApproved)
        let approvedIDs = Set(approved.map(\.id))
        let newlyApproved = approved.filter { !announced.contains($0.id) }

        announced = approvedIDs
        try? JSONEncoder().encode(Array(announced)).write(to: stateURL)

        for pr in newlyApproved { post(pr) }
    }

    // MARK: - Comments

    private struct Watermark: Codable {
        let seen: Date
    }

    /// Announces comments newer than the watermark, then moves the watermark
    /// past everything considered — including anything the cap held back, so a
    /// backlog is summarised once rather than re-announced every poll.
    private func processComments(in lists: PRLists) {
        guard let watermark else {
            // First poll after install: start the clock, stay quiet.
            save(watermark: Date())
            return
        }

        let events = CommentWatcher.events(in: lists, since: watermark)
        guard let newest = events.map(\.createdAt).max() else { return }

        let (posted, extra) = CommentWatcher.split(events, cap: Self.notificationCap)
        for event in posted { post(event) }
        if extra > 0 { postSummary(extra) }

        save(watermark: newest)
    }

    private func save(watermark date: Date) {
        watermark = date
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(Watermark(seen: date)).write(to: watermarkURL)
    }

    private func post(_ event: CommentEvent) {
        let content = UNMutableNotificationContent()
        if event.isBugbot {
            content.title = "🐛 Bugbot found something"
        } else {
            content.title = event.kind == .replyToMe
                ? "↩️ @\(event.author) replied"
                : "💬 @\(event.author) commented"
        }
        content.subtitle = "\(event.repo) #\(event.prNumber) — \(event.prTitle)"
        content.body = event.preview
        content.sound = .default
        // The comment permalink, so clicking lands on the remark itself.
        content.userInfo = ["url": event.url]

        let request = UNNotificationRequest(identifier: event.commentID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func postSummary(_ count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "PRBar"
        content.body = "and \(count) more comment\(count == 1 ? "" : "s")"
        content.sound = .default
        content.userInfo = ["url": "https://github.com/notifications"]

        let request = UNNotificationRequest(identifier: "summary-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func post(_ pr: PullRequest) {
        let content = UNMutableNotificationContent()
        content.title = "Ready to merge — \(pr.repository.nameWithOwner)"
        content.body = "#\(pr.number) \(pr.title)"
        content.sound = .default
        content.userInfo = ["url": pr.url]

        let request = UNNotificationRequest(identifier: pr.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        handler()
    }
}
