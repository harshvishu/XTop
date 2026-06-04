import CoreGraphics
import Foundation

/// Identifies a simulator for window-matching purposes. Carries both the
/// stable UDID (used as the persistence key) and the user-facing device name
/// (used to match the Simulator.app AX window title).
struct SimulatorIdentity: Hashable, Sendable {
    let udid: String
    let displayName: String

    init(udid: String, displayName: String) {
        self.udid = udid
        self.displayName = displayName
    }

    init(device: SimulatorDevice) {
        self.udid = device.udid
        self.displayName = device.name
    }
}

/// Selectable mode for a single grid axis.
enum GridAxisMode: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case uniform
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uniform: return "Uniform"
        case .custom: return "Custom"
        }
    }
}

/// Per-axis grid specification. `uniform` is sugar over `custom`: the
/// renderer always resolves a `[CGFloat]` of cumulative line offsets.
struct GridAxisSpec: Codable, Hashable, Sendable {
    var mode: GridAxisMode
    var uniformSpacing: CGFloat
    var customOffsets: [CGFloat]

    init(
        mode: GridAxisMode = .uniform,
        uniformSpacing: CGFloat = 8,
        customOffsets: [CGFloat] = []
    ) {
        self.mode = mode
        self.uniformSpacing = uniformSpacing
        self.customOffsets = customOffsets
    }

    /// Resolves the spec to a list of line positions (in points) from the
    /// leading/top edge, given the dimension to fill. Lines outside `0..<dimension`
    /// are clipped. Uniform spacing is expanded by repeating `uniformSpacing`
    /// cumulatively until the dimension is reached.
    func resolvedLinePositions(filling dimension: CGFloat) -> [CGFloat] {
        guard dimension > 0 else { return [] }
        switch mode {
        case .uniform:
            guard uniformSpacing > 0 else { return [] }
            var positions: [CGFloat] = []
            var x = uniformSpacing
            // Safety cap to avoid runaway loops on absurd inputs.
            let cap = max(1024, Int((dimension / max(uniformSpacing, 0.5)).rounded(.up)) + 8)
            while x < dimension && positions.count < cap {
                positions.append(x)
                x += uniformSpacing
            }
            return positions
        case .custom:
            var positions: [CGFloat] = []
            var cursor: CGFloat = 0
            for gap in customOffsets {
                guard gap > 0 else { continue }
                cursor += gap
                if cursor >= dimension { break }
                positions.append(cursor)
            }
            return positions
        }
    }
}

/// Complete per-simulator grid overlay configuration.
struct GridOverlayConfig: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var opacity: Double
    var horizontal: GridAxisSpec
    var vertical: GridAxisSpec

    static let defaultOpacity: Double = 0.3
    static let minOpacity: Double = 0.1
    static let maxOpacity: Double = 0.8

    init(
        isEnabled: Bool = false,
        opacity: Double = GridOverlayConfig.defaultOpacity,
        horizontal: GridAxisSpec = GridAxisSpec(),
        vertical: GridAxisSpec = GridAxisSpec()
    ) {
        self.isEnabled = isEnabled
        self.opacity = opacity.clamped(to: GridOverlayConfig.minOpacity ... GridOverlayConfig.maxOpacity)
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// Defaults for a UDID that has no persisted configuration yet:
    /// disabled, 8 pt uniform on both axes, 30% opacity.
    static let `default` = GridOverlayConfig()
}

/// Typed error surfaced by ``GridOffsetsParser``.
enum GridOffsetsParseError: Error, Equatable, Sendable {
    case empty
    case invalidToken(String)
    case nonPositive(Double)
}

/// Parses a comma-separated list of positive point values such as
/// `"8, 8, 4, 4"` into `[CGFloat]`. Whitespace is tolerated.
/// Empty entries and non-positive / non-numeric values produce a typed error.
enum GridOffsetsParser {
    static func parse(_ input: String) -> Result<[CGFloat], GridOffsetsParseError> {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        let rawTokens = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        var values: [CGFloat] = []
        values.reserveCapacity(rawTokens.count)
        for rawToken in rawTokens {
            let token = rawToken.trimmingCharacters(in: .whitespaces)
            if token.isEmpty {
                return .failure(.invalidToken(String(rawToken)))
            }
            guard let parsed = Double(token) else {
                return .failure(.invalidToken(token))
            }
            guard parsed > 0 else {
                return .failure(.nonPositive(parsed))
            }
            values.append(CGFloat(parsed))
        }
        guard !values.isEmpty else { return .failure(.empty) }
        return .success(values)
    }

    /// Renders an offset list back to a canonical `"8, 8, 4, 4"` representation
    /// for display in text fields.
    static func format(_ offsets: [CGFloat]) -> String {
        offsets
            .map { value -> String in
                if value == value.rounded() {
                    return String(Int(value))
                }
                return String(format: "%g", Double(value))
            }
            .joined(separator: ", ")
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
