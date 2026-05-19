import Foundation

enum VoxCPMRuntimeState: String, Codable, Equatable, Sendable {
    case unconfigured
    case validating
    case ready
    case starting
    case running
    case stopping
    case error
}

enum VoxCPMTaskStatus: String, Codable, Equatable, Sendable {
    case idle
    case queued
    case preparing
    case running
    case completed
    case failed
    case cancelled
}

enum VoxCPMTaskMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case quickClone
    case voiceDesign

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickClone:
            return "快速克隆"
        case .voiceDesign:
            return "声音设计"
        }
    }
}

struct VoxCPMPluginConfiguration: Codable, Equatable, Sendable {
    var voxcpmRootPath: String
    var pythonCommand: String
    var defaultOutputDirectory: String
    var modelIdentifier: String

    static let `default` = VoxCPMPluginConfiguration(
        voxcpmRootPath: "",
        pythonCommand: "python",
        defaultOutputDirectory: "",
        modelIdentifier: "openbmb/VoxCPM2"
    )
}

struct VoxCPMTaskRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var mode: VoxCPMTaskMode
    var createdAt: Date
    var status: VoxCPMTaskStatus
    var inputText: String
    var controlInstruction: String
    var referenceAudioPath: String?
    var outputAudioPath: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        mode: VoxCPMTaskMode,
        createdAt: Date = Date(),
        status: VoxCPMTaskStatus = .idle,
        inputText: String = "",
        controlInstruction: String = "",
        referenceAudioPath: String? = nil,
        outputAudioPath: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.createdAt = createdAt
        self.status = status
        self.inputText = inputText
        self.controlInstruction = controlInstruction
        self.referenceAudioPath = referenceAudioPath
        self.outputAudioPath = outputAudioPath
        self.errorMessage = errorMessage
    }
}

struct VoxCPMPluginPersistedState: Codable, Equatable, Sendable {
    var configuration: VoxCPMPluginConfiguration
    var taskHistory: [VoxCPMTaskRecord]

    static let empty = VoxCPMPluginPersistedState(
        configuration: .default,
        taskHistory: []
    )
}

extension VoxCPMPluginPersistedState {
    static let persistenceFilename = "voxcpm-plugin-state.json"
}

enum VoxCPMBridgeCommand: String, Codable, Equatable, Sendable {
    case healthCheck = "health-check"
    case generateDesign = "generate-design"
    case generateClone = "generate-clone"
    case recognizeReferenceText = "recognize-reference-text"
}

struct VoxCPMBridgeRequestEnvelope: Codable, Equatable, Sendable {
    var version: String
    var requestID: String?
    var command: VoxCPMBridgeCommand
    var arguments: [String: VoxCPMBridgeValue]

    enum CodingKeys: String, CodingKey {
        case version
        case requestID = "request_id"
        case command
        case arguments
    }
}

struct VoxCPMBridgeResponseEnvelope: Codable, Equatable, Sendable {
    var version: String
    var requestID: String?
    var command: VoxCPMBridgeCommand?
    var ok: Bool
    var runtimeState: VoxCPMRuntimeState
    var details: [String: VoxCPMBridgeValue]
    var error: VoxCPMBridgeError?

    enum CodingKeys: String, CodingKey {
        case version
        case requestID = "request_id"
        case command
        case ok
        case runtimeState = "runtime_state"
        case details
        case error
    }
}

struct VoxCPMBridgeError: Codable, Equatable, Sendable {
    var code: String
    var message: String
}

struct VoxCPMBridgeRequiredFileStatus: Codable, Equatable, Sendable {
    var exists: Bool
    var path: String?
}

struct VoxCPMHealthCheckResult: Equatable, Sendable {
    var response: VoxCPMBridgeResponseEnvelope
    var voxcpmRoot: String
    var rootExists: Bool
    var requiredFiles: [String: VoxCPMBridgeRequiredFileStatus]
}

struct VoxCPMQuickCloneDraft: Equatable, Sendable {
    var referenceAudioPath: String
    var targetText: String
    var controlInstruction: String

    static let empty = VoxCPMQuickCloneDraft(
        referenceAudioPath: "",
        targetText: "",
        controlInstruction: ""
    )
}

struct VoxCPMVoiceDesignDraft: Equatable, Sendable {
    var targetText: String
    var designDescription: String
    var controlInstruction: String

    static let empty = VoxCPMVoiceDesignDraft(
        targetText: "",
        designDescription: "",
        controlInstruction: ""
    )
}

enum VoxCPMBridgeValue: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case object([String: VoxCPMBridgeValue])
    case array([VoxCPMBridgeValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: VoxCPMBridgeValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([VoxCPMBridgeValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value in VoxCPM bridge payload."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: VoxCPMBridgeValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
