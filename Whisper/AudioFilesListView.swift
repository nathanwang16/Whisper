//
//  AudioFilesListView.swift
//  Walkie
//
//  Created by Nathan Wang on 4/19/25.
//

import SwiftUI
import AVFoundation
import FirebaseCore
import FirebaseStorage

struct AudioFilesListView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var fileManager = AudioFileManager.shared
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentlyPlayingFile: AudioFile?
    @State private var isLoading: Bool = false
    @State private var downloadingFile: AudioFile? = nil
    
    private let localDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    var body: some View {
        NavigationView {
            List {
				ForEach(fileManager.audioFiles, id: \.self) { file in
                    HStack {
                        Text(file.name)
                            .foregroundColor(currentlyPlayingFile == file ? .blue : .primary)
                        Spacer()
                        if currentlyPlayingFile == file {
                            Text("Playing")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        // Status dot
                        if downloadingFile == file {
                            Circle().fill(Color.yellow).frame(width: 10, height: 10)
                        } else if isFileDownloaded(file) {
                            Circle().fill(Color.green).frame(width: 10, height: 10)
                        } else {
                            Circle().fill(Color.red).frame(width: 10, height: 10)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await handleAudioPlayback(for: file) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteAudioFile(file) }
                        } label: {
                            Text("Delete")
                        }
                    }
                }
            }
            .navigationTitle("Recorded Files")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Recorded Files")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                Task { await fileManager.fetchAudioFiles() }
            }
        }
    }
    
    private func isFileDownloaded(_ file: AudioFile) -> Bool {
        let localURL = localDirectory.appendingPathComponent(file.name)
        return FileManager.default.fileExists(atPath: localURL.path)
    }
    
    private func handleAudioPlayback(for file: AudioFile) async {
        if currentlyPlayingFile == file {
            stopAudio()
        } else {
            await playAudio(file: file)
        }
    }
    
    private func playAudio(file: AudioFile) async {
        let localURL = localDirectory.appendingPathComponent(file.name)
        if isFileDownloaded(file) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                audioPlayer = try AVAudioPlayer(contentsOf: localURL)
                audioPlayer?.play()
                currentlyPlayingFile = file
            } catch {
                print("Failed to play audio: \(error.localizedDescription)")
            }
        } else {
            downloadingFile = file
            if let remoteURL = await fileManager.downloadAudioFile(file) {
                do {
                    let data = try Data(contentsOf: remoteURL)
                    try data.write(to: localURL)
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    try AVAudioSession.sharedInstance().setActive(true)
                    audioPlayer = try AVAudioPlayer(contentsOf: localURL)
                    audioPlayer?.play()
                    currentlyPlayingFile = file
                } catch {
                    print("Failed to download or play audio: \(error.localizedDescription)")
                }
            }
            downloadingFile = nil
        }
    }
    
    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlayingFile = nil
    }
    
    private func deleteAudioFile(_ file: AudioFile) async {
        // Remove local file if exists
        let localURL = localDirectory.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.removeItem(at: localURL)
        }
        await fileManager.deleteAudioFile(file)
    }
}
