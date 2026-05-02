import Foundation

struct GenerationProject: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var notes: String?

    static func `default`(createdAt: Date = Date()) -> GenerationProject {
        GenerationProject(
            id: UUID(),
            name: "默认项目",
            createdAt: createdAt,
            updatedAt: createdAt,
            isArchived: false,
            notes: nil
        )
    }
}

struct GenerationBatch: Codable, Identifiable, Hashable {
    let id: UUID
    let projectId: UUID
    var sequenceNumber: Int
    let createdAt: Date
    var updatedAt: Date
    var name: String?
    let baseURL: String
    let model: String
    let prompt: String
    let lyrics: String
    let outputFormat: String
    let audioFormat: String
    let sampleRate: Int
    let bitrate: Int
    let lyricsOptimizer: Bool
    let aigcWatermark: Bool
    let instrumental: Bool
    let referenceAudioURL: String?
    var category: String?
    var notes: String?
    var trackCount: Int

    var title: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名批次" : trimmed
    }

    var categoryText: String {
        category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct GenerationTrack: Codable, Identifiable, Hashable {
    enum ReviewDecision: String, Codable, CaseIterable {
        case pending
        case passed
        case rejected
        case selected

        var title: String {
            switch self {
            case .pending:
                return "待筛选"
            case .passed:
                return "已晋级"
            case .rejected:
                return "已淘汰"
            case .selected:
                return "已选中"
            }
        }
    }

    let id: UUID
    var projectId: UUID
    var batchId: UUID
    var orderInBatch: Int
    let seed: Int
    let createdAt: Date
    let directoryPath: String
    let filePath: String
    let remoteURL: String?
    var displayName: String?
    var notes: String?
    var reviewRound: Int
    var reviewDecision: ReviewDecision
    var reviewTags: [String]
    var isSelected: Bool
    var selectedAt: Date?
    var lastReviewedAt: Date?

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var directoryURL: URL {
        URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    var title: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : trimmed
    }
}

struct GenerationHistoryLibrary: Codable, Hashable {
    var projects: [GenerationProject]
    var batches: [GenerationBatch]
    var tracks: [GenerationTrack]
}

struct GenerationHistoryItem: Identifiable, Hashable {
    let id: UUID
    let projectId: UUID
    let projectName: String
    let batchId: UUID
    let batchSequenceNumber: Int
    let orderInBatch: Int
    let createdAt: Date
    let baseURL: String
    let model: String
    let prompt: String
    let lyrics: String
    let outputFormat: String
    let audioFormat: String
    let sampleRate: Int
    let bitrate: Int
    let lyricsOptimizer: Bool
    let aigcWatermark: Bool
    let instrumental: Bool
    let referenceAudioURL: String?
    let seed: Int
    let directoryPath: String
    let filePath: String
    let remoteURL: String?
    let batchCategory: String?
    let reviewRound: Int
    let reviewDecision: GenerationTrack.ReviewDecision
    let reviewTags: [String]
    let isSelected: Bool
    let selectedAt: Date?
    let lastReviewedAt: Date?
    let displayName: String?
    let notes: String?

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var directoryURL: URL {
        URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    var title: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        let promptTrimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return promptTrimmed.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : promptTrimmed
    }

    var shortTitle: String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 22 else { return value }
        return String(value.prefix(22)) + "…"
    }

    var batchCode: String {
        String(format: "#%03d-%d", batchSequenceNumber, orderInBatch)
    }

    var categoryText: String {
        batchCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var tagsText: String {
        reviewTags.joined(separator: "、")
    }

    var createdAtText: String {
        Self.dateFormatter.string(from: createdAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

struct GenerationHistorySnapshot: Hashable {
    var library: GenerationHistoryLibrary

    var projects: [GenerationProject] { library.projects }
    var batches: [GenerationBatch] { library.batches }
    var tracks: [GenerationTrack] { library.tracks }

    var items: [GenerationHistoryItem] {
        let projectMap = Dictionary(uniqueKeysWithValues: library.projects.map { ($0.id, $0) })
        let batchMap = Dictionary(uniqueKeysWithValues: library.batches.map { ($0.id, $0) })

        return library.tracks
            .sorted(by: { $0.createdAt > $1.createdAt })
            .compactMap { track in
                guard let batch = batchMap[track.batchId], let project = projectMap[track.projectId] else {
                    return nil
                }

                return GenerationHistoryItem(
                    id: track.id,
                    projectId: project.id,
                    projectName: project.name,
                    batchId: batch.id,
                    batchSequenceNumber: batch.sequenceNumber,
                    orderInBatch: track.orderInBatch,
                    createdAt: track.createdAt,
                    baseURL: batch.baseURL,
                    model: batch.model,
                    prompt: batch.prompt,
                    lyrics: batch.lyrics,
                    outputFormat: batch.outputFormat,
                    audioFormat: batch.audioFormat,
                    sampleRate: batch.sampleRate,
                    bitrate: batch.bitrate,
                    lyricsOptimizer: batch.lyricsOptimizer,
                    aigcWatermark: batch.aigcWatermark,
                    instrumental: batch.instrumental,
                    referenceAudioURL: batch.referenceAudioURL,
                    seed: track.seed,
                    directoryPath: track.directoryPath,
                    filePath: track.filePath,
                    remoteURL: track.remoteURL,
                    batchCategory: batch.category,
                    reviewRound: track.reviewRound,
                    reviewDecision: track.reviewDecision,
                    reviewTags: track.reviewTags,
                    isSelected: track.isSelected,
                    selectedAt: track.selectedAt,
                    lastReviewedAt: track.lastReviewedAt,
                    displayName: track.displayName,
                    notes: track.notes
                )
            }
    }
}

enum GenerationHistoryStore {
    static func load(from url: URL) -> GenerationHistorySnapshot {
        guard let data = try? Data(contentsOf: url) else {
            return GenerationHistorySnapshot(library: GenerationHistoryLibrary(projects: [], batches: [], tracks: []))
        }

        if let library = try? JSONDecoder.history.decode(GenerationHistoryLibrary.self, from: data) {
            return GenerationHistorySnapshot(library: normalized(library))
        }

        if let legacyItems = try? JSONDecoder.history.decode([LegacyGenerationHistoryItem].self, from: data) {
            return migrateLegacyItems(legacyItems)
        }

        return GenerationHistorySnapshot(library: GenerationHistoryLibrary(projects: [], batches: [], tracks: []))
    }

    static func save(_ library: GenerationHistoryLibrary, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.history.encode(normalized(library))
        try data.write(to: url, options: .atomic)
    }

    private static func normalized(_ library: GenerationHistoryLibrary) -> GenerationHistoryLibrary {
        let projects = library.projects.sorted(by: { $0.updatedAt > $1.updatedAt })
        let batches = library.batches.sorted { lhs, rhs in
            if lhs.projectId == rhs.projectId {
                return lhs.sequenceNumber > rhs.sequenceNumber
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        let tracks = library.tracks.sorted(by: { $0.createdAt > $1.createdAt })
        return GenerationHistoryLibrary(projects: projects, batches: batches, tracks: tracks)
    }

    private static func migrateLegacyItems(_ items: [LegacyGenerationHistoryItem]) -> GenerationHistorySnapshot {
        guard !items.isEmpty else {
            return GenerationHistorySnapshot(library: GenerationHistoryLibrary(projects: [], batches: [], tracks: []))
        }

        let createdAt = items.map(\.createdAt).min() ?? Date()
        let project = GenerationProject.default(createdAt: createdAt)
        var batches: [GenerationBatch] = []
        var tracks: [GenerationTrack] = []
        var nextSequence = 1

        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            let batchID = UUID()
            let trimmedCategory = item.favoriteTag?.trimmingCharacters(in: .whitespacesAndNewlines)
            let category = (trimmedCategory?.isEmpty == false) ? trimmedCategory : nil
            let batch = GenerationBatch(
                id: batchID,
                projectId: project.id,
                sequenceNumber: nextSequence,
                createdAt: item.createdAt,
                updatedAt: item.createdAt,
                name: nil,
                baseURL: item.baseURL,
                model: item.model,
                prompt: item.prompt,
                lyrics: item.lyrics,
                outputFormat: item.outputFormat,
                audioFormat: item.audioFormat,
                sampleRate: item.sampleRate,
                bitrate: item.bitrate,
                lyricsOptimizer: item.lyricsOptimizer,
                aigcWatermark: item.aigcWatermark,
                instrumental: item.instrumental,
                referenceAudioURL: item.referenceAudioURL,
                category: category,
                notes: nil,
                trackCount: 1
            )
            batches.append(batch)

            let track = GenerationTrack(
                id: item.id,
                projectId: project.id,
                batchId: batchID,
                orderInBatch: 1,
                seed: item.seed,
                createdAt: item.createdAt,
                directoryPath: item.directoryPath,
                filePath: item.filePath,
                remoteURL: item.remoteURL,
                displayName: nil,
                reviewRound: item.isFavorite ? 1 : 0,
                reviewDecision: item.isFavorite ? .selected : .pending,
                reviewTags: category.map { [$0] } ?? [],
                isSelected: item.isFavorite,
                selectedAt: item.isFavorite ? item.createdAt : nil,
                lastReviewedAt: item.isFavorite ? item.createdAt : nil
            )
            tracks.append(track)
            nextSequence += 1
        }

        return GenerationHistorySnapshot(
            library: normalized(
                GenerationHistoryLibrary(
                    projects: [project],
                    batches: batches,
                    tracks: tracks
                )
            )
        )
    }
}

private struct LegacyGenerationHistoryItem: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let baseURL: String
    let model: String
    let prompt: String
    let lyrics: String
    let outputFormat: String
    let audioFormat: String
    let sampleRate: Int
    let bitrate: Int
    let lyricsOptimizer: Bool
    let aigcWatermark: Bool
    let instrumental: Bool
    let referenceAudioURL: String?
    let seed: Int
    let directoryPath: String
    let filePath: String
    let remoteURL: String?
    var isFavorite: Bool
    var favoriteTag: String?
}

struct TranscodeQueueItem: Codable, Identifiable, Hashable {
    enum Status: String, Codable, CaseIterable {
        case pending
        case processing
        case completed
        case failed

        var title: String {
            switch self {
            case .pending:
                return "待转码"
            case .processing:
                return "转码中"
            case .completed:
                return "已完成"
            case .failed:
                return "失败"
            }
        }
    }

    let id: UUID
    let createdAt: Date
    var sourceFilePath: String
    var targetBitrateKbps: Int
    var targetSampleRate: Int
    var status: Status
    var outputFilePath: String?
    var errorMessage: String?

    var sourceFileURL: URL {
        URL(fileURLWithPath: sourceFilePath)
    }

    var outputFileURL: URL? {
        outputFilePath.map(URL.init(fileURLWithPath:))
    }

    var sourceFilename: String {
        sourceFileURL.lastPathComponent
    }

    var createdAtText: String {
        Self.dateFormatter.string(from: createdAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

enum TranscodeQueueStore {
    static func load(from url: URL) -> [TranscodeQueueItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.history.decode([TranscodeQueueItem].self, from: data)) ?? []
    }

    static func save(_ items: [TranscodeQueueItem], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.history.encode(items)
        try data.write(to: url, options: .atomic)
    }
}

extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
