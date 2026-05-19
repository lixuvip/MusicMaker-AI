import SwiftUI

struct VoxCPMQuickCloneView: View {
    @EnvironmentObject private var viewModel: VoxCPMPluginViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("快速克隆")
                        .font(.title3.weight(.semibold))
                    Text("选择参考音频，输入目标文本，再补充可选控制语句即可发起首个原生 VoxCPM 克隆任务。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        await viewModel.submitQuickClone()
                    }
                } label: {
                    if viewModel.activeTaskMode == .quickClone {
                        Label("生成中...", systemImage: "waveform")
                    } else {
                        Label("开始快速克隆", systemImage: "hare")
                    }
                }
                .disabled(!viewModel.canRunQuickClone)
            }

            Form {
                Section("参考音频") {
                    HStack(spacing: 10) {
                        TextField(
                            "选择参考音频文件",
                            text: Binding(
                                get: { viewModel.quickCloneDraft.referenceAudioPath },
                                set: { viewModel.quickCloneDraft.referenceAudioPath = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        Button("浏览...") {
                            viewModel.chooseQuickCloneReferenceAudio()
                        }
                    }

                    if !viewModel.quickCloneDraft.referenceAudioPath.isEmpty {
                        Text(viewModel.quickCloneDraft.referenceAudioPath)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("文本与控制") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("目标文本")
                            .font(.subheadline.weight(.medium))
                        TextEditor(
                            text: Binding(
                                get: { viewModel.quickCloneDraft.targetText },
                                set: { viewModel.quickCloneDraft.targetText = $0 }
                            )
                        )
                        .font(.body)
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("控制语句（可选）")
                            .font(.subheadline.weight(.medium))
                        TextEditor(
                            text: Binding(
                                get: { viewModel.quickCloneDraft.controlInstruction },
                                set: { viewModel.quickCloneDraft.controlInstruction = $0 }
                            )
                        )
                        .font(.body)
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                    }
                }

                Section("提交说明") {
                    LabeledContent("输出目录", value: resolvedOutputPathText)
                    Text("MVP 会通过桥接层生成可回放的输出音频，并将任务记录写入 VoxCPM 插件历史。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var resolvedOutputPathText: String {
        let configured = viewModel.configuration.defaultOutputDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return configured
        }
        return VoxCPMPluginStore.defaultDirectoryURL
            .appendingPathComponent("Outputs", isDirectory: true)
            .path
    }
}
