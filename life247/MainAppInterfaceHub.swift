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
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("life247 Secure Access")
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 10)
            
            TextField("Username", text: $usernameInput)
                .textContentType(.username)
                .autocapitalization(.none)
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
            
            SecureField("Password", text: $passwordInput)
                .textContentType(.password)
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
            
            if let errorMsg = authContext.loginErrorMessage {
                Text(errorMsg)
                    .font(.callout)
                    .foregroundColor(.red)
            }
            
            Button(action: {
                authContext.attemptSecureLogin(username: usernameInput, password: passwordInput)
            }) {
                Text("Authorize Entry")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(usernameInput.isEmpty || passwordInput.isEmpty ? Color.gray : Color.purple)
                    .cornerRadius(12)
            }
            .disabled(usernameInput.isEmpty || passwordInput.isEmpty)
            
            Spacer()
        }
        .padding(24)
    }
}
