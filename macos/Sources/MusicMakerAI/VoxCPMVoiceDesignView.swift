import SwiftUI

struct VoxCPMVoiceDesignView: View {
    @EnvironmentObject private var viewModel: VoxCPMPluginViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("声音设计")
                        .font(.title3.weight(.semibold))
                    Text("围绕目标文本和设计描述组织第一版原生声音设计工作流，适合快速验证描述词与控制指令。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        await viewModel.submitVoiceDesign()
                    }
                } label: {
                    if viewModel.activeTaskMode == .voiceDesign {
                        Label("生成中...", systemImage: "dial.high")
                    } else {
                        Label("开始声音设计", systemImage: "slider.horizontal.3")
                    }
                }
                .disabled(!viewModel.canRunVoiceDesign)
            }

            Form {
                Section("核心输入") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("目标文本")
                            .font(.subheadline.weight(.medium))
                        TextEditor(
                            text: Binding(
                                get: { viewModel.voiceDesignDraft.targetText },
                                set: { viewModel.voiceDesignDraft.targetText = $0 }
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
                        Text("设计描述")
                            .font(.subheadline.weight(.medium))
                        TextEditor(
                            text: Binding(
                                get: { viewModel.voiceDesignDraft.designDescription },
                                set: { viewModel.voiceDesignDraft.designDescription = $0 }
                            )
                        )
                        .font(.body)
                        .frame(minHeight: 100)
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
                                get: { viewModel.voiceDesignDraft.controlInstruction },
                                set: { viewModel.voiceDesignDraft.controlInstruction = $0 }
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
                    LabeledContent("模型", value: viewModel.configuration.modelIdentifier)
                    Text("MVP 会将设计描述和控制语句一起提交给桥接层，并把输出音频路径写回任务历史。")
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
}
