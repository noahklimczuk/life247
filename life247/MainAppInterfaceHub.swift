//
//  MainAppInterfaceHub.swift
//  life247
//

import SwiftUI

// MARK: - App Root Coordinator Hub
struct MainAppInterfaceHub: View {
    @StateObject private var authContext = SessionAuthContext()
    @StateObject private var trackingEngine = BackgroundTrackingEngine.shared
    @State private var splashCompleted = false
    
    var body: some View {
        ZStack {
            if !splashCompleted {
                AppLoadingView(isFullyLoaded: $splashCompleted)
                    .transition(.opacity)
            } else {
                if authContext.isAuthenticated {
                    // FIX: Direct authenticated operators straight to the main tracking workspace map
                    MainApplicationTelemetryWorkspace()
                        .environmentObject(authContext)
                        .environmentObject(trackingEngine)
                        .transition(.opacity)
                } else {
                    NormalLoginView()
                        .environmentObject(authContext)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
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

// MARK: - Telemetry Core Startup Pulse View
struct AppLoadingView: View {
    @Binding var isFullyLoaded: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                ProgressView()
                    .tint(.blue)
                    .scaleEffect(1.5)
                Text("Initializing Telemetry...")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .padding()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation {
                    isFullyLoaded = true
                }
            }
        }
    }
}
