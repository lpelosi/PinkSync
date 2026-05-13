import SwiftUI

struct UserManagementView: View {
    @State private var users: [APIClient.UserResponse] = []
    @State private var rosterPlayers: [APIClient.RosterPlayerResponse] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddUser = false
    @State private var showingMerge = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading users...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            let activeUsers = users.filter(\.isActive)
            if !activeUsers.isEmpty {
                Section("Active Users") {
                    ForEach(activeUsers) { user in
                        NavigationLink {
                            UserFormView(mode: .edit(user), rosterPlayers: rosterPlayers) {
                                await loadData()
                            }
                        } label: {
                            userRow(user)
                        }
                    }
                }
            }

            let inactiveUsers = users.filter { !$0.isActive }
            if !inactiveUsers.isEmpty {
                Section("Inactive Users") {
                    ForEach(inactiveUsers) { user in
                        NavigationLink {
                            UserFormView(mode: .edit(user), rosterPlayers: rosterPlayers) {
                                await loadData()
                            }
                        } label: {
                            userRow(user)
                                .opacity(0.5)
                        }
                    }
                }
            }
        }
        .navigationTitle("Users")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddUser = true
                    } label: {
                        Label("Add User", systemImage: "plus")
                    }
                    Button {
                        showingMerge = true
                    } label: {
                        Label("Merge Accounts", systemImage: "arrow.triangle.merge")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddUser) {
            NavigationStack {
                UserFormView(mode: .add, rosterPlayers: rosterPlayers) {
                    await loadData()
                }
            }
        }
        .sheet(isPresented: $showingMerge) {
            NavigationStack {
                MergeAccountsView(users: users.filter(\.isActive)) {
                    await loadData()
                }
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    private func userRow(_ user: APIClient.UserResponse) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.bold())
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail = linkedPlayerDetail(for: user) {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(user.role.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(roleColor(user.role).opacity(0.2))
                .foregroundStyle(roleColor(user.role))
                .clipShape(Capsule())
        }
    }

    private func linkedPlayerDetail(for user: APIClient.UserResponse) -> String? {
        let linkedPlayerName = rosterPlayers.first(where: { $0.playerId == user.playerId })?.name
        return linkedPlayerName ?? user.playerId
    }

    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin: return AppTheme.pink
        case .rosterManager: return .blue
        case .photographer: return .green
        case .scheduleManager: return .orange
        case .player: return .gray
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            users = try await APIClient.fetchUsers()
            rosterPlayers = (try? await APIClient.fetchRoster()) ?? []
            if rosterPlayers.isEmpty {
                errorMessage = "Users loaded, but roster links are unavailable right now."
            }
        } catch {
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - Merge Accounts View

struct MergeAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    let users: [APIClient.UserResponse]
    let onComplete: () async -> Void

    @State private var primaryUser: APIClient.UserResponse?
    @State private var duplicateUser: APIClient.UserResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showConfirmation = false

    var body: some View {
        Form {
            Section {
                Text("Select the account to keep (primary) and the duplicate to merge into it. The duplicate will be deactivated.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Keep This Account") {
                Picker("Primary", selection: $primaryUser) {
                    Text("Select account...").tag(APIClient.UserResponse?.none)
                    ForEach(users) { user in
                        Text("\(user.displayName) (\(user.email))")
                            .tag(APIClient.UserResponse?.some(user))
                    }
                }
            }

            Section("Merge & Deactivate") {
                Picker("Duplicate", selection: $duplicateUser) {
                    Text("Select account...").tag(APIClient.UserResponse?.none)
                    ForEach(availableDuplicates) { user in
                        Text("\(user.displayName) (\(user.email))")
                            .tag(APIClient.UserResponse?.some(user))
                    }
                }
                .disabled(primaryUser == nil)
            }

            if let primary = primaryUser, let duplicate = duplicateUser {
                Section("Preview") {
                    LabeledContent("Keep", value: "\(primary.displayName) (\(primary.email))")
                    LabeledContent("Deactivate", value: "\(duplicate.displayName) (\(duplicate.email))")
                    Text("Apple ID and any higher role from the duplicate will transfer to the primary account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Merge Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge") { showConfirmation = true }
                    .disabled(primaryUser == nil || duplicateUser == nil || isLoading)
                    .bold()
            }
        }
        .confirmationDialog(
            "Merge Accounts?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Merge Accounts", role: .destructive) {
                performMerge()
            }
        } message: {
            if let duplicate = duplicateUser, let primary = primaryUser {
                Text("\"\(duplicate.displayName)\" will be deactivated and merged into \"\(primary.displayName)\". This cannot be undone.")
            }
        }
    }

    private var availableDuplicates: [APIClient.UserResponse] {
        guard let primary = primaryUser else { return [] }
        return users.filter { $0.userId != primary.userId }
    }

    private func performMerge() {
        guard let primary = primaryUser, let duplicate = duplicateUser else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await APIClient.mergeUsers(
                    primaryUserId: primary.userId,
                    duplicateUserId: duplicate.userId
                )
                await onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
