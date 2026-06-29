//
//  MainAppInterfaceHub.swift
//  life247
//

import SwiftUI

// MARK: - App Root Coordinator Hub
struct MainAppInterfaceHub: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @EnvironmentObject var trackingEngine: BackgroundTrackingEngine

    var body: some View {
        ZStack {
            if authContext.isAuthenticated {
                // Direct authenticated operators straight to the main tracking workspace map viewport
                MainApplicationTelemetryWorkspace()
                    .transition(.opacity)
            } else {
                NormalLoginView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authContext.isAuthenticated)
    }
}

// MARK: - Normal Login View
struct NormalLoginView: View {
    @EnvironmentObject var authContext: SessionAuthContext
    @State private var usernameInput = ""
    @State private var passwordInput = ""
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    private let accent = Color(red: 0.55, green: 0.36, blue: 1.0)

    private var canSubmit: Bool {
        !usernameInput.trimmingCharacters(in: .whitespaces).isEmpty && !passwordInput.isEmpty
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.03, blue: 0.12), Color(red: 0.12, green: 0.06, blue: 0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                brandHeader
                credentialFields
                Spacer()
                Spacer()
            }
            .padding(28)
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.95), accent.opacity(0.45)],
                                         center: .center, startRadius: 2, endRadius: 50))
                    .frame(width: 88, height: 88)
                    .shadow(color: accent.opacity(0.6), radius: 20)
                Image(systemName: "location.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(spacing: 6) {
                Text("Life 24/7")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Sign in to your circle")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private var credentialFields: some View {
        VStack(spacing: 14) {
            TextField("", text: $usernameInput, prompt: Text("Username").foregroundColor(.white.opacity(0.4)))
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .modifier(LoginFieldStyle())

            SecureField("", text: $passwordInput, prompt: Text("Password").foregroundColor(.white.opacity(0.4)))
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
                .modifier(LoginFieldStyle())

            if let errorMsg = authContext.loginErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(errorMsg)
                }
                .font(.callout)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                Text("Sign In")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 14).fill(canSubmit ? accent : Color.white.opacity(0.15)))
            }
            .disabled(!canSubmit)
            .padding(.top, 4)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        authContext.attemptSecureLogin(username: usernameInput, password: passwordInput)
    }
}

/// Shared styling for the login text fields on the dark gradient backdrop.
private struct LoginFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.white)
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
