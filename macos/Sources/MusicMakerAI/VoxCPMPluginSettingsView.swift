import SwiftUI

struct VoxCPMPluginSettingsView: View {
    @EnvironmentObject private var viewModel: VoxCPMPluginViewModel
    @State private var draftConfiguration = VoxCPMPluginConfiguration.default

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("插件设置")
                        .font(.title3.weight(.semibold))
                    Text("管理 VoxCPM 根目录、Python 命令、模型标识与默认输出路径，并随时验证当前运行环境。")
                        .foregroundStyle(.secondary)
                    if hasUnsavedChanges {
                        Text("你有未保存的配置更改，保存后再运行健康检查。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    Button("保存配置") {
                        viewModel.updateConfiguration(draftConfiguration)
                    }
                    .disabled(!hasUnsavedChanges || viewModel.isRunningHealthCheck)

                    Button {
                        Task {
                            await viewModel.runHealthCheck()
                        }
                    } label: {
                        if viewModel.isRunningHealthCheck {
                            Label("检查中...", systemImage: "hourglass")
                        } else {
                            Label("运行健康检查", systemImage: "checkmark.seal")
                        }
                    }
                    .disabled(viewModel.isRunningHealthCheck || hasUnsavedChanges)
                }
            }

            Form {
                Section("运行环境") {
                    TextField("VoxCPM 根目录", text: binding(\.voxcpmRootPath))
                        .textFieldStyle(.roundedBorder)
                    TextField("Python 命令", text: binding(\.pythonCommand))
                        .textFieldStyle(.roundedBorder)
                    TextField("模型标识", text: binding(\.modelIdentifier))
                        .textFieldStyle(.roundedBorder)
                    TextField("默认输出目录", text: binding(\.defaultOutputDirectory))
                        .textFieldStyle(.roundedBorder)
                }

                Section("当前状态") {
                    LabeledContent("运行时状态", value: runtimeStateText(viewModel.runtimeState))
                    LabeledContent("状态说明", value: viewModel.statusMessage)

                    if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("错误信息")
                                .font(.subheadline.weight(.medium))
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }

                    if let lastValidationDate = viewModel.lastValidationDate {
                        LabeledContent(
                            "上次验证",
                            value: lastValidationDate.formatted(date: .abbreviated, time: .standard)
                        )
                    }
                }

                if let latestHealthCheck = viewModel.latestHealthCheck {
                    Section("最近检查") {
                        LabeledContent(
                            "根目录存在",
                            value: latestHealthCheck.rootExists ? "是" : "否"
                        )

                        ForEach(latestHealthCheck.requiredFiles.keys.sorted(), id: \.self) { key in
                            if let status = latestHealthCheck.requiredFiles[key] {
                                LabeledContent(
                                    key,
                                    value: status.exists ? "已找到" : "缺失"
                                )
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            draftConfiguration = viewModel.configuration
        }
        .onReceive(viewModel.$configuration) { newValue in
            draftConfiguration = newValue
        }
    }

    private func binding(_ keyPath: WritableKeyPath<VoxCPMPluginConfiguration, String>) -> Binding<String> {
        Binding(
            get: {
                draftConfiguration[keyPath: keyPath]
            },
            set: { newValue in
                draftConfiguration[keyPath: keyPath] = newValue
            }
        )
    }

    private var hasUnsavedChanges: Bool {
        draftConfiguration != viewModel.configuration
    }

    private func runtimeStateText(_ state: VoxCPMRuntimeState) -> String {
        switch state {
        case .unconfigured:
            return "未配置"
        case .validating:
            return "待验证"
        case .ready:
            return "已就绪"
        case .starting:
            return "启动中"
        case .running:
            return "运行中"
        case .stopping:
            return "停止中"
        case .error:
            return "异常"
        }
    }
}
