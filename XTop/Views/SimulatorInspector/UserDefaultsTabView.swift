import SwiftUI

struct UserDefaultsTabView: View {
    @Environment(SimulatorInspectorViewModel.self) private var viewModel
    @State private var editingEntry: UserDefaultsEntry?
    @State private var showAddSheet = false
    @State private var entryToDelete: UserDefaultsEntry?
    @State private var searchText = ""

    var body: some View {
        Group {
            if viewModel.selectedApp == nil {
                emptyState("Select an installed app to inspect its UserDefaults.")
            } else if viewModel.selectedApp?.dataContainerPath == nil {
                emptyState("This app has no data container yet. Launch the app on the simulator at least once.")
            } else {
                table
            }
        }
        .sheet(item: $editingEntry) { entry in
            EditUserDefaultsEntrySheet(entry: entry) { newValue in
                Task { await viewModel.updateEntry(key: entry.key, value: newValue) }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddUserDefaultsEntrySheet(
                existingKeys: Set(viewModel.entries.map(\.key))
            ) { key, value in
                Task { await viewModel.addEntry(key: key, value: value) }
            }
        }
        .confirmationDialog(
            "Delete \(entryToDelete?.key ?? "key")?",
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            if let entry = entryToDelete {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteEntry(key: entry.key) }
                    entryToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("This removes the key from the on-disk plist. There is no in-app undo.")
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { entryToDelete != nil },
            set: { newValue in if !newValue { entryToDelete = nil } }
        )
    }

    private var filteredEntries: [UserDefaultsEntry] {
        FuzzySearch.filter(viewModel.entries, query: searchText) { $0.key }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                searchField
                Text(countLabel)
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                Button {
                    Task { await viewModel.refreshEntries() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshingEntries)
                Button("Add Key", systemImage: "plus") {
                    showAddSheet = true
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)

            Divider()

            if viewModel.entries.isEmpty {
                emptyState("No UserDefaults entries yet.")
            } else if filteredEntries.isEmpty {
                emptyState("No entries match \u{201C}\(searchText)\u{201D}.")
            } else {
                Table(filteredEntries) {
                    TableColumn("Key") { entry in
                        Text(entry.key)
                            .font(DesignSystem.Typography.monoRow)
                    }
                    .width(min: 160, ideal: 260)

                    TableColumn("Type") { entry in
                        Text(entry.type.displayName)
                            .font(DesignSystem.Typography.rowSecondary)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                    .width(min: 70, ideal: 90, max: 120)

                    TableColumn("Value") { entry in
                        Text(entry.displayValue)
                            .font(DesignSystem.Typography.monoRow)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    TableColumn("") { entry in
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Button("Edit", systemImage: "pencil") {
                                editingEntry = entry
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!entry.isScalar)
                            .help(entry.isScalar ? "Edit value" : "Editing arrays/dictionaries is not supported in v1.")

                            Button("Delete", systemImage: "trash", role: .destructive) {
                                entryToDelete = entry
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Delete entry")
                        }
                    }
                    .width(min: 90, ideal: 100, max: 120)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            TextField("Search keys", text: $searchText)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.row)
                .fill(Color.primary.opacity(0.06))
        )
        .frame(maxWidth: 260)
    }

    private var countLabel: String {
        let total = viewModel.entries.count
        let shown = filteredEntries.count
        if searchText.isEmpty || shown == total {
            return "\(total) entries"
        }
        return "\(shown) of \(total)"
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(DesignSystem.Spacing.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Edit sheet

struct EditUserDefaultsEntrySheet: View {
    let entry: UserDefaultsEntry
    let onSave: (Any) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stringValue: String = ""
    @State private var boolValue: Bool = false
    @State private var dateValue: Date = .now
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Edit \(entry.key)")
                .font(DesignSystem.Typography.sectionTitle)
            Text("Type: \(entry.type.displayName)")
                .font(DesignSystem.Typography.rowSecondary)
                .foregroundStyle(DesignSystem.Colors.secondaryText)

            editor

            if let error {
                Text(error)
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.destructive)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 420)
        .onAppear {
            stringValue = entry.displayValue
            boolValue = entry.displayValue == "true"
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch entry.type {
        case .bool:
            Toggle("Value", isOn: $boolValue)
        case .date:
            DatePicker("Value", selection: $dateValue, displayedComponents: [.date, .hourAndMinute])
        case .data:
            TextField("Base64 data", text: $stringValue, axis: .vertical)
                .lineLimit(4, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
        default:
            TextField("Value", text: $stringValue, axis: .vertical)
                .lineLimit(4, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func commit() {
        do {
            let value = try PlistValueCoder.encodeScalar(
                stringValue: stringValue,
                boolValue: boolValue,
                dateValue: dateValue,
                type: entry.type
            )
            onSave(value)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
