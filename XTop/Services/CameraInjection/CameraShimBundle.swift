import Foundation

/// Resolves the absolute path to the bundled `XTopCameraShim.dylib` inside the
/// macOS app bundle's `Contents/Resources/`. The shim is built by
/// `script/build_camera_shim.sh` as a universal `arm64 + x86_64` iOS-simulator
/// dylib and copied into Resources before xcodebuild runs.
enum CameraShimBundle {
    enum ShimError: Error, LocalizedError {
        case notBundled
        case notReadable(URL)

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "XTopCameraShim.dylib is not bundled inside the app. Run script/build_camera_shim.sh."
            case let .notReadable(url):
                return "XTopCameraShim.dylib at \(url.path) is not readable."
            }
        }
    }

    static let resourceName = "XTopCameraShim"
    /// The shim is shipped with a `.bin` extension so the macOS app target's
    /// synchronized file group does not try to link it (it is an iOS-simulator
    /// dylib and would fail the host link step). simctl's
    /// `DYLD_INSERT_LIBRARIES` accepts any path regardless of extension.
    static let resourceExtension = "bin"

    /// Returns the on-disk URL of the bundled shim or throws if missing.
    ///
    /// The simulator process is the user-level macOS process, so any path
    /// under `Contents/Resources/` is readable as long as it exists.
    static func resolvedURL() throws -> URL {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension
        ) else { throw ShimError.notBundled }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ShimError.notReadable(url)
        }
        return url
    }

    /// Lightweight existence probe that does not throw — useful for UI state.
    static func isAvailable() -> Bool {
        (try? resolvedURL()) != nil
    }
}
