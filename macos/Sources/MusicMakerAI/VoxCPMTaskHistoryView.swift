import SwiftUI
import AppKit

struct VoxCPMTaskHistoryView: View {
    @EnvironmentObject private var viewModel: VoxCPMPluginViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("任务历史", systemImage: "tray.full")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(viewModel.taskHistory.count) 条记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if viewModel.taskHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("还没有 VoxCPM 任务")
                        .font(.headline)
                    Text("完成一次快速克隆或声音设计后，这里会展示提交记录、状态和输出文件操作。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.taskHistory) { task in
                        VoxCPMTaskHistoryRow(task: task)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct VoxCPMTaskHistoryRow: View {
    let task: VoxCPMTaskRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(task.mode.title, systemImage: task.mode == .quickClone ? "hare" : "dial.high")
                    .font(.headline)
                Spacer()
                Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(statusText(task.status))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.background.opacity(0.7), in: Capsule())

                if let outputAudioPath = task.outputAudioPath, !outputAudioPath.isEmpty {
                    Text(outputAudioPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !task.inputText.isEmpty {
                Text(task.inputText)
                    .font(.callout)
                    .lineLimit(3)
            }

            if let errorMessage = task.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let outputAudioPath = task.outputAudioPath, !outputAudioPath.isEmpty {
                HStack(spacing: 10) {
                    Button("打开文件夹") {
                        openFolder(outputAudioPath)
                    }
                    .buttonStyle(.bordered)

                    Button("定位文件") {
                        revealFile(outputAudioPath)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusText(_ status: VoxCPMTaskStatus) -> String {
        switch status {
        case .idle:
            return "未开始"
        case .queued:
            return "排队中"
        case .preparing:
            return "准备中"
        case .running:
            return "运行中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        }
    }

    private func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path).deletingLastPathComponent())
    }

    private func revealFile(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
