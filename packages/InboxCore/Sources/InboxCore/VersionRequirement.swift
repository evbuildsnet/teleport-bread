import Foundation

/// Bundle versions are numeric components, with omitted trailing zeros equal.
struct AppVersion: Comparable {
    private let components: [Int]

    init?(_ value: String) {
        var components: [Int] = []
        for part in value.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let number = Int(part) else { return nil }
            components.append(number)
        }
        while components.last == 0 { components.removeLast() }
        self.components = components
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

/// Invalid policy data cannot lock anyone out. URLs may be unpublished.
public struct VersionRequirement: Sendable {
    public enum Platform: String, Sendable { case ios, mac }

    public let minimum: String
    public let latest: String
    public let message: String?
    public let required: Bool
    public let available: Bool
    private let store: String?
    private let testflight: String?

    public init?(data: Data, platform: Platform, currentVersion: String) {
        guard let policies = try? JSONDecoder().decode([String: Policy].self, from: data),
              let policy = policies[platform.rawValue],
              let current = AppVersion(currentVersion),
              let minimum = AppVersion(policy.minimum),
              let latest = AppVersion(policy.latest),
              minimum <= latest else { return nil }
        self.minimum = policy.minimum
        self.latest = policy.latest
        let message = policy.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.message = message.flatMap { $0.isEmpty ? nil : $0 }
        required = current < minimum
        available = current < latest
        store = policy.store
        testflight = policy.testflight
    }

    public func updateURL(isTestFlight: Bool) -> URL? {
        if isTestFlight, let url = Self.publishedURL(testflight) { return url }
        return Self.publishedURL(store) ?? URL(string: "https://teleportbread.com")
    }

    private static func publishedURL(_ value: String?) -> URL? {
        guard let value, !value.uppercased().contains("PLACEHOLDER"),
              let url = URL(string: value), url.scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private struct Policy: Decodable {
        let minimum: String
        let latest: String
        let message: String?
        let store: String?
        let testflight: String?
    }
}
