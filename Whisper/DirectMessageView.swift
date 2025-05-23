//
//  DirectMessageView.swift
//  Whisper
//
//  Created by Nathan Wang on 5/15/25.
//

import SwiftUI
import CoreData
import FirebaseFirestore
import AVFAudio

struct DirectMessageView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        entity: User.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \User.username, ascending: true)]
    ) private var users: FetchedResults<User>
    @State private var showUserPicker = false
    @State private var selectedUser: User? = nil
    @State private var showAddUser = false
    @StateObject private var viewModel = DMViewModel()
    var onExit: (() -> Void)?
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button("Testflight") { onExit?() }
                        .font(.headline)
                        .padding(.leading)
                    Spacer()
                    Text(selectedUser?.username ?? "Direct Message")
                        .font(.title3).bold()
                    Spacer()
                    Button(action: { showUserPicker = true }) {
                        Label("DM", systemImage: "bubble.left.and.bubble.right.fill")
                            .labelStyle(IconOnlyLabelStyle())
                            .font(.title2)
                            .padding(8)
                    }
                }
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                Spacer()
                // Central avatar record button
                if let user = selectedUser {
                    VStack(spacing: 0) {
                        ZStack {
                            UserAvatarView(username: user.username ?? "?")
                                .frame(width: 120, height: 120)
                                .scaleEffect(viewModel.isPressed ? 1.2 : 1.0)
                                .shadow(radius: 8)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { _ in viewModel.handleGestureChange() }
                                        .onEnded { _ in
                                            viewModel.handleGestureEnd(receiverUsername: user.username, receiverUserID: user.userID)
                                        }
                                )
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isPressed)
                            if viewModel.isPressed {
                                Image(systemName: "mic.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.bottom, 24)
                        // Message list
                        DMMessageListView(selectedUser: user)
                            .environment(\.managedObjectContext, context)
                            .frame(maxHeight: 320)
                    }
                } else {
                    // Show placeholder circle if no user selected
                    Circle()
                        .foregroundStyle(.tint)
                        .frame(width: 120, height: 120)
                        .shadow(radius: 8)
                        .overlay(
                            Image(systemName: "mic.fill")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                        )
                        .padding(.bottom, 60)
                }
                Spacer()
                // Breadcrum bar
                ZStack(alignment: .bottom) {
                    Color.clear.frame(height: 60)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .frame(height: 48)
                        .overlay(
                            HStack {
                                if let user = selectedUser {
                                    UserAvatarView(username: user.username ?? "?")
                                } else {
                                    Text("Select user...")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.up")
                                    .padding(.trailing, 12)
                            }
                            .padding(.horizontal)
                        )
                        .onTapGesture { withAnimation { showUserPicker = true } }
                }
                .padding(.bottom, 8)
            }
            // User picker sheet
            if showUserPicker {
                Color.black.opacity(0.2).ignoresSafeArea()
                    .onTapGesture { withAnimation { showUserPicker = false } }
                VStack {
                    Capsule().frame(width: 40, height: 6).foregroundColor(.gray.opacity(0.5)).padding(.top, 8)
                    HStack {
                        Text("Select User")
                            .font(.headline)
                        Spacer()
                        Button(action: { showAddUser = true }) {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                    }
                    .padding(.horizontal)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 3), spacing: 32) {
                            ForEach(users, id: \.self) { user in
                                VStack {
                                    UserAvatarView(username: user.username ?? "?")
                                        .onTapGesture {
                                            selectedUser = user
                                            withAnimation { showUserPicker = false }
                                        }
                                        .onLongPressGesture {
                                            // Confirm deletion
                                            if let username = user.username {
                                                AudioFileManager.shared.deleteUserFromLocal(username: username)
                                            }
                                        }
                                    Text(user.username ?? "?")
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(.top, 60)
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .sheet(isPresented: $showAddUser) {
            AddUserView(onAdd: { showAddUser = false })
        }
    }
}

struct UserAvatarView: View {
    let username: String
    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.8)).frame(width: 72, height: 72)
            Text(String(username.prefix(2)).uppercased())
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

struct AddUserView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var newUsername: String = ""
    @State private var suggestions: [String] = []
    @State private var isSearching = false
    @State private var error: String? = nil
    var onAdd: (() -> Void)?
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Add New User")) {
                    TextField("Username", text: $newUsername)
                        .onChange(of: newUsername) { value in
                            error = nil
                            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                suggestions = []
                                return
                            }
                            isSearching = true
                            AudioFileManager.shared.searchUsersInFirestore(prefix: value) { names in
                                DispatchQueue.main.async {
                                    suggestions = names.filter { $0 != newUsername }
                                    isSearching = false
                                }
                            }
                        }
                    if isSearching {
                        ProgressView()
                    }
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(suggestions, id: \.self) { name in
                                Button(action: {
                                    newUsername = name
                                    suggestions = []
                                }) {
                                    Text(name)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    if let error = error {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add User")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        AudioFileManager.shared.addUserToLocalIfExists(username: trimmed) { success in
                            DispatchQueue.main.async {
                                if success {
                                    onAdd?()
                                } else {
                                    error = "User not found in Firestore."
                                }
                            }
                        }
                    }.disabled(newUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onAdd?() }
                }
            }
        }
    }
}

struct DMMessageListView: View {
    @Environment(\.managedObjectContext) private var context
    var selectedUser: User
    @FetchRequest var messages: FetchedResults<Message>
    init(selectedUser: User) {
        self.selectedUser = selectedUser
        let myUID = UserDefaults.standard.string(forKey: "userID") ?? ""
        let otherUID = selectedUser.userID ?? ""
        let predicate = NSPredicate(format: "(senderUserID == %@ AND receiverUserID == %@) OR (senderUserID == %@ AND receiverUserID == %@)", myUID, otherUID, otherUID, myUID)
        _messages = FetchRequest(
            entity: Message.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)],
            predicate: predicate
        )
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(messages, id: \.messageID) { msg in
                    HStack(alignment: .center, spacing: 8) {
                        if msg.senderUserID == UserDefaults.standard.string(forKey: "userID") {
                            Spacer()
                            DMMessageBubble(isMe: true, message: msg)
                        } else {
                            DMMessageBubble(isMe: false, message: msg)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct DMMessageBubble: View {
    var isMe: Bool
    var message: Message
    var body: some View {
        HStack(spacing: 4) {
            if isMe {
                Spacer()
            }
            RoundedRectangle(cornerRadius: 16)
                .fill(isMe ? Color.accentColor.opacity(0.8) : Color.gray.opacity(0.2))
                .frame(height: 48)
                .overlay(
                    HStack {
                        Image(systemName: "waveform")
                        Text(message.audioFileName ?? "")
                            .font(.caption)
                            .foregroundColor(isMe ? .white : .primary)
                    }
                    .padding(.horizontal, 12)
                )
            if !isMe {
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}

