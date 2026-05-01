import Foundation

struct MinimaxMusicClient {
    let baseURL: String
    let apiKey: String

    func generateMusic(request: MusicGenerationRequest) async throws -> GeneratedMusic {
        guard let endpoint = URL(string: normalizedBaseURL().appending("/v1/music_generation")) else {
            throw MinimaxMusicError.invalidConfiguration("BASE_URL 无效。")
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 240
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder.api.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response: response, data: data)

        let apiResponse = try JSONDecoder.api.decode(MusicGenerationResponse.self, from: data)
        if let statusCode = apiResponse.baseResponse?.statusCode, statusCode != 0 {
            let message = apiResponse.baseResponse?.statusMsg ?? "MiniMax 返回错误：\(statusCode)"
            throw MinimaxMusicError.requestFailed(message)
        }

        return try apiResponse.generatedMusic()
    }

    private func normalizedBaseURL() -> String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw MinimaxMusicError.requestFailed(body)
        }
    }
}

struct MusicGenerationRequest: Encodable {
    let model: String
    let prompt: String
    let lyrics: String?
    let outputFormat: String
    let audioSetting: AudioSetting
    let lyricsOptimizer: Bool
    let aigcWatermark: Bool
    let instrumental: Bool
    let audioURL: String?
    let seed: Int

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case lyrics
        case outputFormat = "output_format"
        case audioSetting = "audio_setting"
        case lyricsOptimizer = "lyrics_optimizer"
        case aigcWatermark = "aigc_watermark"
        case instrumental = "is_instrumental"
        case audioURL = "audio_url"
        case seed
    }
}

struct AudioSetting: Encodable {
    let sampleRate: Int
    let bitrate: Int
    let format: String

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case bitrate
        case format
    }
}

struct MusicGenerationResponse: Decodable {
    let data: MusicData?
    let audio: String?
    let audioURL: String?
    let baseResponse: BaseResponse?

    enum CodingKeys: String, CodingKey {
        case data
        case audio
        case audioURL = "audio_url"
        case baseResponse = "base_resp"
    }

    func generatedMusic() throws -> GeneratedMusic {
        let audioValue = data?.audio ?? audio
        let remote = data?.audioURL ?? audioURL

        if let audioValue, let audioURL = URL(string: audioValue), audioURL.scheme?.hasPrefix("http") == true {
            return GeneratedMusic(audioData: nil, remoteURL: audioURL)
        }

        if let remote, let url = URL(string: remote) {
            return GeneratedMusic(audioData: nil, remoteURL: url)
        }

        if let audioValue, !audioValue.isEmpty {
            return GeneratedMusic(audioData: try Data(hexEncoded: audioValue), remoteURL: nil)
        }

        throw MinimaxMusicError.invalidResponse("MiniMax 响应缺少可用音频字段。")
    }
}

struct MusicData: Decodable {
    let audio: String?
    let audioURL: String?

    enum CodingKeys: String, CodingKey {
        case audio
        case audioURL = "audio_url"
    }
}

struct BaseResponse: Decodable {
    let statusCode: Int?
    let statusMsg: String?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}

struct GeneratedMusic {
    let audioData: Data?
    let remoteURL: URL?
}

enum MusicModel: String, CaseIterable, Identifiable {
    case free = "music-2.6-free"
    case professional = "music-2.6"
    case cover = "music-2.6-cover"

    var id: String { rawValue }
}

enum OutputMode: String, CaseIterable, Identifiable {
    case url
    case hex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .url: "URL"
        case .hex: "Hex"
        }
    }
}

enum AudioFormat: String, CaseIterable, Identifiable {
    case mp3
    case wav

    var id: String { rawValue }
    var fileExtension: String { rawValue }
}

enum MinimaxMusicError: LocalizedError {
    case invalidConfiguration(String)
    case requestFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message), .requestFailed(let message), .invalidResponse(let message):
            message
        }
    }
}

extension JSONEncoder {
    static var api: JSONEncoder {
        JSONEncoder()
    }
}

extension JSONDecoder {
    static var api: JSONDecoder {
        JSONDecoder()
    }
}

extension Data {
    init(hexEncoded hex: String) throws {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count.isMultiple(of: 2) else {
            throw MinimaxMusicError.invalidResponse("音频 hex 长度不正确。")
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw MinimaxMusicError.invalidResponse("音频 hex 内容无法解析。")
            }
            bytes.append(byte)
            index = next
        }

        self = Data(bytes)
    }
}
