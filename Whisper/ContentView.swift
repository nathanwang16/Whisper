//
//  ContentView.swift
//  Walkie_Talkie
//
//  Created by Nathan Wang on 4/19/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @AppStorage("username") private var username: String = ""
    @State private var usernameInput: String = ""
    @State private var usernameError: String? = nil
    @State private var isCheckingUsername: Bool = false
    @State private var isEditingUsername: Bool = false

    var body: some View {
        VStack {
            VStack(spacing: 8) {
                if isEditingUsername {
                    HStack {
                        TextField("Enter username", text: $usernameInput)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: usernameInput) { _ in usernameError = nil }
                        Button(isCheckingUsername ? "Checking..." : "Save") {
                            Task {
                                await checkAndSetUsername()
                                if usernameError == nil { isEditingUsername = false }
                            }
                        }
                        .disabled(isCheckingUsername || usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let error = usernameError {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                } else {
                    HStack {
                        Text(username)
                            .font(.headline)
                            .onTapGesture {
                                isEditingUsername = true
                                usernameInput = username
                            }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal)
            .onAppear {
                usernameInput = username
            }
            Spacer()
            Circle()
                .foregroundStyle(.tint)
                .scaleEffect(viewModel.isPressed ? 1.5 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isPressed)
                .aspectRatio(1.618, contentMode: .fit)
                .padding()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            viewModel.handleGestureChange()
                        }
                        .onEnded { _ in
                            viewModel.handleGestureEnd()
                        }
                )
                .padding(.bottom, 50)
            Spacer()
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .frame(width: 300, height: 60)
                .foregroundStyle(.black)
                .overlay(
                    Text("Files")
                        .foregroundColor(.white)
                        .font(.headline)
                )
                .onTapGesture {
                    viewModel.showAudioFiles()
                }
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.isShowingAudioFiles) {
            AudioFilesListView()
        }
        .disabled(username.isEmpty)
    }
    
    func checkAndSetUsername() async {
        let trimmed = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCheckingUsername = true
        let db = Firestore.firestore()
        let usersRef = db.collection("users")
        let query = usersRef.whereField("username", isEqualTo: trimmed)
        do {
            let snapshot = try await query.getDocuments()
            let currentUID = Auth.auth().currentUser?.uid
            let isDuplicate = snapshot.documents.contains { $0.documentID != currentUID }
            if !isDuplicate {
                // Save username in Firestore
                let uid = currentUID ?? UUID().uuidString
                try await usersRef.document(uid).setData(["username": trimmed, "uid": uid])
                username = trimmed
                usernameError = nil
            } else {
                usernameError = "Username already taken."
            }
        } catch {
            usernameError = "Error checking username."
        }
        isCheckingUsername = false
    }
}

