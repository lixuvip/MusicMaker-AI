import AVFoundation
import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel
    @State private var selectedModule: ToolModule? = .musicGeneration

    var body: some View {
        NavigationSplitView {
            ModuleSidebar(selectedModule: $selectedModule)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            Group {
                switch selectedModule ?? .musicGeneration {
                case .musicGeneration:
                    MusicGenerationModule()
                case .audioTranscoding:
                    AudioTranscodingModule()
                }
            }
        }
        .alert("生成失败", isPresented: $viewModel.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

enum ToolModule: String, CaseIterable, Identifiable {
    case musicGeneration
    case audioTranscoding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .musicGeneration:
            return "音乐生成"
        case .audioTranscoding:
            return "音频转码"
        }
    }

    var subtitle: String {
        switch self {
        case .musicGeneration:
            return "MiniMax /v1/music_generation"
        case .audioTranscoding:
            return "本地 ffmpeg 转码队列"
        }
    }

    var systemImage: String {
        switch self {
        case .musicGeneration:
            return "music.quarternote.3"
        case .audioTranscoding:
            return "waveform.badge.magnifyingglass"
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

                PlayerToolbar()

                if let fileURL = viewModel.lastFileURL {
                    ResultRow(fileURL: fileURL, remoteURL: viewModel.lastRemoteURL, seed: viewModel.lastSeed)
                }

                HistoryPanel()

                Spacer(minLength: 0)
            }
            .padding(28)
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

            if viewModel.history.isEmpty {
                Text("成功生成后会在这里记录提交参数、Seed、目录、文件路径和链接。")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    List(viewModel.history, selection: $viewModel.selectedHistoryID) { item in
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
                .disabled(selectedItem == nil || viewModel.isTranscoding)
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
    let item: GenerationHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .lineLimit(2)
                .font(.headline)
            HStack {
                Text(item.createdAtText)
                Text("Seed \(item.seed)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(URL(fileURLWithPath: item.filePath).lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

struct HistoryDetail: View {
    @EnvironmentObject private var viewModel: MusicGeneratorViewModel
    let item: GenerationHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.createdAtText)
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.loadHistoryParameters(item)
                } label: {
                    Label("加载参数", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
            }

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
                HistoryField("选项", optionText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("音乐要求")
                    .font(.subheadline.weight(.semibold))
                Text(item.prompt)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("歌词")
                    .font(.subheadline.weight(.semibold))
                Text(item.lyrics)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var optionText: String {
        [
            item.instrumental ? "纯音乐" : "含歌词",
            item.lyricsOptimizer ? "歌词优化" : "不优化歌词",
            item.aigcWatermark ? "AI 水印" : "无 AI 水印"
        ].joined(separator: "，")
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
