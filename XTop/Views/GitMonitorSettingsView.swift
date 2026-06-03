import AppKit
import Foundation
import SwiftUI

struct GitMonitorSettingsView: View {
    @Environment(MacbarViewModel.self) private var viewModel
    @State private var manualDisplayName = ""
    @State private var showingHTTPSSheet = false
    @State private var showingSSHSheet = false

    var body: some View {
        Form {
            Section("Base Folders") {
                if viewModel.gitMonitorRegistry.baseFolders.isEmpty {
                    Text("No base folders configured.")
                        .foregroundStyle(.secondary)
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
                        }
                    }
                }
                Button("Add Base Folder…", systemImage: "folder.badge.plus", action: addBaseFolder)
            }

            Section("Repositories") {
                if viewModel.gitMonitorRegistry.repositories.isEmpty {
                    Text("No repositories tracked.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.gitMonitorRegistry.repositories) { repository in
                        RepositorySettingsRow(repository: repository)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Repository")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Display name (optional)", text: $manualDisplayName)
                    Button("Choose Repository Folder…", systemImage: "folder.badge.plus", action: addRepository)
                }
            }

            Section("Accounts") {
                if viewModel.gitMonitorProfiles.isEmpty {
                    Text("No accounts saved.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.gitMonitorProfiles) { profile in
                        AccountSettingsRow(profile: profile)
                    }
                }

                HStack {
                    Button("Add HTTPS Account") { showingHTTPSSheet = true }
                    Button("Add SSH Account") { showingSSHSheet = true }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingHTTPSSheet) {
            HTTPSAccountSheet { values in
                viewModel.loginHTTPSProfile(
                    displayName: values.displayName,
                    host: values.host,
                    username: values.username,
                    token: values.token
                )
            }
        }
        .sheet(isPresented: $showingSSHSheet) {
            SSHAccountSheet { values in
                viewModel.loginSSHProfile(
                    displayName: values.displayName,
                    host: values.host,
                    username: values.username,
                    privateKeyPath: values.privateKeyPath,
                    publicKeyFingerprint: values.publicKeyFingerprint,
                    passphrase: values.passphrase.isEmpty ? nil : values.passphrase
                )
            }
        }
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

    private func addRepository() {
        guard let url = FolderPicker.pick(prompt: "Select Repository Folder") else { return }
        let name = manualDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.addMonitoredRepository(
            path: url.path(percentEncoded: false),
            displayName: name.isEmpty ? nil : name
        )
        manualDisplayName = ""
    }
}

enum FolderPicker {
    @MainActor
    static func pick(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        panel.message = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct RepositorySettingsRow: View {
    @Environment(MacbarViewModel.self) private var viewModel
    let repository: GitMonitoredRepository

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Button {
                        viewModel.togglePrimaryMonitoredRepository(id: repository.id)
                    } label: {
                        Image(systemName: repository.isPrimary ? "star.fill" : "star")
                            .foregroundStyle(repository.isPrimary ? .yellow : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!repository.isActive)
                    .help(repository.isPrimary ? "Unset Primary" : "Set Primary")
                    .accessibilityLabel(repository.isPrimary ? "Unset Primary" : "Set Primary")

                    Text(repository.displayName)
                        .bold()
                    if !repository.isActive {
                        Text("Inactive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption = configuredUserCaption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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
        }
        .padding(.vertical, 4)
    }

    private var configuredUserCaption: String? {
        guard let snapshot = viewModel.gitSnapshot(for: repository.id) else { return nil }
        switch (snapshot.configuredUserName, snapshot.configuredUserEmail) {
        case let (name?, email?): return "\(name) <\(email)>"
        case let (name?, nil): return name
        case let (nil, email?): return email
        default: return nil
        }
    }
}

private struct AccountSettingsRow: View {
    @Environment(MacbarViewModel.self) private var viewModel
    let profile: GitMonitorAccountProfile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .bold()
                Text("\(profile.username)@\(profile.host) · \(profile.authMode.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Logout", role: .destructive) {
                viewModel.logoutProfile(id: profile.id)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HTTPSAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var host = ""
    @State private var username = ""
    @State private var token = ""
    let onSubmit: (HTTPSValues) -> Void

    struct HTTPSValues {
        let displayName: String
        let host: String
        let username: String
        let token: String
    }

    var body: some View {
        Form {
            Section("HTTPS Account") {
                TextField("Display Name", text: $displayName)
                TextField("Host", text: $host)
                TextField("Username", text: $username)
                SecureField("Personal Access Token", text: $token)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 280)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSubmit(
                        HTTPSValues(
                            displayName: displayName,
                            host: host,
                            username: username,
                            token: token
                        )
                    )
                    dismiss()
                }
                .disabled(displayName.isEmpty || host.isEmpty || username.isEmpty || token.isEmpty)
            }
        }
    }
}

private struct SSHAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var host = ""
    @State private var username = ""
    @State private var privateKeyPath = ""
    @State private var publicKeyFingerprint = ""
    @State private var passphrase = ""
    let onSubmit: (SSHValues) -> Void

    struct SSHValues {
        let displayName: String
        let host: String
        let username: String
        let privateKeyPath: String
        let publicKeyFingerprint: String
        let passphrase: String
    }

    var body: some View {
        Form {
            Section("SSH Account") {
                TextField("Display Name", text: $displayName)
                TextField("Host", text: $host)
                TextField("Username", text: $username)
                TextField("Private Key Path", text: $privateKeyPath)
                TextField("Public Key Fingerprint", text: $publicKeyFingerprint)
                SecureField("Passphrase (optional)", text: $passphrase)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSubmit(
                        SSHValues(
                            displayName: displayName,
                            host: host,
                            username: username,
                            privateKeyPath: privateKeyPath,
                            publicKeyFingerprint: publicKeyFingerprint,
                            passphrase: passphrase
                        )
                    )
                    dismiss()
                }
                .disabled(displayName.isEmpty || host.isEmpty || username.isEmpty || privateKeyPath.isEmpty)
            }
        }
    }
}
