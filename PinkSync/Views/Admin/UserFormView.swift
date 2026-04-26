import SwiftUI

struct UserFormView: View {
    enum Mode {
        case add
        case edit(APIClient.UserResponse)
    }

    let mode: Mode
    let onSave: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var selectedRole: UserRole = .player
    @State private var isActive = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingUser: APIClient.UserResponse? {
        if case .edit(let user) = mode { return user }
        return nil
    }

    var body: some View {
        Form {
            Section {
                if isEditing {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(existingUser?.email ?? "")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }

                TextField("Display Name", text: $displayName)

                if isEditing {
                    SecureField("New Password (leave blank to keep)", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            } header: {
                Text("User Info")
            }

            Section {
                Picker("Role", selection: $selectedRole) {
                    ForEach(UserRole.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
            } header: {
                Text("Permissions")
            }

            if isEditing {
                Section {
                    Toggle("Active", isOn: $isActive)
                } header: {
                    Text("Status")
                } footer: {
                    Text("Deactivating a user will sign them out and prevent future login.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit User" : "New User")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !isEditing {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Create") {
                    save()
                }
                .disabled(isSaving || (!isEditing && (email.isEmpty || displayName.isEmpty || password.isEmpty)))
            }
        }
        .onAppear {
            if let user = existingUser {
                displayName = user.displayName
                selectedRole = user.role
                isActive = user.isActive
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                if let user = existingUser {
                    try await APIClient.updateUser(
                        userId: user.userId,
                        displayName: displayName,
                        role: selectedRole,
                        isActive: isActive,
                        password: password.isEmpty ? nil : password
                    )
                } else {
                    _ = try await APIClient.createUser(
                        email: email,
                        displayName: displayName,
                        password: password,
                        role: selectedRole
                    )
                }
                await onSave()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
