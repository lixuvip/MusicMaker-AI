import SwiftUI

private enum VoiceCloningSection: String, CaseIterable, Identifiable {
    case quickClone
    case voiceDesign
    case taskHistory
    case pluginSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickClone:
            return "快速克隆"
        case .voiceDesign:
            return "声音设计"
        case .taskHistory:
            return "任务历史"
        case .pluginSettings:
            return "插件设置"
        }
    }

    var subtitle: String {
        switch self {
        case .quickClone:
            return "从参考音频进入最短路径的克隆流程。"
        case .voiceDesign:
            return "面向描述词和控制指令的声音设计入口。"
        case .taskHistory:
            return "查看 VoxCPM 插件任务与最近结果。"
        case .pluginSettings:
            return "配置运行环境、模型和输出目录。"
        }
    }

    var systemImage: String {
        switch self {
        case .quickClone:
            return "hare"
        case .voiceDesign:
            return "slider.horizontal.3"
        case .taskHistory:
            return "clock.arrow.circlepath"
        case .pluginSettings:
            return "gearshape.2"
        }
    }
}

struct VoiceCloningModule: View {
    @State private var selectedSection: VoiceCloningSection = .quickClone

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VoiceCloningHeader()

                Picker("声音克隆模块导航", selection: $selectedSection) {
                    ForEach(VoiceCloningSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                VoiceCloningSectionStrip(selectedSection: $selectedSection)

                Group {
                    switch selectedSection {
                    case .quickClone:
                        VoxCPMQuickCloneView()
                    case .voiceDesign:
                        VoxCPMVoiceDesignView()
                    case .taskHistory:
                        VoxCPMTaskHistoryView()
                    case .pluginSettings:
                        VoxCPMPluginSettingsView()
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("声音克隆")
    }
}

private struct VoiceCloningHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("声音克隆")
                .font(.largeTitle.weight(.semibold))
            Text("VoxCPM 模块现在会通过本地桥接层调用外部 VoxCPM 工程，可直接提交快速克隆、声音设计任务并回写历史。")
                .foregroundStyle(.secondary)
        }
    }
}

private struct VoiceCloningSectionStrip: View {
    @Binding var selectedSection: VoiceCloningSection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(VoiceCloningSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.headline)
                        Text(section.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(background(for: section), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func background(for section: VoiceCloningSection) -> some ShapeStyle {
        if selectedSection == section {
            return AnyShapeStyle(.tint.opacity(0.16))
        }
        return AnyShapeStyle(.quaternary.opacity(0.22))
    }
}
