import Foundation

/// Minimal lifecycle surface that `CameraInjectionCoordinator` needs from
/// `AppLifecycleController`. Carved into a protocol so tests can substitute
/// an in-memory fake without standing up `xcrun simctl`.
protocol SimulatorAppLauncher: Sendable {
    func terminate(bundleIdentifier: String, on udid: String) async throws
    @discardableResult
    func launch(
        bundleIdentifier: String,
        on udid: String,
        childEnvironment: [String: String]
    ) async throws -> Int32?
}

extension AppLifecycleController: SimulatorAppLauncher {}
