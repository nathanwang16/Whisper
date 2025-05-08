//
//  ContentViewModel.swift
//  Walkie
//
//  Created by Nathan Wang on 4/19/25.
//

import Foundation
import SwiftUI

class ContentViewModel: ObservableObject {
    @Published var isPressed: Bool = false
    @Published var isShowingAudioFiles: Bool = false
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

    func handleGestureEnd() {
        if isPressed {
            isPressed = false
            audioRecorder?.stopRecording()
        }
    }

    func showAudioFiles() {
        isShowingAudioFiles = true
    }
}
