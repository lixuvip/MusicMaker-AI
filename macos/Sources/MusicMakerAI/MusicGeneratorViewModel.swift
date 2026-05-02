import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MusicGeneratorViewModel: NSObject, ObservableObject {
    enum FFmpegStatus: Equatable {
        case available(path: String)
        case unavailable
        case installing

        var title: String {
            switch self {
            case .available:
                return "已安装"
            case .unavailable:
                return "未安装"
            case .installing:
                return "安装中"
            }
        }
    }

    enum HistoryReviewFilter: String, CaseIterable, Identifiable {
        case all
        case pending
        case passed
        case rejected
        case selected

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "全部状态"
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

    enum SelectionFilter: String, CaseIterable, Identifiable {
        case all
        case selectedOnly
        case unselectedOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "全部结果"
            case .selectedOnly:
                return "仅看已选中"
            case .unselectedOnly:
                return "仅看未选中"
            }
        }
    }

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Defaults.baseURL) }
    }

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Defaults.apiKey) }
    }

    @Published var model: MusicModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: Defaults.model) }
    }

    @Published var outputMode: OutputMode {
        didSet { UserDefaults.standard.set(outputMode.rawValue, forKey: Defaults.outputMode) }
    }

    @Published var audioFormat: AudioFormat {
        didSet { UserDefaults.standard.set(audioFormat.rawValue, forKey: Defaults.audioFormat) }
    }

    @Published var sampleRate: Int {
        didSet { UserDefaults.standard.set(sampleRate, forKey: Defaults.sampleRate) }
    }

    @Published var bitrate: Int {
        didSet { UserDefaults.standard.set(bitrate, forKey: Defaults.bitrate) }
    }

    @Published var generationCount: Int {
        didSet { UserDefaults.standard.set(generationCount, forKey: Defaults.generationCount) }
    }

    @Published var lyricsOptimizer: Bool {
        didSet { UserDefaults.standard.set(lyricsOptimizer, forKey: Defaults.lyricsOptimizer) }
    }

    @Published var instrumental: Bool {
        didSet { UserDefaults.standard.set(instrumental, forKey: Defaults.instrumental) }
    }

    @Published var aigcWatermark: Bool {
        didSet { UserDefaults.standard.set(aigcWatermark, forKey: Defaults.aigcWatermark) }
    }

    @Published var randomSeed: Bool {
        didSet { UserDefaults.standard.set(randomSeed, forKey: Defaults.randomSeed) }
    }

    @Published var manualSeedText: String {
        didSet { UserDefaults.standard.set(manualSeedText, forKey: Defaults.manualSeedText) }
    }

    @Published var prompt: String
    @Published var lyrics: String
    @Published var referenceAudioURL: String
    @Published var categoryLibrary: [String] = []
    @Published var generationCategory: String {
        didSet { UserDefaults.standard.set(generationCategory, forKey: Defaults.generationCategory) }
    }
    @Published var projectLibrary: [GenerationProject] = []
    @Published var draftProjectName = ""
    @Published var selectedProjectID: GenerationProject.ID? {
        didSet {
            if let selectedProjectID {
                UserDefaults.standard.set(selectedProjectID.uuidString, forKey: Defaults.selectedProjectID)
            } else {
                UserDefaults.standard.removeObject(forKey: Defaults.selectedProjectID)
            }

            draftProjectName = activeProject?.name ?? ""
        }
    }
    @Published var isGenerating = false
    @Published var statusText = "准备就绪"
    @Published var errorMessage = ""
    @Published var showError = false
    @Published var lastFileURL: URL?
    @Published var lastRemoteURL: URL?
    @Published var lastSeed: Int?
    @Published var isPlaying = false
    @Published var currentPlaybackURL: URL?
    @Published var currentlyPlayingHistoryID: GenerationHistoryItem.ID?
    @Published var playbackPosition: Double = 0
    @Published var playbackDuration: Double = 0
    @Published var history: [GenerationHistoryItem] = []
    @Published var selectedHistoryID: GenerationHistoryItem.ID?
    @Published var historyReviewFilter: HistoryReviewFilter = .all
    @Published var historySelectionFilter: SelectionFilter = .all
    @Published var historyCategoryFilter = ""
    @Published var historyProjectFilter: GenerationProject.ID?
    @Published var transcodeBitrateKbps: Int {
        didSet { UserDefaults.standard.set(transcodeBitrateKbps, forKey: Defaults.transcodeBitrateKbps) }
    }
    @Published var transcodeSampleRate: Int {
        didSet { UserDefaults.standard.set(transcodeSampleRate, forKey: Defaults.transcodeSampleRate) }
    }
    @Published var transcodeQueue: [TranscodeQueueItem] = []
    @Published var selectedTranscodeID: TranscodeQueueItem.ID?
    @Published var autoTranscodeAfterGeneration: Bool {
        didSet { UserDefaults.standard.set(autoTranscodeAfterGeneration, forKey: Defaults.autoTranscodeAfterGeneration) }
    }
    @Published var autoPlayAfterGeneration: Bool {
        didSet { UserDefaults.standard.set(autoPlayAfterGeneration, forKey: Defaults.autoPlayAfterGeneration) }
    }
    @Published var ffmpegStatus: FFmpegStatus = .unavailable
    @Published var isTranscoding = false
    @Published var batchProgressTotal = 0
    @Published var batchProgressCompleted = 0
    @Published var batchProgressCurrentIndex = 0

    private var historyLibrary = GenerationHistoryLibrary(projects: [], batches: [], tracks: [])
    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?

    var canGenerate: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !needsLyrics &&
        !isGenerating &&
        (1...10).contains(generationCount)
    }

    var needsLyrics: Bool {
        !instrumental && lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isBatchGeneration: Bool {
        generationCount > 1
    }

    var activeProject: GenerationProject? {
        guard let selectedProjectID else { return nil }
        return projectLibrary.first(where: { $0.id == selectedProjectID })
    }

    var availableHistoryCategories: [String] {
        let values = Set(history.map(\.categoryText).filter { !$0.isEmpty })
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var filteredHistory: [GenerationHistoryItem] {
        history.filter { item in
            let projectMatch = historyProjectFilter == nil || item.projectId == historyProjectFilter

            let categoryMatch: Bool
            let trimmedCategory = historyCategoryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCategory.isEmpty {
                categoryMatch = true
            } else {
                categoryMatch = item.categoryText.caseInsensitiveCompare(trimmedCategory) == .orderedSame
            }

            let reviewMatch: Bool
            switch historyReviewFilter {
            case .all:
                reviewMatch = true
            case .pending:
                reviewMatch = item.reviewDecision == .pending
            case .passed:
                reviewMatch = item.reviewDecision == .passed
            case .rejected:
                reviewMatch = item.reviewDecision == .rejected
            case .selected:
                reviewMatch = item.reviewDecision == .selected || item.isSelected
            }

            let selectionMatch: Bool
            switch historySelectionFilter {
            case .all:
                selectionMatch = true
            case .selectedOnly:
                selectionMatch = item.isSelected
            case .unselectedOnly:
                selectionMatch = !item.isSelected
            }

            return projectMatch && categoryMatch && reviewMatch && selectionMatch
        }
    }

    override init() {
        let defaults = UserDefaults.standard
        baseURL = defaults.string(forKey: Defaults.baseURL) ?? "https://api.minimaxi.com"
        apiKey = defaults.string(forKey: Defaults.apiKey) ?? ""
        model = MusicModel(rawValue: defaults.string(forKey: Defaults.model) ?? "") ?? .free
        outputMode = OutputMode(rawValue: defaults.string(forKey: Defaults.outputMode) ?? "") ?? .url
        audioFormat = AudioFormat(rawValue: defaults.string(forKey: Defaults.audioFormat) ?? "") ?? .mp3
        sampleRate = defaults.object(forKey: Defaults.sampleRate) as? Int ?? 44100
        bitrate = defaults.object(forKey: Defaults.bitrate) as? Int ?? 256000
        generationCount = defaults.object(forKey: Defaults.generationCount) as? Int ?? 1
        transcodeBitrateKbps = defaults.object(forKey: Defaults.transcodeBitrateKbps) as? Int ?? 320
        transcodeSampleRate = defaults.object(forKey: Defaults.transcodeSampleRate) as? Int ?? 44100
        autoTranscodeAfterGeneration = defaults.object(forKey: Defaults.autoTranscodeAfterGeneration) as? Bool ?? false
        autoPlayAfterGeneration = defaults.object(forKey: Defaults.autoPlayAfterGeneration) as? Bool ?? false
        lyricsOptimizer = defaults.object(forKey: Defaults.lyricsOptimizer) as? Bool ?? true
        instrumental = defaults.object(forKey: Defaults.instrumental) as? Bool ?? false
        aigcWatermark = defaults.object(forKey: Defaults.aigcWatermark) as? Bool ?? false
        randomSeed = defaults.object(forKey: Defaults.randomSeed) as? Bool ?? true
        manualSeedText = defaults.string(forKey: Defaults.manualSeedText) ?? ""
        prompt = defaults.string(forKey: Defaults.prompt) ?? "流行电子，明亮但有电影感，副歌强记忆点，适合 90 秒宣传片。"
        lyrics = defaults.string(forKey: Defaults.lyrics) ?? ""
        referenceAudioURL = defaults.string(forKey: Defaults.referenceAudioURL) ?? ""
        categoryLibrary = defaults.stringArray(forKey: Defaults.categoryLibrary) ?? []
        generationCategory = defaults.string(forKey: Defaults.generationCategory) ?? ""
        super.init()

        let snapshot = GenerationHistoryStore.load(from: Self.historyURL)
        historyLibrary = snapshot.library
        transcodeQueue = TranscodeQueueStore.load(from: Self.transcodeQueueURL)
        refreshHistoryViews()
        if let rawProjectID = defaults.string(forKey: Defaults.selectedProjectID), let uuid = UUID(uuidString: rawProjectID), projectLibrary.contains(where: { $0.id == uuid }) {
            selectedProjectID = uuid
        } else {
            selectedProjectID = projectLibrary.first?.id
        }
        refreshFFmpegStatus()
    }

    func createProject(named name: String? = nil) {
        let baseName = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? name!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "项目 \(historyLibrary.projects.count + 1)"
        let uniqueName = uniqueProjectName(from: baseName)
        let now = Date()
        let project = GenerationProject(
            id: UUID(),
            name: uniqueName,
            createdAt: now,
            updatedAt: now,
            isArchived: false,
            notes: nil
        )
        historyLibrary.projects.append(project)
        selectedProjectID = project.id
        historyProjectFilter = project.id
        persistAndRefreshHistory()
        draftProjectName = project.name
        statusText = "已创建项目：\(project.name)"
    }

    func renameSelectedProject(to name: String) {
        guard let selectedProjectID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftProjectName = activeProject?.name ?? ""
            return
        }
        guard let index = historyLibrary.projects.firstIndex(where: { $0.id == selectedProjectID }) else { return }
        let uniqueName = uniqueProjectName(from: trimmed, excluding: selectedProjectID)
        historyLibrary.projects[index].name = uniqueName
        historyLibrary.projects[index].updatedAt = Date()
        persistAndRefreshHistory()
        draftProjectName = uniqueName
        statusText = "项目已重命名为：\(uniqueName)"
    }

    func selectProject(_ projectID: GenerationProject.ID?) {
        selectedProjectID = projectID
        historyProjectFilter = projectID
        if let projectName = activeProject?.name {
            statusText = "当前项目：\(projectName)"
        }
    }

    func moveTrack(_ id: GenerationHistoryItem.ID, toProject projectID: GenerationProject.ID) {
        guard let trackIndex = historyLibrary.tracks.firstIndex(where: { $0.id == id }) else { return }
        guard historyLibrary.projects.contains(where: { $0.id == projectID }) else { return }
        guard let item = history.first(where: { $0.id == id }) else { return }

        let originalProjectID = historyLibrary.tracks[trackIndex].projectId
        guard originalProjectID != projectID else { return }

        let targetBatchID: UUID
        let orderInBatch: Int

        if let existingBatch = historyLibrary.batches.first(where: {
            $0.projectId == projectID &&
            $0.prompt == item.prompt &&
            $0.lyrics == item.lyrics &&
            $0.model == item.model &&
            $0.category == (item.categoryText.isEmpty ? nil : item.categoryText)
        }) {
            targetBatchID = existingBatch.id
            orderInBatch = existingBatch.trackCount + 1
        } else {
            let batchID = UUID()
            let now = Date()
            let batch = GenerationBatch(
                id: batchID,
                projectId: projectID,
                sequenceNumber: nextBatchSequenceNumber(in: projectID),
                createdAt: now,
                updatedAt: now,
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
                category: item.categoryText.isEmpty ? nil : item.categoryText,
                notes: nil,
                trackCount: 0
            )
            historyLibrary.batches.append(batch)
            targetBatchID = batchID
            orderInBatch = 1
        }

        if let oldBatchIndex = historyLibrary.batches.firstIndex(where: { $0.id == historyLibrary.tracks[trackIndex].batchId }) {
            historyLibrary.batches[oldBatchIndex].trackCount = max(historyLibrary.batches[oldBatchIndex].trackCount - 1, 0)
            historyLibrary.batches[oldBatchIndex].updatedAt = Date()
        }

        historyLibrary.tracks[trackIndex].projectId = projectID
        historyLibrary.tracks[trackIndex].batchId = targetBatchID
        historyLibrary.tracks[trackIndex].orderInBatch = orderInBatch
        historyLibrary.tracks[trackIndex].lastReviewedAt = Date()

        if let targetBatchIndex = historyLibrary.batches.firstIndex(where: { $0.id == targetBatchID }) {
            historyLibrary.batches[targetBatchIndex].trackCount += 1
            historyLibrary.batches[targetBatchIndex].updatedAt = Date()
        }

        updateProjectTimestamp(projectID: originalProjectID, date: Date())
        updateProjectTimestamp(projectID: projectID, date: Date())
        selectedProjectID = projectID
        historyProjectFilter = projectID
        persistAndRefreshHistory(selecting: id)
        if let movedItem = history.first(where: { $0.id == id }) {
            statusText = "已移动到项目：\(movedItem.projectName)"
        } else {
            statusText = "已移动到新项目"
        }
    }

    func isCurrentlyPlaying(_ item: GenerationHistoryItem) -> Bool {
        currentlyPlayingHistoryID == item.id
    }

    func togglePlaybackFromCommand() {
        if currentPlaybackURL == nil, let item = selectedHistoryItem {
            playFile(url: item.fileURL)
            return
        }
        togglePlayback()
    }

    func generate() async {
        UserDefaults.standard.set(prompt, forKey: Defaults.prompt)
        UserDefaults.standard.set(lyrics, forKey: Defaults.lyrics)
        UserDefaults.standard.set(referenceAudioURL, forKey: Defaults.referenceAudioURL)

        let normalizedPrompt = normalizedInput(prompt)
        let normalizedLyrics = normalizedInput(lyrics)

        guard instrumental || nonEmpty(normalizedLyrics) != nil else {
            errorMessage = "MiniMax 音乐生成接口要求提供 lyrics。请填写歌词，或打开「纯音乐」。"
            showError = true
            statusText = "请填写歌词"
            return
        }

        guard let seed = makeSeed() else {
            errorMessage = "Seed 需要填写 0 到 1000000 之间的整数，或打开「每次随机」。"
            showError = true
            statusText = "Seed 无效"
            return
        }

        let project = ensureActiveProject()
        let batchID = UUID()
        let now = Date()
        let normalizedCategory = nonEmpty(generationCategory)
        let submittedLyrics = requestLyrics(from: normalizedLyrics, prompt: normalizedPrompt)
        let sequenceNumber = nextBatchSequenceNumber(in: project.id)

        let batch = GenerationBatch(
            id: batchID,
            projectId: project.id,
            sequenceNumber: sequenceNumber,
            createdAt: now,
            updatedAt: now,
            name: nil,
            baseURL: baseURL,
            model: model.rawValue,
            prompt: normalizedPrompt,
            lyrics: submittedLyrics,
            outputFormat: outputMode.rawValue,
            audioFormat: audioFormat.rawValue,
            sampleRate: sampleRate,
            bitrate: bitrate,
            lyricsOptimizer: lyricsOptimizer,
            aigcWatermark: aigcWatermark,
            instrumental: instrumental,
            referenceAudioURL: model == .cover ? nonEmpty(referenceAudioURL) : nil,
            category: normalizedCategory,
            notes: nil,
            trackCount: 0
        )
        historyLibrary.batches.append(batch)
        updateProjectTimestamp(projectID: project.id, date: now)
        if let normalizedCategory {
            addCategoryToLibrary(normalizedCategory)
        }

        isGenerating = true
        lastRemoteURL = nil
        lastSeed = seed
        stopPlayback()

        let totalCount = generationCount
        var completedCount = 0
        batchProgressTotal = totalCount
        batchProgressCompleted = 0
        batchProgressCurrentIndex = 0
        let client = MinimaxMusicClient(baseURL: baseURL, apiKey: apiKey)

        do {
            for index in 0..<totalCount {
                batchProgressCurrentIndex = index + 1
                let currentSeed = index == 0 ? seed : Int.random(in: 0...1_000_000)
                lastSeed = currentSeed
                statusText = totalCount == 1
                    ? "正在提交到 MiniMax... Seed: \(currentSeed)"
                    : "正在生成第 \(index + 1) / \(totalCount) 首... Seed: \(currentSeed)"

                let result = try await client.generateMusic(
                    request: MusicGenerationRequest(
                        model: model.rawValue,
                        prompt: normalizedPrompt,
                        lyrics: submittedLyrics,
                        outputFormat: outputMode.rawValue,
                        audioSetting: AudioSetting(
                            sampleRate: sampleRate,
                            bitrate: bitrate,
                            format: audioFormat.rawValue
                        ),
                        lyricsOptimizer: lyricsOptimizer,
                        aigcWatermark: aigcWatermark,
                        instrumental: instrumental,
                        audioURL: model == .cover ? nonEmpty(referenceAudioURL) : nil,
                        seed: currentSeed
                    )
                )

                statusText = totalCount == 1 ? "正在保存音频..." : "正在保存第 \(index + 1) 首音频..."
                let savedURL = try await saveAudio(from: result)
                lastFileURL = savedURL
                lastRemoteURL = result.remoteURL
                appendHistory(
                    batchID: batchID,
                    projectID: project.id,
                    fileURL: savedURL,
                    remoteURL: result.remoteURL,
                    seed: currentSeed,
                    orderInBatch: index + 1
                )
                let transcodeID = enqueueLatestOutputForTranscoding(fileURL: savedURL)
                completedCount += 1
                batchProgressCompleted = completedCount

                if autoPlayAfterGeneration && totalCount == 1 {
                    try preparePlayback(url: savedURL)
                } else {
                    currentPlaybackURL = savedURL
                    currentlyPlayingHistoryID = history.first(where: { $0.fileURL.standardizedFileURL == savedURL.standardizedFileURL })?.id
                    playbackPosition = 0
                    playbackDuration = 0
                }
                if autoTranscodeAfterGeneration, let transcodeID {
                    await runTranscode(for: transcodeID)
                }
            }

            statusText = totalCount == 1 ? "生成完成，Seed: \(seed)" : "批量生成完成，共 \(completedCount) 首"
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            statusText = completedCount > 0
                ? "批量生成中断，已完成 \(completedCount) / \(totalCount) 首"
                : "生成失败"
        }

        isGenerating = false
        batchProgressCurrentIndex = 0
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func playFile(url: URL) {
        do {
            stopPlayback()
            try preparePlayback(url: url)
            currentPlaybackURL = url
            currentlyPlayingHistoryID = history.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL })?.id
            statusText = "正在播放：\(url.lastPathComponent)"
        } catch {
            errorMessage = "播放失败：\(error.localizedDescription)"
            showError = true
        }
    }

    func seekPlayback(to progress: Double) {
        guard let player, playbackDuration > 0 else { return }
        let clamped = min(max(progress, 0), playbackDuration)
        player.currentTime = clamped
        playbackPosition = clamped
    }

    func acceptDroppedAudioFiles(_ providers: [NSItemProvider]) -> Bool {
        let supportedType = UTType.fileURL.identifier
        for provider in providers where provider.hasItemConformingToTypeIdentifier(supportedType) {
            provider.loadItem(forTypeIdentifier: supportedType, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    self.playFile(url: url)
                }
            }
            return true
        }
        return false
    }

    func openOutputFolder() {
        guard let fileURL = lastFileURL else { return }
        NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
    }

    func revealOutputFile() {
        guard let fileURL = lastFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func revealHistoryFile(_ item: GenerationHistoryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    func openHistoryFolder(_ item: GenerationHistoryItem) {
        NSWorkspace.shared.open(item.directoryURL)
    }

    func copyOutputFile() {
        guard let fileURL = lastFileURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        if let lastSeed {
            statusText = "已复制文件，Seed: \(lastSeed)"
        } else {
            statusText = "已复制文件"
        }
    }

    func copyLastSeed() {
        guard let lastSeed else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(String(lastSeed), forType: .string)
        statusText = "已复制 Seed: \(lastSeed)"
    }

    func selectHistory(_ item: GenerationHistoryItem) {
        selectedHistoryID = item.id
        lastFileURL = item.fileURL
        lastRemoteURL = item.remoteURL.flatMap(URL.init(string:))
        lastSeed = item.seed
        historyProjectFilter = item.projectId
        selectedProjectID = item.projectId
        statusText = "已选择历史记录，Seed: \(item.seed)"
    }

    func loadHistoryParameters(_ item: GenerationHistoryItem) {
        model = MusicModel(rawValue: item.model) ?? model
        outputMode = OutputMode(rawValue: item.outputFormat) ?? outputMode
        audioFormat = AudioFormat(rawValue: item.audioFormat) ?? audioFormat
        sampleRate = item.sampleRate
        bitrate = item.bitrate
        lyricsOptimizer = item.lyricsOptimizer
        instrumental = item.instrumental
        aigcWatermark = item.aigcWatermark
        randomSeed = false
        manualSeedText = String(item.seed)
        prompt = item.prompt
        lyrics = item.lyrics
        referenceAudioURL = item.referenceAudioURL ?? ""
        generationCategory = item.categoryText
        selectHistory(item)
        statusText = "已加载历史参数，Seed: \(item.seed)"
    }

    func clearHistory() {
        historyLibrary = GenerationHistoryLibrary(projects: projectLibrary.isEmpty ? [] : [ensureActiveProject()], batches: [], tracks: [])
        selectedHistoryID = nil
        refreshHistoryViews()
        persistHistory()
        statusText = "历史记录已清空"
    }

    func updateCategory(for id: GenerationHistoryItem.ID, category: String) {
        guard let item = history.first(where: { $0.id == id }) else { return }
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if let batchIndex = historyLibrary.batches.firstIndex(where: { $0.id == item.batchId }) {
            historyLibrary.batches[batchIndex].category = trimmed.isEmpty ? nil : trimmed
            historyLibrary.batches[batchIndex].updatedAt = Date()
            if !trimmed.isEmpty {
                addCategoryToLibrary(trimmed)
            }
            updateProjectTimestamp(projectID: item.projectId, date: Date())
            persistAndRefreshHistory()
        }
    }

    func addGenerationCategoryToLibrary() {
        let trimmed = generationCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        generationCategory = trimmed
        addCategoryToLibrary(trimmed)
    }

    func selectGenerationCategory(_ category: String) {
        generationCategory = category
    }

    func markReviewRound(for id: GenerationHistoryItem.ID, round: Int) {
        guard let index = historyLibrary.tracks.firstIndex(where: { $0.id == id }) else { return }
        let normalizedRound = max(0, min(10, round))
        historyLibrary.tracks[index].reviewRound = normalizedRound
        historyLibrary.tracks[index].reviewDecision = normalizedRound == 0 ? .pending : .passed
        historyLibrary.tracks[index].lastReviewedAt = Date()
        if normalizedRound == 0 {
            historyLibrary.tracks[index].isSelected = false
            historyLibrary.tracks[index].selectedAt = nil
        }
        persistAndRefreshHistory()
    }

    func advanceToNextRound(for id: GenerationHistoryItem.ID) {
        guard let item = history.first(where: { $0.id == id }) else { return }
        let nextRound = min(item.reviewRound + 1, 10)
        markReviewRound(for: id, round: nextRound)
    }

    func rejectTrack(_ id: GenerationHistoryItem.ID) {
        guard let index = historyLibrary.tracks.firstIndex(where: { $0.id == id }) else { return }
        historyLibrary.tracks[index].reviewDecision = .rejected
        historyLibrary.tracks[index].isSelected = false
        historyLibrary.tracks[index].selectedAt = nil
        historyLibrary.tracks[index].lastReviewedAt = Date()
        persistAndRefreshHistory()
    }

    func toggleSelected(for id: GenerationHistoryItem.ID) {
        guard let index = historyLibrary.tracks.firstIndex(where: { $0.id == id }) else { return }
        let nextValue = !historyLibrary.tracks[index].isSelected
        historyLibrary.tracks[index].isSelected = nextValue
        historyLibrary.tracks[index].selectedAt = nextValue ? Date() : nil
        historyLibrary.tracks[index].reviewDecision = nextValue ? .selected : (historyLibrary.tracks[index].reviewRound > 0 ? .passed : .pending)
        historyLibrary.tracks[index].lastReviewedAt = Date()
        persistAndRefreshHistory()
    }

    func updateTrackNotes(for id: GenerationHistoryItem.ID, notes: String) {
        guard let index = historyLibrary.tracks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        historyLibrary.tracks[index].notes = trimmed.isEmpty ? nil : notes
        historyLibrary.tracks[index].lastReviewedAt = Date()
        updateProjectTimestamp(projectID: historyLibrary.tracks[index].projectId, date: Date())
        persistAndRefreshHistory(selecting: id)
        statusText = trimmed.isEmpty ? "备注已清空" : "备注已保存"
    }

    func runSelectedTranscode() async {
        guard let selectedTranscodeID else { return }
        await runTranscode(for: selectedTranscodeID)
    }

    func runTranscode(for id: TranscodeQueueItem.ID) async {
        guard !isTranscoding else { return }
        guard let index = transcodeQueue.firstIndex(where: { $0.id == id }) else { return }
        guard case .available = ffmpegStatus else {
            errorMessage = "尚未检测到 ffmpeg。请先在转码页面点击“开始安装”，或手动安装后刷新状态。"
            showError = true
            statusText = "缺少 ffmpeg"
            return
        }

        isTranscoding = true
        transcodeQueue[index].status = .processing
        transcodeQueue[index].errorMessage = nil
        persistTranscodeQueue(bestEffortStatusText: nil)
        statusText = "正在转码 \(transcodeQueue[index].sourceFilename)..."

        do {
            let outputURL = try await Self.transcodeAudio(
                sourceURL: transcodeQueue[index].sourceFileURL,
                bitrateKbps: transcodeQueue[index].targetBitrateKbps,
                sampleRate: transcodeQueue[index].targetSampleRate
            )
            guard let currentIndex = transcodeQueue.firstIndex(where: { $0.id == id }) else {
                isTranscoding = false
                return
            }
            transcodeQueue[currentIndex].status = .completed
            transcodeQueue[currentIndex].outputFilePath = outputURL.path
            transcodeQueue[currentIndex].errorMessage = nil
            statusText = "转码完成：\(outputURL.lastPathComponent)"
            persistTranscodeQueue(bestEffortStatusText: "转码队列已更新")
        } catch {
            guard let currentIndex = transcodeQueue.firstIndex(where: { $0.id == id }) else {
                isTranscoding = false
                return
            }
            transcodeQueue[currentIndex].status = .failed
            transcodeQueue[currentIndex].errorMessage = error.localizedDescription
            statusText = "转码失败"
            errorMessage = error.localizedDescription
            showError = true
            persistTranscodeQueue(bestEffortStatusText: nil)
        }

        isTranscoding = false
    }

    func clearTranscodeQueue() {
        transcodeQueue.removeAll()
        selectedTranscodeID = nil
        do {
            try TranscodeQueueStore.save(transcodeQueue, to: Self.transcodeQueueURL)
            statusText = "转码列表已清空"
        } catch {
            errorMessage = "清空转码列表失败：\(error.localizedDescription)"
            showError = true
        }
    }

    func addTranscodeFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择要加入转码列表的音频文件"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .mp3,
            .wav,
            .mpeg4Audio,
            .aiff,
            UTType(filenameExtension: "flac") ?? .audio
        ]

        guard panel.runModal() == .OK else { return }

        var addedCount = 0
        for url in panel.urls {
            if enqueueLatestOutputForTranscoding(fileURL: url) != nil {
                addedCount += 1
            }
        }

        if addedCount > 0 {
            statusText = "已添加 \(addedCount) 个文件到转码列表"
        }
    }

    func selectTranscodeItem(_ item: TranscodeQueueItem) {
        selectedTranscodeID = item.id
        statusText = "已选择转码任务：\(item.sourceFilename)"
    }

    func revealTranscodedFile(_ item: TranscodeQueueItem) {
        guard let outputFileURL = item.outputFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputFileURL])
    }

    func openTranscodedFolder(_ item: TranscodeQueueItem) {
        guard let outputFileURL = item.outputFileURL else { return }
        NSWorkspace.shared.open(outputFileURL.deletingLastPathComponent())
    }

    func syncPendingTranscodeParameters() {
        for index in transcodeQueue.indices where transcodeQueue[index].status == .pending {
            transcodeQueue[index].targetBitrateKbps = transcodeBitrateKbps
            transcodeQueue[index].targetSampleRate = transcodeSampleRate
        }
        persistTranscodeQueue(bestEffortStatusText: nil)
    }

    func refreshFFmpegStatus() {
        if let path = Self.detectFFmpegPath() {
            ffmpegStatus = .available(path: path)
        } else {
            ffmpegStatus = .unavailable
        }
    }

    func installFFmpeg() async {
        guard ffmpegStatus != .installing else { return }
        guard let brewPath = Self.detectHomebrewPath() else {
            errorMessage = "未检测到 Homebrew。请先安装 Homebrew，再点击“开始安装”。"
            showError = true
            statusText = "缺少 Homebrew"
            return
        }

        ffmpegStatus = .installing
        statusText = "正在安装 ffmpeg..."

        do {
            try await Self.runCommand(
                executablePath: brewPath,
                arguments: ["install", "ffmpeg"]
            )
            refreshFFmpegStatus()
            if case .available = ffmpegStatus {
                statusText = "ffmpeg 安装完成"
            } else {
                statusText = "安装完成，请刷新检测"
            }
        } catch {
            ffmpegStatus = .unavailable
            errorMessage = error.localizedDescription
            showError = true
            statusText = "ffmpeg 安装失败"
        }
    }

    private func preparePlayback(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
        currentPlaybackURL = url
        currentlyPlayingHistoryID = history.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL })?.id
        playbackDuration = player?.duration ?? 0
        playbackPosition = player?.currentTime ?? 0
        isPlaying = true
        startPlaybackTimer()
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        currentPlaybackURL = nil
        currentlyPlayingHistoryID = nil
        playbackPosition = 0
        playbackDuration = 0
        stopPlaybackTimer()
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.playbackPosition = player.currentTime
                self.playbackDuration = player.duration
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    @discardableResult
    private func enqueueLatestOutputForTranscoding(fileURL: URL) -> TranscodeQueueItem.ID? {
        if let existingIndex = transcodeQueue.firstIndex(where: {
            $0.sourceFilePath == fileURL.path && $0.status == .pending
        }) {
            transcodeQueue[existingIndex].targetBitrateKbps = transcodeBitrateKbps
            transcodeQueue[existingIndex].targetSampleRate = transcodeSampleRate
            selectedTranscodeID = transcodeQueue[existingIndex].id
            persistTranscodeQueue(bestEffortStatusText: nil)
            return transcodeQueue[existingIndex].id
        }

        let item = TranscodeQueueItem(
            id: UUID(),
            createdAt: Date(),
            sourceFilePath: fileURL.path,
            targetBitrateKbps: transcodeBitrateKbps,
            targetSampleRate: transcodeSampleRate,
            status: .pending,
            outputFilePath: nil,
            errorMessage: nil
        )
        transcodeQueue.insert(item, at: 0)
        selectedTranscodeID = item.id
        persistTranscodeQueue(bestEffortStatusText: nil)
        return item.id
    }

    private func saveAudio(from result: GeneratedMusic) async throws -> URL {
        let data: Data
        if let audioData = result.audioData {
            data = audioData
        } else if let remoteURL = result.remoteURL {
            let (downloadedData, response) = try await URLSession.shared.data(from: remoteURL)
            try Self.validateHTTP(response: response, data: downloadedData)
            data = downloadedData
        } else {
            throw MinimaxMusicError.invalidResponse("响应里没有 audio hex 或 audio_url。")
        }

        let directory = try Self.outputDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "minimax-\(formatter.string(from: Date())).\(audioFormat.fileExtension)"
        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func appendHistory(batchID: UUID, projectID: UUID, fileURL: URL, remoteURL: URL?, seed: Int, orderInBatch: Int) {
        let track = GenerationTrack(
            id: UUID(),
            projectId: projectID,
            batchId: batchID,
            orderInBatch: orderInBatch,
            seed: seed,
            createdAt: Date(),
            directoryPath: fileURL.deletingLastPathComponent().path,
            filePath: fileURL.path,
            remoteURL: remoteURL?.absoluteString,
            displayName: nil,
            notes: nil,
            reviewRound: 0,
            reviewDecision: .pending,
            reviewTags: [],
            isSelected: false,
            selectedAt: nil,
            lastReviewedAt: nil
        )
        historyLibrary.tracks.insert(track, at: 0)
        if let batchIndex = historyLibrary.batches.firstIndex(where: { $0.id == batchID }) {
            historyLibrary.batches[batchIndex].trackCount += 1
            historyLibrary.batches[batchIndex].updatedAt = Date()
        }
        updateProjectTimestamp(projectID: projectID, date: Date())
        persistAndRefreshHistory(selecting: track.id)
    }

    private func ensureActiveProject() -> GenerationProject {
        if let selectedProjectID, let project = historyLibrary.projects.first(where: { $0.id == selectedProjectID }) {
            return project
        }

        if let existing = historyLibrary.projects.first(where: { !$0.isArchived }) {
            selectedProjectID = existing.id
            return existing
        }

        let project = GenerationProject.default()
        historyLibrary.projects.append(project)
        selectedProjectID = project.id
        return project
    }

    private func nextBatchSequenceNumber(in projectID: UUID) -> Int {
        let existing = historyLibrary.batches.filter { $0.projectId == projectID }.map(\.sequenceNumber)
        return (existing.max() ?? 0) + 1
    }

    private func updateProjectTimestamp(projectID: UUID, date: Date) {
        guard let projectIndex = historyLibrary.projects.firstIndex(where: { $0.id == projectID }) else { return }
        historyLibrary.projects[projectIndex].updatedAt = date
    }

    private func addCategoryToLibrary(_ category: String) {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !categoryLibrary.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            categoryLibrary.append(trimmed)
            categoryLibrary.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            UserDefaults.standard.set(categoryLibrary, forKey: Defaults.categoryLibrary)
        }
    }

    private func refreshHistoryViews() {
        let snapshot = GenerationHistorySnapshot(library: historyLibrary)
        history = snapshot.items
        projectLibrary = snapshot.projects
        if let activeProject {
            draftProjectName = activeProject.name
        }
        rebuildCategoryLibraryIfNeeded()
    }

    private var selectedHistoryItem: GenerationHistoryItem? {
        guard let selectedHistoryID else { return nil }
        return history.first(where: { $0.id == selectedHistoryID })
    }

    private func uniqueProjectName(from proposedName: String, excluding excludedID: UUID? = nil) -> String {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "默认项目" }

        let existingNames = Set(
            historyLibrary.projects
                .filter { $0.id != excludedID }
                .map { $0.name.lowercased() }
        )

        if !existingNames.contains(trimmed.lowercased()) {
            return trimmed
        }

        var index = 2
        while existingNames.contains("\(trimmed) \(index)".lowercased()) {
            index += 1
        }
        return "\(trimmed) \(index)"
    }

    private func rebuildCategoryLibraryIfNeeded() {
        for item in history {
            if !item.categoryText.isEmpty {
                addCategoryToLibrary(item.categoryText)
            }
        }
    }

    private func persistHistory() {
        do {
            try GenerationHistoryStore.save(historyLibrary, to: Self.historyURL)
        } catch {
            errorMessage = "历史记录保存失败：\(error.localizedDescription)"
            showError = true
        }
    }

    private func persistAndRefreshHistory(selecting trackID: GenerationTrack.ID? = nil) {
        refreshHistoryViews()
        if let trackID {
            selectedHistoryID = trackID
        }
        persistHistory()
    }

    private static func outputDirectory() throws -> URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = music.appendingPathComponent("MusicMaker-AI", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var historyURL: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return music
            .appendingPathComponent("MusicMaker-AI", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    private static var transcodeQueueURL: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return music
            .appendingPathComponent("MusicMaker-AI", isDirectory: true)
            .appendingPathComponent("transcode-queue.json")
    }

    private func persistTranscodeQueue(bestEffortStatusText: String?) {
        do {
            try TranscodeQueueStore.save(transcodeQueue, to: Self.transcodeQueueURL)
            if let bestEffortStatusText {
                statusText = bestEffortStatusText
            }
        } catch {
            errorMessage = "转码列表保存失败：\(error.localizedDescription)"
            showError = true
        }
    }

    private static func transcodeAudio(sourceURL: URL, bitrateKbps: Int, sampleRate: Int) async throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MinimaxMusicError.invalidResponse("源音频文件不存在：\(sourceURL.path)")
        }

        let transcodeDirectory = try outputDirectory().appendingPathComponent("Transcoded", isDirectory: true).creatingDirectoryIfNeeded()
        let outputURL = transcodeDirectory.appendingPathComponent(makeTranscodedFilename(from: sourceURL, bitrateKbps: bitrateKbps, sampleRate: sampleRate))
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try await runFFmpeg(
            arguments: [
                "-y",
                "-i", sourceURL.path,
                "-b:a", "\(bitrateKbps)k",
                "-ar", "\(sampleRate)",
                outputURL.path
            ]
        )

        return outputURL
    }

    private static func runFFmpeg(arguments: [String]) async throws {
        guard let ffmpegPath = detectFFmpegPath() else {
            throw MinimaxMusicError.requestFailed("未检测到可用的 ffmpeg。")
        }
        try await runCommand(executablePath: ffmpegPath, arguments: arguments)
    }

    private static func makeTranscodedFilename(from sourceURL: URL, bitrateKbps: Int, sampleRate: Int) -> String {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = preferredTranscodeExtension(for: sourceURL)
        let khzText = String(format: "%.1f", Double(sampleRate) / 1000.0)
        return "\(baseName)-\(bitrateKbps)kbps-\(khzText)kHz.\(ext)"
    }

    private static func preferredTranscodeExtension(for sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.lowercased()
        return ext.isEmpty ? "mp3" : ext
    }

    private static func detectFFmpegPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }

    private static func detectHomebrewPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    private static func runCommand(executablePath: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            ].joined(separator: ":")
            process.environment = environment

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()

            process.terminationHandler = { process in
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: MinimaxMusicError.requestFailed(errorOutput ?? "命令执行失败"))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: MinimaxMusicError.requestFailed("无法启动命令：\(error.localizedDescription)"))
            }
        }
    }

    nonisolated private static func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw MinimaxMusicError.requestFailed(body)
        }
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeSeed() -> Int? {
        if randomSeed {
            return Int.random(in: 0...1_000_000)
        }

        guard let seed = Int(manualSeedText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        guard (0...1_000_000).contains(seed) else {
            return nil
        }

        return seed
    }

    private func normalizedInput(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n")
    }

    private func requestLyrics(from normalizedLyrics: String, prompt normalizedPrompt: String) -> String {
        if instrumental {
            return nonEmpty(normalizedLyrics) ?? "[instrumental]"
        }

        return nonEmpty(normalizedLyrics) ?? normalizedPrompt
    }
}

extension MusicGeneratorViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            playbackPosition = 0
            stopPlaybackTimer()
        }
    }
}

private enum Defaults {
    static let baseURL = "baseURL"
    static let apiKey = "apiKey"
    static let model = "model"
    static let outputMode = "outputMode"
    static let audioFormat = "audioFormat"
    static let sampleRate = "sampleRate"
    static let bitrate = "bitrate"
    static let generationCount = "generationCount"
    static let transcodeBitrateKbps = "transcodeBitrateKbps"
    static let transcodeSampleRate = "transcodeSampleRate"
    static let autoTranscodeAfterGeneration = "autoTranscodeAfterGeneration"
    static let autoPlayAfterGeneration = "autoPlayAfterGeneration"
    static let generationCategory = "generationCategory"
    static let categoryLibrary = "categoryLibrary"
    static let selectedProjectID = "selectedProjectID"
    static let lyricsOptimizer = "lyricsOptimizer"
    static let instrumental = "instrumental"
    static let aigcWatermark = "aigcWatermark"
    static let randomSeed = "randomSeed"
    static let manualSeedText = "manualSeedText"
    static let prompt = "prompt"
    static let lyrics = "lyrics"
    static let referenceAudioURL = "referenceAudioURL"
}

private extension URL {
    func creatingDirectoryIfNeeded() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
