import AppKit
import SwiftUI

/// "Grid" tab in the Simulator Inspector. Lets the developer enable a thin
/// alignment grid overlay over the currently selected booted simulator's
/// window. Configuration is persisted per simulator UDID.
struct GridTabView: View {
    @Environment(SimulatorInspectorViewModel.self) private var inspector
    @Environment(GridOverlayController.self) private var overlay
    @Environment(AXPermissionMonitor.self) private var axMonitor

    @State private var config: GridOverlayConfig = .default
    @State private var horizontalCustomText: String = ""
    @State private var verticalCustomText: String = ""
    @State private var horizontalParseError: String?
    @State private var verticalParseError: String?

    private let store: GridOverlayConfigStore

    init(store: GridOverlayConfigStore) {
        self.store = store
    }

    var body: some View {
        Group {
            if axMonitor.status != .granted {
                axPermissionEmptyState
            } else if let simulator = inspector.selectedSimulator {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        content(for: simulator)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.md)
                }
            } else {
                noSimulatorEmptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { axMonitor.refresh() }
        .onChange(of: inspector.selectedSimulatorID) { _, newValue in
            loadConfig(for: newValue)
        }
        .task { loadConfig(for: inspector.selectedSimulatorID) }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for simulator: SimulatorDevice) -> some View {
        zoomNotice

        Toggle(isOn: enableBinding(for: simulator)) {
            Text("Show grid overlay")
                .font(DesignSystem.Typography.rowPrimary)
        }
        .toggleStyle(.switch)

        if case .error(let message) = overlay.currentState(udid: simulator.udid) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignSystem.Colors.destructive)
                Text(message)
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
        }

        Divider()

        opacityRow(for: simulator)

        Divider()

        HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
            axisSection(
                title: "Vertical lines",
                spec: config.vertical,
                customText: $verticalCustomText,
                parseError: $verticalParseError,
                update: { newSpec in
                    config.vertical = newSpec
                    persist(for: simulator)
                    overlay.updateConfig(config, udid: simulator.udid)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            axisSection(
                title: "Horizontal lines",
                spec: config.horizontal,
                customText: $horizontalCustomText,
                parseError: $horizontalParseError,
                update: { newSpec in
                    config.horizontal = newSpec
                    persist(for: simulator)
                    overlay.updateConfig(config, udid: simulator.udid)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var zoomNotice: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "info.circle")
                .foregroundStyle(DesignSystem.Colors.accent)
            Text("Set the Simulator zoom to 100% (⌘0) for accurate alignment. The overlay assumes 1 simulated point = 1 host point.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func opacityRow(for simulator: SimulatorDevice) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack {
                Text("Opacity")
                    .font(DesignSystem.Typography.rowPrimary)
                Spacer()
                Text(opacityLabel)
                    .font(DesignSystem.Typography.monoCaption)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
            Slider(
                value: opacityBinding(for: simulator),
                in: GridOverlayConfig.minOpacity ... GridOverlayConfig.maxOpacity
            )
        }
    }

    private var opacityLabel: String {
        "\(Int((config.opacity * 100).rounded()))%"
    }

    @ViewBuilder
    private func axisSection(
        title: String,
        spec: GridAxisSpec,
        customText: Binding<String>,
        parseError: Binding<String?>,
        update: @escaping (GridAxisSpec) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.sectionTitle)

            Picker("Mode", selection: Binding(
                get: { spec.mode },
                set: { newMode in
                    var newSpec = spec
                    newSpec.mode = newMode
                    update(newSpec)
                }
            )) {
                ForEach(GridAxisMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch spec.mode {
            case .uniform:
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Spacing")
                        .font(DesignSystem.Typography.rowSecondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                    TextField(
                        "8",
                        value: Binding(
                            get: { Int(spec.uniformSpacing.rounded()) },
                            set: { newValue in
                                var newSpec = spec
                                newSpec.uniformSpacing = CGFloat(max(1, min(256, newValue)))
                                update(newSpec)
                            }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(DesignSystem.Typography.monoCaption)
                    .frame(width: 56)
                    Stepper(
                        "",
                        value: Binding(
                            get: { spec.uniformSpacing },
                            set: { newValue in
                                var newSpec = spec
                                newSpec.uniformSpacing = max(1, min(256, newValue))
                                update(newSpec)
                            }
                        ),
                        in: 1 ... 256,
                        step: 1
                    )
                    .labelsHidden()
                    Text("pt")
                        .font(DesignSystem.Typography.rowSecondary)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
            case .custom:
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    TextField(
                        "8, 8, 4, 4",
                        text: customText
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(DesignSystem.Typography.monoCaption)
                    .onChange(of: customText.wrappedValue) { _, newValue in
                        applyCustom(text: newValue, into: spec, update: update, parseError: parseError)
                    }
                    if let error = parseError.wrappedValue {
                        Text(error)
                            .font(DesignSystem.Typography.rowSecondary)
                            .foregroundStyle(DesignSystem.Colors.destructive)
                    } else {
                        Text("Comma-separated gaps from the previous line, in points.")
                            .font(DesignSystem.Typography.rowSecondary)
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    }
                }
            }
        }
    }

    // MARK: - Bindings

    private func enableBinding(for simulator: SimulatorDevice) -> Binding<Bool> {
        Binding(
            get: { config.isEnabled },
            set: { newValue in
                config.isEnabled = newValue
                persist(for: simulator)
                if newValue {
                    overlay.activate(for: SimulatorIdentity(device: simulator), config: config)
                } else {
                    overlay.deactivate(udid: simulator.udid)
                }
            }
        )
    }

    private func opacityBinding(for simulator: SimulatorDevice) -> Binding<Double> {
        Binding(
            get: { config.opacity },
            set: { newValue in
                config.opacity = newValue
                persist(for: simulator)
                overlay.updateConfig(config, udid: simulator.udid)
            }
        )
    }

    // MARK: - Mutations

    private func applyCustom(
        text: String,
        into spec: GridAxisSpec,
        update: (GridAxisSpec) -> Void,
        parseError: Binding<String?>
    ) {
        switch GridOffsetsParser.parse(text) {
        case .success(let offsets):
            parseError.wrappedValue = nil
            var newSpec = spec
            newSpec.customOffsets = offsets
            update(newSpec)
        case .failure(let error):
            parseError.wrappedValue = errorMessage(for: error)
        }
    }

    private func errorMessage(for error: GridOffsetsParseError) -> String {
        switch error {
        case .empty:
            return "Enter at least one positive number, e.g. 8, 8, 4, 4."
        case .invalidToken(let token):
            return "Could not parse \"\(token)\" as a number."
        case .nonPositive(let value):
            return "Values must be greater than zero (got \(value))."
        }
    }

    private func persist(for simulator: SimulatorDevice) {
        store.setConfig(config, forUDID: simulator.udid)
    }

    private func loadConfig(for udid: String?) {
        guard let udid else {
            config = .default
            horizontalCustomText = ""
            verticalCustomText = ""
            horizontalParseError = nil
            verticalParseError = nil
            return
        }
        let loaded = store.config(forUDID: udid)
        config = loaded
        horizontalCustomText = GridOffsetsParser.format(loaded.horizontal.customOffsets)
        verticalCustomText = GridOffsetsParser.format(loaded.vertical.customOffsets)
        horizontalParseError = nil
        verticalParseError = nil
    }

    // MARK: - Empty states

    private var axPermissionEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(DesignSystem.Colors.accent)
            Text("Accessibility permission required")
                .font(DesignSystem.Typography.title)
            Text("XTop needs Accessibility permission to locate the Simulator window and pin a grid overlay over it. The overlay is click-through and does not interact with the simulator.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            HStack(spacing: DesignSystem.Spacing.sm) {
                Button("Grant Accessibility Access", systemImage: "checkmark.shield") {
                    _ = axMonitor.requestAccess()
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                Button("Re-check", systemImage: "arrow.clockwise") {
                    axMonitor.refresh()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
    }

    private var noSimulatorEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(DesignSystem.Colors.accent)
            Text("No simulator selected")
                .font(DesignSystem.Typography.title)
            Text("Select a booted simulator from the sidebar to configure its grid overlay.")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
