import Foundation

public struct Memory: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let app: String
    public let title: String
    public let text: String
    public let imagePath: String
    public let sourceURL: String?
    public let snippet: String

    public init(id: String = UUID().uuidString, date: Date = Date(), app: String, title: String,
                text: String, imagePath: String, sourceURL: String? = nil, snippet: String? = nil) {
        self.id = id
        self.date = date
        self.app = app
        self.title = title
        self.text = text
        self.imagePath = imagePath
        self.sourceURL = sourceURL
        self.snippet = snippet ?? String(text.prefix(240))
    }
}

public enum SearchQuery {
    public static func terms(_ input: String) -> [String] {
        let noise: Set<String> = ["a", "an", "and", "are", "at", "can", "did", "do", "for", "from",
            "hey", "how", "i", "in", "is", "it", "me", "my", "of", "on", "or", "please", "saw",
            "show", "some", "that", "the", "this", "to", "was", "what", "when", "where", "which", "with"]
        let words = input.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let useful = words.filter { !noise.contains($0) }
        return Array(Set(useful.isEmpty ? words : useful).sorted().prefix(20))
    }

    public static func expression(_ input: String) -> String? {
        let terms = terms(input)
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"*" }.joined(separator: " OR ")
    }

    public static func safeURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
}
