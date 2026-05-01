import Foundation

struct GenerationHistoryItem: Codable, Identifiable, Hashable {
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

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var directoryURL: URL {
        URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    var title: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名生成" : prompt
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

enum GenerationHistoryStore {
    static func load(from url: URL) -> [GenerationHistoryItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.history.decode([GenerationHistoryItem].self, from: data)) ?? []
    }

    static func save(_ items: [GenerationHistoryItem], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.history.encode(items)
        try data.write(to: url, options: .atomic)
    }
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
