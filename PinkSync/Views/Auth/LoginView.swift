import AuthenticationServices
import LocalAuthentication
import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showBiometric = false
    @FocusState private var focusedField: Field?

    private enum Mode { case signIn, register }
    private enum Field: Hashable { case email, password, fullName, confirmPassword }

    var body: some View {
        ZStack {
            AppTheme.darkBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 40)

                    Image("TeamLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)

                    Text("Frozen Flamingos")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(AppTheme.pink)

                    Text(mode == .signIn ? "Sign in to PinkSync" : "Create your account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    formFields

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    primaryButton

                    if showBiometric && mode == .signIn {
                        Button(action: biometricSignIn) {
                            Label("Sign in with Face ID", systemImage: "faceid")
                                .font(.subheadline)
                        }
                        .tint(AppTheme.teal)
                    }

                    divider

                    SignInWithAppleButton(
                        mode == .signIn ? .signIn : .signUp,
                        onRequest: configureAppleRequest,
                        onCompletion: handleAppleResult
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .cornerRadius(10)
                    .padding(.horizontal, 32)

                    modeToggle

                    Spacer()
                }
            }
        }
        .onAppear {
            showBiometric = authManager.biometricEnabled && hasBiometricCapability()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: 16) {
            if mode == .register {
                TextField("Full Name", text: $fullName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)
                    .focused($focusedField, equals: .fullName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }
            }

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .focused($focusedField, equals: .password)
                .submitLabel(mode == .signIn ? .go : .next)
                .onSubmit {
                    if mode == .signIn {
                        signIn()
                    } else {
                        focusedField = .confirmPassword
                    }
                }

            if mode == .register {
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirmPassword)
                    .submitLabel(.go)
                    .onSubmit { registerAccount() }
            }
        }
        .padding(.horizontal, 32)
    }

    private var primaryButton: some View {
        Button(action: mode == .signIn ? signIn : registerAccount) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.pink)
        .disabled(primaryButtonDisabled)
        .padding(.horizontal, 32)
    }

    private var divider: some View {
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text("or")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 32)
    }

    private var modeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = mode == .signIn ? .register : .signIn
                errorMessage = nil
            }
        } label: {
            if mode == .signIn {
                Text("Don't have an account? ") + Text("Sign Up").bold()
            } else {
                Text("Already have an account? ") + Text("Sign In").bold()
            }
        }
        .font(.footnote)
        .tint(AppTheme.teal)
    }

    private var primaryButtonDisabled: Bool {
        if isLoading { return true }
        if email.isEmpty || password.isEmpty { return true }
        if mode == .register && (fullName.isEmpty || confirmPassword.isEmpty) { return true }
        return false
    }

    // MARK: - Actions

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        focusedField = nil

        Task {
            do {
                try await authManager.login(email: email, password: password)
                offerBiometric()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func registerAccount() {
        guard !fullName.isEmpty, !email.isEmpty, !password.isEmpty else { return }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        isLoading = true
        errorMessage = nil
        focusedField = nil

        Task {
            do {
                try await authManager.register(email: email, displayName: fullName, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func biometricSignIn() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.authenticateWithBiometric()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.handleAppleSignIn(result: result)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func offerBiometric() {
        if !authManager.biometricEnabled && hasBiometricCapability() {
            authManager.biometricEnabled = true
        }
    }

    private func hasBiometricCapability() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}
