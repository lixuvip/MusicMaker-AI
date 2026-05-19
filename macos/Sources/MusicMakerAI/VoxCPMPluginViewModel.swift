import Foundation
import Combine
import AppKit

@MainActor
final class VoxCPMPluginViewModel: ObservableObject {
    @Published var configuration: VoxCPMPluginConfiguration
    @Published var runtimeState: VoxCPMRuntimeState
    @Published var taskHistory: [VoxCPMTaskRecord]
    @Published var statusMessage: String
    @Published var errorMessage: String?
    @Published var lastValidationDate: Date?
    @Published var isRunningHealthCheck: Bool
    @Published var latestHealthCheck: VoxCPMHealthCheckResult?
    @Published var quickCloneDraft: VoxCPMQuickCloneDraft
    @Published var voiceDesignDraft: VoxCPMVoiceDesignDraft
    @Published var activeTaskID: UUID?
    @Published var activeTaskMode: VoxCPMTaskMode?
    @Published var lastCompletedTaskID: UUID?

    private let store: VoxCPMPluginStore
    private let runtime: VoxCPMPluginRuntime

    init(
        store: VoxCPMPluginStore = VoxCPMPluginStore(),
        runtime: VoxCPMPluginRuntime = VoxCPMPluginRuntime()
    ) {
        self.store = store
        self.runtime = runtime
        self.lastValidationDate = nil
        self.isRunningHealthCheck = false
        self.latestHealthCheck = nil
        self.quickCloneDraft = .empty
        self.voiceDesignDraft = .empty
        self.activeTaskID = nil
        self.activeTaskMode = nil
        self.lastCompletedTaskID = nil

        do {
            let state = try store.loadStateOrEmpty()
            let configuration = state.configuration
            let taskHistory = state.taskHistory
            let isConfigured = !configuration.voxcpmRootPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty

            self.configuration = configuration
            self.taskHistory = taskHistory
            self.runtimeState = isConfigured
                ? .validating
                : .unconfigured
            self.statusMessage = isConfigured
                ? "VoxCPM 配置已载入，等待验证。"
                : "请先配置 VoxCPM 根目录。"
            self.errorMessage = nil
        } catch {
            self.configuration = .default
            self.taskHistory = []
            self.runtimeState = .error
            self.statusMessage = "VoxCPM 插件状态加载失败。"
            self.errorMessage = "无法读取 VoxCPM 插件配置：\(error.localizedDescription)"
        }
    }

    func updateConfiguration(_ configuration: VoxCPMPluginConfiguration) {
        self.configuration = configuration
        if persistConfiguration() {
            applyNeedsRevalidationState(for: configuration)
        }
    }

    func reloadPersistedState() {
        do {
            let state = try store.loadStateOrEmpty()
            configuration = state.configuration
            taskHistory = state.taskHistory
            applyNeedsRevalidationState(for: configuration)
        } catch {
            runtimeState = .error
            statusMessage = "重新加载 VoxCPM 配置失败。"
            errorMessage = error.localizedDescription
            latestHealthCheck = nil
            lastValidationDate = nil
            isRunningHealthCheck = false
        }
    }

    func runHealthCheck() async {
        isRunningHealthCheck = true
        runtimeState = .validating
        statusMessage = "正在验证 VoxCPM 运行环境..."
        errorMessage = nil

        defer {
            isRunningHealthCheck = false
            lastValidationDate = Date()
        }

        do {
            let result = try await runtime.healthCheck(configuration: configuration)
            latestHealthCheck = result
            runtimeState = result.response.runtimeState

            if result.response.ok {
                statusMessage = "VoxCPM 运行环境验证通过。"
                errorMessage = nil
            } else {
                statusMessage = result.response.error?.message ?? "VoxCPM 运行环境未通过验证。"
                errorMessage = formatHealthCheckIssue(from: result)
            }
        } catch {
            runtimeState = .error
            latestHealthCheck = nil
            statusMessage = "VoxCPM 运行环境验证失败。"
            errorMessage = error.localizedDescription
        }
    }

    func replaceTaskHistory(_ history: [VoxCPMTaskRecord]) {
        taskHistory = history.sorted(by: { $0.createdAt > $1.createdAt })
        persistTaskHistory()
    }

    var canRunQuickClone: Bool {
        guard runtimeState == .ready else { return false }
        guard activeTaskID == nil else { return false }
        return !quickCloneDraft.referenceAudioPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !quickCloneDraft.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRunVoiceDesign: Bool {
        guard runtimeState == .ready else { return false }
        guard activeTaskID == nil else { return false }
        return !voiceDesignDraft.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !voiceDesignDraft.designDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func chooseQuickCloneReferenceAudio() {
        let panel = NSOpenPanel()
        panel.title = "选择快速克隆参考音频"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mp3, .wav, .mpeg4Audio, .aiff]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        quickCloneDraft.referenceAudioPath = url.path
        statusMessage = "已选择参考音频：\(url.lastPathComponent)"
        errorMessage = nil
    }

    func submitQuickClone() async {
        let referenceAudioPath = quickCloneDraft.referenceAudioPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetText = quickCloneDraft.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        let controlInstruction = quickCloneDraft.controlInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !referenceAudioPath.isEmpty else {
            errorMessage = "请先选择参考音频。"
            statusMessage = "快速克隆缺少参考音频。"
            return
        }
        guard !targetText.isEmpty else {
            errorMessage = "请输入目标文本。"
            statusMessage = "快速克隆缺少目标文本。"
            return
        }
        guard runtimeState == .ready else {
            errorMessage = "请先完成 VoxCPM 运行环境验证。"
            statusMessage = "运行环境尚未就绪。"
            return
        }

        let record = VoxCPMTaskRecord(
            mode: .quickClone,
            createdAt: Date(),
            status: .running,
            inputText: targetText,
            controlInstruction: controlInstruction,
            referenceAudioPath: referenceAudioPath
        )
        beginTask(record, status: "正在提交快速克隆任务...")

        let request = VoxCPMBridgeRequestEnvelope(
            version: VoxCPMPluginRuntime.bridgeVersion,
            requestID: record.id.uuidString,
            command: .generateClone,
            arguments: [
                "voxcpm_root": .string(configuration.voxcpmRootPath),
                "output_directory": .string(resolvedOutputDirectory),
                "model_identifier": .string(configuration.modelIdentifier),
                "reference_audio_path": .string(referenceAudioPath),
                "target_text": .string(targetText),
                "control_instruction": .string(controlInstruction)
            ]
        )

        await runTask(recordID: record.id, mode: .quickClone, request: request, successMessage: "快速克隆已完成。")
    }

    func submitVoiceDesign() async {
        let targetText = voiceDesignDraft.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        let designDescription = voiceDesignDraft.designDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let controlInstruction = voiceDesignDraft.controlInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !targetText.isEmpty else {
            errorMessage = "请输入目标文本。"
            statusMessage = "声音设计缺少目标文本。"
            return
        }
        guard !designDescription.isEmpty else {
            errorMessage = "请输入声音设计描述。"
            statusMessage = "声音设计缺少描述信息。"
            return
        }
        guard runtimeState == .ready else {
            errorMessage = "请先完成 VoxCPM 运行环境验证。"
            statusMessage = "运行环境尚未就绪。"
            return
        }

        let record = VoxCPMTaskRecord(
            mode: .voiceDesign,
            createdAt: Date(),
            status: .running,
            inputText: targetText,
            controlInstruction: [designDescription, controlInstruction]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        )
        beginTask(record, status: "正在提交声音设计任务...")

        let request = VoxCPMBridgeRequestEnvelope(
            version: VoxCPMPluginRuntime.bridgeVersion,
            requestID: record.id.uuidString,
            command: .generateDesign,
            arguments: [
                "voxcpm_root": .string(configuration.voxcpmRootPath),
                "output_directory": .string(resolvedOutputDirectory),
                "model_identifier": .string(configuration.modelIdentifier),
                "target_text": .string(targetText),
                "design_description": .string(designDescription),
                "control_instruction": .string(controlInstruction)
            ]
        )

        await runTask(recordID: record.id, mode: .voiceDesign, request: request, successMessage: "声音设计已完成。")
    }

    func revealTaskOutput(_ task: VoxCPMTaskRecord) {
        guard let outputAudioPath = task.outputAudioPath, !outputAudioPath.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputAudioPath)])
    }

    func openTaskOutputFolder(_ task: VoxCPMTaskRecord) {
        guard let outputAudioPath = task.outputAudioPath, !outputAudioPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: outputAudioPath).deletingLastPathComponent())
    }

    @discardableResult
    private func persistConfiguration() -> Bool {
        do {
            try store.saveConfiguration(configuration, preservingTaskHistory: taskHistory)
            return true
        } catch {
            runtimeState = .error
            statusMessage = "保存 VoxCPM 配置失败。"
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func persistTaskHistory() {
        do {
            try store.saveTaskHistory(taskHistory, preservingConfiguration: configuration)
        } catch {
            runtimeState = .error
            statusMessage = "保存 VoxCPM 任务历史失败。"
            errorMessage = error.localizedDescription
        }
    }

    private var resolvedOutputDirectory: String {
        let configured = configuration.defaultOutputDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return configured
        }
        return VoxCPMPluginStore.defaultDirectoryURL
            .appendingPathComponent("Outputs", isDirectory: true)
            .path
    }

    private func beginTask(_ record: VoxCPMTaskRecord, status: String) {
        activeTaskID = record.id
        activeTaskMode = record.mode
        lastCompletedTaskID = nil
        errorMessage = nil
        runtimeState = .running
        statusMessage = status
        taskHistory.insert(record, at: 0)
        persistTaskHistory()
    }

    private func runTask(
        recordID: UUID,
        mode: VoxCPMTaskMode,
        request: VoxCPMBridgeRequestEnvelope,
        successMessage: String
    ) async {
        do {
            let response = try await runtime.invoke(
                request: request,
                preferredPythonCommand: configuration.pythonCommand,
                timeout: 20
            )
            applyTaskSuccess(recordID: recordID, response: response, mode: mode, successMessage: successMessage)
        } catch {
            applyTaskFailure(recordID: recordID, message: error.localizedDescription)
        }
    }

    private func applyTaskSuccess(
        recordID: UUID,
        response: VoxCPMBridgeResponseEnvelope,
        mode: VoxCPMTaskMode,
        successMessage: String
    ) {
        defer { finishActiveTask() }

        guard response.ok else {
            applyTaskFailure(recordID: recordID, message: response.error?.message ?? "任务执行失败。")
            return
        }

        if let index = taskHistory.firstIndex(where: { $0.id == recordID }) {
            taskHistory[index].status = .completed
            taskHistory[index].outputAudioPath = response.details["output_audio_path"]?.stringValue
            taskHistory[index].errorMessage = nil
            persistTaskHistory()
        }

        runtimeState = .ready
        statusMessage = successMessage
        errorMessage = nil
        lastCompletedTaskID = recordID

        switch mode {
        case .quickClone:
            quickCloneDraft.targetText = ""
            quickCloneDraft.controlInstruction = ""
        case .voiceDesign:
            voiceDesignDraft.targetText = ""
            voiceDesignDraft.designDescription = ""
            voiceDesignDraft.controlInstruction = ""
        }
    }

    private func applyTaskFailure(recordID: UUID, message: String) {
        defer { finishActiveTask() }

        if let index = taskHistory.firstIndex(where: { $0.id == recordID }) {
            taskHistory[index].status = .failed
            taskHistory[index].errorMessage = message
            persistTaskHistory()
        }

        runtimeState = .ready
        statusMessage = "VoxCPM 任务执行失败。"
        errorMessage = message
    }

    private func finishActiveTask() {
        activeTaskID = nil
        activeTaskMode = nil
    }

    private func applyNeedsRevalidationState(for configuration: VoxCPMPluginConfiguration) {
        latestHealthCheck = nil
        lastValidationDate = nil
        isRunningHealthCheck = false
        errorMessage = nil

        if configuration.voxcpmRootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runtimeState = .unconfigured
            statusMessage = "请先配置 VoxCPM 根目录。"
        } else {
            runtimeState = .validating
            statusMessage = "VoxCPM 配置已更新，等待重新验证。"
        }
    }

    private func formatHealthCheckIssue(from result: VoxCPMHealthCheckResult) -> String {
        let missingFiles = result.requiredFiles
            .filter { !$0.value.exists }
            .map(\.key)
            .sorted()

        if !result.rootExists {
            return "目录不存在：\(result.voxcpmRoot)"
        }

        if missingFiles.isEmpty {
            return result.response.error?.message ?? "VoxCPM 运行环境未通过验证。"
        }

        return "缺少必要文件：\(missingFiles.joined(separator: ", "))"
    }
}
