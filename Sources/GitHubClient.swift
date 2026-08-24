import Foundation

struct Repo: Decodable {
    let nameWithOwner: String
}

struct Author: Decodable {
    let login: String
}

/// GraphQL wraps every connection in a `nodes` array.
struct Nodes<T: Decodable>: Decodable {
    let nodes: [T]
}

struct CommentAuthor: Decodable {
    let login: String
    /// GitHub's `__typename` — "User" for people, "Bot" for app accounts.
    let typename: String

    enum CodingKeys: String, CodingKey {
        case login
        case typename = "__typename"
    }

    var isBot: Bool { typename == "Bot" }

    /// Cursor's Bugbot. GraphQL reports it as a Bot under this bare login, and
    /// it is the one bot whose comments are wanted.
    var isBugbot: Bool { login == "cursor" }
}

/// One piece of prose someone wrote on a pull request. Timeline comments,
/// review summaries and inline code comments all carry the same fields, so
/// they decode into the same type.
struct PRComment: Decodable {
    let id: String
    let url: String
    let createdAt: Date
    let bodyText: String
    /// Null for a since-deleted account.
    let author: CommentAuthor?
}

/// An inline code comment and its replies. The only place GitHub gives a pull
/// request conversation real threading, and so the only place a reply to one
/// of your comments can be recognised as such.
struct ReviewThread: Decodable {
    let id: String
    /// Marked resolved on GitHub. Timeline comments and review summaries have no
    /// equivalent, which is why only threads can drive a badge that clears.
    let isResolved: Bool
    let comments: Nodes<PRComment>

    /// Whoever wrote the earliest comment raised the thread, so a colleague
    /// answering one of Bugbot's findings leaves it Bugbot's thread.
    var isBugbot: Bool { comments.nodes.first?.author?.isBugbot == true }
}

struct PullRequest: Decodable {
    let id: String
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let reviewDecision: String?
    let updatedAt: Date
    let repository: Repo
    /// Null for pull requests opened by a since-deleted account.
    let author: Author?
    let comments: Nodes<PRComment>
    let reviews: Nodes<PRComment>
    let reviewThreads: Nodes<ReviewThread>

    /// True when the PR satisfies its repo's branch protection review requirement:
    /// required approvals are in, with no blocking change-requests.
    var isApproved: Bool { reviewDecision == "APPROVED" && !isDraft }

    /// Review threads still awaiting resolution. Resolving one on GitHub clears
    /// it here on the next poll.
    var unresolvedThreads: [ReviewThread] { reviewThreads.nodes.filter { !$0.isResolved } }

    /// Trails the status glyph in the menu: a speech bubble for outstanding
    /// discussion, a bug for outstanding Bugbot findings, both when both apply.
    var badges: String {
        var badges = ""
        if unresolvedThreads.contains(where: { !$0.isBugbot }) { badges += " 💬" }
        if unresolvedThreads.contains(where: \.isBugbot) { badges += " 🐛" }
        return badges
    }

    var glyph: String {
        if isDraft { return "📝" }
        switch reviewDecision {
        case "APPROVED": return "✅"
        case "CHANGES_REQUESTED": return "🔴"
        default: return "⏳"
        }
    }
}

struct PRLists {
    let mine: [PullRequest]
    let toReview: [PullRequest]
    /// Other people's pull requests that you have commented on. Not shown in
    /// the menu; it exists so replies to your comments can be spotted.
    let commented: [PullRequest]
    let viewerLogin: String
}

enum GitHubError: LocalizedError {
    case noToken
    case http(Int)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noToken: return "Couldn't read a token from `gh auth token`"
        case .http(let code): return "GitHub returned HTTP \(code)"
        case .api(let msg): return msg
        }
    }
}

enum GitHubClient {
    /// Timeline comments, review summaries and inline code comments are three
    /// different GraphQL types, so the identical field list is spelled three
    /// times — a fragment is bound to one type.
    private static let query = """
    fragment Timeline on IssueComment {
      id url createdAt bodyText author { login __typename }
    }
    fragment ReviewBody on PullRequestReview {
      id url createdAt bodyText author { login __typename }
    }
    fragment Inline on PullRequestReviewComment {
      id url createdAt bodyText author { login __typename }
    }
    fragment PR on PullRequest {
      id
      number
      title
      url
      isDraft
      reviewDecision
      updatedAt
      repository { nameWithOwner }
      author { login }
      comments(last: 15) { nodes { ...Timeline } }
      reviews(last: 15) { nodes { ...ReviewBody } }
      reviewThreads(last: 15) {
        nodes { id isResolved comments(last: 15) { nodes { ...Inline } } }
      }
    }
    query {
      viewer { login }
      mine: search(query: "is:pr is:open author:@me archived:false", type: ISSUE, first: 60) {
        nodes { ...PR }
      }
      toReview: search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 60) {
        nodes { ...PR }
      }
      commented: search(query: "is:pr is:open commenter:@me -author:@me archived:false", type: ISSUE, first: 60) {
        nodes { ...PR }
      }
    }
    """

    /// Locates the `gh` binary. A menu bar app launched from Finder gets a
    /// minimal PATH, so the usual install locations are checked explicitly.
    private static func ghPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
            NSHomeDirectory() + "/.local/bin/gh",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func token() -> String? {
        guard let gh = ghPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["auth", "token"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func fetch(completion: @escaping (Result<PRLists, Error>) -> Void) {
        guard let token = token() else {
            completion(.failure(GitHubError.noToken))
            return
        }

        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { return completion(.failure(error)) }
            if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
                return completion(.failure(GitHubError.http(code)))
            }
            guard let data else { return completion(.failure(GitHubError.api("Empty response"))) }
            do {
                completion(.success(try decode(data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private struct Envelope: Decodable {
        struct Viewer: Decodable { let login: String }
        struct Data: Decodable {
            let viewer: Viewer
            let mine: Nodes<PullRequest>
            let toReview: Nodes<PullRequest>
            let commented: Nodes<PullRequest>
        }
        struct APIError: Decodable { let message: String }
        let data: Data?
        let errors: [APIError]?
    }

    private static func decode(_ data: Data) throws -> PRLists {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubError.api(errors.map(\.message).joined(separator: "; "))
        }
        guard let payload = envelope.data else { throw GitHubError.api("No data in response") }
        return PRLists(mine: payload.mine.nodes,
                       toReview: payload.toReview.nodes,
                       commented: payload.commented.nodes,
                       viewerLogin: payload.viewer.login)
    }
}
