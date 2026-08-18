import AppKit
import UserNotifications

/// Posts a notification the moment one of your PRs satisfies its required
/// approvals, and remembers which ones it already announced so a restart
/// doesn't replay them.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var announced: Set<String>
    private let stateURL: URL

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PRBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        stateURL = support.appendingPathComponent("announced.json")

        let saved = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        announced = Set(saved ?? [])
        super.init()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Compares this poll's approved set against the last one. Anything newly
    /// approved gets announced; anything that closed or fell back out of the
    /// approved state is forgotten, so it can announce again if it returns.
    func process(mine: [PullRequest]) {
        let approved = mine.filter(\.isApproved)
        let approvedIDs = Set(approved.map(\.id))
        let newlyApproved = approved.filter { !announced.contains($0.id) }

        announced = approvedIDs
        try? JSONEncoder().encode(Array(announced)).write(to: stateURL)

        for pr in newlyApproved { post(pr) }
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
