import AppKit
import SwiftUI

struct SimulatorInspectorRootView: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel
    @Environment(CameraInjectionViewModel.self) private var cameraViewModel
    @AppStorage("SimulatorInspector.cameraInjectionEnabled") private var cameraInjectionEnabled = false
    @State private var selectedTab: InspectorTab = .userDefaults

    var body: some View {
        Group {
            if viewModel.bookmarkStore.hasAccess {
                NavigationSplitView {
                    SimulatorListSidebar()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
                } content: {
                    InstalledAppListView()
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
                } detail: {
                    detail
                }
                .toolbar {
                    inspectorToolbar
                }
            } else {
                AccessOnboardingView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .task {
            viewModel.startPeriodicRefresh()
        }
        .onDisappear {
            viewModel.stopPeriodicRefresh()
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            InspectorBanners()
            Picker("Inspector", selection: $selectedTab) {
                ForEach(visibleTabs) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, DesignSystem.Spacing.sm)

            Divider()

            switch selectedTab {
            case .userDefaults:
                UserDefaultsTabView()
            case .appGroups:
                AppGroupsTabView()
            case .camera:
                CameraTabView(viewModel: cameraViewModel)
            case .keychain:
                KeychainTabView()
            }
        }
    }

    private var visibleTabs: [InspectorTab] {
        InspectorTab.allCases.filter { tab in
            switch tab {
            case .camera: return cameraInjectionEnabled
            default: return true
            }
        }
    }

    @ToolbarContentBuilder
    private var inspectorToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Toggle(isOn: $cameraInjectionEnabled) {
                Label("Camera Injection", systemImage: "camera.viewfinder")
            }
            .toggleStyle(.button)
            .help("Enable the Camera tab to stream Mac-side frames into iOS simulator apps (experimental).")

            Button {
                Task { await viewModel.relaunchSelectedApp() }
            } label: {
                Label("Relaunch App", systemImage: "airplane.departure")
            }
            .disabled(viewModel.selectedBundleIdentifier == nil)
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case userDefaults
    case appGroups
    case camera
    case keychain

    var id: String { rawValue }
    var title: String {
        switch self {
        case .userDefaults: return "UserDefaults"
        case .appGroups: return "App Groups"
        case .camera: return "Camera"
        case .keychain: return "Keychain"
        }
    }
}

private struct InspectorBanners: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            if let error = viewModel.lastError {
                bannerRow(
                    icon: "exclamationmark.triangle.fill",
                    text: error,
                    foreground: DesignSystem.Colors.destructive,
                    background: DesignSystem.Colors.destructive.opacity(0.08),
                    onDismiss: viewModel.dismissError
                )
            }
            if viewModel.isTargetAppRunning {
                bannerRow(
                    icon: "play.circle.fill",
                    text: "The selected app is running. Writes may be overwritten — terminate or relaunch the app to apply edits.",
                    foreground: .orange,
                    background: DesignSystem.Colors.warningBackground,
                    onDismiss: nil
                )
            }
            if viewModel.pendingRelaunchSuggestion {
                RelaunchPill()
            } else if let info = viewModel.lastInfo {
                bannerRow(
                    icon: "checkmark.circle.fill",
                    text: info,
                    foreground: .green,
                    background: Color.green.opacity(0.08),
                    onDismiss: viewModel.dismissInfo
                )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.sm)
    }

    private func bannerRow(
        icon: String,
        text: String,
        foreground: Color,
        background: Color,
        onDismiss: (() -> Void)?
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(foreground)
            Text(text)
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .background(background)
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.row))
    }
}

private struct RelaunchPill: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel
    @State private var isRelaunching = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "paperplane.fill")
                .foregroundStyle(DesignSystem.Colors.accent)
            Text("Edits queued — relaunch the app to apply.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                relaunch()
            } label: {
                if isRelaunching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Relaunch")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isRelaunching)

            Button {
                viewModel.dismissRelaunchSuggestion()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.accent.opacity(0.08))
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.row))
    }

    private func relaunch() {
        guard !isRelaunching else { return }
        isRelaunching = true
        Task {
            await viewModel.relaunchSelectedApp()
            isRelaunching = false
        }
    }
}

private struct AccessOnboardingView: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel
    @State private var pickerError: String?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(DesignSystem.Colors.accent)
            Text("Grant Simulator Access")
                .font(DesignSystem.Typography.title)
            Text("XTop needs one-time access to the CoreSimulator folder to read installed apps and edit UserDefaults.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.xl)
            Text(SimulatorAccessBookmarkStore.requiredFolderPath)
                .font(DesignSystem.Typography.monoCaption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .textSelection(.enabled)
            Button("Choose Folder…", systemImage: "folder.badge.plus") {
                presentPicker()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            if let pickerError {
                Text(pickerError)
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Select the CoreSimulator/Devices folder shown below."
        panel.prompt = "Grant Access"
        panel.directoryURL = URL(fileURLWithPath: SimulatorAccessBookmarkStore.requiredFolderPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.bookmarkStore.storeBookmark(for: url)
            Task { await viewModel.refreshSimulators() }
        } catch {
            pickerError = error.localizedDescription
        }
    }
}
