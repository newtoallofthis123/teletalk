import Foundation
import os

struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let audioDurationSeconds: Double
    let modelVersion: String

    init(text: String, audioDurationSeconds: Double, modelVersion: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.audioDurationSeconds = audioDurationSeconds
        self.modelVersion = modelVersion
    }

    var wordCount: Int {
        text.split(separator: " ").count
    }
}

@MainActor
@Observable
final class TranscriptionHistory {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "History")

    private(set) var entries: [TranscriptionEntry] = []

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TeleTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Constants.History.fileName)
    }

    init() {
        load()
    }

    func add(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Constants.History.maxEntries {
            entries = Array(entries.prefix(Constants.History.maxEntries))
        }
        save()
    }

    func delete(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Today's Stats

    var todayEntries: [TranscriptionEntry] {
        entries.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    var todayWordCount: Int {
        todayEntries.reduce(0) { $0 + $1.wordCount }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription)")
        }
    }
}
