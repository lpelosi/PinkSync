import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        List {
            if let user = authManager.currentUser {
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppTheme.pink)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.headline)
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    HStack {
                        Text("Role")
                        Spacer()
                        Text(user.role.displayName)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Account")
                }

                Section {
                    Toggle("Face ID Quick Sign-In", isOn: Binding(
                        get: { authManager.biometricEnabled },
                        set: { authManager.biometricEnabled = $0 }
                    ))
                } header: {
                    Text("Security")
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        authManager.logout()
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("Delete Account")
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Permanently deletes your account and all associated data. This action cannot be undone.")
                }
            }
        }
        .navigationTitle("Profile")
        .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    await authManager.deleteAccount()
                    isDeleting = false
                }
            }
        } message: {
            Text("This will permanently delete your account and all associated data. This action cannot be undone.")
        }
    }
}
