import AppKit
import SwiftUI

struct DashboardRootView: View {
    @Environment(MacbarViewModel.self) private var viewModel
    @State private var podName = ""
    @State private var pendingMaintenanceAction: PendingMaintenanceAction?

    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    var onOpenSimulatorInspector: () -> Void = {}

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DashboardTheme.sectionSpacing) {
                SystemTelemetryCard(
                    onRefresh: onRefresh,
                    onOpenSettings: onOpenSettings,
                    onQuit: onQuit
                )
                
                SimulatorInspectorCard(action: onOpenSimulatorInspector)

                XcodeUtilityCard(snapshot: viewModel.xcodeSnapshot)
                
                GitMonitorCard()
                
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

    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        DashboardCard(title: "System", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {
                HStack(spacing: DashboardTheme.itemSpacing) {
                    TelemetryValueTile(title: "CPU", metric: viewModel.telemetry.cpuPercent)
                    TelemetryValueTile(title: "Memory", metric: viewModel.telemetry.memoryUsedPercent)
                    TelemetryValueTile(title: "Storage", metric: viewModel.telemetry.storageUsedPercent)
                }

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
            SystemCardToolbar(
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings,
                onQuit: onQuit
            )
        }
    }

    private func capability(for metric: AdvancedSensorMetric) -> AdvancedSensorCapability? {
        viewModel.sensorSettings.capabilities.first { $0.metric == metric }
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
        DashboardCard(title: "", systemImage: "hammer") {
            VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {
                SubmenuRow(title: "Xcode Utility", isExpanded: $detailExpanded)

                if detailExpanded {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            LabeledValue(label: "DerivedData", value: FileSizeScanner.formatBytes(snapshot.totalDerivedDataBytes))
                            Spacer()
                            LabeledValue(label: "Projects", value: "\(snapshot.openProjects.count)")
                        }

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

private struct GitMonitorCard: View {
    @Environment(MacbarViewModel.self) private var viewModel
    @State private var detailExpanded = false
    @State private var managedRepositoryID: UUID?

    var body: some View {
        DashboardCard(title: "", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
            VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {

                if let primary = viewModel.primaryMonitoredRepository {
                    PrimaryRepositoryRow(
                        repository: primary,
                        snapshot: viewModel.gitSnapshot(for: primary.id),
                        onManage: {
                            managedRepositoryID = primary.id
                        }
                    )
                }

                SubmenuRow(title: "Repositories", isExpanded: $detailExpanded)

                if detailExpanded {
                    VStack(alignment: .leading, spacing: 7) {
                        if !viewModel.secondaryMonitoredRepositories.isEmpty {
                            DashboardDetailHeading(title: "Other Active Repositories")
                            ForEach(viewModel.secondaryMonitoredRepositories) { repository in
                                MonitoredRepositoryRow(
                                    repository: repository,
                                    snapshot: viewModel.gitSnapshot(for: repository.id),
                                    onManage: {
                                        managedRepositoryID = repository.id
                                    }
                                )
                            }
                        }

                        if !viewModel.inactiveMonitoredRepositories.isEmpty {
                            DashboardDetailHeading(title: "Inactive Repositories")
                            ForEach(viewModel.inactiveMonitoredRepositories) { repository in
                                InactiveRepositoryRow(
                                    repository: repository,
                                    onManage: {
                                        managedRepositoryID = repository.id
                                    }
                                )
                            }
                        }

                        Button("Add Repository…", systemImage: "folder.badge.plus", action: addRepository)

                        DashboardDetailHeading(title: "Base Folders for Discovery")
                        if viewModel.gitMonitorRegistry.baseFolders.isEmpty {
                            Text("No base folders configured.")
                                .foregroundStyle(DashboardTheme.secondaryText)
                        } else {
                            ForEach(viewModel.gitMonitorRegistry.baseFolders, id: \.self) { folder in
                                HStack {
                                    Text(folder)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                        removeBaseFolder(folder)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        Button("Add Base Folder…", systemImage: "folder.badge.plus", action: addBaseFolder)
                    }
                    .font(.caption)
                    .transition(.opacity)
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { managedRepositoryID != nil },
                set: { presented in
                    if !presented {
                        managedRepositoryID = nil
                    }
                }
            )
        ) {
            if let repositoryID = managedRepositoryID {
                RepositoryDetailView(repositoryID: repositoryID)
                    .environment(viewModel)
            }
        }
    }

    private func addRepository() {
        guard let url = FolderPicker.pick(prompt: "Select Repository Folder") else { return }
        viewModel.addMonitoredRepository(
            path: url.path(percentEncoded: false),
            displayName: nil
        )
    }

    private func addBaseFolder() {
        guard let url = FolderPicker.pick(prompt: "Select Base Folder") else { return }
        var folders = viewModel.gitMonitorRegistry.baseFolders
        let path = url.path(percentEncoded: false)
        if !folders.contains(path) {
            folders.append(path)
            viewModel.setGitMonitorBaseFolders(folders)
        }
    }

    private func removeBaseFolder(_ folder: String) {
        let folders = viewModel.gitMonitorRegistry.baseFolders.filter { $0 != folder }
        viewModel.setGitMonitorBaseFolders(folders)
    }
}

private struct PrimaryRepositoryRow: View {
    @Environment(MacbarViewModel.self) private var viewModel
    let repository: GitMonitoredRepository
    let snapshot: GitRepositorySnapshot?
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PrimaryStarButton(repository: repository)
                Text(repository.displayName)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Button("Manage", action: onManage)
                    .buttonStyle(.borderless)
                SyncStateBadge(state: snapshot?.syncState ?? .idle)
            }

            HStack(spacing: 12) {
                LabeledValue(label: "Branch", value: snapshot?.branch ?? "—")
                Spacer()
                LabeledValue(label: "Changes", value: changesSummary)
                Spacer()
                LabeledValue(label: "Ahead/Behind", value: aheadBehindSummary)
            }

            ConfiguredUserCaption(snapshot: snapshot)
        }
    }

    private var changesSummary: String {
        guard let snapshot else { return "—" }
        return "\(snapshot.stagedCount + snapshot.unstagedCount + snapshot.untrackedCount)"
    }

    private var aheadBehindSummary: String {
        guard let snapshot else { return "—" }
        let ahead = snapshot.aheadBy ?? 0
        let behind = snapshot.behindBy ?? 0
        return "↑\(ahead) ↓\(behind)"
    }
}

private struct MonitoredRepositoryRow: View {
    @Environment(MacbarViewModel.self) private var viewModel
    let repository: GitMonitoredRepository
    let snapshot: GitRepositorySnapshot?
    let onManage: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    PrimaryStarButton(repository: repository)
                    Text(repository.displayName)
                        .bold()
                    Spacer()
                    SyncStateBadge(state: snapshot?.syncState ?? .idle)
                }
                HStack {
                    Text(snapshot?.branch ?? "—")
                    Spacer()
                    Text("↑\(snapshot?.aheadBy ?? 0) ↓\(snapshot?.behindBy ?? 0)")
                        .foregroundStyle(DashboardTheme.secondaryText)
                }
                ConfiguredUserCaption(snapshot: snapshot)
            }

            Button(role: .destructive) {
                viewModel.removeMonitoredRepository(id: repository.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove")

            Button("Manage", action: onManage)
                .buttonStyle(.borderless)
        }
    }
}

private struct InactiveRepositoryRow: View {
    @Environment(MacbarViewModel.self) private var viewModel
    let repository: GitMonitoredRepository
    let onManage: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.displayName)
                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(role: .destructive) {
                viewModel.removeMonitoredRepository(id: repository.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove")

            Button("Manage", action: onManage)
                .buttonStyle(.borderless)
        }
    }
}

private struct PrimaryStarButton: View {
    @Environment(MacbarViewModel.self) private var viewModel
    let repository: GitMonitoredRepository

    var body: some View {
        Button {
            viewModel.togglePrimaryMonitoredRepository(id: repository.id)
        } label: {
            Image(systemName: repository.isPrimary ? "star.fill" : "star")
                .foregroundStyle(repository.isPrimary ? .yellow : DashboardTheme.secondaryText)
        }
        .buttonStyle(.borderless)
        .help(repository.isPrimary ? "Unset Primary" : "Set Primary")
        .accessibilityLabel(repository.isPrimary ? "Unset Primary" : "Set Primary")
    }
}

private struct ConfiguredUserCaption: View {
    let snapshot: GitRepositorySnapshot?

    var body: some View {
        if let text = captionText {
            Text(text)
                .font(.caption2)
                .foregroundStyle(DashboardTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var captionText: String? {
        guard let snapshot else { return nil }
        let name = snapshot.configuredUserName
        let email = snapshot.configuredUserEmail
        switch (name, email) {
        case let (name?, email?): return "\(name) <\(email)>"
        case let (name?, nil): return name
        case let (nil, email?): return email
        default: return nil
        }
    }
}

private struct SyncStateBadge: View {
    let state: GitMonitorSyncState

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var label: String {
        switch state {
        case .idle: return "Idle"
        case .syncingLocal: return "Local Sync"
        case .syncingRemote: return "Remote Sync"
        case .healthy: return "Healthy"
        case .authRequired: return "Auth Required"
        case .timeout: return "Timed Out"
        case .failed: return "Failed"
        }
    }

    private var symbol: String {
        switch state {
        case .idle: return "circle"
        case .syncingLocal, .syncingRemote: return "arrow.triangle.2.circlepath"
        case .healthy: return "checkmark.circle.fill"
        case .authRequired: return "key.fill"
        case .timeout: return "clock.badge.exclamationmark"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .healthy: return .green
        case .authRequired, .timeout, .failed: return .red
        default: return DashboardTheme.secondaryText
        }
    }
}

private struct MaintenanceCard: View {
    @Environment(MacbarViewModel.self) private var viewModel
    @Binding var podName: String
    @Binding var pendingMaintenanceAction: PendingMaintenanceAction?
    @State private var utilitiesExpanded = false

    var body: some View {
        DashboardCard(title: "", systemImage: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: DashboardTheme.itemSpacing) {
                SubmenuRow(title: "Dependency Managers", isExpanded: $utilitiesExpanded)

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
            if !title.isEmpty || !(accessory is EmptyView) {
                HStack {
                    if !title.isEmpty {
                        Label(title, systemImage: systemImage)
                            .font(.headline)
                            .foregroundStyle(DashboardTheme.primaryText)
                    }
                    Spacer(minLength: 8)
                    accessory
                }
            }
            content
        }
//        .padding(.horizontal, DashboardTheme.sectionHorizontalPadding)
        .padding(.vertical, hasHeader ? DashboardTheme.sectionVerticalPadding : 0)
    }

    private var hasHeader: Bool {
        !title.isEmpty || !(accessory is EmptyView)
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

private struct SimulatorInspectorCard: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3")
                    .frame(width: 16)
                Text("Simulator Inspector")
                    .font(.body)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.body)
                    .foregroundStyle(DashboardTheme.secondaryText)
            }
            .foregroundStyle(DashboardTheme.primaryText)
            .frame(maxWidth: .infinity, minHeight: DashboardTheme.rowMinimumHeight, alignment: .leading)
            .padding(.horizontal, DashboardTheme.rowHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: DashboardTheme.rowCornerRadius)
                    .fill(isHovered ? DashboardTheme.rowHover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: DashboardTheme.rowCornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Open Simulator Inspector")
    }
}

private struct SystemCardToolbar: View {
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ToolbarIconButton(systemImage: "arrow.clockwise", help: "Refresh", action: onRefresh)
            ToolbarIconButton(systemImage: "gearshape", help: "Open Settings", action: onOpenSettings)
            ToolbarIconButton(systemImage: "power", help: "Quit XTop", action: onQuit)
        }
    }
}

private struct ToolbarIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: DashboardTheme.rowMinimumHeight, height: DashboardTheme.rowMinimumHeight)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(DashboardTheme.secondaryText)
        .contentShape(Rectangle())
        .help(help)
        .accessibilityLabel(help)
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
        SettingsWindowActivator.bringToFront()
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
        SettingsWindowActivator.bringToFront()
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
            .padding(.horizontal, DashboardTheme.rowHorizontalPadding)
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
    static let sectionSpacing: CGFloat = 4
    static let itemSpacing: CGFloat = 10
    static let rowCornerRadius: CGFloat = 6
    static let rowHorizontalPadding: CGFloat = 10
    static let rowMinimumHeight: CGFloat = 32
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
