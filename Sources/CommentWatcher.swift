import Foundation

/// One comment worth telling you about, already stripped of everything that
/// isn't: your own writing, bot chatter, and anything you've been shown before.
struct CommentEvent {
    enum Kind: Equatable {
        /// Someone else wrote on a pull request you opened.
        case onMyPR
        /// Someone answered you in a review thread on someone else's pull request.
        case replyToMe
    }

    let kind: Kind
    let commentID: String
    let author: String
    let isBugbot: Bool
    let repo: String
    let prNumber: Int
    let prTitle: String
    let preview: String
    let url: String
    let createdAt: Date
}

/// Turns a poll's worth of pull requests into the comment events that deserve a
/// banner. Pure: no network, no disk, no notifications — which is what makes the
/// rules here testable on their own.
enum CommentWatcher {
    private static let previewLimit = 140

    static func events(in lists: PRLists, since watermark: Date) -> [CommentEvent] {
        var events: [CommentEvent] = []

        for pr in lists.mine {
            let all = pr.comments.nodes + pr.reviews.nodes + pr.reviewThreads.nodes.flatMap(\.comments.nodes)
            events += all
                .filter { qualifies($0, viewer: lists.viewerLogin, after: watermark) }
                .map { event(.onMyPR, $0, pr) }
        }

        // review-requested:@me and commenter:@me overlap, and neither should
        // include a pull request of your own — but guard rather than assume.
        for pr in lists.toReview + lists.commented where pr.author?.login != lists.viewerLogin {
            for thread in pr.reviewThreads.nodes {
                guard let mine = thread.comments.nodes
                    .filter({ $0.author?.login == lists.viewerLogin })
                    .map(\.createdAt)
                    .min() else { continue }

                events += thread.comments.nodes
                    .filter { $0.createdAt > mine }
                    .filter { qualifies($0, viewer: lists.viewerLogin, after: watermark) }
                    .map { event(.replyToMe, $0, pr) }
            }
        }

        var seen = Set<String>()
        return events
            .filter { seen.insert($0.commentID).inserted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Splits events into the ones to post individually and a count for the
    /// rest. Waking from a long sleep can surface a whole day of conversation,
    /// and a screen full of banners is worse than a tally.
    static func split(_ events: [CommentEvent], cap: Int) -> (posted: [CommentEvent], extra: Int) {
        guard events.count > cap else { return (events, 0) }
        return (Array(events.suffix(cap)), events.count - cap)
    }

    // MARK: - Rules

    private static func qualifies(_ comment: PRComment, viewer: String, after watermark: Date) -> Bool {
        guard let author = comment.author else { return false }
        guard author.login != viewer else { return false }
        guard !author.isBot || author.isBugbot else { return false }
        guard comment.createdAt > watermark else { return false }
        // Approving without writing anything still creates a review.
        return !preview(comment.bodyText).isEmpty
    }

    private static func event(_ kind: CommentEvent.Kind, _ comment: PRComment, _ pr: PullRequest) -> CommentEvent {
        CommentEvent(kind: kind,
                     commentID: comment.id,
                     author: comment.author?.login ?? "someone",
                     isBugbot: comment.author?.isBugbot == true,
                     repo: pr.repository.nameWithOwner,
                     prNumber: pr.number,
                     prTitle: pr.title,
                     preview: preview(comment.bodyText),
                     url: comment.url,
                     createdAt: comment.createdAt)
    }

    /// Notification bodies are a couple of lines of plain text, so paragraph
    /// breaks and indentation become single spaces.
    private static func preview(_ body: String) -> String {
        let collapsed = body
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count > previewLimit else { return collapsed }
        return collapsed.prefix(previewLimit) + "…"
    }
}
