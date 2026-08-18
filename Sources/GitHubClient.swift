import Foundation

struct Repo: Decodable {
    let nameWithOwner: String
}

struct Author: Decodable {
    let login: String
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

    /// True when the PR satisfies its repo's branch protection review requirement:
    /// required approvals are in, with no blocking change-requests.
    var isApproved: Bool { reviewDecision == "APPROVED" && !isDraft }

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
    private static let query = """
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
    }
    query {
      mine: search(query: "is:pr is:open author:@me archived:false", type: ISSUE, first: 60) {
        nodes { ...PR }
      }
      toReview: search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 60) {
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
        struct Nodes: Decodable { let nodes: [PullRequest] }
        struct Data: Decodable { let mine: Nodes; let toReview: Nodes }
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
        return PRLists(mine: payload.mine.nodes, toReview: payload.toReview.nodes)
    }
}
