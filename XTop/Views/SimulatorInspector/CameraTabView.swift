import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Camera" tab in the Simulator Inspector. Allows the developer to pick a
/// frame source, inject the shim into the selected installed app, and
/// monitor the live transport state.
struct CameraTabView: View {
    @Environment(SimulatorInspectorViewModel.self) private var inspector
    @State private var viewModel: CameraInjectionViewModel

    init(viewModel: CameraInjectionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            if inspector.simulators.isEmpty {
                noSimulatorEmptyState
            } else {
                shimAvailabilityRow

                sourcePicker
                    .padding(.top, DesignSystem.Spacing.sm)

                sourceConfigRow

                actionRow

                statusRow

                disclosure
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .onAppear {
            viewModel.startObservingTransport()
            if let udid = inspector.selectedSimulatorID,
               let bundleID = inspector.selectedBundleIdentifier {
                viewModel.loadPreference(udid: udid, bundleID: bundleID)
            }
        }
        .onChange(of: inspector.selectedSimulatorID) { _, _ in reloadPreference() }
        .onChange(of: inspector.selectedBundleIdentifier) { _, _ in reloadPreference() }
        .onDisappear {
            viewModel.stopObservingTransport()
            Task { await viewModel.stop() }
        }
    }

    private var noSimulatorEmptyState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label("No booted simulator", systemImage: "iphone.slash")
                .font(.headline)
            Text("Boot a simulator from Xcode or `xcrun simctl boot <udid>`, then return to this tab. Camera injection requires a running iOS simulator to target.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.rowHover)
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.row))
    }

    private func reloadPreference() {
        guard let udid = inspector.selectedSimulatorID,
              let bundleID = inspector.selectedBundleIdentifier else { return }
        viewModel.loadPreference(udid: udid, bundleID: bundleID)
    }

    @ViewBuilder
    private var shimAvailabilityRow: some View {
        if !CameraShimBundle.isAvailable() {
            Label(
                "XTopCameraShim.bin is missing from the app bundle. Run script/build_camera_shim.sh.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(DesignSystem.Colors.destructive)
            .padding(DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.destructive.opacity(0.08))
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.row))
        }
    }

    private var sourcePicker: some View {
        Picker("Frame source", selection: $viewModel.selectedKind) {
            ForEach(CameraSourceKind.allCases) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var sourceConfigRow: some View {
        switch viewModel.selectedKind {
        case .videoFile:
            HStack {
                Text(viewModel.videoFileURL?.lastPathComponent ?? "No file selected")
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                Button("Choose Video…") { pickVideoFile() }
            }
        case .testPattern:
            Text("Generates a 640×480 SMPTE-style pattern at 30 fps. No permissions required.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        case .webcam:
            Text("Captures from the default Mac camera. Requests camera permission on first use.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        case .screenRegion:
            Text("Captures the main display via ScreenCaptureKit. Requests Screen Recording permission on first use.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
    }

    private var actionRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button {
                Task { await injectTapped() }
            } label: {
                Label("Inject & Launch", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(injectDisabled)

            Button {
                Task { await viewModel.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!viewModel.transportState.isConnected && !inProgress)

            Spacer()

            Button {
                copySnippet()
            } label: {
                Label("Copy scheme snippet", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.transportState.port == nil)

            Button {
                copyLogCommand()
            } label: {
                Label("Copy log command", systemImage: "text.viewfinder")
            }
            .help("Copies a shell command that streams the shim's hook logs from the booted simulator.")
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            statusLine("App", value: inspector.selectedBundleIdentifier ?? "—")
            statusLine("Simulator", value: inspector.selectedSimulatorID ?? "—")
            statusLine("Transport", value: stateLabel(viewModel.transportState))
            if let pid = viewModel.activePID {
                statusLine("PID", value: String(pid))
            }
            if let error = viewModel.lastError {
                Text(error)
                    .foregroundStyle(DesignSystem.Colors.destructive)
                    .font(DesignSystem.Typography.rowSecondary)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.rowHover)
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.row))
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Frames stay on this Mac: the shim connects to 127.0.0.1, authenticates with a per-launch random token, and only one client is accepted per session.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text("If the simulator shows a grey screen after Connected, the app likely uses no AVCaptureDevice at all (a real iOS-only path) or holds the preview in a custom Metal/SceneKit view we cannot intercept. AVCaptureVideoPreviewLayer and AVCaptureVideoDataOutput-based UIs are supported.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
        }
    }

    // MARK: - Helpers

    private var injectDisabled: Bool {
        inspector.selectedSimulatorID == nil
            || inspector.selectedBundleIdentifier == nil
            || !CameraShimBundle.isAvailable()
    }

    private var inProgress: Bool {
        switch viewModel.phase {
        case .preparing, .awaitingClient, .running, .stopping: return true
        default: return false
        }
    }

    private func injectTapped() async {
        guard let udid = inspector.selectedSimulatorID,
              let bundleID = inspector.selectedBundleIdentifier else { return }
        await viewModel.injectAndLaunch(bundleID: bundleID, udid: udid)
    }

    private func pickVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.movie, UTType.mpeg4Movie, UTType.quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            viewModel.videoFileURL = panel.url
        }
    }

    private func copySnippet() {
        Task {
            let snippet = await viewModel.xcodeSchemeSnippet()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(snippet, forType: .string)
        }
    }

    private func copyLogCommand() {
        let command = #"xcrun simctl spawn booted log stream --predicate 'subsystem == "com.vishwakarma.XTop.shim"' --level debug"#
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func statusLine(_ label: String, value: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(label)
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(DesignSystem.Typography.monoCaption)
                .textSelection(.enabled)
        }
    }

    private func stateLabel(_ state: CameraTransportState) -> String {
        switch state {
        case .stopped: return "stopped"
        case let .listening(p): return "listening on :\(p)"
        case let .connected(p, _): return "connected on :\(p)"
        case let .streaming(p, _): return "streaming on :\(p)"
        case let .failed(reason): return "failed: \(reason)"
        }
    }
}
