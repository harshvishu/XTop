import Foundation

actor GitMonitorScheduler {
    private let monitorService: GitMonitorService
    private var refreshTask: Task<Void, Never>?

    init(monitorService: GitMonitorService) {
        self.monitorService = monitorService
    }

    func start(
        interval: Duration,
        onSnapshots: @escaping @Sendable ([GitRepositorySnapshot]) -> Void
    ) {
        stop()

        refreshTask = Task { [monitorService] in
            while !Task.isCancelled {
                let snapshots = await monitorService.refreshAllActiveRepositories()
                if Task.isCancelled {
                    break
                }
                onSnapshots(snapshots)

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
