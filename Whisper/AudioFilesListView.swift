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
import CoreData

struct AudioFilesListView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        entity: AudioFile.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AudioFile.timestamp, ascending: false)]
    ) private var coreDataFiles: FetchedResults<AudioFile>
    @ObservedObject private var fileManager = AudioFileManager.shared
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentlyPlayingFile: AudioFile?
    @State private var isLoading: Bool = false
    @State private var downloadingFile: AudioFile? = nil
    @State private var renamingFile: AudioFile? = nil
    @State private var newCustomName: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameError: String? = nil
    @State private var transcriptSnippets: [String: String] = [:] // [audioFile.name: first2chars]
    @State private var transcribingFile: AudioFile? = nil
    
    private let localDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(coreDataFiles, id: \.self) { file in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text((file.customName?.isEmpty == false ? file.customName! : file.fileName ?? ""))
                            .foregroundColor(currentlyPlayingFile == file ? .blue : .primary)
                                if let snippet = transcriptSnippets[file.fileName ?? ""] {
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
                        if transcriptSnippets[file.fileName ?? ""] == nil {
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
                    await fileManager.syncFromFirebaseToCoreData()
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
    
    private func isFileDownloaded(_ file: AudioFile) -> Bool {
        let localURL = localDirectory.appendingPathComponent(file.fileName ?? "")
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
        let localURL = localDirectory.appendingPathComponent(file.fileName ?? "")
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
            if let remoteURL = await fileManager.downloadAudioFileFromFirebase(file: file) {
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
        let localURL = localDirectory.appendingPathComponent(file.fileName ?? "")
        if FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.removeItem(at: localURL)
        }
        await fileManager.deleteAudioFileAndSync(file)
    }
    
    private func handleRename() async {
        guard let file = renamingFile else { return }
        let trimmed = newCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            renameError = "Name cannot be empty."
            showRenameAlert = true
            return
        }
        if coreDataFiles.contains(where: { ($0.customName?.lowercased() ?? "") == trimmed.lowercased() && $0.fileName != file.fileName }) {
            renameError = "Name already exists."
            showRenameAlert = true
            return
        }
        let success = await fileManager.renameAudioFileAndSync(file, to: trimmed)
        if !success {
            renameError = "Failed to rename."
            showRenameAlert = true
        } else {
            renameError = nil
            showRenameAlert = false
        }
    }
    
    private func fetchAllTranscriptSnippets() async {
        for file in coreDataFiles {
            if let text = await fileManager.fetchTranscriptFromCoreData(fileName: file.fileName ?? ""), !text.isEmpty {
                let snippet = String(text.prefix(2))
                transcriptSnippets[file.fileName ?? ""] = snippet
            }
        }
    }
    
    private func handleTranscribe(for file: AudioFile) async {
        transcribingFile = file
        // Download audio file if not local
        let localURL = localDirectory.appendingPathComponent(file.fileName ?? "")
        if !FileManager.default.fileExists(atPath: localURL.path) {
            if let remoteURL = await fileManager.downloadAudioFileFromFirebase(file: file) {
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
        if let transcript = await fileManager.transcribeAudioFileFromCoreData(file, localURL: localURL), !transcript.isEmpty {
            await fileManager.uploadTranscriptionAndSync(file, text: transcript)
            transcriptSnippets[file.fileName ?? ""] = String(transcript.prefix(2))
        }
        transcribingFile = nil
    }
}
