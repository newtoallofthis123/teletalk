import Foundation
import os

struct DictionaryTerm: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var aliases: [String]

    init(text: String, aliases: [String] = []) {
        self.id = UUID()
        self.text = text
        self.aliases = aliases
    }
}

@MainActor
@Observable
final class PersonalDictionary {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Dictionary")

    private(set) var terms: [DictionaryTerm] = []

    var onTermsChanged: (() -> Void)?

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TeleTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Constants.Dictionary.fileName)
    }

    init() {
        load()
    }

    func add(_ term: DictionaryTerm) {
        terms.append(term)
        save()
        onTermsChanged?()
    }

    func update(_ term: DictionaryTerm) {
        guard let idx = terms.firstIndex(where: { $0.id == term.id }) else { return }
        terms[idx] = term
        save()
        onTermsChanged?()
    }

    func delete(_ term: DictionaryTerm) {
        terms.removeAll { $0.id == term.id }
        save()
        onTermsChanged?()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(terms)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save dictionary: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            terms = try JSONDecoder().decode([DictionaryTerm].self, from: data)
        } catch {
            logger.error("Failed to load dictionary: \(error.localizedDescription)")
        }
    }
}
