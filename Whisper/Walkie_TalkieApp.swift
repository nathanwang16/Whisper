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

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct Walkie_TalkieApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("privacyAccepted") private var privacyAccepted: Bool = false
    @State private var showPrivacy: Bool = false
    
    init() {
        SFSpeechRecognizer.requestAuthorization { status in
            // Optionally handle status
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .disabled(!privacyAccepted)
                    .blur(radius: privacyAccepted ? 0 : 8)
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
            }
        }
    }
}
