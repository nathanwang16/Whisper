//
//  FileBartender.swift
//  Walkie_Talkie
//
//  Created by Nathan Wang on 4/24/25.
//

import Foundation
import FirebaseStorage
import Speech

class AudioFileManager: ObservableObject {
    static let shared = AudioFileManager()
    @Published var audioFiles: [AudioFile] = [] // AudioFile is a struct with name, downloadURL, and timestamp
    private let storage = Storage.storage()
    private let storageRef: StorageReference
    private let translateRef: StorageReference
    
    private init() {
        self.storageRef = storage.reference().child("audio")
        self.translateRef = storage.reference().child("translate")
    }
    
    // MARK: - List Files
    @MainActor
    func fetchAudioFiles() async {
        do {
            let result = try await storageRef.listAll()
            var files: [AudioFile] = []
            for item in result.items {
                let metadata = try? await item.getMetadata()
                let timestamp = metadata?.timeCreated ?? Date.distantPast
                let customName = metadata?.customMetadata?["customName"]
                files.append(AudioFile(name: item.name, customName: customName, downloadURL: nil, timestamp: timestamp))
            }
            self.audioFiles = files.sorted { $0.timestamp > $1.timestamp }
        } catch {
            print("Failed to list audio files: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Upload File (with optional customName)
    @MainActor
    func uploadAudioFile(_ fileURL: URL, customName: String? = nil) async {
        let fileName = fileURL.lastPathComponent
        let fileRef = storageRef.child(fileName)
        var metadata = StorageMetadata()
        if let customName = customName {
            metadata.customMetadata = ["customName": customName]
        }
        do {
            _ = try await fileRef.putFileAsync(from: fileURL, metadata: metadata)
            await fetchAudioFiles()
        } catch {
            print("Failed to upload audio file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delete File
    @MainActor
    func deleteAudioFile(_ file: AudioFile) async {
        let fileRef = storageRef.child(file.name)
        do {
            try await fileRef.delete()
            await fetchAudioFiles()
        } catch {
            print("Failed to delete audio file: \(error.localizedDescription)")
        }
    }

    // MARK: - Download File
    func downloadAudioFile(_ file: AudioFile) async -> URL? {
        let fileRef = storageRef.child(file.name)
        do {
            let url = try await fileRef.downloadURL()
            return url
        } catch {
            print("Failed to get download URL: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Rename File (update customName in metadata)
    @MainActor
    func renameAudioFile(_ file: AudioFile, to newCustomName: String) async -> Bool {
        let fileRef = storageRef.child(file.name)
        do {
            let metadata = StorageMetadata()
            metadata.customMetadata = ["customName": newCustomName]
            _ = try await fileRef.updateMetadata(metadata)
            await fetchAudioFiles()
            return true
        } catch {
            print("Failed to rename audio file: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Transcription
    func transcriptionFileName(for audioFile: AudioFile) -> String {
        let base = (audioFile.name as NSString).deletingPathExtension
        return base + ".txt"
    }
    
    func checkTranscriptionExists(for audioFile: AudioFile) async -> Bool {
        let fileName = transcriptionFileName(for: audioFile)
        let fileRef = translateRef.child(fileName)
        do {
            _ = try await fileRef.getMetadata()
            return true
        } catch {
            return false
        }
    }
    
    func fetchTranscription(for audioFile: AudioFile) async -> String? {
        let fileName = transcriptionFileName(for: audioFile)
        let fileRef = translateRef.child(fileName)
        do {
            let url = try await fileRef.downloadURL()
            let data = try Data(contentsOf: url)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Failed to fetch transcription: \(error.localizedDescription)")
            return nil
        }
    }
    
    func uploadTranscription(for audioFile: AudioFile, text: String) async {
        let fileName = transcriptionFileName(for: audioFile)
        let fileRef = translateRef.child(fileName)
        guard let data = text.data(using: .utf8) else { return }
        do {
            _ = try await fileRef.putDataAsync(data)
        } catch {
            print("Failed to upload transcription: \(error.localizedDescription)")
        }
    }
    
    func transcribeAudioFile(_ audioFile: AudioFile, localURL: URL, locale: Locale = Locale(identifier: "en-US")) async -> String? {
        let recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer = recognizer, recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: localURL)
        return await withCheckedContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error = error {
                    print("Transcription error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct AudioFile: Identifiable, Hashable {
    let id = UUID()
    let name: String // unique file name (e.g., UUID or timestamp)
    var customName: String? // user-customized name
    var downloadURL: URL?
    let timestamp: Date
}

