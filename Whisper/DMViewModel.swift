import Foundation
import SwiftUI
import AVFAudio


class DMViewModel: ObservableObject {
    @Published var isPressed: Bool = false
    private var audioRecorder: AudioRecorder?
    
    init() {
        audioRecorder = AudioRecorder()
    }
    
    func handleGestureChange() {
        if !isPressed {
            isPressed = true
            audioRecorder?.startRecording()
        }
    }
    
    func handleGestureEnd(receiverUsername: String?, receiverUserID: String?) {
        if isPressed {
            isPressed = false
            audioRecorder?.stopRecording()
            if let url = audioRecorder?.lastRecordingURL,
               let receiverUsername = receiverUsername,
               let receiverUserID = receiverUserID {
                Task {
                    await AudioFileManager.shared.uploadDMMessage(fileURL: url, receiverUsername: receiverUsername, receiverUserID: receiverUserID)
                }
            }
            audioRecorder = AudioRecorder() // Reset for next use
        }
    }
} 
