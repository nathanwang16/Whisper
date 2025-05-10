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
    @State private var currentlyPlayingFile: AppAudioFile?
    @State private var isLoading: Bool = false
    @State private var downloadingFile: AppAudioFile? = nil
    @State private var renamingFile: AppAudioFile? = nil
    @State private var newCustomName: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameError: String? = nil
    @State private var transcriptSnippets: [String: String] = [:] // [audioFile.name: first2chars]
    @State private var transcribingFile: AppAudioFile? = nil
    
    private let localDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    var body: some View {
        NavigationView {
            List {
				ForEach(fileManager.audioFiles, id: \.self) { file in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(file.customName?.isEmpty == false ? file.customName! : file.name)
                            .foregroundColor(currentlyPlayingFile == file ? .blue : .primary)
                                if let snippet = transcriptSnippets[file.name] {
                                    Text("[\(snippet)]")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if let error = renameError, renamingFile == file {
                                Text(error).foregroundColor(.red).font(.caption)
                            }
                        }
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
                        Button(action: {
                            Task { await handleAudioPlayback(for: file) }
                        }) {
                            Image(systemName: "play.circle.fill")
                                .resizable()
                                .frame(width: 28, height: 28)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        if transcriptSnippets[file.name] == nil {
                            if transcribingFile == file {
                                ProgressView().frame(width: 28, height: 28)
                            } else {
                                Button("Transcribe") {
                                    Task { await handleTranscribe(for: file) }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        renamingFile = file
                        newCustomName = file.customName ?? ""
                        showRenameAlert = true
                        renameError = nil
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
                Task {
                    await fileManager.fetchAudioFiles()
                    await fetchAllTranscriptSnippets()
                }
            }
            .alert("Rename Audio File", isPresented: $showRenameAlert, actions: {
                TextField("New name", text: $newCustomName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    Task { await handleRename() }
            }
            }, message: {
                if let error = renameError {
                    Text(error)
                }
            })
        }
    }
    
    private func isFileDownloaded(_ file: AppAudioFile) -> Bool {
        let localURL = localDirectory.appendingPathComponent(file.name)
        return FileManager.default.fileExists(atPath: localURL.path)
    }
    
    private func handleAudioPlayback(for file: AppAudioFile) async {
        if currentlyPlayingFile == file {
            stopAudio()
        } else {
            await playAudio(file: file)
        }
    }
    
    private func playAudio(file: AppAudioFile) async {
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
    
    private func deleteAudioFile(_ file: AppAudioFile) async {
        // Remove local file if exists
        let localURL = localDirectory.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.removeItem(at: localURL)
        }
        await fileManager.deleteAudioFile(file)
    }
    
    private func handleRename() async {
        guard let file = renamingFile else { return }
        let trimmed = newCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            renameError = "Name cannot be empty."
            showRenameAlert = true
            return
        }
        if fileManager.audioFiles.contains(where: { ($0.customName?.lowercased() ?? "") == trimmed.lowercased() && $0.name != file.name }) {
            renameError = "Name already exists."
            showRenameAlert = true
            return
        }
        let success = await fileManager.renameAudioFile(file, to: trimmed)
        if !success {
            renameError = "Failed to rename."
            showRenameAlert = true
        } else {
            renameError = nil
            showRenameAlert = false
        }
    }
    
    private func fetchAllTranscriptSnippets() async {
        for file in fileManager.audioFiles {
            if let text = await fileManager.fetchTranscription(for: file), !text.isEmpty {
                let snippet = String(text.prefix(2))
                transcriptSnippets[file.name] = snippet
            }
        }
    }
    
    private func handleTranscribe(for file: AppAudioFile) async {
        transcribingFile = file
        // Download audio file if not local
        let localURL = localDirectory.appendingPathComponent(file.name)
        if !FileManager.default.fileExists(atPath: localURL.path) {
            if let remoteURL = await fileManager.downloadAudioFile(file) {
                do {
                    let data = try Data(contentsOf: remoteURL)
                    try data.write(to: localURL)
                } catch {
                    print("Failed to download audio for transcription: \(error.localizedDescription)")
                    transcribingFile = nil
                    return
                }
            } else {
                transcribingFile = nil
                return
            }
        }
        // Transcribe
        if let transcript = await fileManager.transcribeAudioFile(file, localURL: localURL), !transcript.isEmpty {
            await fileManager.uploadTranscription(for: file, text: transcript)
            transcriptSnippets[file.name] = String(transcript.prefix(2))
        }
        transcribingFile = nil
    }
}
