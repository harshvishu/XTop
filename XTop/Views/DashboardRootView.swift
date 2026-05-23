import AppKit
import SwiftUI

struct DashboardRootView: View {
    @Environment(MacbarViewModel.self) private var viewModel
    @State private var manualPath = ""
    @State private var podName = ""
    @State private var pendingMaintenanceAction: PendingMaintenanceAction?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DashboardTheme.sectionSpacing) {
                SystemTelemetryCard()
                DashboardDivider()
                XcodeUtilityCard(snapshot: viewModel.xcodeSnapshot)
                DashboardDivider()
                GitContextCard(
                    manualPath: $manualPath
                )
                DashboardDivider()
                MaintenanceCard(
                    podName: $podName,
                    pendingMaintenanceAction: $pendingMaintenanceAction
                )
            }
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .frame(height: 620)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            pendingMaintenanceAction?.title ?? "Confirm Maintenance Action",
            isPresented: pendingMaintenanceBinding,
            titleVisibility: .visible
        ) {
            if let pendingMaintenanceAction {
                Button(pendingMaintenanceAction.buttonTitle, role: pendingMaintenanceAction.role) {
                    performMaintenanceAction(pendingMaintenanceAction.action)
                    self.pendingMaintenanceAction = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let pendingMaintenanceAction {
                Text(pendingMaintenanceAction.message)
            }
        }
    }

    private var pendingMaintenanceBinding: Binding<Bool> {
        Binding(
            get: { pendingMaintenanceAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingMaintenanceAction = nil
                }
            }
        )
    }

    private var dashboardWidth: CGFloat {
        CoreMeterGeometry.dashboardWidth(
            for: viewModel.telemetry.perCoreCpuPercent.count,
            maximumWidth: Double(viewModel.preferences.dashboardDensity.width)
        )
    }

    private func performMaintenanceAction(_ action: MaintenanceAction) {
        Task {
            await viewModel.performMaintenanceAction(action)
        }
    }
}

private struct ScrollbarFreeDashboardScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true

        let hostingView = context.coordinator.hostingView
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView.rootView = content
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
    }

    @MainActor
    final class Coordinator {
        let hostingView: NSHostingView<Content>

        init(content: Content) {
            hostingView = NSHostingView(rootView: content)
        }
    }
}

private struct SystemTelemetryCard: View {
    @Environment(MacbarViewModel.self) private var viewModel

    var body: some View {
        DashboardCard(title: "System", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {
                HStack(spacing: DashboardTheme.itemSpacing) {
                    TelemetryValueTile(title: "CPU", metric: viewModel.telemetry.cpuPercent)
                    TelemetryValueTile(title: "Memory", metric: viewModel.telemetry.memoryUsedPercent)
                    TelemetryValueTile(title: "Storage", metric: viewModel.telemetry.storageUsedPercent)
                }

                Label(
                    viewModel.telemetry.severity.rawValue.capitalized,
                    systemImage: severitySymbol(viewModel.telemetry.severity)
                )
                .font(.caption)
                .foregroundStyle(severityColor(viewModel.telemetry.severity))

                if viewModel.telemetry.sampleDelayed {
                    Label("Showing prior stable sample", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.accent)
                }

                CoreMeterChart(percentages: viewModel.telemetry.perCoreCpuPercent)

                VStack(alignment: .leading, spacing: 6) {
                    AdvancedMetricRow(
                        title: "GPU",
                        metric: viewModel.telemetry.gpuPercent,
                        capability: capability(for: .gpu)
                    )
                    AdvancedMetricRow(
                        title: "Temp",
                        metric: viewModel.telemetry.temperatureC,
                        capability: capability(for: .temperature)
                    )
                    AdvancedMetricRow(
                        title: "Fan",
                        metric: viewModel.telemetry.fanRPM,
                        capability: capability(for: .fan)
                    )
                    AdvancedMetricRow(title: "Disk Cache", metric: viewModel.telemetry.diskCacheMB, capability: nil)
                }

                if viewModel.preferences.includesDeveloperProcesses,
                   !viewModel.telemetry.developerToolUsage.isEmpty {
                    Divider().overlay(DashboardTheme.stroke)
                    Text("Developer Tools")
                        .font(.subheadline)
                        .foregroundStyle(DashboardTheme.secondaryText)

                    ForEach(viewModel.telemetry.developerToolUsage.prefix(4)) { usage in
                        HStack {
                            Text(usage.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(usage.cpuPercent.formatted(.number.precision(.fractionLength(1))))% CPU")
                                .foregroundStyle(DashboardTheme.secondaryText)
                            Text("\(usage.memoryMB.formatted(.number.precision(.fractionLength(0)))) MB")
                                .foregroundStyle(DashboardTheme.secondaryText)
                        }
                        .font(.caption)
                    }
                }
            }
        } accessory: {
            SettingsIconButton()
        }
    }

    private func capability(for metric: AdvancedSensorMetric) -> AdvancedSensorCapability? {
        viewModel.sensorSettings.capabilities.first { $0.metric == metric }
    }

    private func severityColor(_ severity: SeverityLevel) -> Color {
        switch severity {
        case .healthy:
            return .green
        case .warning:
            return .yellow
        case .critical:
            return .red
        case .unknown:
            return DashboardTheme.secondaryText
        }
    }

    private func severitySymbol(_ severity: SeverityLevel) -> String {
        switch severity {
        case .healthy:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .critical:
            return "bolt.trianglebadge.exclamationmark.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

private struct CoreMeterChart: View {
    let percentages: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per Core")
                .font(.subheadline)
                .foregroundStyle(DashboardTheme.secondaryText)

            GeometryReader { proxy in
                let blockSide = CoreMeterGeometry.expandedBlockSide(
                    for: percentages.count,
                    availableWidth: proxy.size.width
                )
                let chartWidth = CoreMeterGeometry.expandedChartWidth(
                    for: percentages.count,
                    availableWidth: proxy.size.width
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: CoreMeterGeometry.columnSpacing) {
                        ForEach(Array(percentages.enumerated()), id: \.offset) { core in
                            CoreMeterColumn(
                                coreNumber: core.offset + 1,
                                percentage: core.element,
                                blockSide: blockSide
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(width: chartWidth, alignment: .leading)
                    .background(HiddenScrollIndicatorConfigurator())
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: CoreMeterGeometry.maximumMeterHeight)
        }
    }
}

private struct HiddenScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> HiddenScrollIndicatorView {
        HiddenScrollIndicatorView()
    }

    func updateNSView(_ nsView: HiddenScrollIndicatorView, context: Context) {
        nsView.hideScrollIndicators()
    }
}

private final class HiddenScrollIndicatorView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        hideScrollIndicators()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideScrollIndicators()
    }

    func hideScrollIndicators() {
        DispatchQueue.main.async { [weak self] in
            guard let scrollView = self?.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
    }
}

private struct CoreMeterColumn: View {
    let coreNumber: Int
    let percentage: Double
    let blockSide: Double

    var body: some View {
        VStack(spacing: 5) {
            VStack(spacing: CoreMeterGeometry.blockSpacing) {
                ForEach(Array(CoreMeterMapper.segments(for: percentage).reversed().enumerated()), id: \.offset) { segment in
                    CoreMeterBlock(
                        segment: segment.element,
                        blockSide: blockSide,
                        fillColor: usageColor
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Core \(coreNumber)")
            .accessibilityValue("\(Int(percentage.rounded())) percent")

            Text("\(coreNumber)")
                .font(.caption)
                .foregroundStyle(DashboardTheme.secondaryText)
        }
        .frame(width: max(blockSide, CoreMeterGeometry.labelWidth))
        .help("Core \(coreNumber): \(percentage.formatted(.number.precision(.fractionLength(1))))%")
    }

    private var usageColor: Color {
        switch CoreMeterUsageBand.band(for: percentage) {
        case .low:
            return .green
        case .moderate:
            return .yellow
        case .elevated:
            return DashboardTheme.accent
        case .high:
            return .red
        }
    }
}

private struct CoreMeterBlock: View {
    let segment: CoreMeterSegment
    let blockSide: Double
    let fillColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(DashboardTheme.meterTrack)
            .frame(width: blockSide, height: blockSide)
            .overlay {
                if segment.fillFraction > 0 {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(fillColor)
                            .overlay(alignment: .top) {
                                if segment.fillFraction < 1 {
                                    Rectangle()
                                        .fill(.white.opacity(0.58))
                                        .frame(height: proxy.size.height * (1 - segment.fillFraction))
                                }
                            }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
    }
}

private struct TelemetryValueTile: View {
    let title: String
    let metric: MetricValue

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(DashboardTheme.secondaryText)
            Text(metricString)
                .font(.headline)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricString: String {
        guard metric.isAvailable, let value = metric.value else {
            return "N/A"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0))))\(metric.unit)"
    }
}

private struct AdvancedMetricRow: View {
    let title: String
    let metric: MetricValue
    let capability: AdvancedSensorCapability?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(DashboardTheme.secondaryText)
            Spacer()
            if metric.isAvailable, let value = metric.value {
                Text("\(value.formatted(.number.precision(.fractionLength(1)))) \(metric.unit)")
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            } else if capability != nil {
                SettingsWarningButton()
            } else {
                Text(metric.unavailableReason ?? "Unavailable")
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
        }
        .font(.caption)
    }
}

private struct XcodeUtilityCard: View {
    let snapshot: XcodeEnvironmentSnapshot
    @State private var detailExpanded = false

    var body: some View {
        DashboardCard(title: "Xcode Utility", systemImage: "hammer") {
            VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {
                HStack {
                    LabeledValue(label: "DerivedData", value: FileSizeScanner.formatBytes(snapshot.totalDerivedDataBytes))
                    Spacer()
                    LabeledValue(label: "Projects", value: "\(snapshot.openProjects.count)")
                }

                SubmenuRow(title: "Details", isExpanded: $detailExpanded)

                if detailExpanded {
                    VStack(alignment: .leading, spacing: 7) {
                        DashboardDetailHeading(title: "DerivedData Locations")
                        DashboardList(paths: snapshot.derivedDataLocations.map {
                            "\($0.path) -> \(FileSizeScanner.formatBytes($0.sizeBytes))"
                        }, emptyText: "No DerivedData folders found.")

                        DashboardDetailHeading(title: "Open Projects")
                        DashboardList(paths: snapshot.openProjects.map {
                            "\($0.projectPath) -> \(FileSizeScanner.formatBytes($0.sizeBytes))"
                        }, emptyText: "No open projects detected.")

                        Text("Provisioning Profiles: \(snapshot.provisioningProfiles.count)")
                        Text("Certificates: \(snapshot.certificates.count)")

                        DashboardList(paths: snapshot.errors, emptyText: "")
                            .foregroundStyle(DashboardTheme.accent)
                    }
                    .font(.caption)
                    .transition(.opacity)
                }
            }
        }
    }
}

private struct GitContextCard: View {
    @Environment(MacbarViewModel.self) private var viewModel
    @Binding var manualPath: String
    @State private var detailExpanded = false

    var body: some View {
        DashboardCard(title: "Git", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
            VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {
                HStack {
                    LabeledValue(label: "Branch", value: viewModel.gitSnapshot.branch ?? "N/A")
                    Spacer()
                    LabeledValue(label: "Repository", value: viewModel.gitSnapshot.repositoryRoot == nil ? "None" : "Found")
                }

                SubmenuRow(title: "Details", isExpanded: $detailExpanded)

                if detailExpanded {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Focused Project: \(viewModel.focusedProject.projectPath ?? "None")")
                        Text("Source: \(viewModel.focusedProject.source)")
                        Text("Confidence: \(viewModel.focusedProject.confidence.formatted(.number.precision(.fractionLength(2))))")
                        Text("Repository: \(viewModel.gitSnapshot.repositoryRoot ?? "Not a repo")")

                        DashboardDetailHeading(title: "Worktrees")
                        DashboardList(paths: viewModel.gitSnapshot.worktrees.map {
                            "\($0.isCurrent ? "*" : "-") \($0.path) [\($0.branch)]"
                        }, emptyText: "No Git worktrees resolved.")

                        TextField("Manual project path", text: $manualPath)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Set", systemImage: "checkmark", action: setManualPath)
                            Button("Clear", systemImage: "xmark", action: clearManualPath)
                        }
                    }
                    .font(.caption)
                    .transition(.opacity)
                }
            }
        }
    }

    private func setManualPath() {
        viewModel.setManualProjectOverride(path: manualPath)
    }

    private func clearManualPath() {
        manualPath = ""
        viewModel.setManualProjectOverride(path: nil)
    }
}

private struct MaintenanceCard: View {
    @Environment(MacbarViewModel.self) private var viewModel
    @Binding var podName: String
    @Binding var pendingMaintenanceAction: PendingMaintenanceAction?
    @State private var utilitiesExpanded = false

    var body: some View {
        DashboardCard(title: "Maintenance", systemImage: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {
                HStack {
                    ToolBadge(label: "git", available: viewModel.toolAvailability.git)
                    ToolBadge(label: "xcodebuild", available: viewModel.toolAvailability.xcodebuild)
                    ToolBadge(label: "pod", available: viewModel.toolAvailability.pod)
                }

                SubmenuRow(title: "Utilities", isExpanded: $utilitiesExpanded)

                if utilitiesExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        UtilityActionRow(title: "Clean DerivedData", systemImage: "trash") {
                            pendingMaintenanceAction = .cleanDerivedData
                        }
                        UtilityActionRow(title: "Clean Developer Caches", systemImage: "trash") {
                            pendingMaintenanceAction = .cleanCaches
                        }
                        UtilityActionRow(
                            title: "Reset SwiftPM",
                            systemImage: "arrow.counterclockwise",
                            isEnabled: canRunProjectXcodeAction
                        ) {
                            pendingMaintenanceAction = .resetSwiftPM
                        }
                        UtilityActionRow(
                            title: "Refetch SwiftPM",
                            systemImage: "arrow.down.circle",
                            isEnabled: canRunProjectXcodeAction
                        ) {
                            performMaintenanceAction(.refetchSwiftPM)
                        }
                        UtilityActionRow(
                            title: "List Pods",
                            systemImage: "list.bullet",
                            isEnabled: hasFocusedProject
                        ) {
                            performMaintenanceAction(.listPods)
                        }
                        UtilityActionRow(
                            title: "Install Pods",
                            systemImage: "square.and.arrow.down",
                            isEnabled: canRunProjectPodAction
                        ) {
                            performMaintenanceAction(.installPods)
                        }
                        UtilityActionRow(
                            title: "Deintegrate CocoaPods",
                            systemImage: "xmark.circle",
                            isEnabled: canRunProjectPodAction
                        ) {
                            pendingMaintenanceAction = .deintegratePods
                        }

                        TextField("Pod name", text: $podName)
                            .textFieldStyle(.roundedBorder)
                        UtilityActionRow(
                            title: "Update Named Pod",
                            systemImage: "arrow.triangle.2.circlepath",
                            isEnabled: canRunProjectPodAction && !trimmedPodName.isEmpty
                        ) {
                            performMaintenanceAction(.updateSinglePod(trimmedPodName))
                        }
                        UtilityActionRow(
                            title: "Clean Named Pod Cache",
                            systemImage: "trash",
                            isEnabled: viewModel.toolAvailability.pod && !trimmedPodName.isEmpty
                        ) {
                            pendingMaintenanceAction = .cleanPodCache(trimmedPodName)
                        }
                        UtilityActionRow(
                            title: "Clean All Pod Caches",
                            systemImage: "trash",
                            isEnabled: viewModel.toolAvailability.pod
                        ) {
                            pendingMaintenanceAction = .cleanPodCache(nil)
                        }

                        DashboardDetailHeading(title: "Recent Action Logs")
                        DashboardList(paths: viewModel.maintenanceLogs.prefix(8).map {
                            "\($0.action): \($0.summary)"
                        }, emptyText: "No maintenance actions yet.")
                    }
                    .font(.caption)
                    .transition(.opacity)
                }
            }
        }
    }

    private var hasFocusedProject: Bool {
        viewModel.focusedProject.projectPath != nil
    }

    private var canRunProjectXcodeAction: Bool {
        hasFocusedProject && viewModel.toolAvailability.xcodebuild
    }

    private var canRunProjectPodAction: Bool {
        hasFocusedProject && viewModel.toolAvailability.pod
    }

    private var trimmedPodName: String {
        podName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performMaintenanceAction(_ action: MaintenanceAction) {
        Task {
            await viewModel.performMaintenanceAction(action)
        }
    }
}

private struct DashboardCard<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    let content: Content
    let accessory: Accessory

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(DashboardTheme.primaryText)
                Spacer(minLength: 8)
                accessory
            }
            content
        }
//        .padding(.horizontal, DashboardTheme.sectionHorizontalPadding)
        .padding(.vertical, DashboardTheme.sectionVerticalPadding)
    }
}

private struct DashboardDivider: View {
    var body: some View {
        Divider()
            .overlay(DashboardTheme.stroke)
//            .padding(.horizontal, DashboardTheme.sectionHorizontalPadding)
    }
}

private struct DashboardDetailHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .foregroundStyle(DashboardTheme.secondaryText)
    }
}

private struct DashboardList: View {
    let paths: [String]
    let emptyText: String

    var body: some View {
        if paths.isEmpty {
            if !emptyText.isEmpty {
                Text(emptyText)
                    .foregroundStyle(DashboardTheme.secondaryText)
            }
        } else {
            ForEach(paths, id: \.self) { path in
                Text(path)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DashboardTheme.secondaryText)
            Text(value)
                .font(.subheadline)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct ToolBadge: View {
    let label: String
    let available: Bool

    var body: some View {
        Label(label, systemImage: available ? "checkmark.circle.fill" : "xmark.circle")
            .font(.caption)
            .foregroundStyle(available ? .green : DashboardTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(DashboardTheme.meterTrack)
            )
    }
}

private struct SettingsIconButton: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button(action: openDashboardSettings) {
            Image(systemName: "gearshape")
                .font(.body)
                .frame(width: DashboardTheme.rowMinimumHeight, height: DashboardTheme.rowMinimumHeight)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(DashboardTheme.secondaryText)
        .contentShape(Rectangle())
        .help("Open Settings")
        .accessibilityLabel("Open Settings")
    }

    private func openDashboardSettings() {
        openSettings()
    }
}

private struct SettingsWarningButton: View {
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        Button(action: openSensorSettings) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption.bold())
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(DashboardTheme.accent)
        .contentShape(Rectangle())
        .help("Configure sensor access in Settings")
        .accessibilityLabel("Configure sensor access in Settings")
    }

    private func openSensorSettings() {
        openSettings()
    }
}

private struct SubmenuRow: View {
    let title: String
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.body.bold())
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .foregroundStyle(DashboardTheme.primaryText)
            .frame(maxWidth: .infinity, minHeight: DashboardTheme.rowMinimumHeight, alignment: .leading)
//            .padding(.horizontal, DashboardTheme.rowHorizontalPadding)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: DashboardTheme.rowCornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DashboardTheme.rowCornerRadius)
            .fill(isHovered ? DashboardTheme.rowHover : .clear)
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isExpanded.toggle()
        }
    }
}

private struct UtilityActionRow: View {
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
            }
            .font(.body)
            .foregroundStyle(isEnabled ? DashboardTheme.primaryText : DashboardTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: DashboardTheme.rowMinimumHeight, alignment: .leading)
            .padding(.horizontal, DashboardTheme.rowHorizontalPadding)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: DashboardTheme.rowCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DashboardTheme.rowCornerRadius)
            .fill(isHovered && isEnabled ? DashboardTheme.rowHover : .clear)
    }
}

private enum DashboardTheme {
    static let meterTrack = Color(red: 0.28, green: 0.285, blue: 0.30)
    static let rowHover = Color.white.opacity(0.11)
    static let stroke = Color.white.opacity(0.08)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let accent = Color(red: 1, green: 0.36, blue: 0.12)
    static let outerPadding: CGFloat = 0
    static let sectionHorizontalPadding: CGFloat = 12
    static let sectionVerticalPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 0
    static let itemSpacing: CGFloat = 10
    static let rowCornerRadius: CGFloat = 6
    static let rowHorizontalPadding: CGFloat = 8
    static let rowMinimumHeight: CGFloat = 28
}

private enum PendingMaintenanceAction: Identifiable {
    case cleanDerivedData
    case cleanCaches
    case resetSwiftPM
    case cleanPodCache(String?)
    case deintegratePods

    var id: String {
        switch self {
        case .cleanDerivedData:
            return "clean-derived-data"
        case .cleanCaches:
            return "clean-caches"
        case .resetSwiftPM:
            return "reset-swiftpm"
        case .cleanPodCache(let podName):
            return "clean-pod-cache-\(podName ?? "all")"
        case .deintegratePods:
            return "deintegrate-pods"
        }
    }

    var action: MaintenanceAction {
        switch self {
        case .cleanDerivedData:
            return .cleanDerivedData
        case .cleanCaches:
            return .cleanCaches
        case .resetSwiftPM:
            return .resetSwiftPM
        case .cleanPodCache(let podName):
            return .cleanPodCache(podName)
        case .deintegratePods:
            return .deintegratePods
        }
    }

    var title: String {
        switch self {
        case .cleanDerivedData:
            return "Clean DerivedData?"
        case .cleanCaches:
            return "Clean Developer Caches?"
        case .resetSwiftPM:
            return "Reset SwiftPM State?"
        case .cleanPodCache(let podName):
            return podName == nil ? "Clean All CocoaPods Caches?" : "Clean CocoaPods Cache?"
        case .deintegratePods:
            return "Deintegrate CocoaPods?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .cleanDerivedData:
            return "Clean DerivedData"
        case .cleanCaches:
            return "Clean Caches"
        case .resetSwiftPM:
            return "Reset SwiftPM"
        case .cleanPodCache(let podName):
            return podName == nil ? "Clean All Pods" : "Clean Pod"
        case .deintegratePods:
            return "Deintegrate"
        }
    }

    var message: String {
        switch self {
        case .cleanDerivedData:
            return "This removes Xcode DerivedData and Xcode will rebuild affected products."
        case .cleanCaches:
            return "This removes SwiftPM and CocoaPods cache directories that may need to be fetched again."
        case .resetSwiftPM:
            return "This changes package resolution state for the selected Xcode project."
        case .cleanPodCache(let podName):
            if let podName {
                return "This removes cached CocoaPods artifacts for \(podName)."
            }
            return "This removes all cached CocoaPods artifacts."
        case .deintegratePods:
            return "This removes CocoaPods integration from the selected Xcode project."
        }
    }

    var role: ButtonRole? {
        .destructive
    }
}
