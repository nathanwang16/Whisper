//
//  Walkie_TalkieApp.swift
//  Walkie_Talkie
//
//  Created by Nathan Wang on 4/19/25.
//

import SwiftUI
import FirebaseCore
import FirebaseStorage
import Speech
import FirebaseAuth
import FirebaseFirestore
import CoreData

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        //FirebaseApp.configure()
        return true
    }
}

@main
struct Walkie_TalkieApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("privacyAccepted") private var privacyAccepted: Bool = false
    @AppStorage("username") private var username: String = ""
    @State private var showPrivacy: Bool = false
    @State private var usernameInput: String = ""
    @State private var usernameError: String? = nil
    @State private var isCheckingUsername: Bool = false
    @State private var userID: String = ""
    
    init() {
        SFSpeechRecognizer.requestAuthorization { status in }
        FirebaseApp.configure()
        // Anonymous Auth
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { result, error in
                if let user = result?.user {
                    UserDefaults.standard.set(user.uid, forKey: "userID")
                }
            }
        } else {
            UserDefaults.standard.set(Auth.auth().currentUser?.uid, forKey: "userID")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                    .disabled(!privacyAccepted || username.isEmpty)
                    .blur(radius: (!privacyAccepted || username.isEmpty) ? 8 : 0)
                if !privacyAccepted {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 24) {
                        Text("Privacy Agreement")
                            .font(.title)
                            .bold()
                        ScrollView {
                            Text("By using this app, you agree to the use of speech recognition and cloud storage for your audio and transcriptions. Your data may be processed by third-party services (Apple, Google, Firebase). Please review our privacy policy for details.")
                                .padding()
                        }
                        Button("Accept & Continue") {
                            privacyAccepted = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(32)
                }
                if privacyAccepted && username.isEmpty {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text("Choose a Username")
                            .font(.title2)
                            .bold()
                        TextField("Enter username", text: $usernameInput)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                        if let error = usernameError {
                            Text(error).foregroundColor(.red).font(.caption)
                        }
                        Button(isCheckingUsername ? "Checking..." : "Set Username") {
                            Task { await checkAndSetUsername() }
                        }
                        .disabled(isCheckingUsername || usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(32)
                }
            }
        }
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
            if snapshot.documents.isEmpty {
                // Save username in Firestore
                let uid = Auth.auth().currentUser?.uid ?? UUID().uuidString
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
