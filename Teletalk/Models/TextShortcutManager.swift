import Foundation
import os

struct TextAlias: Identifiable, Codable, Equatable {
    let id: UUID
    var trigger: String
    var expansion: String

    init(trigger: String, expansion: String) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
    }
}

@MainActor
@Observable
final class TextShortcutManager {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "TextShortcuts")

    private(set) var aliases: [TextAlias] = []
    private(set) var emojiDictionary: [String: String] = [:]
    private(set) var emojiLoaded = false
    private(set) var emojiLoading = false

    var onAliasesChanged: (() -> Void)?

    init() {
        loadAliases()
    }

    // MARK: - Alias CRUD

    func addAlias(_ alias: TextAlias) {
        aliases.append(alias)
        saveAliases()
        onAliasesChanged?()
    }

    func updateAlias(_ alias: TextAlias) {
        guard let idx = aliases.firstIndex(where: { $0.id == alias.id }) else { return }
        aliases[idx] = alias
        saveAliases()
        onAliasesChanged?()
    }

    func deleteAlias(_ alias: TextAlias) {
        aliases.removeAll { $0.id == alias.id }
        saveAliases()
        onAliasesChanged?()
    }

    // MARK: - Emoji Dictionary

    /// Downloads and parses the gemoji dictionary from GitHub.
    /// Call when emoji expansion is enabled and dictionary hasn't been loaded yet.
    func loadEmojiDictionaryIfNeeded() async {
        guard !emojiLoaded, !emojiLoading else { return }
        emojiLoading = true
        defer { emojiLoading = false }

        // Check for cached file first
        let cachedURL = storageDirectory.appendingPathComponent("emoji-cache.json")
        if let cached = try? Data(contentsOf: cachedURL),
           let dict = parseGemoji(data: cached)
        {
            emojiDictionary = dict
            emojiLoaded = true
            logger.info("Loaded emoji dictionary from cache (\(dict.count) entries)")
            return
        }

        // Download from GitHub
        guard let url = URL(string: Constants.TextShortcuts.emojiSourceURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let dict = parseGemoji(data: data) {
                emojiDictionary = dict
                emojiLoaded = true
                // Cache for next launch
                try? data.write(to: cachedURL, options: .atomic)
                logger.info("Downloaded emoji dictionary (\(dict.count) entries)")
            }
        } catch {
            logger.error("Failed to download emoji dictionary: \(error.localizedDescription)")
        }
    }

    /// Parses GitHub's gemoji format: [{emoji, aliases, tags, ...}, ...]
    private func parseGemoji(data: Data) -> [String: String]? {
        struct GemojiEntry: Decodable {
            let emoji: String
            let aliases: [String]
            let tags: [String]?
        }
        guard let entries = try? JSONDecoder().decode([GemojiEntry].self, from: data) else { return nil }

        var dict: [String: String] = [:]
        for entry in entries {
            for alias in entry.aliases {
                dict[alias.lowercased()] = entry.emoji
            }
            for tag in entry.tags ?? [] {
                // Don't override aliases with tags
                let key = tag.lowercased()
                if dict[key] == nil {
                    dict[key] = entry.emoji
                }
            }
        }
        return dict
    }

    // MARK: - Text Processing

    func expandAliases(in text: String) -> String {
        guard !aliases.isEmpty else { return text }
        var result = text
        for alias in aliases {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: alias.trigger))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: alias.expansion
                )
            }
        }
        return result
    }

    func expandEmoji(in text: String) -> String {
        guard emojiLoaded else { return text }
        let pattern = "\\bemoji\\s+(\\w+)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let keywordRange = Range(match.range(at: 1), in: result) else { continue }
            let keyword = String(result[keywordRange]).lowercased()
            if let emoji = emojiDictionary[keyword] {
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: emoji)
            }
        }
        return result
    }

    /// URL of the cached emoji JSON file, if it exists.
    var emojiCacheURL: URL? {
        let url = storageDirectory.appendingPathComponent("emoji-cache.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Persistence

    private var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TeleTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var aliasFileURL: URL {
        storageDirectory.appendingPathComponent(Constants.TextShortcuts.aliasFileName)
    }

    private func saveAliases() {
        do {
            let data = try JSONEncoder().encode(aliases)
            try data.write(to: aliasFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save aliases: \(error.localizedDescription)")
        }
    }

    private func loadAliases() {
        guard FileManager.default.fileExists(atPath: aliasFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: aliasFileURL)
            aliases = try JSONDecoder().decode([TextAlias].self, from: data)
        } catch {
            logger.error("Failed to load aliases: \(error.localizedDescription)")
        }
    }
}
