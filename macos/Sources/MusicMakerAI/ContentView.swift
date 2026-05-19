import AVFoundation
import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel
    @State private var selectedModule: ToolModule? = .musicGeneration

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                ModuleSidebar(selectedModule: $selectedModule)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            } detail: {
                Group {
                    switch selectedModule ?? .musicGeneration {
                    case .musicGeneration:
                        MusicGenerationModule()
                    case .voiceCloning:
                        VoiceCloningModule()
                    case .audioTranscoding:
                        AudioTranscodingModule()
                    case .history:
                        HistoryModule()
                    }
                }
            }
            Divider()
            GlobalPlayerBar()
        }
        .alert("生成失败", isPresented: $viewModel.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .background(
            PlaybackShortcutMonitor {
                viewModel.togglePlaybackFromCommand()
            }
        )
    }
}

enum ToolModule: String, CaseIterable, Identifiable {
    case musicGeneration
    case voiceCloning
    case audioTranscoding
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .musicGeneration:
            return "音乐生成"
        case .voiceCloning:
            return "声音克隆"
        case .audioTranscoding:
            return "音频转码"
        case .history:
            return "历史记录"
        }
    }

    var subtitle: String {
        switch self {
        case .musicGeneration:
            return "MiniMax /v1/music_generation"
        case .voiceCloning:
            return "VoxCPM 插件模块"
        case .audioTranscoding:
            return "本地 ffmpeg 转码队列"
        case .history:
            return "生成参数与文件记录"
        }
    }

    var systemImage: String {
        switch self {
        case .musicGeneration:
            return "music.quarternote.3"
        case .voiceCloning:
            return "waveform.and.mic"
        case .audioTranscoding:
            return "waveform.badge.magnifyingglass"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

struct ModuleSidebar: View {
    @Binding var selectedModule: ToolModule?

    var body: some View {
        List(ToolModule.allCases, selection: $selectedModule) { module in
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(module.title)
                        .font(.headline)
                    Text(module.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: module.systemImage)
            }
            .tag(module)
        }
        .navigationTitle("工具")
    }
}

struct PlaybackShortcutMonitor: NSViewRepresentable {
    let onSpace: () -> Void

    func makeNSView(context: Context) -> PlaybackShortcutMonitorView {
        let view = PlaybackShortcutMonitorView()
        view.onSpace = onSpace
        return view
    }

    func updateNSView(_ nsView: PlaybackShortcutMonitorView, context: Context) {
        nsView.onSpace = onSpace
    }
}

final class PlaybackShortcutMonitorView: NSView {
    var onSpace: (() -> Void)?
    private var localMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else {
            installMonitorIfNeeded()
        }
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event: event)
        }
    }

    private func removeMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
            return event
        }
        guard event.charactersIgnoringModifiers == " " else {
            return event
        }
        guard !isEditingText else {
            return event
        }

        onSpace?()
        return nil
    }

    private var isEditingText: Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder is NSTextView
    }
}

struct MusicGenerationModule: View {
    var body: some View {
        HStack(spacing: 0) {
            SettingsPanel()
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
            Divider()
            GeneratorPanel()
        }
        .navigationTitle("音乐生成")
    }
}

struct AudioTranscodingModule: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("音频转码")
                        .font(.largeTitle.weight(.semibold))
                    Text("管理自动加入或手动添加的音频文件，按目标比特率和采样率进行本地转码。")
                        .foregroundStyle(.secondary)
                }

                TranscodePanel()

                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .navigationTitle("音频转码")
    }
}

struct HistoryModule: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("历史记录")
                        .font(.largeTitle.weight(.semibold))
                    Text("查看历史生成参数、音频文件路径、Seed 与提交内容，方便回溯和复用。")
                        .foregroundStyle(.secondary)
                }

                HistoryPanel()

                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .navigationTitle("历史记录")
    }
}

struct SettingsPanel: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var body: some View {
        Form {
            Section("MiniMax 配置") {
                TextField("https://api.minimaxi.com", text: $viewModel.baseURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("配置只保存在这台 Mac 的本地用户设置里。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("模型") {
                Picker("模型", selection: $viewModel.model) {
                    ForEach(MusicModel.allCases) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
                .pickerStyle(.menu)

                if viewModel.model == .cover {
                    TextField("参考音频 URL", text: $viewModel.referenceAudioURL)
                        .textFieldStyle(.roundedBorder)
                    Text("用于翻唱/参考音色场景。普通生成可使用 free 或 professional 模型。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("输出") {
                Picker("返回方式", selection: $viewModel.outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("格式", selection: $viewModel.audioFormat) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Picker("采样率", selection: $viewModel.sampleRate) {
                    Text("32 kHz").tag(32000)
                    Text("44.1 kHz").tag(44100)
                }
                .pickerStyle(.segmented)

                Picker("比特率", selection: $viewModel.bitrate) {
                    Text("128 kbps").tag(128000)
                    Text("256 kbps").tag(256000)
                }
                .pickerStyle(.segmented)

                Picker("生成数量", selection: $viewModel.generationCount) {
                    ForEach(1...10, id: \.self) { count in
                        Text("\(count) 首").tag(count)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("选项") {
                Toggle("歌词优化", isOn: $viewModel.lyricsOptimizer)
                Toggle("纯音乐", isOn: $viewModel.instrumental)
                Toggle("添加 AI 水印", isOn: $viewModel.aigcWatermark)
            }

            Section("Seed") {
                Toggle("每次随机", isOn: $viewModel.randomSeed)
                TextField("手动 Seed", text: $viewModel.manualSeedText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.randomSeed)
                if let lastSeed = viewModel.lastSeed {
                    HStack {
                        Text("上次 Seed")
                        Spacer()
                        Text(String(lastSeed))
                            .font(.body.monospacedDigit())
                            .textSelection(.enabled)
                        Button {
                            viewModel.copyLastSeed()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("复制 Seed")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }
}

struct GeneratorPanel: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("音乐生成")
                        .font(.largeTitle.weight(.semibold))
                    Text("写下你想要的风格、情绪、结构和歌词，生成完成后会自动保存到本机。")
                        .foregroundStyle(.secondary)
                }

                ProjectPanel()

                VStack(alignment: .leading, spacing: 8) {
                    Label("音乐要求", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    TextEditor(text: $viewModel.prompt)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .frame(minHeight: 130)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("歌词", systemImage: "music.note.list")
                        .font(.headline)
                    TextEditor(text: $viewModel.lyrics)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .frame(minHeight: 180)
                        .disabled(viewModel.instrumental)
                        .opacity(viewModel.instrumental ? 0.45 : 1)

                    if viewModel.needsLyrics {
                        Text("MiniMax 要求 lyrics 字段。请填写歌词，或在左侧打开「纯音乐」。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("本次分类", systemImage: "tag")
                        .font(.headline)
                    HStack(spacing: 10) {
                        Picker("分类列表", selection: Binding(
                            get: { viewModel.generationCategory },
                            set: { viewModel.selectGenerationCategory($0) }
                        )) {
                            Text("未选择").tag("")
                            ForEach(viewModel.categoryLibrary, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("输入新分类", text: $viewModel.generationCategory)
                            .textFieldStyle(.roundedBorder)

                        Button("加入分类库") {
                            viewModel.addGenerationCategoryToLibrary()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.generationCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("这里填写的分类会自动写入本次生成的所有历史记录，批量生成时每首都会继承。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                PlayerToolbar()

                Toggle("生成完成后自动播放", isOn: $viewModel.autoPlayAfterGeneration)
                    .disabled(viewModel.generationCount > 1)

                if viewModel.generationCount > 1 {
                    Text("批量生成时不支持“生成后自动播放”，以避免播放状态和批量任务互相干扰。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isGenerating && viewModel.batchProgressTotal > 1 {
                    BatchProgressPanel()
                }

                if let fileURL = viewModel.lastFileURL {
                    ResultRow(fileURL: fileURL, remoteURL: viewModel.lastRemoteURL, seed: viewModel.lastSeed)
                }

                Spacer(minLength: 0)
            }
            .padding(28)
        }
    }
}

struct ProjectPanel: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("当前项目", systemImage: "folder.badge.person.crop")
                .font(.headline)

            HStack(spacing: 10) {
                Picker("项目", selection: Binding(
                    get: { viewModel.selectedProjectID },
                    set: { viewModel.selectProject($0) }
                )) {
                    ForEach(viewModel.projectLibrary) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)

                Button {
                    viewModel.createProject()
                } label: {
                    Label("新建项目", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            TextField("项目名称", text: $viewModel.draftProjectName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.renameSelectedProject(to: viewModel.draftProjectName)
                }

            HStack(spacing: 10) {
                Button("保存项目名称") {
                    viewModel.renameSelectedProject(to: viewModel.draftProjectName)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedProjectID == nil)

                if let activeProject = viewModel.activeProject {
                    Text("当前写入：\(activeProject.name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text("生成时会先落到当前项目，再在项目下创建批次并写入单曲结果。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct PlayerToolbar: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.generate() }
            } label: {
                Label(viewModel.isGenerating ? "生成中..." : "生成音乐", systemImage: "wand.and.stars")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canGenerate)

            if viewModel.isGenerating {
                ProgressView()
                    .controlSize(.small)
            }
            Text(viewModel.statusText)
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.lastFileURL != nil {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Label(viewModel.isPlaying ? "暂停" : "播放", systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.openOutputFolder()
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.revealOutputFile()
                } label: {
                    Label("定位文件", systemImage: "scope")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.copyOutputFile()
                } label: {
                    Label("复制文件", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct ResultRow: View {
    let fileURL: URL
    let remoteURL: URL?
    let seed: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("已保存", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
            Text(fileURL.path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            if let seed {
                Text("Seed: \(seed)")
                    .font(.callout.monospacedDigit())
                    .textSelection(.enabled)
            }
            if let remoteURL {
                Link("MiniMax 临时音频链接", destination: remoteURL)
                    .font(.callout)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BatchProgressPanel: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("批量生成进度", systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.batchProgressCompleted) / \(viewModel.batchProgressTotal)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: Double(viewModel.batchProgressCompleted),
                total: Double(max(viewModel.batchProgressTotal, 1))
            )

            Text(progressText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private var progressText: String {
        if viewModel.batchProgressCurrentIndex > 0 {
            return "当前正在处理第 \(viewModel.batchProgressCurrentIndex) 首，已完成 \(viewModel.batchProgressCompleted) 首。"
        }
        return "正在准备批量生成任务。"
    }
}

struct HistoryPanel: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var selectedItem: GenerationHistoryItem? {
        guard let selectedID = viewModel.selectedHistoryID else { return nil }
        return viewModel.history.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("历史记录", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if !viewModel.history.isEmpty {
                    Button("清空历史", role: .destructive) {
                        viewModel.clearHistory()
                    }
                    .buttonStyle(.bordered)
                }
            }

            HistoryFilterBar()

            if viewModel.filteredHistory.isEmpty {
                Text("成功生成后会在这里记录项目、批次、轮次、文件路径和筛选状态。")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    List(viewModel.filteredHistory, selection: $viewModel.selectedHistoryID) { item in
                        HistoryListRow(item: item)
                            .tag(item.id)
                            .onTapGesture {
                                viewModel.selectHistory(item)
                            }
                    }
                    .frame(minWidth: 300, minHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let selectedItem {
                        HistoryDetail(item: selectedItem)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Text("选择一条历史记录查看详情。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 260)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct HistoryFilterBar: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("项目", selection: $viewModel.historyProjectFilter) {
                    Text("全部项目").tag(Optional<GenerationProject.ID>.none)
                    ForEach(viewModel.projectLibrary) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)

                Picker("轮次", selection: $viewModel.historyReviewFilter) {
                    ForEach(MusicGeneratorViewModel.HistoryReviewFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("选中状态", selection: $viewModel.historySelectionFilter) {
                    ForEach(MusicGeneratorViewModel.SelectionFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                Picker("分类", selection: $viewModel.historyCategoryFilter) {
                    Text("全部分类").tag("")
                    ForEach(viewModel.availableHistoryCategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.menu)

                if !viewModel.historyCategoryFilter.isEmpty {
                    Button("清除分类") {
                        viewModel.historyCategoryFilter = ""
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Text("共 \(viewModel.filteredHistory.count) 条")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TranscodePanel: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var selectedItem: TranscodeQueueItem? {
        guard let selectedID = viewModel.selectedTranscodeID else { return nil }
        return viewModel.transcodeQueue.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("音频转码", systemImage: "waveform.badge.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.addTranscodeFiles()
                } label: {
                    Label("添加文件", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                if !viewModel.transcodeQueue.isEmpty {
                    Button("清空列表", role: .destructive) {
                        viewModel.clearTranscodeQueue()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("最新生成的音乐会自动加入转码列表，默认按 320 kbps / 44.1 kHz 处理。")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(ffmpegStatusText, systemImage: ffmpegSystemImage)
                    .foregroundStyle(ffmpegStatusColor)

                Button("刷新检测") {
                    viewModel.refreshFFmpegStatus()
                }
                .buttonStyle(.bordered)

                if case .unavailable = viewModel.ffmpegStatus {
                    Button {
                        Task { await viewModel.installFFmpeg() }
                    } label: {
                        Label("开始安装", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if case .installing = viewModel.ffmpegStatus {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let selectedItem {
                Text("已添加文件：\(selectedItem.sourceFilename)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Toggle("生成完成后自动转码", isOn: $viewModel.autoTranscodeAfterGeneration)

            HStack(spacing: 12) {
                Picker("目标比特率", selection: $viewModel.transcodeBitrateKbps) {
                    Text("128 kbps").tag(128)
                    Text("256 kbps").tag(256)
                    Text("320 kbps").tag(320)
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.transcodeBitrateKbps) { _ in
                    viewModel.syncPendingTranscodeParameters()
                }

                Picker("目标采样率", selection: $viewModel.transcodeSampleRate) {
                    Text("32 kHz").tag(32000)
                    Text("44.1 kHz").tag(44100)
                    Text("48 kHz").tag(48000)
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.transcodeSampleRate) { _ in
                    viewModel.syncPendingTranscodeParameters()
                }

                Button {
                    Task { await viewModel.runSelectedTranscode() }
                } label: {
                    Label(viewModel.isTranscoding ? "转码中..." : "开始转码", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItem == nil || viewModel.isTranscoding || !ffmpegReady)
            }

            if viewModel.transcodeQueue.isEmpty {
                Text("生成一首歌曲后，这里会自动出现待转码任务。")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    List(viewModel.transcodeQueue, selection: $viewModel.selectedTranscodeID) { item in
                        TranscodeListRow(item: item)
                            .tag(item.id)
                            .onTapGesture {
                                viewModel.selectTranscodeItem(item)
                            }
                    }
                    .frame(minWidth: 300, minHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let selectedItem {
                        TranscodeDetail(item: selectedItem)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Text("选择一条转码任务查看详情。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private var ffmpegReady: Bool {
        if case .available = viewModel.ffmpegStatus {
            return true
        }
        return false
    }

    private var ffmpegStatusText: String {
        switch viewModel.ffmpegStatus {
        case .available(let path):
            return "ffmpeg 已就绪：\(path)"
        case .unavailable:
            return "未检测到 ffmpeg，可点击“开始安装”自动安装"
        case .installing:
            return "正在通过 Homebrew 安装 ffmpeg..."
        }
    }

    private var ffmpegSystemImage: String {
        switch viewModel.ffmpegStatus {
        case .available:
            return "checkmark.circle.fill"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        case .installing:
            return "gearshape.2.fill"
        }
    }

    private var ffmpegStatusColor: Color {
        switch viewModel.ffmpegStatus {
        case .available:
            return .green
        case .unavailable:
            return .orange
        case .installing:
            return .secondary
        }
    }
}

struct TranscodeListRow: View {
    let item: TranscodeQueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.sourceFilename)
                .lineLimit(1)
                .font(.headline)
            HStack {
                Text(item.createdAtText)
                Text(item.status.title)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("\(item.targetBitrateKbps) kbps / \(sampleRateText(item.targetSampleRate))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

struct TranscodeDetail: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel
    let item: TranscodeQueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.createdAtText)
                    .font(.headline)
                Spacer()
                if item.status != .processing {
                    Button {
                        Task { await viewModel.runTranscode(for: item.id) }
                    } label: {
                        Label("转码此条", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isTranscoding)
                }
                if item.outputFileURL != nil {
                    Button {
                        viewModel.openTranscodedFolder(item)
                    } label: {
                        Label("打开目录", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.revealTranscodedFile(item)
                    } label: {
                        Label("定位文件", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                HistoryField("状态", item.status.title)
                HistoryField("源文件", item.sourceFilePath)
                HistoryField("目标参数", "\(item.targetBitrateKbps) kbps / \(sampleRateText(item.targetSampleRate))")
                if let outputFilePath = item.outputFilePath {
                    HistoryField("输出文件", outputFilePath)
                }
                if let errorMessage = item.errorMessage {
                    HistoryField("错误信息", errorMessage)
                }
            }
        }
    }
}

struct HistoryListRow: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel
    let item: GenerationHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        if viewModel.isCurrentlyPlaying(item) {
                            Label("播放中", systemImage: viewModel.isPlaying ? "speaker.wave.2.fill" : "pause.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }

                        if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                            Label("有备注", systemImage: "note.text")
                                .font(.caption)
                                .foregroundStyle(.teal)
                                .help(notes)
                        }

                        Text(listTitle)
                            .lineLimit(1)
                            .font(.headline)
                            .foregroundStyle(titleColor)
                    }

                    HStack(spacing: 8) {
                        Text(item.createdAtText)
                        Text(item.projectName)
                        if !item.categoryText.isEmpty {
                            Text(item.categoryText)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        HistoryStatusBadge(
                            title: roundTitle,
                            systemImage: roundSystemImage,
                            foregroundColor: statusColor,
                            backgroundColor: statusBackgroundColor
                        )
                        if item.isSelected {
                            HistoryStatusBadge(
                                title: "最终选中",
                                systemImage: "checkmark.seal.fill",
                                foregroundColor: .green,
                                backgroundColor: .green.opacity(0.12)
                            )
                        }
                    }
                    .font(.caption)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button {
                        viewModel.playFile(url: item.fileURL)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("播放")

                    Button {
                        viewModel.openHistoryFolder(item)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("打开文件夹")

                    Button {
                        viewModel.advanceToNextRound(for: item.id)
                    } label: {
                        Image(systemName: "arrow.right.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("推进下一轮")

                    Button {
                        viewModel.toggleSelected(for: item.id)
                    } label: {
                        Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.borderless)
                    .help(item.isSelected ? "取消已选中" : "标记已选中")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var roundTitle: String {
        if item.reviewDecision == .rejected {
            return "已淘汰"
        }
        if item.isSelected || item.reviewDecision == .selected {
            return "最终选中"
        }
        if item.reviewRound > 0 {
            return "第 \(item.reviewRound) 轮"
        }
        return "待筛选"
    }

    private var roundSystemImage: String {
        if item.reviewDecision == .rejected {
            return "xmark.circle"
        }
        if item.isSelected || item.reviewDecision == .selected {
            return "checkmark.circle"
        }
        if item.reviewRound > 0 {
            return "arrow.triangle.branch"
        }
        return "clock"
    }

    private var titleColor: Color {
        if item.reviewDecision == .rejected {
            return .secondary
        }
        if item.isSelected || item.reviewDecision == .selected {
            return .green
        }
        if item.reviewRound > 0 {
            return .orange
        }
        return .primary
    }

    private var statusColor: Color {
        if item.reviewDecision == .rejected {
            return .red
        }
        if item.isSelected || item.reviewDecision == .selected {
            return .green
        }
        if item.reviewRound > 0 {
            return .orange
        }
        return .secondary
    }

    private var statusBackgroundColor: Color {
        if item.reviewDecision == .rejected {
            return .red.opacity(0.12)
        }
        if item.isSelected || item.reviewDecision == .selected {
            return .green.opacity(0.12)
        }
        if item.reviewRound > 0 {
            return .yellow.opacity(0.18)
        }
        return .secondary.opacity(0.10)
    }

    private var listTitle: String {
        "\(item.projectName) \(item.batchCode)"
    }
}

struct HistoryDetail: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel
    @State private var targetProjectID: GenerationProject.ID?
    @State private var notesDraft = ""
    @State private var showAdvancedDetails = false
    @State private var showManagementTools = false
    @State private var showPromptDetails = false
    @State private var showLyricsDetails = false
    let item: GenerationHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.batchCode)
                        .font(.headline.monospaced())
                    Text(item.createdAtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.playFile(url: item.fileURL)
                } label: {
                    Label("播放此条", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                Button {
                    viewModel.openHistoryFolder(item)
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                Button {
                    viewModel.revealHistoryFile(item)
                } label: {
                    Label("定位文件", systemImage: "scope")
                }
                .buttonStyle(.bordered)
                Button {
                    viewModel.loadHistoryParameters(item)
                } label: {
                    Label("加载参数", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                HistoryField("项目", item.projectName)
                HistoryField("批次", item.batchCode)
                HistoryTintedField(label: "轮次", value: reviewRoundText, color: statusColor)
                HistoryTintedField(label: "状态", value: item.reviewDecision.title, color: statusColor)
                HistoryTintedField(label: "是否选中", value: item.isSelected ? "是" : "否", color: item.isSelected ? .green : .secondary)
                HistoryField("分类", item.categoryText.isEmpty ? "未设置" : item.categoryText)
                HistoryField("选项", optionText)
            }

            HistoryDisclosureSection(
                title: showAdvancedDetails ? "收起详细参数" : "展开详细参数",
                isExpanded: $showAdvancedDetails
            ) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                    HistoryField("模型", item.model)
                    HistoryField("Seed", String(item.seed))
                    HistoryField("输出", "\(item.outputFormat) / \(item.audioFormat)")
                    HistoryField("音频", "\(item.sampleRate) Hz / \(item.bitrate) bps")
                    HistoryField("目录", item.directoryPath)
                    HistoryField("文件", item.filePath)
                    if let remoteURL = item.remoteURL {
                        HistoryField("远端链接", remoteURL)
                    }
                    if let referenceAudioURL = item.referenceAudioURL {
                        HistoryField("参考音频", referenceAudioURL)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.subheadline.weight(.semibold))

                TextField("输入备注", text: $notesDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)

                HStack(spacing: 10) {
                    Button("保存备注") {
                        viewModel.updateTrackNotes(for: item.id, notes: notesDraft)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("清空备注") {
                        notesDraft = ""
                        viewModel.updateTrackNotes(for: item.id, notes: "")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }

            HistoryDisclosureSection(
                title: showManagementTools ? "收起管理工具" : "展开管理工具",
                isExpanded: $showManagementTools
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("移动到项目")
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 10) {
                            Picker("目标项目", selection: $targetProjectID) {
                                Text("选择目标项目").tag(Optional<GenerationProject.ID>.none)
                                ForEach(availableMoveProjects) { project in
                                    Text(project.name).tag(Optional(project.id))
                                }
                            }
                            .pickerStyle(.menu)

                            Button("移动") {
                                if let projectID = targetProjectID {
                                    viewModel.moveTrack(item.id, toProject: projectID)
                                    targetProjectID = nil
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(targetProjectID == nil)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("分类")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            Picker("分类列表", selection: Binding(
                                get: { item.categoryText },
                                set: { viewModel.updateCategory(for: item.id, category: $0) }
                            )) {
                                Text("未选择").tag("")
                                ForEach(viewModel.categoryLibrary, id: \.self) { category in
                                    Text(category).tag(category)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField(
                                "输入新分类",
                                text: Binding(
                                    get: { item.categoryText },
                                    set: { viewModel.updateCategory(for: item.id, category: $0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(.top, 8)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.advanceToNextRound(for: item.id)
                } label: {
                    Label("推进下一轮", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.isSelected)

                Button {
                    viewModel.toggleSelected(for: item.id)
                } label: {
                    Label(item.isSelected ? "取消选中" : "标记已选中", systemImage: item.isSelected ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    viewModel.rejectTrack(item.id)
                } label: {
                    Label("淘汰", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }

            HistoryDisclosureSection(
                title: showPromptDetails ? "收起音乐要求" : "展开音乐要求",
                isExpanded: $showPromptDetails
            ) {
                Text(item.prompt)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 8)
            }

            HistoryDisclosureSection(
                title: showLyricsDetails ? "收起歌词" : "展开歌词",
                isExpanded: $showLyricsDetails
            ) {
                Text(item.lyrics)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 8)
            }
        }
        .onAppear {
            if targetProjectID == nil {
                targetProjectID = availableMoveProjects.first?.id
            }
            notesDraft = item.notes ?? ""
        }
        .onChange(of: item.projectId) { _ in
            targetProjectID = availableMoveProjects.first?.id
        }
        .onChange(of: item.id) { _ in
            targetProjectID = availableMoveProjects.first?.id
            notesDraft = item.notes ?? ""
        }
    }

    private var optionText: String {
        [
            item.instrumental ? "纯音乐" : "含歌词",
            item.lyricsOptimizer ? "歌词优化" : "不优化歌词",
            item.aigcWatermark ? "AI 水印" : "无 AI 水印"
        ].joined(separator: "，")
    }

    private var reviewRoundText: String {
        if item.isSelected || item.reviewDecision == .selected {
            return "最终 selected"
        }
        if item.reviewDecision == .rejected {
            return "已淘汰"
        }
        if item.reviewRound == 0 {
            return "待筛选"
        }
        return "第 \(item.reviewRound) 轮"
    }

    private var statusColor: Color {
        if item.reviewDecision == .rejected {
            return .red
        }
        if item.isSelected || item.reviewDecision == .selected {
            return .green
        }
        if item.reviewRound > 0 {
            return .orange
        }
        return .secondary
    }

    private var availableMoveProjects: [GenerationProject] {
        viewModel.projectLibrary.filter { $0.id != item.projectId }
    }
}

struct HistoryTintedField: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
    }
}

struct HistoryStatusBadge: View {
    let title: String
    let systemImage: String
    let foregroundColor: Color
    let backgroundColor: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(foregroundColor)
    }
}

struct HistoryDisclosureSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                DisclosureHeader(title: title, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
            }
        }
    }
}

struct DisclosureHeader: View {
    let title: String
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct GlobalPlayerBar: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text("拖拽本地音频到这里即可直接播放；同一时间只会播放一首。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.currentPlaybackURL == nil)
            }

            HStack(spacing: 12) {
                Text(formattedTime(viewModel.playbackPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { viewModel.playbackPosition },
                        set: { viewModel.seekPlayback(to: $0) }
                    ),
                    in: 0...max(viewModel.playbackDuration, 1)
                )
                .disabled(viewModel.currentPlaybackURL == nil)

                Text(formattedTime(viewModel.playbackDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            viewModel.acceptDroppedAudioFiles(providers)
        }
    }

    private var currentTitle: String {
        guard let url = viewModel.currentPlaybackURL else {
            return "播放器待命中"
        }
        return url.lastPathComponent
    }

    private func formattedTime(_ time: Double) -> String {
        guard time.isFinite, !time.isNaN else { return "00:00" }
        let total = Int(time.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

@MainActor
private func HistoryField(_ label: String, _ value: String) -> some View {
    GridRow {
        Text(label)
            .foregroundStyle(.secondary)
        Text(value)
            .textSelection(.enabled)
            .lineLimit(2)
    }
}

private func sampleRateText(_ sampleRate: Int) -> String {
    String(format: "%.1f kHz", Double(sampleRate) / 1000.0)
}
