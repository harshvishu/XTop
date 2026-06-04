import AppKit
import SwiftUI

/// Interactive empty state shown when no iOS Simulator is currently booted.
///
/// The illustration consists of a stylized phone that tilts to follow the
/// pointer, a soft pulsing aura behind it, and primary/secondary actions for
/// launching `Simulator.app` or re-checking for booted devices.
struct SimulatorInspectorEmptyStateView: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel
    @State private var pointer: CGPoint? = nil
    @State private var canvasSize: CGSize = .zero
    @State private var isRefreshing = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        DesignSystem.Colors.accent.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.xl) {
                    PhoneIllustration(
                        tilt: tiltVector,
                        isLoading: viewModel.isRefreshingSimulators
                    )
                    .frame(width: 220, height: 360)

                    copyBlock

                    actionRow
                }
                .padding(DesignSystem.Spacing.xl)
                .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    pointer = location
                case .ended:
                    pointer = nil
                }
            }
            .onAppear { canvasSize = proxy.size }
            .onChange(of: proxy.size) { _, newValue in canvasSize = newValue }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var copyBlock: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text("No simulator is booted")
                .font(DesignSystem.Typography.title)
                .foregroundStyle(DesignSystem.Colors.primaryText)

            Text("Boot an iOS Simulator from Xcode or launch Simulator.app, then come back here to inspect UserDefaults, app groups, keychains, and overlay grids.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button("Open Simulator", systemImage: "iphone.gen3", action: openSimulatorApp)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Button {
                refresh()
            } label: {
                if isRefreshing || viewModel.isRefreshingSimulators {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isRefreshing || viewModel.isRefreshingSimulators)
        }
    }

    // MARK: Helpers

    /// Normalized pointer offset from the center of the visible area, in
    /// the range `-1...1` on each axis. Returns `.zero` when the pointer has
    /// left the view so the phone eases back to rest.
    private var tiltVector: CGSize {
        guard let pointer, canvasSize.width > 0, canvasSize.height > 0 else {
            return .zero
        }
        let dx = (pointer.x - canvasSize.width / 2) / (canvasSize.width / 2)
        let dy = (pointer.y - canvasSize.height / 2) / (canvasSize.height / 2)
        return CGSize(width: max(-1, min(1, dx)), height: max(-1, min(1, dy)))
    }

    private func openSimulatorApp() {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") {
            let config = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await viewModel.refreshSimulators()
            isRefreshing = false
        }
    }
}

// MARK: - Illustration

private struct PhoneIllustration: View {
    let tilt: CGSize
    let isLoading: Bool

    var body: some View {
        ZStack {
            PulsingAura()
                .blendMode(.plusLighter)

            ZStack {
                PhoneBody()
                PhoneScreen(isLoading: isLoading)
                    .padding(12)
            }
            .rotation3DEffect(
                .degrees(Double(-tilt.height) * 10),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.6
            )
            .rotation3DEffect(
                .degrees(Double(tilt.width) * 14),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
            .shadow(color: DesignSystem.Colors.accent.opacity(0.18), radius: 24, x: 0, y: 12)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: tilt)
        }
    }
}

private struct PhoneBody: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.16),
                            Color.primary.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.stroke, lineWidth: 1)
                }

            // Side hardware buttons.
            HStack {
                VStack(spacing: 14) {
                    sideButton(width: 3, height: 18)
                    sideButton(width: 3, height: 30)
                    sideButton(width: 3, height: 30)
                }
                Spacer()
                VStack {
                    sideButton(width: 3, height: 48)
                }
            }
            .padding(.vertical, 80)
            .padding(.horizontal, -2)
        }
    }

    private func sideButton(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.18))
            .frame(width: width, height: height)
    }
}

private struct PhoneScreen: View {
    let isLoading: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.85))

            // Dynamic Island.
            Capsule()
                .fill(Color.black)
                .frame(width: 70, height: 22)
                .offset(y: -148)

            VStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: isLoading ? "circle.dotted" : "powersleep")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(DesignSystem.Colors.accent.opacity(0.85))
                    .symbolEffect(.pulse, options: .repeating, isActive: isLoading)

                Text(isLoading ? "Looking for simulators…" : "Awaiting boot")
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(Color.white.opacity(0.7))

                HeartbeatDots()
            }
            .padding(.top, 24)
        }
    }
}

private struct HeartbeatDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = time * 2.4 - Double(index) * 0.4
                    let scale = 0.6 + 0.4 * max(0, sin(phase))
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.7))
                        .frame(width: 8, height: 8)
                        .scaleEffect(scale)
                        .opacity(0.4 + 0.6 * scale)
                }
            }
        }
        .frame(height: 12)
    }
}

private struct PulsingAura: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let phase = (time * 0.7 + Double(ring) * 0.7).truncatingRemainder(dividingBy: 2.0)
                    let progress = phase / 2.0
                    Circle()
                        .stroke(
                            DesignSystem.Colors.accent.opacity(0.35 * (1.0 - progress)),
                            lineWidth: 1.5
                        )
                        .scaleEffect(0.6 + progress * 0.9)
                }
            }
            .frame(width: 320, height: 320)
        }
        .allowsHitTesting(false)
    }
}

