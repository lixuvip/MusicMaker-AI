import Foundation

struct VoxCPMPluginStore {
    let stateURL: URL

    init(stateURL: URL = VoxCPMPluginStore.defaultStateURL) {
        self.stateURL = stateURL
    }

    static var defaultDirectoryURL: URL {
        let musicDirectory = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return musicDirectory
            .appendingPathComponent("MusicMaker-AI", isDirectory: true)
            .appendingPathComponent("VoxCPMPlugin", isDirectory: true)
    }

    static var defaultStateURL: URL {
        defaultDirectoryURL.appendingPathComponent(VoxCPMPluginPersistedState.persistenceFilename)
    }

    func loadState() throws -> VoxCPMPluginPersistedState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: stateURL)
        let state = try JSONDecoder.history.decode(VoxCPMPluginPersistedState.self, from: data)
        return normalized(state)
    }

    func saveState(_ state: VoxCPMPluginPersistedState) throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.history.encode(normalized(state))
        try data.write(to: stateURL, options: .atomic)
    }

    func loadStateOrEmpty() throws -> VoxCPMPluginPersistedState {
        try loadState() ?? .empty
    }

    func loadConfiguration() throws -> VoxCPMPluginConfiguration? {
        try loadState()?.configuration
    }

    func loadTaskHistory() throws -> [VoxCPMTaskRecord]? {
        try loadState()?.taskHistory
    }

    func saveConfiguration(
        _ configuration: VoxCPMPluginConfiguration,
        preservingTaskHistory taskHistory: [VoxCPMTaskRecord] = []
    ) throws {
        let existingTaskHistory = try loadState()?.taskHistory ?? taskHistory
        try saveState(
            VoxCPMPluginPersistedState(
                configuration: configuration,
                taskHistory: existingTaskHistory
            )
        )
    }

    func saveTaskHistory(
        _ taskHistory: [VoxCPMTaskRecord],
        preservingConfiguration configuration: VoxCPMPluginConfiguration = .default
    ) throws {
        let existingConfiguration = try loadState()?.configuration ?? configuration
        try saveState(
            VoxCPMPluginPersistedState(
                configuration: existingConfiguration,
                taskHistory: taskHistory
            )
        )
    }

    private func normalized(_ state: VoxCPMPluginPersistedState) -> VoxCPMPluginPersistedState {
        VoxCPMPluginPersistedState(
            configuration: state.configuration,
            taskHistory: state.taskHistory.sorted(by: { $0.createdAt > $1.createdAt })
        )
    }
}
