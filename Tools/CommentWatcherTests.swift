import Foundation

// Tests for CommentWatcher's matching rules — which comments deserve a
// notification, and which are noise. Run with ./test.sh.
//
// The whole app compiles as one module, so these build pull requests through
// the models' implicit memberwise initialisers rather than through JSON.

// MARK: - Fixtures

private let me = "pshinde9"
private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

/// Seconds after the fixture epoch, so orderings read plainly at the call site.
private func t(_ offset: TimeInterval) -> Date { epoch.addingTimeInterval(offset) }

private func comment(_ id: String,
                     by login: String,
                     at offset: TimeInterval,
                     body: String = "this looks good to me",
                     bot: Bool = false) -> PRComment {
    PRComment(id: id,
              url: "https://github.com/acme/app/pull/1#\(id)",
              createdAt: t(offset),
              bodyText: body,
              author: CommentAuthor(login: login, typename: bot ? "Bot" : "User"))
}

private func pr(_ number: Int,
                by author: String,
                timeline: [PRComment] = [],
                reviews: [PRComment] = [],
                threads: [[PRComment]] = [],
                resolvedThreads: [[PRComment]] = []) -> PullRequest {
    PullRequest(id: "pr\(number)",
                number: number,
                title: "Add a thing",
                url: "https://github.com/acme/app/pull/\(number)",
                isDraft: false,
                reviewDecision: nil,
                updatedAt: t(0),
                repository: Repo(nameWithOwner: "acme/app"),
                author: Author(login: author),
                comments: Nodes(nodes: timeline),
                reviews: Nodes(nodes: reviews),
                reviewThreads: Nodes(nodes:
                    threads.enumerated().map {
                        ReviewThread(id: "thread\($0.offset)", isResolved: false, comments: Nodes(nodes: $0.element))
                    }
                    + resolvedThreads.enumerated().map {
                        ReviewThread(id: "resolved\($0.offset)", isResolved: true, comments: Nodes(nodes: $0.element))
                    }))
}

private func lists(mine: [PullRequest] = [],
                   toReview: [PullRequest] = [],
                   commented: [PullRequest] = []) -> PRLists {
    PRLists(mine: mine, toReview: toReview, commented: commented, viewerLogin: me)
}

// MARK: - Harness

private var failures: [String] = []

private func expect<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    if actual == expected {
        print("  ok   \(name)")
    } else {
        print("  FAIL \(name)\n         expected: \(expected)\n         actual:   \(actual)")
        failures.append(name)
    }
}

// MARK: - Tests

private func testCommentsOnMyPRs() {
    print("comments on my pull requests")

    let stranger = lists(mine: [pr(1, by: me, timeline: [comment("c1", by: "ryannie29", at: 10)])])
    expect("a colleague's timeline comment notifies",
           CommentWatcher.events(in: stranger, since: t(0)).map(\.commentID), ["c1"])
    expect("and is tagged as being on my PR",
           CommentWatcher.events(in: stranger, since: t(0)).map(\.kind), [.onMyPR])

    let mineOwn = lists(mine: [pr(1, by: me, timeline: [comment("c1", by: me, at: 10)])])
    expect("my own comment is ignored",
           CommentWatcher.events(in: mineOwn, since: t(0)).count, 0)

    let inline = lists(mine: [pr(1, by: me, threads: [[comment("c1", by: "alanmarcero", at: 10)]])])
    expect("an inline code comment notifies",
           CommentWatcher.events(in: inline, since: t(0)).map(\.commentID), ["c1"])

    let withBody = lists(mine: [pr(1, by: me, reviews: [comment("r1", by: "meltach", at: 10, body: "needs a test")])])
    expect("a review summary with a body notifies",
           CommentWatcher.events(in: withBody, since: t(0)).map(\.commentID), ["r1"])

    let bareApprove = lists(mine: [pr(1, by: me, reviews: [comment("r1", by: "meltach", at: 10, body: "")])])
    expect("a bare approval with no body is ignored",
           CommentWatcher.events(in: bareApprove, since: t(0)).count, 0)

    let whitespaceOnly = lists(mine: [pr(1, by: me, reviews: [comment("r1", by: "meltach", at: 10, body: "  \n ")])])
    expect("a whitespace-only body is ignored",
           CommentWatcher.events(in: whitespaceOnly, since: t(0)).count, 0)
}

private func testBots() {
    print("bots")

    let noisy = lists(mine: [pr(1, by: me, timeline: [comment("c1", by: "dependabot", at: 10, bot: true)])])
    expect("an ordinary bot is ignored",
           CommentWatcher.events(in: noisy, since: t(0)).count, 0)

    let bugbot = lists(mine: [pr(1, by: me, timeline: [comment("c1", by: "cursor", at: 10, bot: true)])])
    expect("Bugbot notifies",
           CommentWatcher.events(in: bugbot, since: t(0)).map(\.commentID), ["c1"])
    expect("and is flagged so it gets the badged icon",
           CommentWatcher.events(in: bugbot, since: t(0)).map(\.isBugbot), [true])

    let human = lists(mine: [pr(1, by: me, timeline: [comment("c1", by: "ryannie29", at: 10)])])
    expect("a human is not flagged as Bugbot",
           CommentWatcher.events(in: human, since: t(0)).map(\.isBugbot), [false])
}

private func testRepliesToMe() {
    print("replies to my comments on other people's pull requests")

    let replied = lists(commented: [pr(2, by: "ZECTBynmo", threads: [[
        comment("mine", by: me, at: 10),
        comment("theirs", by: "ZECTBynmo", at: 20),
    ]])])
    expect("a reply after my comment notifies",
           CommentWatcher.events(in: replied, since: t(0)).map(\.commentID), ["theirs"])
    expect("and is tagged as a reply",
           CommentWatcher.events(in: replied, since: t(0)).map(\.kind), [.replyToMe])

    let notMyThread = lists(commented: [pr(2, by: "ZECTBynmo", threads: [[
        comment("a", by: "ZECTBynmo", at: 10),
        comment("b", by: "dperrera", at: 20),
    ]])])
    expect("a thread I never joined is ignored",
           CommentWatcher.events(in: notMyThread, since: t(0)).count, 0)

    let beforeMe = lists(commented: [pr(2, by: "ZECTBynmo", threads: [[
        comment("theirs", by: "ZECTBynmo", at: 10),
        comment("mine", by: me, at: 20),
    ]])])
    expect("a comment posted before mine is not a reply to me",
           CommentWatcher.events(in: beforeMe, since: t(0)).count, 0)

    let timelineOnly = lists(commented: [pr(2, by: "ZECTBynmo", timeline: [
        comment("mine", by: me, at: 10),
        comment("theirs", by: "ZECTBynmo", at: 20),
    ])])
    expect("an untracked timeline comment on their PR is ignored",
           CommentWatcher.events(in: timelineOnly, since: t(0)).count, 0)

    // review-requested:@me and commenter:@me overlap, so the same PR can arrive twice.
    let overlap = pr(2, by: "ZECTBynmo", threads: [[
        comment("mine", by: me, at: 10),
        comment("theirs", by: "ZECTBynmo", at: 20),
    ]])
    expect("a PR in both searches yields one event",
           CommentWatcher.events(in: lists(toReview: [overlap], commented: [overlap]), since: t(0)).count, 1)
}

private func testWatermark() {
    print("watermark")

    let pull = pr(1, by: me, timeline: [
        comment("old", by: "ryannie29", at: 10),
        comment("new", by: "ryannie29", at: 30),
    ])
    expect("only comments after the watermark notify",
           CommentWatcher.events(in: lists(mine: [pull]), since: t(20)).map(\.commentID), ["new"])
    expect("a comment exactly on the watermark is already seen",
           CommentWatcher.events(in: lists(mine: [pull]), since: t(30)).count, 0)
    expect("events come back oldest first",
           CommentWatcher.events(in: lists(mine: [pull]), since: t(0)).map(\.commentID), ["old", "new"])
}

private func testPreview() {
    print("preview")

    let wrapped = lists(mine: [pr(1, by: me, timeline: [
        comment("c1", by: "ryannie29", at: 10, body: "  first line\n\nsecond   line\t "),
    ])])
    expect("newlines and runs of space collapse",
           CommentWatcher.events(in: wrapped, since: t(0)).first?.preview, "first line second line")

    let long = String(repeating: "a", count: 200)
    let truncated = lists(mine: [pr(1, by: me, timeline: [comment("c1", by: "ryannie29", at: 10, body: long)])])
    expect("a long body is cut to 140 characters plus an ellipsis",
           CommentWatcher.events(in: truncated, since: t(0)).first?.preview,
           String(repeating: "a", count: 140) + "…")
}

private func testSplit() {
    print("flood control")

    let events = CommentWatcher.events(
        in: lists(mine: [pr(1, by: me, timeline: (1...8).map { comment("c\($0)", by: "ryannie29", at: TimeInterval($0) * 10) })]),
        since: t(0))
    expect("all eight qualify", events.count, 8)

    let few = CommentWatcher.split(Array(events.prefix(3)), cap: 5)
    expect("under the cap everything posts", few.posted.map(\.commentID), ["c1", "c2", "c3"])
    expect("with nothing left over", few.extra, 0)

    let many = CommentWatcher.split(events, cap: 5)
    expect("over the cap only the newest five post, oldest first",
           many.posted.map(\.commentID), ["c4", "c5", "c6", "c7", "c8"])
    expect("and the remainder is counted", many.extra, 3)
}

private func testMenuBadges() {
    print("menu badges")

    let quiet = pr(1, by: me)
    expect("a pull request with no threads has no badge", quiet.badges, "")

    let human = pr(1, by: me, threads: [[comment("c1", by: "ryannie29", at: 10)]])
    expect("an unresolved human thread shows a speech bubble", human.badges, " 💬")

    let bugbot = pr(1, by: me, threads: [[comment("c1", by: "cursor", at: 10, bot: true)]])
    expect("an unresolved Bugbot thread shows a bug", bugbot.badges, " 🐛")

    let both = pr(1, by: me, threads: [
        [comment("c1", by: "ryannie29", at: 10)],
        [comment("c2", by: "cursor", at: 20, bot: true)],
    ])
    expect("both kinds show both badges", both.badges, " 💬 🐛")

    let settled = pr(1, by: me, resolvedThreads: [[comment("c1", by: "ryannie29", at: 10)]])
    expect("a resolved thread clears the badge", settled.badges, "")

    let partly = pr(1, by: me,
                    threads: [[comment("c1", by: "ryannie29", at: 10)]],
                    resolvedThreads: [[comment("c2", by: "cursor", at: 20, bot: true)]])
    expect("resolving only the Bugbot thread leaves the speech bubble", partly.badges, " 💬")

    // Bugbot raises a thread; a colleague answers in it. It stays Bugbot's thread.
    let answered = pr(1, by: me, threads: [[
        comment("c1", by: "cursor", at: 10, bot: true),
        comment("c2", by: "ryannie29", at: 20),
    ]])
    expect("a thread is classified by who raised it", answered.badges, " 🐛")

    // Timeline comments have no resolved state, so they must never badge a row.
    let chatty = pr(1, by: me, timeline: [comment("c1", by: "ryannie29", at: 10)],
                    reviews: [comment("r1", by: "meltach", at: 20, body: "looks fine")])
    expect("timeline comments and review bodies never badge", chatty.badges, "")
}

@main
struct CommentWatcherTests {
    static func main() {
        testCommentsOnMyPRs()
        testBots()
        testRepliesToMe()
        testWatermark()
        testPreview()
        testSplit()
        testMenuBadges()

        print("")
        if failures.isEmpty {
            print("all tests passed")
        } else {
            print("\(failures.count) failed: \(failures.joined(separator: ", "))")
            exit(1)
        }
    }
}
