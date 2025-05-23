//
//  Audio.swift
//  Walkie
//
//  Created by Nathan Wang on 4/19/25.
//
// This is used to start, stop and store recorded audio files.


import Foundation
import AVFoundation

class AudioRecorder {
    private var audioRecorder: AVAudioRecorder?
    public private(set) var lastRecordingURL: URL?
    
    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let audioFileURL = generateFileName() // Use the generateFileName method
            lastRecordingURL = audioFileURL
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFileURL, settings: settings)
            audioRecorder?.record()
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }

    
    func stopRecording() {
        audioRecorder?.stop()
        if let fileURL = audioRecorder?.url {
            lastRecordingURL = fileURL
            Task {
                await AudioFileManager.shared.uploadAudioFile(fileURL, customName: nil)
            }
        }
        audioRecorder = nil
    }
    
    private func generateFileName() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-HH-mm-ss"
        let fileName = formatter.string(from: Date()) + ".m4a"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(fileName)
    }


}
