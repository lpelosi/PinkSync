import SwiftUI

struct UserManagementView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var users: [APIClient.UserResponse] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddUser = false

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
                            UserFormView(mode: .edit(user)) {
                                await loadUsers()
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
                            UserFormView(mode: .edit(user)) {
                                await loadUsers()
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
            Button {
                showingAddUser = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddUser) {
            NavigationStack {
                UserFormView(mode: .add) {
                    await loadUsers()
                }
            }
        }
        .task {
            await loadUsers()
        }
        .refreshable {
            await loadUsers()
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

    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin: return AppTheme.pink
        case .rosterManager: return .blue
        case .photographer: return .green
        case .scheduleManager: return .orange
        case .player: return .gray
        }
    }

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        do {
            users = try await APIClient.fetchUsers()
        } catch {
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
