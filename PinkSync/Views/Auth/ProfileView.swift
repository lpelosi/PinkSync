import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var authManager

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
            }
        }
        .navigationTitle("Profile")
    }
}
