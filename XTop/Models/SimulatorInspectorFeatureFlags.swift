import Foundation

/// Feature flags that gate work-in-progress Simulator Inspector surfaces.
///
/// Stored under XTop's standard `UserDefaults` so QA can flip them via
/// `defaults write com.vishwakarma.XTop` without rebuilding.
@MainActor
struct SimulatorInspectorFeatureFlags {
    private static let cameraInjectionKey = "SimulatorInspector.cameraInjectionEnabled"

    /// Camera injection tab visibility. Default `false` until end-to-end QA
    /// against ≥3 real third-party apps has been signed off (see task 10.4).
    static var cameraInjectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: cameraInjectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: cameraInjectionKey) }
    }
}
